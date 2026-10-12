# NoTell Attack Surface & Security Posture

This document outlines the known cryptographic limitations, architectural trade-offs, and attack vectors in NoTell V1, along with the scoped upgrades for production V2.

---

## 1. Primary Vulnerability: Unauthenticated `postCommitment` (Free Payout Forgery)

### The Structural Vulnerability
In the deployed V1 `PolicyRegistry`, the `postCommitment` entry point has no caller access control (`msg.sender` check), no signature verification from an oracle network, and no on-chain read from the lending market comptroller:

```solidity
function postCommitment(
    uint256 policyId,
    uint256 roundId,
    uint256 liquidity,
    uint256 shortfall,
    uint256 commitment
) external {
    Policy storage p = policies[policyId];
    if (p.state != PolicyState.Active) revert PolicyNotActive(policyId);
    require(shortfall > 0, "No shortfall: position is healthy");

    commitments[policyId][roundId] = commitment;
    emit ClaimWindowOpened(policyId, roundId, liquidity, shortfall);
}
```

### The Exploit Vector
1. Any actor buys cover for a 1% premium (e.g. paying 0.01 MON for a 1.0 MON policy).
2. The actor waits out the 288,000-block holding period (~25 hours on Monad testnet).
3. The actor computes off-chain a Poseidon hash for arbitrary fabricated values (e.g., `liquidity = 0, shortfall = 1000`) and calls `postCommitment` directly with `shortfall > 0`.
4. The actor generates a valid Groth16 proof matching those fabricated values and calls `processClaim`.
5. The `InsurancePool` verifies the proof against the stored commitment and releases the fixed 10% payout (0.1 MON).

**Result:** A policyholder can extract 10% of notional for a 1% premium without maintaining any collateral or borrowing position on a lending market. This completely subsumes the dummy-position exploit below.

---

## 2. Public Event Inputs: Cleartext Disclosure in V1

In NoTell V1, `ClaimWindowOpened` emits `liquidity` and `shortfall` in plaintext:

```solidity
emit ClaimWindowOpened(policyId, roundId, liquidity, shortfall);
```

### Implications
- In this V1 deployment, health factor deltas are public on-chain in event logs, allowing any observer to inspect the account's state and recompute the Poseidon commitment.
- The browser frontend reads these values from the Envio indexer to construct the ZK witness without requiring archive RPC nodes on Monad testnet.
- Consequently, V1 does **not** hide health factors or shortfall numbers from observers. Complete privacy requires client-side proof generation with DON multi-signatures directly over the commitment hash.

---

## 3. The Parametric "Dummy Position" Exploit (ZK Bounding Gap)

### The Gap
The Groth16 circuit (`shortfall.circom`) proves only that `shortfall != 0`, not its quantitative magnitude.
Because V1 pays a fixed parametric multiple `min(notional, 10 * premiumPaid)` (10% of notional), an attacker with a real undercollateralized position of just $1 can claim against a $1,000,000 policy held on the same address.

### Mitigation in V2
Extending the circuit constraints so that `requestedPayout` is a public input and the circuit enforces `shortfall >= requestedPayout`.

---

## 4. Additional Deployed Contract Limitations (V1)

1. **No on-chain persistence check:** The contract does not enforce a two-consecutive-poll persistence check; a single keeper transaction opens the claim window.
2. **Keeper-computed commitments:** The Poseidon hash is calculated off-chain by the keeper bot, not in an on-chain precompile or circuit contract.
3. **Overwriteable commitments (griefing):** A second call to `postCommitment` for the same `(policyId, roundId)` overwrites the stored commitment, allowing griefing against in-flight proof submissions.
4. **Uninitialized policy ID acceptance (indexer poisoning):** Uninitialized mapping entries default to enum index 0 (`PolicyState.Active`), so arbitrary policy IDs can have commitments posted to pollute indexer state.
5. **Unchecked `roundId` freshness:** Any arbitrary `uint256` is accepted as `roundId` without checking against recent block numbers.
6. **ABI-stable stub on `checkHealthFactors`:** `CREBridge` calls `checkHealthFactors`, which is an empty no-op stub on this registry deployment.
7. **Chainlink CRE cannot write to Monad testnet:** Chainlink's release notes list production onchain writes for Monad mainnet and local simulation only for testnet. A CRE simulation against Monad testnet did not reach a completed write in our testing. Commitments are posted by a keeper script, and CREBridge currently calls a no-op stub (item 6), so CRE does not drive the claim path in this deployment.
8. **Correlated claims can drain the pool:** There is no utilization-based pricing or tranching. A shock that produces many valid claims can exceed pool assets.
9. **Deploy-time setter window:** One-time setters (insurance pool, CRE address, Poseidon, claim verifier) leave a deploy-time window in which the deployer chooses the addresses. After that window closes, changing them requires a redeploy.
10. **buyPolicy does not require durationBlocks to exceed HOLDING_PERIOD:** A policy bought with durationBlocks equal to the holding period expires at the block it becomes claimable.
11. **Mock lending market:** The lending market is a mock (`MockComptroller`), because no Compound-style market with a `getAccountLiquidity` interface was live on Monad testnet.
12. **Historical state requests returned HTTP 503:** Our requests for state at blocks roughly 100,000 blocks old returned HTTP 503 on the Alchemy endpoint. We did not establish why.

---

## 5. Formal Test Suite

These behaviors are formally covered by Foundry unit tests in [`contracts/test/PostCommitment.t.sol`](./contracts/test/PostCommitment.t.sol) (31/31 passing tests), documenting current V1 behavior and edge cases.
