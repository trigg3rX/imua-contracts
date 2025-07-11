// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TriggerGasRegistrySpoke} from "../../src/TriggerGasRegistrySpoke.sol";

contract TestSpokeTG is Script {
    function run() public {
        address spokeAddr = vm.envAddress("TG_REGISTRY");
        TriggerGasRegistrySpoke spoke = TriggerGasRegistrySpoke(spokeAddr);

        address testUser = vm.addr(vm.envUint("PRIVATE_KEY"));

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        uint256 tgAmount = 100000;

        // Test purchaseTG
        try spoke.purchaseTG{value: 100}(testUser, tgAmount) {
            console.log("purchaseTG called successfully");
        } catch Error(string memory reason) {
            console.log("purchaseTG failed:", reason);
        } 
        vm.stopBroadcast();
    }
} 