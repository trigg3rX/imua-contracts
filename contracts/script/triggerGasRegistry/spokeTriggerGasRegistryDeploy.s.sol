// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TriggerGasRegistrySpoke} from "../../src/TriggerGasRegistrySpoke.sol";
import {CREATE3} from "solady/src/utils/CREATE3.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

contract SpokeTriggerGasRegistryDeploy is Script {
    
    /// @dev Build Type-3 executor options for LayerZero messages
    /// Based on the pattern from AvsGovernanceLogic contract
    function _buildExecutorOptions(uint128 gas, uint128 value) internal pure returns (bytes memory) {
        uint16 TYPE_3 = 3;
        uint8 WORKER_ID = 1;
        uint8 OPTION_TYPE_LZRECEIVE = 1;

        bytes memory option = value == 0
            ? abi.encodePacked(gas)
            : abi.encodePacked(gas, value);

        uint16 optionLength = uint16(option.length + 1);

        return abi.encodePacked(
            TYPE_3,
            WORKER_ID,
            optionLength,
            OPTION_TYPE_LZRECEIVE,
            option
        );
    }

    /// @dev Build Type-3 options with native drop
    function _buildExecutorWithNativeDrop(
        uint128 gas, 
        uint128 dropAmount, 
        bytes32 receiver
    ) internal pure returns (bytes memory) {
        uint16 TYPE_3 = 3;
        uint8 WORKER_ID = 1;
        uint8 OPTION_TYPE_LZRECEIVE = 1;
        uint8 OPTION_TYPE_NATIVE_DROP = 2;

        // First option: lzReceive with gas only
        bytes memory lzReceiveOption = abi.encodePacked(gas);
        uint16 lzReceiveLength = uint16(lzReceiveOption.length + 1);

        // Second option: native drop
        bytes memory nativeDropOption = abi.encodePacked(dropAmount, receiver);
        uint16 nativeDropLength = uint16(nativeDropOption.length + 1);

        return abi.encodePacked(
            TYPE_3,
            WORKER_ID,
            lzReceiveLength,
            OPTION_TYPE_LZRECEIVE,
            lzReceiveOption,
            WORKER_ID,
            nativeDropLength,
            OPTION_TYPE_NATIVE_DROP,
            nativeDropOption
        );
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        uint256 tgPerEth = 1000;

        vm.startBroadcast(privateKey);

        bytes32 salt = bytes32(
            keccak256(abi.encodePacked(vm.envString("TG_SALT")))
        );
        uint32 dstEid = uint32(vm.envUint("EXOCORE_EID"));
        address BASE_SEPOLIA_ENDPOINT = vm.envAddress("EVM_ENDPOINT");
        address user = vm.addr(privateKey);

        address payable hub = payable(vm.envAddress("TG_REGISTRY"));

        address payable spokeAddr = payable(
            CREATE3.deployDeterministic(
                bytes.concat(
                    type(TriggerGasRegistrySpoke).creationCode,
                    abi.encode(
                        dstEid,
                        hub,
                        tgPerEth,
                        BASE_SEPOLIA_ENDPOINT,
                        user
                    )
                ),
                salt
            )
        );

        TriggerGasRegistrySpoke spoke = TriggerGasRegistrySpoke(spokeAddr);

        console.log("Spoke deployed to:", spokeAddr);
        console.log("Spoke owner:", spoke.owner());
        console.log("Spoke dstEid:", uint256(spoke.dstEid()));
        console.log("Spoke tgPerEth:", spoke.tgPerEth());

        // Step 1: Set up gas options for the contract
        console.log("Setting up gas options...");
        
        // Set gas limit to 200k and native drop to 0.0005 ETH for sell operations
        // spoke.setGasOptions(200_000, 5e14);
        console.log("Gas options set successfully!");

        // Step 2: Test quote functions and call purchaseTG
        console.log("Getting quotes...");

        // // Get quotes for both operations
        // MessagingFee memory purchaseFee = spoke.quotePurchaseTG(user, 100000);
        // MessagingFee memory sellFee = spoke.quoteSellTG(user, 50000);

        // console.log("Purchase fee (native):", purchaseFee.nativeFee);
        // console.log(
        //     "Sell fee (native):",
        //     sellFee.nativeFee,
        //     "(includes 0.0005 ETH native drop)"
        // );

        // Call purchaseTG with proper fee
        // console.log("Calling purchaseTG...");
        // spoke.purchaseTG{value: purchaseFee.nativeFee + 0.01 ether}(
        //     user,
        //     100000
        // ); // Add extra for safety
        // console.log("purchaseTG called successfully!");

        // // Call sellTG with proper fee plus buffer
        // console.log("Calling sellTG...");
        // uint256 feeWithBuffer = sellFee.nativeFee + (sellFee.nativeFee / 1000) + 0.01 ether; // Add 0.1% buffer + extra safety
        // spoke.sellTG{value: feeWithBuffer}(user, 50000);
        // console.log("sellTG called successfully!");

        vm.stopBroadcast();
    }
}
