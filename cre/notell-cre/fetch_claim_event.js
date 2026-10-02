const { JsonRpcProvider, Contract, id } = require('ethers');

async function main() {
    const provider = new JsonRpcProvider('https://testnet-rpc.monad.xyz/');
    const address = '0xEc64c7aF444f6b44f61a140363fA406141fAfde8';
    
    // ClaimPaid(uint256 indexed policyId, address indexed recipient, uint256 amount)
    const topic0 = id("ClaimPaid(uint256,address,uint256)");
    const policy1Topic = "0x0000000000000000000000000000000000000000000000000000000000000001";
    
    console.log("Scanning for ClaimPaid event for Policy 1...");
    
    // We know the claim happened shortly after the commitment at 66939339
    let startBlock = 66939000;
    let endBlock = 66949000; 
    let current = startBlock;
    
    while (current < endBlock) {
        let toBlock = Math.min(current + 99, endBlock);
        
        try {
            const logs = await provider.getLogs({
                address: address,
                fromBlock: current,
                toBlock: toBlock,
                topics: [topic0, policy1Topic]
            });
            
            if (logs.length > 0) {
                console.log("FOUND CLAIM EVENT!");
                console.log("Transaction Hash:", logs[0].transactionHash);
                console.log("Block Number:", logs[0].blockNumber);
                
                // The amount is the non-indexed data (the only data field)
                // parse the hex string to bigint
                const amount = BigInt(logs[0].data);
                console.log("Payout Amount (wei):", amount.toString());
                console.log("Payout Amount (ETH):", (Number(amount) / 1e18).toString());
                return;
            }
            
            process.stdout.write(`\rScanned up to block ${toBlock}...`);
        } catch (e) {
            // retry logic if rate limited
            await new Promise(r => setTimeout(r, 500));
            continue;
        }
        current = toBlock + 1;
    }
    console.log("\nNot found in range.");
}

main().catch(console.error);
