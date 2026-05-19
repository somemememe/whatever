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
[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "User-controlled swap params can spend arbitrary token balances held by gateway contracts",
    "locations": [
      "GatewayCrossChain.sol:373",
      "GatewayCrossChain.sol:492",
      "GatewayTransferNative.sol:414",
      "GatewayTransferNative.sol:453",
      "GatewayTransferNative.sol:574",
      "GatewaySend.sol:199",
      "GatewaySend.sol:245",
      "GatewaySend.sol:366"
    ],
    "claim": "The contracts decode `MixSwapParams` from attacker-controlled payloads and approve/swap using `params.fromToken`/`params.fromTokenAmount` without enforcing that they match the token and amount actually received in the current flow.",
    "impact": "Attackers can spend unrelated token balances already stored in these contracts (fees, stranded funds, prior user funds) and route swap outputs to attacker-controlled recipients, causing direct theft.",
    "paths": [
      "Craft payload/swapData with `params.fromToken` set to a valuable token currently held by the contract.",
      "Trigger `onCall`, `withdrawToNativeChain`, or `depositAndCall` with cheap/unrelated input or minimal value.",
      "Contract approves DODO for attacker-chosen token, and `mixSwap` pulls and converts those tokens for attacker benefit."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "high",
    "title": "Refunds for non-20-byte recipients are claimable by anyone",
    "locations": [
      "GatewayCrossChain.sol:607",
      "GatewayCrossChain.sol:612",
      "GatewayTransferNative.sol:685",
      "GatewayTransferNative.sol:689"
    ],
    "claim": "In both `claimRefund` implementations, when `walletAddress.length != 20`, `receiver` is left as `msg.sender`; the subsequent caller check then always passes for arbitrary callers.",
    "impact": "Refunds intended for non-EVM recipients (e.g., Bitcoin/Solana-style addresses) can be front-run and stolen by any observer.",
    "paths": [
      "A failed cross-chain call stores refund info with non-20-byte `walletAddress`.",
      "Attacker observes `externalId` and calls `claimRefund(externalId)` first.",
      "Authorization passes trivially and funds are transferred to attacker."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Bitcoin/non-EVM revert recipient is truncated to 20 bytes, misdirecting refunds",
    "locations": [
      "GatewayCrossChain.sol:318",
      "GatewayCrossChain.sol:550",
      "GatewayTransferNative.sol:319",
      "GatewayTransferNative.sol:631"
    ],
    "claim": "`withdraw` encodes revert recipient as `bytes20(sender)`, truncating non-20-byte addresses. `onRevert` then treats the 52-byte revert payload as an EVM address refund target.",
    "impact": "Failed non-EVM withdrawals can refund to unintended EVM addresses (or unusable addresses), causing permanent user fund loss.",
    "paths": [
      "User initiates withdrawal using a non-20-byte recipient format.",
      "Withdrawal fails and gateway calls `onRevert` with the truncated 20-byte recipient.",
      "Contract transfers refund to the truncated EVM address instead of the intended non-EVM recipient."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-004",
    "severity": "Critical",
    "confidence": "high",
    "title": "ETH sentinel path in `withdrawToNativeChain` allows unfunded withdrawal of contract-held tokens",
    "locations": [
      "GatewayTransferNative.sol:549",
      "GatewayTransferNative.sol:554",
      "GatewayTransferNative.sol:570",
      "GatewayTransferNative.sol:574",
      "GatewayTransferNative.sol:477"
    ],
    "claim": "When `zrc20 == 0xEeee...`, `withdrawToNativeChain` skips token transfer-in but still trusts caller-supplied `amount` and proceeds to approve/withdraw `decoded.targetZRC20` from contract balances.",
    "impact": "Attackers can withdraw real escrowed tokens from contract inventory without providing matching input assets.",
    "paths": [
      "Call `withdrawToNativeChain(_ETH_ADDRESS_, amount, message)` with arbitrary `amount` and little/no real funding.",
      "Function skips input `transferFrom` and computes output from attacker-controlled amount/swap data.",
      "Gateway withdrawals are executed using tokens already held by the contract."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "medium",
    "title": "GatewaySend destination payout uses payload amount/token flags instead of reconciled delivered assets",
    "locations": [
      "GatewaySend.sol:347",
      "GatewaySend.sol:354",
      "GatewaySend.sol:363",
      "GatewaySend.sol:370"
    ],
    "claim": "`GatewaySend.onCall` trusts `amount`, `fromToken`, and `toToken` decoded from payload and does not reconcile them against the assets actually delivered by gateway in that call (or `msg.value`).",
    "impact": "Crafted cross-chain payloads can overstate payout and drain pre-existing ETH/token balances in destination `GatewaySend`.",
    "paths": [
      "Send a cross-chain call with payload encoding inflated `amount` and favorable token mode (notably ETH paths that skip token pull).",
      "`onCall` computes payout from payload values and transfers funds to attacker-controlled recipient.",
      "Any contract reserves beyond actual delivered assets are siphoned."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Reentrancy in `GatewayTransferNative.claimRefund` allows repeated refund claims",
    "locations": [
      "GatewayTransferNative.sol:691",
      "GatewayTransferNative.sol:692"
    ],
    "claim": "`claimRefund` performs external token transfer before deleting `refundInfos[externalId]`, enabling reentrancy on malicious refund tokens.",
    "impact": "A malicious token can reenter and claim the same refund multiple times in one transaction, draining additional token balance held by the contract.",
    "paths": [
      "Create refund entry where `refundInfo.token` is a reentrant token.",
      "Call `claimRefund(externalId)`; token transfer reenters before storage deletion.",
      "Repeated claims execute until balance is exhausted or reentrancy stops."
    ],
    "round": 1,
    "source_agents": [
      "codex_1",
      "opencode_1"
    ]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Balance-based pair existence check can be dust-poisoned into swap-path DoS",
    "locations": [
      "GatewayCrossChain.sol:234",
      "GatewayCrossChain.sol:245",
      "GatewayTransferNative.sol:235",
      "GatewayTransferNative.sol:246",
      "libraries/UniswapV2Library.sol:44"
    ],
    "claim": "`_existsPairPool` infers pair existence by token balances at computed pair address rather than verifying deployed pair code/reserves.",
    "impact": "Attackers can dust non-pair addresses so routing selects nonexistent direct pools, causing reserve lookups/swaps to revert and denying service for affected routes.",
    "paths": [
      "For token pair without real direct pool, send dust of both tokens to computed pair address.",
      "`_existsPairPool` returns true and route selection uses 2-hop direct path.",
      "Subsequent `getReserves`/swap call reverts on non-pair target, blocking those swaps."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-008",
    "severity": "Medium",
    "confidence": "low",
    "title": "Public `withdraw` can be abused when residual gateway allowances remain",
    "locations": [
      "GatewayTransferNative.sol:305",
      "GatewayTransferNative.sol:319",
      "GatewayTransferNative.sol:477",
      "GatewayTransferNative.sol:496"
    ],
    "claim": "`GatewayTransferNative.withdraw` is publicly callable, while other flows can leave residual gateway allowance (notably approvals of `outputAmount + gasFee` against lower effective spend). Under certain fee/limit conditions, callers can consume leftover allowance to trigger unauthorized withdrawals.",
    "impact": "If residual approval plus contract balance exist, arbitrary callers can route contract-held tokens out to attacker-chosen recipients.",
    "paths": [
      "A prior flow leaves nonzero residual approval from `GatewayTransferNative` to gateway.",
      "Attacker calls public `withdraw` with attacker-controlled recipient bytes and amount within remaining spendable margin.",
      "Gateway pulls tokens from contract allowance and emits withdrawal to attacker destination."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  }
]

## This Round's Agent Outputs
### Agent: codex_1
```
[
  {
    "id": "F-009",
    "severity": "Critical",
    "confidence": "high",
    "title": "withdrawToNativeChain trusts nominal deposit amount/token and can execute underfunded withdrawals",
    "locations": [
      "GatewayTransferNative.sol:554",
      "GatewayTransferNative.sol:555",
      "GatewayTransferNative.sol:570",
      "GatewayTransferNative.sol:574",
      "GatewayTransferNative.sol:577",
      "GatewayTransferNative.sol:599"
    ],
    "claim": "The function only checks a boolean `transferFrom` return and then uses caller-supplied `amount` for fee/swap/withdraw flows without verifying actual token balance delta or canonical token type.",
    "impact": "A malicious or heavily deflationary token can underfund (or fake) the input while the contract still withdraws real `decoded.targetZRC20` from its own balances, enabling direct theft of pooled assets.",
    "paths": [
      "Deploy/use a token that returns true on `transferFrom`/`transfer` but does not transfer full value.",
      "Call `withdrawToNativeChain` with that token as `zrc20`, large `amount`, and message targeting a valuable `targetZRC20`.",
      "Contract computes output from nominal `amount` and withdraws valuable target tokens from existing inventory."
    ]
  },
  {
    "id": "F-010",
    "severity": "Critical",
    "confidence": "high",
    "title": "GatewayCrossChain empty-swap path allows withdrawing arbitrary target token without conversion",
    "locations": [
      "GatewayCrossChain.sol:369",
      "GatewayCrossChain.sol:370",
      "GatewayCrossChain.sol:492",
      "GatewayCrossChain.sol:495",
      "GatewayCrossChain.sol:517"
    ],
    "claim": "When `swapDataZ` is empty, `_doMixSwap` returns the input amount directly, but `onCall` still performs withdrawal logic using user-controlled `decoded.targetZRC20`.",
    "impact": "Attackers can bridge a low-value token and trigger withdrawal of a different high-value token held by the contract, draining inventory.",
    "paths": [
      "Send cross-chain call with `targetZRC20 != zrc20` and empty `swapDataZ`.",
      "`onCall` sets `outputAmount = amount` without any conversion proof.",
      "Withdrawal handlers execute against `targetZRC20` and transfer out valuable token balances."
    ]
  },
  {
    "id": "F-011",
    "severity": "Critical",
    "confidence": "high",
    "title": "GatewaySend source flow does not bind swap output asset to bridged asset",
    "locations": [
      "GatewaySend.sol:245",
      "GatewaySend.sol:257",
      "GatewaySend.sol:266"
    ],
    "claim": "`depositAndCall(fromToken,...)` uses numeric `outputAmount` from `_doMixSwap`, then bridges whichever `asset` the caller supplied, without verifying that this asset was actually received from swap execution.",
    "impact": "If the contract holds balances of another token/ETH, an attacker can swap one asset but bridge out a different asset from pooled reserves.",
    "paths": [
      "Call `depositAndCall(fromToken, amount, swapData, ..., asset, ...)` with swap output token different from `asset`.",
      "Obtain nonzero `outputAmount` from swap in token C.",
      "Contract deposits `outputAmount` of user-chosen `asset` B to gateway, consuming B from contract reserves."
    ]
  },
  {
    "id": "F-012",
    "severity": "High",
    "confidence": "high",
    "title": "Recipient bytes are truncated/padded into EVM addresses in payout paths",
    "locations": [
      "GatewayTransferNative.sol:390",
      "GatewaySend.sol:356"
    ],
    "claim": "Both contracts cast dynamic recipient bytes to `bytes20`/`address` without requiring exact 20-byte length.",
    "impact": "Non-20-byte recipients are silently misinterpreted, causing irreversible payout misdirection (including attacker-controlled prefix truncation).",
    "paths": [
      "Provide recipient bytes longer than 20 bytes with attacker-controlled first 20 bytes.",
      "Contract truncates to 20-byte EVM address and transfers funds there."
    ]
  },
  {
    "id": "F-013",
    "severity": "Medium",
    "confidence": "medium",
    "title": "GatewaySend destination execution ignores ERC20 transfer success values",
    "locations": [
      "GatewaySend.sol:359",
      "GatewaySend.sol:372"
    ],
    "claim": "`onCall` does not check return values of `IERC20.transferFrom` and `IERC20.transfer`.",
    "impact": "For tokens that return `false` on failure, the bridge flow can report success while funds were not delivered, causing silent non-payment and accounting inconsistencies.",
    "paths": [
      "Use token behavior where failed `transferFrom`/`transfer` returns false instead of reverting.",
      "`onCall` continues and emits success event despite no actual token movement."
    ]
  },
  {
    "id": "F-014",
    "severity": "Medium",
    "confidence": "low",
    "title": "GatewayTransferNative refund records are overwriteable for the same externalId",
    "locations": [
      "GatewayTransferNative.sol:642",
      "GatewayTransferNative.sol:648",
      "GatewayTransferNative.sol:664",
      "GatewayTransferNative.sol:670"
    ],
    "claim": "`onRevert`/`onAbort` write `refundInfos[externalId]` without checking for an existing entry.",
    "impact": "If duplicate/colliding callbacks are delivered, prior refund metadata can be replaced, potentially redirecting or invalidating a pending refund.",
    "paths": [
      "First callback stores refund info for externalId X.",
      "Second callback with same X stores different wallet/token/amount and overwrites claimant data."
    ]
  },
  {
    "id": "F-015",
    "severity": "Medium",
    "confidence": "medium",
    "title": "AccountEncoder.decompressAccounts builds invalid memory layout for Account[]",
    "locations": [
      "libraries/AccountEncoder.sol:28",
      "libraries/AccountEncoder.sol:33",
      "libraries/AccountEncoder.sol:48",
      "GatewayCrossChain.sol:425",
      "GatewayTransferNative.sol:505",
      "GatewayTransferNative.sol:534"
    ],
    "claim": "`decompressAccounts` stores pointers in array slots where static `Account` structs are expected inline, so subsequent ABI encoding reads corrupted struct fields.",
    "impact": "Solana-targeted payloads can be malformed and fail downstream decoding/calls, causing persistent route-level DoS/refund churn for affected transfers.",
    "paths": [
      "Use Solana path (`dstChainId == SOLANA_EDDY`) with compressed accounts data.",
      "`decompressAccounts` produces malformed `Account[]` memory representation.",
      "Encoded payload is invalid for downstream processing and withdraw-and-call fails."
    ]
  }
]

```

### Agent: opencode_1
```
Let me also read the libraries to understand the full context:
Now I have enough context. Let me analyze the contracts for additional vulnerabilities beyond the known findings.

Based on my analysis, I've identified several new security vulnerabilities:

```json
[
  {
    "id": "F-009",
    "severity": "Critical",
    "confidence": "high",
    "title": "Fee calculation error in _swapAndSendERC20Tokens approves wrong amount leading to potential token theft",
    "locations": [
      "GatewayCrossChain.sol:342",
      "GatewayTransferNative.sol:338"
    ],
    "claim": "The `_swapAndSendERC20Tokens` function calculates `amountInMax` using `amountsQuote[0]` (the input amount needed), then approves this full amount for spending. However, after the swap, the contract approves `targetAmount - amounts[0]` to the gateway. If `amountsQuote[0]` differs from actual swap input, the approval can be significantly higher than swapped tokens, allowing the gateway to withdraw more than intended from the contract.",
    "impact": "An attacker could exploit this miscalculation to drain gateway contract tokens by manipulating swap routes or through normal operation variance.",
    "paths": [
      "Call `_swapAndSendERC20Tokens` with any swap path → approval exceeds actual swapped value → gateway withdraws excess → contract undercollated"
    ]
  },
  {
    "id": "F-010",
    "severity": "High",
    "confidence": "high",
    "title": "Missing slippage protection and minReturnAmount validation in swap operations",
    "locations": [
      "GatewaySend.sol:245",
      "GatewaySend.sol:366",
      "GatewayCrossChain.sol:492",
      "GatewayTransferNative.sol:414",
      "GatewayTransferNative.sol:574"
    ],
    "claim": "The `_doMixSwap` functions use `params.minReturnAmount` from user-controlled swap params but never validate that the actual output meets this minimum. Additionally, there is no slippage protection enforced at the contract level - users can receive significantly less than expected due to price impact or MEV sandwich attacks.",
    "impact": "Users may receive far less than expected from swaps with no contract-level protection. Front-runners can extract value through sandwich attacks with no recourse.",
    "paths": [
      "Call depositAndCall with unfavorable swap params → exchange rate shifts during processing → user receives minimal tokens"
    ]
  },
  {
    "id": "F-011",
    "severity": "High",
    "confidence": "medium",
    "title": "Unchecked externalId collision in revert/abort handlers causes refund overwrite",
    "locations": [
      "GatewayCrossChain.sol:561",
      "GatewayCrossChain.sol:585",
      "GatewayTransferNative.sol:648",
      "GatewayTransferNative.sol:670"
    ],
    "claim": "The `onRevert` and `onAbort` functions store refund info without checking if an entry already exists. If two different cross-chain transactions produce the same `externalId` (which is derived from user transaction data), the second deposit will overwrite the first refund, permanently losing the first user's funds.",
    "impact": "Users can lose all funds in refund entries due to collision. ExternalId is user-controlled or derived from predictable on-chain data making collision feasible.",
    "paths": [
      "Trigger first revert with externalId=X → refund stored → trigger second revert with same externalId → first refund overwritten → first user loses funds"
    ]
  },
  {
    "id": "F-012",
    "severity": "High",
    "confidence": "high",
    "title": "GatewayCrossChain claimRefund deletes refundInfo after transfer allowing reentrancy via callback",
    "locations": [
      "GatewayCrossChain.sol:618-621"
    ],
    "claim": "While `claimRefund` in GatewayCrossChain deletes refundInfo before transfer (reentrancy-safe pattern), it uses `TransferHelper.safeTransfer` which makes an external call to an untrusted token. If the token is malicious (e.g., a reentrancy-gentoken), it can call back into `claimRefund` before the delete completes its execution. Because the storage deletion was already performed earlier in the function (line 619), a reentrancy attack can cause the refund to be paid multiple times.",
    "impact": "Attacker can drain the contract by creating/refunding through a malicious token with callback, draining refund pool.",
    "paths": [
      "Create malicious token with callback → trigger refund → in callback call claimRefund with same externalId → delete happened → refund again"
    ]
  },
  {
    "id": "F-013",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Missing destination chain (dstChainId) validation allows routing to invalid chains",
    "locations": [
      "GatewayCrossChain.sol:480",
      "GatewayCrossChain.sol:495",
      "GatewayTransferNative.sol:562",
      "GatewayTransferNative.sol:577"
    ],
    "claim": "The `decodeMessage` function decodes `dstChainId` from user-provided message data without validating it against known/valid chain IDs. Invalid chain IDs may cause the withdrawal to fail silently or route to unintended destinations.",
    "impact": "Users may specify invalid chain IDs resulting in permanently locked funds or failed transactions with no clear error.",
    "paths": [
      "Call withdrawToNativeChain with invalid dstChainId → message encoded → gateway processes → routing fails or directs to wrong chain"
    ]
  },
  {
    "id": "F-014",
    "severity": "Medium",
    "confidence": "medium",
    "title": "No deadline enforcement allows Stuck stale swaps",
    "locations": [
      "GatewaySend.sol:202-215",
      "GatewayCrossChain.sol:373-387",
      "GatewayTransferNative.sol:453-467"
    ],
    "claim": "The `_doMixSwap` functions accept `params.deadline` from user input but do not enforce that `

```



## Excluded From Direct Audit Scope
Do not keep findings whose reportable root cause exists solely in files matching:
- `mocks/**`

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
