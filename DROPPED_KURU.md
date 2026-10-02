# Phase 2c Dropped: Kuru Integration

## Decision

The Kuru integration (Phase 2c), which aimed to "list the policy as a tradable position on Kuru's order book," is formally dropped from the NoTell project scope. 

Per the `ROADMAP.md` explicit escape hatch: *"If this slips past Week 2, cut it. A missed bounty costs less than eating into Week 3's circuit time."* 

While we currently have a 20-day schedule buffer because we executed Phase 3 ahead of schedule, the decision to drop Kuru is not based on time constraints, but on **architectural incompatibility and protocol safety**.

## Rationale

### 1. The ERC20 vs. Non-Fungible Mismatch
Kuru is an on-chain Central Limit Order Book (CLOB) designed for trading fungible ERC20 tokens. A NoTell insurance policy is intrinsically non-fungible. Every policy has a bespoke `notional` value, a specific `endBlock` expiry, and is uniquely tied to the underlying Peridot position of the purchaser. 
Listing a non-fungible asset on an ERC20 spot order book is technically incoherent without fractionalizing a single policy into its own isolated ERC20 token, which would have zero liquidity and no real market.

### 2. The Adverse Selection Loophole
To make a policy tradable on a secondary market, we would have to tokenize `PolicyRegistry` (e.g., upgrading it to an ERC721). This introduces transferability, which violently breaks our core security model.
The Phase 1 design explicitly built a **Q1 binary exclusion zone**: `buyPolicy` checks if `msg.sender` is already liquidatable before issuing the policy. 
If a policy can be transferred, who is the `holder`? 
- **If the `holder` dynamically updates to the new owner:** A user who is already underwater could simply buy an active policy on the secondary market, entirely bypassing the Q1 health check at purchase time.
- **If the `holder` remains statically bound to the original minter (The CDS Model):** The secondary buyer is no longer buying insurance for themselves; they are buying a Credit Default Swap (CDS) betting on the original minter's liquidation. While a fascinating DeFi primitive, this would require a massive foundational refactor of `PolicyRegistry.sol` and `InsurancePool.sol` to decouple the `insuredAccount` from the `payoutRecipient`, completely invalidating the rigorous E2E testing and Phase 3 verifications we just sealed.

### 3. Conditional Bounties Closed
Because the Perpl bounty was strictly gated behind the successful completion of the CRE, Envio, and Kuru integrations, dropping Kuru officially drops the Perpl integration as well. 

## Conclusion
We are sacrificing the Kuru bounty to maintain the structural integrity and security of the core insurance protocol. Specifically, this rules out **transferable claim positions** due to the adverse-selection loophole they introduce. While it would be architecturally safe to list fungible `InsurancePool` LP shares on Kuru instead, pivoting the scope to build a custom LP-token market this late in Phase 2 cuts against our commitment to disciplined pacing.

The 20-day schedule buffer will be exclusively dedicated to Phase 4: building a high-fidelity frontend, finalizing the `ATTACK_SURFACE.md` documentation, and executing the live Oct 10 demo.
