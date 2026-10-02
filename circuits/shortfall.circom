pragma circom 2.1.0;

include "node_modules/circomlib/circuits/poseidon.circom";
include "node_modules/circomlib/circuits/comparators.circom";

/// @title Shortfall Proof
/// @notice Proves that a position is under-collateralized (shortfall != 0).
///         And proves that Poseidon(liquidity, shortfall, roundId) matches the commitment.
template ShortfallProof() {
    // Private inputs from off-chain
    signal input liquidity;
    signal input shortfall;
    
    // Public inputs enforced on-chain
    signal input roundId;
    signal input commitment;
    
    // 1. Enforce shortfall != 0
    component isZero = IsZero();
    isZero.in <== shortfall;
    isZero.out === 0;
    
    // 2. Hash(liquidity, shortfall, roundId)
    component hasher = Poseidon(3);
    hasher.inputs[0] <== liquidity;
    hasher.inputs[1] <== shortfall;
    hasher.inputs[2] <== roundId;
    
    // 3. Output matches commitment
    hasher.out === commitment;
}

component main {public [roundId, commitment]} = ShortfallProof();
