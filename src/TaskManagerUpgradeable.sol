// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {IBitcoin} from "./interfaces/IBitcoin.sol";
import {IBridge} from "./interfaces/IBridge.sol";
import {BtcParser} from "./libraries/BtcParser.sol";

/**
 * @title TaskManagerUpgradeable
 * @dev Contract for managing tasks and partners.
 */
contract TaskManagerUpgradeable is AccessControlUpgradeable {
    using BtcParser for bytes;

    enum TaskState {
        None,
        Created,
        Received,
        TimelockInitialized,
        Confirmed,
        Completed
    }

    // Constants
    uint256 public constant AVAILABLE_TASK_STATE = type(uint256).max;
    uint256 public constant MIN_DEPOSIT_AMOUNT = 5 * 10 ** 14; // Minimum deposit amount in satoshis

    // Events
    event TaskCreated(uint256 taskId);
    event TaskCancelled(uint256 taskId);
    event FundsReceived(uint256 taskId, bytes32 fundingTxHash, uint32 txOut);
    event TimelockInitialized(
        uint256 taskId,
        bytes32 timelockTxHash,
        uint32 txOut,
        bytes32[7] witnessScript
    );
    event TimelockProcessed(uint256 taskId);
    event Burned(uint256 taskId);

    // Struct representing a task
    struct Task {
        uint256 partnerId; // Address of the associated partner
        address depositAddress; // Address where the funds are deposited
        TaskState state; // Task state: 0 (default/cancelled), 1 (created), 2 (received), 3, (init timelock), 4(confirmed) 5 (completed)
        uint32 timelockEndTime; // Timestamp when the timelock of the funds expires
        uint32 deadline; // Timestamp when the task is considered expired
        uint128 amount; // Amount of funds associated with the task
        uint32 fundingTxOut; // txOut of the funding tx
        uint32 timelockTxOut; // txOut of the timelock tx
        bytes32 fundingTxHash; // Tx hash of the btc tx
        bytes32 timelockTxHash; // Tx hash of the btc timelock
        bytes32[7] witnessScript; // witnessScript of the btc timelock
        bytes32[2] btcAddress; // Bitcoin address associated with the task
        bytes32[2] btcPubKey; // Bitcoin public key associated with the task
    }

    // Role identifiers for access control
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    // @note The relayer is implemented using TSS (Threshold Signature Scheme), meaning
    // submissions under this role come from different participants with off-chain consensus.
    // This setup enhances security and makes the role significantly harder to compromise.
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    address public immutable bitcoin;
    address public immutable bridge;

    // Array of tasks
    Task[] public tasks;
    mapping(uint256 partnerId => uint256[]) public partnerTasks;
    mapping(address depositAddress => uint256) public hasPendingTask; // 0/AVAILABLE_TASK_STATE: available

    // Constructor to initialize immutable variables
    constructor(address _bitcoin, address _bridge) {
        bitcoin = _bitcoin;
        bridge = _bridge;
        _disableInitializers();
    }

    // Initializer function for upgradeable contracts
    function initialize() public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // push an empty task to avoid index 0
        tasks.push();
    }

    function getTask(uint256 _taskId) external view returns (Task memory) {
        return tasks[_taskId];
    }

    function getPartnerTasks(
        uint256 _partnerId
    ) external view returns (uint256[] memory) {
        return partnerTasks[_partnerId];
    }

    /**
     * @dev Set up a new task for a partner.
     * Only P2WPKH addresses are supported.
     */
    function setupTask(
        uint256 _partnerId,
        address _depositAddress,
        uint32 _timelockEndTime,
        uint32 _deadline,
        uint128 _amount,
        bytes calldata _btcAddress,
        bytes calldata _btcPubKey
    ) public onlyRole(ADMIN_ROLE) {
        require(_deadline > block.timestamp, "Invalid deadline");
        require(_timelockEndTime > _deadline, "Invalid timelock");
        require(
            _amount > MIN_DEPOSIT_AMOUNT && (_amount % 10 ** 12) == 0,
            "Invalid amount"
        );
        require(
            hasPendingTask[_depositAddress] == AVAILABLE_TASK_STATE ||
                hasPendingTask[_depositAddress] == 0,
            "Task already exists"
        );
        // Check if the address is a valid P2WPKH address
        require(
            keccak256(_btcPubKey.pubKeyToP2WPKH(false)) ==
                keccak256(_btcAddress),
            "Invalid btc address"
        );

        uint256 taskId = tasks.length;
        hasPendingTask[_depositAddress] = taskId;
        tasks.push(
            Task({
                partnerId: _partnerId,
                depositAddress: _depositAddress,
                state: TaskState.Created,
                timelockEndTime: _timelockEndTime,
                deadline: _deadline,
                amount: _amount,
                fundingTxOut: 0,
                timelockTxOut: 0,
                fundingTxHash: 0,
                timelockTxHash: 0,
                witnessScript: [
                    bytes32(0),
                    bytes32(0),
                    bytes32(0),
                    bytes32(0),
                    bytes32(0),
                    bytes32(0),
                    bytes32(0)
                ],
                btcAddress: _btcAddress.bytesToBytes2(),
                btcPubKey: _btcPubKey.bytesToBytes2()
            })
        );
        partnerTasks[_partnerId].push(taskId);
        emit TaskCreated(taskId);
    }

    /**
     * @dev Cancel a task before the funds is received.
     */
    function cancelTask(uint256 _taskId) public onlyRole(ADMIN_ROLE) {
        require(tasks[_taskId].state == TaskState.Created, "Invalid task");
        hasPendingTask[tasks[_taskId].depositAddress] = AVAILABLE_TASK_STATE;
        delete tasks[_taskId];
        emit TaskCancelled(_taskId);
    }

    /**
     * @dev Mark a task as received when funds are received.
     */
    function receiveFunds(
        uint256 _taskId,
        uint128 _amount,
        bytes32 _fundingTxHash,
        uint32 _txOut
    ) public onlyRole(RELAYER_ROLE) {
        require(tasks[_taskId].state == TaskState.Created, "Invalid task");
        require(block.timestamp <= tasks[_taskId].deadline, "Task expired");
        require(_amount == tasks[_taskId].amount, "Invalid amount");
        require(
            IBridge(bridge).isDeposited(_fundingTxHash, _txOut),
            "Tx not found"
        );
        tasks[_taskId].state = TaskState.Received; // Task state is set to 'received'
        tasks[_taskId].fundingTxHash = _fundingTxHash;
        tasks[_taskId].fundingTxOut = _txOut;
        emit FundsReceived(_taskId, _fundingTxHash, _txOut);
    }

    /**
     * @dev Initialize Timelock tx for the funds
     */
    function initTimelockTx(
        uint256 _taskId,
        bytes memory _txData,
        uint32 _txOut,
        bytes32[7] calldata _witnessScript
    ) public onlyRole(RELAYER_ROLE) {
        require(_txData.length > 64, "Invalid tx data");
        require(
            tasks[_taskId].state == TaskState.Received ||
                tasks[_taskId].state == TaskState.TimelockInitialized,
            "Invalid task state"
        );
        bytes32 timelockTxHash = _doubleSha256Bytes(_txData);
        tasks[_taskId].state = TaskState.TimelockInitialized; // Task state is set to 'init timelock'
        tasks[_taskId].timelockTxHash = timelockTxHash;
        tasks[_taskId].timelockTxOut = _txOut;
        tasks[_taskId].witnessScript = _witnessScript;
        emit TimelockInitialized(
            _taskId,
            timelockTxHash,
            _txOut,
            _witnessScript
        );
    }

    /**
     * @dev Verify the timelock tx for the funds using SPV.
     */
    function processTimelockTx(
        uint256 _taskId,
        bytes calldata _rawHeader,
        uint256 _height,
        bytes32[] calldata _proof,
        uint256 _index
    ) public onlyRole(RELAYER_ROLE) {
        require(
            tasks[_taskId].state == TaskState.TimelockInitialized,
            "Invalid task"
        );
        (bytes32 blockHash, bytes32 merkleRoot) = _parseBtcBlockHeader(
            _rawHeader
        );
        require(
            blockHash == IBitcoin(bitcoin).blockHash(_height),
            "Invalid block hash"
        );
        require(
            verifyMerkleProof(
                merkleRoot,
                _proof,
                tasks[_taskId].timelockTxHash,
                _index
            ),
            "Invalid proof"
        );
        hasPendingTask[tasks[_taskId].depositAddress] = AVAILABLE_TASK_STATE;
        tasks[_taskId].state = TaskState.Confirmed; // Task state is set to 'confirmed'
        emit TimelockProcessed(_taskId);
    }

    /**
     * @dev Burn a task after its staking period has ended.
     */
    function burn(uint256 _taskId) public payable {
        require(tasks[_taskId].state == TaskState.Confirmed, "Invalid state");
        require(
            block.timestamp >= tasks[_taskId].timelockEndTime,
            "Time not reached"
        );
        tasks[_taskId].state = TaskState.Completed; // Task state is set to 'completed'
        payable(address(0)).transfer(tasks[_taskId].amount);
        emit Burned(_taskId);
    }

    /**
     * @dev Forcefully burn a task before the timelock expires.
     * Only callable by accounts with the ADMIN_ROLE.
     */
    function forceBurn(uint256 _taskId) public payable onlyRole(ADMIN_ROLE) {
        require(tasks[_taskId].state == TaskState.Confirmed, "Invalid state");
        tasks[_taskId].state = TaskState.Completed; // Task state is set to 'completed'
        payable(address(0)).transfer(tasks[_taskId].amount);
        emit Burned(_taskId);
    }

    /**
     * @dev Verify a merkle proof of Bitcoin SPV.
     */
    function verifyMerkleProof(
        bytes32 root,
        bytes32[] memory proof,
        bytes32 leaf,
        uint256 index
    ) public pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i; i < proof.length; ++i) {
            if (index % 2 == 0) {
                computedHash = _doubleSha256Pair(computedHash, proof[i]);
            } else {
                computedHash = _doubleSha256Pair(proof[i], computedHash);
            }
            index /= 2;
        }

        return computedHash == root;
    }

    function _parseBtcBlockHeader(
        bytes calldata _rawHeader
    ) public pure returns (bytes32 blockHash, bytes32 merkleRoot) {
        blockHash = sha256(abi.encodePacked(sha256(_rawHeader)));
        assembly {
            merkleRoot := mload(add(_rawHeader.offset, 0x44))
        }
    }

    /**
     * @dev Double SHA256 hash of two inputs.
     */
    function _doubleSha256Pair(
        bytes32 txA,
        bytes32 txB
    ) internal pure returns (bytes32) {
        // concatenate and do sha256 once
        bytes32 hash = sha256(abi.encodePacked(txA, txB));

        // do sha256 once again
        return sha256(abi.encodePacked(hash));
    }

    /**
     * @dev Calculate BTC tx hash from raw tx data.
     */
    function _doubleSha256Bytes(
        bytes memory _data
    ) public pure returns (bytes32) {
        // Compute double SHA256
        bytes32 first = sha256(_data);
        return sha256(abi.encodePacked(first));
    }

    receive() external payable {}
}
