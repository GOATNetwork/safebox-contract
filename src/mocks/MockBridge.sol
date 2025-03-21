// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IBridge} from "../interfaces/IBridge.sol";

contract MockBridge is IBridge {
    function isDeposited(bytes32, uint32) external pure returns (bool) {
        return true;
    }
}
