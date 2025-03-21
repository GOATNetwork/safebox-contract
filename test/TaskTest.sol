pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TaskManagerUpgradeable} from "../src/TaskManagerUpgradeable.sol";
import {PartnerUpgradeable} from "../src/PartnerUpgradeable.sol";

import {MockBridge} from "../src/mocks/MockBridge.sol";

contract TaskTest is Test {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

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
            uint24 stakingPeriod,
            uint32 deadline,
            uint32 fulfilledTime,
            uint256 amount,
            string memory btcAddress
        ) = taskManager.tasks(taskId);
        assertEq(state, 1);

        // Send funds to the partner contract
        // @dev using call remove gas limitation
        partnerAddress.call{value: 1 ether}("");
        assertEq(address(partnerAddress).balance, 1 ether);

        // receive funds
        vm.prank(relayer);
        taskManager.receiveFunds(0, "Tx Hash", 1234);

        // admin transfer funds
        vm.prank(admin);
        partnerContract.transfer(address(0), address(100), 1 ether);

        // burn failed due to insufficient balance
        vm.expectRevert();
        taskManager.burn(taskId);

        // transfer funds back to the partner contract
        partnerAddress.call{value: 1 ether}("");

        // failed to burn due to time not reached
        vm.expectRevert("Time not reached");
        taskManager.burn(taskId);

        // skip time
        skip(90 days);

        // burn funds
        taskManager.burn(taskId);
        assertEq(address(partnerAddress).balance, 0);
    }
}
