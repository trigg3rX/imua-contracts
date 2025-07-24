// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {TriggerXAvs} from "../../src/TriggerXAvs.sol";
import {console2} from "forge-std/console2.sol";

contract TriggerXAvsUpgrade is Script {
    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        address triggerXAvsProxy = 0x72A5016ECb9EB01d7d54ae48bFFB62CA0B8e57a5;

        vm.startBroadcast(deployerPrivateKey);

        TriggerXAvs implementation = new TriggerXAvs();

        TriggerXAvs(payable(triggerXAvsProxy)).upgradeToAndCall(address(implementation), "");

        console2.log("TriggerXAvs proxy upgraded to", address(implementation));

        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 raw = vm.load(address(triggerXAvsProxy), implSlot);
        address fetchimplementation = address(uint160(uint256(raw)));
        console2.log("Implementation:", fetchimplementation);

        vm.stopBroadcast();
    }
}