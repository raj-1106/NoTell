// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IClaimVerifier
/// @notice Interface for the Phase 3 ZK claim verifier.
///         Declared here in Phase 1 so InsurancePool can reference it
///         as a typed slot even before the implementation exists.
///         Phase 1 uses a plaintext oracle check; Phase 3 swaps in
///         the real ClaimVerifier behind this interface with no
///         change to InsurancePool's call site.
interface IClaimVerifier {
    /// @notice Verify a ZK proof that a covered position crossed its threshold.
    /// @param policyId      The policy being claimed against. Explicit because
    ///                      ClaimVerifier must look up policies[policyId].threshold
    ///                      and commitments[policyId][roundId] on PolicyRegistry —
    ///                      those live in a separate contract, not here.
    /// @param a             Groth16 proof element A.
    /// @param b             Groth16 proof element B.
    /// @param c             Groth16 proof element C.
    /// @param publicInputs  [roundId, commitment]
    ///                      roundId    — block.number at which CRE posted the commitment
    ///                      commitment — Poseidon(liquidity, shortfall, roundId) posted by CRE
    /// @return              True iff all checks pass and the proof verifies.
    function verifyClaim(
        uint256 policyId,
        uint256[2]    calldata a,
        uint256[2][2] calldata b,
        uint256[2]    calldata c,
        uint256[2]    calldata publicInputs
    ) external view returns (bool);
}
