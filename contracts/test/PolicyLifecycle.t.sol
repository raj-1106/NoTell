// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {InsurancePool}  from "../src/InsurancePool.sol";
import {IPeridotComptroller} from "../src/interfaces/IPeridotComptroller.sol";

/// @title PolicyLifecycle
/// @notice Main-case tests: buy → hold → expire.
///         Tests the happy path and all access-control / state-machine invariants.
contract PolicyLifecycleTest is Test {
    PolicyRegistry internal registry;
    InsurancePool  internal pool;

    address internal mockComptroller = makeAddr("mockComptroller");
    address internal alice           = makeAddr("alice");

    uint256 constant NOTIONAL       = 10 ether;
    uint256 constant DURATION       = 1_000;        // blocks
    uint256 constant PREMIUM        = NOTIONAL / 100; // 1%

    function setUp() public {
        // Deploy in order: registry (no pool yet) → pool (pointing at registry) → wire.
        registry = new PolicyRegistry(mockComptroller);
        pool     = new InsurancePool(address(registry));
        registry.setInsurancePool(address(pool));

        // Seed pool with 100 ETH LP liquidity.
        vm.deal(address(this), 100 ether);
        pool.deposit{value: 100 ether}();

        // Fund alice.
        vm.deal(alice, 10 ether);

        // Mock a healthy position (shortfall == 0) for any caller.
        _mockComptrollerHealthy();
    }

    // ─── Happy path ────────────────────────────────────────────────────────

    function test_BuyPolicyEmitsIssued() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit PolicyRegistry.PolicyIssued(0, alice, NOTIONAL, block.number + DURATION);
        registry.buyPolicy{value: PREMIUM}(NOTIONAL, DURATION);
    }

    function test_PolicyIsActiveAfterPurchase() public {
        vm.prank(alice);
        uint256 id = registry.buyPolicy{value: PREMIUM}(NOTIONAL, DURATION);
        (,,,,,PolicyRegistry.PolicyState state) = registry.policies(id);
        assertEq(uint256(state), uint256(PolicyRegistry.PolicyState.Active));
    }

    function test_ExpirePolicyAtEndBlock() public {
        vm.prank(alice);
        uint256 id = registry.buyPolicy{value: PREMIUM}(NOTIONAL, DURATION);

        // Roll to endBlock.
        (, , , , uint256 endBlock,) = registry.policies(id);
        vm.roll(endBlock);

        registry.expirePolicy(id);
        (,,,,,PolicyRegistry.PolicyState state) = registry.policies(id);
        assertEq(uint256(state), uint256(PolicyRegistry.PolicyState.Expired));
    }

    // ─── Failure cases ─────────────────────────────────────────────────────

    function test_ExpireRevertsBeforeEndBlock() public {
        vm.prank(alice);
        uint256 id = registry.buyPolicy{value: PREMIUM}(NOTIONAL, DURATION);

        vm.expectRevert(
            abi.encodeWithSelector(PolicyRegistry.PolicyNotExpired.selector, id, block.number + DURATION)
        );
        registry.expirePolicy(id);
    }

    function test_ReExpireRevertsOnAlreadyExpired() public {
        vm.prank(alice);
        uint256 id = registry.buyPolicy{value: PREMIUM}(NOTIONAL, DURATION);
        (, , , , uint256 endBlock,) = registry.policies(id);
        vm.roll(endBlock);
        registry.expirePolicy(id);

        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.PolicyNotActive.selector, id));
        registry.expirePolicy(id);
    }

    function test_MarkClaimedRevertsForNonPool() public {
        vm.prank(alice);
        uint256 id = registry.buyPolicy{value: PREMIUM}(NOTIONAL, DURATION);

        vm.expectRevert(PolicyRegistry.NotInsurancePool.selector);
        vm.prank(alice);
        registry.markClaimed(id, 1 ether);
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
