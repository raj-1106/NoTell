// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {InsurancePool} from "../src/InsurancePool.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";

contract VerifyZK is Script {
    InsurancePool pool;
    PolicyRegistry registry;
    uint256 deployerPk;
    address deployer;

    function run() external {
        // Load dependencies from env
        address poolAddr = vm.envAddress("INSURANCE_POOL_ADDRESS");
        address registryAddr = vm.envAddress("POLICY_REGISTRY_ADDRESS");
        deployerPk = vm.envUint("DEPLOYER_PK");
        deployer = vm.addr(deployerPk);

        pool = InsurancePool(payable(poolAddr));
        registry = PolicyRegistry(payable(registryAddr));

        vm.startPrank(deployer);

        // 1. Buy a fresh policy on the fork
        uint256 notional = 1 * 1e18; // 1 MON
        uint256 premium = notional / 100; // 1%
        uint256 blockDuration = 10_000_000;
        
        vm.deal(deployer, 10 ether);

        uint256 policyId = registry.buyPolicy{value: premium}(notional, blockDuration);
        console2.log("Purchased fresh Policy ID:", policyId);

        // 2. Backdate the policy's startBlock via vm.store
        _backdatePolicy(policyId, notional, premium, blockDuration);

        // 3. Trigger CREBridge via MockComptroller to generate commitment
        uint256 commitment = _triggerMockCommitment(policyId);

        // 4. Generate and process ZK Proof
        _generateAndProcessProof(policyId, commitment);
        
        vm.stopPrank();
    }

    function _backdatePolicy(uint256 policyId, uint256 notional, uint256 premium, uint256 blockDuration) internal {
        uint256 startBlockSlot = uint256(keccak256(abi.encode(policyId, 1))) + 3; // Slot 1 mapping, offset 3 for startBlock

        uint256 oldStartBlock = uint256(vm.load(address(registry), bytes32(startBlockSlot)));
        uint256 newStartBlock = block.number > 300000 ? block.number - 300000 : 0;
        vm.store(address(registry), bytes32(startBlockSlot), bytes32(newStartBlock));
        
        uint256 readStartBlock = uint256(vm.load(address(registry), bytes32(startBlockSlot)));
        require(readStartBlock == newStartBlock, "startBlock not updated correctly");
        
        _verifyStructIntact(registry, policyId, deployer, newStartBlock);

        console2.log("Successfully backdated startBlock via vm.store without corruption!");
    }
    
    function _verifyStructIntact(PolicyRegistry _registry, uint256 policyId, address expectedUser, uint256 expectedStartBlock) internal view {
        (
            address fetchedUser,
            uint256 fetchedNotional,
            uint256 fetchedPremium,
            uint256 fetchedStartBlock,
            ,
            
        ) = _registry.policies(policyId);
        
        require(fetchedUser == expectedUser, "User corrupted");
        require(fetchedNotional == 1 ether, "Notional corrupted");
        require(fetchedPremium == 0.01 ether, "Premium corrupted");
        require(fetchedStartBlock == expectedStartBlock, "Start block readback failed");
    }

    function _triggerMockCommitment(uint256 policyId) internal returns (uint256) {
        address comptrollerAddr = address(registry.comptroller());
        (bool success, ) = comptrollerAddr.call(abi.encodeWithSignature("setShortfall(bool)", true));
        require(success, "MockComptroller setShortfall failed");

        uint256[] memory policies = new uint256[](1);
        policies[0] = policyId;

        vm.stopPrank();
        vm.startPrank(registry.creAddress());
        registry.checkHealthFactors(policies);
        registry.checkHealthFactors(policies);
        vm.stopPrank();
        vm.startPrank(deployer);

        uint256 roundId = block.number;
        uint256 commitment = registry.commitments(policyId, roundId);
        require(commitment != 0, "Commitment not posted");
        
        console2.log("Simulated CRE report posted. Commitment:", commitment);
        return commitment;
    }

    function _generateAndProcessProof(uint256 policyId, uint256 commitment) internal {
        string memory simulatedLiquidity = "0";
        string memory simulatedShortfall = "50000000000000000000000";
        uint256 roundId = block.number;
        
        string[] memory proveCmds = new string[](5);
        proveCmds[0] = "node";
        proveCmds[1] = "../circuits/prove.js";
        proveCmds[2] = simulatedLiquidity;
        proveCmds[3] = simulatedShortfall;
        proveCmds[4] = vm.toString(roundId);
        
        console2.log("Generating ZK Proof off-chain...");
        bytes memory proofRes = vm.ffi(proveCmds);
        
        (
            uint256[2] memory a,
            uint256[2][2] memory b,
            uint256[2] memory c,
            uint256[2] memory pubInputs
        ) = abi.decode(proofRes, (uint256[2], uint256[2][2], uint256[2], uint256[2]));
        
        console2.log("Proof generated. Processing claim...");
        // Fund the pool so it can pay out the claim
        pool.deposit{value: 2 ether}();
        pool.processClaim(policyId, a, b, c, pubInputs);
        console2.log("Claim verified successfully via ZK Proof!");
    }
}
