// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {PolicyRegistry}   from "../src/PolicyRegistry.sol";
import {InsurancePool}    from "../src/InsurancePool.sol";
import {CREBridge}        from "../src/CREBridge.sol";
import {Groth16Verifier}  from "../src/Groth16Verifier.sol";
import {ClaimVerifier}    from "../src/ClaimVerifier.sol";
import {MockComptroller}  from "../test/mocks/MockComptroller.sol";

/// @title Deploy
/// @notice Deploys PolicyRegistry and InsurancePool to Monad testnet.
///         Run with:
///           forge script script/Deploy.s.sol \
///             --rpc-url monad_testnet \
///             --broadcast \
///             --verify
///
///         Requires env vars:
///           DEPLOYER_PK        — private key of the deployer wallet
///           MONAD_RPC_URL      — RPC endpoint (set in foundry.toml [rpc_endpoints])
///           CHAINLINK_FEED     — Monad testnet Chainlink price feed address
///           MONAD_ETHERSCAN_KEY — block explorer API key (for --verify)
///           MONAD_EXPLORER_URL — block explorer URL (set in foundry.toml [etherscan])
///
///         After deployment, addresses are logged to stdout and should be
///         committed to deployments/monad-testnet.json for the indexer and frontend.
contract Deploy is Script {
    function run() external {
        uint256 deployerPk  = vm.envUint("DEPLOYER_PK");

        vm.startBroadcast(deployerPk);
        
        MockComptroller comptroller = new MockComptroller();

        // 1. Deploy InsurancePool with a placeholder registry address.
        //    We need InsurancePool's address before PolicyRegistry is deployed,
        //    but PolicyRegistry needs InsurancePool's address in its constructor.
        //    Solution: deploy Pool with address(0), then deploy Registry pointing
        //    at Pool, then — since pool.policyRegistry is set in constructor —
        //    we instead deploy them in order using a two-step approach:
        //    Pool address is predictable (nonce-based), so we can precompute it.

        // Compute predicted address for PolicyRegistry (nonce + 1 after pool).
        address deployer     = vm.addr(deployerPk);
        uint64  nonce        = vm.getNonce(deployer);
        address predictedReg = computeCreateAddress(deployer, nonce + 1);

        InsurancePool  pool     = new InsurancePool(predictedReg);
        PolicyRegistry registry = new PolicyRegistry(address(comptroller));
        
        // 2. Deploy PoseidonT3 dynamically from bytecode
        string memory hexContent = vm.readFile("./PoseidonT3Bytecode.hex");
        bytes memory bytecode = vm.parseBytes(string.concat("0x", hexContent));
        address poseidon;
        assembly {
            poseidon := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(poseidon != address(0), "Poseidon deployment failed");

        // Chainlink CRE Forwarder on Monad Testnet (provided via env or placeholder)
        address creForwarder = vm.envOr("CRE_FORWARDER_ADDRESS", address(0x0000000000000000000000000000000000000000));
        
        CREBridge bridge = new CREBridge(creForwarder, address(registry));

        // Phase 3: ZK Verifier
        Groth16Verifier groth16 = new Groth16Verifier();
        ClaimVerifier claimVerifier = new ClaimVerifier(address(registry), address(groth16));

        registry.setInsurancePool(address(pool));
        registry.setPoseidon(poseidon);
        pool.setClaimVerifier(address(claimVerifier));
        
        // Sequence is vital: Deploy registry -> Deploy bridge pointing to it -> Set bridge on registry
        // TEMPORARY FALLBACK: Bypass the CREBridge entirely and authorize the deployer wallet 
        // to push commitments directly. This unblocks the E2E claim flow test while Chainlink 
        // deployment access is stuck in manual review.
        registry.setCREAddress(deployer);

        // Sanity check: predicted address matched actual.
        require(address(registry) == predictedReg, "Address prediction failed");

        vm.stopBroadcast();

        console2.log("InsurancePool  deployed at:", address(pool));
        console2.log("PolicyRegistry deployed at:", address(registry));
        console2.log("MockComptroller deployed at:", address(comptroller));
        console2.log("CREBridge      deployed at:", address(bridge));
        console2.log("ClaimVerifier  deployed at:", address(claimVerifier));
        console2.log("Groth16Verifier deployed at:", address(groth16));
        console2.log("");
        console2.log("Add to deployments/monad-testnet.json:");
        console2.log("{");
        console2.log('  "InsurancePool"  : "', address(pool),   '",');
        console2.log('  "PolicyRegistry" : "', address(registry), '",');
        console2.log('  "CREBridge"      : "', address(bridge), '"');
        console2.log("}");
    }
}
