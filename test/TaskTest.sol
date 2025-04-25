pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TaskManagerUpgradeable} from "../src/TaskManagerUpgradeable.sol";
import {BTCStyleMerkle} from "../src/libraries/BTCStyleMerkle.sol";

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
        MockBridge mockBridge = new MockBridge();
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
        assertEq(task.state, 1);
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
            memory txData = hex"0100000001ec2f8cd24340271826b88b342f12aea3752b6f6eca2c0214c89e25089acae3bc000000000001ffffff0200e1f505000000002200205edd35692a52d352e252bb38618faef733cf24bd5525774e906d6c7160724623d684010000000000160014237cc8e0fd3afb6bec89eeed15c28b15d33a6f5f00000000";
        vm.prank(relayer);
        taskManager.initTimelockTx(taskId, txData, 4321, witnessScriptArray);
        task = taskManager.getTask(taskId);
        assertEq(task.state, 3);
        assertEq(task.fundingTxOut, 1234);
        assertEq(task.fundingTxHash, "Funding Tx Hash");
        assertEq(task.timelockTxOut, 4321);
        assertEq(
            task.timelockTxHash,
            0x20bb8ba38319e7d8f0e564962a8145a6e462f71292dac07a5564f3d4d0014ecf
        );

        // failed to burn due to invalid state
        vm.expectRevert("Invalid state");
        taskManager.burn(taskId);

        bytes32[] memory blockHashes = new bytes32[](3);
        // block 125 in regtest
        blockHashes[0] = BTCStyleMerkle.reverseBytes32(
            0x841ca96a59778c0d30e9a1cb70cb3329402de0ae1633e7c029cdd9874280a12c
        );
        // 126
        blockHashes[1] = BTCStyleMerkle.reverseBytes32(
            0x7689cc2cf531ca0d04ed4bf94348f87650a4a3385b4ff82de35416a809154887
        );
        // 127
        blockHashes[2] = BTCStyleMerkle.reverseBytes32(
            0xf3feb36a650888afc7006dfee0e30516e1564e301d49f773b853b1930d27b5df
        );
        (
            bytes32[] memory blockMerkleProof,
            bytes32 blockHashMerkleRoot
        ) = BTCStyleMerkle.generateMerkleProof(blockHashes, 1);

        bytes32 computedRoot = BTCStyleMerkle.computeMerkleRoot(blockHashes);
        assertEq(computedRoot, blockHashMerkleRoot);

        // vm.prank(relayer);
        // bytes32[] memory proof = new bytes32[](2);
        // proof[
        //     0
        // ] = 0x43a434c639ab3884361f168870b658d331e8dbc9dfbf05af093ee07c20ab766f;
        // proof[
        //     1
        // ] = 0xf5d02b376037aa1b24f911ddac2347508b81dd97b1037a0fe25e4a3ff1b2e21d;
        // taskManager.processTimelockTx(taskId, 0, proof, 0);

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
