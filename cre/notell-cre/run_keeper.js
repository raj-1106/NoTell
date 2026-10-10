const { ethers } = require("ethers");
require("dotenv").config();

async function main() {
  if (!process.env.CRE_ETH_PRIVATE_KEY) {
    throw new Error("CRE_ETH_PRIVATE_KEY not found in .env");
  }

  const provider = new ethers.JsonRpcProvider(process.env.MONAD_RPC_URL, {
    chainId: 10143,
    name: "monad-testnet"
  }, { staticNetwork: true });
  const wallet = new ethers.Wallet(process.env.CRE_ETH_PRIVATE_KEY, provider);
  
  const registryAddress = process.env.POLICY_REGISTRY_ADDRESS;
  const abi = [
    "function nextPolicyId() view returns (uint256)",
    "function checkHealthFactors(uint256[] calldata policyIds) external",
    "function policies(uint256) view returns (address holder, uint256 notional, uint256 premiumPaid, uint256 startBlock, uint256 endBlock, uint8 state)"
  ];
  
  const registry = new ethers.Contract(registryAddress, abi, wallet);
  
  console.log(`[Temporary Keeper] Started on ${wallet.address}`);
  console.log(`[Temporary Keeper] Polling PolicyRegistry at ${registryAddress}`);
  
  while (true) {
    try {
      const nextId = await registry.nextPolicyId();
      if (nextId === 0n) {
        console.log(`[Keeper] No policies issued yet. Skipping.`);
      } else {
        const activePolicyIds = [];
        for (let i = 1; i < Number(nextId); i++) {
          try {
            const p = await registry.policies(i);
            const state = Number(p[5]);
            const endBlock = BigInt(p[4]);
            const currentBlock = BigInt(await provider.getBlockNumber());
            
            if (state !== 0) {
              console.log(`[Keeper] Skipping policy ${i}: State is not Active (state=${state})`);
            } else if (currentBlock >= endBlock) {
              console.log(`[Keeper] Skipping policy ${i}: Expired (endBlock=${endBlock}, currentBlock=${currentBlock})`);
            } else {
              activePolicyIds.push(i);
            }
          } catch (e) {
            console.error(`[Keeper] Error fetching policy ${i}:`, e.message);
          }
        }
        
        if (activePolicyIds.length === 0) {
          console.log(`[Keeper] No active, unexpired policies found to monitor.`);
        } else {
          console.log(`[Keeper] Pinging checkHealthFactors for active policies: [${activePolicyIds.join(', ')}]...`);
          const tx = await registry.checkHealthFactors(activePolicyIds);
          console.log(`[Keeper] Tx sent: ${tx.hash}`);
          const receipt = await tx.wait();
          console.log(`[Keeper] Tx confirmed in block ${receipt.blockNumber}`);
        }
      }
    } catch (err) {
      console.error(`[Keeper] Network or polling error: ${err.message}`);
      if (err.code) console.error(`  -> Code: ${err.code}`);
      if (err.cause) console.error(`  -> Cause: ${err.cause}`);
      if (err.errors) console.error(`  -> Errors: ${err.errors}`);
    }
    
    await new Promise(resolve => setTimeout(resolve, 5000));
  }
}

main().catch(console.error);
