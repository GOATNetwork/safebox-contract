// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IBridge {
    function isDeposited(
        bytes32 txHash,
        uint32 txout
    ) external view returns (bool);
}
