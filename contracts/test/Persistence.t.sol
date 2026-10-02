// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {InsurancePool} from "../src/InsurancePool.sol";
import {MockPoseidon} from "./mocks/MockPoseidon.sol";

contract MockComptroller {
    uint256 public err;
    uint256 public liquidity;
    uint256 public shortfall;

    function setLiquidity(uint256 _err, uint256 _liq, uint256 _short) external {
        err = _err;
        liquidity = _liq;
        shortfall = _short;
    }

    function getAccountLiquidity(address) external view returns (uint256, uint256, uint256) {
        return (err, liquidity, shortfall);
    }
}

contract PersistenceTest is Test {
    PolicyRegistry registry;
    InsurancePool pool;
    MockComptroller comptroller;
    MockPoseidon poseidon;
    
    address deployer = address(this);
    address cre = address(0xC2E);
    address user = address(0x111);

    function setUp() public {
        comptroller = new MockComptroller();
        poseidon = new MockPoseidon();
        
        registry = new PolicyRegistry(address(comptroller));
        pool = new InsurancePool(address(registry));
        
        registry.setInsurancePool(address(pool));
        registry.setCREAddress(cre);
        registry.setPoseidon(address(poseidon));
        
        vm.deal(user, 100 ether);
        
        // Buy a policy
        comptroller.setLiquidity(0, 100, 0); // healthy
        vm.prank(user);
        registry.buyPolicy{value: 0.01 ether}(1 ether, 100);
    }

    function test_PersistenceIncrementWithoutCommit() public {
        // Poll 1: Shortfall
        comptroller.setLiquidity(0, 0, 10);
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        
        vm.prank(cre);
        registry.checkHealthFactors(ids);
        
        assertEq(registry.consecutiveShortfalls(0), 1);
        assertEq(registry.commitments(0, block.number), 0);
    }

    function test_PersistenceCommitAtTwo() public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        
        // Poll 1: Shortfall
        comptroller.setLiquidity(0, 0, 10);
        vm.prank(cre);
        registry.checkHealthFactors(ids);
        
        // Poll 2: Shortfall
        vm.roll(block.number + 1);
        vm.prank(cre);
        registry.checkHealthFactors(ids);
        
        assertEq(registry.consecutiveShortfalls(0), 2);
        
        uint256[3] memory inputs = [uint256(0), uint256(10), block.number];
        uint256 expectedCommitment = poseidon.poseidon(inputs);
        assertEq(registry.commitments(0, block.number), expectedCommitment);
    }

    function test_PersistenceResetOnHeal() public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        
        // Poll 1: Shortfall
        comptroller.setLiquidity(0, 0, 10);
        vm.prank(cre);
        registry.checkHealthFactors(ids);
        assertEq(registry.consecutiveShortfalls(0), 1);
        
        // Poll 2: Healthy
        comptroller.setLiquidity(0, 100, 0);
        vm.prank(cre);
        registry.checkHealthFactors(ids);
        assertEq(registry.consecutiveShortfalls(0), 0);
    }

    function test_PersistenceCapWithoutOverflow() public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        
        comptroller.setLiquidity(0, 0, 10);
        
        // 300 polls (would overflow uint8 if not capped)
        for (uint i = 0; i < 300; i++) {
            vm.roll(block.number + 1);
            vm.prank(cre);
            registry.checkHealthFactors(ids);
        }
        
        assertEq(registry.consecutiveShortfalls(0), 2);
    }
}
