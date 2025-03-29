pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TaskManagerUpgradeable} from "../src/TaskManagerUpgradeable.sol";

import {MockBridge, MockBitcoin} from "../src/mocks/MockContracts.sol";

contract TaskTest is Test {
    TaskManagerUpgradeable public taskManager;

    address public msgSender;
    address public admin = address(1);
    address public relayer = address(2);
    address public safeAddress = address(3);

    function setUp() public virtual {
        msgSender = address(this);

        // deploy contracts
        MockBitcoin mockBitcoin = new MockBitcoin();
        MockBridge mockBridge = new MockBridge();
        taskManager = new TaskManagerUpgradeable(
            address(mockBitcoin),
            address(mockBridge)
        );

        // initialize task manager
        taskManager.initialize();
        assertTrue(
            taskManager.hasRole(taskManager.DEFAULT_ADMIN_ROLE(), msgSender)
        );
        taskManager.grantRole(taskManager.ADMIN_ROLE(), admin);
        taskManager.grantRole(taskManager.RELAYER_ROLE(), relayer);

        // provide funds to the user(msgSender)
        vm.deal(msgSender, 100 ether);
    }

    function test_StandardProcess() public {
        vm.prank(admin);
        uint256 newPartnerId = 10;
        bytes32[2] memory btcAddress = [
            bytes32("btcAddress0"),
            bytes32("btcAddress1")
        ];
        taskManager.setupTask(
            newPartnerId,
            safeAddress,
            uint32(block.timestamp + 90 days),
            uint32(block.timestamp + 1 days),
            1 ether,
            btcAddress
        );
        uint256 taskId = 0;

        TaskManagerUpgradeable.Task memory task = taskManager.getTask(taskId);
        assertEq(task.partnerId, newPartnerId);
        assertEq(task.depositAddress, safeAddress);
        assertEq(task.state, 1);
        assertEq(task.timelockEndTime, block.timestamp + 90 days);
        assertEq(task.deadline, block.timestamp + 1 days);
        assertEq(task.amount, 1 ether);
        assertEq(task.btcAddress[0], "btcAddress0");
        assertEq(taskManager.partnerTasks(newPartnerId, 0), taskId);
        assertEq(taskManager.getPartnerTasks(newPartnerId).length, 1);

        // Send funds to the partner contract
        // @dev using call remove gas limitation
        safeAddress.call{value: 1 ether}("");
        assertEq(address(safeAddress).balance, 1 ether);

        // receive funds
        vm.prank(relayer);
        taskManager.receiveFunds(taskId, 1 ether, "Funding Tx Hash", 1234);

        bytes32[7] memory witnessScriptArray;
        vm.prank(relayer);
        taskManager.initTimelockTx(
            taskId,
            "Timelock Tx Hash",
            4321,
            witnessScriptArray
        );
        task = taskManager.getTask(taskId);
        assertEq(task.state, 3);
        assertEq(task.fundingTxOut, 1234);
        assertEq(task.fundingTxHash, "Funding Tx Hash");
        assertEq(task.timelockTxOut, 4321);
        assertEq(task.timelockTxHash, "Timelock Tx Hash");

        // failed to burn due to invalid state
        vm.expectRevert("Invalid state");
        taskManager.burn(taskId);

        // vm.prank(relayer);
        // taskManager.processTimelockTx(taskId);

        // // failed to burn due to time not reached
        // vm.expectRevert("Time not reached");
        // taskManager.burn(taskId);

        // // skip time
        // skip(90 days);

        // // burn failed due to insufficient balance
        // vm.expectRevert();
        // taskManager.burn(taskId);

        // // return the funds
        // vm.prank(safeAddress);
        // address(taskManager).call{value: 1 ether}("");

        // // burn funds
        // taskManager.burn(taskId);
        // assertEq(address(safeAddress).balance, 0);
    }
}
