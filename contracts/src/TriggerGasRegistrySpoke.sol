// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OApp, MessagingFee, Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OAppOptionsType3} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";

contract TriggerGasRegistrySpoke is OAppOptionsType3, OApp {
    enum Action {
        CREDIT,
        DEBIT,
        RELEASE
    }

    uint32 public immutable dstEid;
    uint256 public tgPerEth;

    // Default gas limit for cross-chain messages
    uint128 public gasLimit = 200_000;
    
    // Native drop amount for sell operations (0.0005 ETH)
    uint128 public nativeDropAmount = 5e14;

    // Message types for enforced options
    uint16 public constant MSG_TYPE_PURCHASE = 1;
    uint16 public constant MSG_TYPE_SELL = 2;

    event TGpurchased(address indexed user, uint256 tgAmount, uint256 ethAmount);
    event sellTGRequested(address indexed user, uint256 tgAmount);
    event ethReleased(address indexed user, uint256 tgAmount, uint256 ethAmount);
    event TGPerEthUpdated(uint256 tgPerEth);

    constructor(
        uint32 _dstEid,
        address _hub,
        uint256 _tgPerEth,
        address _endpoint,
        address _delegate
    ) Ownable(_delegate) OApp(_endpoint, _delegate) {
        dstEid = _dstEid;
        tgPerEth = _tgPerEth;
        _setPeer(dstEid, bytes32(uint256(uint160(_hub))));
    }

    function purchaseTG(address user, uint256 tgAmount) external payable {

        bytes memory executorOptions = _buildExecutorOptions(gasLimit, 0);

        // Use enforced options for purchase message type
        bytes memory options = this.combineOptions(dstEid, MSG_TYPE_PURCHASE, executorOptions);
        
        uint256 ethAmount = tgAmount / tgPerEth;

        // For purchase, we don't need return options since no ETH is returned
        bytes memory returnOptions = new bytes(0);

        // Quote the cross-chain fee so that the caller can provide enough ETH.
        MessagingFee memory fee = _quote(dstEid, abi.encode(user, tgAmount, Action.CREDIT, returnOptions), options, false);
        require(msg.value >= fee.nativeFee + ethAmount, "Insufficient native fee");

        uint256 feeToUse = msg.value - ethAmount;  // Actual fee amount after subtracting ETH amount

        _lzSend(
            dstEid,
            abi.encode(user, tgAmount, Action.CREDIT, returnOptions),
            options,
            MessagingFee(feeToUse, 0),
            payable(msg.sender)
        );
        emit TGpurchased(user, tgAmount, ethAmount);
    }

    function sellTG(address user, uint256 tgAmount) external payable {

        bytes memory executorOptions = _buildExecutorWithNativeDrop(
            gasLimit, 
            nativeDropAmount, 
            bytes32(uint256(uint160(address(this))))
        );

        bytes memory returnOptions = _buildExecutorOptions(gasLimit, 0);

        // Use enforced options for sell message type
        bytes memory options = this.combineOptions(dstEid, MSG_TYPE_SELL, executorOptions);

        // Quote the fee for this message so the caller knows the minimum required.
        MessagingFee memory fee = _quote(dstEid, abi.encode(user, tgAmount, Action.DEBIT, returnOptions), options, false);
        require(msg.value >= fee.nativeFee, "Insufficient native fee");

        _lzSend(
            dstEid,
            abi.encode(user, tgAmount, Action.DEBIT, returnOptions),
            options,
            MessagingFee(msg.value, 0),  // Use actual msg.value instead of quoted fee
            payable(msg.sender)
        );
        emit sellTGRequested(user, tgAmount);
    }

    /**
     * @notice Get a quote for sellTG operation
     * @param user The user address
     * @param tgAmount The trigger gas amount
     * @return fee The messaging fee required (includes native drop if configured)
     */
    function quoteSellTG(address user, uint256 tgAmount) external view returns (MessagingFee memory fee) {
        
        bytes memory executorOptions = _buildExecutorWithNativeDrop(
            gasLimit, 
            nativeDropAmount, 
            bytes32(uint256(uint160(address(this))))
        );
        bytes memory returnOptions = _buildExecutorOptions(gasLimit, 0);
        bytes memory options = this.combineOptions(dstEid, MSG_TYPE_SELL, executorOptions);
        return _quote(dstEid, abi.encode(user, tgAmount, Action.DEBIT, returnOptions), options, false);
    }

    /**
     * @notice Get a quote for purchaseTG operation
     * @param user The user address
     * @param tgAmount The trigger gas amount
     * @return fee The messaging fee required
     */
    function quotePurchaseTG(address user, uint256 tgAmount) external view returns (MessagingFee memory fee) {
        bytes memory executorOptions = _buildExecutorOptions(gasLimit, 0);
        bytes memory returnOptions = new bytes(0);  // No return options for purchase
        bytes memory options = this.combineOptions(dstEid, MSG_TYPE_PURCHASE, executorOptions);
        return _quote(dstEid, abi.encode(user, tgAmount, Action.CREDIT, returnOptions), options, false);
    }

    function _lzReceive(
        Origin calldata, // _origin
        bytes32, // _guid
        bytes calldata _message,
        address, // _executor
        bytes calldata // _extraData
    ) internal override {
        (address user, uint256 tgAmount, Action action) = abi.decode(
            _message,
            (address, uint256, Action)
        );
        if (action == Action.RELEASE) {
            _releaseETH(user, tgAmount);
        }
    }

    function _releaseETH(address user, uint256 tgAmount) internal {
        uint256 ethAmount = tgAmount / tgPerEth;
        payable(user).transfer(ethAmount);
        emit ethReleased(user, tgAmount, ethAmount);
    }

    function setTGPerEth(uint256 _tgPerEth) external onlyOwner {
        require(_tgPerEth > 0, "TGPerEth must be greater than 0");
        tgPerEth = _tgPerEth;
        emit TGPerEthUpdated(tgPerEth);
    }

    function _payNative(uint256 _nativeFee) internal override returns (uint256 nativeFee) {
        if (msg.value < _nativeFee) revert NotEnoughNative(msg.value);
        return _nativeFee;
    }

    /**
     * @notice Updates the gas configuration for cross-chain messages
     * @param _gasLimit The new gas limit
     * @param _nativeDropAmount The new native drop amount for sell operations
     */
    function setGasOptions(uint128 _gasLimit, uint128 _nativeDropAmount) external onlyOwner {
        gasLimit = _gasLimit;
        nativeDropAmount = _nativeDropAmount;
    }

    /**
     * @notice Build Type-3 executor options for LayerZero messages
     * @param gas The gas limit for the message
     * @param value The value to be sent with the message
     * @return The encoded options
     */
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

    /**
     * @notice Build Type-3 options with native drop
     * @param gas The gas limit for lzReceive
     * @param dropAmount The amount to drop natively 
     * @param receiver The receiver of the native drop
     * @return The encoded options with native drop
     */
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
}
