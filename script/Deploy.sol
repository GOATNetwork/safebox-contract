pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";

import {TaskManagerUpgradeable} from "../src/TaskManagerUpgradeable.sol";

contract TaskTest is Script {
    address public admin;
    address public relayer;
    address public goatBridge;
    address public bitcoin;

    function setUp() public virtual {
        admin = vm.envAddress("ADMIN_ADDR");
        relayer = vm.envAddress("RELAYER_ADDR");
        bitcoin = vm.envAddress("BITCOIN_CONTRACT");
        goatBridge = vm.envAddress("GOAT_BRIDGE_CONTRACT");
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // deploy contracts
        TaskManagerUpgradeable taskManager = new TaskManagerUpgradeable(
            bitcoin,
            goatBridge
        );

        // initialize task manager
        taskManager.initialize();
        taskManager.grantRole(taskManager.ADMIN_ROLE(), admin);
        taskManager.grantRole(taskManager.RELAYER_ROLE(), relayer);

        console.log(
            "TaskManagerUpgradeable contract address: ",
            address(taskManager)
        );

        vm.stopBroadcast();
    }
}
