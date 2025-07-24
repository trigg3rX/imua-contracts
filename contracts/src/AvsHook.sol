// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IAvsHook} from "./interfaces/IAvsHook.sol";
import {OApp, MessagingFee, Origin, MessagingReceipt} from "@layerzero-v2/oapp/contracts/oapp/OApp.sol";
import {ILayerZeroEndpointV2, MessagingParams} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AvsGovernanceLogic
 * @notice A LayerZero-enabled contract that manages operator registration and cross-chain communication
 * @dev This contract handles operator registration and broadcasts updates to the L2 network
 */
contract AvsHook is Ownable, IAvsHook, OApp {
    /**
     * @notice Enum defining the types of actions that can be performed on operators
     */
    enum ActionType {
        REGISTER,
        UNREGISTER
    }

    /**
     * @notice Structure to store failed message attempts for retry
     */
    struct FailedMessage {
        ActionType action;
        address operator;
        uint256 timestamp;
        uint8 retryCount;
    }

    address public taskExecutionHub;
    address public immutable avsAddress;

    uint32 public immutable dstEid;

    uint128 public gasLimit = 1_000_000;
    uint128 public callValue = 0;

    event OperatorRegistered(address indexed operator);
    event OperatorUnregistered(address indexed operator);
    event LowBalanceAlert(uint256 currentBalance, uint256 threshold);
    event MessageSent(uint32 indexed dstEid, bytes32 indexed guid, uint256 fee);
    event GasOptionsUpdated(uint128 gasLimit, uint128 callValue);

    /**
     * @notice Emitted when a message fails to send
     * @param dstEid The destination chain endpoint ID
     * @param guid The message GUID
     * @param reason The reason for the failure
     */
    event MessageFailed(
        uint32 indexed dstEid,
        bytes32 indexed guid,
        bytes reason
    );

    /**
     * @notice Modifier to check if the caller is AVS
     */
    modifier onlyAvsGovernance() {
        require(msg.sender == avsAddress, "Only AVS can call this function");
        _;
    }

    /**
     * @notice Constructor for the AvsGovernanceLogic contract
     * @param _endpoint The LayerZero endpoint address
     * @param _taskExecutionHub The address of the L2 task execution hub contract
     * @param _dstEid The destination chain endpoint ID
     * @param _ownerAddress The owner address
     * @param _avsAddress The address of the AVS contract
     */
    constructor(
        address _endpoint,
        address _taskExecutionHub,
        uint32 _dstEid,
        address _ownerAddress,
        address _avsAddress
    ) OApp(_endpoint, _ownerAddress) Ownable(_ownerAddress) {
        require(_taskExecutionHub != address(0), "Invalid taskExecutionHub");
        require(_avsAddress != address(0), "Invalid avsAddress");
        taskExecutionHub = _taskExecutionHub;
        dstEid = _dstEid;
        avsAddress = _avsAddress;
        _setPeer(dstEid, bytes32(uint256(uint160(_taskExecutionHub))));
    }   

    /**
     * @notice Updates the task execution hub address
     * @param _taskExecutionHub The new task execution hub address
     */
    function setTaskExecutionHub(address _taskExecutionHub) external onlyOwner {
        require(_taskExecutionHub != address(0), "Invalid task execution hub address");
        taskExecutionHub = _taskExecutionHub;
        _setPeer(dstEid, bytes32(uint256(uint160(_taskExecutionHub))));
    }

    /**
     * @notice Allows the owner to withdraw ETH from the contract
     * @param _to The address to send the ETH to
     * @param _amount The amount of ETH to withdraw
     */
    function withdraw(address payable _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "Invalid recipient");
        require(_amount > 0, "Amount must be greater than 0");
        require(address(this).balance >= _amount, "Insufficient balance");
        _to.transfer(_amount);
    }

    /**
     * @notice Hook called before an operator is registered
     * @param _operator The address of the operator to be registered
     */
    function beforeOperatorOptIn(address _operator) external override onlyAvsGovernance {
        if (address(this).balance < 1e16) emit LowBalanceAlert(address(this).balance, 1e16);
    }

    /**
     * @notice Hook called after an operator is registered
     * @param _operator The address of the registered operator
     */
    // slither-disable-next-line reentrancy-events
    function afterOperatorOptIn(address _operator) external override onlyAvsGovernance {
        bytes memory payload = abi.encode(ActionType.REGISTER, _operator);
        bytes memory options = _buildExecutorOptions(gasLimit, callValue);

        try
            endpoint.quote(
                MessagingParams({
                    dstEid: dstEid,
                    receiver: bytes32(uint256(uint160(taskExecutionHub))),
                    message: payload,
                    options: options,
                    payInLzToken: false
                }),
                address(this)
            )
        returns (MessagingFee memory fee) {
            // Add 10% buffer to account for gas price fluctuations
            uint256 feeWithBuffer = fee.nativeFee + (fee.nativeFee * 10) / 100;
            require(
                address(this).balance >= feeWithBuffer,
                "Insufficient balance for message fee (with 10% buffer)"
            );

            MessagingReceipt memory receipt = _lzSend(
                dstEid,
                payload,
                options,
                fee,
                payable(address(this))
            );

            emit MessageSent(dstEid, receipt.guid, fee.nativeFee);
            emit OperatorRegistered(_operator);
        } catch (bytes memory reason) {
            emit MessageFailed(dstEid, bytes32(0), reason);
            revert(
                string(abi.encodePacked("Register failed: ", string(reason)))
            );
        }
    }

    /**
     * @notice Hook called before an operator is unregistered
     */
    function beforeOperatorOptOut(address) external override onlyAvsGovernance {}

    /**
     * @notice Hook called after an operator is unregistered
     * @param _operator The address of the unregistered operator
     */
    // slither-disable-next-line reentrancy-events
    function afterOperatorOptOut(address _operator) external override onlyAvsGovernance {
        bytes memory payload = abi.encode(ActionType.UNREGISTER, _operator);
        bytes memory options = _buildExecutorOptions(gasLimit, callValue);

        try
            endpoint.quote(
                MessagingParams({
                    dstEid: dstEid,
                    receiver: bytes32(uint256(uint160(taskExecutionHub))),
                    message: payload,
                    options: options,
                    payInLzToken: false
                }),
                address(this)
            )
        returns (MessagingFee memory fee) {
            // Add 10% buffer to account for gas price fluctuations
            uint256 feeWithBuffer = fee.nativeFee + (fee.nativeFee * 10) / 100;
            require(
                address(this).balance >= feeWithBuffer,
                "Insufficient balance for message fee (with 10% buffer)"
            );

            MessagingReceipt memory receipt = _lzSend(
                dstEid,
                payload,
                options,
                fee,
                payable(address(this))
            );

            emit MessageSent(dstEid, receipt.guid, fee.nativeFee);
            emit OperatorUnregistered(_operator);
        } catch (bytes memory reason) {
            emit MessageFailed(dstEid, bytes32(0), reason);
            revert(
                string(abi.encodePacked("Unregister failed: ", string(reason)))
            );
        }
    }

    /**
     * @notice Handles incoming LayerZero messages
     * @dev This contract should not receive messages
     */
    // slither-disable-next-line dead-code
    function _lzReceive(
        Origin calldata,
        bytes32,
        bytes calldata,
        address,
        bytes calldata
    ) internal pure override {
        revert("AvsGovernanceLogic: should not receive messages");
    }

    /**
     * @notice Builds executor options for LayerZero messages
     * @param gas The gas limit for the message
     * @param value The value to be sent with the message
     * @return The encoded options
     */
    function _buildExecutorOptions(
        uint128 gas,
        uint128 value
    ) internal pure returns (bytes memory) {
        uint16 TYPE_3 = 3;
        uint8 WORKER_ID = 1;
        uint8 OPTION_TYPE_LZRECEIVE = 1;

        bytes memory option = value == 0
            ? abi.encodePacked(gas)
            : abi.encodePacked(gas, value);

        uint16 optionLength = uint16(option.length + 1);

        return
            abi.encodePacked(
                TYPE_3,
                WORKER_ID,
                optionLength,
                OPTION_TYPE_LZRECEIVE,
                option
            );
    }

    /**
     * @notice Updates the gas configuration for cross-chain messages
     * @param _gasLimit The new gas limit
     * @param _callValue The new call value
     */
    function setGasOptions(
        uint128 _gasLimit,
        uint128 _callValue
    ) external onlyOwner {
        gasLimit = _gasLimit;
        callValue = _callValue;
        emit GasOptionsUpdated(_gasLimit, _callValue);
    }

    /**
     * @notice Override _payNative to use contract balance instead of msg.value
     * @param _nativeFee The native fee to be paid
     * @return nativeFee The amount of native currency paid
     */
    // slither-disable-next-line dead-code
    function _payNative(
        uint256 _nativeFee
    ) internal view override returns (uint256 nativeFee) {
        require(
            address(this).balance >= _nativeFee,
            "Insufficient contract balance"
        );
        return _nativeFee;
    }

    /**
     * @notice Allows the contract to receive ETH
     */
    receive() external payable {}
}
