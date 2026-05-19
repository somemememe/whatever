Below are findings and vulnerability signals from 2 agents auditing the same codebase,
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
### Agent: codex_1
```
[
  {
    "id": "F-001",
    "severity": "High",
    "confidence": "high",
    "title": "Pool-directed transferFrom burns more tokens than the approved allowance",
    "locations": [
      "0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:409",
      "0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:489",
      "0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:496",
      "0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:545"
    ],
    "claim": "When `to == uniswapPoolAddress`, `transferFrom` spends allowance only for `amount`, but `_transfer` then calls `_burn(from, burnAmount)` and removes additional tokens from `from` without requiring extra allowance. This violates the ERC20 approval boundary and lets an approved spender reduce a user's balance by more than the approved amount.",
    "impact": "Any router, pool, or spender approved for N tokens can cause the holder to lose N plus the extra burn on each pool-directed transfer. Users and integrating protocols relying on allowance caps can suffer unauthorized token loss.",
    "paths": [
      "user approves spender for N tokens",
      "spender calls transferFrom(user, uniswapPoolAddress, N)",
      "_spendAllowance(user, spender, N) passes, then _burn(user, burnAmount) removes extra balance beyond N"
    ]
  },
  {
    "id": "F-002",
    "severity": "Medium",
    "confidence": "high",
    "title": "Sell transfers require extra balance beyond the requested amount and can revert exact-balance exits",
    "locations": [
      "0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:481",
      "0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:487",
      "0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:489",
      "0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:496",
      "0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:546"
    ],
    "claim": "The sell-side burn is charged on top of `amount` instead of being carved out of it. `_transfer` first deducts the full `amount` from the sender and credits the recipient, then `_burn(from, burnAmount)` requires the sender to still have additional tokens left. A holder therefore cannot transfer or sell their full stated amount to the configured pool unless they hold extra tokens for the burn.",
    "impact": "Users and protocols that attempt exact-balance exits, exact-amount swaps, liquidations, repayments, or vault withdrawals to the configured pool can revert unexpectedly. This can strand balances and break integrations that assume ERC20 `amount` is the total amount removed from the sender.",
    "paths": [
      "user with balance B calls transfer(uniswapPoolAddress, B)",
      "the initial subtraction leaves zero balance",
      "_burn(user, burnAmount) reverts with `burn amount exceeds balance`"
    ]
  },
  {
    "id": "F-003",
    "severity": "Low",
    "confidence": "high",
    "title": "Sell-path Transfer events are fabricated and do not match actual balance changes",
    "locations": [
      "0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:487",
      "0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:494",
      "0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:495"
    ],
    "claim": "On pool-directed transfers, the contract credits `to` with the full `amount`, never credits `marketingWalletAddress`, yet emits events claiming only 97% reached the pool and 2% reached the marketing wallet. The emitted logs therefore describe transfers that never occurred in storage.",
    "impact": "Indexers, accounting systems, tax tooling, snapshots, or exchange deposit processors that rely on Transfer logs can be misled into recording nonexistent marketing transfers and incorrect received amounts, creating reconciliation failures and possible false credits.",
    "paths": [
      "any transfer or transferFrom to `uniswapPoolAddress`",
      "storage gives the pool the full `amount` while the log claims a split transfer"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Owner can retarget the punitive pool logic to any arbitrary destination address at any time",
    "locations": [
      "0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:282",
      "0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:489"
    ],
    "claim": "`uniswapPoolAddress` is fully mutable by the owner and gates the non-standard burn path. The owner can therefore redirect the extra-burn / exact-amount-revert behavior from the original pool to any arbitrary address with a single transaction.",
    "impact": "This creates a protocol-level griefing lever: the owner can unexpectedly make transfers to a bridge, vault, exchange deposit address, or new pool start over-burning senders and reverting exact-amount flows, even after users have granted approvals or integrated with another venue.",
    "paths": [
      "owner calls setUniswapPoolAddress(target)",
      "users or protocols transfer tokens to `target`",
      "the extra burn and exact-balance failure behavior activates for that destination"
    ]
  }
]

```

### Agent: opencode_1
```
Now I'll analyze the contract for security vulnerabilities and prepare the JSON output.

Looking at the contract, I've identified several security issues:

1. **Owner can set arbitrary pool address** (lines 282-284) - This allows owner to redirect the 3% sell tax mechanism to any address, potentially a malicious contract that could steal user funds
2. **Owner can set arbitrary marketing wallet** (lines 286-288) - Allows redirecting the 2% marketing fee to any address
3. **No timelock on critical functions** - Changes happen immediately

Let me verify the tax calculation logic more closely:
[{"id": "F-001", "severity": "High", "confidence": "high", "title": "Owner can arbitrarily set pool address enabling fund theft", "locations": ["0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:282-284"], "claim": "The setUniswapPoolAddress function allows the owner to set any address as the Uniswap pool, which controls where the 3% sell tax (2% marketing + 1% burn) is applied.", "impact": "Owner can set the pool address to a malicious contract with callback hooks that can re-enter the transfer function or manipulate state to steal user funds. Additionally, owner can redirect the tax mechanism to collect fees or disable it entirely at will.", "paths": ["1. Owner calls setUniswapPoolAddress() to set pool to a malicious contract\n2. User transfers tokens to pool (selling)\n3. Malicious contract executes callback during transfer\n4. Attacker extracts additional value from user"]}, {"id": "F-002", "severity": "High", "confidence": "high", "title": "Owner can arbitrarily redirect marketing fee to any address", "locations": ["0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:286-288"], "claim": "The setMarketingWallet function allows the owner to change the marketing wallet address that receives 2% of each sell transaction.", "impact": "Owner can redirect the 2% marketing fee to any address, allowing collection of fees that should go to a designated marketing address. This creates a direct fund theft vector where owner can collect the fee portion of user transfers.", "paths": ["1. Owner calls setMarketingWallet() to set wallet to their own address\n2. User transfers tokens to pool (selling)\n3. 2% marketing fee is sent to owner's address instead of intended wallet"]}, {"id": "F-003", "severity": "Medium", "confidence": "high", "title": "No timelock on critical administrative functions", "locations": ["0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:282-288"], "claim": "setUniswapPoolAddress and setMarketingWallet execute immediately with no delay mechanism.", "impact": "Changes to critical protocol parameters (pool address, marketing wallet) take effect instantly. This allows owner to front-run large transfers or react instantly to market conditions, extracting maximum value before reverting changes. Users have no time to react to malicious parameter changes.", "paths": ["1. Owner monitors mempool for large pending transfer\n2. Owner front-runs by changing pool/marketing address\n3. Large transfer executes with modified parameters\n4. Owner reverts changes after extracting value"]}, {"id": "F-004", "severity": "Low", "confidence": "medium", "title": "Missing events for critical parameter changes", "locations": ["0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:282-288"], "claim": "setUniswapPoolAddress and setMarketingWallet do not emit events when changing state.", "impact": "No on-chain record of pool address or marketing wallet changes makes it difficult to track historical changes off-chain via event logs. This reduces transparency and makes it harder to detect suspicious changes.", "paths": []}, {"id": "F-005", "severity": "Informational", "confidence": "high", "title": "High owner concentration - single point of failure", "locations": ["0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:282-288"], "claim": "The owner has unrestricted control over critical token parameters including tax mechanism and fee collection.", "impact": "Single compromised owner key or malicious owner can completely control the token's economic parameters. No governance, multi-sig, or timelock protections exist. This is a centralization risk typical of pre-launch tokens but creates significant trust assumptions.", "paths": []}]

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
