// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {CREATE3} from "solady/src/utils/CREATE3.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TaskExecutionHubImua} from "../../src/lz/TaskExecutionHub.sol";
import {TaskExecutionSpokeImua} from "../../src/lz/TaskExecutionSpoke.sol";
import {TriggerGasRegistryImua} from "../../src/TriggerGasRegistry.sol";

contract DeployAll is Script {
    // --- Configuration (Update if needed) ---
    // LayerZero Endpoints
    address constant LZ_ENDPOINT_OP_SEPOLIA = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    address constant LZ_ENDPOINT_BASE_SEPOLIA = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    address constant LZ_ENDPOINT_IMUA = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    // Endpoint IDs (EIDs for LayerZero)
    uint32 constant OP_SEPOLIA_EID = 40232; // Optimism Sepolia Endpoint ID
    uint32 constant BASE_SEPOLIA_EID = 40245; // Base Sepolia Endpoint ID
    uint32 constant HOLESKY_EID = 40217; // Holesky Endpoint ID
    uint32 constant ARBITRUM_SEPOLIA_EID = 40231; // Arbitrum Sepolia Endpoint ID
    uint32 constant POLYGON_ARBITRUM_EID = 40267; // Polygon Amoy Endpoint ID
    uint32 constant AVALANCHE_FUJI_EID = 40106; // Avalanche Fuji Endpoint ID
    uint32 constant BNB_TESTNET_EID = 40102; // BNB Testnet Endpoint ID
    uint32 constant IMUA_EID = 40259; // IMUA Endpoint ID

    address constant JOB_REGISTRY_ADDRESS = 0x309Bb6871d548E25e6051074A1bcE73199d8B647;
    address constant TRIGGER_GAS_REGISTRY_ADDRESS = 0x93dDB2307F3Af5df85F361E5Cddd898Acd3d132d;
    


    bytes32 SALT = bytes32(keccak256(abi.encodePacked(vm.envString("TASK_EXECUTION_SALT"))));

    // Struct to hold network deployment information
    struct NetworkInfo {
        string name;
        string rpcEnvVar;
        address endpoint;
        uint32 eid;
    }

    // State variables to avoid stack depth issues
    address[] private operators;
    address private hubAddress;
    address[] private spokeAddresses;

    function deployHub(uint256 deployerPrivateKey, address deployerAddress) internal {
        console.log("\n=== Deploying TaskExecutionHub on Base Sepolia ===");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy the implementation contract
        TaskExecutionHubImua hubImpl = new TaskExecutionHubImua(LZ_ENDPOINT_BASE_SEPOLIA, deployerAddress);
        console.log("TaskExecutionHub implementation deployed at:", address(hubImpl));

        // 2. Prepare the initialization calldata
        bytes memory initData = abi.encodeWithSelector(
            TaskExecutionHubImua.initialize.selector,
            deployerAddress,                   // _ownerAddress
            IMUA_EID,                       // _srcEid
            BASE_SEPOLIA_EID,                  // _originEid
            operators,                         // _initialKeepers
            JOB_REGISTRY_ADDRESS,              // _jobRegistryAddress (random)
            TRIGGER_GAS_REGISTRY_ADDRESS       // _triggerGasRegistryAddress (random)
        );

        // 3. Prepare the proxy bytecode
        bytes memory proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(address(hubImpl), initData)
        );
        
        // 4. Deploy proxy using CREATE3
        hubAddress = CREATE3.deployDeterministic(proxyBytecode, SALT);
        console.log("TaskExecutionHub proxy deployed at:", hubAddress);

        // TaskExecutionHub(payable(hubAddress)).setPeer(HOLESKY_EID, bytes32(uint256(uint160(AVS_GOVERNANCE_LOGIC_ADDRESS))));
        // TriggerGasRegistryImua(TRIGGER_GAS_REGISTRY_ADDRESS).setOperator(hubAddress);

        console.log("Operator Role:", TriggerGasRegistryImua(TRIGGER_GAS_REGISTRY_ADDRESS).operatorRole());

        vm.stopBroadcast();
    }

    function configureHub(uint256 deployerPrivateKey) internal {
        vm.startBroadcast(deployerPrivateKey);

        TaskExecutionHubImua hub = TaskExecutionHubImua(payable(hubAddress));

        // Create spoke EIDs array
        uint32[] memory spokeEids = new uint32[](1);
        spokeEids[0] = OP_SEPOLIA_EID;
        // spokeEids[1] = ARBITRUM_SEPOLIA_EID;

        // Add all spoke endpoints to Hub
        hub.addSpokes(spokeEids);
        console.log("Added spoke endpoint:", OP_SEPOLIA_EID, "(OP Sepolia)");
        // console.log("Added spoke endpoint:", ARBITRUM_SEPOLIA_EID, "(Arbitrum Sepolia)");

        // Send ETH to Hub contract to cover LayerZero fees
        // vm.deal(address(hub), 1 ether);
        // console.log("Sent 1 ETH to Hub contract at:", address(hub));

        vm.stopBroadcast();
    }

    function deploySpoke(
        string memory networkName,
        string memory rpcEnvVar,
        address endpoint,
        uint256 deployerPrivateKey,
        address deployerAddress
    ) internal returns (address) {
        console.log(string.concat("\n=== Deploying TaskExecutionSpoke on ", networkName, " ==="));
        
        // Create fork for the network
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy implementation
        TaskExecutionSpokeImua spokeImpl = new TaskExecutionSpokeImua(endpoint, deployerAddress);
        console.log(string.concat("TaskExecutionSpoke implementation on ", networkName, " deployed at:"), address(spokeImpl));

        // 2. Prepare initialization calldata
        bytes memory initData = abi.encodeWithSelector(
            TaskExecutionSpokeImua.initialize.selector,
            deployerAddress,    // _ownerAddress
            BASE_SEPOLIA_EID,   // _hubEid
            operators,          // _initialKeepers
            JOB_REGISTRY_ADDRESS,       // _jobRegistryAddress (random)
            TRIGGER_GAS_REGISTRY_ADDRESS        // _triggerGasRegistryAddress (random)
        );

        // 3. Prepare proxy bytecode
        bytes memory proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(address(spokeImpl), initData)
        );
        
        // 4. Deploy proxy using CREATE3
        address spokeAddr = CREATE3.deployDeterministic(proxyBytecode, SALT);
        console.log(string.concat("TaskExecutionSpoke proxy deployed on ", networkName, " at:"), spokeAddr);
        vm.stopBroadcast();

        vm.startBroadcast(deployerPrivateKey);

        // TriggerGasRegistryImua(TRIGGER_GAS_REGISTRY_ADDRESS).setOperator(spokeAddr);


        console.log("Operator Role:", TriggerGasRegistryImua(TRIGGER_GAS_REGISTRY_ADDRESS).operatorRole());

        vm.stopBroadcast();
        
        return spokeAddr;
    }

    function deployAllSpokes(uint256 deployerPrivateKey, address deployerAddress) internal {
        spokeAddresses = new address[](1);
        
        // Deploy OP Sepolia spoke
        spokeAddresses[0] = deploySpoke(
            "OP Sepolia",
            "OPSEPOLIA_RPC", 
            LZ_ENDPOINT_OP_SEPOLIA,
            deployerPrivateKey,
            deployerAddress
        );


        // // Deploy Arbitrum Sepolia spoke
        // spokeAddresses[1] = deploySpoke(
        //     "Arbitrum Sepolia",
        //     "ARBITRUM_SEPOLIA_RPC",
        //     LZ_ENDPOINT_ARBITRUM_SEPOLIA, 
        //     deployerPrivateKey,
        //     deployerAddress
        // );
    }

    function printDeploymentSummary() internal view {
        console.log("\n--- Deployment Complete ---");
        console.log("Hub Address:", hubAddress);
        
        TaskExecutionHubImua hub = TaskExecutionHubImua(payable(hubAddress));
        console.log("Hub Owner:", hub.owner());
        
        // OP Sepolia spoke
        TaskExecutionSpokeImua opSpoke = TaskExecutionSpokeImua(payable(spokeAddresses[0]));
        console.log("OP Sepolia Spoke Address:", spokeAddresses[0]);
        console.log("OP Sepolia Spoke Owner:", opSpoke.owner());
        
        // Arbitrum Sepolia spoke
        // TaskExecutionSpoke arbSpoke = TaskExecutionSpoke(payable(spokeAddresses[1]));
        // console.log("Arbitrum Sepolia Spoke Address:", spokeAddresses[1]);
        // console.log("Arbitrum Sepolia Spoke Owner:", arbSpoke.owner());
        
        console.log("---------------------------");
    }

    function run() external {
        // Fetch deployer information from environment variables.
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        console.log("Deploying contracts using deployer:", deployerAddress);

        // Deploy Hub on Base Sepolia
        vm.createSelectFork(vm.envString("BASE_SEPOLIA_RPC"));
        deployHub(deployerPrivateKey, deployerAddress);
        
        // Configure Hub with spoke endpoints
        configureHub(deployerPrivateKey);

        // Deploy all spokes
        vm.createSelectFork(vm.envString("OPSEPOLIA_RPC"));
        deployAllSpokes(deployerPrivateKey, deployerAddress);

        // Print final deployment summary
        printDeploymentSummary();
    }
} 