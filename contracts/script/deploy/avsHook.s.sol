// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {AvsHook} from "../../src/AvsHook.sol";
import {TaskExecutionHubImua} from "../../src/lz/TaskExecutionHub.sol";

contract DeployAvsGovernance is Script {
 
    address payable constant TASK_EXECUTION_HUB = payable(0x0360aA5C71d4959059FC8c309B8767Ed5b53693e);

    address payable constant TriggerXAvsAddress = payable(0x72A5016ECb9EB01d7d54ae48bFFB62CA0B8e57a5); // TestnetProduction AVS Governance address

     // LayerZero Endpoints
    address constant LZ_ENDPOINT_IMUA = 0x6EDCE65403992e310A62460808c4b910D972f10f; // IMUA endpoint

    // Endpoint IDs (EIDs for LayerZero)
    uint32 constant OP_SEPOLIA_EID = 40232; // Optimism Sepolia Endpoint ID
    uint32 constant BASE_SEPOLIA_EID = 40245; // Base Sepolia Endpoint ID
    uint32 constant IMUA_EID = 40259; // IMUA Endpoint ID

    function run() external {
        // Fetch deployer information from environment variables.
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        console.log("Deploying contracts using deployer:", deployerAddress);

        // Create a fork using the IMUA RPC.
        uint256 forkId = vm.createSelectFork(vm.envString("IMUA_RPC_URL"));
        vm.startBroadcast(deployerPrivateKey);

        // Deploy AvsHook on IMUA
        console.log("\n=== Deploying AvsHook on IMUA ===");
        AvsHook avsHook = new AvsHook(
            LZ_ENDPOINT_IMUA,  // LayerZero endpoint
            TASK_EXECUTION_HUB,            // TaskExecutionHub address
            BASE_SEPOLIA_EID,     // Destination chain ID (Base Sepolia)
            deployerAddress,      // Owner address
            TriggerXAvsAddress       // AVS Governance address
        );
        console.log("AvsHook deployed at:", address(avsHook));

        // setTaskExecutionHub on IMUA
        console.log("\n=== Setting TaskExecutionHub on IMUA ===");
        avsHook.setTaskExecutionHub(TASK_EXECUTION_HUB);
        console.log("TaskExecutionHub set successfully on IMUA");
        
        vm.stopBroadcast();

        // Set peer on TaskExecutionHub for IMUA
        console.log("\n=== Setting peer on TaskExecutionHub for IMUA ===");
        vm.createSelectFork(vm.envString("BASE_SEPOLIA_RPC"));
        vm.startBroadcast(deployerPrivateKey);
        
        TaskExecutionHubImua taskExecutionHub = TaskExecutionHubImua(TASK_EXECUTION_HUB);
        taskExecutionHub.setPeer(IMUA_EID, bytes32(uint256(uint160(address(avsHook)))));
        console.log("Peer set successfully on TaskExecutionHub");
        vm.stopBroadcast();

        // Optionally, call afterOperatorRegistered if needed (commented out)
        // vm.selectFork(forkId);
        // AvsGovernanceLogic avsGovernance = AvsGovernanceLogic(payable(0xCd40429c3A85550EC75E3153F5fb7c0F06826EE5));
        // avsGovernance.afterOperatorRegistered(
        //     0x72461158B7abbd3741773F7F3BA145cE02F5177c,  // operator
        //     100,             // votingPower (example value)
        //     [uint256(0), 0, 0, 0],  // blsKey (example value)
        //     0x72461158B7abbd3741773F7F3BA145cE02F5177c  // rewardsReceiver
        // );
        // vm.stopBroadcast();
        // console.log("afterOperatorRegistered called successfully");

        console.log("\n--- Deployment Complete ---");
        console.log("AvsHook Address:", address(avsHook));
        console.log("---------------------------");
    }
} 