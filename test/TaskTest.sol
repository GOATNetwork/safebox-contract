pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {TaskManagerUpgradeable} from "../src/TaskManagerUpgradeable.sol";
import {UpgradeableProxy} from "../src/UpgradeableProxy.sol";

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
        MockBridge mockBridge = new MockBridge();
        taskManager = new TaskManagerUpgradeable(address(mockBridge));
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
            memory txData = hex"0100000002e907a52bebbb81806b0563d04a7ad631176d4582e62cf85448c8fa023688dc30000000000001ffffff36432a6b40d125d901c7b4a1a86436d8e19c62cb8db069fde991e2c74b610e1a010000000001ffffff0238c70000000000002200208359f2b3fdbf85311b02ee3d017547cafd09bee979012363bfd5e7d242a85eded9aec50400000000160014fc456386689dfe8e94dfcfae8a0b953eb91d140b00000000";
        vm.prank(relayer);
        taskManager.initTimelockTx(taskId, txData, 4321, witnessScriptArray);
        task = taskManager.getTask(taskId);
        assertEq(uint8(task.state), 3);
        assertEq(task.fundingTxOut, 1234);
        assertEq(task.fundingTxHash, "Funding Tx Hash");
        assertEq(task.timelockTxOut, 4321);
        assertEq(
            task.timelockTxHash,
            0xadcf472b310848a41272aa3d72f5b04aec42867549e80e3b60712722a296ce0f
        );

        // failed to burn due to invalid state
        vm.expectRevert("Invalid state");
        taskManager.burn(taskId);

        vm.prank(relayer);
        bytes32 merkleRoot = 0x39dc554a21dace16b0b94295f45d64b3dba1e8a717504b467939c8c5cd2052e9;
        bytes32[] memory proof = new bytes32[](11);
        proof[
            0
        ] = 0xaec693ed07aa507d71728090ebedeb0e25d51351f495c35278c25be542718022;
        proof[
            1
        ] = 0x47efe1e96eb55de81ceb6256c0675f6988e793a970faf02ee916fb57fedf81c0;
        proof[
            2
        ] = 0x38304f8be20ffae66b97e9a904ff55eba372a6ca24dd9df466a6148a59b45eaf;
        proof[
            3
        ] = 0x454e4146b8041226f7eef6627de9db93a1b3e549ab55f147ebe416232fb4137b;
        proof[
            4
        ] = 0x9fbfda72c6d95f5f1597c19dd025475dd2a6f6c5bfaba0b46e009d0be3ebcc93;
        proof[
            5
        ] = 0xdaa1bd6551356d04cd836d1f76519b785b85493dcd42985ad85afaea6ed67f9b;
        proof[
            6
        ] = 0x899091ff1eece7f2815b39003274dd9907f93fb2ddda52e072b3d065fc529ca4;
        proof[
            7
        ] = 0x024679d9aa192a213c2395bda62eb41382440d2e5af5c7a01217212a950cb53d;
        proof[
            8
        ] = 0x81786ec31574dd94fb56a722eb59d277f465b8ab2a22451d2ed67665d343e180;
        proof[
            9
        ] = 0x110b4921fd1accdbe98a989cd3361726487463c8b6ab3cae580f7cd2c513d250;
        proof[
            10
        ] = 0xe3455c6f045b2f486dbf553018bccaa95d95a2864c1ddf90011e59d0bd31dc44;
        uint256 txIndex = 1386;
        taskManager.processTimelockTx(taskId, merkleRoot, proof, txIndex);

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
