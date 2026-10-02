// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoseidon} from "../../src/interfaces/IPoseidon.sol";

contract MockPoseidon is IPoseidon {
    function poseidon(uint256[3] calldata inputs) external pure returns (uint256) {
        return uint256(keccak256(abi.encode(inputs[0], inputs[1], inputs[2])));
    }
}
