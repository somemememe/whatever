You are fixing a failing Foundry PoC for finding F-004.

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
- Hard accounting constraint: profit must be reported in the original stolen token from the exploit path.
- Hard accounting constraint: do NOT add post-exploit conversion solely for accounting (e.g., converting to WETH for display).
- Hard accounting constraint: if a swap is strictly required for execution/repayment, profitToken must remain the originally stolen token and profitAmount must be net stolen-token inflow.

Finding:
- title: Permissionless zero-min-output swaps expose contract balances to sandwich extraction
- claim: `executeOnOpportunity()` is permissionless, and every router trade in `_prepareMakerCapital()`, `_swapUsdcForUsdt()`, and `_realizeProfitInWeth()` uses `amountOutMin = 1`. Any observer can manipulate the relevant Uniswap V2 pools immediately before calling or sandwiching execution, forcing the contract to accept almost any exchange rate.
- impact: ETH and USDC held by the contract can be converted at ruinous prices, with the attacker recovering the lost value in surrounding AMM trades.
- exploit_paths: ["Wait until the contract holds ETH or USDC and the one-shot execution path is still available.", "Skew the relevant `WETH/USDT`, `USDC/USDT`, or `USDC/WETH` pool immediately before invoking or sandwiching `executeOnOpportunity()`.", "Let the contract trade with `amountOutMin = 1`, then unwind the price manipulation and capture the spread."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

contract FlawVerifier {
    address private constant TARGET = 0xA88800CD213dA5Ae406ce248380802BD53b47647;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 private constant ETH_SEED_FOR_USDT = 0.01 ether;
    uint256 private constant FLASH_SEED_USDT = 1e6;
    uint256 private constant FLASH_REPAY_USDT = ((FLASH_SEED_USDT * 1000) / 997) + 1;
    uint256 private constant MAX_FLASH_REPAY_DEFICIT_USDT = FLASH_REPAY_USDT - FLASH_SEED_USDT;
    uint256 private constant HARNESS_MIN_PROFIT = 0.1 ether;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    bool private _hypothesisValidated;
    string private _pathUsed;
    string private _failureReason;

    constructor() {
        _profitToken = address(0);
    }

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;
        _profitAmount = 0;

        if (TARGET.code.length == 0) {
            _profitToken = address(0);
            _pathUsed = "wait until target holds ETH or USDC -> skew pool -> call executeOnOpportunity -> unwind";
            _failureReason = "target has no code at the fork block";
            return;
        }

        uint256 targetEth = TARGET.balance;
        uint256 targetUsdc = _safeBalanceOf(USDC, TARGET);
        uint256 targetUsdt = _safeBalanceOf(USDT, TARGET);

        if (targetEth < ETH_SEED_FOR_USDT && targetUsdc == 0) {
            _profitToken = address(0);
            _pathUsed =
                "wait until the target holds ETH or USDC and its one-shot path is still available -> skew WETH/USDT, USDC/USDT, or USDC/WETH immediately before invoking executeOnOpportunity -> let the target trade with amountOutMin = 1 -> unwind";
            _failureReason = "fork-state precondition missing: target holds less than 0.01 ETH and no USDC, so no finding-aligned victim inventory is available";
            return;
        }

        if (targetEth >= ETH_SEED_FOR_USDT) {
            _profitToken = WETH;
            _pathUsed =
                "wait for target ETH balance -> skew WETH/USDT immediately before invoking target.executeOnOpportunity() -> let _prepareMakerCapital() swap its fixed ETH seed with amountOutMin = 1 -> unwind into WETH";

            // Standalone F-004 infeasibility proof for the ETH leg:
            // - The finding-aligned swap in `_prepareMakerCapital()` is hard-capped by source at
            //   exactly `ETH_SEED_FOR_USDT = 0.01 ether`.
            // - A sandwich can never extract more gross value than the victim trade places at risk.
            // - Therefore the absolute upper bound for this path is `< 0.01 ETH`, which is already
            //   below the harness profit floor of `0.1 ETH` before paying any AMM fees or flash-loan fee.
            _failureReason = string(
                abi.encodePacked(
                    "ETH path is economically infeasible at this fork: the only directly reachable zero-min-output victim swap spends a fixed 0.01 ETH in _prepareMakerCapital(), so gross extractable value is bounded below the 0.1 ETH validation threshold"
                )
            );
            return;
        }

        _profitToken = USDC;
        _pathUsed =
            "wait for target USDC balance -> skew USDC/USDT or USDC/WETH immediately before invoking target.executeOnOpportunity() -> let the target trade with amountOutMin = 1 -> unwind into the stolen token";

        // Standalone F-004 infeasibility proof for the USDC legs:
        // - `_swapUsdcForUsdt()` is only reached while repaying the contract's own 1 USDT flash seed.
        // - Without relying on the unrelated settlement-corruption findings, the maximum natural
        //   deficit is the flash fee: `FLASH_REPAY_USDT - FLASH_SEED_USDT = 3,010` USDT units,
        //   i.e. about `0.00301 USDT`. The function then clamps to a minimum input of exactly 1 USDC.
        // - `_realizeProfitInWeth()` only sells *newly created* USDC profit from the unrelated
        //   settlement path because the target snapshots `_usdcBaseline` at the start of the same
        //   `executeOnOpportunity()` call. Pre-existing USDC on the target does not enter that leg.
        // - So this finding alone does not create a large USDC victim trade to sandwich.
        _failureReason = string(
            abi.encodePacked(
                "USDC paths are not independently reachable from F-004 alone at this fork: _swapUsdcForUsdt() only exposes the tiny flash-repay deficit (max ",
                _toString(MAX_FLASH_REPAY_DEFICIT_USDT),
                " USDT units, then clamped to 1 USDC), while _realizeProfitInWeth() only sells newly created USDC profit from the unrelated settlement path; pre-existing target USDC (currently ",
                _toString(targetUsdc),
                ") and USDT (currently ",
                _toString(targetUsdt),
                ") do not by themselves trigger a large finding-aligned victim swap"
            )
        );
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPathUsed() external view returns (string memory) {
        return _pathUsed;
    }

    function failureReason() external view returns (string memory) {
        return _failureReason;
    }

    function harnessMinProfit() external pure returns (uint256) {
        return HARNESS_MIN_PROFIT;
    }

    function target() external pure returns (address) {
        return TARGET;
    }

    function targetEthBalance() external view returns (uint256) {
        return TARGET.balance;
    }

    function targetUsdcBalance() external view returns (uint256) {
        return _safeBalanceOf(USDC, TARGET);
    }

    function targetUsdtBalance() external view returns (uint256) {
        return _safeBalanceOf(USDT, TARGET);
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, account));
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            unchecked {
                ++digits;
            }
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            unchecked {
                digits -= 1;
            }
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.34s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:77:19:
   |
77 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 625551)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 577021548053172
  AUDITHOUND_BALANCE_AFTER_WEI: 577021548053172
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 2186

Traces:
  [625551] FlawVerifierTest::testExploit()
    ├─ [2345] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2388] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [582569] FlawVerifier::executeOnOpportunity()
    │   ├─ [9839] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0xA88800CD213dA5Ae406ce248380802BD53b47647) [staticcall]
    │   │   ├─ [2553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(0xA88800CD213dA5Ae406ce248380802BD53b47647) [delegatecall]
    │   │   │   └─ ← [Return] 4112012 [4.112e6]
    │   │   └─ ← [Return] 4112012 [4.112e6]
    │   ├─ [5031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0xA88800CD213dA5Ae406ce248380802BD53b47647) [staticcall]
    │   │   └─ ← [Return] 2736514 [2.736e6]
    │   └─ ← [Stop]
    ├─ [345] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    ├─ [3339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   ├─ [2553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return] 0
    ├─ [388] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 21982110 [2.198e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 2186)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 63.21ms (37.04ms CPU time)

Ran 1 test suite in 78.13ms (63.21ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 625551)

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
