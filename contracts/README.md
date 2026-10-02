# NoTell — Smart Contracts

Private liquidation insurance for Monad Metropolis.

## Overview

Two contracts, one interface each, no proxies.

| Contract | Role |
|---|---|
| `PolicyRegistry.sol` | Issues policies, enforces purchase-time exclusion zone (Q1), forwards premiums, stores CRE-posted commitments (Phase 2+) |
| `InsurancePool.sol` | ERC-4626-style LP pool, collects premiums, processes claims with Q4 cap, pluggable ZK verifier slot (Phase 3) |
| `IChainlinkFeed.sol` | Thin oracle interface — injectable via `vm.mockCall` in tests |
| `IClaimVerifier.sol` | ZK verifier interface — zero address in Phase 1, wired in Phase 3 |

## Design decisions baked in

| Decision | Value | File |
|---|---|---|
| Q1 exclusion zone | ratio ≥ threshold + 20pp at purchase | `PolicyRegistry.EXCLUSION_BUFFER` |
| Q2 flat premium | 1% of notional (100 bps) | `PolicyRegistry.PREMIUM_BPS` |
| Q3 expiry | block-based (`block.number + N`) | `PolicyRegistry.Policy.endBlock` |
| Q4 payout cap | `K=10 × premiumPaid` (≈10% notional at 1% premium) | `InsurancePool.K_PAYOUT_MULTIPLE` |
| Q4 holding period | 288,000 blocks (~25h at 309ms/block — verify testnet RPC) | `InsurancePool.HOLDING_PERIOD` |
| Pool-wide solvency cap | 80% of totalAssets per payout | `InsurancePool.MAX_UTILIZATION` |
| Reserve floor | 1 ETH always kept in pool | `InsurancePool.MIN_RESERVE` |

`ratioAtPurchase` is **not stored** — it would leak the collateral/debt data the privacy design exists to hide.

## Install & test

`contracts/lib/` is vendored directly in the repo — no install step needed on a clean clone.

```bash
# Build (from contracts/)
forge build

# Run tests — 20 tests, 4 suites
forge test -vv
```

If you need to re-install dependencies from scratch (e.g. after manually deleting `lib/`):

```bash
# These are the exact commands that originally populated lib/
forge install foundry-rs/forge-std --no-git
forge install smartcontractkit/chainlink-brownie-contracts --no-git
```

> `forge install` with no arguments does nothing here — there is no `.gitmodules` file.
> The `--no-git` flag is required because the original installs didn't create submodule metadata.

## Deploy (Monad testnet)

```bash
export DEPLOYER_PK=<your-key>
export MONAD_RPC_URL=<rpc>
export CHAINLINK_FEED=<feed-address>
export MONAD_ETHERSCAN_KEY=<key>
export MONAD_EXPLORER_URL=<explorer-url>

forge script script/Deploy.s.sol --rpc-url monad_testnet --broadcast --verify
```

Post-deploy: commit the two addresses to `deployments/monad-testnet.json` for the indexer and frontend.

## Trust assumptions

- **Deployer**: controls `setInsurancePool()` and `setClaimVerifier()` — two one-time initializers — during the deploy transaction. Both are guarded to `deployer` (captured at construction).
- **CRE (Phase 2+)**: the only writer of `commitments[policyId][blockNumber]`. A compromised CRE can post a false commitment; there is no cryptographic mitigation at this layer. Named in `ATTACK_SURFACE.md`.

## Phase status

| Phase | Scope | Status |
|---|---|---|
| 1 — Plaintext core | Contracts + 20 tests | ✅ Complete (`phase1-complete`) |
| 2 — CRE + Envio | `checkHealthFactors`, indexer schema | Not started |
| 3 — ZK circuit | Circom, `ClaimVerifier.sol`, proof integration | Not started |
| 4 — Frontend + polish | UI, Kuru/Perpl integrations, `ATTACK_SURFACE.md` | Not started |
