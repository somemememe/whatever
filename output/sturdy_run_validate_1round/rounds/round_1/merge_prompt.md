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
    "confidence": "medium",
    "title": "Balancer LP collateral can be massively overvalued through read-only reentrancy during pool exit",
    "locations": [
      "Contract.sol:276",
      "Contract.sol:286",
      "Contract.sol:291",
      "Contract.sol:294",
      "Contract.sol:302"
    ],
    "claim": "The exploit path shows the protocol valuing `B_STETH_STABLE` collateral from live Balancer pool state while `Balancer.exitPool` is still in progress. Because the exit sends ETH mid-execution, the attacker's `receive()` hook can synchronously observe a transient pool state and `SturdyOracle.getAssetPrice(cB_stETH_STABLE)` returns an inflated collateral price before the pool settles.",
    "impact": "A borrower can make a small amount of Balancer BPT appear worth far more than it really is, pass solvency checks, and extract assets against non-existent collateral value. This is a protocol-draining primitive, not a benign pricing glitch.",
    "paths": [
      "testExploit -> executeOperation -> Exploiter.yoink -> joinBalancerPool -> depositCollateralAndBorrow -> exitBalancerPool -> receive -> SturdyOracle.getAssetPrice(cB_stETH_STABLE)"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "medium",
    "title": "Collateral-disable checks can be bypassed under the transient LP mispricing, enabling withdrawal of real collateral",
    "locations": [
      "Contract.sol:297",
      "Contract.sol:305",
      "Contract.sol:306",
      "Contract.sol:317",
      "Contract.sol:318"
    ],
    "claim": "While the manipulated Balancer price is live inside the reentrant window, the borrower is able to call `setUserUseReserveAsCollateral(address(csteCRV), false)` and then later withdraw the entire `steCRV` position. This means the reserve-disable / collateral-withdraw path accepts a health check based on a manipulable, non-final collateral valuation instead of enforcing safety against a reentrancy-safe price.",
    "impact": "An attacker can strip out the honest collateral that was actually securing the loan, leaving the account backed only by the temporarily overvalued LP token. Once the price normalizes, the position is insolvent and can be unwound for profit, creating bad debt or direct loss to lenders.",
    "paths": [
      "testExploit -> executeOperation -> Exploiter.yoink -> depositCollateralAndBorrow -> exitBalancerPool -> receive -> lendingPool.setUserUseReserveAsCollateral(csteCRV, false) -> withdrawCollateralAndLiquidation -> ConvexCurveLPVault2.withdrawCollateral(address(steCRV), ...)"
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
