// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPartner} from "./interfaces/IPartner.sol";

contract PartnerUpgradeable is IPartner, AccessControlUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    function initialize(address _owner, address _manager) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(ADMIN_ROLE, _owner);
        _grantRole(MANAGER_ROLE, _manager);
    }

    function transfer(
        address _token,
        address _to,
        uint256 _amount
    ) public onlyRole(ADMIN_ROLE) {
        if (_token == address(0)) {
            payable(_to).transfer(_amount);
        } else {
            IERC20(_token).transfer(_to, _amount);
        }
        emit Transfer(_token, _to, _amount);
    }

    function burn(uint256 _amount) public onlyRole(MANAGER_ROLE) {
        require(address(this).balance >= _amount, "Insufficient balance");
        payable(address(0)).transfer(_amount);
        emit Burn(_amount);
    }

    receive() external payable {}
}
