const fs = require('fs');
const { poseidonContract } = require('circomlibjs');

// We need a Poseidon hash for 3 inputs (liquidity, shortfall, roundId).
const bytecode = poseidonContract.createCode(3);
const abi = poseidonContract.generateABI(3);

fs.writeFileSync('PoseidonT3Bytecode.hex', bytecode.slice(2)); // Remove 0x prefix if present
fs.writeFileSync('PoseidonT3ABI.json', JSON.stringify(abi));

console.log('Successfully generated Poseidon(3) bytecode and ABI');
