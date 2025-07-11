// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OApp, MessagingFee, Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OAppOptionsType3} from "@layerzerolabs/oapp-evm/contracts/oapp/OAppOptionsType3.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TriggerGasRegistrySpoke is Ownable, OApp {
    enum Action {
        CREDIT,
        DEBIT,
        RELEASE
    }

    uint32 public immutable dstEid;

    uint256 public tgPerEth;

    event TGpurchased(address indexed user, uint256 tgAmount);
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
        MessagingFee memory fee = _quote(dstEid, abi.encode(user, tgAmount, Action.CREDIT), bytes(""), false);
        require(msg.value >= fee.nativeFee + (tgAmount / tgPerEth), "Insufficient native fee");
        _lzSend(
            dstEid,
            abi.encode(user, tgAmount, Action.CREDIT),
            ,
            MessagingFee(fee.nativeFee, 0),
            payable(msg.sender)
        );
        emit TGpurchased(user, tgAmount);
    }

    function sellTG(address user, uint256 tgAmount) external payable {
        _lzSend(
            dstEid,
            abi.encode(user, tgAmount, Action.DEBIT),
            bytes(""),
            MessagingFee(msg.value, 0),
            payable(msg.sender)
        );
        emit sellTGRequested(user, tgAmount);
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
}
