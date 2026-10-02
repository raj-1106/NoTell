const puppeteer = require('puppeteer');
const { JsonRpcProvider, Wallet, Contract, parseEther } = require('ethers');
const fs = require('fs');

async function main() {
  console.log("Starting Headless Browser UI Test...");

  // Setup Anvil provider & deployer wallet
  const provider = new JsonRpcProvider("http://127.0.0.1:8545");
  const wallet = new Wallet("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", provider);

  const deployments = JSON.parse(fs.readFileSync('../contracts/deployments/monad-testnet.json'));
  const registryFullAbi = JSON.parse(fs.readFileSync('../contracts/out/PolicyRegistry.sol/PolicyRegistry.json')).abi;
  const registryFull = new Contract(deployments.PolicyRegistry, registryFullAbi, wallet);
  const comptrollerAbi = ["function setShortfall(bool) external"];
  const comptroller = new Contract(deployments.MockComptroller, comptrollerAbi, wallet);

  // 1. Launch Puppeteer
  const browser = await puppeteer.launch({ headless: "new" });
  const page = await browser.newPage();

  // Handle alerts
  let lastAlert = "";
  page.on('dialog', async dialog => {
    lastAlert = dialog.message();
    console.log(`[Browser Alert]: ${lastAlert}`);
    await dialog.accept();
  });

  page.on('console', msg => {
    if (msg.type() === 'error') {
      console.error(`[Browser Console Error]: ${msg.text()}`);
    } else {
      console.log(`[Browser Console]: ${msg.text()}`);
    }
  });

  await page.goto('http://localhost:5173');
  console.log("Navigated to localhost:5173");

  // 2. Connect Wallet
  await page.waitForSelector('button.btn-primary');
  await page.click('button.btn-primary');
  await new Promise(r => setTimeout(r, 1000));
  console.log("Wallet Connected via E2E Fake Provider");

  // 3. Buy Policy
  console.log("Ensuring MockComptroller is healthy for purchase (Q1 check)...");
  await (await comptroller.setShortfall(false)).wait();

  await page.evaluate(() => {
    const btns = Array.from(document.querySelectorAll('button'));
    const buyBtn = btns.find(b => b.textContent.includes('Buy Policy'));
    if (buyBtn) buyBtn.click();
  });
  console.log("Clicked Buy Policy...");
  
  // Wait for policy to be bought (alert is triggered)
  while(lastAlert !== "Policy purchased successfully!" && !lastAlert.includes("failed")) {
    await new Promise(r => setTimeout(r, 500));
  }
  if (lastAlert.includes("failed")) throw new Error("Buy Policy Failed");

  // Get policy ID
  const nextId = await registryFull.nextPolicyId();
  const policyId = nextId - 1n;
  console.log(`Policy Purchased on-chain! Policy ID: ${policyId}`);

  // 4. Setup mock state & post commitment
  console.log("Setting shortfall and posting CRE commitment...");
  await (await comptroller.setShortfall(true)).wait();
  
  const creAddress = await registryFull.creAddress();
  await provider.send("anvil_impersonateAccount", [creAddress]);
  await provider.send("anvil_setBalance", [creAddress, "0xDE0B6B3A7640000"]);
  const creSigner = await provider.getSigner(creAddress);
  const registryCre = registryFull.connect(creSigner);
  
  // Clear alerts
  lastAlert = "";

  try { await (await registryCre.checkHealthFactors([policyId])).wait(); } catch(e) {}
  await provider.send("evm_mine", []);
  
  let claimRoundId = "0";
  try {
    const tx = await registryCre.checkHealthFactors([policyId]);
    const receipt = await tx.wait();
    claimRoundId = receipt.blockNumber.toString();
    console.log(`Commitment posted at block: ${claimRoundId}`);
  } catch(e) {
    console.log("CRE post failed", e.message);
  }

  await provider.send("anvil_stopImpersonatingAccount", [creAddress]);
  
  console.log("Bypassing Holding Period (Warp 288001 blocks)...");
  await provider.send("anvil_mine", ["0x46501"]); // 288001 blocks

  // 5. Fill ZK Claim Form in Browser
  console.log("Filling ZK Claim Inputs...");
  const inputs = await page.$$('input[type="number"]');
  // First input is notional, second is PolicyId, third is RoundId
  await inputs[1].type(policyId.toString());
  await inputs[2].type(claimRoundId);

  // 6. Click Generate Proof
  console.log("Clicking Generate Proof & Claim in browser...");
  await page.evaluate(() => {
    const btns = Array.from(document.querySelectorAll('button'));
    const claimBtn = btns.find(b => b.textContent.includes('Generate Proof'));
    if (claimBtn) claimBtn.click();
  });

  // Wait for proof generation and claim alert
  while(lastAlert === "") {
    await new Promise(r => setTimeout(r, 500));
  }

  if (lastAlert.includes("successfully")) {
    console.log("SUCCESS! The browser generated the ZK proof and claimed it on-chain!");
  } else {
    console.error("FAILED. Alert:", lastAlert);
  }

  await browser.close();
}

main().catch(console.error);
