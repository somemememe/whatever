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
      "GatewayTransferNative.sol:389",
      "GatewayTransferNative.sol:414",
      "GatewayTransferNative.sol:453",
      "GatewayTransferNative.sol:574",
      "GatewaySend.sol:199",
      "GatewaySend.sol:245",
      "GatewaySend.sol:366"
    ],
    "claim": "The contracts decode `MixSwapParams` from attacker-controlled payloads and use `params.fromToken` / `params.fromTokenAmount` in approvals and `mixSwap` without enforcing that they match the token and net amount actually available in the current execution path, including fee-adjusted paths.",
    "impact": "Attackers can spend unrelated token balances already held by these contracts, such as fees, stranded balances, or prior user funds, and route swap outputs to attacker-controlled recipients, causing direct theft.",
    "paths": [
      "Craft payload or swapData with `params.fromToken` set to a valuable token currently held by the contract and `params.fromTokenAmount` set to the desired drain amount.",
      "Trigger `onCall`, `withdrawToNativeChain`, or `depositAndCall` with cheap or unrelated input.",
      "The contract approves DODO for the attacker-chosen token and `mixSwap` pulls or spends contract inventory for attacker benefit.",
      "In `GatewayTransferNative.onCall`, fee is transferred out first but swap still uses pre-fee `amount`, so deficits can be externalized to reserves."
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
    "claim": "In both `claimRefund` implementations, when `walletAddress.length != 20`, `receiver` remains `msg.sender`; the caller check then trivially passes for arbitrary callers.",
    "impact": "Refunds intended for non-EVM recipients, such as Bitcoin or Solana-style addresses, can be front-run and stolen by any observer.",
    "paths": [
      "A failed cross-chain call stores refund info with non-20-byte `walletAddress`.",
      "An attacker observes `externalId` and calls `claimRefund(externalId)` first.",
      "Authorization passes trivially and funds are transferred to the attacker."
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
    "claim": "`withdraw` encodes revert recipient as `bytes20(sender)`, truncating non-20-byte addresses. `onRevert` then interprets the 52-byte revert payload as an EVM address refund target.",
    "impact": "Failed non-EVM withdrawals can refund to unintended EVM addresses or unusable addresses, causing permanent user fund loss.",
    "paths": [
      "A user initiates withdrawal with a non-20-byte recipient format.",
      "The withdrawal fails and the gateway calls `onRevert` with truncated 20-byte recipient bytes.",
      "The contract refunds to that truncated EVM address instead of the intended non-EVM recipient."
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
    "title": "withdrawToNativeChain trusts nominal input amount and can execute underfunded withdrawals from contract reserves",
    "locations": [
      "GatewayTransferNative.sol:360",
      "GatewayTransferNative.sol:454",
      "GatewayTransferNative.sol:477",
      "GatewayTransferNative.sol:549",
      "GatewayTransferNative.sol:554",
      "GatewayTransferNative.sol:555",
      "GatewayTransferNative.sol:570",
      "GatewayTransferNative.sol:574",
      "GatewayTransferNative.sol:577",
      "GatewayTransferNative.sol:599"
    ],
    "claim": "`withdrawToNativeChain` uses caller-supplied `amount` as the accounting source for fee, swap, and withdrawal flows, but does not verify actual token or ETH funding. The ETH sentinel path skips transfer-in entirely, `_handleFeeTransfer` treats `_ETH_ADDRESS_` like an ERC20 transfer, and `_doMixSwap` still forwards full `msg.value` to DODO. ERC20 paths only check a boolean `transferFrom` return and never reconcile the actual balance delta.",
    "impact": "Attackers can trigger withdrawals of real `decoded.targetZRC20` from contract-held inventory without providing equivalent funding, enabling direct theft of pooled assets. On native-input paths, callers can also underpay or bypass protocol fees by setting a tiny nominal `amount` while processing larger `msg.value`.",
    "paths": [
      "Call `withdrawToNativeChain(_ETH_ADDRESS_, amount, message)` to bypass token pull, then route to a valuable `targetZRC20`.",
      "Or use a malicious or deflationary token that returns success while transferring less than `amount`.",
      "On the native-input path, set `amount` small or zero but send large `msg.value`; fees are computed on nominal `amount` while full `msg.value` is forwarded into DODO.",
      "The contract computes output from nominal accounting and executes gateway withdrawal using existing target-token balances or undercharged fee accounting."
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
    "claim": "`_existsPairPool` infers pair existence by token balances at the computed pair address rather than verifying deployed pair code or reserves.",
    "impact": "Attackers can dust non-pair addresses so routing selects nonexistent direct pools, causing reserve lookups or swaps to revert and denying service for affected routes.",
    "paths": [
      "For a token pair without a real direct pool, send dust of both tokens to the computed pair address.",
      "`_existsPairPool` returns true and route selection chooses the direct path.",
      "Subsequent `getReserves` or swap calls revert on the non-pair target, blocking those swaps."
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
      "GatewayTransferNative.sol:416",
      "GatewayTransferNative.sol:477",
      "GatewayTransferNative.sol:496"
    ],
    "claim": "`GatewayTransferNative.withdraw` is publicly callable. Other flows approve `outputAmount + gasFee` when gas token equals output token, but the gateway spends only `outputAmount`, leaving residual allowance under some conditions.",
    "impact": "If residual approval and contract balance exist, notably after gas-fee changes, arbitrary callers may consume leftover allowance to trigger unauthorized withdrawals to attacker-chosen recipients.",
    "paths": [
      "A prior withdrawal path leaves nonzero residual approval from `GatewayTransferNative` to the gateway.",
      "An attacker calls public `withdraw` with attacker-controlled recipient bytes and an amount that fits the remaining allowance conditions.",
      "The gateway pulls contract tokens via leftover allowance and emits withdrawal to the attacker destination."
    ],
    "round": 1,
    "source_agents": [
      "codex_1",
      "opencode_1"
    ]
  },
  {
    "id": "F-009",
    "severity": "Critical",
    "confidence": "high",
    "title": "Empty `swapDataZ` path allows cross-asset withdrawals without performing conversion",
    "locations": [
      "GatewayCrossChain.sol:369",
      "GatewayCrossChain.sol:492",
      "GatewayCrossChain.sol:495",
      "GatewayCrossChain.sol:517",
      "GatewayTransferNative.sol:449",
      "GatewayTransferNative.sol:414",
      "GatewayTransferNative.sol:574",
      "GatewayTransferNative.sol:577",
      "GatewayTransferNative.sol:599"
    ],
    "claim": "When `swapDataZ` is empty, `_doMixSwap` returns the input `amount` directly. Callers can still set arbitrary `decoded.targetZRC20`, and withdrawal or payout logic proceeds as if a real conversion occurred.",
    "impact": "Attackers can provide one asset but withdraw or receive a different, more valuable token from contract-held reserves, causing direct reserve theft.",
    "paths": [
      "Send a message or call with `targetZRC20 != input zrc20` and empty `swapDataZ`.",
      "`_doMixSwap` returns the nominal input amount without any token conversion proof.",
      "The contract executes withdrawal or transfer in `targetZRC20` using its own inventory."
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-010",
    "severity": "Critical",
    "confidence": "high",
    "title": "GatewaySend source flow does not bind bridged asset to swap output asset",
    "locations": [
      "GatewaySend.sol:245",
      "GatewaySend.sol:257",
      "GatewaySend.sol:266",
      "GatewaySend.sol:170",
      "GatewaySend.sol:186"
    ],
    "claim": "`depositAndCall(fromToken,...)` computes a numeric `outputAmount` from `_doMixSwap`, then deposits whichever `asset` the caller supplied, without verifying that this asset was actually produced or received from the swap.",
    "impact": "If the contract holds balances of another token or ETH, attackers can swap one asset but bridge out a different asset from pooled reserves.",
    "paths": [
      "Call `depositAndCall(fromToken, amount, swapData, ..., asset, ...)` with swap output token different from `asset`.",
      "Obtain nonzero `outputAmount` or force it via crafted swap data.",
      "The contract deposits `outputAmount` of the attacker-chosen `asset` to the gateway, consuming contract reserves."
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-011",
    "severity": "Medium",
    "confidence": "high",
    "title": "Refund key collisions and zero-key handling can overwrite entries, block recording, or lock refunds",
    "locations": [
      "GatewayTransferNative.sol:628",
      "GatewayTransferNative.sol:648",
      "GatewayTransferNative.sol:661",
      "GatewayTransferNative.sol:670",
      "GatewayTransferNative.sol:683",
      "GatewayCrossChain.sol:561",
      "GatewayCrossChain.sol:585"
    ],
    "claim": "Refunds are keyed only by `externalId`. `GatewayTransferNative` overwrites `refundInfos[externalId]` without existence checks, and `claimRefund` rejects entries with zero-valued `externalId`, making key `0x0` refunds unclaimable. `GatewayCrossChain` uses a zero-sentinel duplicate guard that can be bypassed for `externalId == 0x0`, while non-zero collisions revert with `REFUND_INFO_ALREADY_EXISTS` and block later recording.",
    "impact": "Attackers can cause refund misdirection or overwrite, prevent later callback refund recording for colliding non-zero keys, and permanently lock refunds stored under `externalId == 0x0`.",
    "paths": [
      "Trigger a callback path that stores `refundInfos[externalId]` for key `X` in `GatewayTransferNative`; a later callback with the same key overwrites previous refund metadata.",
      "Pre-populate `GatewayCrossChain.refundInfos[X]` for non-zero `X`; subsequent callbacks for the same key revert on the duplicate guard and fail to record the new refund.",
      "Supply or propagate `externalId == 0x0` so callbacks store under key zero; `GatewayTransferNative.claimRefund(0x0)` always reverts due to the sentinel check."
    ],
    "round": 2,
    "source_agents": [
      "codex_1",
      "opencode_1"
    ]
  },
  {
    "id": "F-012",
    "severity": "Medium",
    "confidence": "high",
    "title": "AccountEncoder.decompressAccounts builds invalid memory layout for `Account[]`",
    "locations": [
      "libraries/AccountEncoder.sol:28",
      "libraries/AccountEncoder.sol:33",
      "libraries/AccountEncoder.sol:48",
      "GatewayCrossChain.sol:425",
      "GatewayCrossChain.sol:454",
      "GatewayTransferNative.sol:505",
      "GatewayTransferNative.sol:534"
    ],
    "claim": "`decompressAccounts` stores pointers in array slots where static `Account` structs are expected inline, so later ABI encoding reads corrupted struct fields.",
    "impact": "Solana-targeted payloads can be malformed and fail downstream decoding or calls, causing persistent route-level DoS and refund churn for affected transfers.",
    "paths": [
      "Use the Solana path with compressed accounts data.",
      "`decompressAccounts` produces a malformed `Account[]` memory representation.",
      "The encoded payload becomes invalid for downstream processing and `withdrawAndCall` fails."
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-013",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Recipient bytes are silently truncated or padded into EVM addresses in the local payout path",
    "locations": [
      "GatewayTransferNative.sol:390"
    ],
    "claim": "`GatewayTransferNative.onCall` casts dynamic recipient bytes to `bytes20/address` without requiring exact 20-byte length.",
    "impact": "Malformed or non-20-byte recipient payloads can be irreversibly misinterpreted, causing payouts to unintended EVM addresses and user fund loss.",
    "paths": [
      "Provide recipient bytes longer than 20 bytes with attacker-controlled first 20 bytes, or shorter bytes that get padded.",
      "The contract truncates or pads the bytes and derives an EVM address without validation.",
      "Funds are transferred to the derived address, not the intended recipient."
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-014",
    "severity": "High",
    "confidence": "medium",
    "title": "GatewaySend direct ERC20 source deposit uses nominal amount and can spend reserves on underfunded transfer-in",
    "locations": [
      "GatewaySend.sol:317",
      "GatewaySend.sol:320",
      "GatewaySend.sol:186"
    ],
    "claim": "In `depositAndCall(address targetContract, uint256 amount, address asset, ...)`, ERC20 intake checks only `transferFrom` boolean success and never reconciles actual balance delta before approving and depositing the full nominal `amount` to the gateway.",
    "impact": "With fee-on-transfer or deflationary ERC20s, the contract may receive less than `amount` but still bridge `amount`; any deficit is covered from pre-existing contract balances, enabling reserve drain and insolvency over repeated calls.",
    "paths": [
      "Call `depositAndCall(targetContract, amount, asset, ...)` using a taxed ERC20.",
      "The contract receives less than `amount` but still approves and deposits full `amount` to the gateway.",
      "The gateway pull succeeds using contract-held inventory to cover the shortfall, transferring value to an attacker-controlled cross-chain flow."
    ],
    "round": 3,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-017",
    "severity": "High",
    "confidence": "high",
    "title": "GatewaySend revert handler lacks native-asset refund path and can strand reverted ETH",
    "locations": [
      "GatewaySend.sol:393",
      "GatewaySend.sol:396"
    ],
    "claim": "`onRevert` always calls ERC20-style `TransferHelper.safeTransfer(context.asset, ...)` and has no branch for native refunds. For gas-token reverts where `context.asset` is empty or zero-address, this call does not transfer ETH back to the user.",
    "impact": "Failed ETH-origin cross-chain calls can be finalized without refunding the sender, leaving reverted value stranded in `GatewaySend` and exposed to secondary reserve-drain bugs.",
    "paths": [
      "A user submits an ETH `depositAndCall` through `GatewaySend`.",
      "Destination execution fails and the gateway triggers `onRevert` with gas-token context.",
      "The handler attempts token transfer using `context.asset` instead of native ETH transfer, so the sender is not refunded."
    ],
    "round": 3,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-018",
    "severity": "Critical",
    "confidence": "high",
    "title": "Swap output asset is not bound to target payout token before withdrawal/transfer",
    "locations": [
      "GatewayCrossChain.sol:376",
      "GatewayCrossChain.sol:492",
      "GatewayCrossChain.sol:432",
      "GatewayTransferNative.sol:414",
      "GatewayTransferNative.sol:422",
      "GatewayTransferNative.sol:456",
      "GatewayTransferNative.sol:541",
      "GatewayTransferNative.sol:574"
    ],
    "claim": "Both contracts execute DODO swaps using `params.toToken` but later withdraw or transfer `decoded.targetZRC20` without enforcing `params.toToken == decoded.targetZRC20`, or otherwise proving that the swapped asset matches the payout asset.",
    "impact": "Attackers can route swaps into a different or cheap token while forcing payout or withdrawal in a valuable reserve token, draining contract-held inventories.",
    "paths": [
      "Craft swap payload where `params.toToken` is not `decoded.targetZRC20` and yields a controllable `outputAmount`.",
      "Trigger `GatewayCrossChain.onCall`, `GatewayTransferNative.withdrawToNativeChain`, or `GatewayTransferNative.onCall` swap branches.",
      "The contract treats numeric `outputAmount` as an amount of `decoded.targetZRC20` and transfers or withdraws that token from reserves."
    ],
    "round": 4,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-022",
    "severity": "Medium",
    "confidence": "medium",
    "title": "`amountInMax`-based post-swap check can cause avoidable withdrawal reverts",
    "locations": [
      "GatewayTransferNative.sol:338",
      "GatewayTransferNative.sol:352",
      "GatewayTransferNative.sol:357"
    ],
    "claim": "`_swapAndSendERC20Tokens` computes `amountInMax` with slippage buffer, executes the swap, but then checks `targetAmount - amountInMax > 0` instead of `targetAmount - amounts[0] > 0`. This can revert even when actual spent input leaves a positive withdrawable remainder.",
    "impact": "Valid withdrawal flows can fail unnecessarily, causing cross-chain execution failures or refunds and enabling practical route-level liveness degradation when quotes are pushed near the threshold.",
    "paths": [
      "Increase quote pressure, or rely on high configured slippage, so `amountInMax >= targetAmount` while actual `amounts[0] < targetAmount`.",
      "`swapTokensForExactTokens` succeeds, but the subsequent `require(targetAmount - amountInMax > 0)` reverts.",
      "The user-facing withdrawal path fails despite sufficient actual post-swap balance."
    ],
    "round": 4,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-023",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Exact-output Uniswap approval pattern can DoS strict-approve tokens",
    "locations": [
      "GatewayCrossChain.sol:342",
      "GatewayCrossChain.sol:343",
      "GatewayCrossChain.sol:347",
      "GatewayTransferNative.sol:338",
      "GatewayTransferNative.sol:339",
      "GatewayTransferNative.sol:343"
    ],
    "claim": "Both contracts approve `amountInMax` before `swapTokensForExactTokens`. Because exact-output swaps commonly spend less than `amountInMax`, leftover router allowance remains. Later calls set another non-zero allowance without zero-reset.",
    "impact": "For tokens that enforce zero-first allowance updates, future swaps on affected routes revert, causing persistent token-pair liveness failure until allowance is manually cleared.",
    "paths": [
      "Run an exact-output gas-fee swap where `amounts[0] < amountInMax`.",
      "Residual allowance to `UniswapRouter` remains non-zero.",
      "A subsequent call executes `approve(UniswapRouter, newAmountInMax)` from non-zero allowance and strict token logic reverts."
    ],
    "round": 6,
    "source_agents": [
      "codex_1",
      "opencode_1"
    ]
  },
  {
    "id": "F-024",
    "severity": "Low",
    "confidence": "high",
    "title": "GatewaySend ETH input flows ignore `amount` and consume full `msg.value`",
    "locations": [
      "GatewaySend.sol:202",
      "GatewaySend.sol:233",
      "GatewaySend.sol:245",
      "GatewaySend.sol:308",
      "GatewaySend.sol:311"
    ],
    "claim": "Both ETH-input `depositAndCall` paths only require `msg.value >= amount`, but downstream consume the full `msg.value`: the direct overload deposits `msg.value` to the gateway, and the swap overload forwards `msg.value` into DODO instead of binding ETH spend to `amount`.",
    "impact": "Callers and integrators can unintentionally spend or bridge more ETH than intended, causing direct user loss and accounting mismatches.",
    "paths": [
      "Invoke the direct ETH overload with `msg.value > amount`; the function deposits full `msg.value` to the gateway even though the API parameter indicates a smaller amount.",
      "Invoke the swap ETH overload with `fromToken == _ETH_ADDRESS_` and `msg.value > amount`; `_doMixSwap` forwards full `msg.value` to DODO with no contract-side cap or refund of excess."
    ],
    "round": 6,
    "source_agents": [
      "codex_1",
      "merge_reviewer"
    ]
  },
  {
    "id": "F-025",
    "severity": "Low",
    "confidence": "high",
    "title": "GatewayTransferNative refund-claimed event emits zero token/amount due to storage read after delete",
    "locations": [
      "GatewayTransferNative.sol:692",
      "GatewayTransferNative.sol:694",
      "GatewayTransferNative.sol:696",
      "GatewayTransferNative.sol:697"
    ],
    "claim": "`claimRefund` stores `refundInfo` as a storage pointer, deletes `refundInfos[externalId]`, then emits `EddyCrossChainRefundClaimed` using `refundInfo.token` and `refundInfo.amount` from the deleted slot.",
    "impact": "Off-chain accounting, monitoring, and incident response that rely on the claim event can record zeroed token or amount values, weakening operational controls and reconciliation.",
    "paths": [
      "Execute any successful `claimRefund(externalId)` in `GatewayTransferNative`.",
      "The function transfers funds, deletes the mapping entry, and then reads fields via the stale storage reference for the event.",
      "The event logs zero token or amount despite a real payout."
    ],
    "round": 8,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-026",
    "severity": "High",
    "confidence": "high",
    "title": "GatewaySend `onCall` return type is ABI-incompatible with ZetaChain `Callable`",
    "locations": [
      "GatewaySend.sol:344",
      "GatewaySend.sol:385",
      "node_modules/@zetachain/protocol-contracts/contracts/evm/interfaces/IGatewayEVM.sol:229",
      "node_modules/@zetachain/protocol-contracts/contracts/evm/GatewayEVM.sol:439"
    ],
    "claim": "`GatewaySend.onCall` is declared `returns (bytes4)` and returns `\"\"`, but `IGatewayEVM.Callable.onCall` requires `returns (bytes memory)`. `GatewayEVM` invokes authenticated deliveries via `Callable(destination).onCall(...)`, so the caller ABI-decodes returndata as dynamic bytes and reverts on the fixed-size `bytes4` return payload.",
    "impact": "Authenticated cross-chain deliveries targeting `GatewaySend` cannot complete; the gateway call reverts and the destination settlement path is effectively bricked, forcing failure or refund handling for every attempted delivery.",
    "paths": [
      "A user targets `GatewaySend` as the destination contract for an authenticated cross-chain call.",
      "`GatewayEVM` performs `Callable(destination).onCall(...)` and expects a dynamic `bytes` return.",
      "`GatewaySend.onCall` returns fixed-size `bytes4`; ABI decoding in the gateway reverts, rolling back the entire destination execution."
    ],
    "round": 9,
    "source_agents": [
      "merge_reviewer"
    ]
  }
]

## This Round's Agent Outputs
### Agent: codex_1
```
[
  {
    "id": "F-027",
    "severity": "High",
    "confidence": "medium",
    "title": "Receive-side callbacks spend nominal amounts instead of actual received balances",
    "locations": [
      "GatewaySend.sol:359",
      "GatewaySend.sol:363",
      "GatewayCrossChain.sol:488",
      "GatewayCrossChain.sol:492",
      "GatewayTransferNative.sol:389",
      "GatewayTransferNative.sol:394",
      "GatewayTransferNative.sol:414"
    ],
    "claim": "The destination-side onCall handlers never verify how many tokens actually arrived before charging fees, swapping, or paying out. If a callback delivers less than its nominal amount, these paths still use the nominal amount and can consume pre-existing balances to cover the shortfall.",
    "impact": "An attacker can route under-delivering assets through the receive side and make the gateway contracts top up the difference from stored reserves, treasury accruals, or previous users' funds, causing insolvency or direct balance drain.",
    "paths": [
      "Bridge a fee-on-transfer ERC20 into GatewaySend with fromToken == toToken; transferFrom pulls the nominal amount from the gateway, the contract receives less, and the same-token branch still pays the full nominal amount.",
      "Deliver a short-receiving ZRC20 into GatewayCrossChain; platform fees and the downstream swap/withdraw logic still execute against the nominal amount, spending any existing local balance if needed.",
      "Deliver a short-receiving ZRC20 into GatewayTransferNative; the same-token payout path or swap path uses the nominal callback amount without measuring the actual receipt."
    ]
  },
  {
    "id": "F-028",
    "severity": "Medium",
    "confidence": "high",
    "title": "Native-input withdrawals can bypass platform fees during swap execution",
    "locations": [
      "GatewayTransferNative.sol:365",
      "GatewayTransferNative.sol:454",
      "GatewayTransferNative.sol:570"
    ],
    "claim": "For withdrawToNativeChain(_ETH_ADDRESS_, ...), platform fees are 'paid' via TransferHelper.safeTransfer to the ETH sentinel address, which does not move native value, while _doMixSwap still forwards the full msg.value to DODO. The fee deduction is therefore bookkeeping-only on native swap paths.",
    "impact": "Users can avoid the configured platform fee on native-input swap withdrawals, depriving the treasury of revenue and potentially receiving output on the full native input.",
    "paths": [
      "Call withdrawToNativeChain with zrc20 set to the ETH sentinel and a non-empty swapDataZ path; the contract computes a fee, transfers nothing to the treasury, and still supplies full msg.value to mixSwap."
    ]
  },
  {
    "id": "F-029",
    "severity": "Medium",
    "confidence": "medium",
    "title": "GatewaySend silently treats failed ERC20 payouts as successful",
    "locations": [
      "GatewaySend.sol:372",
      "GatewaySend.sol:375"
    ],
    "claim": "GatewaySend ignores the boolean return value of IERC20(toToken).transfer during the final payout. Tokens that return false instead of reverting make the callback emit a success event and return successfully even though no recipient transfer occurred.",
    "impact": "Bridged output tokens can become trapped inside GatewaySend with no refund, because the gateway sees a successful callback and the source-side revert flow is never triggered.",
    "paths": [
      "Route a bridge into a token whose transfer returns false or becomes non-transferable as toToken; the payout call fails silently and the function still reports success."
    ]
  },
  {
    "id": "F-030",
    "severity": "Medium",
    "confidence": "high",
    "title": "ETH payouts use 2300-gas transfer and can DoS contract recipients",
    "locations": [
      "GatewaySend.sol:369",
      "GatewaySend.sol:370"
    ],
    "claim": "When toToken is native ETH, GatewaySend uses transfer, which forwards only 2300 gas. Any recipient contract with a non-trivial receive/fallback, multisig logic, or deliberate revert will make the entire callback fail.",
    "impact": "A broad class of valid contract recipients cannot receive bridged ETH through this path, causing repeatable payout reverts and potentially cascading into source-side refund or fund-stranding flows.",
    "paths": [
      "Set the destination recipient to a contract wallet or receiver with a reverting or gas-heavy receive/fallback function while bridging to ETH; the callback reverts at the final transfer."
    ]
  },
  {
    "id": "F-031",
    "severity": "Low",
    "confidence": "high",
    "title": "Same-token WZETA payouts skip the unwrap path and deliver the wrong asset",
    "locations": [
      "GatewayTransferNative.sol:392",
      "GatewayTransferNative.sol:416"
    ],
    "claim": "The native-ZETA unwrap logic exists only in the swap branch. If the incoming asset is already WZETA and decoded.targetZRC20 == zrc20, the contract takes the same-token branch and transfers WZETA ERC20 directly instead of unwrapping to native ZETA.",
    "impact": "Receivers expecting native ZETA can receive the wrong asset, and contracts without ERC20 recovery logic may permanently lock the funds.",
    "paths": [
      "Bridge WZETA with decoded.targetZRC20 equal to WZETA; the contract follows the same-token branch and never reaches the unwrap-and-send-ETH branch."
    ]
  }
]

```

### Agent: opencode_1
```
I'll now read the contracts in scope to find security vulnerabilities.
Now let me read the library files and interfaces to get a complete picture:
Now I'll search for more potential vulnerabilities in the code:
Now let me examine more closely specific vulnerability patterns:
Now let me check if the `withdraw` function in GatewayCrossChain has access control:
Let me search for more potential issues:
Now let me compile my findings. Based on my analysis, I've identified several unique vulnerabilities not already in the known findings list:
Now I have analyzed all the files and can provide my findings. Based on my analysis of the contracts, I've identified several unique vulnerabilities that are distinct from the known findings list:

The main areas I found issues include:
1. GatewaySend.onCall - allows any message caller to transfer arbitrary token amounts from users
2. GatewaySend._calcExternalId - uses block.timestamp which can be manipulated
3. GatewayTransferNative.withdraw is public without access control  
4. ClaimRefund in GatewayTransferNative reads storage after delete

Let me return the JSON array:

```json
[
  {
    "id": "F-027",
    "severity": "Critical",
    "confidence": "high",
    "title": "GatewaySend onCall allows arbitrary token amount from user-provided allowance",
    "locations": [
      "GatewaySend.sol:359"
    ],
    "claim": "In GatewaySend.onCall, the contract transfers tokens from msg.sender using amount from the calldata message, allowing an attacker who controls the cross-chain message to drain approved user tokens",
    "impact": "Any user who has approved GatewaySend to spend their tokens can have arbitrary amounts stolen by anyone who can trigger cross-chain messages with crafted amount values",
    "paths": [
      "1. Attacker deposits to target chain with attacker-controlled message containing large amount",
      "2. Gateway calls onCall with attacker's crafted amount",
      "3. Contract transfers attacker's approved tokens to itself"
    ]
  },
  {
    "id": "F-028",
    "severity": "Medium",
    "confidence": "medium",
    "title": "GatewaySend externalId uses block.timestamp which can be manipulated by validators",
    "locations": [
      "GatewaySend.sol:161"
    ],
    "claim": "_calcExternalId uses block.timestamp in the hash calculation which can be slightly manipulated by validators within bounds",
    "impact": "ExternalId collisions become more feasible as validators can influence block.timestamp within a range, potentially enabling refund claim race conditions",
    "paths": [
      "1. Validator includes multiple transactions with different timestamps",
      "2. Same external ID generation becomes predictable"
    ]
  },
  {
    "id": "F-029",
    "severity": "Medium",
    "confidence": "high",
    "title": "GatewayTransferNative.withdraw lacks access control and is publicly callable",
    "locations": [
      "GatewayTransferNative.sol:305"
    ],
    "claim": "The withdraw function is public without any access control modifier, allowing anyone to trigger withdrawals from contract reserves",
    "impact": "Can drain the contract's token balance if withdrawals are not properly gated by the gateway",
    "paths": [
      "1. Anyone calls withdraw with crafted parameters",
      "2. Contract sends tokens to sender address"
    ]
  },
  {
    "id": "F-030",
    "severity": "Medium",
    "confidence": "high",
    "title": "GatewayTransferNative claimRefund reads storage after delete risking zero amount",
    "locations": [
      "GatewayTransferNative.sol:680-700"
    ],
    "claim": "In claimRefund, storage is deleted after TransferHelper.safeTransfer but event emission reads refundInfo after delete, causing zero token/amount to be emitted",
    "impact": "Off-chain monitors tracking refund claims see zero amounts, breaking reconciliation and accounting",
    "paths": [
      "1. Claim refund is called",
      "2. Transfer executes before delete",
      "3. Event emits zeros because storage was cleared"
    ]
  }
]
```

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
