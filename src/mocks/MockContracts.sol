// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IBitcoin} from "../interfaces/IBitcoin.sol";
import {IBridge} from "../interfaces/IBridge.sol";

contract MockBitcoin is IBitcoin {
    function blockHash(uint256) external view returns (bytes32) {
        return
            0x7b51798b5df7f949a45ec16fa2160b6ef30d9870bfc6345bc9b4e1a4e22b986d;
    }
}

contract MockBridge is IBridge {
    function isDeposited(bytes32, uint32) external pure returns (bool) {
        return true;
    }
}
