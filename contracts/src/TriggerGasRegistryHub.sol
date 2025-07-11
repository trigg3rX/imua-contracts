// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OApp, MessagingFee, Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title TriggerGasRegistryHub (hub – Imua)
/// @notice Keeps canonical TG balances, callable by AVS contract or LayerZero OApp.
///         TG is an internal, non-transferable accounting unit (18 decimals).
///         Cross-chain purchase / withdrawal only adjusts balances; no mint/burn.
contract TriggerGasRegistryHub is Ownable, OApp{

    enum Action {
        CREDIT,
        DEBIT,
        RELEASE
    }

    address public immutable avs;

    mapping(address => uint256) public tgBalances;

    event TGcredited(address indexed user, uint256 tgAmount);
    event TGdebited(address indexed user, uint256 tgAmount);
    event TGdeducted(address indexed user, uint256 tgAmount);
    event releaseMessageSent(address indexed user, uint256 tgAmount);

    modifier onlyAVS() {
        require(msg.sender == avs, "Only AVS can call this function");
        _;
    }

    constructor(
        address _avs,
        address _endpoint,
        address _delegate
    ) Ownable(_delegate) OApp(_endpoint, _delegate) {
        avs = _avs;
    }

    receive() external payable {}

    function deductTG(address user, uint256 tgAmount) external onlyAVS {
        require(tgBalances[user] >= tgAmount, "Insufficient TG balance");
        tgBalances[user] -= tgAmount;
        emit TGdeducted(user, tgAmount);
    }

    function setSpokePeers(uint32[] calldata _spokeEids) external onlyOwner {
        for (uint256 i = 0; i < _spokeEids.length;) {
            _setPeer(_spokeEids[i], bytes32(uint256(uint160(address(this)))));
            unchecked {
                ++i;
            }
        }
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32, // _guid
        bytes calldata _message,
        address, // _executor
        bytes calldata // _extraData
    ) internal override {
        (address user, uint256 tgAmount, Action action) = abi.decode(
            _message,
            (address, uint256, Action)
        );

        if (action == Action.CREDIT) {
            tgBalances[user] += tgAmount;
            emit TGcredited(user, tgAmount);
        } else if (action == Action.DEBIT) {
            require(tgBalances[user] >= tgAmount, "Insufficient TG balance");
            tgBalances[user] -= tgAmount;
            _sendReleaseMessage(_origin.srcEid, user, tgAmount);
            emit TGdebited(user, tgAmount);
        }
    }

    function _sendReleaseMessage(
        uint32 srcEid,
        address user,
        uint256 tgAmount
    ) internal {
        bytes memory message = abi.encode(user, tgAmount, Action.RELEASE);

        _lzSend(
            srcEid,
            message,
            bytes(""),
            MessagingFee(msg.value, 0),
            payable(address(this))
        );
        emit releaseMessageSent(user, tgAmount);
    }
}
