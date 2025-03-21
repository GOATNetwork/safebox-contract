// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IPartner {
    event Distribute(uint256 strategyId, uint256 amount);
    event Claim();
    event Withdraw();
    event Transfer(address token, address to, uint256 amount);
    event Burn(uint256 amount);

    function initialize(address _owner, address _manager) external;
    function claim() external;
    function burn(uint256 _amount) external;
}
