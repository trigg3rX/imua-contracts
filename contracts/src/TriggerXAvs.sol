// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IAVSManager.sol" as avs;
import "./interfaces/IAvsHook.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/UUPSUpgradeable.sol";

struct TaskDefinition {
    uint8 taskDefinitionId;
    string name; // human readable name
    uint256 baseRewardFeeForAttesters;
    uint256 baseRewardFeeForPerformer;
    uint256 baseRewardFeeForAggregator;
    uint256 minimumVotingPower;
    address[] restrictedOperatorIds;
    uint256 maximumNumberOfAttesters;
}

/// @title TriggerX AVS (Imua compatible)
/// @notice Upgradeable contract acting as TriggerX's AVS proxy to the Imua AVS-Manager precompile.
///         Initially provides thin wrappers around IAVSManager with modular hooks for future
///         reward and slashing logic.
contract TriggerXAvs is OwnableUpgradeable, UUPSUpgradeable {
    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    uint8 private _lastTaskDefinitionId;
    mapping(uint8 => TaskDefinition) private _taskDefinitions;
    
    address public avsHook;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event OperatorOptedIn(address indexed operator);
    event OperatorOptedOut(address indexed operator);
    event BLSPublicKeyRegistered(address indexed operator, address indexed avsAddress, bytes pubKey);
    event TaskSubmitted(uint64 indexed taskID, address indexed operator, uint8 phase);
    event ChallengeSubmitted(uint64 taskId, address taskAddress);
    event TaskCreated(
        uint256 taskId,
        address issuer,
        string name,
        uint8 taskDefinitionId,
        bytes taskData,
        uint64 taskResponsePeriod,
        uint64 taskChallengePeriod,
        uint8 thresholdPercentage,
        uint64 taskStatisticalPeriod
    );
    event TaskDefinitionCreated(uint8 indexed taskDefinitionId, string name);
    event TaskDefinitionUpdated(uint8 indexed taskDefinitionId, string name);
    event AVSRegistered(address indexed sender, string avsName);
    event AVSUpdated(address indexed sender, string avsName);

    // ---------------------------------------------------------------------
    // Initializer & Upgrade Authorization
    // ---------------------------------------------------------------------

    /// @dev Upgradeable initializer replacing constructor
    function initialize(address initialOwner) external initializer {
        __Ownable_init(initialOwner);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}


    // ---------------------------------------------------------------------
    // AVS-Manager wrappers
    // ---------------------------------------------------------------------

    function registerAVS(
        avs.AVSParams calldata params
    ) external onlyOwner returns (bool success) {
        success = avs.AVSMANAGER_CONTRACT.registerAVS(params);
        if (success) emit AVSRegistered(msg.sender, params.avsName);
    }

    function updateAVS(
        avs.AVSParams calldata params
    ) external onlyOwner returns (bool success) {
        success = avs.AVSMANAGER_CONTRACT.updateAVS(params);
        if (success) emit AVSUpdated(msg.sender, params.avsName);
    }

    function registerOperatorToAVS() external returns (bool success) {
        if (avsHook != address(0)) {
            IAvsHook(avsHook).beforeOperatorOptIn(msg.sender);
        }
        success = avs.AVSMANAGER_CONTRACT.registerOperatorToAVS(msg.sender);
        if (success) {
            if (avsHook != address(0)) {
                IAvsHook(avsHook).afterOperatorOptIn(msg.sender);
            }
            emit OperatorOptedIn(msg.sender);
        }
    }

    function deregisterOperatorFromAVS() external returns (bool success) {
        if (avsHook != address(0)) {
            IAvsHook(avsHook).beforeOperatorOptOut(msg.sender);
        }
        success = avs.AVSMANAGER_CONTRACT.deregisterOperatorFromAVS(msg.sender);
        if (success) {
            if (avsHook != address(0)) {
                IAvsHook(avsHook).afterOperatorOptOut(msg.sender);
            }
            emit OperatorOptedOut(msg.sender);
        }
    }

    function registerBLSPublicKey(
        address avsAddr,
        bytes calldata pubKey,
        bytes calldata pubKeyRegistrationSignature
    ) external returns (bool success) {
        success = avs.AVSMANAGER_CONTRACT.registerBLSPublicKey(
            msg.sender,
            avsAddr,
            pubKey,
            pubKeyRegistrationSignature
        );
        if (success) emit BLSPublicKeyRegistered(msg.sender, avsAddr, pubKey);
    }

    /**
     * @notice Register a new task with Imua AVS-Manager.
     * @param taskName The name of the task.
     * @param taskData The data of the task.
     * @param taskDefinitionId The ID of the task definition.
     * @param taskResponsePeriod The response period of the task.
     * @param taskChallengePeriod The challenge period of the task.
     * @param thresholdPercentage The threshold percentage of the task.
     * @param taskStatisticalPeriod The statistical period of the task.
     * @return taskID The task identifier returned by the precompile.
     */
    function createTask(
        string memory taskName,
        uint8 taskDefinitionId,
        bytes calldata taskData,
        uint64 taskResponsePeriod,
        uint64 taskChallengePeriod,
        uint8 thresholdPercentage,
        uint64 taskStatisticalPeriod
    ) external returns (uint64 taskID) {
        require(
            thresholdPercentage <= 100,
            "The threshold cannot be greater than 100"
        );

        bytes32 combinedHash = keccak256(
            abi.encode(
                taskName,
                taskDefinitionId,
                taskData,
                taskResponsePeriod,
                taskChallengePeriod,
                thresholdPercentage,
                taskStatisticalPeriod
            )
        );

        taskID = avs.AVSMANAGER_CONTRACT.createTask(
            msg.sender,
            taskName,
            abi.encodePacked(combinedHash),
            taskResponsePeriod,
            taskChallengePeriod,
            thresholdPercentage,
            taskStatisticalPeriod
        );

        emit TaskCreated(
            taskID,
            msg.sender,
            taskName,
            taskDefinitionId,
            taskData,
            taskResponsePeriod,
            taskChallengePeriod,
            thresholdPercentage,
            taskStatisticalPeriod
        );
    }

    function operatorSubmitTask(
        uint64 taskID,
        bytes calldata taskResponse,
        bytes calldata blsSignature,
        address taskContractAddress,
        uint8 phase
    ) external returns (bool success) {
        success = avs.AVSMANAGER_CONTRACT.operatorSubmitTask(
            msg.sender,
            taskID,
            taskResponse,
            blsSignature,
            taskContractAddress,
            phase
        );
        if (success) emit TaskSubmitted(taskID, msg.sender, phase);
    }

    /**
     * @notice Initiate a challenge for a specific task.
     * @param taskID               The task identifier on Imua.
     * @param actualThreshold      Observed threshold of signatures.
     * @param isExpected           Whether the task outcome meets expectations.
     * @param eligibleRewardOperators Operators eligible for rewards.
     * @param eligibleSlashOperators  Operators eligible for slash.
     */
    function challenge(
        uint64 taskID,
        uint8 actualThreshold,
        bool isExpected,
        address[] calldata eligibleRewardOperators,
        address[] calldata eligibleSlashOperators
    ) external returns (bool success) {
        success = avs.AVSMANAGER_CONTRACT.challenge(
            msg.sender,
            taskID,
            address(this),
            actualThreshold,
            isExpected,
            eligibleRewardOperators,
            eligibleSlashOperators
        );
        if (success) emit ChallengeSubmitted(taskID, address(this));
    }

    // ---------------------------------------------------------------------
    // Setters
    // ---------------------------------------------------------------------

    function setAvsHook(address _avsHook) external onlyOwner {
        avsHook = _avsHook;
    }
    
    // ---------------------------------------------------------------------
    // View helpers delegating to AVS-Manager
    // ---------------------------------------------------------------------

    function getOptInOperators(
        address avsAddress
    ) external view returns (address[] memory) {
        return avs.AVSMANAGER_CONTRACT.getOptInOperators(avsAddress);
    }

    function getRegisteredPubkey(
        address operator,
        address avsAddr
    ) external view returns (bytes memory) {
        return avs.AVSMANAGER_CONTRACT.getRegisteredPubkey(operator, avsAddr);
    }

    function getAVSUSDValue(address avsAddr) external view returns (uint256) {
        return avs.AVSMANAGER_CONTRACT.getAVSUSDValue(avsAddr);
    }

    function getOperatorOptedUSDValue(
        address avsAddr,
        address operatorAddr
    ) external view returns (uint256) {
        return avs.AVSMANAGER_CONTRACT.getOperatorOptedUSDValue(avsAddr, operatorAddr);
    }

    function getAVSEpochIdentifier(
        address avsAddr
    ) external view returns (string memory) {
        return avs.AVSMANAGER_CONTRACT.getAVSEpochIdentifier(avsAddr);
    }

    function getTaskInfo(
        address taskAddress,
        uint64 taskID
    ) external view returns (avs.TaskInfo memory) {
        return avs.AVSMANAGER_CONTRACT.getTaskInfo(taskAddress, taskID);
    }

    function isOperator(address operator) external view returns (bool) {
        return avs.AVSMANAGER_CONTRACT.isOperator(operator);
    }

    function getCurrentEpoch(
        string calldata epochIdentifier
    ) external view returns (int64) {
        return avs.AVSMANAGER_CONTRACT.getCurrentEpoch(epochIdentifier);
    }

    function getChallengeInfo(
        address taskAddress,
        uint64 taskID
    ) external view returns (address) {
        return avs.AVSMANAGER_CONTRACT.getChallengeInfo(taskAddress, taskID);
    }

    function getOperatorTaskResponse(
        address taskAddress,
        address operator,
        uint64 taskID
    ) external view returns (avs.TaskResultInfo memory) {
        return avs.AVSMANAGER_CONTRACT.getOperatorTaskResponse(taskAddress, operator, taskID);
    }

    function getOperatorTaskResponseList(
        address taskAddress,
        uint64 taskID
    ) external view returns (avs.OperatorResInfo[] memory) {
        return avs.AVSMANAGER_CONTRACT.getOperatorTaskResponseList(taskAddress, taskID);
    }

    // ---------------------------------------------------------------------
    // Task Definition functions
    // ---------------------------------------------------------------------

    /**
     * @notice Creates TaskDefinition and stores it locally.
     */
    function createTaskDefinition(
        string calldata name,
        uint256 baseRewardFeeForAttesters,
        uint256 baseRewardFeeForPerformer,
        uint256 baseRewardFeeForAggregator,
        uint256 minimumVotingPower,
        address[] calldata restrictedOperatorIds,
        uint256 maximumNumberOfAttesters
    ) external onlyOwner returns (uint8 taskDefinitionId) {
        taskDefinitionId = ++_lastTaskDefinitionId;
        _taskDefinitions[taskDefinitionId] = TaskDefinition(
            taskDefinitionId,
            name,
            baseRewardFeeForAttesters,
            baseRewardFeeForPerformer,
            baseRewardFeeForAggregator,
            minimumVotingPower,
            restrictedOperatorIds,
            maximumNumberOfAttesters
        );
        emit TaskDefinitionCreated(taskDefinitionId, name);
    }

    function updateTaskDefinition(
        uint8 taskDefinitionId,
        string calldata name,
        uint256 baseRewardFeeForAttesters,
        uint256 baseRewardFeeForPerformer,
        uint256 baseRewardFeeForAggregator,
        uint256 minimumVotingPower,
        address[] calldata restrictedOperatorIds,
        uint256 maximumNumberOfAttesters
    ) external onlyOwner {
        require(
            _taskDefinitions[taskDefinitionId].taskDefinitionId != 0,
            "TaskDefinition does not exist"
        );
        _taskDefinitions[taskDefinitionId] = TaskDefinition(
            taskDefinitionId,
            name,
            baseRewardFeeForAttesters,
            baseRewardFeeForPerformer,
            baseRewardFeeForAggregator,
            minimumVotingPower,
            restrictedOperatorIds,
            maximumNumberOfAttesters
        );
        emit TaskDefinitionUpdated(taskDefinitionId, name);
    }

    function getTaskDefinition(
        uint8 id
    ) external view returns (TaskDefinition memory) {
        return _taskDefinitions[id];
    }

    uint256[50] private __gap;
}
