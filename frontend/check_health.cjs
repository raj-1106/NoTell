const { ethers } = require('ethers');
const fs = require('fs');

async function main() {
  const provider = new ethers.JsonRpcProvider('https://monad-testnet.g.alchemy.com/v2/OOIMS_hWS2oBIZXbMyjTG');
  const deps = JSON.parse(fs.readFileSync('../contracts/deployments/monad-testnet.json'));
  
  const comptroller = new ethers.Contract(deps.MockComptroller, [
    'function getAccountLiquidity(address) view returns (uint256, uint256, uint256)'
  ], provider);

  const holder = '0xD89E12cb9e6191A0F5b9C1335A21EE7701Fe527F';
  
  const liq = await comptroller.getAccountLiquidity(holder);
  
  console.log('Error:', liq[0].toString());
  console.log('Liquidity:', liq[1].toString());
  console.log('Shortfall:', liq[2].toString());
}
main().catch(console.error);
