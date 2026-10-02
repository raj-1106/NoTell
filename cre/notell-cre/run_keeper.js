const { ethers } = require("ethers");
require("dotenv").config();
const fs = require("fs");
const path = require("path");

async function main() {
  if (!process.env.CRE_ETH_PRIVATE_KEY) {
    throw new Error("CRE_ETH_PRIVATE_KEY not found in .env");
  }

  const provider = new ethers.JsonRpcProvider("https://monad-testnet.g.alchemy.com/v2/OOIMS_hWS2oBIZXbMyjTG", {
    chainId: 10143,
    name: "monad-testnet"
  }, { staticNetwork: true });
  const wallet = new ethers.Wallet(process.env.CRE_ETH_PRIVATE_KEY, provider);
  
  // Load live deployments
  const deploymentsPath = path.join(__dirname, "../../contracts/deployments/monad-testnet.json");
  const deployments = JSON.parse(fs.readFileSync(deploymentsPath, "utf8"));
  
  const abi = [
    "function nextPolicyId() view returns (uint256)",
    "function checkHealthFactors(uint256[] calldata policyIds) external"
  ];
  
  const registry = new ethers.Contract(deployments.PolicyRegistry, abi, wallet);
  
  console.log(`[Temporary Keeper] Started on ${wallet.address}`);
  console.log(`[Temporary Keeper] Polling PolicyRegistry at ${deployments.PolicyRegistry}`);
  
  while (true) {
    const nextId = await registry.nextPolicyId();
    if (nextId === 0n) {
      console.log(`[Keeper] No policies issued yet. Skipping.`);
    } else {
      const policyIds = [];
      for (let i = 0; i < Number(nextId); i++) {
        policyIds.push(i);
      }
      
      console.log(`[Keeper] Pinging checkHealthFactors for ${policyIds.length} policies...`);
      try {
        const tx = await registry.checkHealthFactors(policyIds);
        console.log(`[Keeper] Tx sent: ${tx.hash}`);
        const receipt = await tx.wait();
        console.log(`[Keeper] Tx confirmed in block ${receipt.blockNumber}`);
      } catch (err) {
        console.error(`[Keeper] Error sending tx: ${err.message}`);
      }
    }
    
    // Wait 5 seconds before next poll
    await new Promise(resolve => setTimeout(resolve, 5000));
  }
}

main().catch(console.error);
