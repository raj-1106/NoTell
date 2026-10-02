# NoTell Attack Surface and Accepted Gaps

This document tracks known security boundaries, threat models, and explicitly accepted gaps in the NoTell product architecture.

## 1. Deploy-Time Trust Window
**The Mechanism:** The `PolicyRegistry` constructor captures `msg.sender` as the `deployer`. The `setInsurancePool`, `setPoseidon`, and `setCREAddress` functions are restricted to this `deployer` address.
**Why it is accepted:** This is a one-time setup step documented in Phase 1. Once all three setters have been called, the `deployer` has no further special privileges, freezing the trust window. Users verifying the contracts must check that these setters have already been executed and cannot be called again before trusting the policy issuance logic.

## 2. Flat Premium Pricing
**The Mechanism:** All policies cost exactly `PREMIUM_BPS` (100 bps or 1%) of the chosen notional amount, regardless of how close the Peridot position is to liquidation.
**Why it is accepted:** Discussed in Q2 of the Phase 1 design. This is a known limitation of the MVP model to keep the contracts simple. The "binary exclusion zone" (Q1) prevents buying a policy for an already-underwater position, which is the baseline defense.

## 3. Chainlink CRE Forwarder Spoofing
**The Mechanism:** The `CREBridge` contract accepts any call from the Monad Testnet Chainlink `KeystoneForwarder`. Because there is only one Forwarder per chain shared by all CRE workflows, any other team deploying a workflow on the same testnet could route a payload to our `CREBridge.onReport` function.
**Why it is accepted:** The risk is constrained by two factors:
1. The random payload must decode into a valid `uint256[]` without reverting.
2. Even if it succeeds, `checkHealthFactors` is safe to call arbitrarily. It cannot inject false data or force an invalid commitment.
**Future Mitigation:** The bridge must be updated to decode and verify `workflowOwner` and `workflowName` identifiers explicitly.

## 3b. TEMPORARY: Centralized Keeper Fallback
**The Mechanism:** Due to Chainlink manual review delays for live deployment access on the Monad testnet, the `PolicyRegistry.creAddress` is temporarily pointed directly at the `deployer` EOA wallet. A local Node.js Keeper script uses the deployer private key to poll the Comptroller and call `checkHealthFactors`.
**Why it is accepted:** This is strictly an emergency unblocker to allow the end-to-end ZK claim flow to be tested and demoed. 
**Future Mitigation:** Once Chainlink approves the deployment, this script will be killed and `creAddress` will be restored to the decentralized `CREBridge`.

## 4. Cron Gas Scaling
**The Mechanism:** The Chainlink CRE workflow queries `nextPolicyId` and iterates over every policy ever issued in every 5-minute poll.
**Why it is accepted:** For a hackathon demo, the number of policies issued will remain small (under 100), meaning the gas cost easily stays within the Chainlink Forwarder's block limit.

## 5. Self-Inflicted Cap Limits
**The Mechanism:** The `MAX_PAYOUT_RATIO` mathematically caps the claim payout to 10% of the policy's notional value. This creates a hard ceiling on the financial reward a user can extract from the pool.
**Why it is accepted:** This is the primary defense against self-inflicted liquidations. Without this cap, a user could take out a massive policy, intentionally collapse their Peridot position, and drain the insurance pool for profit. Capping the payout at 10% ensures that the capital lost in the Peridot liquidation strictly exceeds the insurance payout, breaking the economic incentive to attack the protocol.

## 6. Mass-Claim Liquidity Risks
**The Mechanism:** The `InsurancePool` is not technically "isolated" per policy. It relies on a pooled liquidity model where premiums and underwriter capital sit in a single contract balance. If a systemic event causes massive simultaneous Peridot liquidations, a correlated mass-claim event could occur.
**Why it is accepted:** If total valid claims exceed the `InsurancePool` balance, late claimers will encounter a `transfer` revert until more capital is injected (via premiums or LP deposits). This is a known liquidity limit of V1. The 24-hour holding period staggers the claim window, but does not solve the fundamental capital-efficiency problem of under-collateralized insurance. 
