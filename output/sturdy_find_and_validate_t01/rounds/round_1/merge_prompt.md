Below are findings and vulnerability signals from 1 agents auditing the same codebase,
plus accumulated findings from previous rounds. You need to inspect the source code when needed.

You are the merge and review layer for a audit.

Your task:
- merge new or materially improved reportable issues into the accumulated findings
- reconstruct plausible but poorly written findings or signals into low-confidence findings when the code supports them
- reject clearly non-reportable candidates with your reasons
- try to use this round's signals and the source code to look for additional findings yourself

Prefer downgrading severity or confidence over discarding a plausible issue.
Keep findings that can cause realistic protocol-level harm, including fund loss,
theft, insolvency, permanent lockup, economic manipulation, or permissionless DoS and some other realistic issues.

## Accumulated Findings
[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "Transient Balancer `exitPool` state can inflate Balancer-LP collateral prices and bypass collateral-removal solvency checks",
    "locations": [
      "Contract.sol:288",
      "Contract.sol:291",
      "Contract.sol:302",
      "Contract.sol:306",
      "Contract.sol:318",
      "FlawVerifier.sol:361",
      "FlawVerifier.sol:362",
      "FlawVerifier.sol:399",
      "FlawVerifier.sol:400",
      "FlawVerifier.sol:366"
    ],
    "claim": "The PoC shows that `SturdyOracle.getAssetPrice(cB_stETH_STABLE)` returns a higher value from inside the ETH payout callback of `Balancer.exitPool(...)` than it did immediately before the exit. Because that callback can also invoke `setUserUseReserveAsCollateral(CSTECRV, false)`, the lending system is willing to make collateralization decisions from a transient, reentrancy-reachable Balancer pool state rather than a finalized one. Once `steCRV` has been switched off during that fake-health window, the attacker can still withdraw it after the LP price normalizes.",
    "impact": "An attacker can temporarily overvalue Balancer LP collateral inside one transaction, make an unsafe account appear healthy, disable honest collateral, and then withdraw that honest collateral after prices revert. The included forked exploit completes this sequence and extracts substantial profit, so the issue is directly fund-threatening.",
    "paths": [
      "Flash-loan `wstETH` and `WETH`, mint `B_STETH_STABLE`, and deposit both `B_STETH_STABLE` and `steCRV` as collateral before borrowing `WETH`.",
      "Call `Balancer.exitPool(...)`; during the first ETH callback, read the inflated `cB_stETH_STABLE` oracle price and call `setUserUseReserveAsCollateral(CSTECRV, false)` while solvency checks use the transient price.",
      "After control returns and the oracle price normalizes, call `withdrawCollateral(steCRV, ...)` to remove the real collateral and leave the debt backed only by the previously overvalued LP position."
    ],
    "round": 1,
    "source_agents": [
      "codex"
    ]
  }
]

## This Round's Agent Outputs
### Agent: codex
```
[
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "low",
    "title": "Transient Balancer-exit pricing window likely also enables over-borrowing, not only collateral removal",
    "locations": [
      "FlawVerifier.sol:79",
      "FlawVerifier.sol:221",
      "FlawVerifier.sol:320",
      "FlawVerifier.sol:382",
      "Contract.sol:32",
      "Contract.sol:286",
      "Contract.sol:294"
    ],
    "claim": "The verifier proves that `getAssetPrice(CB_STETH_STABLE)` is materially higher inside the Balancer `exitPool` callback than before or after exit, and that arbitrary lending-pool entrypoints can be invoked from that callback. Because `borrow()` is exposed through the same lending interface and relies on the same collateral accounting surface, the same manipulated window can likely be used to borrow against the inflated Balancer-LP valuation directly, rather than only to disable/remove other collateral.",
    "impact": "If reachable, an attacker can mint immediate bad debt by extracting borrowable assets while the LP collateral is temporarily overpriced, which is stronger than a mere collateral-removal bypass because it drains pool liquidity in the same manipulated transaction.",
    "paths": [
      "Acquire Balancer LP collateral",
      "Start `exitPool` on the LP",
      "Use the ETH callback while `getAssetPrice` is inflated",
      "Call `borrow()` before balances and pricing settle"
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Debtors can self-liquidate and internalize the liquidation bonus",
    "locations": [
      "FlawVerifier.sol:327",
      "FlawVerifier.sol:331",
      "Contract.sol:319",
      "Contract.sol:324"
    ],
    "claim": "The exploit path intentionally calls `liquidationCall(..., user = address(this), ...)` from the debtor account itself after making the position unhealthy, showing that the protocol permits self-liquidation instead of restricting liquidation to third parties.",
    "impact": "Once an attacker can push its own account below the health threshold, it can immediately seize its own collateral at the liquidation discount instead of leaving that discount to honest liquidators. This makes transient insolvency/oracle manipulation materially more profitable and lets the attacker reclaim discounted collateral before the market can correct the position.",
    "paths": [
      "Open leveraged position",
      "Make the account unhealthy",
      "Call `liquidationCall` with `user == msg.sender`",
      "Receive discounted collateral back into the attacker-controlled account"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "high",
    "title": "ERC20 helper libraries accept EOAs and non-contract addresses as successful token operations",
    "locations": [
      "interface.sol:4764",
      "interface.sol:4780",
      "interface.sol:5692",
      "interface.sol:5722",
      "interface.sol:5751"
    ],
    "claim": "Both `TransferHelper` and `SafeTransferLib` treat a low-level call with empty return data as success but never verify that the target token address actually has code. Calls to an EOA, a destroyed contract, or an undeployed address can therefore appear to succeed even though no ERC20 logic executed.",
    "impact": "Any downstream vault, lending market, or accounting contract that relies on these helpers with a misconfigured or user-influenced token address can credit deposits, consider repayments complete, or continue privileged flows even though no tokens moved, causing direct fund loss or insolvency.",
    "paths": [
      "Caller uses helper with an EOA/undeployed address as `token`",
      "Low-level call returns success with zero-length returndata",
      "Helper does not revert",
      "Caller updates balances/shares/debt as if the transfer or approval happened"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "high",
    "title": "safeApprove wrappers preserve the ERC20 allowance race condition",
    "locations": [
      "interface.sol:4764",
      "interface.sol:5751"
    ],
    "claim": "Both approval helpers directly overwrite allowances without first zeroing them or using a force-approve pattern, so changing a non-zero allowance to another non-zero allowance leaves the classic ERC20 front-run window open.",
    "impact": "A spender with an existing allowance can front-run an allowance update and spend the old allowance before the new approval lands, then spend the new allowance as well, draining more tokens than the caller intended.",
    "paths": [
      "Protocol approves spender for amount A",
      "Protocol later changes allowance directly to amount B",
      "Spender front-runs and consumes A before the update",
      "Spender then also consumes B after the update"
    ]
  },
  {
    "id": "F-006",
    "severity": "Low",
    "confidence": "medium",
    "title": "ETH helper functions forward all gas and turn payouts into reentrancy gadgets",
    "locations": [
      "interface.sol:4789",
      "interface.sol:5676"
    ],
    "claim": "Both ETH-transfer helpers use a raw `call` that forwards all remaining gas to the recipient, which means every caller that uses them inherits an externally controlled reentrancy point.",
    "impact": "Any downstream withdrawal, reward, or refund flow that updates state before invoking these helpers can be reentered by the recipient and drained or left in a corrupted accounting state.",
    "paths": [
      "Caller performs partial state updates",
      "Caller invokes `safeTransferETH` to an attacker-controlled recipient",
      "Recipient reenters caller with full gas before state is finalized"
    ]
  }
]

```



## Excluded From Direct Audit Scope
Do not keep findings whose reportable root cause exists solely in files matching:
- `out/**`

Those files may still be read as context for in-scope implementation code.


## Output
Return a JSON object with:
- `findings`: the COMPLETE updated findings list
- `rejected_candidates`: candidates rejected from this round, with concise reasons

Each `findings` element must have:
- `id`
- `severity`
- `confidence`
- `title`
- `locations`
- `claim`
- `impact`
- `paths`
- `round`
- `source_agents`

Preserve existing IDs for surviving findings whenever possible.
`source_agents` must include every agent that materially supports the final finding.

Each `rejected_candidates` element must have:
- `title`
- `source_agents`
- `reason`

Output ONLY valid JSON. No markdown. No prose.
