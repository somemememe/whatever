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
    "severity": "High",
    "confidence": "high",
    "title": "Old proxy credits fee-on-transfer inputs at the user-declared amount, allowing theft from pre-existing token balances",
    "locations": [
      "onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:69",
      "onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:73",
      "onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:83"
    ],
    "claim": "The 0x3335 deployment computes `_amountIn` from `_params.srcInputAmount` instead of the actual post-transfer balance delta. For deflationary / fee-on-transfer tokens, the contract can approve and spend more tokens than it really received from the caller, with the shortfall coming from tokens already held by the proxy.",
    "impact": "An attacker can bridge or swap using other users' residual balances, accrued platform fees, or accidentally sent funds of the same token. This is direct token theft from the proxy's inventory.",
    "paths": [
      "Proxy already holds token T from fees or prior stuck funds",
      "Attacker calls `routerCall` with token T that burns/taxes on transfer",
      "Contract receives less than `_params.srcInputAmount` but still computes fees and allowance from the larger declared amount",
      "Router/gateway spends the larger `_amountIn`, and the missing amount is sourced from the proxy's existing T balance"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Old proxy leaves permanent max approvals to gateways, exposing all future balances to gateway compromise or abuse",
    "locations": [
      "onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:81",
      "onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/libraries/SmartApprove.sol:19",
      "onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/libraries/SmartApprove.sol:22"
    ],
    "claim": "The 0x3335 deployment grants `type(uint256).max` allowance to each chosen gateway and never resets it after the router call finishes.",
    "impact": "Any whitelisted gateway that is compromised, upgraded maliciously, or simply exposes a callable pull path can drain every current and future balance of that token from the proxy, including accrued fees and other users' funds, without needing another approval transaction.",
    "paths": [
      "A user makes an ordinary `routerCall` for token T through gateway G",
      "`SmartApprove` sets allowance from the proxy to G to `uint256.max`",
      "At any later time, G (or an attacker controlling G) calls `transferFrom(proxy, attacker, amount)` for token T",
      "The drain continues until the proxy's T balance is exhausted"
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "high",
    "title": "Any caller can impersonate a privileged integrator and inherit its custom fee schedule",
    "locations": [
      "onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:71",
      "onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/contracts/RubicProxy.sol:80",
      "onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:140",
      "onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:174",
      "onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:311",
      "onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/rubic-bridge-base/contracts/BridgeBase.sol:140",
      "onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/rubic-bridge-base/contracts/BridgeBase.sol:174",
      "onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/rubic-bridge-base/contracts/BridgeBase.sol:311"
    ],
    "claim": "Integrator fee parameters are keyed only by the user-supplied `_params.integrator` address, but neither proxy authenticates that the caller is actually routed by or authorized by that integrator.",
    "impact": "If any partner integrator is configured with discounted or zero fees, every user can reuse that address to bypass the normal Rubic fee model. This causes protocol-wide fee leakage and breaks partner-specific pricing assumptions.",
    "paths": [
      "Manager configures an integrator address with cheaper `tokenFee` and/or `fixedFeeAmount`",
      "Arbitrary user sets `_params.integrator` to that address",
      "`accrueFixedCryptoFee` and `accrueTokenFees` apply the partner fee schedule with no signature or caller check",
      "User pays the discounted partner rate despite having no relationship with that integrator"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "low",
    "title": "Router and gateway are authorized independently, so approvals can be combined with an unrelated whitelisted call target",
    "locations": [
      "onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:66",
      "onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:81",
      "onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:85",
      "onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/contracts/RubicProxy.sol:69",
      "onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/contracts/RubicProxy.sol:84",
      "onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/contracts/RubicProxy.sol:86"
    ],
    "claim": "Both proxies only require `_params.router` and `_gateway` to appear somewhere in the same global whitelist; they do not bind a specific gateway to a specific router or validate that the calldata actually uses the approved gateway as intended.",
    "impact": "If any whitelisted router supports arbitrary forwarding / multicall semantics, callers can pair it with a different whitelisted gateway and consume the freshly granted allowance in unintended ways. This breaks the trust boundary from 'approved integration pair' into 'any approved router plus any approved gateway'.",
    "paths": [
      "User chooses whitelisted router R and different whitelisted gateway G",
      "Proxy approves G for the source token, then executes arbitrary calldata on R",
      "If R can forward arbitrary calls, it can invoke G (or a helper that invokes G) with attacker-chosen parameters",
      "The source-token allowance is consumed outside the integration flow the whitelist was meant to authorize"
    ]
  },
  {
    "id": "F-005",
    "severity": "Low",
    "confidence": "high",
    "title": "Configured min/max token limits are dead code and never enforced at the entrypoints",
    "locations": [
      "onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:31",
      "onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:343",
      "onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/rubic-bridge-base/contracts/BridgeBase.sol:31",
      "onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/rubic-bridge-base/contracts/BridgeBase.sol:343",
      "onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:61",
      "onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:96",
      "onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/contracts/RubicProxy.sol:63",
      "onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/contracts/RubicProxy.sol:102"
    ],
    "claim": "BridgeBase stores configurable `minTokenAmount` / `maxTokenAmount` values and exposes admin setters, but neither `routerCall` nor `routerCallNative` checks them before accepting a transfer.",
    "impact": "Operators may believe they have enforced safe per-token bounds when in reality any size is accepted. That can permit dust calls or oversized calls that downstream routes cannot safely handle, producing stuck transfers, griefing, or broken operational assumptions.",
    "paths": [
      "Manager sets min/max values for a token",
      "User submits a call below the configured minimum or above the configured maximum",
      "The proxy processes it normally because no entrypoint ever reads those mappings"
    ]
  }
]

```


## Included Direct Audit Scope
Only keep findings whose root cause location is inside files matching:
- `onchain/**`

Other files can still be read as context.



## Excluded From Direct Audit Scope
Do not keep findings whose reportable root cause exists solely in files matching:
- `out/**`
- `**/_baseline_excluded/**`
- `FlawVerifier.sol`
- `interface.sol`

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
