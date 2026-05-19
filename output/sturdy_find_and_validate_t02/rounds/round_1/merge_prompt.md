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
None yet.

## This Round's Agent Outputs
### Agent: codex
```
[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "Balancer LP collateral is priced from a transient, callback-visible state",
    "locations": [
      "FlawVerifier.sol:320",
      "FlawVerifier.sol:385",
      "FlawVerifier.sol:221",
      "Contract.sol:286",
      "Contract.sol:302"
    ],
    "claim": "The exploit records `getAssetPrice(CB_STETH_STABLE)` immediately before `exitPool`, again inside the ETH-receiving callback, and again after the exit completes; `hypothesisValidated = duringPrice > beforePrice && duringPrice > afterPrice` shows the oracle is reading a temporary Balancer pool state that becomes observable during `exitPool` reentrancy. That makes the B-stETH-STABLE collateral price flash-manipulable within a single transaction.",
    "impact": "Any health-factor check that trusts this price can be bypassed with flash liquidity. An attacker can temporarily inflate LP collateral value, unlock otherwise-disallowed credit actions, and leave the protocol undercollateralized or insolvent after the pool state normalizes.",
    "paths": [
      "Flash-loan WSTETH/WETH -> join `B_STETH_STABLE` -> deposit BPT as collateral -> borrow WETH -> call `BALANCER.exitPool(...)` -> during callback read inflated `STURDY_ORACLE.getAssetPrice(CB_STETH_STABLE)`"
    ]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "high",
    "title": "Collateral usage can be disabled during the manipulated-price callback and withdrawn after normalization",
    "locations": [
      "FlawVerifier.sol:382",
      "FlawVerifier.sol:386",
      "FlawVerifier.sol:328",
      "Contract.sol:305",
      "Contract.sol:318"
    ],
    "claim": "While `exitPool` is still in progress, the callback calls `LENDING_POOL.setUserUseReserveAsCollateral(CSTECRV, false)` exactly when the LP oracle is inflated, then later `withdrawCollateral(STECRV, ...)` succeeds after the temporary price spike disappears. This means collateral-configuration changes rely on an instantaneous, manipulable health check and are not protected against callback/reentrancy timing.",
    "impact": "An attacker can strip genuine supporting collateral from their account while the protocol is momentarily overestimating another asset, then keep or realize borrowed funds after prices normalize. The result is direct bad debt and practical fund loss for lenders; in the provided path it also enables profitable liquidation of the now-undercollateralized position.",
    "paths": [
      "`BALANCER.exitPool(...)` -> receive callback -> `setUserUseReserveAsCollateral(CSTECRV, false)` under inflated BPT price -> oracle normalizes -> `withdrawCollateral(STECRV, 1000 ether, ...)` -> liquidate the weakened position"
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
