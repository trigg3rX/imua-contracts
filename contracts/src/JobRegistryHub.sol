// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/UUPSUpgradeable.sol";

interface ITriggerGasRegistry {
    function deductTG(address user, uint256 amount) external;
}

/// @title JobRegistry - Manages jobs and task execution tracking
/// @notice Handles job creation, task validation, and TG charging while maintaining operator privacy
contract JobRegistry is OwnableUpgradeable, UUPSUpgradeable {
    
    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------
    
    struct Job {
        address creator; 
        bytes32 salt;    
        uint32  executed;
        uint32  createdAt;
    }
    
    /// @dev Maps jobHash to job details
    mapping(bytes32 => Job) public jobs;

    mapping(address => bytes32) public jobHashes;
    
    /// @dev Address of TriggerGasRegistry contract
    ITriggerGasRegistry public triggerGasRegistry;
    
    /// @dev Address of TriggerXAvs contract (only caller allowed for registerTask)
    address public triggerXAvs;
    
    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------
    
    event JobCreated(
        bytes32 indexed jobHash,
        address indexed owner,
        bytes32 salt,
        uint32 timestamp
    );

    event TaskExecuted(
        bytes32 indexed jobHash,
        uint64 taskNonce,
        address indexed performer,
        uint256 tgCost,
        uint32 totalExecuted
    );
    
    event TriggerGasRegistryUpdated(address indexed newRegistry);
    event TriggerXAvsUpdated(address indexed newAvs);
    
    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------
    
    modifier onlyTriggerXAvs() {
        require(msg.sender == triggerXAvs, "Only TriggerXAvs can call");
        _;
    }
    
    // ---------------------------------------------------------------------
    // Initializer & Upgrade Authorization
    // ---------------------------------------------------------------------
    
    /// @dev Upgradeable initializer replacing constructor
    function initialize(
        address initialOwner,
        address _triggerGasRegistry,
        address _triggerXAvs
    ) external initializer {
        require(initialOwner != address(0), "Invalid owner");
        require(_triggerGasRegistry != address(0), "Invalid TG registry");
        require(_triggerXAvs != address(0), "Invalid TriggerXAvs");
        
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        
        triggerGasRegistry = ITriggerGasRegistry(_triggerGasRegistry);
        triggerXAvs = _triggerXAvs;
    }
    
    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}
    
    // ---------------------------------------------------------------------
    // Admin Functions
    // ---------------------------------------------------------------------
    
    function setTriggerGasRegistry(address _triggerGasRegistry) external onlyOwner {
        require(_triggerGasRegistry != address(0), "Invalid address");
        triggerGasRegistry = ITriggerGasRegistry(_triggerGasRegistry);
        emit TriggerGasRegistryUpdated(_triggerGasRegistry);
    }
    
    function setTriggerXAvs(address _triggerXAvs) external onlyOwner {
        require(_triggerXAvs != address(0), "Invalid address");
        triggerXAvs = _triggerXAvs;
        emit TriggerXAvsUpdated(_triggerXAvs);
    }
    
    // ---------------------------------------------------------------------
    // Core Functions
    // ---------------------------------------------------------------------
    
    /// @notice Creates a new job with the given jobHash and salt
    /// @param jobHash The unique identifier for the job (keccak256(jobId, salt))
    /// @param salt The random salt used in jobHash generation
    function createJob(bytes32 jobHash, bytes32 salt) external {
        require(jobHash != bytes32(0), "Invalid jobHash");
        require(jobs[jobHash].creator == address(0), "Job already exists");
        
        jobs[jobHash] = Job({
            creator: msg.sender,
            salt: salt,
            executed: 0,
            createdAt: uint32(block.timestamp)
        });
        
        emit JobCreated(jobHash, msg.sender, salt, uint32(block.timestamp));
    }
    
    /// @notice Registers a completed task and charges the job owner
    /// @param jobHash The job identifier (passed by TriggerXAvs)
    /// @param cipher The encrypted task identifier (keccak256(jobId, nonce))
    /// @param nonce The task sequence number
    /// @param jobId The original job identifier (revealed during task execution)
    /// @param performer The address of the task performer/operator
    /// @param tgCost The amount of TG to charge for this task
    function registerTask(
        bytes32 jobHash,
        bytes32 cipher,
        uint64 nonce,
        bytes32 jobId,
        address performer,
        uint256 tgCost
    ) external onlyTriggerXAvs {
        // Verify the job exists
        Job storage job = jobs[jobHash];
        require(job.creator != address(0), "Job does not exist");
        
        // Verify the jobHash was correctly derived from jobId and salt
        bytes32 expectedJobHash = keccak256(abi.encodePacked(jobId, job.salt));
        require(jobHash == expectedJobHash, "Invalid jobHash");
        
        // Verify the cipher is valid for this job and nonce
        bytes32 expectedCipher = keccak256(abi.encodePacked(jobId, nonce));
        require(cipher == expectedCipher, "Invalid cipher");
        
        // Charge the job owner and pay the performer
        if (tgCost > 0) {
            triggerGasRegistry.deductTG(job.creator, tgCost);
        }
        
        // Update job state
        job.executed += 1;
        
        emit TaskExecuted(jobHash, nonce, performer, tgCost, job.executed);
    }
    
    // ---------------------------------------------------------------------
    // View Functions
    // ---------------------------------------------------------------------
    
    /// @notice Returns job details for a given jobHash
    function getJob(bytes32 jobHash) external view returns (
        address creator,
        bytes32 salt,
        uint32 executed,
        uint32 createdAt
    ) {
        Job memory job = jobs[jobHash];
        return (job.creator, job.salt, job.executed, job.createdAt);
    }
    
    /// @notice Returns just the owner of a job
    function getJobOwner(bytes32 jobHash) external view returns (address) {
        return jobs[jobHash].creator;
    }
    
    /// @notice Returns job execution stats
    function getJobStats(bytes32 jobHash) external view returns (
        uint32 executed,
        uint32 createdAt
    ) {
        Job memory job = jobs[jobHash];
        return (job.executed, job.createdAt);
    }
    
    /// @notice Checks if a job exists
    function jobExists(bytes32 jobHash) external view returns (bool) {
        return jobs[jobHash].creator != address(0);
    }
}
