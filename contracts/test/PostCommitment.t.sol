// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {InsurancePool} from "../src/InsurancePool.sol";
import {IPeridotComptroller} from "../src/interfaces/IPeridotComptroller.sol";

contract PostCommitmentTest is Test {
    event ClaimWindowOpened(uint256 indexed policyId, uint256 roundId, uint256 liquidity, uint256 shortfall);

    PolicyRegistry internal registry;
    InsurancePool internal pool;
    address internal mockComptroller = makeAddr("mockComptroller");
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");
    uint256 constant NOTIONAL = 1 ether;
    uint256 constant DURATION = 2_016_000;
    uint256 constant PREMIUM = NOTIONAL / 100;

    function setUp() public {
        registry = new PolicyRegistry(mockComptroller);
        pool = new InsurancePool(address(registry));
        registry.setInsurancePool(address(pool));
        vm.deal(address(this), 10 ether);
        pool.deposit{value: 10 ether}();
        vm.deal(alice, 1 ether);
        vm.mockCall(
            mockComptroller,
            abi.encodeWithSelector(IPeridotComptroller.getAccountLiquidity.selector),
            abi.encode(uint256(0), uint256(1000 ether), uint256(0))
        );
        vm.prank(alice);
        registry.buyPolicy{value: PREMIUM}(NOTIONAL, DURATION);
    }

    function test_main_postStoresCommitmentAndEmits() public {
        uint256 round = block.number;
        vm.expectEmit(true, false, false, true, address(registry));
        emit ClaimWindowOpened(0, round, 0, 1000 ether);
        registry.postCommitment(0, round, 0, 1000 ether, 123);
        assertEq(registry.commitments(0, round), 123);
    }

    function test_edge_anyAddressCanPost() public {
        vm.prank(attacker);
        registry.postCommitment(0, block.number, 0, 1, 999);
        assertEq(registry.commitments(0, block.number), 999);
    }

    function test_edge_secondPostOverwritesFirst() public {
        uint256 round = block.number;
        registry.postCommitment(0, round, 0, 1000 ether, 111);
        vm.prank(attacker);
        registry.postCommitment(0, round, 0, 1, 222);
        assertEq(registry.commitments(0, round), 222);
    }

    function test_edge_nonexistentPolicyAccepted() public {
        registry.postCommitment(99, block.number, 0, 1, 7);
        assertEq(registry.commitments(99, block.number), 7);
    }

    function test_failure_revertsWithoutShortfall() public {
        vm.expectRevert(bytes("No shortfall: position is healthy"));
        registry.postCommitment(0, block.number, 1000 ether, 0, 5);
    }
}
