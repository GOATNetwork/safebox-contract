// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeableProxy is TransparentUpgradeableProxy {
    constructor(
        address _logic,
        address _initialOwner,
        bytes memory _data
    ) TransparentUpgradeableProxy(_logic, _initialOwner, _data) {}

    function proxyAdmin() external view returns (address) {
        return _proxyAdmin();
    }
}
