// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPartner} from "./interfaces/IPartner.sol";

contract PartnerUpgradeable is IPartner, AccessControlUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    uint256 public balance;
    uint256 public allowance;

    function initialize(address _owner, address _manager) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(ADMIN_ROLE, _owner);
        _grantRole(MANAGER_ROLE, _manager);
    }

    function transfer(
        address _to,
        uint256 _amount
    ) public onlyRole(ADMIN_ROLE) {
        require(allowance >= _amount, "Insufficient allowance");
        allowance -= _amount;
        payable(_to).transfer(_amount);
        emit Transfer(_to, _amount);
    }

    function returnFunds() public payable {
        allowance += msg.value;
        require(allowance <= balance, "Exceeded balance");
        emit ReturnFunds(msg.value);
    }

    function credit(uint256 _amount) public onlyRole(MANAGER_ROLE) {
        allowance += _amount;
        require(allowance <= balance, "Exceeded balance");
        emit Credit(_amount);
    }

    function burn(uint256 _amount) public onlyRole(MANAGER_ROLE) {
        require(balance >= _amount, "Insufficient balance");
        balance -= _amount;
        allowance -= _amount;
        payable(address(0)).transfer(_amount);
        emit Burn(_amount);
    }

    receive() external payable {
        balance += msg.value;
    }
}
