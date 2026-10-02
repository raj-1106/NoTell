const { ethers } = require('ethers');
const fs = require('fs');

async function main() {
  const provider = new ethers.JsonRpcProvider('https://monad-testnet.g.alchemy.com/v2/OOIMS_hWS2oBIZXbMyjTG');
  const deps = JSON.parse(fs.readFileSync('../contracts/deployments/monad-testnet.json'));
  
  const comptroller = new ethers.Contract(deps.MockComptroller, [
    'function supplied(address) view returns (uint256)',
    'function borrowed(address) view returns (uint256)',
    'function hasShortfallOverride() view returns (bool)'
  ], provider);

  const holder = '0xD89E12cb9e6191A0F5b9C1335A21EE7701Fe527F';
  
  const sup = await comptroller.supplied(holder);
  const bor = await comptroller.borrowed(holder);
  const over = await comptroller.hasShortfallOverride();
  
  console.log('Supplied:', sup.toString());
  console.log('Borrowed:', bor.toString());
  console.log('Override:', over);
}
main().catch(console.error);
