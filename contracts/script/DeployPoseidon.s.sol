// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";

contract DeployPoseidon is Script {
    function run() external {
        address registryAddress = vm.envAddress("POLICY_REGISTRY_ADDRESS");
        uint256 deployerPk = vm.envUint("DEPLOYER_PK");
        
        vm.startBroadcast(deployerPk);

        // Read bytecode
        // fs.writeFileSync writes without 0x in our JS script, but let's read it
        string memory hexContent = vm.readFile("./PoseidonT3Bytecode.hex");
        // Ensure it starts with 0x for parseBytes
        bytes memory bytecode = vm.parseBytes(string.concat("0x", hexContent));
        
        address poseidonT3;
        assembly {
            poseidonT3 := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(poseidonT3 != address(0), "Poseidon deployment failed");

        console2.log("PoseidonT3 deployed at:", poseidonT3);

        // Update PolicyRegistry
        PolicyRegistry registry = PolicyRegistry(registryAddress);
        registry.setPoseidon(poseidonT3);
        console2.log("Updated PolicyRegistry.poseidon() with new PoseidonT3 address");

        vm.stopBroadcast();
    }
}
