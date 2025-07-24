// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {TriggerXAvs} from "../src/TriggerXAvs.sol";
import "../src/interfaces/IAVSManager.sol";

contract TestAvs is Script {
    function run() public {
        address AVS_ADDR = 0x55728184367f9D6Aa47e3Bb4932Bf9B38250Db4d;
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        vm.startBroadcast(deployer);

        TriggerXAvs avs = TriggerXAvs(AVS_ADDR);

        AVSParams memory avsParams = AVSParams({
            sender: deployer,
            avsName: "TriggerX",
            minStakeAmount: uint64(1000000000000000000),
            taskAddress: address(0),
            slashAddress: address(0),
            rewardAddress: address(0),
            avsOwnerAddresses: new address[](0),
            whitelistAddresses: new address[](0),
            assetIDs: new string[](0),
            avsUnbondingPeriod: uint64(1000000000000000000),
            minSelfDelegation: uint64(1000000000000000000),
            epochIdentifier: "epoch",
            miniOptInOperators: uint64(1000000000000000000),
            minTotalStakeAmount: uint64(1000000000000000000),
            avsRewardProportion: uint64(1000000000000000000),
            avsSlashProportion: uint64(1000000000000000000)
        });

        avs.registerAVS(avsParams);
        // avs.registerOperatorToAVS();

        vm.stopBroadcast();

    }
}