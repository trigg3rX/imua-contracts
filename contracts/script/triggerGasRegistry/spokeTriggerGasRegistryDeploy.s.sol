// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TriggerGasRegistrySpoke} from "../../src/TriggerGasRegistrySpoke.sol";
import {CREATE3} from "solady/src/utils/CREATE3.sol";

contract SpokeTriggerGasRegistryDeploy is Script {
    function run() public {

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        uint256 tgPerEth = 1000;

        vm.startBroadcast(privateKey);

        bytes32 salt = bytes32(keccak256(abi.encodePacked(vm.envString("TG_SALT"))));
        uint32 dstEid = uint32(vm.envUint("EXOCORE_EID"));
        address BASE_SEPOLIA_ENDPOINT = vm.envAddress("EVM_ENDPOINT");
        address user = vm.addr(privateKey);

        address payable hub = payable(vm.envAddress("TG_REGISTRY_HUB"));

        address payable spokeAddr = payable(CREATE3.deployDeterministic(
            bytes.concat(type(TriggerGasRegistrySpoke).creationCode, abi.encode(dstEid, hub, tgPerEth, BASE_SEPOLIA_ENDPOINT, user)),
            salt
        ));

        TriggerGasRegistrySpoke spoke = TriggerGasRegistrySpoke(spokeAddr);

        console.log("Spoke deployed to:", spokeAddr);
        console.log("Spoke owner:", spoke.owner());
        console.log("Spoke dstEid:", uint256(spoke.dstEid()));
        console.log("Spoke tgPerEth:", spoke.tgPerEth());

        vm.stopBroadcast();
    }
}