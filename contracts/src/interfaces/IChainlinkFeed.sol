// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IChainlinkFeed
/// @notice Thin injectable wrapper over AggregatorV3Interface.
///         Declared as an interface so tests can inject a mock via vm.mockCall
///         without pulling in the full Chainlink dependency.
interface IChainlinkFeed {
    /// @notice Returns the latest round data from the price feed.
    /// @return roundId       The round ID.
    /// @return answer        The price (8 decimals for USD feeds).
    /// @return startedAt     Timestamp when the round started.
    /// @return updatedAt     Timestamp when the round was last updated.
    /// @return answeredInRound The round ID in which the answer was computed.
    function latestRoundData()
        external
        view
        returns (
            uint80  roundId,
            int256  answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80  answeredInRound
        );

    /// @notice Returns data for a specific historical round.
    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80  roundId,
            int256  answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80  answeredInRound
        );
}
