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
    "confidence": "medium",
    "title": "Refund key collisions can overwrite entries or block later refund recording",
    "locations": [
      "GatewayTransferNative.sol:642",
      "GatewayTransferNative.sol:648",
      "GatewayTransferNative.sol:664",
      "GatewayTransferNative.sol:670",
      "GatewayCrossChain.sol:476",
      "GatewayCrossChain.sol:561",
      "GatewayCrossChain.sol:568",
      "GatewayCrossChain.sol:585",
      "GatewayCrossChain.sol:592"
    ],
    "claim": "Refunds are keyed only by `externalId`. `GatewayTransferNative` overwrites `refundInfos[externalId]` without existence checks. `GatewayCrossChain` reverts if the key is already populated, which lets a pre-existing entry block later callback recording; additionally, `externalId == 0x0` bypasses the duplicate guard because stored sentinel checks compare against zero.",
    "impact": "Attackers can cause refund misdirection/overwrite, or pre-poison refund slots so later non-52-byte revert/abort callbacks fail with `REFUND_INFO_ALREADY_EXISTS`, leading to refund loss or lockup.",
    "paths": [
      "Create a refund entry for key `X` via an earlier revert/abort path (or overwrite directly in `GatewayTransferNative`).",
      "When a later callback uses the same `externalId = X`, `GatewayCrossChain` reverts on duplicate and fails to record that refund.",
      "For `externalId == 0x0`, repeated callbacks can overwrite prior metadata because the sentinel check always passes."
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
  }
]

## This Round's Agent Outputs
### Agent: codex_1
```
[
  {
    "id": "F-025",
    "severity": "High",
    "confidence": "high",
    "title": "GatewaySend destination execution uses nominal `amount` without validating actual ERC20 intake",
    "locations": [
      "GatewaySend.sol:359",
      "GatewaySend.sol:363",
      "GatewaySend.sol:372"
    ],
    "claim": "`onCall` assumes the declared `amount` is fully received, but it neither checks `transferFrom` return value nor measures balance deltas before paying out.",
    "impact": "For fee-on-transfer/deflationary/soft-fail ERC20s, recipients can be paid the full nominal amount while less was actually received, draining token reserves held by `GatewaySend`.",
    "paths": [
      "Gateway invokes `onCall` with ERC20 `fromToken` and `amount = M`.",
      "`IERC20(fromToken).transferFrom(gateway, this, M)` transfers less than `M` (or returns false without revert).",
      "Contract still uses nominal `M` for payout logic and transfers out `M`, sourcing the shortfall from existing reserves."
    ]
  },
  {
    "id": "F-026",
    "severity": "Low",
    "confidence": "high",
    "title": "Native-input fee transfer silently no-ops when `_ETH_ADDRESS_` is used as token address",
    "locations": [
      "GatewayTransferNative.sol:360",
      "GatewayTransferNative.sol:365",
      "GatewayTransferNative.sol:554"
    ],
    "claim": "`withdrawToNativeChain` allows `zrc20 == _ETH_ADDRESS_`, but `_handleFeeTransfer` still uses ERC20 `safeTransfer` on that sentinel address; this call can succeed without moving any value.",
    "impact": "Protocol fee accounting is broken on native-input flows: treasury can receive zero while execution continues, causing fee mis-accounting and stranded ETH inside the contract.",
    "paths": [
      "Caller uses `withdrawToNativeChain` with `zrc20 = _ETH_ADDRESS_`.",
      "`_handleFeeTransfer` calls `TransferHelper.safeTransfer(_ETH_ADDRESS_, treasury, fee)`.",
      "Call reports success but no transfer occurs; fee is not delivered to treasury."
    ]
  },
  {
    "id": "F-027",
    "severity": "Informational",
    "confidence": "high",
    "title": "Refund-claimed event logs zero token/amount due storage-delete ordering",
    "locations": [
      "GatewayTransferNative.sol:691",
      "GatewayTransferNative.sol:692",
      "GatewayTransferNative.sol:696",
      "GatewayTransferNative.sol:697"
    ],
    "claim": "`claimRefund` emits `refundInfo.token` and `refundInfo.amount` after deleting the storage slot referenced by `refundInfo`.",
    "impact": "Audit/monitoring pipelines can record incorrect refund data (zero token and amount), weakening incident response and reconciliation.",
    "paths": [
      "`claimRefund` transfers using `refundInfo` storage pointer.",
      "`delete refundInfos[externalId]` clears that slot.",
      "Event reads cleared storage values and emits zeros."
    ]
  },
  {
    "id": "F-028",
    "severity": "Low",
    "confidence": "medium",
    "title": "Packed-message parser can read token addresses outside declared `crossChainData` length",
    "locations": [
      "GatewaySend.sol:135",
      "GatewaySend.sol:138",
      "GatewaySend.sol:148",
      "GatewaySend.sol:150"
    ],
    "claim": "`decodePackedData` uses raw `calldataload` for `tokenA/tokenB` without enforcing `data.length >= 40`, so parsed addresses may come from bytes beyond the declared slice.",
    "impact": "Length fields do not strictly constrain parsed token fields; malformed payloads can produce unintended token interpretation and routing behavior.",
    "paths": [
      "Craft message with small `crossChainDataLen` but append trailing bytes.",
      "`decodePackedData` still loads 40 bytes from calldata starting at `data.offset`.",
      "Loaded bytes may come from outside the declared `crossChainData` segment."
    ]
  },
  {
    "id": "F-029",
    "severity": "Low",
    "confidence": "low",
    "title": "TransferNative revert handlers lack minimum `revertMessage` length checks",
    "locations": [
      "GatewayTransferNative.sol:628",
      "GatewayTransferNative.sol:661"
    ],
    "claim": "`onRevert` and `onAbort` slice `revertMessage[0:32]` without validating that `revertMessage.length >= 32`.",
    "impact": "Malformed callbacks can panic-revert the handler and prevent refund recording/processing, potentially stranding reverted assets.",
    "paths": [
      "Gateway callback provides `revertMessage` shorter than 32 bytes.",
      "Slice operation on `[0:32]` reverts.",
      "Refund handling path aborts."
    ]
  }
]

```

### Agent: opencode_1
```
I'll audit the contracts in the specified directory. Let me start by exploring the files and reading them to find security vulnerabilities.
Now let me read the libraries and interfaces:
Let me also check the prior round summary and global audit memory for context:
Now I have a comprehensive understanding of the codebase and existing findings. Let me analyze the code for new security vulnerabilities. Based on my review, I'll now identify and report new, distinct security issues:
Based on my thorough review of the contracts and existing findings, I've identified additional security vulnerabilities that are distinct from the known findings F-001 through F-024.

[
  {
    "id": "F-025",
    "severity": "High",
    "confidence": "high",
    "title": "RefundInfo entry can be overwritten causing loss of refund claims",
    "locations": [
      "GatewayCrossChain.sol:561",
      "GatewayCrossChain.sol:585",
      "GatewayTransferNative.sol:642",
      "GatewayTransferNative.sol:664"
    ],
    "claim": "In onRevert and onAbort, refund entries are created without checking if a prior refund entry already exists with the same externalId. While there is a check for REFUND_INFO_ALREADY_EXISTS, this only checks within the same transaction flow. An attacker who can predict or manipulate the externalId generation could overwrite legitimate refund entries.",
    "impact": "Users waiting for refunds may have their refund records overwritten, causing permanent loss of their refund claims and funds.",
    "paths": [
      "Attacker monitors pending cross-chain transaction",
      "Attacker predicts or influences externalId generation",
      "Attacker initiates revert that creates same externalId refund record",
      "Original user refund entry is overwritten",
      "Original user loses refund claim"
    ]
  },
  {
    "id": "F-026",
    "severity": "Critical",
    "confidence": "medium",
    "title": "onCall does not validate fromToken and toToken are legitimate ZRC20 tokens",
    "locations": [
      "GatewaySend.sol:341",
      "GatewaySend.sol:345-366"
    ],
    "claim": "In GatewaySend.onCall, the fromToken and toToken are decoded directly from the message payload without validating these are legitimate ZRC20 token contracts. The code only checks if tokens equal ETH_ADDRESS sentinel, but does not verify that non-ETH tokens actually implement ERC20 interface.",
    "impact": "An attacker can pass arbitrary addresses as tokens. If these addresses are non-contracts or malicious contracts, the transfer calls will fail silently or execute unexpected behavior. More critically, the contract assumes any address passed is a valid ERC20 and will call transfer() on it, enabling potential interaction with malicious contracts.",
    "paths": [
      "Attacker calls cross-chain message to GatewaySend",
      "Attacker passes fake/malicious token address in message payload",
      "Contract decodes and uses attacker-controlled token address",
      "Potential reentrancy or malicious contract interaction"
    ]
  },
  {
    "id": "F-027",
    "severity": "High",
    "confidence": "high",
    "title": "Platform fees deducted before swap validation; swap failure causes permanent fee loss",
    "locations": [
      "GatewayTransferNative.sol:569-574",
      "GatewayCrossChain.sol:488-492"
    ],
    "claim": "In withdrawToNativeChain and onCall, platform fees are deducted from the input amount BEFORE the swap (_doMixSwap) is executed. If the swap fails due to invalid parameters, insufficient liquidity, or DoS, the fees are already deducted and not refunded.",
    "impact": "Users who provide invalid swap parameters lose their platform fees permanently even though no swap was executed. This creates a permanent fund loss vector for users.",
    "paths": [
      "User calls withdrawToNativeChain with swapDataZ",
      "Platform fees deducted before swap: amount -= platformFeesForTx",
      "Swap executes via _doMixSwap",
      "If swap fails (invalid params, no liquidity, etc), entire transaction reverts",
      "BUT platformFeesForTx was already transferred to EddyTreasurySafe before swap",
      "User loses fees without receiving swap output"
    ]
  },
  {
    "id": "F-028",
    "severity": "Medium",
    "confidence": "medium",
    "title": "No slippage protection on output amount in onCall cross-chain receive path",
    "locations": [
      "GatewaySend.sol:362-367"
    ],
    "claim": "In GatewaySend.onCall, when receiving cross-chain tokens and executing a swap (fromToken != toToken), the swap output amount is used directly without any slippage protection. The executed swap can return significantly less than expected due to price movement but the transaction still commits.",
    "impact": "Users receive less token output than expected due to slippage, with no protection or minimum output validation. Price manipulation or unfavorable market conditions can cause significant loss.",
    "paths": [
      "Cross-chain message received at onCall",
      "Swap executes via _doMixSwap",
      "Market moves against user between quote and execution",
      "Output amount significantly lower than expected",
      "Transaction commits with no slippage check"
    ]
  },
  {
    "id": "F-029",
    "severity": "Medium",
    "confidence": "high",
    "title": "decodeMessage allows empty swapDataZ but onCall path lacks empty-handling in some branches",
    "locations": [
      "SwapDataHelperLib.sol:56",
      "GatewayCrossChain.sol:492",
      "GatewayTransferNative.sol:414"
    ],
    "claim": "decodeMessage accepts empty swapDataZ (swapDataZLen=0) and returns MixSwapParams with zero/default values. However in onCall paths, the _doMixSwap is called even with empty swapData. While _doMixSwap has a length==0 check in some places, the flow is inconsistent and empty swap params can lead to unexpected behavior.",
    "impact": "Confusion in swap handling can lead to incorrect token routing or amount calculations. The inconsistent handling of empty swapData can cause funds to be sent to wrong tokens or addresses.",
    "paths": [
      "User provides empty swapDataZ in message",
      "mixSwapParams decoded with zero values",
      "Swap call executes without proper validation",
      "Unexpected token output or routing"
    ]
  },
  {
    "id": "F-030",
    "severity": "Medium",
    "confidence": "medium",
    "title": "ExternalId generation uses predictable components enabling collision attacks",
    "locations": [
      "GatewayTransferNative.sol:195-197"
    ],
    "claim": "_calcExternalId uses keccak256(address(this), sender, globalNonce, msg.sender, blockhash(block.number - 1)). While blockhash adds some entropy, using msg.sender and globalNonce which attacker can observe or partially influence creates predictability. An attacker who monitors pending transactions can predict and front-run refund entries.",
    "impact": "Attackers can predict externalIds and create conflicting refund entries, causing DoS on legitimate refund claims.",
    "paths": [
      "Attacker monitors pending transaction in mempool",
      "Attacker observes sender, calculates potential externalId",
      "Attacker creates revert with matching externalId",
      "Legitimate refund entry is blocked"
    ]
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
