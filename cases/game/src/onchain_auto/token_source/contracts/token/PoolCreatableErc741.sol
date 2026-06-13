// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./ERC741.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "../lib/Ownable.sol";

abstract contract PoolCreatableErc741 is ERC741 {
    IUniswapV2Router02 immutable uniswapV2Router;
    address internal _pair;
    uint256 internal _startTime;
    bool internal _feeLocked;

    constructor(
        string memory name_,
        string memory symbol_,
        address routerAddress
    ) ERC741(name_, symbol_) {
        uniswapV2Router = IUniswapV2Router02(routerAddress);
    }

    modifier lockFee() {
        _feeLocked = true;
        _;
        _feeLocked = false;
    }

    function createPair() external payable {
        _pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this),
            uniswapV2Router.WETH()
        );
        _mint(address(this), createPairCount());
        _approve(address(this), address(uniswapV2Router), type(uint256).max);
        uniswapV2Router.addLiquidityETH{value: msg.value}(
            address(this),
            createPairCount(),
            0,
            0,
            msg.sender,
            block.timestamp
        );
        _startTime = block.timestamp;
    }

    function isStarted() internal view returns (bool) {
        return _pair != address(0);
    }

    function createPairCount() internal pure virtual returns (uint256);

    function _sellTokens(uint256 tokenAmount, address to) internal lockFee {
        if (tokenAmount == 0) return;
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        // make the swap
        uniswapV2Router.swapExactTokensForETH(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            to,
            block.timestamp
        );
    }
}
