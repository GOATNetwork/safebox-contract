// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IBitcoin {
    function blockHash(uint256 height) external view returns (bytes32);
}
