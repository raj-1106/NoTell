// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPoseidon
/// @notice Interface for a deployed PoseidonT4 contract (3 inputs → t=4 state).
///         Used by PolicyRegistry.checkHealthFactors to compute:
///           commitment = Poseidon(collateral, debt, block.number)
///
///         The deployed address is injected into PolicyRegistry by the deployer.
///         Circuit alignment (input ordering, parameter set) is documented in
///         Phase 3 when the circuit and ClaimVerifier are written.
///
/// @dev In tests, use MockPoseidon (returns keccak256 of inputs) to avoid
///      deploying the full constant-heavy PoseidonT4 bytecode in setUp.
///      The mock is only valid for unit tests — ZK proof generation requires
///      the real Poseidon output in the commitment on testnet.
interface IPoseidon {
    function poseidon(uint256[3] calldata inputs) external pure returns (uint256);
}
