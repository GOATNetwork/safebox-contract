// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {IBridge} from "./interfaces/IBridge.sol";
import {IPartner} from "./interfaces/IPartner.sol";
// import {console} from "forge-std/console.sol";
/**
 * @title TaskManagerUpgradeable
 * @dev Contract for managing tasks and partners.
 */
contract TaskManagerUpgradeable is AccessControlUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Events for logging important actions
    event PartnerCreated(address partner);
    event PartnerRemoved(address partner);
    event TaskCreated(uint256 taskId);
    event FundsReceived(uint256 taskId, bytes32 txHash, uint32 txOut);
    event Burned(uint256 taskId);

    // Struct representing a task
    struct Task {
        address partner; // Address of the associated partner
        uint8 state; // Task state: 0 (default), 1 (created), 2 (fulfilled), 3 (burned)
        uint24 stakingPeriod; // The minimum staking period, max of 194 days.
        uint32 deadline; // Timestamp when the task is considered expired
        uint32 fulfilledTime; // Timestamp when the funds are received
        uint256 amount; // Amount of funds associated with the task
        string btcAddress; // Bitcoin address associated with the task
    }

    // Role identifiers for access control
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    // Immutable addresses for partner beacon and bridge
    address public immutable partnerBeacon;
    address public immutable bridge;

    // Set of partner addresses
    EnumerableSet.AddressSet private partners;

    // Array of tasks
    Task[] public tasks;

    // Constructor to initialize immutable variables
    constructor(address _partnerBeacon, address _bridge) {
        partnerBeacon = _partnerBeacon;
        bridge = _bridge;
    }

    // Initializer function for upgradeable contracts
    function initialize() public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function getPartner(uint256 _index) public view returns (address) {
        return partners.at(_index);
    }

    function isPartner(address _partner) public view returns (bool) {
        return partners.contains(_partner);
    }

    /**
     * @dev Create a new partner by deploying a BeaconProxy.
     * Only callable by accounts with the ADMIN_ROLE.
     */
    function createPartner() public onlyRole(ADMIN_ROLE) {
        BeaconProxy partnerProxy = new BeaconProxy(
            partnerBeacon,
            abi.encodeWithSelector(
                IPartner.initialize.selector,
                msg.sender,
                address(this)
            )
        );
        partners.add(address(partnerProxy));
        emit PartnerCreated(address(partnerProxy));
    }

    /**
     * @dev Remove an existing partner.
     * Only callable by accounts with the ADMIN_ROLE.
     */
    function removePartner(address _partiner) public onlyRole(ADMIN_ROLE) {
        partners.remove(_partiner);
        emit PartnerRemoved(_partiner);
    }

    /**
     * @dev Set up a new task for a partner.
     * Only callable by accounts with the ADMIN_ROLE.
     */
    function setupTask(
        address _partner,
        uint24 _stakingPeriod,
        uint32 _deadline,
        uint256 _amount,
        string memory _btcAddress
    ) public onlyRole(ADMIN_ROLE) {
        require(partners.contains(_partner), "Invalid partner");
        tasks.push(
            Task({
                partner: _partner,
                state: 1, // Task state is set to 'created'
                stakingPeriod: _stakingPeriod,
                deadline: _deadline,
                fulfilledTime: 0,
                amount: _amount,
                btcAddress: _btcAddress
            })
        );
        emit TaskCreated(tasks.length - 1);
    }

    /**
     * @dev Mark a task as fulfilled when funds are received.
     * Only callable by accounts with the RELAYER_ROLE.
     */
    function receiveFunds(
        uint256 _taskId,
        bytes32 _txHash,
        uint32 _txOut
    ) public onlyRole(RELAYER_ROLE) {
        require(tasks[_taskId].state == 1, "Invalid task");
        require(IBridge(bridge).isDeposited(_txHash, _txOut), "Tx not found");
        // TODO: better way to check if funds are received?
        require(
            address(tasks[_taskId].partner).balance >= tasks[_taskId].amount,
            "Insufficient funds received"
        );
        tasks[_taskId].fulfilledTime = uint32(block.timestamp);
        tasks[_taskId].state = 2; // Task state is set to 'fulfilled'
        emit FundsReceived(_taskId, _txHash, _txOut);
    }

    /**
     * @dev Claim funds for all partners.
     * Loops through all partners and calls their `claim` function.
     */
    function claimAll() public {
        address[] memory partnerList = partners.values();
        for (uint256 i = 0; i < partnerList.length; i++) {
            IPartner(partnerList[i]).claim();
        }
    }

    /**
     * @dev Burn a task after its staking period has ended.
     * Only callable if the task is in the 'fulfilled' state.
     */
    function burn(uint256 _taskId) public {
        require(tasks[_taskId].state == 2, "Invalid state");
        require(
            block.timestamp >=
                tasks[_taskId].fulfilledTime + tasks[_taskId].stakingPeriod,
            "Time not reached"
        );
        tasks[_taskId].state = 3; // Task state is set to 'burned'
        IPartner(tasks[_taskId].partner).burn(tasks[_taskId].amount);
        emit Burned(_taskId);
    }

    /**
     * @dev Forcefully burn a task.
     * Only callable by accounts with the ADMIN_ROLE.
     */
    function forceBurn(uint256 _taskId) public onlyRole(ADMIN_ROLE) {
        require(tasks[_taskId].state == 2, "Invalid state");
        tasks[_taskId].state = 3; // Task state is set to 'burned'
        IPartner(tasks[_taskId].partner).burn(tasks[_taskId].amount);
        emit Burned(_taskId);
    }
}
