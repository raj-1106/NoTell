// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PolicyRegistry} from "./PolicyRegistry.sol";

interface IReceiver {
  function onReport(bytes calldata metadata, bytes calldata report) external;
}

/// @title CREBridge
/// @notice Receives signed consensus reports from the Chainlink CRE DON and
///         forwards the extracted policy IDs to the PolicyRegistry.
contract CREBridge is IReceiver {
    PolicyRegistry public immutable registry;
    address public immutable forwarder;

    error Unauthorized();

    constructor(address _forwarder, address _registry) {
        forwarder = _forwarder;
        registry = PolicyRegistry(_registry);
    }

    function onReport(bytes calldata /* metadata */, bytes calldata report) external override {
        if (msg.sender != forwarder) revert Unauthorized();
        uint256[] memory policyIds = abi.decode(report, (uint256[]));
        registry.checkHealthFactors(policyIds);
    }
}
