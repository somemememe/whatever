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
    "claim": "The contracts decode `MixSwapParams` from attacker-controlled payloads and use `params.fromToken` / `params.fromTokenAmount` in approvals and `mixSwap` without enforcing that they match the token and net amount actually available in the current execution path (including fee-adjusted paths).",
    "impact": "Attackers can spend unrelated token balances already held by these contracts (fees, stranded balances, prior user funds) and route swap outputs to attacker-controlled recipients, causing direct theft.",
    "paths": [
      "Craft payload/swapData with `params.fromToken` set to a valuable token currently held by the contract and `params.fromTokenAmount` set to the desired drain amount.",
      "Trigger `onCall`, `withdrawToNativeChain`, or `depositAndCall` with cheap/unrelated input.",
      "Contract approves DODO for attacker-chosen token and `mixSwap` pulls/spends contract inventory for attacker benefit.",
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
    "claim": "`withdraw` encodes revert recipient as `bytes20(sender)`, truncating non-20-byte addresses. `onRevert` then interprets the 52-byte revert payload as an EVM address refund target.",
    "impact": "Failed non-EVM withdrawals can refund to unintended EVM addresses (or unusable addresses), causing permanent user fund loss.",
    "paths": [
      "User initiates withdrawal with a non-20-byte recipient format.",
      "Withdrawal fails and gateway calls `onRevert` with truncated 20-byte recipient bytes.",
      "Contract refunds to that truncated EVM address instead of the intended non-EVM recipient."
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
      "GatewayTransferNative.sol:549",
      "GatewayTransferNative.sol:554",
      "GatewayTransferNative.sol:555",
      "GatewayTransferNative.sol:570",
      "GatewayTransferNative.sol:574",
      "GatewayTransferNative.sol:577",
      "GatewayTransferNative.sol:599",
      "GatewayTransferNative.sol:477"
    ],
    "claim": "`withdrawToNativeChain` uses caller-supplied `amount` as the accounting source for fee/swap/withdraw flows, but does not verify actual token balance delta. The ETH sentinel path skips transfer-in entirely, and ERC20 paths only check a boolean `transferFrom` return.",
    "impact": "Attackers can trigger withdrawals of real `decoded.targetZRC20` from contract-held inventory without providing equivalent funding, enabling direct theft of pooled assets.",
    "paths": [
      "Call `withdrawToNativeChain(_ETH_ADDRESS_, amount, message)` to bypass token pull, then route to valuable `targetZRC20`.",
      "Or use a malicious/deflationary token that returns success while transferring less than `amount`.",
      "Contract computes output from nominal `amount` and executes gateway withdrawal using existing target-token balances."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-005",
    "severity": "Critical",
    "confidence": "high",
    "title": "GatewaySend destination onCall trusts payload amount/token data and can drain contract reserves",
    "locations": [
      "GatewaySend.sol:347",
      "GatewaySend.sol:354",
      "GatewaySend.sol:359",
      "GatewaySend.sol:363",
      "GatewaySend.sol:370",
      "GatewaySend.sol:372"
    ],
    "claim": "`GatewaySend.onCall` trusts `amount`, `fromToken`, and `toToken` decoded from attacker-controlled payload bytes instead of reconciling to assets delivered by gateway for that call. The function can skip funding pulls (`fromToken == ETH sentinel`) and also ignores ERC20 transfer return values.",
    "impact": "Crafted cross-chain payloads can force ETH/ERC20 payouts from pre-existing contract balances to attacker-controlled recipients, causing direct theft.",
    "paths": [
      "Send cross-chain call with payload encoding inflated `amount` and attacker-chosen token mode.",
      "Destination `onCall` computes `outputAmount` from payload values, not reconciled balances.",
      "Contract transfers ETH/ERC20 reserves to attacker recipient."
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
      "For a token pair without a real direct pool, send dust of both tokens to computed pair address.",
      "`_existsPairPool` returns true and route selection chooses 2-hop direct path.",
      "Subsequent `getReserves`/swap calls revert on non-pair target, blocking those swaps."
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
    "claim": "`GatewayTransferNative.withdraw` is publicly callable. Other flows approve `outputAmount + gasFee` when gas token equals output token, but gateway spends only `outputAmount`, leaving residual allowance under some conditions.",
    "impact": "If residual approval and contract balance exist (notably after gas-fee changes), arbitrary callers may consume leftover allowance to trigger unauthorized withdrawals to attacker-chosen recipients.",
    "paths": [
      "A prior withdrawal path leaves nonzero residual allowance from `GatewayTransferNative` to gateway.",
      "Attacker calls public `withdraw` with attacker-controlled recipient bytes and amount that fits remaining allowance conditions.",
      "Gateway pulls contract tokens via leftover allowance and emits withdrawal to attacker destination."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
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
    "claim": "When `swapDataZ` is empty, `_doMixSwap` returns the input `amount` directly. Callers can still set arbitrary `decoded.targetZRC20`, and withdrawal/payout logic proceeds as if a real conversion occurred.",
    "impact": "Attackers can provide one asset but withdraw/receive a different, more valuable token from contract-held reserves, causing direct reserve theft.",
    "paths": [
      "Send message/call with `targetZRC20 != input zrc20` and empty `swapDataZ`.",
      "`_doMixSwap` returns nominal input amount without any token conversion proof.",
      "Contract executes withdraw/transfer in `targetZRC20` using its own inventory."
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
    "claim": "`depositAndCall(fromToken,...)` computes a numeric `outputAmount` from `_doMixSwap`, then deposits whichever `asset` the caller supplied, without verifying that this asset was actually produced/received from the swap.",
    "impact": "If the contract holds balances of another token/ETH, attackers can swap one asset but bridge out a different asset from pooled reserves.",
    "paths": [
      "Call `depositAndCall(fromToken, amount, swapData, ..., asset, ...)` with swap output token different from `asset`.",
      "Obtain nonzero `outputAmount` (or force it via crafted swap data).",
      "Contract deposits `outputAmount` of attacker-chosen `asset` to gateway, consuming contract reserves."
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
    "claim": "Refunds are keyed only by `externalId`. `GatewayTransferNative` overwrites `refundInfos[externalId]` without existence checks, and `claimRefund` rejects entries with zero-valued `externalId` (`refundInfo.externalId != \"\"`), making key `0x0` refunds unclaimable. `GatewayCrossChain` uses a zero-sentinel duplicate guard that can be bypassed for `externalId == 0x0`, while non-zero collisions revert with `REFUND_INFO_ALREADY_EXISTS` and block later recording.",
    "impact": "Attackers can cause refund misdirection/overwrite, prevent later callback refund recording for colliding non-zero keys, and permanently lock refunds stored under `externalId == 0x0`.",
    "paths": [
      "Trigger a callback path that stores `refundInfos[externalId]` for key `X` in `GatewayTransferNative`; a later callback with the same key overwrites previous refund metadata.",
      "Pre-populate `GatewayCrossChain.refundInfos[X]` for non-zero `X`; subsequent callbacks for the same key revert on duplicate guard and fail to record the new refund.",
      "Supply/propagate `externalId == 0x0` (e.g., via crafted message IDs) so callbacks store under key zero; `GatewayTransferNative.claimRefund(0x0)` always reverts due the sentinel check."
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
    "impact": "Solana-targeted payloads can be malformed and fail downstream decoding/calls, causing persistent route-level DoS/refund churn for affected transfers.",
    "paths": [
      "Use Solana path (`dstChainId == SOLANA_EDDY`) with compressed accounts data.",
      "`decompressAccounts` produces malformed `Account[]` memory representation.",
      "Encoded payload becomes invalid for downstream processing and withdraw-and-call fails."
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
    "title": "Recipient bytes are silently truncated/padded into EVM addresses in payout paths",
    "locations": [
      "GatewayTransferNative.sol:390",
      "GatewaySend.sol:356"
    ],
    "claim": "Both payout paths cast dynamic recipient bytes to `bytes20/address` without requiring exact 20-byte length.",
    "impact": "Malformed or non-20-byte recipient payloads can be irreversibly misinterpreted, causing payouts to unintended EVM addresses and user fund loss.",
    "paths": [
      "Provide recipient bytes longer than 20 bytes with attacker-controlled first 20 bytes (or shorter bytes that get padded).",
      "Contract truncates/pads and derives an EVM address without validation.",
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
    "claim": "In `depositAndCall(address targetContract, uint256 amount, address asset, ...)`, ERC20 intake checks only `transferFrom` boolean success and never reconciles actual balance delta before approving/depositing the full nominal `amount` to the gateway.",
    "impact": "With fee-on-transfer/deflationary ERC20s, the contract may receive less than `amount` but still bridge `amount`; any deficit is covered from pre-existing contract balances, enabling reserve drain and insolvency over repeated calls.",
    "paths": [
      "Call `depositAndCall(targetContract, amount, asset, ...)` using a taxed ERC20.",
      "Contract receives `< amount` but still approves/deposits full `amount` to gateway.",
      "Gateway pull succeeds using contract-held inventory to cover the shortfall, transferring value to attacker-controlled cross-chain flow."
    ],
    "round": 3,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-015",
    "severity": "Medium",
    "confidence": "high",
    "title": "GatewaySend destination finalizes success even when ERC20 payout transfer fails softly",
    "locations": [
      "GatewaySend.sol:372",
      "GatewaySend.sol:385"
    ],
    "claim": "`onCall` executes `IERC20(toToken).transfer(...)` without checking the returned boolean and then returns success to the gateway.",
    "impact": "If a token returns `false` (instead of reverting), cross-chain delivery is marked successful while recipient payment never happens, causing silent non-delivery and potential fund lockup in the contract.",
    "paths": [
      "Process destination message where payout token's `transfer` returns `false`.",
      "`onCall` does not revert and still returns success.",
      "No revert/refund path is triggered, while recipient remains unpaid."
    ],
    "round": 3,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-016",
    "severity": "Low",
    "confidence": "high",
    "title": "GatewaySend ETH payout uses `.transfer` and can DoS smart-contract recipients",
    "locations": [
      "GatewaySend.sol:370"
    ],
    "claim": "ETH delivery uses Solidity `.transfer`, forwarding only 2300 gas to the recipient.",
    "impact": "Many contract wallets/proxies cannot receive ETH under 2300 gas; affected cross-chain deliveries deterministically revert, reducing liveness for those recipients.",
    "paths": [
      "Set destination recipient to a contract with non-trivial `receive`/`fallback` logic.",
      "`onCall` executes `payable(recipient).transfer(outputAmount)`.",
      "Transfer reverts and delivery path fails for that recipient class."
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
    "claim": "`onRevert` always calls ERC20-style `TransferHelper.safeTransfer(context.asset, ...)` and has no branch for native refunds. For gas-token reverts where `context.asset` is empty/zero-address, this call does not transfer ETH back to the user.",
    "impact": "Failed ETH-origin cross-chain calls can be finalized without refunding the sender, leaving reverted value stranded in `GatewaySend` (and exposed to secondary reserve-drain bugs).",
    "paths": [
      "User submits ETH `depositAndCall` through `GatewaySend`.",
      "Destination execution fails and gateway triggers `onRevert` with gas-token context.",
      "Handler attempts token transfer using `context.asset` instead of native ETH transfer, so sender is not refunded."
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
    "claim": "Both contracts execute DODO swaps using `params.toToken` but later withdraw/transfer `decoded.targetZRC20` without enforcing `params.toToken == decoded.targetZRC20` (or proving that the swapped asset matches the payout asset).",
    "impact": "Attackers can route swaps into a different/cheap token while forcing payout/withdrawal in a valuable reserve token, draining contract-held inventories.",
    "paths": [
      "Craft swap payload where `params.toToken` is not `decoded.targetZRC20` and yields a controllable `outputAmount`.",
      "Trigger `GatewayCrossChain.onCall`, `GatewayTransferNative.withdrawToNativeChain`, or `GatewayTransferNative.onCall` swap branch.",
      "Contract treats numeric `outputAmount` as amount of `decoded.targetZRC20` and transfers/withdraws that token from reserves."
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
    "impact": "Valid withdrawal flows can fail unnecessarily, causing cross-chain execution failures/refunds and enabling practical route-level liveness degradation (economic DoS) when quotes are pushed near threshold.",
    "paths": [
      "Increase quote pressure (or rely on high configured slippage) so `amountInMax >= targetAmount` while actual `amounts[0] < targetAmount`.",
      "`swapTokensForExactTokens` succeeds, but the subsequent `require(targetAmount - amountInMax > 0)` reverts.",
      "User-facing withdrawal path fails despite sufficient actual post-swap balance."
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
    "claim": "Both contracts approve `amountInMax` before `swapTokensForExactTokens`. Because exact-output swaps commonly spend `< amountInMax`, leftover router allowance remains. Later calls set another non-zero allowance without zero-reset.",
    "impact": "For tokens that enforce zero-first allowance updates (USDT-style), future swaps on affected routes revert, causing persistent token-pair liveness failure until allowance is manually cleared.",
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
    "title": "ETH `depositAndCall` overload ignores `amount` and forwards full `msg.value`",
    "locations": [
      "GatewaySend.sol:307",
      "GatewaySend.sol:311"
    ],
    "claim": "In `depositAndCall(address targetContract, uint256 amount, address asset, ...)` for ETH, the function only checks `msg.value >= amount` but deposits `msg.value` to gateway instead of `amount`.",
    "impact": "Callers and integrators can unintentionally bridge more ETH than intended, causing direct user loss and accounting mismatches across source/destination systems.",
    "paths": [
      "Invoke the ETH overload with `msg.value > amount`.",
      "Function passes validation and calls `_handleETHDeposit(..., msg.value, ...)`.",
      "Full `msg.value` is bridged even though the API parameter indicates a smaller intended amount."
    ],
    "round": 6,
    "source_agents": [
      "codex_1"
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
    "impact": "Off-chain accounting, monitoring, and incident response that rely on the claim event can record zeroed token/amount values, weakening operational controls and reconciliation.",
    "paths": [
      "Execute any successful `claimRefund(externalId)` in `GatewayTransferNative`.",
      "Function transfers funds, deletes mapping entry, and then reads fields via the stale storage reference for the event.",
      "Event logs zero token/amount despite a real payout."
    ],
    "round": 8,
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
    "id": "F-026",
    "severity": "High",
    "confidence": "high",
    "title": "GatewayTransferNative local-delivery swaps spend the pre-fee amount and can siphon reserves",
    "locations": [
      "GatewayTransferNative.sol:389",
      "GatewayTransferNative.sol:414",
      "GatewayTransferNative.sol:453"
    ],
    "claim": "`GatewayTransferNative.onCall` transfers the platform fee out of the received `zrc20`, but any non-same-token branch still calls `_doMixSwap(decoded.swapData, amount, params)` with the original pre-fee `amount`. The DODO route is therefore approved for more tokens than remain after fee collection, so it can consume the fee shortfall from pre-existing balances or revert.",
    "impact": "An attacker can repeatedly recover the fee portion from retained `zrc20` balances during local ZetaChain payouts, draining reserves over time or making destination swaps unavailable once those reserves are exhausted.",
    "paths": [
      "GatewayTransferNative.onCall -> _handleFeeTransfer(zrc20, amount) -> _doMixSwap(decoded.swapData, amount, params) -> DODO pulls the full pre-fee amount although only `amount - platformFeesForTx` remains"
    ]
  },
  {
    "id": "F-027",
    "severity": "High",
    "confidence": "high",
    "title": "GatewaySend destination settlement trusts nominal ERC20 pull amounts and can spend reserves on taxed or soft-failing tokens",
    "locations": [
      "GatewaySend.sol:359",
      "GatewaySend.sol:363",
      "GatewaySend.sol:372"
    ],
    "claim": "`GatewaySend.onCall` uses the message's `amount` after calling `IERC20(fromToken).transferFrom(msg.sender, address(this), amount)` without checking the return value or the actual balance delta. Fee-on-transfer, rebasing, or false-return ERC20s can therefore leave the contract underfunded while the function still swaps or pays out the full nominal amount.",
    "impact": "If any supported bridged asset delivers less than `amount`, the contract subsidizes the shortfall from existing balances. With enough retained funds, attackers can drain reserves on destination-chain settlements; otherwise legitimate transfers become flaky or revert unpredictably.",
    "paths": [
      "GatewaySend.onCall -> transferFrom(gateway, this, amount) receives less than `amount` -> `fromToken == toToken` branch transfers full `amount` to the recipient from reserves",
      "GatewaySend.onCall -> transferFrom(gateway, this, amount) receives less than `amount` -> `_doMixSwap(swapData)` still executes against the nominal amount and can consume retained token balances"
    ]
  },
  {
    "id": "F-028",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Cross-chain withdrawal logic never binds `dstChainId` to `targetZRC20` and can route funds through the wrong chain-specific path",
    "locations": [
      "libraries/SwapDataHelperLib.sol:68",
      "GatewayCrossChain.sol:425",
      "GatewayCrossChain.sol:495",
      "GatewayTransferNative.sol:505",
      "GatewayTransferNative.sol:577"
    ],
    "claim": "Both withdrawal flows decode a user-controlled `dstChainId` and `targetZRC20`, but never verify that they describe the same destination chain. The contracts branch on `dstChainId` to choose Bitcoin vs EVM/Solana handling and whether to Solana-wrap the payload, while the actual gateway withdrawal is parameterized only by `targetZRC20` and receiver bytes.",
    "impact": "A crafted mismatch can force an asset into an incompatible withdrawal mode or payload format, causing malformed receivers, perpetual reverts, or permanently misdelivered/locked funds.",
    "paths": [
      "Use an EVM-chain `targetZRC20` with `dstChainId = BITCOIN_EDDY` to force the Bitcoin `withdraw` path and raw receiver bytes on a non-Bitcoin asset",
      "Use a non-Solana `targetZRC20` with `dstChainId = SOLANA_EDDY` to force Solana account encoding and `withdrawAndCall` payload wrapping for the wrong destination"
    ]
  },
  {
    "id": "F-029",
    "severity": "Medium",
    "confidence": "high",
    "title": "Native-input `withdrawToNativeChain` lets callers bypass platform fees by decoupling `amount` from `msg.value`",
    "locations": [
      "GatewayTransferNative.sol:360",
      "GatewayTransferNative.sol:454",
      "GatewayTransferNative.sol:553",
      "GatewayTransferNative.sol:570"
    ],
    "claim": "When `zrc20 == _ETH_ADDRESS_`, `withdrawToNativeChain` skips any transfer-in, computes fees from the caller-supplied `amount`, attempts to 'transfer' that fee to the `_ETH_ADDRESS_` sentinel via `TransferHelper.safeTransfer` (a no-op), and then forwards the full `msg.value` into `_doMixSwap`. Callers can therefore process arbitrary native value while paying fees only on a tiny nominal `amount`, including zero.",
    "impact": "Users can permissionlessly evade protocol fees on native-input withdrawals, depriving the treasury of expected revenue and leaving internal accounting/events inconsistent with the actual value bridged.",
    "paths": [
      "Call `withdrawToNativeChain(_ETH_ADDRESS_, 0, message)` with non-empty `swapDataZ`, set the swap to consume native value, and send a large `msg.value`"
    ]
  }
]

```

### Agent: opencode_1
```
Let me first explore the in-scope contracts to understand the codebase and find new vulnerabilities.
Let me read the main in-scope contracts to find new vulnerabilities:
Let me also read the libraries to understand all the code paths:
Let me also read the prior round summary to avoid duplicating findings:
Let me also check the global summary:
Now I have a comprehensive view of the contracts. Let me analyze for NEW vulnerabilities not already in the known findings list (F-001 to F-025):

Based on my analysis, here are the new findings:

[
  {
    "id": "F-026",
    "severity": "Critical",
    "confidence": "high",
    "title": "GatewaySend depositAndCall does not verify swap output or return funds on swap failure",
    "locations": ["GatewaySend.sol:245", "GatewaySend.sol:257-272"],
    "claim": "depositAndCall calls _doMixSwap and uses outputAmount for deposit without verifying swap success or handling swap failure. If swap returns 0 or less than expected, user loses funds or gets unexpected deposit.",
    "impact": "Users lose funds when swap fails, returns 0, or produces unexpectedly low output. No fallback or refund mechanism exists.",
    "paths": ["User calls depositAndCall with swapData -> _doMixSwap executes external call to DODORouteProxy -> outputAmount used for deposit without验证 -> user funds lost if swap fails/returns 0"]
  },
  {
    "id": "F-027",
    "severity": "Critical",
    "confidence": "high",
    "title": "GatewaySend onCall uses message amount instead of actual token balance",
    "locations": ["GatewaySend.sol:358-359"],
    "claim": "onCall uses IERC20(fromToken).transferFrom(msg.sender, address(this), amount) with amount from decoded message, not actual received balance. This allows arbitrary amount claims from gateway.",
    "impact": "Gateway can be tricked into believing different amounts were received, causing accounting issues and potential reserve drained via onRevert path.",
    "paths": ["Gateway calls onCall with crafted message containing inflated amount -> transferFrom extracts tokens from gateway -> accounting mismatch"]
  },
  {
    "id": "F-028",
    "severity": "Critical",
    "confidence": "high",
    "title": "GatewayTransferNative.claimRefund reads storage after delete allowing double-claim with reentrancy",
    "locations": ["GatewayTransferNative.sol:680-700"],
    "claim": "claimRefund reads refundInfo.amount and token BEFORE delete, but emits event AFTER transfer. Unlike GatewayCrossChain which deletes first, this has storage-read-after-delete pattern that can still re-enter between transfer and emit.",
    "impact": "Reentrancy can allow double-claim of refund via callbacks before event emission completes the state change.",
    "paths": ["Attacker calls claimRefund -> receives refund -> callback re-enters claimRefund with same externalId -> now refundInfo.amount may read as 0 (if deleted) or be inconsistent state"]
  },
  {
    "id": "F-029",
    "severity": "High",
    "confidence": "medium",
    "title": "Platform fee calculation ignores token decimals causing severe undercharging",
    "locations": ["GatewayCrossChain.sol:324-327", "GatewayTransferNative.sol:360-366"],
    "claim": "Platform fee is calculated as (amount * feePercent) / 1000 using raw amount without accounting for token decimals. A 100k token with 18 decimals is treated the same as 100k with 6 decimals.",
    "impact": "Protocol loses 99.9%+ of expected fees on high-decimal tokens, or overcharges low-decimal tokens.",
    "paths": ["User bridges high-decimal token (e.g., 18 decimals) -> amount is large number -> fee calculation massively undercollected"]
  },
  {
    "id": "F-030",
    "severity": "High",
    "confidence": "medium",
    "title": "Public withdraw function in GatewayTransferNative lacks access control and can be abused",
    "locations": ["GatewayTransferNative.sol:305-323"],
    "claim": "withdraw function is public (not internal), allowing anyone to trigger withdrawals. Combined with approval leftovers from _swapAndSendERC20Tokens, attacker can trigger withdrawal that uses approval residue.",
    "impact": "Anyone can trigger withdrawals using contract's approved tokens or cause unexpected withdraw calls.",
    "paths": ["Anyone calls public withdraw() -> gateway.withdraw executes -> uses any approved tokens leftover"]
  },
  {
    "id": "F-031",
    "severity": "High",
    "confidence": "medium",
    "title": "No deadline check in Uniswap swap allowing stale trades",
    "locations": ["GatewayCrossChain.sol:342-353", "GatewayTransferNative.sol:338-349"],
    "claim": "Swap uses block.timestamp + MAX_DEADLINE (200 seconds) but deadline is passed AFTER approval is set and swap is executed, creating race condition where stale trades execute after deadline passes.",
    "impact": "Swaps may execute at unfavorable rates after user expected deadline, causing unexpected token output.",
    "paths": ["User initiates swap -> 200 second window allows execution after price moves -> user receives less than expected"]
  },
  {
    "id": "F-032",
    "severity": "Medium",
    "confidence": "medium",
    "title": "onRevert uses .transfer for ETH which can DoS smart contract receivers",
    "locations": ["GatewaySend.sol:396", "GatewayCrossChain.sol:552"],
    "claim": "onRevert in GatewaySend uses plain .transfer() for ETH which is deprecated and fails for contracts with receive() that uses more than 2300 gas.",
    "impact": "Smart contract receivers cannot receiveETH refunds via onRevert path, refunds get stuck.",
    "paths": ["Cross-chain swap reverts -> onRevert called -> .transfer to smart contract -> fails -> refund stuck"]
  },
  {
    "id": "F-033",
    "severity": "Medium",
    "confidence": "medium",
    "title": "No event emitted for critical withdrawToNativeChain state change",
    "locations": ["GatewayTransferNative.sol:549-619"],
    "claim": "withdrawToNativeChain updates globalNonce and processes swaps but emits event only in sub-calls, not for the main withdrawal action.",
    "impact": "Off-chain indexers cannot track the main withdrawal, causing incorrect balance tracking.",
    "paths": ["User calls withdrawToNativeChain -> state changes but no main event emitted -> off-chain indexing misses it"]
  },
  {
    "id": "F-034",
    "severity": "Medium",
    "confidence": "low",
    "title": "Message decoding lacks bounds checking allowing out-of-bounds read",
    "locations": ["GatewaySend.sol:114-141"],
    "claim": "decodePackedMessage uses assembly to read packed message fields but does not verify message length before reading, potentially reading beyond calldata.",
    "impact": "Reading beyond bounds returns undefined data, causing mis-parsed messages and potential logic errors.",
    "paths": ["Attacker provides short message -> decode reads beyond -> garbage data used -> wrong token/amount routing"]
  },
  {
    "id": "F-035",
    "severity": "Low",
    "confidence": "medium",
    "title": "External call to DODORouteProxy lacks reentrancy protection",
    "locations": ["GatewayCrossChain.sol:373-387", "GatewayTransferNative.sol:444-467", "GatewaySend.sol:195-216"],
    "claim": "_doMixSwap and _doMixSwapExternal make external calls to untrusted DODORouteProxy without reentrancy guards.",
    "impact": "Malicious or compromised DODORouteProxy can re-enter contract during swap execution.",
    "paths": ["Contract calls DODORouteProxy.mixSwap -> malicious contract Callback/reentrancy -> state inconsistency"]
  }
]

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
