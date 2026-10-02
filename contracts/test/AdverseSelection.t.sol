// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {InsurancePool}  from "../src/InsurancePool.sol";
import {IPeridotComptroller} from "../src/interfaces/IPeridotComptroller.sol";

/// @title AdverseSelection
/// @notice Q1 failure-case tests: purchase-time exclusion zone.
///
/// Phase 2 design (Path 2, binary shortfall):
///   Aave is not deployed on Monad testnet. Peridot is the only testnet lending
///   protocol (DeFi::Lending in monad-crypto/protocols registry). Peridot is
///   Compound v2-style: getAccountLiquidity() returns (error, liquidity, shortfall)
///   in absolute USD, not a scale-invariant ratio.
///
///   Normalising liquidity against `notional` (buyer-chosen) would be gameable:
///   a buyer could pick a tiny notional against a large, healthy position to
///   inflate the ratio past any threshold artificially. Path 2 avoids this by
///   using the binary: shortfall == 0 means healthy, shortfall > 0 means liquidatable.
///
///   Known limitation: no risk-differentiation at purchase. Two positions, one with
///   $1 liquidity buffer and one with $100,000, are treated identically at purchase
///   and pay the same flat premium. Documented in ATTACK_SURFACE.md.
///
/// Tests:
///   - Healthy position (shortfall == 0): purchase succeeds.
///   - Liquidatable position (shortfall > 0): purchase reverts.
///   - Comptroller error (error != 0): purchase reverts.
///   - Edge: liquidity == 0 AND shortfall == 0 (dust position, exactly at boundary):
///     treated as healthy (no shortfall), purchase succeeds. This is the correct
///     behaviour — Compound marks shortfall only when the position is actually
///     undercollateralised.
contract AdverseSelectionTest is Test {
    PolicyRegistry internal registry;
    InsurancePool  internal pool;

    address internal mockComptroller = makeAddr("mockComptroller");
    address internal alice           = makeAddr("alice");

    uint256 constant NOTIONAL  = 10 ether;
    uint256 constant DURATION  = 1_000;
    uint256 constant PREMIUM   = NOTIONAL / 100; // 1%

    function setUp() public {
        registry = new PolicyRegistry(mockComptroller);
        pool     = new InsurancePool(address(registry));
        registry.setInsurancePool(address(pool));

        vm.deal(address(this), 100 ether);
        pool.deposit{value: 100 ether}();
        vm.deal(alice, 10 ether);
    }

    // ─── Core Q1 cases ────────────────────────────────────────────────────

    /// Healthy position (shortfall == 0, liquidity > 0): purchase must succeed.
    function test_BuySucceedsWhenLiquid() public {
        _mockAccountLiquidity(0, 1 ether, 0); // error=0, liquidity=1e18, shortfall=0
        vm.prank(alice);
        uint256 id = registry.buyPolicy{value: PREMIUM}(NOTIONAL, DURATION);
        assertEq(id, 0, "First policy should have id 0");
    }

    /// Liquidatable position (shortfall > 0): purchase must revert.
    function test_BuyRevertsWhenShortfallNonZero() public {
        _mockAccountLiquidity(0, 0, 1); // error=0, liquidity=0, shortfall=1 wei
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyRegistry.PositionAlreadyLiquidatable.selector,
                uint256(0) // policyId would have been 0
            )
        );
        vm.prank(alice);
        registry.buyPolicy{value: PREMIUM}(NOTIONAL, DURATION);
    }

    /// Large shortfall (deeply underwater): still reverts on the same error.
    function test_BuyRevertsOnLargeShortfall() public {
        _mockAccountLiquidity(0, 0, 1_000_000 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyRegistry.PositionAlreadyLiquidatable.selector,
                uint256(0)
            )
        );
        vm.prank(alice);
        registry.buyPolicy{value: PREMIUM}(NOTIONAL, DURATION);
    }

    // ─── Edge: dust position exactly at the boundary ───────────────────────

    /// liquidity == 0 AND shortfall == 0: position is exactly at minimum collateral.
    /// No shortfall means not liquidatable — purchase should succeed.
    /// This is the inclusive lower boundary of the healthy half.
    function test_BuySucceedsAtExactBoundary() public {
        _mockAccountLiquidity(0, 0, 0); // no shortfall, no excess — just healthy
        vm.prank(alice);
        uint256 id = registry.buyPolicy{value: PREMIUM}(NOTIONAL, DURATION);
        assertEq(id, 0);
    }

    // ─── Comptroller error handling ────────────────────────────────────────

    /// Comptroller returns non-zero error code: purchase must revert with ComptrollerError.
    function test_BuyRevertsOnComptrollerError() public {
        _mockAccountLiquidity(1, 0, 0); // error code 1
        vm.expectRevert(
            abi.encodeWithSelector(PolicyRegistry.ComptrollerError.selector, uint256(1))
        );
        vm.prank(alice);
        registry.buyPolicy{value: PREMIUM}(NOTIONAL, DURATION);
    }

    // ─── Sequential purchases ──────────────────────────────────────────────

    /// Two sequential healthy purchases assign sequential IDs.
    function test_SequentialPolicyIds() public {
        _mockAccountLiquidity(0, 1 ether, 0);

        vm.prank(alice);
        uint256 id0 = registry.buyPolicy{value: PREMIUM}(NOTIONAL, DURATION);

        address bob = makeAddr("bob");
        vm.deal(bob, 10 ether);
        vm.prank(bob);
        uint256 id1 = registry.buyPolicy{value: PREMIUM}(NOTIONAL, DURATION);

        assertEq(id0, 0);
        assertEq(id1, 1);
    }

    // ─── Internal helpers ─────────────────────────────────────────────────

    function _mockAccountLiquidity(
        uint256 err,
        uint256 liquidity,
        uint256 shortfall
    ) internal {
        vm.mockCall(
            mockComptroller,
            abi.encodeWithSelector(
                IPeridotComptroller.getAccountLiquidity.selector,
                alice
            ),
            abi.encode(err, liquidity, shortfall)
        );
        // Also mock for any other caller (bob in sequential test).
        vm.mockCall(
            mockComptroller,
            abi.encodeWithSelector(IPeridotComptroller.getAccountLiquidity.selector),
            abi.encode(err, liquidity, shortfall)
        );
    }
}
