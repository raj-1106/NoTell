// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {InsurancePool} from "../src/InsurancePool.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {CREBridge} from "../src/CREBridge.sol";

contract MockComptroller {
    function getAccountLiquidity(address) external pure returns (uint256, uint256, uint256) {
        // Return excess liquidity to pass the checkHealthFactors
        return (0, 100000 ether, 0);
    }
}

contract VerifyE2E is Script {
    function run() public {
        address payable poolAddr = payable(0x7F4109584a81d7BF793d70a815a2DB3f486040EA);
        address registryAddr = 0xae5548136455595Ac4908C1C4b8A9545c2A0E7C1;
        address bridgeAddr = 0xCFF4284814eAd380A132b6dF09318ae6b202D304;
        address forwarder = 0xF8344CFd5c43616a4366C34E3EEE75af79a74482; // Real CRE Forwarder
        
        // Etch MockComptroller onto the empty address that PolicyRegistry uses
        address comptrollerAddr = 0xa41D586530BC7BC872095950aE03a780d5114445;
        MockComptroller mockComptroller = new MockComptroller();
        vm.etch(comptrollerAddr, address(mockComptroller).code);

        InsurancePool pool = InsurancePool(poolAddr);
        PolicyRegistry registry = PolicyRegistry(registryAddr);
        CREBridge bridge = CREBridge(bridgeAddr);
        
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address deployer = vm.addr(pk);
        
        // --- 1. Provide Liquidity (Simulated on Fork) ---
        {
            vm.startPrank(deployer);
            vm.deal(deployer, 100 ether); // give ETH to the deployer on the fork
            
            uint256 depositAmt = 0.1 ether;
            pool.deposit{value: depositAmt}();
            console2.log("Deposited liquidity:", depositAmt);
        }
        
        uint256 policyId;
        // --- 2. Buy Policy ---
        {
            uint256 notional = 0.1 ether;
            uint256 premium = (notional * registry.PREMIUM_BPS()) / 10000;
            policyId = registry.buyPolicy{value: premium}(notional, 100);
            console2.log("Purchased policy ID:", policyId);
            vm.stopPrank();
        }
        
        // --- 3. Simulate CRE Workflow Trigger (Impersonating Forwarder) ---
        {
            console2.log("Simulating CRE DON checkHealthFactors (Tick 1)...");
            
            uint256[] memory policyIds = new uint256[](1);
            policyIds[0] = policyId;
            bytes memory reportData = abi.encode(policyIds);
            bytes memory callData = abi.encodeWithSignature("onReport(bytes,bytes)", bytes(""), reportData);
            
            vm.prank(forwarder);
            (bool success1, ) = address(bridge).call(callData);
            require(success1, "Tick 1 failed");

            vm.roll(block.number + 1);

            console2.log("Simulating CRE DON checkHealthFactors (Tick 2 - persistence)...");
            vm.prank(forwarder);
            (bool success2, ) = address(bridge).call(callData);
            require(success2, "Tick 2 failed");

            console2.log("CREBridge.onReport executed successfully! Claim window should be open.");
            
            // --- 4. Process Claim ---
            vm.roll(block.number + 288_000 + 1); // Pass holding period

            vm.prank(deployer);
            uint256[2] memory a;
            uint256[2][2] memory b;
            uint256[2] memory c;
            uint256[2] memory p;
            pool.processClaim(policyId, a, b, c, p);

            // Check if policy is claimed
            (,,,,, PolicyRegistry.PolicyState state) = registry.policies(policyId);
            require(uint(state) == uint(PolicyRegistry.PolicyState.Claimed), "Policy not claimed!");
            console2.log("Verified! Policy state updated to Claimed.");
        }
        
        console2.log("E2E Verification Complete.");
    }
}
