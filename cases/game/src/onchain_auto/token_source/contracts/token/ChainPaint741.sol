//ChainPaint is a gamified art project fully hosted on-chain, where participants use ERC20 $PXL tokens to collectively paint a live ERC721 canvas to create a unique piece of bitmap art - saved permanently to the blockchain.

//TG: t.me/ChainPaint
//X: twitter.com/ChainPaint

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./PoolCreatableErc741.sol";
import "../lib/Ownable.sol";

contract ChainPaint741 is PoolCreatableErc741, Ownable {
    uint256 constant _startTotalSupply = 100000 * (10 ** _decimals);
    uint256 constant _startMaxBuyCount = (_startTotalSupply * 5) / 10000;
    uint256 constant _addMaxBuyPercentPerSec = 1; // 100%=_addMaxBuyPrecesion add 0.005%/second
    uint256 constant _addMaxBuyPrecesion = 10000;
    uint256 _taxBuy = 250;
    uint256 _taxSell = 250;
    uint256 constant _taxPrecesion = 1000;
    uint256 constant _transferZeroTaxSeconds = 1000; // zero tax transfer time
    address _deployer;
    address immutable _withdrawer;
    address public immutable rewardPool;
    uint256 public devShare = 50;
    uint256 public devSharePrecision = 100;
    uint256 public devShareMax = 50;

    constructor(
        address rewardPool_,
        address routerAddress
    ) PoolCreatableErc741("ChainPaint", "PXL", routerAddress) {
        _deployer = msg.sender;
        _withdrawer = msg.sender;
        rewardPool = rewardPool_;
    }

    modifier maxBuyLimit(uint256 amount) {
        require(amount <= maxBuy(), "max buy limit");
        _;
    }

    receive() external payable {
        uint256 devFee = (msg.value * devShare) / devSharePrecision;
        bool sent;
        if (devFee > 0) {
            (sent, ) = payable(_withdrawer).call{value: devFee}("");
            require(sent, "sent fee error: dev ether is not sent");
        }
        (sent, ) = payable(rewardPool).call{value: msg.value - devFee}("");
        require(sent, "sent fee error: rewardPool ether is not sent");
    }

    function setTax(uint256 taxBuy, uint256 taxSell) external onlyOwner {
        require(taxBuy < 250);
        require(taxSell < 250);
        _taxBuy = taxBuy;
        _taxSell = taxSell;
    }

    function setDevShare(uint256 newDevShare) external onlyOwner {
        require(newDevShare <= devShareMax);
        devShare = newDevShare;
    }

    function createPairCount() internal pure override returns (uint256) {
        return _startTotalSupply;
    }

    function maxBuy() public view returns (uint256) {
        if (!isStarted()) return _startTotalSupply;
        uint256 count = _startMaxBuyCount +
            (_startTotalSupply *
                (block.timestamp - _startTime) *
                _addMaxBuyPercentPerSec) /
            _addMaxBuyPrecesion;
        if (count > _startTotalSupply) count = _startTotalSupply;
        return count;
    }

    function transferTax() public view returns (uint256) {
        if (!isStarted()) return 0;
        uint256 deltaTime = block.timestamp - _startTime;
        if (deltaTime >= _transferZeroTaxSeconds) return 0;
        return
            (_taxPrecesion * (_transferZeroTaxSeconds - deltaTime)) /
            _transferZeroTaxSeconds;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        // allow burning
        if (to == address(0)) {
            _burn(from, amount);
            return;
        }

        // system transfers
        if (
            from == address(0) ||
            from == address(this) ||
            from == _deployer ||
            to == _deployer
        ) {
            super._transfer(from, to, amount);
            return;
        }

        // transfers with fee
        if (_feeLocked) {
            super._transfer(from, to, amount);
            return;
        } else {
            if (from == _pair) {
                buy(to, amount);
                return;
            } else if (to == _pair) {
                sell(from, amount);
                return;
            } else transferFithFee(from, to, amount);
        }
    }

    function buy(
        address to,
        uint256 amount
    ) private maxBuyLimit(amount) lockFee {
        uint256 tax = (amount * _taxBuy) / _taxPrecesion;
        if (tax > 0) super._transfer(_pair, address(this), tax);
        super._transfer(_pair, to, amount - tax);
    }

    function sell(address from, uint256 amount) private lockFee {
        _sellTokens();
        uint256 tax = (amount * _taxBuy) / _taxPrecesion;
        if (tax > 0) super._transfer(from, address(this), tax);
        super._transfer(from, _pair, amount - tax);
    }

    function _sellTokens() private {
        uint256 sellCount = balanceOf(address(this));
        uint256 maxSwapCount = sellCount * 2;
        if (sellCount > maxSwapCount) sellCount = maxSwapCount;
        _sellTokens(sellCount, address(this));
    }

    function transferFithFee(
        address from,
        address to,
        uint256 amount
    ) private lockFee {
        uint256 tax = (amount * transferTax()) / _taxPrecesion;
        if (tax > 0) _burn(from, tax);
        super._transfer(from, to, amount - tax);
    }

    function burnCount() public view returns (uint256) {
        return _startTotalSupply - totalSupply();
    }
}
