// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/ICustomGateway.sol";
import "./CrosschainMessenger.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract L1TokenBridge is IL1CustomGateway, L1CrosschainMessenger, Ownable {
    address public router;
    address public l1CustomToken;
    address public l2CustomToken;
    address public l2Gateway;

    constructor(
        address _router,
        address _inboxContract
    ) L1CrosschainMessenger(_inboxContract) {
        router = _router;
    }

    function outboundTransfer(
        address _l1Token,
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data
    ) public payable override returns (bytes memory) {
        return
            outboundTransferCustomRefund(
                _l1Token,
                _to,
                _to,
                _amount,
                _maxGas,
                _gasPriceBid,
                _data
            );
    }

    function outboundTransferCustomRefund(
        address _l1Token,
        address _refundTo,
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data
    ) public payable override returns (bytes memory result) {
        require(msg.sender == router, "Call not received from router");
        require(
            _l1Token == l1CustomToken,
            "Token is not allowed through this gateway"
        );

        address from;
        uint256 seqNum;
        {
            bytes memory extraData;
            uint256 maxSubmissionCost;
            (from, maxSubmissionCost, extraData) = _parseOutboundData(_data);

            require(extraData.length == 0, "EXTRA_DATA_DISABLED");

            IERC20(_l1Token).transferFrom(from, address(this), _amount);

            result = getOutboundCalldata(
                _l1Token,
                from,
                _to,
                _amount,
                extraData
            );

            seqNum = _sendTxToL2CustomRefund(
                l2Gateway,
                _refundTo,
                from,
                msg.value,
                0,
                maxSubmissionCost,
                _maxGas,
                _gasPriceBid,
                result
            );
        }

        emit DepositInitiated(_l1Token, from, _to, seqNum, _amount);
        result = abi.encode(seqNum);
    }

    function setTokenBridgeInformation(
        address _l1CustomToken,
        address _l2CustomToken,
        address _l2Gateway
    ) public onlyOwner {
        require(
            l1CustomToken == address(0),
            "Token bridge information already set"
        );
        l1CustomToken = _l1CustomToken;
        l2CustomToken = _l2CustomToken;
        l2Gateway = _l2Gateway;
    }

    function finalizeInboundTransfer(
        address _l1Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) public payable override onlyCounterpartGateway(l2Gateway) {
        require(
            _l1Token == l1CustomToken,
            "Token is not allowed through this gateway"
        );

        (uint256 exitNum, ) = abi.decode(_data, (uint256, bytes));

        IERC20(_l1Token).transfer(_to, _amount);

        emit WithdrawalFinalized(_l1Token, _from, _to, exitNum, _amount);
    }

    function getOutboundCalldata(
        address _l1Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _data
    ) public pure override returns (bytes memory outboundCalldata) {
        bytes memory emptyBytes = "";

        outboundCalldata = abi.encodeWithSelector(
            ICustomGateway.finalizeInboundTransfer.selector,
            _l1Token,
            _from,
            _to,
            _amount,
            abi.encode(emptyBytes, _data)
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
        return l2Gateway;
    }

    function _parseOutboundData(
        bytes memory _data
    )
        internal
        pure
        returns (
            address from,
            uint256 maxSubmissionCost,
            bytes memory extraData
        )
    {
        (from, extraData) = abi.decode(_data, (address, bytes));

        (maxSubmissionCost, extraData) = abi.decode(
            extraData,
            (uint256, bytes)
        );
    }
}
