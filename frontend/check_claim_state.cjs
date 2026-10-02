const { ethers } = require('ethers');
const fs = require('fs');

async function main() {
  const provider = new ethers.JsonRpcProvider('https://monad-testnet.g.alchemy.com/v2/OOIMS_hWS2oBIZXbMyjTG');
  const deps = JSON.parse(fs.readFileSync('../contracts/deployments/monad-testnet.json'));
  
  const registry = new ethers.Contract(deps.PolicyRegistry, [
    'function policies(uint256) view returns (address holder, uint256 notional, uint256 premiumPaid, uint256 startBlock, uint256 endBlock, uint8 state)',
    'function commitments(uint256, uint256) view returns (uint256)'
  ], provider);
  
  const comptroller = new ethers.Contract(deps.MockComptroller, [
    'function getAccountLiquidity(address) view returns (uint256, uint256, uint256)',
    'function hasShortfallOverride() view returns (bool)'
  ], provider);

  const policyId = 1; // Assuming policy 1
  const block = 66396622;

  const p = await registry.policies(policyId);
  console.log('Holder:', p.holder);
  
  const commitment = await registry.commitments(policyId, block);
  console.log('Commitment at', block, ':', commitment.toString());
  
  const liq = await comptroller.getAccountLiquidity(p.holder, { blockTag: block });
  console.log('Liquidity at', block, ':', liq[1].toString(), 'Shortfall:', liq[2].toString());
  
  const override = await comptroller.hasShortfallOverride({ blockTag: block });
  console.log('Override at', block, ':', override);
}
main().catch(console.error);
