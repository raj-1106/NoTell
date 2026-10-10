# NoTell

**Zero-knowledge private liquidation insurance on Monad testnet.**

Nobody sees your tell.

---

## The problem

Lending protocols are public by design, and liquidation insurance built on top of them usually is too. Buy cover against your position getting liquidated, and you've just told the network exactly how leveraged you are and where your liquidation threshold sits. That's a standing invitation for targeted price pressure aimed at triggering it.

Insurance that announces your weak spot isn't insurance, it's a bounty poster.

You should be able to hedge that risk without showing your hand.

## The solution

NoTell is a parametric liquidation insurance protocol deployed on Monad testnet. A user buys coverage, and if their position becomes liquidatable, they can claim a payout, privately. The chain learns that a hand was played and that it was a winner. It never learns the cards.

The claim is backed by a Groth16 ZK-SNARK, generated entirely in the browser via a Circom circuit. The proof establishes that a committed shortfall is non-zero, without ever revealing the user's collateral, debt, or exact liquidation threshold on-chain. `InsurancePool` verifies the proof and releases the payout without ever learning the underlying numbers.

## Architecture

| Path | Contents |
|---|---|
| `contracts/` | Foundry project: `PolicyRegistry` (policy lifecycle, oracle commitments), `InsurancePool` (LP capital, claim verification, payout), `ClaimVerifier` (Groth16 adapter), `CREBridge` (Chainlink receiver), `MockComptroller` (simulated lending market, see note below) |
| `circuits/` | Circom circuit proving a committed shortfall is non-zero, bound to a commitment posted on-chain by the oracle |
| `frontend/` | React + Vite dApp; in-browser proof generation via snarkjs/WASM |
| `indexer/` | Envio indexer tracking policy, pool, and claim state |
| `cre/notell-cre/` | Chainlink CRE workflow and the live fallback (see below) |

`MockComptroller` exists because no Compound-style lending protocol with a `getAccountLiquidity`-equivalent interface is currently live on Monad testnet. Full detail in `ATTACK_SURFACE.md`.

The protocol's time-based parameters (`HOLDING_PERIOD`, `MAX_PROOF_AGE_BLOCKS`) are expressed in blocks, not seconds. Monad testnet's measured block time at the time of deployment was approximately 309ms, giving a `HOLDING_PERIOD` of 288,000 blocks a real-world duration of roughly 25 hours, not the 24 hours a 300ms assumption would suggest. Even the house rules run a little long here.

## Bounties targeted

**Track 01 — Onchain Finance & Trading.** NoTell prices and caps risk the same way other financial primitives in this track do: liquidation exposure priced at purchase, a bounded payout at claim time.

**Chainlink — Best workflow with CRE.** We built and simulation-verified a CRE workflow targeting `CREBridge.onReport()`, confirmed against the Forwarder address for Monad testnet. As of this submission, Chainlink confirmed directly with us that CRE does not yet support production on-chain writes to Monad testnet, only Monad mainnet. Until that lands, live commitment-posting runs through `run_keeper.js`, which performs the identical on-chain call (`checkHealthFactors`) the CRE DON would make. Documented in `ATTACK_SURFACE.md`.

**Envio — Best Use of Envio.** The frontend queries a live Envio GraphQL indexer for policy state and claim-window data, with a visible fallback (direct `eth_call` scan) if the indexer is unreachable. The fallback is surfaced to the user, not silently substituted.

**Alchemy — Best Projects using Alchemy.** The keeper and the Envio indexer sync use Alchemy RPC endpoints. Some one-off checks and earlier local runs used the public Monad RPC.

## Security posture

NoTell's V1 payout is parametric, not an indemnity: any valid proof of a non-zero shortfall pays a fixed amount, `min(notional, k × premiumPaid)`, which at the current premium rate resolves to a fixed 10% of the insured notional, regardless of the real size of the loss. Because the circuit only proves the shortfall is non-zero and never bounds its magnitude, this is currently exploitable: an attacker can insure a large notional, trigger a shortfall on a trivially small position, and collect the full parametric payout.

This is a known, documented limitation of the V1 circuit design, not an oversight. Closing it requires extending the circuit to bind the claimed payout to the real shortfall (`shortfall >= requestedPayout` as a public input), scoped as V2.

Full writeup, including this and three other known limitations, in [`ATTACK_SURFACE.md`](./ATTACK_SURFACE.md).

## Running locally

Deal yourself in:

```bash
# Contracts
cd contracts && forge test

# Indexer (requires Docker)
cd indexer && docker compose up -d

# Frontend
cd frontend && npm run dev

# Keeper (posts oracle commitments; required for a full local claim)
cd cre/notell-cre && node run_keeper.js
```

A complete end-to-end claim requires Docker running (Envio), the Keeper running (commitment posting), and a wallet connected to Monad testnet. No wallet, no seat at the table.

## Deployed contracts

See `deployments/monad-testnet.json` for current addresses on Monad testnet.