// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/ICustomGateway.sol";
import "./CrosschainMessenger.sol";
import "./interfaces/IArbToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract L2TokenBridge is IL2CustomGateway, L2CrosschainMessenger, Ownable {
    address public router;
    address public l1CustomToken;
    address public l2CustomToken;
    address public l1Gateway;
    uint256 public exitNum;

    constructor(address _router) {
        router = _router;
    }

    function setTokenBridgeInformation(
        address _l1CustomToken,
        address _l2CustomToken,
        address _l1Gateway
    ) public onlyOwner {
        require(
            l1CustomToken == address(0),
            "Token bridge information already set"
        );
        l1CustomToken = _l1CustomToken;
        l2CustomToken = _l2CustomToken;
        l1Gateway = _l1Gateway;
    }

    function outboundTransfer(
        address _l1Token,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) public payable returns (bytes memory) {
        return outboundTransfer(_l1Token, _to, _amount, 0, 0, _data);
    }

    function outboundTransfer(
        address _l1Token,
        address _to,
        uint256 _amount,
        uint256,
        uint256,
        bytes calldata _data
    ) public payable override returns (bytes memory result) {
        require(msg.value == 0, "NO_VALUE");
        require(
            _l1Token == l1CustomToken,
            "Token is not allowed through this gateway"
        );

        (address from, bytes memory extraData) = _parseOutboundData(_data);

        require(extraData.length == 0, "EXTRA_DATA_DISABLED");
        IArbToken(l2CustomToken).bridgeBurn(from, _amount);

        // Current exit number for this operation
        uint256 currExitNum = exitNum++;

        result = getOutboundCalldata(_l1Token, from, _to, _amount, extraData);

        uint256 id = _sendTxToL1(from, l1Gateway, result);

        emit WithdrawalInitiated(_l1Token, from, _to, id, currExitNum, _amount);
        return abi.encode(id);
    }

    function finalizeInboundTransfer(
        address _l1Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) public payable override onlyCounterpartGateway(l1Gateway) {
        require(
            _l1Token == l1CustomToken,
            "Token is not allowed through this gateway"
        );

        (, bytes memory callHookData) = abi.decode(_data, (bytes, bytes));
        if (callHookData.length != 0) {
            callHookData = bytes("");
        }

        // Mints L2 tokens
        IArbToken(l2CustomToken).bridgeMint(_to, _amount);

        emit DepositFinalized(_l1Token, _from, _to, _amount);
    }

    function getOutboundCalldata(
        address _l1Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _data
    ) public view override returns (bytes memory outboundCalldata) {
        outboundCalldata = abi.encodeWithSelector(
            ICustomGateway.finalizeInboundTransfer.selector,
            _l1Token,
            _from,
            _to,
            _amount,
            abi.encode(exitNum, _data)
        );

        return outboundCalldata;
    }

    function calculateL2TokenAddress(
        address _l1Token
    ) public view override returns (address) {
        if (_l1Token == l1CustomToken) {
            return l2CustomToken;
        }

        return address(0);
    }

    function counterpartGateway() public view override returns (address) {
        return l1Gateway;
    }

    function _parseOutboundData(
        bytes memory _data
    ) internal view returns (address from, bytes memory extraData) {
        if (msg.sender == router) {
            (from, extraData) = abi.decode(_data, (address, bytes));
        } else {
            from = msg.sender;
            extraData = _data;
        }
    }
}
