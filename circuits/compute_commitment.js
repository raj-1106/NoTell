const { poseidon } = require('circomlibjs');
const ethers = require('ethers');

async function main() {
    const liquidity = process.argv[2];
    const shortfall = process.argv[3];
    const roundId = process.argv[4];

    // poseidon takes BigInts
    const hash = poseidon([BigInt(liquidity), BigInt(shortfall), BigInt(roundId)]);
    
    // poseidon returns a Uint8Array, we need to convert to BigInt
    // poseidon function from circomlibjs returns the F element (which is a bigint in newer versions, or we can use poseidon.F.toString)
    // Actually, poseidon returns a Uint8Array or BigInt depending on the version. Let's use F.toObject
    // Wait, in circomlibjs, poseidon returns a Uint8Array that represents the element in Montgomery form, or we can use poseidon.F.toObject(hash)
    // A safer way is to just use buildPoseidon() but circomlibjs v0.1.2 export poseidon directly as a function that returns BigInt.
    
    // Let's assume it returns a BigInt (circomlib 0.1.x) or we use the ABI coder.
    // wait, we installed circomlibjs (latest).
    const { buildPoseidon } = require('circomlibjs');
    const p = await buildPoseidon();
    const h = p([liquidity, shortfall, roundId]);
    const hex = p.F.toString(h, 16);
    
    const abi = new ethers.AbiCoder();
    const encoded = abi.encode(["uint256"], ["0x" + hex]);
    
    // output for ffi
    process.stdout.write(encoded);
    process.exit(0);
}

main().catch(err => {
    console.error(err);
    process.exit(1);
});
