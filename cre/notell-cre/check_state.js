const { ethers } = require("ethers");
require("dotenv").config();
const fs = require("fs");
const path = require("path");

async function main() {
  const provider = new ethers.JsonRpcProvider("https://testnet-rpc.monad.xyz/", {
    chainId: 10143,
    name: "monad-testnet"
  }, { staticNetwork: true });

  const deployments = JSON.parse(fs.readFileSync(path.join(__dirname, "../../contracts/deployments/monad-testnet.json"), "utf8"));
  
  const registryAbi = ["function policies(uint256) view returns (uint256, address, uint256, uint256, uint8)"];
  const registry = new ethers.Contract(deployments.PolicyRegistry, registryAbi, provider);
  
  const comptrollerAbi = ["function getAccountLiquidity(address) view returns (uint256, uint256, uint256)", "function shortfalls(address) view returns (uint256)"];
  const comptroller = new ethers.Contract(deployments.MockComptroller, comptrollerAbi, provider);
  
  for (let i = 0; i < 3; i++) {
    const policy = await registry.policies(i);
    const holder = policy[1];
    const liquidity = await comptroller.getAccountLiquidity(holder);
    console.log(`Policy ${i} Holder: ${holder}`);
    console.log(`Holder Shortfall (getAccountLiquidity): ${liquidity[2].toString()}`);
  }
}
main().catch(console.error);
