const { ethers } = require('ethers');
const fs = require('fs');

async function main() {
  const provider = new ethers.JsonRpcProvider('https://monad-testnet.g.alchemy.com/v2/OOIMS_hWS2oBIZXbMyjTG');
  const deps = JSON.parse(fs.readFileSync('../contracts/deployments/monad-testnet.json'));
  const registry = new ethers.Contract(deps.PolicyRegistry, [
    'function policies(uint256) view returns (address holder, uint256 notional, uint256 premiumPaid, uint256 startBlock, uint256 endBlock, uint8 state)'
  ], provider);
  
  const p = await registry.policies(1);
  console.log('Policy 1 State:', p.state.toString());
  console.log('Policy 1 Holder:', p.holder);
  
  const currentBlock = await provider.getBlockNumber();
  console.log('Start Block:', p.startBlock.toString());
  console.log('End Block:', p.endBlock.toString());
  console.log('Current Block:', currentBlock);
}
main().catch(console.error);
