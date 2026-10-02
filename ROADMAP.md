# ROADMAP.md — NoTell

*Get covered against liquidation without broadcasting how close you were to it.*

Build window: Sep 15 – Oct 13, 2026 (Monad Metropolis, four weeks remaining from plan date)

## Naming note

Working repo name during planning was "position-blind-cover" / PBLC. Project is now **NoTell**. Rename the repo root, README title, and any folder/package names to match before publishing, so the working title and public brand don't drift apart mid-build.

## Target track and bounties

**Track**: Onchain Finance & Trading. Fit is a stretch (no track lists insurance as an example use case), so the submission needs to explicitly bridge the gap rather than assume judges make the connection.

**Bounties (four selected):**
- Chainlink, Best workflow with CRE — committed, this is the strongest fit and the CRE monitoring workflow is core to Week 2
- Envio, Best Use of Envio — committed, LP solvency dashboard depends on the indexer
- Kuru, Bring New Assets and Markets to Kuru — committed, via tokenizing the policy as a tradable position (see Week 2)
- Perpl, Best Analytics / Risk Tool — **conditional**, not in the current stack. Only start this if CRE, Envio, and the Kuru listing are done by end of Week 2. If not, drop it without letting it eat into Week 3's circuit time. This gate exists specifically to protect the Oct 1 checkpoint below.

## Architecture decisions (read before touching code)

- **Groth16 over Plonk/Halo2**: the circuit is small and fixed (single constraint: ratio-below-threshold, bound to a specific oracle round). Groth16's per-circuit trusted setup is an acceptable cost for a circuit that won't change shape, and it gives smaller proofs and cheaper on-chain verification, which matters for gas in a live demo. If the circuit needed to be reconfigurable later, Plonk would be the better call — it doesn't, so Groth16 stays.
- **Single asset, fixed threshold for the MVP**: configurable thresholds multiply the test matrix (every threshold value is a new edge case for adverse-selection and self-inflicted-liquidation tests) for no demo value in the time available.
- **zk circuit gets protected time in Week 3, not leftover time in Week 4**: Nexus Mutual's Leveraged Liquidation Cover is already live and capitalized, so a plaintext-only submission is not competitively differentiated on its own. The circuit is load-bearing for the pitch, not a stretch goal.
- **Prevention (relayer saves a position before public liquidation) was considered and dropped.** It has a hard real-time race condition against professional MEV liquidation bots that doesn't go away whether the save is public or private, and the category (automated liquidation protection) already exists in production (DeFi Saver, Instadapp-style automation). Staying with payout insurance + private zk claims as the core differentiator. Prevention is a possible post-hackathon roadmap item, not in scope here.

## Week 1 (Sep 15–21): plaintext core, oracle-gated

- [ ] `PolicyRegistry.sol` — issue policy, store threshold + notional, track active/expired/claimed state
- [ ] `InsurancePool.sol` — LP deposit/withdraw, premium collection, payout execution, solvency accounting
- [ ] Single Chainlink price feed integration (not CRE yet — that's Week 2). Claim verification checks price at a specific round.
- [ ] Decide the self-inflicted-liquidation payout cap formula *before* writing the contract, not while writing it.
- [ ] Tests: `PolicyLifecycle.t.sol` (main case — buy, hold, expire unclaimed), `AdverseSelection.t.sol` (failure case — position already below threshold rejected at standard pricing), `PoolSolvency.t.sol` (edge case — payout request exceeding pool balance reverts cleanly)
- [ ] Deploy to Monad testnet by end of week

## Week 2 (Sep 22–28): sponsor integrations, in priority order

1. [ ] **Chainlink CRE monitoring workflow** — periodic health-factor check across covered positions, triggers the claim window. Highest-priority bounty ($3,000, direct fit). Budget extra debugging time; CRE tooling is newer with less community documentation than core Solidity.
   - [ ] Failure-case test: monitoring check delayed or misses a block
2. [ ] **Envio indexer** — policy issuance, premiums, claims, feeds LP dashboard + Envio bounty
3. [ ] **Kuru, scoped down** — list the policy as a tradable position on Kuru's order book (fits "Bring New Assets and Markets to Kuru" better than routing premium payments through it). If this slips past Week 2, cut it. A missed bounty costs less than eating into Week 3's circuit time.

## Week 3 (Sep 29–Oct 5): zk circuit — protected time

- [ ] `threshold-crossing.circom` — single constraint, ratio-below-threshold, bound to a specific oracle round (closes stale-proof-replay)
- [ ] Groth16 verifier generation + `ClaimVerifier.sol` integration
- [ ] Tests: `ClaimVerification.t.sol` — main case (valid proof against current round verifies and pays out), failure case (proof from an old round after price recovered is rejected), edge case (proof at the exact threshold boundary)
- [ ] **Checkpoint Oct 1**: if the circuit isn't generating and verifying correctly by here, fall back to specifying it rigorously in docs instead of shipping it broken. Decide this on Oct 1, not Oct 5.
- [ ] Read through the generated verifier code, don't just run it. If you can't explain it back to yourself, that's a problem even if it passes tests.

## Week 4 (Oct 6–13): integration, docs, submission

- [ ] Frontend — policy purchase flow, live health-factor display (`provider.on("block", ...)`), claim submission UI
- [ ] `PRIOR_ART.md` — lead with Nexus Mutual's Leveraged Liquidation Cover and the claims-privacy gap specifically (their model is committee-vote, public, 2–6 day payout; this one is automatic, parametric, private). Not the 2022 protocol as the primary comparison.
- [ ] `ATTACK_SURFACE.md` — finalize, including the self-inflicted-liquidation cap number and correlated-mass-claim risk as a stated known limitation
- [ ] Freeze features **Oct 9**
- [ ] Record demo video by **Oct 11** — two days of buffer before the deadline
- [ ] Submit under Track 01, Onchain Finance & Trading, with the application explicitly bridging the fit gap (liquidation cover priced on real-time health factor vs. their "credit-history-priced lending" example) rather than assuming judges make the connection themselves

## Known open risks, not yet resolved (NoTell)

- Nobody has verified whether another Metropolis team is building something similar — no public evidence found, but the applicant pool isn't publicly searchable, so this is an absence of evidence, not evidence of absence
- Track fit for an insurance product remains a genuine stretch against all four official track descriptions
- Proving time for the Groth16 circuit hasn't been benchmarked yet — measure this early in Week 3, don't assume it's fast enough for a smooth demo# ROADMAP.md — NoTell

*Get covered against liquidation without broadcasting how close you were to it.*

Build window: Sep 15 – Oct 13, 2026 (Monad Metropolis, four weeks remaining from plan date)

## Naming note

Working repo name during planning was "position-blind-cover" / PBLC. Project is now **NoTell**. Rename the repo root, README title, and any folder/package names to match before publishing, so the working title and public brand don't drift apart mid-build.

## Target track and bounties

**Track**: Onchain Finance & Trading. Fit is a stretch (no track lists insurance as an example use case), so the submission needs to explicitly bridge the gap rather than assume judges make the connection.

**Bounties (four selected):**
- Chainlink, Best workflow with CRE — committed, this is the strongest fit and the CRE monitoring workflow is core to Week 2
- Envio, Best Use of Envio — committed, LP solvency dashboard depends on the indexer
- Kuru, Bring New Assets and Markets to Kuru — committed, via tokenizing the policy as a tradable position (see Week 2)
- Perpl, Best Analytics / Risk Tool — **conditional**, not in the current stack. Only start this if CRE, Envio, and the Kuru listing are done by end of Week 2. If not, drop it without letting it eat into Week 3's circuit time. This gate exists specifically to protect the Oct 1 checkpoint below.

## Architecture decisions (read before touching code)

- **Groth16 over Plonk/Halo2**: the circuit is small and fixed (single constraint: ratio-below-threshold, bound to a specific oracle round). Groth16's per-circuit trusted setup is an acceptable cost for a circuit that won't change shape, and it gives smaller proofs and cheaper on-chain verification, which matters for gas in a live demo. If the circuit needed to be reconfigurable later, Plonk would be the better call — it doesn't, so Groth16 stays.
- **Single asset, fixed threshold for the MVP**: configurable thresholds multiply the test matrix (every threshold value is a new edge case for adverse-selection and self-inflicted-liquidation tests) for no demo value in the time available.
- **zk circuit gets protected time in Week 3, not leftover time in Week 4**: Nexus Mutual's Leveraged Liquidation Cover is already live and capitalized, so a plaintext-only submission is not competitively differentiated on its own. The circuit is load-bearing for the pitch, not a stretch goal.
- **Prevention (relayer saves a position before public liquidation) was considered and dropped.** It has a hard real-time race condition against professional MEV liquidation bots that doesn't go away whether the save is public or private, and the category (automated liquidation protection) already exists in production (DeFi Saver, Instadapp-style automation). Staying with payout insurance + private zk claims as the core differentiator. Prevention is a possible post-hackathon roadmap item, not in scope here.

## Week 1 (Sep 15–21): plaintext core, oracle-gated

- [ ] `PolicyRegistry.sol` — issue policy, store threshold + notional, track active/expired/claimed state
- [ ] `InsurancePool.sol` — LP deposit/withdraw, premium collection, payout execution, solvency accounting
- [ ] Single Chainlink price feed integration (not CRE yet — that's Week 2). Claim verification checks price at a specific round.
- [ ] Decide the self-inflicted-liquidation payout cap formula *before* writing the contract, not while writing it.
- [ ] Tests: `PolicyLifecycle.t.sol` (main case — buy, hold, expire unclaimed), `AdverseSelection.t.sol` (failure case — position already below threshold rejected at standard pricing), `PoolSolvency.t.sol` (edge case — payout request exceeding pool balance reverts cleanly)
- [ ] Deploy to Monad testnet by end of week

## Week 2 (Sep 22–28): sponsor integrations, in priority order

1. [ ] **Chainlink CRE monitoring workflow** — periodic health-factor check across covered positions, triggers the claim window. Highest-priority bounty ($3,000, direct fit). Budget extra debugging time; CRE tooling is newer with less community documentation than core Solidity.
   - [ ] Failure-case test: monitoring check delayed or misses a block
2. [ ] **Envio indexer** — policy issuance, premiums, claims, feeds LP dashboard + Envio bounty
3. [ ] **Kuru, scoped down** — list the policy as a tradable position on Kuru's order book (fits "Bring New Assets and Markets to Kuru" better than routing premium payments through it). If this slips past Week 2, cut it. A missed bounty costs less than eating into Week 3's circuit time.

## Week 3 (Sep 29–Oct 5): zk circuit — protected time

- [ ] `threshold-crossing.circom` — single constraint, ratio-below-threshold, bound to a specific oracle round (closes stale-proof-replay)
- [ ] Groth16 verifier generation + `ClaimVerifier.sol` integration# ROADMAP.md — NoTell

*Get covered against liquidation without broadcasting how close you were to it.*

Build window: Sep 15 – Oct 13, 2026 (Monad Metropolis, four weeks remaining from plan date)

## Naming note

Working repo name during planning was "position-blind-cover" / PBLC. Project is now **NoTell**. Rename the repo root, README title, and any folder/package names to match before publishing, so the working title and public brand don't drift apart mid-build.

## Target track and bounties

**Track**: Onchain Finance & Trading. Fit is a stretch (no track lists insurance as an example use case), so the submission needs to explicitly bridge the gap rather than assume judges make the connection.

**Bounties (four selected):**
- Chainlink, Best workflow with CRE — committed, this is the strongest fit and the CRE monitoring workflow is core to Week 2
- Envio, Best Use of Envio — committed, LP solvency dashboard depends on the indexer
- Kuru, Bring New Assets and Markets to Kuru — committed, via tokenizing the policy as a tradable position (see Week 2)
- Perpl, Best Analytics / Risk Tool — **conditional**, not in the current stack. Only start this if CRE, Envio, and the Kuru listing are done by end of Week 2. If not, drop it without letting it eat into Week 3's circuit time. This gate exists specifically to protect the Oct 1 checkpoint below.

## Architecture decisions (read before touching code)

- **Groth16 over Plonk/Halo2**: the circuit is small and fixed (single constraint: ratio-below-threshold, bound to a specific oracle round). Groth16's per-circuit trusted setup is an acceptable cost for a circuit that won't change shape, and it gives smaller proofs and cheaper on-chain verification, which matters for gas in a live demo. If the circuit needed to be reconfigurable later, Plonk would be the better call — it doesn't, so Groth16 stays.
- **Single asset, fixed threshold for the MVP**: configurable thresholds multiply the test matrix (every threshold value is a new edge case for adverse-selection and self-inflicted-liquidation tests) for no demo value in the time available.
- **zk circuit gets protected time in Week 3, not leftover time in Week 4**: Nexus Mutual's Leveraged Liquidation Cover is already live and capitalized, so a plaintext-only submission is not competitively differentiated on its own. The circuit is load-bearing for the pitch, not a stretch goal.
- **Prevention (relayer saves a position before public liquidation) was considered and dropped.** It has a hard real-time race condition against professional MEV liquidation bots that doesn't go away whether the save is public or private, and the category (automated liquidation protection) already exists in production (DeFi Saver, Instadapp-style automation). Staying with payout insurance + private zk claims as the core differentiator. Prevention is a possible post-hackathon roadmap item, not in scope here.

## Week 1 (Sep 15–21): plaintext core, oracle-gated

- [ ] `PolicyRegistry.sol` — issue policy, store threshold + notional, track active/expired/claimed state
- [ ] `InsurancePool.sol` — LP deposit/withdraw, premium collection, payout execution, solvency accounting
- [ ] Single Chainlink price feed integration (not CRE yet — that's Week 2). Claim verification checks price at a specific round.
- [ ] Decide the self-inflicted-liquidation payout cap formula *before* writing the contract, not while writing it.
- [ ] Tests: `PolicyLifecycle.t.sol` (main case — buy, hold, expire unclaimed), `AdverseSelection.t.sol` (failure case — position already below threshold rejected at standard pricing), `PoolSolvency.t.sol` (edge case — payout request exceeding pool balance reverts cleanly)
- [ ] Deploy to Monad testnet by end of week

## Week 2 (Sep 22–28): sponsor integrations, in priority order

1. [ ] **Chainlink CRE monitoring workflow** — periodic health-factor check across covered positions, triggers the claim window. Highest-priority bounty ($3,000, direct fit). Budget extra debugging time; CRE tooling is newer with less community documentation than core Solidity.
   - [ ] Failure-case test: monitoring check delayed or misses a block
2. [ ] **Envio indexer** — policy issuance, premiums, claims, feeds LP dashboard + Envio bounty
3. [ ] **Kuru, scoped down** — list the policy as a tradable position on Kuru's order book (fits "Bring New Assets and Markets to Kuru" better than routing premium payments through it). If this slips past Week 2, cut it. A missed bounty costs less than eating into Week 3's circuit time.

## Week 3 (Sep 29–Oct 5): zk circuit — protected time

- [ ] `threshold-crossing.circom` — single constraint, ratio-below-threshold, bound to a specific oracle round (closes stale-proof-replay)
- [ ] Groth16 verifier generation + `ClaimVerifier.sol` integration
- [ ] Tests: `ClaimVerification.t.sol` — main case (valid proof against current round verifies and pays out), failure case (proof from an old round after price recovered is rejected), edge case (proof at the exact threshold boundary)
- [ ] **Checkpoint Oct 1**: if the circuit isn't generating and verifying correctly by here, fall back to specifying it rigorously in docs instead of shipping it broken. Decide this on Oct 1, not Oct 5.
- [ ] Read through the generated verifier code, don't just run it. If you can't explain it back to yourself, that's a problem even if it passes tests.

## Week 4 (Oct 6–13): integration, docs, submission

- [ ] Frontend — policy purchase flow, live health-factor display (`provider.on("block", ...)`), claim submission UI
- [ ] `PRIOR_ART.md` — lead with Nexus Mutual's Leveraged Liquidation Cover and the claims-privacy gap specifically (their model is committee-vote, public, 2–6 day payout; this one is automatic, parametric, private). Not the 2022 protocol as the primary comparison.
- [ ] `ATTACK_SURFACE.md` — finalize, including the self-inflicted-liquidation cap number and correlated-mass-claim risk as a stated known limitation
- [ ] Freeze features **Oct 9**
- [ ] Record demo video by **Oct 11** — two days of buffer before the deadline
- [ ] Submit under Track 01, Onchain Finance & Trading, with the application explicitly bridging the fit gap (liquidation cover priced on real-time health factor vs. their "credit-history-priced lending" example) rather than assuming judges make the connection themselves

## Known open risks, not yet resolved (NoTell)

- Nobody has verified whether another Metropolis team is building something similar — no public evidence found, but the applicant pool isn't publicly searchable, so this is an absence of evidence, not evidence of absence
- Track fit for an insurance product remains a genuine stretch against all four official track descriptions
- Proving time for the Groth16 circuit hasn't been benchmarked yet — measure this early in Week 3, don't assume it's fast enough for a smooth demo
- [ ] Tests: `ClaimVerification.t.sol` — main case (valid proof against current round verifies and pays out), failure case (proof from an old round after price recovered is rejected), edge case (proof at the exact threshold boundary)
- [ ] **Checkpoint Oct 1**: if the circuit isn't generating and verifying correctly by here, fall back to specifying it rigorously in docs instead of shipping it broken. Decide this on Oct 1, not Oct 5.
- [ ] Read through the generated verifier code, don't just run it. If you can't explain it back to yourself, that's a problem even if it passes tests.

## Week 4 (Oct 6–13): integration, docs, submission

- [ ] Frontend — policy purchase flow, live health-factor display (`provider.on("block", ...)`), claim submission UI
- [ ] `PRIOR_ART.md` — lead with Nexus Mutual's Leveraged Liquidation Cover and the claims-privacy gap specifically (their model is committee-vote, public, 2–6 day payout; this one is automatic, parametric, private). Not the 2022 protocol as the primary comparison.
- [ ] `ATTACK_SURFACE.md` — finalize, including the self-inflicted-liquidation cap number and correlated-mass-claim risk as a stated known limitation
- [ ] Freeze features **Oct 9**
- [ ] Record demo video by **Oct 11** — two days of buffer before the deadline
- [ ] Submit under Track 01, Onchain Finance & Trading, with the application explicitly bridging the fit gap (liquidation cover priced on real-time health factor vs. their "credit-history-priced lending" example) rather than assuming judges make the connection themselves

## Known open risks, not yet resolved (NoTell)

- Nobody has verified whether another Metropolis team is building something similar — no public evidence found, but the applicant pool isn't publicly searchable, so this is an absence of evidence, not evidence of absence
- Track fit for an insurance product remains a genuine stretch against all four official track descriptions
- Proving time for the Groth16 circuit hasn't been benchmarked yet — measure this early in Week 3, don't assume it's fast enough for a smooth demo