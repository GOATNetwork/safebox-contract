// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PartnerUpgradeable is AccessControlUpgradeable {
    event Distribute(uint256 strategyId, uint256 amount);
    event Claim();
    event Withdraw();
    event Transfer(address token, address to, uint256 amount);
    event Burn(uint256 amount);

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    function initialize(address _owner, address _manager) public initializer {
        grantRole(DEFAULT_ADMIN_ROLE, _owner);
        grantRole(ADMIN_ROLE, _owner);
        grantRole(MANAGER_ROLE, _manager);
    }

    function strategy1(uint256 _amount) public onlyRole(ADMIN_ROLE) {
        // ...
        emit Distribute(1, _amount);
    }

    function claim() public {
        // ...
        emit Claim();
    }

    function withdraw() public onlyRole(ADMIN_ROLE) {
        // ...
        emit Withdraw();
    }

    function transfer(
        address _token,
        address _to,
        uint256 _amount
    ) public onlyRole(ADMIN_ROLE) {
        IERC20(_token).transfer(_to, _amount);
        emit Transfer(_token, _to, _amount);
    }

    function burn(uint256 _amount) public onlyRole(MANAGER_ROLE) {
        if (address(this).balance < _amount) {
            withdraw();
        }
        payable(address(0)).transfer(_amount);
        emit Burn(_amount);
    }
}
