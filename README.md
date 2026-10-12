# NoTell

**Zero-knowledge liquidation insurance on Monad testnet (hackathon V1: commitment inputs are public, see ATTACK_SURFACE.md).**

Nobody sees your tell.
*(Note: Complete position privacy is the core design goal of NoTell; our hackathon V1 prototype emits commitment inputs in events for indexing and does not deliver privacy yet. See `ATTACK_SURFACE.md`.)*

---

## The problem

Lending protocols are public by design, and liquidation insurance built on top of them usually is too. Buy cover against your position getting liquidated, and you've just told the network exactly how leveraged you are and where your liquidation threshold sits. That's a standing invitation for targeted price pressure aimed at triggering it.

Insurance that announces your weak spot isn't insurance, it's a bounty poster.

You should be able to hedge that risk without showing your hand.

## The solution

NoTell is a parametric liquidation insurance protocol deployed on Monad testnet. A user buys coverage, and if their position becomes liquidatable, they can claim a parametric payout.

The claim is backed by a Groth16 ZK-SNARK, generated entirely in the browser via a Circom circuit. The proof establishes that an account's committed shortfall is non-zero against an oracle commitment. In this V1 deployment, the keeper emits the commitment inputs in `ClaimWindowOpened` for off-chain indexing; production V2 client-side proving and privacy trade-offs are documented in `ATTACK_SURFACE.md`.

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

**Chainlink — Best workflow with CRE.** As of this submission, Chainlink confirmed directly with us that CRE does not yet support production on-chain writes to Monad testnet, only Monad mainnet. Until that lands, commitments are posted by a keeper script (`one_shot_keeper.js`) that calls `PolicyRegistry.postCommitment()` directly. The CRE workflow targets `CREBridge.onReport()` and was dry-run simulated. Documented in `ATTACK_SURFACE.md`.

**Envio — Best Use of Envio.** The frontend queries a live Envio GraphQL indexer for policy state and claim-window data, with a visible fallback (direct `eth_call` scan) if the indexer is unreachable. The fallback is surfaced to the user, not silently substituted.

**Alchemy — Best Projects using Alchemy.** Our Foundry configuration points at an Alchemy Monad Testnet endpoint, which the keeper and the later deployments used. Some one-off checks used the public Monad RPC. The Envio indexer syncs over RPC because HyperSync needs an auth token we did not have.

## Security posture

The most serious V1 flaw: postCommitment has no access control and no comptroller check, so a policyholder can post fabricated values, prove them, and collect a fixed 10% payout for a 1% premium without holding any position. The commitment inputs are also public in an event. Full details in ATTACK_SURFACE.md.

NoTell's V1 payout is parametric, not an indemnity: any valid proof of a non-zero shortfall pays a fixed amount, `min(notional, k × premiumPaid)`, which at the current premium rate resolves to a fixed 10% of the insured notional, regardless of the real size of the loss. Because the circuit only proves the shortfall is non-zero and never bounds its magnitude, this is currently exploitable: an attacker can insure a large notional, trigger a shortfall on a trivially small position, and collect the full parametric payout.

This is a known, documented limitation of the V1 circuit design, not an oversight. Closing it requires extending the circuit to bind the claimed payout to the real shortfall (`shortfall >= requestedPayout` as a public input), scoped as V2.

Full writeup, including this and twelve other known limitations, in [`ATTACK_SURFACE.md`](./ATTACK_SURFACE.md).

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
cd cre/notell-cre && node one_shot_keeper.js
```

A complete end-to-end claim requires Envio indexing, the Keeper posting commitments, and a connected Monad testnet wallet.

## Deployed contracts (Monad Testnet - Chain ID: 10143)

| Contract | Address |
|---|---|
| `InsurancePool` | `0x9f9dd3a65d39cde4657bab7d100eb93ceffc07e9` |
| `PolicyRegistry` | `0x87fe1f2479be5d332dde97bc649370e300d64c55` |
| `MockComptroller` | `0x3d702b11bb88fac0151714a37414ef90866dcb2e` |
| `CREBridge` | `0xb2eaed1122cd332f46ad9841f6ccf4ee74cf6295` |
| `ClaimVerifier` | `0x65eD7daF272194C27F236722334d20D713f2eF52` |
| `Groth16Verifier` | `0xe525941ceEE47726Ae8cf7329c1fa93b1DAB8374` |

- **Hosted Envio HyperIndex:** `https://indexer.dev.hyperindex.xyz/84dad5e/v1/graphql`
- **Live dApp:** `https://no-tell.vercel.app`

## Verification (Onchain Evidence)

Both Policy 0 and Policy 1 have completed the entire end-to-end lifecycle on Monad testnet, with their 0.1 MON payouts verified onchain:

| Policy | Event / Action | Monad Testnet Block | Transaction Hash | Value |
|---|---|---|---|---|
| **Policy 0** | Policy Issued | 69,883,224 | [`0x49427b7499111ba6d9a1261d3567316a17254ab1653a6c708c6e87a41fc7f9c7`](https://testnet.monadexplorer.com/tx/0x49427b7499111ba6d9a1261d3567316a17254ab1653a6c708c6e87a41fc7f9c7) | 0.01 MON premium (1.0 MON notional) |
| **Policy 0** | Commitment Posted | Round 70,200,851 | [`0x07138da4d6e59dd1a9b4e173ede7566e587cd71a1d489efd1416384ae5048052`](https://testnet.monadexplorer.com/tx/0x07138da4d6e59dd1a9b4e173ede7566e587cd71a1d489efd1416384ae5048052) | Oracle shortfall commitment |
| **Policy 0** | ClaimPaid | 70,201,777 | [`0xd80e750a00be03e9edc9b7721395035654858c2bfbc5dee442334698f6366a2f`](https://testnet.monadexplorer.com/tx/0xd80e750a00be03e9edc9b7721395035654858c2bfbc5dee442334698f6366a2f) | **0.1 MON payout** |
| **Policy 1** | Policy Issued | 69,900,288 | [`0x4e6582169e4a8dcdb4e80c0d9b219346aa2d51f8ac868ecb016da516440493f6`](https://testnet.monadexplorer.com/tx/0x4e6582169e4a8dcdb4e80c0d9b219346aa2d51f8ac868ecb016da516440493f6) | 0.01 MON premium (1.0 MON notional) |
| **Policy 1** | Commitment Posted | Round 70,204,878 | Keeper-posted commitment | Oracle shortfall commitment |
| **Policy 1** | ClaimPaid | 70,205,152 | [`0x425b6d285c597bde3e513aa96448e95e9dd2b8e2d2e265170bdc28e3dd65ddf0`](https://testnet.monadexplorer.com/tx/0x425b6d285c597bde3e513aa96448e95e9dd2b8e2d2e265170bdc28e3dd65ddf0) | **0.1 MON payout** |