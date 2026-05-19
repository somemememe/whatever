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
    "title": "Module creation trusts an attacker-controlled rate provider",
    "locations": [
      "Corkprotocol.sol:92",
      "Corkprotocol.sol:100",
      "Corkprotocol.sol:108",
      "Corkprotocol.sol:237",
      "Corkprotocol.sol:241"
    ],
    "claim": "The exploit initializes a new module with `address(this)` as the pricing/rate source and then immediately issues a new DS series. Because the attacker contract itself implements `rate()` and `rate(bytes32)`, the setup path appears to trust arbitrary caller-chosen rate providers during module initialization and issuance.",
    "impact": "An attacker can create synthetic markets whose pricing behavior they fully control, then mint or misprice CT/DS/LV positions and drain reserve assets during later swaps or redemptions.",
    "paths": [
      "attack() -> initializeModuleCore(address(WstETH), ds2, 1, 100, address(this))",
      "attack() -> getId(...) -> issueNewDs(id, ...)",
      "protocol later queries attacker-supplied rate()/rate(bytes32)"
    ]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "high",
    "title": "Swap-hook entrypoint can be driven with spoofed sender and pool metadata",
    "locations": [
      "Corkprotocol.sol:168",
      "Corkprotocol.sol:169",
      "Corkprotocol.sol:171",
      "Corkprotocol.sol:180",
      "Corkprotocol.sol:185",
      "Corkprotocol.sol:201",
      "Corkprotocol.sol:212"
    ],
    "claim": "The exploit directly invokes `CorkHook.beforeSwap` through a low-level call while supplying arbitrary `sender`, `PoolKey`, and hook data, including `sender = _erc1967Proxy` and `hooks = address(this)`. This only succeeds if the hook logic does not authenticate the pool manager/current pool context and instead trusts caller-controlled parameters.",
    "impact": "An attacker can impersonate protocol components inside swap hooks, force accounting to execute against assets held by the proxy, and extract value without performing a legitimate swap.",
    "paths": [
      "attack() -> PoolManager.unlock(data) -> unlockCallback()",
      "unlockCallback() -> beforeSwap(_erc1967Proxy, forged PoolKey, forged hookData)",
      "unlockCallback() -> beforeSwap(_erc1967Proxy, forged PoolKey, hex\"\")"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "Reserve-asset redemption is not tightly bound to the correct CT/DS series",
    "locations": [
      "Corkprotocol.sol:152",
      "Corkprotocol.sol:155",
      "Corkprotocol.sol:156",
      "Corkprotocol.sol:219",
      "Corkprotocol.sol:224",
      "Corkprotocol.sol:225"
    ],
    "claim": "The attacker calls `returnRaWithCtDs` twice while passing only an `id` and an amount, first with a hard-coded legacy id instead of the freshly-created `id`, and later after approving a different CT/DS pair (`ct3`/`ds3`). This strongly suggests the redemption path does not strictly verify that the CT and DS being redeemed belong to the same series identified by `id`.",
    "impact": "If redemption is mis-bound, an attacker can present unrelated or freshly-forged receipt tokens to withdraw reserve assets from another market, directly draining protocol collateral.",
    "paths": [
      "attack() -> returnRaWithCtDs(hard-coded id, balCT2)",
      "unlockCallback() -> returnRaWithCtDs(id, balDs2) using newly created ct3/ds3 assets"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "medium",
    "title": "Raw token donations can manipulate accounting before swap and mint flows",
    "locations": [
      "Corkprotocol.sol:53",
      "Corkprotocol.sol:54",
      "Corkprotocol.sol:72",
      "Corkprotocol.sol:78",
      "Corkprotocol.sol:79",
      "Corkprotocol.sol:86"
    ],
    "claim": "The exploit starts by transferring `LiquidityToken` directly into the proxy without calling a protocol entrypoint, then immediately performs reserve-sensitive operations (`getReserves`, `swap`, `depositPsm`). This pattern indicates protocol pricing or mint/redeem math is derived from live token balances that can be skewed by unsolicited transfers.",
    "impact": "An attacker can donate assets to distort exchange rates, mint terms, or pool reserves and then extract underpriced CT/DS/RA value, causing insolvency or large one-transaction losses.",
    "paths": [
      "attack() -> transferFrom(attacker, ERC1967Proxy, balLT)",
      "attack() -> getReserves(...) -> swap(...)",
      "attack() -> depositPsm(...)"
    ]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "medium",
    "title": "Unlock/settle flow exposes transient proxy balances to attacker-controlled callbacks",
    "locations": [
      "Corkprotocol.sol:127",
      "Corkprotocol.sol:142",
      "Corkprotocol.sol:180",
      "Corkprotocol.sol:182",
      "Corkprotocol.sol:210",
      "Corkprotocol.sol:229",
      "Corkprotocol.sol:232"
    ],
    "claim": "After `depositLv`, the attacker enters `PoolManager.unlock`, reads the proxy's intermediate `ds2` balance, drives custom hook logic against that balance, and only settles the manager at the end with minimal transfers. This indicates protocol state becomes externally usable before final settlement, enabling callback-time extraction of transient assets.",
    "impact": "A user who can enter the unlock path can trade against temporarily-accounted balances before they are finalized, leaving the system with bad debt or drained reserve assets.",
    "paths": [
      "attack() -> depositLv(...)",
      "attack() -> PoolManager.unlock(data)",
      "unlockCallback() -> balanceOf(_erc1967Proxy) -> beforeSwap(...) -> settleFor(...)"
    ]
  }
]

```



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
