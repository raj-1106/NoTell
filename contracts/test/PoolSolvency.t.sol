// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {InsurancePool}  from "../src/InsurancePool.sol";
import {IPeridotComptroller} from "../src/interfaces/IPeridotComptroller.sol";

/// @title PoolSolvency
/// @notice Edge-case tests: pool utilization cap, LP accounting, reserve floor.
contract PoolSolvencyTest is Test {
    PolicyRegistry internal registry;
    InsurancePool  internal pool;

    address internal mockComptroller = makeAddr("mockComptroller");
    address internal alice           = makeAddr("alice");
    address internal lp              = makeAddr("lp");

    uint256 constant NOTIONAL       = 10 ether;
    uint256 constant DURATION       = 400_000;
    uint256 constant PREMIUM        = NOTIONAL / 100;
    uint256 constant HOLDING_PERIOD = 288_000;

    uint256[2]    internal _a;
    uint256[2][2] internal _b;
    uint256[2]    internal _c;
    uint256[2]    internal _pub;

    function setUp() public {
        registry = new PolicyRegistry(mockComptroller);
        pool     = new InsurancePool(address(registry));
        registry.setInsurancePool(address(pool));

        _mockComptrollerHealthy();

        // LP deposits 10 ETH: 80% = 8 ETH available; claim cap = 1 ETH. Ample headroom.
        // After a 1 ETH payout the pool has ~9.1 ETH — LP can withdraw partial shares
        // without hitting MIN_RESERVE = 1 ETH.
        vm.deal(lp, 10 ether);
        vm.prank(lp);
        pool.deposit{value: 10 ether}();

        vm.deal(alice, 10 ether);
    }

    // ─── Normal claim ─────────────────────────────────────────────────────

    /// Normal claim within utilization limit: payout succeeds and LP share value is updated.
    function test_NormalClaimUpdatesPoolAssets() public {
        vm.prank(alice);
        uint256 id = registry.buyPolicy{value: PREMIUM}(NOTIONAL, DURATION);
        (, , , uint256 startBlock, ,) = registry.policies(id);
        vm.roll(startBlock + HOLDING_PERIOD);

        uint256 assetsBefore = pool.totalAssets();
        vm.prank(alice);
        pool.processClaim(id, _a, _b, _c, _pub);
        uint256 assetsAfter = pool.totalAssets();

        uint256 expectedPayout = 10 * PREMIUM; // K * premium = 1 ETH
        assertEq(assetsBefore - assetsAfter, expectedPayout);
    }

    // ─── Utilization cap ─────────────────────────────────────────────────

    /// Claim that would exceed MAX_UTILIZATION (80%) of pool reverts with InsufficientPoolLiquidity.
    /// Setup: pool has 1 ETH total → 80% available = 0.8 ETH.
    /// Claim cap = K * PREMIUM = 10 * 0.1 ETH = 1 ETH > 0.8 ETH → revert.
    function test_ClaimRevertsWhenExceedsUtilization() public {
        // Deploy a tight pool (1 ETH only) wired to the same registry.
        PolicyRegistry tightRegistry = new PolicyRegistry(mockComptroller);
        InsurancePool  tightPool     = new InsurancePool(address(tightRegistry));
        tightRegistry.setInsurancePool(address(tightPool));

        vm.deal(address(this), 1 ether);
        tightPool.deposit{value: 1 ether}();
        // Total assets = 1 ETH. 80% of 1 ETH = 0.8 ETH available for payout.
        // K * PREMIUM = 10 * 0.1 ETH = 1 ETH > 0.8 ETH → should revert.

        address bob = makeAddr("utilBob");
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        uint256 id = tightRegistry.buyPolicy{value: PREMIUM}(NOTIONAL, DURATION);

        (, , , uint256 startBlock, ,) = tightRegistry.policies(id);
        vm.roll(startBlock + HOLDING_PERIOD);

        // payout = min(notional, K*premium) = min(10 ETH, 1 ETH) = 1 ETH
        // available = 80% of (1 ETH pool + 0.1 ETH premium) = 80% of 1.1 ETH = 0.88 ETH
        // 1 ETH > 0.88 ETH → InsufficientPoolLiquidity
        vm.expectRevert(
            abi.encodeWithSelector(
                InsurancePool.InsufficientPoolLiquidity.selector,
                1 ether,
                (1.1 ether * 80) / 100
            )
        );
        vm.prank(bob);
        tightPool.processClaim(id, _a, _b, _c, _pub);
    }

    // ─── LP withdraw ──────────────────────────────────────────────────────

    /// LP can withdraw a partial position after a claim (pool still respects MIN_RESERVE).
    /// Full-withdraw is blocked by MIN_RESERVE — that's tested separately.
    /// This test confirms the withdraw path itself works in a post-claim pool state.
    function test_LPWithdrawAfterClaim() public {
        vm.prank(alice);
        uint256 id = registry.buyPolicy{value: PREMIUM}(NOTIONAL, DURATION);
        (, , , uint256 startBlock, ,) = registry.policies(id);
        vm.roll(startBlock + HOLDING_PERIOD);

        vm.prank(alice);
        pool.processClaim(id, _a, _b, _c, _pub);

        // After a 1 ETH payout the pool has ~9.1 ETH (10 ETH deposit + 0.1 ETH premium - 1 ETH payout).
        // Withdrawing ALL shares would still breach MIN_RESERVE (tested in test_WithdrawRevertsOnMinReserve).
        // Withdraw half the shares — confirms the withdraw path works in a post-claim pool state.
        uint256 lpShares = pool.shares(lp);
        assertTrue(lpShares > 0);
        uint256 halfShares = lpShares / 2;
        uint256 balanceBefore = lp.balance;
        vm.prank(lp);
        pool.withdraw(halfShares);
        assertTrue(lp.balance > balanceBefore, "LP should receive assets on partial withdraw");
    }

    /// Deposit and immediate withdraw with no claims returns the same amount (no loss).
    function test_DepositWithdrawNoLoss() public {
        address bob = makeAddr("bob");
        vm.deal(bob, 5 ether);
        vm.prank(bob);
        pool.deposit{value: 5 ether}();

        uint256 bobShares = pool.shares(bob);
        uint256 balanceBefore = bob.balance;
        vm.prank(bob);
        pool.withdraw(bobShares);
        // Allow 1 wei rounding loss maximum.
        assertApproxEqAbs(bob.balance - balanceBefore, 5 ether, 1);
    }

    // ─── Reserve floor ────────────────────────────────────────────────────

    /// Withdraw that would drop pool below MIN_RESERVE reverts.
    function test_WithdrawRevertsOnMinReserve() public {
        uint256 lpShares = pool.shares(lp);
        // Try to withdraw everything — pool total is ~2.1 ETH, MIN_RESERVE = 1 ETH.
        vm.expectRevert(InsurancePool.BelowMinReserve.selector);
        vm.prank(lp);
        pool.withdraw(lpShares);
    }

    // ─── Internal helpers ─────────────────────────────────────────────────

    function _mockComptrollerHealthy() internal {
        vm.mockCall(
            mockComptroller,
            abi.encodeWithSelector(IPeridotComptroller.getAccountLiquidity.selector),
            abi.encode(uint256(0), uint256(1 ether), uint256(0))
        );
    }
}
