// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ClaimVerifier} from "../src/ClaimVerifier.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";

contract MockGroth16Verifier {
    bool public shouldPass = true;

    function setPass(bool _pass) external {
        shouldPass = _pass;
    }

    function verifyProof(
        uint256[2] calldata,
        uint256[2][2] calldata,
        uint256[2] calldata,
        uint256[2] calldata
    ) external view returns (bool) {
        return shouldPass;
    }
}

contract MockRegistry {
    mapping(uint256 => mapping(uint256 => uint256)) public commitments;

    function setCommitment(uint256 policyId, uint256 roundId, uint256 commitment) external {
        commitments[policyId][roundId] = commitment;
    }
}

contract ClaimVerificationTest is Test {
    ClaimVerifier verifier;
    MockGroth16Verifier groth16;
    MockRegistry registry;

    uint256 constant POLICY_ID = 1;
    uint256 constant VALID_ROUND = 1000;
    uint256 constant VALID_COMMITMENT = 0x123456789;

    function setUp() public {
        registry = new MockRegistry();
        groth16 = new MockGroth16Verifier();
        
        verifier = new ClaimVerifier(
            address(registry),
            address(groth16)
        );

        // Pre-configure a valid state
        registry.setCommitment(POLICY_ID, VALID_ROUND, VALID_COMMITMENT);
        vm.roll(VALID_ROUND + 10); // Move 10 blocks forward (not stale)
    }

    function _buildValidCall() internal view returns (
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        uint256[2] memory pubInputs
    ) {
        a = [uint256(1), uint256(2)];
        b = [[uint256(1), uint256(2)], [uint256(3), uint256(4)]];
        c = [uint256(1), uint256(2)];
        pubInputs = [VALID_ROUND, VALID_COMMITMENT];
    }

    function test_VerifyClaim_HappyPath() public {
        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c, uint256[2] memory pubInputs) = _buildValidCall();
        
        bool result = verifier.verifyClaim(POLICY_ID, a, b, c, pubInputs);
        assertTrue(result, "Claim should verify successfully");
    }

    function test_RevertWhen_CommitmentIsZero() public {
        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c, ) = _buildValidCall();
        
        // Use a roundId that hasn't been set (defaults to 0)
        uint256[2] memory pubInputs = [uint256(9999), VALID_COMMITMENT];

        vm.expectRevert(ClaimVerifier.ZeroCommitment.selector);
        verifier.verifyClaim(POLICY_ID, a, b, c, pubInputs);
    }

    function test_RevertWhen_FabricatedCommitment() public {
        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c, ) = _buildValidCall();
        
        // Pass a fake commitment in the public inputs that doesn't match the registry
        uint256[2] memory pubInputs = [VALID_ROUND, 0xDEADBEEF];

        vm.expectRevert(ClaimVerifier.InvalidCommitment.selector);
        verifier.verifyClaim(POLICY_ID, a, b, c, pubInputs);
    }

    function test_RevertWhen_ProofIsStale() public {
        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c, uint256[2] memory pubInputs) = _buildValidCall();
        
        // Roll forward just past the MAX_PROOF_AGE_BLOCKS (12_000)
        vm.roll(VALID_ROUND + 12001);

        vm.expectRevert(ClaimVerifier.StaleProof.selector);
        verifier.verifyClaim(POLICY_ID, a, b, c, pubInputs);
    }

    function test_RevertWhen_Groth16Fails() public {
        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c, uint256[2] memory pubInputs) = _buildValidCall();
        
        // Set mock verifier to reject the proof
        groth16.setPass(false);

        vm.expectRevert(ClaimVerifier.ProofFailed.selector);
        verifier.verifyClaim(POLICY_ID, a, b, c, pubInputs);
    }
}
