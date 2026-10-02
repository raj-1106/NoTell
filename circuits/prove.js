const snarkjs = require('snarkjs');
const { buildPoseidon } = require('circomlibjs');
const ethers = require('ethers');

async function main() {
    const liquidity = process.argv[2];
    const shortfall = process.argv[3];
    const roundId = process.argv[4];

    // Compute commitment
    const p = await buildPoseidon();
    const h = p([liquidity, shortfall, roundId]);
    const commitment = "0x" + p.F.toString(h, 16);

    const path = require('path');
    const { proof, publicSignals } = await snarkjs.groth16.fullProve(
        { liquidity, shortfall, roundId, commitment },
        path.join(__dirname, "shortfall_js/shortfall.wasm"),
        path.join(__dirname, "shortfall_0001.zkey")
    );

    // Format for Solidity
    const a = [proof.pi_a[0], proof.pi_a[1]];
    const b = [
        [proof.pi_b[0][1], proof.pi_b[0][0]],
        [proof.pi_b[1][1], proof.pi_b[1][0]]
    ];
    const c = [proof.pi_c[0], proof.pi_c[1]];
    const pub = publicSignals;

    const abi = new ethers.AbiCoder();
    const encoded = abi.encode(
        ["uint256[2]", "uint256[2][2]", "uint256[2]", "uint256[2]"],
        [a, b, c, pub]
    );

    process.stdout.write(encoded);
    process.exit(0);
}

main().catch(err => {
    console.error(err);
    process.exit(1);
});
