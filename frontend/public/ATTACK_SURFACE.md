# NoTell Attack Surface & Security Posture

This document outlines the known cryptographic limitations and attack vectors in NoTell V1, specifically regarding the zero-knowledge verification mechanisms, and the scoped upgrades for V2.

## 1. The Parametric "Dummy Position" Exploit (ZK Bounding Gap)

### The Structural Gap
In NoTell V1, the Groth16 circuit (`shortfall.circom`) is designed to prove that an account's shortfall is non-zero (`shortfall != 0`) without revealing the exact numeric value of the shortfall or the position size. This was implemented using Circom's `IsZero` template to enforce absolute privacy.

Because the ZK proof only verifies the *existence* of a shortfall and not its magnitude, the `InsurancePool` smart contract has no cryptographic guarantee that the claimed payout bears any proportional relationship to the real economic loss. 

To handle claims without knowing the exact loss, V1 uses a deterministic, parametric payout structure where the cap is derived mechanically: `maxPayout = 10 * premiumPaid`. Because the premium is strictly enforced at 1% of the chosen notional (`premium = notional * 0.01`), the payout cap is mathematically locked to exactly 10% of notional (`10 * 0.01 * notional = notional / 10`) for every single policy.

### The Attack Vector
This parametric decoupling between actual loss and payout makes the contract vulnerable to intentional dummy-liquidations. Because the `ClaimVerifier` strictly checks that the ZK shortfall commitment belongs to the specific `policyId` being claimed against, an attacker must manipulate the health factor of the *exact same wallet address* that holds the policy:

1. An attacker uses their primary wallet to buy a massive insurance policy (e.g., 50,000 ETH notional, paying a 500 ETH premium). This locks in a maximum payout cap of 5,000 ETH (`500 * 10`).
2. The attacker uses that *exact same wallet address* to open a tiny, isolated "dummy" position on the money market (e.g., supplying $20 of collateral and borrowing $15).
3. The attacker intentionally lets the $20 dummy position become undercollateralized (shortfall > 0).
4. The keeper bot generates a valid ZK proof using the wallet's dummy position commitment hash. Since the dummy position lives on the same address that owns the policy, the commitment perfectly binds to the `policyId`. 
5. The attacker submits the proof to claim the massive 5,000 ETH payout.

Because the circuit only proves `shortfall != 0`, the verifier accepts the proof. The smart contract, completely blind to the fact that the actual loss was only $5, pays out the fixed 5,000 ETH parametric cap. **The attacker always nets exactly 10% of whatever notional they bought, regardless of the real loss.** This allows them to drain the pool's LPs for massive profit at virtually zero cost.

### V2 Cryptographic Fix
This cannot be patched with Solidity parameter tweaks (such as letting the user choose their own premium or cap) because the gap is structural within the circuit constraints. No matter how the cap is calculated on-chain, as long as the payout is decoupled from the verified loss, the exploit remains profitable.

The V2 fix requires extending the ZK circuit to prove a numerical bound. The user must provide their `requestedPayout` as a public input to the circuit. 
The circuit must enforce a comparative constraint:
`shortfall >= requestedPayout` 
(or a similar bounding constraint relative to the exact liquidation penalty mechanics).

This cryptographic bound ensures the user can only claim up to their actual economic loss, definitively neutralizing the dummy position exploit while still keeping the exact position size mathematically concealed behind the zero-knowledge proof.
