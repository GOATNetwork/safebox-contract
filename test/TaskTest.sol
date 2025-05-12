pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {TaskManagerUpgradeable} from "../src/TaskManagerUpgradeable.sol";
import {UpgradeableProxy} from "../src/UpgradeableProxy.sol";

import {MockBitcoin} from "../src/mocks/MockContracts.sol";
import {MockBridge} from "../src/mocks/MockContracts.sol";

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
            address(mockBridge),
            false
        );
        UpgradeableProxy proxy = new UpgradeableProxy(
            address(taskManager),
            admin,
            abi.encodeWithSelector(TaskManagerUpgradeable.initialize.selector)
        );
        taskManager = TaskManagerUpgradeable(payable(proxy));

        // initialize task manager
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
        bytes
            memory btcAddress = hex"7462317165306b39743278306632367478723470373374303275617737716e637333343876637430656b";
        bytes
            memory btcPubKey = hex"038bc0a6e6b046ffdbd84aee9aea83d177c9f26f66d5f373949a78f6e774ca7f11";
        taskManager.setupTask(
            newPartnerId,
            safeAddress,
            uint32(block.timestamp + 90 days),
            uint32(block.timestamp + 1 days),
            1 ether,
            btcAddress,
            btcPubKey
        );
        uint256 taskId = 1;

        TaskManagerUpgradeable.Task memory task = taskManager.getTask(taskId);
        assertEq(task.partnerId, newPartnerId);
        assertEq(task.depositAddress, safeAddress);
        assertEq(uint8(task.state), 1);
        assertEq(task.timelockEndTime, block.timestamp + 90 days);
        assertEq(task.deadline, block.timestamp + 1 days);
        assertEq(task.amount, 1 ether);
        assertEq(
            task.btcAddress[0],
            0x7462317165306b39743278306632367478723470373374303275617737716e63
        );
        assertEq(
            task.btcPubKey[0],
            0x038bc0a6e6b046ffdbd84aee9aea83d177c9f26f66d5f373949a78f6e774ca7f
        );
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
        bytes
            memory txData = hex"010000000266701563d6a7a9111f09e7661a26bea81f8731ff89c9996f300349e78da4d560010000000001ffffff5d1afe8b0eae12602cc9470e23cc5f07a60cb744e81e8d574c32f432d542794d000000000001ffffff0260ea00000000000022002006c0dee822a6e9ea2e97ce4668ac4363679b4ba52b76566dc388f4278c2f423a800d280000000000160014fc456386689dfe8e94dfcfae8a0b953eb91d140b00000000";
        vm.prank(relayer);
        taskManager.initTimelockTx(taskId, txData, 4321, witnessScriptArray);
        task = taskManager.getTask(taskId);
        assertEq(uint8(task.state), 3);
        assertEq(task.fundingTxOut, 1234);
        assertEq(task.fundingTxHash, "Funding Tx Hash");
        assertEq(task.timelockTxOut, 4321);
        assertEq(
            task.timelockTxHash,
            0x4f89a5ea25537300bc64896c155fd5bd1e34699a72a261253842d70a2e2110f2
        );

        // failed to burn due to invalid state
        vm.expectRevert("Invalid state");
        taskManager.burn(taskId);

        vm.prank(relayer);
        // curl https://blockstream.info/testnet/api/block/0000000000d8286a670f353aa460dad943185a829e594b47a9f516f5ca10ed28
        bytes
            memory rawHeader = hex"00a0572211d2d2d76f7db99a71ef1a61f5bd3933942a1bc6b7536744ffc3080000000000cbb4f9ca6a2c050515ae008a94083a4a3d0eaeeed6c26318b7e7a25c7ca257f0fd371a68ffff001d7602e77e";
        uint256 blockHeight = 4324887;
        bytes32[] memory proof = new bytes32[](12);
        proof[
            0
        ] = 0x4e392f9a538c569512840e319e76c6e028f200637aefb11f61b09284e0b73f36;
        proof[
            1
        ] = 0xd09231cbdd71e51a66cb1a3a0a413d47f1cb58cccf1aa5c71a8f32659e92e7ea;
        proof[
            2
        ] = 0x524f0abbfbb041ed6c056666eab19cffa358b3fe80b9fca1e0f6ddca3ca6a1b1;
        proof[
            3
        ] = 0x15b4033d5b058bbb565dc637b9aad7a68316b35fde5815d7e4b8c73feb6206af;
        proof[
            4
        ] = 0x93a630a7988df6b8a70257fbd61463b032a39070b45a09bf6b1223d96d60eb27;
        proof[
            5
        ] = 0x2a1e750c35bd07d983eeb0f1f44beccfabaf1113e35d81c2f5f2dcb8a35c95f3;
        proof[
            6
        ] = 0x53c8d5252776cc075926ee0f4ce8430aba9f5f2317383ebe1aa94a49010097b3;
        proof[
            7
        ] = 0x667a2ad411dfa6f6c5d9c70f6fb45c52891e147f43c5ffa2064ab41eccf4d5b0;
        proof[
            8
        ] = 0x66225259cad089344a6372872eb5722350cd0633c20696b90203c4456103dd4e;
        proof[
            9
        ] = 0xc984a57a3473757af59b113010ac7632521e76369d7ced47998f49dee14ab1cd;
        proof[
            10
        ] = 0x2e526e8d65ad84d329e4ba779173bb1dff13a87672a1a60d64be4da1235d0b8c;
        proof[
            11
        ] = 0x0a181f52043542baa4e82631c6f88b3f61c0fd3d9af35bc1af9e4a571ac5baf2;

        uint256 txIndex = 3029;
        taskManager.processTimelockTx(
            taskId,
            rawHeader,
            blockHeight,
            proof,
            txIndex
        );

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
