// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPeridotComptroller} from "./interfaces/IPeridotComptroller.sol";
import {IPoseidon}           from "./interfaces/IPoseidon.sol";

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
/// Phase 2a extends this contract with checkHealthFactors() and the commitments
/// mapping, both declared here so the storage layout is stable.

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

    /// @notice Peridot Comptroller — used to check position health at purchase
    ///         and by checkHealthFactors() in Phase 2a.
    IPeridotComptroller public immutable comptroller;

    /// @notice Deployer address. Only this address may call setInsurancePool().
    ///         This is a deploy-time trust assumption: whoever deploys the registry
    ///         controls where premiums and claims flow until setInsurancePool() is called.
    ///         That window is one transaction wide (deploy → setInsurancePool in Deploy.s.sol),
    ///         but it is a real trust assumption and is named here rather than left implicit.
    ///         See ATTACK_SURFACE.md.
    address public immutable deployer;

    /// @notice The InsurancePool contract — the only address allowed to call markClaimed.
    ///         Set once via setInsurancePool() after both contracts are deployed.
    address public insurancePool;

    mapping(uint256 => Policy) public policies;
    uint256 public nextPolicyId;

    /// @notice Tracks consecutive CRE polls where shortfall > 0. Capped at 2 to prevent overflow.
    mapping(uint256 => uint16) public consecutiveShortfalls;

    /// @notice Authorized CRE caller address
    address public creAddress;

    /// @notice Deployed PoseidonT4 contract for computing commitments
    IPoseidon public poseidon;

    /// @notice CRE-posted position commitments. Written by checkHealthFactors (Phase 2a).
    ///         commitments[policyId][blockNumber] = Poseidon(liquidity, shortfall, blockNumber)
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
    /// @notice Emitted by checkHealthFactors (Phase 2a) when shortfall > 0 for a covered position.
    event ClaimWindowOpened(uint256 indexed policyId);

    // ─── Errors ─────────────────────────────────────────────────────────────

    /// @notice Purchase rejected: position already has shortfall (Q1 exclusion).
    error PositionAlreadyLiquidatable(uint256 policyId);
    /// @notice Comptroller returned a non-zero error code.
    error ComptrollerError(uint256 errorCode);
    error PolicyNotActive(uint256 policyId);
    error PolicyNotExpired(uint256 policyId, uint256 endBlock);
    error NotInsurancePool();
    error ZeroDurationBlocks();
    error ZeroNotional();
    error PoolAlreadySet();
    error ZeroAddress();
    error NotDeployer();
    error NotAuthorizedCRE();

    modifier onlyCRE() {
        if (msg.sender != creAddress) revert NotAuthorizedCRE();
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address _comptroller) {
        comptroller = IPeridotComptroller(_comptroller);
        deployer    = msg.sender;
    }

    /// @notice Set the InsurancePool address once after both contracts are deployed.
    ///         One-time initializer — cannot be changed after it is set.
    ///         Restricted to the deployer address captured at construction time.
    ///         The deploy-time trust window (between deploy and this call) is documented
    ///         in ATTACK_SURFACE.md as a known, named assumption.
    function setInsurancePool(address _insurancePool) external {
        if (msg.sender != deployer)       revert NotDeployer();
        if (insurancePool != address(0))  revert PoolAlreadySet();
        if (_insurancePool == address(0)) revert ZeroAddress();
        insurancePool = _insurancePool;
    }

    /// @notice One-time setter for the CRE monitoring workflow caller address.
    function setCREAddress(address _cre) external {
        if (msg.sender != deployer) revert NotDeployer();
        if (creAddress != address(0)) revert PoolAlreadySet(); // reuse error for simplicity
        if (_cre == address(0)) revert ZeroAddress();
        creAddress = _cre;
    }

    /// @notice One-time setter for the Poseidon contract address.
    function setPoseidon(address _poseidon) external {
        if (msg.sender != deployer) revert NotDeployer();
        if (address(poseidon) != address(0)) revert PoolAlreadySet();
        if (_poseidon == address(0)) revert ZeroAddress();
        poseidon = IPoseidon(_poseidon);
    }

    // ─── External functions ───────────────────────────────────────────────────

    /// @notice Purchase a policy for msg.sender.
    /// @param notional       Covered amount in wei.
    /// @param durationBlocks Number of blocks the policy is active for.
    /// @return policyId      The newly issued policy ID.
    ///
    /// Q1 exclusion: reverts if msg.sender's Peridot position currently has shortfall > 0
    /// (i.e. is already liquidatable). No ratio gradient — binary check only.
    /// Rationale: Compound-style liquidity values are absolute USD amounts, not scale-invariant
    /// ratios. Any normalisation against `notional` (buyer-chosen) would be gameable.
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

        // Forward premium to InsurancePool via collectPremium.
        // Pool address must be set via setInsurancePool() before any policy is purchased.
        require(insurancePool != address(0), "Pool not configured");
        (bool ok,) = insurancePool.call{value: premium}(
            abi.encodeWithSignature("collectPremium(uint256)", policyId)
        );
        require(ok, "Premium transfer failed");
    }

    /// @notice Transition an expired policy to the Expired state.
    ///         Callable by anyone — no access restriction needed.
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

    // ─── Phase 2a stub ────────────────────────────────────────────────────────
    // checkHealthFactors() is implemented in Phase 2 when CRE is wired up.
    // Declared here as a no-op so the ABI is stable and tests can call it.

    /// @notice Called by the CRE monitoring workflow. Posts a position commitment
    ///         for each policy and emits ClaimWindowOpened for threshold crossers.
    function checkHealthFactors(uint256[] calldata policyIds) external onlyCRE {
        for (uint i = 0; i < policyIds.length; i++) {
            address holder = policies[policyIds[i]].holder;
            
            (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(holder);
            if (err != 0) continue; // Skip on comptroller error
            
            if (shortfall > 0) {
                // Cap increment to prevent overflow on positions that stay underwater for days
                if (consecutiveShortfalls[policyIds[i]] < 2) {
                    consecutiveShortfalls[policyIds[i]]++;
                }
                
                // Persistence check: only commit if shortfall observed across 2 consecutive polls (5 mins)
                if (consecutiveShortfalls[policyIds[i]] >= 2) {
                    uint256[3] memory inputs = [liquidity, shortfall, block.number];
                    uint256 commitment = poseidon.poseidon(inputs);
                    commitments[policyIds[i]][block.number] = commitment;
                    emit ClaimWindowOpened(policyIds[i]);
                }
            } else {
                // Reset counter if position heals or is collateralized
                consecutiveShortfalls[policyIds[i]] = 0;
            }
        }
    }

}
// No _currentRatio() helper — Phase 2 removed the ratio-based check.
// getAccountLiquidity is called inline in buyPolicy and checkHealthFactors.
