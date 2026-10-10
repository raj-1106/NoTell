// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPeridotComptroller} from "./interfaces/IPeridotComptroller.sol";

/// @title PolicyRegistry
/// @notice Issues and tracks NoTell liquidation-insurance policies.
///
/// Design decisions encoded here (see implementation_plan.md for full reasoning):
///   Q1 — Binary exclusion zone: purchase reverts if the position's Peridot
///          shortfall > 0 at buy time (i.e. already liquidatable). No ratio gradient.
///          Rationale: Compound-style comptrollers expose (liquidity, shortfall) in
///          absolute USD, not a scale-invariant ratio. Normalising against `notional`
///          (buyer-chosen) would be gameable. The honest boundary is binary: either
///          the position is healthy (shortfall == 0) or it isn't.
///   Q2 — Flat premium: PREMIUM_BPS basis points of notional, same for all positions
///          that pass Q1. No risk-differentiation by proximity to liquidation.
///          Known limitation: documented in ATTACK_SURFACE.md.
///   Q3 — Block-based expiry: endBlock = block.number + durationBlocks.
///   Q4 — Self-inflicted cap enforced in InsurancePool.processClaim, not here.
///
/// Phase 2a: postCommitment() lets the keeper post Poseidon commitments computed
/// off-chain, emitting liquidity and shortfall in ClaimWindowOpened so the
/// frontend can reconstruct ZK inputs without archive eth_call queries.

contract PolicyRegistry {
    // ─── Types ─────────────────────────────────────────────────────────────

    enum PolicyState { Active, Expired, Claimed }

    struct Policy {
        address holder;
        uint256 notional;
        uint256 premiumPaid;
        uint256 startBlock;
        uint256 endBlock;
        PolicyState state;
    }

    // ─── Constants ─────────────────────────────────────────────────────────

    /// @notice Basis points of notional charged as premium (Q2: 1% = 100 bps).
    uint256 public constant PREMIUM_BPS = 100;

    // ─── State ─────────────────────────────────────────────────────────────

    /// @notice Peridot Comptroller — used to check position health at purchase.
    IPeridotComptroller public immutable comptroller;

    /// @notice Deployer address. Only this address may call setInsurancePool().
    address public immutable deployer;

    /// @notice The InsurancePool contract — the only address allowed to call markClaimed.
    ///         Set once via setInsurancePool() after both contracts are deployed.
    address public insurancePool;

    mapping(uint256 => Policy) public policies;
    uint256 public nextPolicyId;

    /// @notice Keeper-posted position commitments.
    ///         commitments[policyId][roundId] = Poseidon(liquidity, shortfall, roundId)
    ///         Declared here so ClaimVerifier can read it via the public getter.
    mapping(uint256 => mapping(uint256 => uint256)) public commitments;

    // ─── Events ─────────────────────────────────────────────────────────────

    event PolicyIssued(
        uint256 indexed policyId,
        address indexed holder,
        uint256 notional,
        uint256 endBlock
    );
    event PolicyExpired(uint256 indexed policyId);
    event PolicyClaimed(uint256 indexed policyId, uint256 amountPaid);
    /// @notice Emitted by postCommitment() when the keeper detects a shortfall.
    /// @dev    liquidity and shortfall are included so the frontend can reconstruct
    ///         ZK circuit inputs without needing archive eth_call queries.
    event ClaimWindowOpened(
        uint256 indexed policyId,
        uint256          roundId,
        uint256          liquidity,
        uint256          shortfall
    );

    // ─── Errors ─────────────────────────────────────────────────────────────

    error PositionAlreadyLiquidatable(uint256 policyId);
    error ComptrollerError(uint256 errorCode);
    error PolicyNotActive(uint256 policyId);
    error PolicyNotExpired(uint256 policyId, uint256 endBlock);
    error NotInsurancePool();
    error ZeroDurationBlocks();
    error ZeroNotional();
    error PoolAlreadySet();
    error ZeroAddress();
    error NotDeployer();

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address _comptroller) {
        comptroller = IPeridotComptroller(_comptroller);
        deployer    = msg.sender;
    }

    /// @notice Set the InsurancePool address once after both contracts are deployed.
    function setInsurancePool(address _insurancePool) external {
        if (msg.sender != deployer)       revert NotDeployer();
        if (insurancePool != address(0))  revert PoolAlreadySet();
        if (_insurancePool == address(0)) revert ZeroAddress();
        insurancePool = _insurancePool;
    }

    // ─── External functions ───────────────────────────────────────────────────

    /// @notice Purchase a policy for msg.sender.
    /// @param notional       Covered amount in wei.
    /// @param durationBlocks Number of blocks the policy is active for.
    /// @return policyId      The newly issued policy ID.
    function buyPolicy(
        uint256 notional,
        uint256 durationBlocks
    ) external payable returns (uint256 policyId) {
        if (notional == 0) revert ZeroNotional();
        if (durationBlocks == 0) revert ZeroDurationBlocks();

        uint256 premium = (notional * PREMIUM_BPS) / 10_000;
        require(msg.value == premium, "Incorrect premium");

        // Q1: reject if position is already liquidatable.
        (uint256 err, , uint256 shortfall) = comptroller.getAccountLiquidity(msg.sender);
        if (err != 0) revert ComptrollerError(err);
        if (shortfall > 0) revert PositionAlreadyLiquidatable(nextPolicyId);

        policyId = nextPolicyId++;
        policies[policyId] = Policy({
            holder:      msg.sender,
            notional:    notional,
            premiumPaid: premium,
            startBlock:  block.number,
            endBlock:    block.number + durationBlocks,
            state:       PolicyState.Active
        });

        emit PolicyIssued(policyId, msg.sender, notional, block.number + durationBlocks);

        require(insurancePool != address(0), "Pool not configured");
        (bool ok,) = insurancePool.call{value: premium}(
            abi.encodeWithSignature("collectPremium(uint256)", policyId)
        );
        require(ok, "Premium transfer failed");
    }

    /// @notice Transition an expired policy to the Expired state.
    function expirePolicy(uint256 policyId) external {
        Policy storage p = policies[policyId];
        if (p.state != PolicyState.Active) revert PolicyNotActive(policyId);
        if (block.number < p.endBlock) revert PolicyNotExpired(policyId, p.endBlock);
        p.state = PolicyState.Expired;
        emit PolicyExpired(policyId);
    }

    /// @notice Mark a policy as Claimed. Only callable by InsurancePool after payout.
    function markClaimed(uint256 policyId, uint256 amountPaid) external {
        if (msg.sender != insurancePool) revert NotInsurancePool();
        Policy storage p = policies[policyId];
        if (p.state != PolicyState.Active) revert PolicyNotActive(policyId);
        p.state = PolicyState.Claimed;
        emit PolicyClaimed(policyId, amountPaid);
    }

    // ─── Phase 2a: Keeper commitment posting ──────────────────────────────────
    //
    // checkHealthFactors() is kept as an ABI-stable no-op so CREBridge can call
    // it without reverting. Real commitment posting uses postCommitment() below.

    /// @notice No-op stub kept for CREBridge ABI compatibility.
    function checkHealthFactors(uint256[] calldata /*policyIds*/) external {
        // Intentional no-op. See postCommitment().
    }

    /// @notice Called by the keeper after computing Poseidon(liquidity, shortfall, roundId)
    ///         off-chain. Stores the commitment on-chain and emits ClaimWindowOpened
    ///         with the raw inputs so Envio can index them, eliminating archive eth_call
    ///         queries in the frontend.
    /// @param policyId   The policy being monitored.
    /// @param roundId    Block number used as the round identifier.
    /// @param liquidity  getAccountLiquidity liquidity value at roundId.
    /// @param shortfall  getAccountLiquidity shortfall value at roundId.
    /// @param commitment Poseidon(liquidity, shortfall, roundId) computed off-chain.
    function postCommitment(
        uint256 policyId,
        uint256 roundId,
        uint256 liquidity,
        uint256 shortfall,
        uint256 commitment
    ) external {
        Policy storage p = policies[policyId];
        if (p.state != PolicyState.Active) revert PolicyNotActive(policyId);
        require(shortfall > 0, "No shortfall: position is healthy");

        commitments[policyId][roundId] = commitment;
        emit ClaimWindowOpened(policyId, roundId, liquidity, shortfall);
    }

}
