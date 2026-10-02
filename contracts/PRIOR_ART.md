# Prior Art: NoTell vs. Nexus Mutual

NoTell is designed to fundamentally rethink the smart contract cover model pioneered by Nexus Mutual. 

While Nexus Mutual is the gold standard for decentralized insurance, its reliance on public subjective consensus introduces significant friction for the end user. NoTell leverages Zero-Knowledge (ZK) proofs to execute parametric claims deterministically, privately, and instantly.

## The Nexus Mutual Model (Subjective Oracle)

Nexus Mutual uses a subjective voting mechanism to verify claims.
1. **The Claim:** A user submits a claim describing their loss.
2. **The Stakers:** Members of the mutual stake NXM tokens to vote on whether the claim is valid.
3. **The Timeline:** Voting takes several days. If consensus isn't reached immediately, escalation processes prolong the payout timeline.
4. **The Privacy Gap:** To convince the voters, the claimant must publicly link their wallet address, their lost position, and the exploit details.

**Pros:** Highly flexible. It can cover novel hacks, smart contract logic bugs, and exploits that cannot be defined parametrically in advance.
**Cons:** Subjective, slow, requires public disclosure, and places the burden of proof (and persuasion) on the victim.

## The NoTell Model (Parametric ZK Execution)

NoTell removes human subjectivity entirely by shifting verification to deterministic cryptography.
1. **The Setup:** A trusted oracle (Chainlink CRE) posts cryptographic commitments of underwater positions to the blockchain.
2. **The Proof:** A user generates a Groth16 ZK proof locally in their browser. This proof mathematically proves they own an underwater position matching a posted commitment, *without revealing which position it is*.
3. **The Execution:** The smart contract verifies the proof in a single transaction and transfers the payout instantly.

**Pros:** 
- **Instant Payouts:** No voting periods. If the proof is valid, the contract pays out in the same block.
- **Privacy-Preserving:** The user's underlying identity and the specific position being covered remain hidden from public observers.
- **Deterministic:** The payout logic is purely mathematical. 

**Cons:** 
- **Rigid:** Can only cover parametrically defined conditions (e.g. `shortfall > 0`). It cannot cover subjective logic bugs or non-quantifiable exploits.
- **Oracle Reliance:** The system trusts the CRE oracle to post accurate commitments. If the oracle goes offline, claims cannot be processed.

## Architectural Trade-offs

| Feature | Nexus Mutual | NoTell |
|---------|-------------|--------|
| **Claim Verification** | Human Voting (Staked Consensus) | Cryptographic Verification (zk-SNARKs) |
| **Payout Timeline** | 2 - 6+ days | Instant (1 block) |
| **Privacy** | Fully Public | Zero-Knowledge |
| **Cover Scope** | Subjective / Open-ended | Parametric / Pre-defined |
| **Trust Model** | Trust the crowd | Trust the Oracle + Math |

NoTell trades the flexibility of human judgment for the speed and privacy of cryptographic execution, carving out a specialized niche for high-speed, privacy-first DeFi insurance.
