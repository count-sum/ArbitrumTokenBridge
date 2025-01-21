// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/ICustomToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IL1GatewayRouter {
    function setGateway(
        address gateway,
        uint256 maxGas,
        uint256 gasPriceBid,
        uint256 maxSubmissionCost,
        address creditBackAddress
    ) external payable returns (uint256);
}

contract L1ERC20Token is Ownable, ICustomToken, ERC20 {
    address public l1GatewayAddress;
    address public routerAddress;

    constructor(
        address _l1GatewayAddress,
        address _routerAddress,
        uint256 _initialSupply
    ) ERC20("L1DummyToken", "L1DT") {
        l1GatewayAddress = _l1GatewayAddress;
        routerAddress = _routerAddress;
        _mint(msg.sender, _initialSupply * 10 ** decimals());
    }

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) public override(ICustomToken, ERC20) returns (bool) {
        return super.transferFrom(_sender, _recipient, _amount);
    }

    function balanceOf(
        address _account
    ) public view override(ICustomToken, ERC20) returns (uint256) {
        return super.balanceOf(_account);
    }

    function isArbitrumEnabled() external pure returns (uint8) {
        return uint8(0xb1);
    }

    function registerTokenOnL2(
        address _l2CustomTokenAddress,
        uint256 _maxSubmissionCostForCustomGateway,
        uint256 _maxSubmissionCostForRouter,
        uint256 _maxGasForCustomGateway,
        uint256 _maxGasForRouter,
        uint256 _gasPriceBid,
        uint256 _valueForGateway,
        uint256 _valueForRouter,
        address _creditBackAddress
    ) public payable override onlyOwner {
        IL1GatewayRouter(routerAddress).setGateway{value: _valueForRouter}(
            l1GatewayAddress,
            _maxGasForRouter,
            _gasPriceBid,
            _maxSubmissionCostForRouter,
            _creditBackAddress
        );
    }
}
