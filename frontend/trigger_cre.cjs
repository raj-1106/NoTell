const { JsonRpcProvider, Contract, Wallet } = require("ethers");
const fs = require("fs");

async function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    console.error("Please provide the Policy ID as an argument. Example: node trigger_cre.cjs 0");
    process.exit(1);
  }
  const policyId = parseInt(args[0], 10);

  console.log(`Setting up CRE Oracle simulation for Policy ID: ${policyId}`);

  // Connect to local Anvil testnet
  const provider = new JsonRpcProvider("http://127.0.0.1:8545");
  
  // Use the default Anvil private key (which is used for mock deployments)
  const wallet = new Wallet("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", provider);

  const deployments = JSON.parse(fs.readFileSync('../contracts/deployments/monad-testnet.json'));
  
  const registryAbi = [
    "function creAddress() view returns (address)",
    "function checkHealthFactors(uint256[] calldata policyIds) external"
  ];
  const registry = new Contract(deployments.PolicyRegistry, registryAbi, wallet);
  
  const comptrollerAbi = ["function setShortfall(bool) external"];
  const comptroller = new Contract(deployments.MockComptroller, comptrollerAbi, wallet);

  console.log("1. Modifying MockComptroller to report a shortfall (simulating Peridot liquidation)...");
  const tx1 = await comptroller.setShortfall(true);
  await tx1.wait();
  console.log("   Shortfall created.");

  console.log("2. Impersonating Chainlink CRE Oracle...");
  const creAddress = await registry.creAddress();
  await provider.send("anvil_impersonateAccount", [creAddress]);
  await provider.send("anvil_setBalance", [creAddress, "0xDE0B6B3A7640000"]); // Give ETH for gas
  
  const creSigner = await provider.getSigner(creAddress);
  const registryCre = registry.connect(creSigner);

  console.log("3. Executing CRE workflow: polling checkHealthFactors...");
  // First call sets the consecutive shortfalls counter to 1
  try { await (await registryCre.checkHealthFactors([policyId])).wait(); } catch(e) {}
  
  // Mine a block to simulate 5-minute interval
  await provider.send("evm_mine", []);

  // Second call increments counter to 2 and posts the commitment
  let blockNum;
  try {
    const tx = await registryCre.checkHealthFactors([policyId]);
    const receipt = await tx.wait();
    blockNum = receipt.blockNumber;
    console.log(`   Success! CRE Oracle posted the commitment at Block: ${blockNum}`);
  } catch(e) {
    console.error("   CRE post failed:", e.message);
  }

  await provider.send("anvil_stopImpersonatingAccount", [creAddress]);

  console.log("\n4. Bypassing 24-hour Holding Period for testing...");
  console.log("   Mining 288,001 blocks (This takes about 5 seconds)...");
  await provider.send("anvil_mine", ["0x46501"]); // Warp forward
  console.log("   Time warp complete.");

  console.log(`\nDONE!`);
  console.log(`You can now go back to the browser.`);
  console.log(`Click 'Auto-Fetch' next to the Round ID field, and it will pull Block ${blockNum}.`);
  console.log(`Then click 'Generate Proof & Claim'!`);
}

main().catch(console.error);
