// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IPartner {
    function initialize(address _owner) external;
    function claim() external;
    function burn(uint256 _amount) external;
}
