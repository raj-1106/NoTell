/**
 * one_shot_keeper.js
 * Reads getAccountLiquidity for all active policies, computes Poseidon hash
 * off-chain, and calls PolicyRegistry.postCommitment() exactly once per policy
 * in shortfall, then exits.
 */
require('dotenv').config();
const { ethers } = require('ethers');
const { buildPoseidon } = require('circomlibjs');

const REGISTRY_ABI = [
  "function nextPolicyId() view returns (uint256)",
  "function policies(uint256) view returns (address holder, uint256 notional, uint256 premiumPaid, uint256 startBlock, uint256 endBlock, uint8 state)",
  "function postCommitment(uint256 policyId, uint256 roundId, uint256 liquidity, uint256 shortfall, uint256 commitment) external",
  "function checkHealthFactors(uint256[] calldata policyIds) external"
];

const COMPTROLLER_ABI = [
  "function getAccountLiquidity(address account) view returns (uint256 err, uint256 liquidity, uint256 shortfall)"
];

async function main() {
  const provider = new ethers.JsonRpcProvider(process.env.MONAD_RPC_URL, {
    chainId: 10143,
    name: 'monad-testnet'
  }, { staticNetwork: true });

  const wallet   = new ethers.Wallet(process.env.CRE_ETH_PRIVATE_KEY, provider);
  const registry = new ethers.Contract(process.env.POLICY_REGISTRY_ADDRESS, REGISTRY_ABI, wallet);

  // Get the Comptroller address from the registry's immutable
  const COMPTROLLER_ADDRESS = process.env.COMPTROLLER_ADDRESS;
  if (!COMPTROLLER_ADDRESS) {
    console.error('[OneShot] COMPTROLLER_ADDRESS not set in .env');
    process.exit(1);
  }
  const comptroller = new ethers.Contract(COMPTROLLER_ADDRESS, COMPTROLLER_ABI, provider);

  const poseidon = await buildPoseidon();

  const nextId = await registry.nextPolicyId();
  const roundId = await provider.getBlockNumber();
  let posted = 0;

  for (let i = 0; i < Number(nextId); i++) {
    const p = await registry.policies(i);
    const state = Number(p[5]);
    if (state !== 0) {
      console.log(`[OneShot] Policy ${i}: skipping (state=${state})`);
      continue;
    }

    const [err, liquidity, shortfall] = await comptroller.getAccountLiquidity(p[0]);
    if (Number(err) !== 0) {
      console.log(`[OneShot] Policy ${i}: comptroller error ${err}`);
      continue;
    }
    if (shortfall === 0n) {
      console.log(`[OneShot] Policy ${i}: no shortfall — position healthy, skipping`);
      continue;
    }

    console.log(`[OneShot] Policy ${i}: shortfall=${shortfall}, liquidity=${liquidity}, roundId=${roundId}`);

    // Compute Poseidon(liquidity, shortfall, roundId) off-chain
    const hash = poseidon([liquidity, shortfall, BigInt(roundId)]);
    const commitment = poseidon.F.toObject(hash);
    console.log(`[OneShot] Policy ${i}: commitment=${commitment}`);

    const tx = await registry.postCommitment(i, roundId, liquidity, shortfall, commitment);
    const receipt = await tx.wait();
    console.log(`[OneShot] ✅ Policy ${i}: postCommitment confirmed in block ${receipt.blockNumber}`);
    console.log(`[OneShot] Tx: ${tx.hash}`);
    console.log(`\n>>> ROUND ID TO USE IN UI: ${receipt.blockNumber} <<<\n`);
    posted++;
  }

  if (posted === 0) {
    console.log('[OneShot] No policies in shortfall found. Did you click Force Liquidation?');
    process.exit(1);
  }

  console.log(`[OneShot] Done. ${posted} commitment(s) posted.`);
}

main().catch(e => { console.error(e); process.exit(1); });
