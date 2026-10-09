// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IClaimVerifier} from "./interfaces/IClaimVerifier.sol";
import {PolicyRegistry} from "./PolicyRegistry.sol";

interface IGroth16Verifier {
    function verifyProof(
        uint256[2] calldata _pA,
        uint256[2][2] calldata _pB,
        uint256[2] calldata _pC,
        uint256[2] calldata _pubSignals
    ) external view returns (bool);
}

contract ClaimVerifier is IClaimVerifier {
    PolicyRegistry public immutable registry;
    IGroth16Verifier public immutable groth16Verifier;

    uint256 public constant MAX_PROOF_AGE_BLOCKS = 12_000; // ~1 hour at 0.3s/block

    error InvalidCommitment();
    error ZeroCommitment();
    error StaleProof();
    error ProofFailed();

    constructor(address _registry, address _groth16Verifier) {
        registry = PolicyRegistry(_registry);
        groth16Verifier = IGroth16Verifier(_groth16Verifier);
    }

    function verifyClaim(
        uint256 policyId,
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[2] calldata publicInputs // [roundId, commitment]
    ) external view returns (bool) {
        uint256 roundId = publicInputs[0];
        uint256 proofCommitment = publicInputs[1];

        if (block.number > roundId + MAX_PROOF_AGE_BLOCKS) revert StaleProof();

        uint256 storedCommitment = registry.commitments(policyId, roundId);
        if (storedCommitment == 0) revert ZeroCommitment();
        if (storedCommitment != proofCommitment) revert InvalidCommitment();

        bool isValid = groth16Verifier.verifyProof(a, b, c, publicInputs);
        if (!isValid) revert ProofFailed();
        return isValid;
    }
}
