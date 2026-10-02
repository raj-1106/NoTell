// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAavePool
/// @notice Minimal interface over Aave v3 Pool for reading account health data.
///         Only `getUserAccountData` is needed — no write paths required.
///         Aave v3.7 is live on Monad mainnet (deployed July 2, 2026).
///
///         Full return values:
///           totalCollateralBase    — total collateral in USD, 8 decimals
///           totalDebtBase          — total debt in USD, 8 decimals
///           availableBorrowsBase   — remaining borrow capacity in USD, 8 decimals
///           currentLiquidationThreshold — weighted avg liquidation threshold, basis points
///           ltv                    — weighted avg loan-to-value ratio, basis points
///           healthFactor           — position health factor, 18 decimals (< 1e18 = liquidatable)
///
///         For the NoTell commitment: we use `totalCollateralBase` and `totalDebtBase`
///         as the raw inputs to Poseidon(collateral, debt, block.number).
///         The circuit checks `collateral * 100 < threshold * debt`, consistent with
///         `threshold` stored as a ×100 integer (e.g. 150 = 150% ratio).
interface IAavePool {
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
}
