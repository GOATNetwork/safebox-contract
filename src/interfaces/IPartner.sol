// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IPartner {
    event Claim();
    event Withdraw();
    event Transfer(address to, uint256 amount);
    event ReturnFunds(uint256 amount);
    event Credit(uint256 amount);
    event Burn(uint256 amount);

    function initialize(address _owner, address _manager) external;
    function transfer(address _to, uint256 _amount) external;
    function burn(uint256 _amount) external;
    function credit(uint256 _amount) external;
}
