// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IArbToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract L2ERC20Token is ERC20, IArbToken {
    address public l2GatewayAddress;
    address public override l1Address;

    modifier onlyL2Gateway() {
        require(msg.sender == l2GatewayAddress, "NOT_GATEWAY");
        _;
    }

    constructor(
        address _l2GatewayAddress,
        address _l1TokenAddress
    ) ERC20("L2DummyToken", "L2DT") {
        l2GatewayAddress = _l2GatewayAddress;
        l1Address = _l1TokenAddress;
    }

    function bridgeMint(
        address _account,
        uint256 _amount
    ) external override onlyL2Gateway {
        _mint(_account, _amount);
    }

    function bridgeBurn(
        address _account,
        uint256 _amount
    ) external override onlyL2Gateway {
        _burn(_account, _amount);
    }
}
