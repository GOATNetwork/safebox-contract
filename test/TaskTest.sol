pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TaskManagerUpgradeable} from "../src/TaskManagerUpgradeable.sol";

import {MockBridge} from "../src/mocks/MockBridge.sol";

contract TaskTest is Test {
    TaskManagerUpgradeable public taskManager;
    MockBridge public mockBridge;

    address public msgSender;
    address public admin = address(1);
    address public relayer = address(2);
    address public safeAddress = address(3);

    function setUp() public virtual {
        msgSender = address(this);

        // deploy contracts
        mockBridge = new MockBridge();
        taskManager = new TaskManagerUpgradeable(address(mockBridge));

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
        taskManager.setupTask(
            newPartnerId,
            safeAddress,
            uint32(block.timestamp + 90 days),
            uint32(block.timestamp + 1 days),
            1 ether,
            "btcAddress"
        );
        uint256 taskId = 0;
        (
            uint256 partnerId,
            address depositAddress,
            uint8 state,
            uint32 timelockEndTime,
            uint32 deadline,
            uint128 amount,
            uint32 txOut,
            bytes32 fundingTxHash,
            bytes32 timelockTxHash,
            bytes32 witnessScript,
            string memory btcAddress
        ) = taskManager.tasks(taskId);
        assertEq(partnerId, newPartnerId);
        assertEq(depositAddress, safeAddress);
        assertEq(state, 1);
        assertEq(timelockEndTime, block.timestamp + 90 days);
        assertEq(deadline, block.timestamp + 1 days);
        assertEq(amount, 1 ether);
        assertEq(btcAddress, "btcAddress");
        assertEq(taskManager.partnerTasks(partnerId, 0), taskId);
        assertEq(taskManager.getPartnerTasks(partnerId).length, 1);

        // Send funds to the partner contract
        // @dev using call remove gas limitation
        safeAddress.call{value: 1 ether}("");
        assertEq(address(safeAddress).balance, 1 ether);

        // receive funds
        vm.prank(relayer);
        taskManager.receiveFunds(
            1 ether,
            0,
            "Funding Tx Hash",
            1234,
            "Timelock Tx Hash",
            "Witness Script"
        );
        (
            partnerId,
            depositAddress,
            state,
            timelockEndTime,
            deadline,
            amount,
            txOut,
            fundingTxHash,
            timelockTxHash,
            witnessScript,
            btcAddress
        ) = taskManager.tasks(taskId);
        assertEq(state, 2);
        assertEq(txOut, 1234);
        assertEq(fundingTxHash, "Funding Tx Hash");
        assertEq(timelockTxHash, "Timelock Tx Hash");
        assertEq(witnessScript, "Witness Script");

        // failed to burn due to time not reached
        vm.expectRevert("Time not reached");
        taskManager.burn(taskId);

        // skip time
        skip(90 days);

        // burn failed due to insufficient balance
        vm.expectRevert();
        taskManager.burn(taskId);

        // return the funds
        vm.prank(safeAddress);
        address(taskManager).call{value: 1 ether}("");

        // burn funds
        taskManager.burn(taskId);
        assertEq(address(safeAddress).balance, 0);
    }
}
