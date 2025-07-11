// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TriggerGasRegistryHub} from "../../src/TriggerGasRegistryHub.sol";
import {CREATE3} from "solady/src/utils/CREATE3.sol";

contract HubTriggerGasRegistryDeploy is Script {
    function run() public {
        uint256 privateKey = vm.envUint("DEV0_PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        bytes32 salt = bytes32(keccak256(abi.encodePacked(vm.envString("TG_SALT"))));
        address payable AVS = payable(0x4729BC58ADC71E5386b995f99402176757d75940);
        uint32 BASE_SEPOLIA_EID = uint32(vm.envUint("BASE_SEPOLIA_EID"));
        address EXOCORE_LZ_ENDPOINT = vm.envAddress("EVM_ENDPOINT");
        address user = vm.addr(privateKey);

        address payable hubAddr = payable(CREATE3.deployDeterministic(
            bytes.concat(type(TriggerGasRegistryHub).creationCode, abi.encode(AVS, EXOCORE_LZ_ENDPOINT, user)),
            salt
        ));

        TriggerGasRegistryHub hub = TriggerGasRegistryHub(hubAddr);

        uint32[] memory spokePeers = new uint32[](1);
        spokePeers[0] = BASE_SEPOLIA_EID;
        hub.setSpokePeers(spokePeers);

        console.log("Hub deployed to:", hubAddr);
        console.log("Hub owner:", hub.owner());
        
        vm.stopBroadcast();
    }
}