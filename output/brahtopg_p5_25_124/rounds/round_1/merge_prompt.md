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
    "severity": "Medium",
    "confidence": "medium",
    "title": "Caller-controlled approvals create persistent drain rights over stranded tokens",
    "locations": [
      "onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:138",
      "onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:143"
    ],
    "claim": "The zapper lets each caller choose both `allowanceTarget` and `swapTarget`, then grants `inputToken` allowance before making an arbitrary external call. Because the approved spender does not have to be the contract that is actually called, a user can intentionally leave a live allowance to a malicious spender and later use that allowance to pull any same-token balance that becomes stranded in the zapper.",
    "impact": "Failed swaps, accidental transfers, dust, airdrops, or partially completed withdrawals that leave tokens on the zapper can be stolen by an attacker who previously planted an allowance, front-running governance's `sweep` recovery path.",
    "paths": [
      "zapOut -> `completeWithdrawalWithZap` credits want tokens -> approve(attackerSpender, amountIn) -> no-op swap target leaves allowance live -> attacker later calls `transferFrom(zapper, attacker, amount)`",
      "zapIn -> approve(attackerSpender, amountIn) on a chosen ERC20 -> swap spends less than approved or nothing -> attacker later drains stranded balance of that token"
    ]
  },
  {
    "id": "F-002",
    "severity": "Medium",
    "confidence": "high",
    "title": "Unchecked ERC20 return values allow silent transfer and approval failures",
    "locations": [
      "onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:53",
      "onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:61",
      "onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:76",
      "onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:105",
      "onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:108",
      "onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:138"
    ],
    "claim": "Although `SafeERC20` is imported, the contract uses raw `transfer`, `transferFrom`, and `approve` calls and ignores their boolean return values. Tokens that return `false`, levy transfer fees, or otherwise deviate from ideal ERC20 semantics can therefore make zap flows continue after a failed or partial token movement.",
    "impact": "Users can receive no payout while the transaction still succeeds, swaps can execute against stale balances, approvals can silently fail, and pre-existing token balances in the zapper can be unintentionally consumed or left stuck.",
    "paths": [
      "`zapIn` pulls input tokens with unchecked `transferFrom`, then proceeds into the swap path anyway",
      "`zapOut` transfers the final asset with unchecked `transfer`, so a false-returning token can make the function emit success while paying nothing",
      "`sweep` can silently fail to recover a false-returning ERC20"
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Non-zero-to-non-zero approvals can permanently brick zero-first tokens on common routers",
    "locations": [
      "onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:61",
      "onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:138"
    ],
    "claim": "The contract overwrites allowances directly instead of zeroing them first or using safe allowance helpers. If a prior swap leaves any residual allowance, tokens that enforce a zero-first approval rule will make subsequent zaps on the same token/spender pair revert.",
    "impact": "An attacker can intentionally leave allowance on a popular router address and DoS future zap-ins or zap-outs for that asset, especially when the vault asset or common input token behaves like USDT-style zero-first tokens.",
    "paths": [
      "attacker picks the canonical router as `allowanceTarget` -> crafts a swap that does not fully consume allowance -> later users hit `approve(router, newAmount)` and revert on zero-first tokens"
    ]
  },
  {
    "id": "F-004",
    "severity": "Low",
    "confidence": "high",
    "title": "Native-ETH zaps accept overpayment and trap the surplus for governance",
    "locations": [
      "onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:126",
      "onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:128",
      "onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:98"
    ],
    "claim": "For native-ETH deposits, the zapper only checks `msg.value >= amountIn` and forwards exactly `amountIn` to the swap target. Any excess ETH is left on the contract with no refund path for the caller.",
    "impact": "Frontend bugs, user mistakes, or intentionally inflated `msg.value` result in immediate user fund loss; the stranded ETH can later be captured by governance through `sweep`.",
    "paths": [
      "`zapIn(requiredToken = nativeETH, msg.value > amountIn)` -> only `amountIn` is forwarded -> surplus ETH remains on the zapper -> governance recovers it via `sweep(nativeETH)`"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "low",
    "title": "zapOut trusts the nominal withdrawal amount instead of measuring what the batcher actually delivered",
    "locations": [
      "onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:74",
      "onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:123",
      "onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:138"
    ],
    "claim": "After calling `completeWithdrawalWithZap(zapCall.amountIn, msg.sender)`, the zapper never measures how many want tokens it actually received before approving and attempting to swap based on the caller-supplied nominal amount. If the batcher underpays, partially fulfills, rounds, or otherwise returns less than `zapCall.amountIn`, the zapper will consume any pre-existing want balance it holds.",
    "impact": "The first caller after any want-token residue appears can potentially absorb that residue into their own withdrawal path, and mismatches between expected and actual batcher payouts can leave stale approvals or unpredictable failures.",
    "paths": [
      "`zapOut` with an `amountIn` larger than the actual batcher payout -> zapper still approves/swap-attempts using the nominal amount -> existing want balance on the contract is used to cover the difference"
    ]
  }
]

```

### Agent: opencode_1
```
I'll read all the source files in the target directory to conduct the security audit.
Now I'll analyze the Zapper.sol contract for security vulnerabilities. Let me identify the issues:
Here are the security vulnerabilities I found in the Zapper contract:

1. **Unchecked Return Value from `transfer`** (line 76) - The ERC20 transfer in zapOut doesn't check return value. Failed transfers silently lose user funds.

2. **Approval Not Reset Before Setting New Allowance** (line 138-141) - When tokens have existing approvals, setting a new approval without first setting to 0 can cause transaction failures with certain tokens (like USDT).

3. **No Slippage Protection in zapOut** - zapIn has minAmountOut check (line 149), but zapOut doesn't validate the batcher withdrawal amount before the swap.

4. **Missing Zero-Address Validation** - The `sweep()` function doesn't validate that governance isn't address(0), which could permanently lock funds.

5. **Missing Event Emissions** - The `sweep()` function doesn't emit events, making governance actions hard to track.

6. **Unchecked Low-Level Call Return** (lines 128, 143) - The swap calls don't properly handle failure cases.

7. **Excess ETH Not Refunded** (line 126) - If msg.value > zapCall.amountIn, the excess ETH is not returned to user.

8. **No Access Control on Critical Functions** - The sweep function relies solely on vault.governance() which could be a compromised EOA.
[
  {
    "id": "F-001",
    "severity": "High",
    "confidence": "high",
    "title": "Unchecked ERC20 transfer return value in zapOut",
    "locations": ["Zapper.sol:76"],
    "claim": "IERC20(zapCall.requiredToken).transfer(msg.sender, amountOut) does not check the return value",
    "impact": "If the transfer fails silently (e.g., due to token contract issues, blacklisting, or reverts), users lose their funds without any revert, and the protocol appears to complete successfully",
    "paths": ["User calls zapOut -> batcher withdrawal succeeds -> transfer fails silently -> user loses funds"]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "medium",
    "title": "Approval not reset before setting new allowance causes transaction failure",
    "locations": ["Zapper.sol:138-141"],
    "claim": "IERC20(inputToken).approve() is called without first setting approval to 0, which fails for tokens like USDT that require resetting approval",
    "impact": "Transactions will revert when trying to swap tokens with existing non-zero allowances, causing user funds to be stuck in the contract",
    "paths": ["User calls zapIn with token that has existing approval -> approve fails -> transaction reverts -> user loses tokens sent to contract"]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "Missing slippage protection for batcher withdrawal in zapOut",
    "locations": ["Zapper.sol:74"],
    "claim": "zapOut calls batcher().completeWithdrawalWithZap() without any check on the returned amount before performing the swap",
    "impact": "If the batcher returns less than expected (due to slippage, fees, or manipulation), users receive fewer tokens with no way to set minimum acceptable amount. The swap then executes on whatever amount was received",
    "paths": ["User calls zapOut -> batcher returns reduced amount -> swap executes on reduced input -> user receives less than expected"]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "medium",
    "title": "No zero-address validation for governance in sweep",
    "locations": ["Zapper.sol:98-109"],
    "claim": "sweep() allows governance to be address(0) which would permanently lock all swept funds with no recovery mechanism",
    "impact": "If vault.governance() returns address(0) (due to misconfiguration or migration), all funds swept from the contract are permanently lost",
    "paths": ["Vault governance incorrectly set to address(0) -> sweep called -> funds sent to address(0) -> funds permanently locked"]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "high",
    "title": "Excess ETH not refunded to user in zapIn",
    "locations": ["Zapper.sol:126"],
    "claim": "When inputToken is nativeETH, the check require(msg.value >= zapCall.amountIn) does not refund excess ETH sent by user",
    "impact": "Users sending more ETH than zapCall.amountIn lose the excess ETH permanently",
    "paths": ["User calls zapIn with msg.value > amountIn -> excess ETH kept by contract"]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "low",
    "title": "Missing event emissions for governance operations",
    "locations": ["Zapper.sol:98-109"],
    "claim": "sweep() function transfers funds to governance without emitting any event",
    "impact": "Makes it difficult to track governance actions on-chain, reducing transparency and making it harder to monitor fund movements",
    "paths": ["Governance calls sweep -> no event emitted -> off-chain tracking difficult"]
  },
  {
    "id": "F-007",
    "severity": "Low",
    "confidence": "medium",
    "title": "Unchecked call return values in zap function",
    "locations": ["Zapper.sol:128-131", "Zapper.sol:143"],
    "claim": "Low-level calls to swapTarget use require(success) but success only indicates the call didn't revert, not that the swap was successful",
    "impact": "If the swapTarget executes a malicious contract that always returns success without performing the swap, users receive no tokens but the transaction proceeds",
    "paths": ["User provides malicious swapTarget -> call returns success=false on low-level but require passes -> swap doesn't happen -> user loses funds"]
  },
  {
    "id": "F-008",
    "severity": "Low",
    "confidence": "low",
    "title": "Floating pragma allows incompatible compiler versions",
    "locations": ["Zapper.sol:2"],
    "claim": "Contract uses pragma solidity ^0.8.4 allowing compiler versions 0.8.5+ which may have breaking changes",
    "impact": "Future compiler versions could introduce breaking changes that affect contract behavior without explicit opt-in",
    "paths": []
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
