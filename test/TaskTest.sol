pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TaskManagerUpgradeable} from "../src/TaskManagerUpgradeable.sol";
import {PartnerUpgradeable} from "../src/PartnerUpgradeable.sol";

import {MockBridge} from "../src/mocks/MockBridge.sol";

contract TaskTest is Test {
    TaskManagerUpgradeable public taskManager;
    PartnerUpgradeable public partnerContract;
    MockBridge public mockBridge;

    address public msgSender;
    address public admin = address(1);
    address public relayer = address(2);

    address public partnerAddress;

    function setUp() public virtual {
        msgSender = address(this);

        // deploy contracts
        mockBridge = new MockBridge();
        PartnerUpgradeable partnerLogic = new PartnerUpgradeable();
        UpgradeableBeacon partnerBeacon = new UpgradeableBeacon(
            address(partnerLogic),
            admin
        );
        taskManager = new TaskManagerUpgradeable(
            address(partnerBeacon),
            address(mockBridge)
        );

        // initialize task manager
        taskManager.initialize();
        assertTrue(
            taskManager.hasRole(taskManager.DEFAULT_ADMIN_ROLE(), msgSender)
        );
        taskManager.grantRole(taskManager.ADMIN_ROLE(), admin);
        taskManager.grantRole(taskManager.RELAYER_ROLE(), relayer);

        // create a new partner
        vm.prank(admin);
        taskManager.createPartner();
        partnerAddress = taskManager.getPartner(0);
        partnerContract = PartnerUpgradeable(payable(partnerAddress));
        assertTrue(taskManager.isPartner(partnerAddress));

        // provide funds to the user(msgSender)
        vm.deal(msgSender, 100 ether);
    }

    function test_StandardProcess() public {
        vm.prank(admin);
        taskManager.setupTask(
            partnerAddress,
            90 days,
            1 days,
            1 ether,
            "btcAddress"
        );
        uint256 taskId = 0;
        (
            address partner,
            uint8 state,
            uint32 stakingPeriod,
            uint32 deadline,
            uint32 fulfilledTime,
            uint32 txOut,
            bytes32 txHash,
            bytes32 witnessScript,
            uint256 amount,
            string memory btcAddress
        ) = taskManager.tasks(taskId);
        assertEq(partner, partnerAddress);
        assertEq(state, 1);
        assertEq(stakingPeriod, 90 days);
        assertEq(deadline, 1 days);
        assertEq(fulfilledTime, 0);
        assertEq(amount, 1 ether);
        assertEq(btcAddress, "btcAddress");
        assertEq(taskManager.partnerTasks(partnerAddress, 0), taskId);
        assertEq(taskManager.getPartnerTasks(partnerAddress).length, 1);

        // Send funds to the partner contract
        // @dev using call remove gas limitation
        partnerAddress.call{value: 1 ether}("");
        assertEq(address(partnerAddress).balance, 1 ether);

        // receive funds
        vm.prank(relayer);
        taskManager.receiveFunds(1 ether, 0, "Tx Hash", 1234, "Witness Script");
        (
            partner,
            state,
            stakingPeriod,
            deadline,
            fulfilledTime,
            txOut,
            txHash,
            witnessScript,
            amount,
            btcAddress
        ) = taskManager.tasks(taskId);
        assertEq(state, 2);
        assertEq(txOut, 1234);
        assertEq(txHash, "Tx Hash");
        assertEq(witnessScript, "Witness Script");

        // admin transfer funds
        vm.prank(admin);
        partnerContract.transfer(address(100), 1 ether);

        // failed to burn due to time not reached
        vm.expectRevert("Time not reached");
        taskManager.burn(taskId);

        // skip time
        skip(90 days);

        // burn failed due to insufficient balance
        vm.expectRevert();
        taskManager.burn(taskId);

        // transfer funds back to the partner contract
        partnerContract.returnFunds{value: 1 ether}();

        // burn funds
        taskManager.burn(taskId);
        assertEq(address(partnerAddress).balance, 0);
    }
}
