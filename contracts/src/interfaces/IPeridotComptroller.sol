// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPeridotComptroller
/// @notice Minimal interface for the Peridot Finance Comptroller (Compound v2-style).
///
/// Peridot is the only DeFi::Lending protocol on Monad testnet as of the Phase 2
/// build date (Sep 2026). Aave V3.7 is live on Monad mainnet only.
///
/// Testnet deployment (chain ID 10143, from monad-crypto/protocols registry):
///   UnitrollerProxy: 0xa41D586530BC7BC872095950aE03a780d5114445
///
/// Architecture note: Peridot follows the Compound v2 pattern, NOT Aave v3.
///   - There is NO getUserAccountData(address) → (collateral, debt, ...) call.
///   - Health is expressed as (liquidity, shortfall) in absolute USD (1e18 scale),
///     not as a scale-invariant percentage ratio.
///   - A healthy position has liquidity > 0, shortfall == 0.
///   - A liquidatable position has shortfall > 0, liquidity == 0.
///
/// ZK commitment scheme (Phase 3):
///   commitments[policyId][block] = Poseidon(liquidity, shortfall, block.number)
///   The circuit proves shortfall > 0 at the committed block.
interface IPeridotComptroller {
    /// @notice Determine the current account health for `account`.
    /// @return error     0 on success, non-zero on comptroller error.
    /// @return liquidity Excess collateral above minimum required (USD, 1e18 scale).
    ///                   Non-zero only when shortfall == 0.
    /// @return shortfall Collateral deficit below minimum required (USD, 1e18 scale).
    ///                   Non-zero when position is liquidatable.
    function getAccountLiquidity(address account)
        external
        view
        returns (uint256 error, uint256 liquidity, uint256 shortfall);
}
