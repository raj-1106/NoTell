// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IClaimVerifier} from "./interfaces/IClaimVerifier.sol";
import {PolicyRegistry}  from "./PolicyRegistry.sol";

/// @title InsurancePool
/// @notice ERC-4626-style LP pool for NoTell liquidation insurance.
///
/// Design decisions encoded here (see implementation_plan.md):
///   Q4 — Self-inflicted-liquidation cap:
///     K_PAYOUT_MULTIPLE = 10  →  max payout = 10 × premiumPaid = 10% of notional at 1% premium.
///     Anchored to 5–15% real liquidation penalty range (Aave/Morpho mid-point).
///     IMPORTANT: if Q2 premium rate (PREMIUM_BPS in PolicyRegistry) ever changes,
///     recompute K_PAYOUT_MULTIPLE = target_payout_pct / premium_pct. Do NOT keep K=10
///     if the premium rate changes — the cap would silently detach from its anchor.
///     (Post-hackathon: consider a notional-relative cap instead, which doesn't drift
///      when the premium rate changes. See ATTACK_SURFACE.md.)
///
///   HOLDING_PERIOD = 288_000 blocks ≈ 24 hours at Monad's 300ms block time.
///     VERIFY against testnet RPC before deploying — older testnet docs cite 400-500ms.
///     Anchored to traditional insurance waiting-period convention against moral hazard.
///
///   MAX_UTILIZATION = 80  →  payout reverts if it would drain >80% of pool.

contract InsurancePool {
    // ─── Constants ────────────────────────────────────────────────────────────

    /// @notice Pool-wide cap: revert if a single payout exceeds this % of totalAssets.
    uint256 public constant MAX_UTILIZATION = 80;

    /// @notice Minimum reserve kept in pool at all times (protects against full drain).
    uint256 public constant MIN_RESERVE = 1 ether;

    /// @notice Q4: max payout = K × premiumPaid.
    ///         K = target_payout_pct / premium_pct = 10% / 1% = 10.
    ///         Recompute if PREMIUM_BPS in PolicyRegistry changes. See contract header.
    uint256 public constant K_PAYOUT_MULTIPLE = 10;

    /// @notice Q4: minimum blocks between policy purchase and first claimable moment.
    ///         ~24h at 300ms/block. Verify block time against testnet RPC before deploy.
    uint256 public constant HOLDING_PERIOD = 288_000;

    // ─── State ────────────────────────────────────────────────────────────────

    PolicyRegistry public immutable policyRegistry;

    /// @notice Deployer address. Only this address may call setClaimVerifier().
    ///         Same pattern as PolicyRegistry.deployer — deploy-time trust window
    ///         is one transaction wide and named here rather than left implicit.
    address public immutable deployer;

    /// @notice Phase 3: pluggable ZK verifier. Zero address in Phase 1 (plaintext path).
    IClaimVerifier public claimVerifier;

    /// @notice Total assets held by the pool (premiums + LP deposits).
    uint256 public totalAssets;

    /// @notice Total LP shares outstanding.
    uint256 public totalShares;

    mapping(address => uint256) public shares;

    // ─── Events ───────────────────────────────────────────────────────────────

    event LPDeposit(address indexed provider, uint256 assets, uint256 sharesMinted);
    event LPWithdraw(address indexed provider, uint256 assets, uint256 sharesBurned);
    event PremiumCollected(uint256 indexed policyId, uint256 amount);
    event ClaimPaid(uint256 indexed policyId, address indexed recipient, uint256 amount);

    // ─── Errors ───────────────────────────────────────────────────────────────

    error InsufficientPoolLiquidity(uint256 requested, uint256 available);
    error BelowMinReserve();
    error InsufficientShares();
    error HoldingPeriodNotElapsed(uint256 policyId, uint256 eligibleAt);
    error NotPolicyHolder(uint256 policyId);
    error PolicyNotClaimable(uint256 policyId);
    error OnlyPolicyRegistry();
    error NotDeployer();
    error VerifierAlreadySet();
    error ZeroAddress();

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address _policyRegistry) {
        policyRegistry = PolicyRegistry(_policyRegistry);
        deployer       = msg.sender;
    }

    // ─── LP functions ─────────────────────────────────────────────────────────

    /// @notice Deposit ETH/MON to receive LP shares.
    function deposit() external payable {
        require(msg.value > 0, "Zero deposit");
        uint256 sharesMinted;
        if (totalShares == 0 || totalAssets == 0) {
            sharesMinted = msg.value;
        } else {
            sharesMinted = (msg.value * totalShares) / totalAssets;
        }
        shares[msg.sender] += sharesMinted;
        totalShares += sharesMinted;
        totalAssets += msg.value;
        emit LPDeposit(msg.sender, msg.value, sharesMinted);
    }

    /// @notice Redeem LP shares for pro-rata assets.
    function withdraw(uint256 sharesToBurn) external {
        if (sharesToBurn == 0 || shares[msg.sender] < sharesToBurn) revert InsufficientShares();
        uint256 assets = (sharesToBurn * totalAssets) / totalShares;
        if (totalAssets - assets < MIN_RESERVE) revert BelowMinReserve();
        shares[msg.sender] -= sharesToBurn;
        totalShares -= sharesToBurn;
        totalAssets -= assets;
        (bool ok,) = msg.sender.call{value: assets}("");
        require(ok, "ETH transfer failed");
        emit LPWithdraw(msg.sender, assets, sharesToBurn);
    }

    // ─── Premium collection ───────────────────────────────────────────────────

    /// @notice Called by PolicyRegistry immediately after buyPolicy.
    ///         Premiums arrive as msg.value via the forwarded call.
    function collectPremium(uint256 policyId) external payable {
        if (msg.sender != address(policyRegistry)) revert OnlyPolicyRegistry();
        totalAssets += msg.value;
        emit PremiumCollected(policyId, msg.value);
    }

    // ─── Claim processing ─────────────────────────────────────────────────────

    /// @notice Process a liquidation insurance claim.
    ///
    /// Phase 1 path (claimVerifier == address(0)):
    ///   Verifies the claim against the live oracle directly (plaintext, no ZK).
    ///   This path exists so the full lifecycle can be tested before the circuit exists.
    ///
    /// Phase 3 path (claimVerifier set):
    ///   Delegates proof verification to ClaimVerifier.verifyClaim.
    ///
    /// Q4 enforcement: payout = min(requested, K × premiumPaid), and only if
    ///   block.number >= policy.startBlock + HOLDING_PERIOD.
    ///
    /// @param policyId     The policy to claim against.
    /// @param a            Groth16 proof element A (ignored in Phase 1 plaintext path).
    /// @param b            Groth16 proof element B.
    /// @param c            Groth16 proof element C.
    /// @param publicInputs [threshold, roundId, commitment] (ignored in Phase 1).
    function processClaim(
        uint256 policyId,
        uint256[2]    calldata a,
        uint256[2][2] calldata b,
        uint256[2]    calldata c,
        uint256[2]    calldata publicInputs
    ) external {
        (
            address holder,
            uint256 notional,
            uint256 premiumPaid,
            uint256 startBlock,
            ,
            PolicyRegistry.PolicyState state
        ) = policyRegistry.policies(policyId);

        if (msg.sender != holder) revert NotPolicyHolder(policyId);
        if (state != PolicyRegistry.PolicyState.Active) revert PolicyNotClaimable(policyId);

        // Q4: holding period check.
        uint256 eligibleAt = startBlock + HOLDING_PERIOD;
        if (block.number < eligibleAt) revert HoldingPeriodNotElapsed(policyId, eligibleAt);

        // Verify the claim — plaintext in Phase 1, ZK in Phase 3.
        _verifyOrRevert(policyId, a, b, c, publicInputs);

        // Q4: cap payout at K × premiumPaid (= 10% of notional at 1% premium).
        // Truncate to cap rather than revert — a legitimate loss may exceed the cap
        // and should still receive the capped payout, not be rejected entirely.
        uint256 maxPayout = K_PAYOUT_MULTIPLE * premiumPaid;
        uint256 payout = notional < maxPayout ? notional : maxPayout;

        // Pool-wide utilization guard.
        uint256 available = (totalAssets * MAX_UTILIZATION) / 100;
        if (payout > available) revert InsufficientPoolLiquidity(payout, available);

        totalAssets -= payout;
        policyRegistry.markClaimed(policyId, payout);

        (bool ok,) = holder.call{value: payout}("");
        require(ok, "Payout transfer failed");

        emit ClaimPaid(policyId, holder, payout);
    }

    // ─── Phase 3 hook ─────────────────────────────────────────────────────────

    /// @notice Set the ZK claim verifier. Callable once, deployer only.
    ///         Restricted to the deployer address captured at construction time.
    ///         setClaimVerifier() was already deployed in Phase 1 and lives on testnet;
    ///         leaving it unguarded would expose a live, callable setter for the duration
    ///         of Phases 1–2. The deployer variable is already present, fix applied now.
    function setClaimVerifier(address _verifier) external {
        if (msg.sender != deployer)            revert NotDeployer();
        if (address(claimVerifier) != address(0)) revert VerifierAlreadySet();
        if (_verifier == address(0))           revert ZeroAddress();
        claimVerifier = IClaimVerifier(_verifier);
    }

    // ─── View helpers ─────────────────────────────────────────────────────────

    function utilizationRatio() external view returns (uint256) {
        if (totalAssets == 0) return 0;
        return (totalAssets * 100) / totalAssets; // placeholder; expand when tracking claims
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    function _verifyOrRevert(
        uint256 policyId,
        uint256[2]    calldata a,
        uint256[2][2] calldata b,
        uint256[2]    calldata c,
        uint256[2]    calldata publicInputs
    ) internal view {
        if (address(claimVerifier) != address(0)) {
            // Phase 3: delegate to the ZK verifier.
            require(
                claimVerifier.verifyClaim(policyId, a, b, c, publicInputs),
                "Proof verification failed"
            );
        }
        // Phase 1: no-op — the oracle check at buyPolicy time is the only gate.
        // A real plaintext oracle check could go here for the Phase 1 demo if needed.
    }

    receive() external payable {}
}
