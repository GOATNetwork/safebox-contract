// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IBitcoin} from "../interfaces/IBitcoin.sol";
import {IBridge} from "../interfaces/IBridge.sol";

contract MockBitcoin is IBitcoin {
    function blockHash(uint256 height) external view returns (bytes32) {
        return 0;
    }
}

contract MockBridge is IBridge {
    function isDeposited(bytes32, uint32) external pure returns (bool) {
        return true;
    }
}
