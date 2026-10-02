// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {InsurancePool}  from "../src/InsurancePool.sol";
import {IPeridotComptroller} from "../src/interfaces/IPeridotComptroller.sol";

/// @title SelfInflictedCap
/// @notice Q4 tests: holding period + payout cap enforcement.
///
/// Q4 values (see implementation_plan.md for derivation):
///   K_PAYOUT_MULTIPLE = 10   → max payout = 10 × premiumPaid = 10% of notional at 1% premium.
///     Anchored to 5–15% real liquidation penalty range (Aave/Morpho mid-point).
///   HOLDING_PERIOD = 288_000 blocks ≈ 24h at 300ms/block.
///     Verify against testnet RPC before deploying.
///
/// Test strategy: fast-forward with vm.roll() rather than vm.warp() (block-based policy).
contract SelfInflictedCapTest is Test {
    PolicyRegistry internal registry;
    InsurancePool  internal pool;

    address internal mockComptroller = makeAddr("mockComptroller");
    address internal alice            = makeAddr("alice");

    uint256 constant NOTIONAL       = 10 ether;
    uint256 constant DURATION       = 400_000;    // longer than HOLDING_PERIOD
    uint256 constant PREMIUM        = NOTIONAL / 100; // 1% = 0.1 ETH

    // Q4 constants — must match InsurancePool.
    uint256 constant K              = 10;
    uint256 constant HOLDING_PERIOD = 288_000;
    uint256 constant MAX_PAYOUT     = K * PREMIUM; // 1 ETH at these numbers

    // Dummy proof args (ignored in Phase 1 plaintext path).
    uint256[2]    internal _a;
    uint256[2][2] internal _b;
    uint256[2]    internal _c;
    uint256[2]    internal _pub;

    uint256 internal policyId;

    function setUp() public {
        registry = new PolicyRegistry(mockComptroller);
        pool     = new InsurancePool(address(registry));
        registry.setInsurancePool(address(pool));

        // Seed pool with 100 ETH.
        vm.deal(address(this), 100 ether);
        pool.deposit{value: 100 ether}();

        // Fund alice and buy a policy.
        vm.deal(alice, 10 ether);
        _mockComptrollerHealthy();
        vm.prank(alice);
        policyId = registry.buyPolicy{value: PREMIUM}(NOTIONAL, DURATION);
    }

    // ─── Holding period ────────────────────────────────────────────────────

    /// Claim before HOLDING_PERIOD blocks have elapsed → revert.
    function test_ClaimRevertsBeforeHoldingPeriod() public {
        (, , , uint256 startBlock, ,) = registry.policies(policyId);
        vm.roll(startBlock + HOLDING_PERIOD - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                InsurancePool.HoldingPeriodNotElapsed.selector,
                policyId,
                startBlock + HOLDING_PERIOD
            )
        );
        vm.prank(alice);
        pool.processClaim(policyId, _a, _b, _c, _pub);
    }

    /// Claim at exactly HOLDING_PERIOD blocks → succeeds (inclusive boundary).
    function test_ClaimSucceedsAtExactHoldingPeriod() public {
        (, , , uint256 startBlock, ,) = registry.policies(policyId);
        vm.roll(startBlock + HOLDING_PERIOD);

        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        pool.processClaim(policyId, _a, _b, _c, _pub);

        // Payout should be MAX_PAYOUT (notional > max, so cap applies).
        assertEq(alice.balance - balanceBefore, MAX_PAYOUT);
    }

    // ─── Payout cap ────────────────────────────────────────────────────────

    /// Claim where notional > K × premium → truncated to cap, not reverted.
    function test_PayoutTruncatedToCapNotReverted() public {
        (, , , uint256 startBlock, ,) = registry.policies(policyId);
        vm.roll(startBlock + HOLDING_PERIOD);

        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        pool.processClaim(policyId, _a, _b, _c, _pub);

        uint256 received = alice.balance - balanceBefore;
        assertEq(received, MAX_PAYOUT, "Should be capped at K * premium");
        assertLt(received, NOTIONAL,   "Should be less than full notional");
    }

    /// Cap tracks actual premium paid, not an assumed 1%-of-notional.
    /// Buy at different notional but same premium rate, verify cap adjusts.
    function test_CapTracksActualPremiumPaid() public {
        uint256 smallNotional = 5 ether;
        uint256 smallPremium  = smallNotional / 100; // 0.05 ETH
        uint256 expectedCap   = K * smallPremium;    // 0.5 ETH

        address bob = makeAddr("bob");
        vm.deal(bob, 5 ether);
        _mockComptrollerHealthy();
        vm.prank(bob);
        uint256 bobPolicyId = registry.buyPolicy{value: smallPremium}(smallNotional, DURATION);

        (, , , uint256 startBlock, ,) = registry.policies(bobPolicyId);
        vm.roll(startBlock + HOLDING_PERIOD);

        uint256 balanceBefore = bob.balance;
        vm.prank(bob);
        pool.processClaim(bobPolicyId, _a, _b, _c, _pub);

        assertEq(bob.balance - balanceBefore, expectedCap);
    }

    // ─── Internal helpers ─────────────────────────────────────────────────

    /// Mock a healthy position: no shortfall, some liquidity.
    function _mockComptrollerHealthy() internal {
        vm.mockCall(
            mockComptroller,
            abi.encodeWithSelector(IPeridotComptroller.getAccountLiquidity.selector),
            abi.encode(uint256(0), uint256(1 ether), uint256(0))
        );
    }
}
