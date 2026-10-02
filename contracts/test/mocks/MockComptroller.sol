// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockComptroller {
    // Branch B: Minimal Supply/Borrow State
    mapping(address => uint256) public supplied; // ETH collateral (in wei)
    mapping(address => uint256) public borrowed; // USDC debt (in 6 decimals, but let's just use 18 for simplicity)
    
    uint256 public constant ETH_PRICE = 2500 * 1e18; // $2500 USD per ETH
    uint256 public constant MAX_LTV = 80; // 80% LTV

    // Keep the manual override for the "Force Liquidation" button
    bool public hasShortfallOverride;

    function setShortfall(bool _hasShortfall) external {
        hasShortfallOverride = _hasShortfall;
    }

    // Minimal Lending API
    function supply() external payable {
        supplied[msg.sender] += msg.value;
    }

    function borrow(uint256 borrowUsd) external {
        borrowed[msg.sender] += borrowUsd;
    }

    // Standard Comptroller Interface
    function getAccountLiquidity(address account) external view returns (uint256 error, uint256 liquidity, uint256 shortfall) {
        if (hasShortfallOverride) {
            return (0, 0, 50000 * 1e18); // Return a large mock shortfall
        }

        uint256 collateralValueUsd = (supplied[account] * ETH_PRICE) / 1e18;
        uint256 borrowLimitUsd = (collateralValueUsd * MAX_LTV) / 100;
        uint256 currentDebtUsd = borrowed[account];

        if (currentDebtUsd > borrowLimitUsd) {
            // Position is underwater
            return (0, 0, currentDebtUsd - borrowLimitUsd);
        } else {
            // Position is healthy
            return (0, borrowLimitUsd - currentDebtUsd, 0);
        }
    }
}
