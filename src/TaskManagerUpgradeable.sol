// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IBridge} from "./interfaces/IBridge.sol";

/**
 * @title TaskManagerUpgradeable
 * @dev Contract for managing tasks and partners.
 */
contract TaskManagerUpgradeable is AccessControlUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Events for logging important actions
    event PartnerCreated(uint256 partnerId);
    event PartnerRemoved(uint256 partnerId);
    event TaskCreated(uint256 taskId);
    event FundsReceived(
        uint256 taskId,
        bytes32 fundingTxHash,
        uint32 txOut,
        bytes32 timelockTxHash,
        bytes32 witnessScript
    );
    event Burned(uint256 taskId);

    // Struct representing a task
    struct Task {
        uint256 partnerId; // Address of the associated partner
        address depositAddress; // Address where the funds are deposited
        uint8 state; // Task state: 0 (default), 1 (created), 2 (fulfilled), 3 (burned)
        uint32 timelockEndTime; // Timestamp when the timelock of the funds expires
        uint32 deadline; // Timestamp when the task is considered expired
        uint128 amount; // Amount of funds associated with the task
        uint32 txOut; // txOut of the bridge tx
        bytes32 fundingTxHash; // Tx hash of the btc tx
        bytes32 timelockTxHash; // Tx hash of the btc timelock
        bytes32 witnessScript; // witnessScript of the btc timelock
        string btcAddress; // Bitcoin address associated with the task
    }

    // Role identifiers for access control
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    // Immutable addresses for partner beacon and bridge
    address public immutable partnerBeacon;
    address public immutable bridge;

    // Array of tasks
    Task[] public tasks;
    mapping(uint256 partnerId => uint256[]) public partnerTasks;

    // Constructor to initialize immutable variables
    constructor(address _bridge) {
        bridge = _bridge;
    }

    // Initializer function for upgradeable contracts
    function initialize() public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function getPartnerTasks(
        uint256 _partnerId
    ) public view returns (uint256[] memory) {
        return partnerTasks[_partnerId];
    }

    /**
     * @dev Set up a new task for a partner.
     * Only callable by accounts with the ADMIN_ROLE.
     */
    function setupTask(
        uint256 _partnerId,
        address _depositAddress,
        uint32 _timelockEndTime,
        uint32 _deadline,
        uint128 _amount,
        string memory _btcAddress
    ) public onlyRole(ADMIN_ROLE) {
        require(_timelockEndTime > block.timestamp, "Invalid timelock");
        require(_deadline > block.timestamp, "Invalid deadline");
        require(_amount > 0, "Invalid amount");
        require(bytes(_btcAddress).length > 0, "Invalid btc address");
        uint256 taskId = tasks.length;
        tasks.push(
            Task({
                partnerId: _partnerId,
                depositAddress: _depositAddress,
                state: 1, // Task state is set to 'created'
                timelockEndTime: _timelockEndTime,
                deadline: _deadline,
                amount: _amount,
                txOut: 0,
                fundingTxHash: 0,
                timelockTxHash: 0,
                witnessScript: 0,
                btcAddress: _btcAddress
            })
        );
        partnerTasks[_partnerId].push(taskId);
        emit TaskCreated(taskId);
    }

    /**
     * @dev Mark a task as fulfilled when funds are received.
     * Only callable by accounts with the RELAYER_ROLE.
     */
    function receiveFunds(
        uint128 _amount,
        uint256 _taskId,
        bytes32 _fundingTxHash,
        uint32 _txOut,
        bytes32 _timelockTxHash,
        bytes32 _witnessScript
    ) public onlyRole(RELAYER_ROLE) {
        require(tasks[_taskId].state == 1, "Invalid task");
        require(block.timestamp <= tasks[_taskId].deadline, "Task expired");
        require(_amount == tasks[_taskId].amount, "Invalid amount");
        require(
            IBridge(bridge).isDeposited(_fundingTxHash, _txOut),
            "Tx not found"
        );
        tasks[_taskId].state = 2; // Task state is set to 'fulfilled'
        tasks[_taskId].fundingTxHash = _fundingTxHash;
        tasks[_taskId].timelockTxHash = _timelockTxHash;
        tasks[_taskId].txOut = _txOut;
        tasks[_taskId].witnessScript = _witnessScript;
        emit FundsReceived(
            _taskId,
            _fundingTxHash,
            _txOut,
            _timelockTxHash,
            _witnessScript
        );
    }

    /**
     * @dev Burn a task after its staking period has ended.
     * Only callable if the task is in the 'fulfilled' state.
     */
    function burn(uint256 _taskId) public {
        require(tasks[_taskId].state == 2, "Invalid state");
        require(
            block.timestamp >= tasks[_taskId].timelockEndTime,
            "Time not reached"
        );
        tasks[_taskId].state = 3; // Task state is set to 'burned'
        payable(address(0)).transfer(tasks[_taskId].amount);
        emit Burned(_taskId);
    }

    /**
     * @dev Forcefully burn a task.
     * Only callable by accounts with the ADMIN_ROLE.
     */
    function forceBurn(uint256 _taskId) public onlyRole(ADMIN_ROLE) {
        require(tasks[_taskId].state == 2, "Invalid state");
        tasks[_taskId].state = 3; // Task state is set to 'burned'
        payable(address(0)).transfer(tasks[_taskId].amount);
        emit Burned(_taskId);
    }

    receive() external payable {}
}
