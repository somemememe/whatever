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
    "title": "GatewayTransferNative onCall charges fee but still swaps gross amount, enabling reserve-subsidized payouts",
    "locations": [
      "GatewayTransferNative.sol:389",
      "GatewayTransferNative.sol:414"
    ],
    "claim": "In `onCall`, platform fees are transferred out first, but the swap path still uses the original `amount` instead of `amount - platformFeesForTx`; cross-asset routes can therefore consume contract reserves to top up the missing input.",
    "impact": "Attackers can bypass intended fee economics and repeatedly force reserve consumption (or fail user flows when reserves are low), leading to protocol insolvency/DoS on payout paths.",
    "paths": [
      "Call `onCall` with `decoded.targetZRC20 != zrc20` and swap params that use the full bridged amount as input",
      "Fee is sent to treasury, reducing available balance",
      "Swap still attempts gross amount and pulls the shortfall from existing contract reserves"
    ]
  },
  {
    "id": "F-026",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Refund entries keyed by zero externalId become permanently unclaimable",
    "locations": [
      "GatewayTransferNative.sol:628",
      "GatewayTransferNative.sol:661",
      "GatewayTransferNative.sol:683"
    ],
    "claim": "`claimRefund` rejects entries where `refundInfo.externalId == 0`, but `onRevert`/`onAbort` can store refunds under key `0x0` when revert messages carry a zero externalId.",
    "impact": "Affected refunds cannot be claimed by users/bots, causing permanent lockup of refundable assets in the contract.",
    "paths": [
      "Produce a revert/abort callback whose first 32 bytes (externalId) are zero",
      "`onRevert`/`onAbort` stores `refundInfos[0x0]`",
      "`claimRefund(0x0)` always reverts on `refundInfo.externalId != \"\"`"
    ]
  },
  {
    "id": "F-027",
    "severity": "Low",
    "confidence": "high",
    "title": "Refund-claimed event logs zero token/amount due to emit-after-delete on storage pointer",
    "locations": [
      "GatewayTransferNative.sol:692",
      "GatewayTransferNative.sol:694",
      "GatewayTransferNative.sol:696",
      "GatewayTransferNative.sol:697"
    ],
    "claim": "`claimRefund` deletes `refundInfos[externalId]` before emitting and then reads `refundInfo.token`/`refundInfo.amount` from the deleted storage slot, emitting zeroed values.",
    "impact": "Off-chain accounting/monitoring can record incorrect claim amounts and token addresses, degrading operational security and incident response.",
    "paths": [
      "Any successful `claimRefund` call",
      "State is deleted before event fields are read",
      "Event emits zero token and zero amount instead of actual payout data"
    ]
  },
  {
    "id": "F-028",
    "severity": "Low",
    "confidence": "low",
    "title": "GatewayTransferNative revert callbacks can hard-revert on short revertMessage",
    "locations": [
      "GatewayTransferNative.sol:628",
      "GatewayTransferNative.sol:661"
    ],
    "claim": "`onRevert` and `onAbort` slice `revertMessage[0:32]` without validating length, so malformed callback payloads can panic and revert callback handling.",
    "impact": "Malformed callback payloads can block refund recording/processing and may strand funds in failure handling flows.",
    "paths": [
      "Gateway invokes `onRevert` or `onAbort` with `revertMessage.length < 32`",
      "Slice operation reverts before refund transfer/storage logic executes"
    ]
  }
]

```

### Agent: opencode_1
```
I'll read the contract files in scope and audit them for security vulnerabilities.
My task is to provide a JSON listing all newly discovered vulnerabilities.
F-025 highlights a critical flaw in SwapDataHelperLib's decodeCompressedMixSwapParams function: unchecked calldata bounds. This enables out-of-bounds reads, causing potential reverts or the extraction of stale data.

F-026 identifies another issue in the same function: potential integer underflow with offset calculations if the calldata structure is maliciously constructed, leading to memory corruption.

F-027 flags a cross-contract vulnerability in GatewaySend's onCall function: the missing reentrancy guard allows for reentrant calls during token transfers, which enables an attacker to potentially drain the contract's assets.
Here are the newly identified findings in JSON format:

```json
[
  {
    "id": "F-025",
    "severity": "High",
    "confidence": "medium",
    "title": "SwapDataHelperLib decodeCompressedMixSwapParams lacks calldata bounds checks",
    "locations": [
      "libraries/SwapDataHelperLib.sol:144"
    ],
    "claim": "decodeCompressedMixSwapParams reads multiple length-prefixed variable-length regions from calldata without validating that the total encoded length fits within the provided calldata.",
    "impact": "Malformed or truncated calldata causes out-of-bounds library calldata reads, leading to unexpected reverts or extraction of unintended memory region data as parsed parameter values.",
    "paths": [
      "Caller encodes compressed swap params with incorrect length prefixes → decodeCompressedMixSwapParams attempts to read beyond calldata bounds → reverts or reads stale memory"
    ]
  },
  {
    "id": "F-026",
    "severity": "Medium",
    "confidence": "low",
    "title": "SwapDataHelperLib decodeCompressedMixSwapParams offset arithmetic can underflow",
    "locations": [
      "libraries/SwapDataHelperLib.sol:144"
    ],
    "claim": "The offset variable in decodeCompressedMixSwapParams only increments and wraps in assembly; if calldata contains crafted lengths, arithmetic can proceed past valid bounds without explicit check.",
    "impact": "Corrupted parsed parameters can flow downstream to external calls (DODORouteProxy.mixSwap), potentially causing unexpected token movement or approval manipulation.",
    "paths": [
      "Calldata contains length fields pointing backward → offset wraps or becomes misaligned → parsing produces invalid address/amount values passed to mixSwap"
    ]
  },
  {
    "id": "F-027",
    "severity": "Medium",
    "confidence": "medium",
    "title": "GatewaySend onCall lacks reentrancy protection on token transfers",
    "locations": [
      "GatewaySend.sol:341"
    ],
    "claim": "onCall performs external token transfers (IERC20.transfer, transferFrom) and ETH .call without a reentrancy guard, allowing a malicious contract receiver to callback into onCall before state updates finalize.",
    "impact": "A malicious token callback can trigger onCall again (as the gateway) during the execution window, potentially manipulating state-dependent logic or draining assets in the same transaction.",
    "paths": [
      "Gateway calls onCall with malicious recipient → recipient is a contract with a hook → hook calls back into onCall as gateway (using onRevert or another path) before onCall completes state updates"
    ]
  },
  {
    "id": "F-028",
    "severity": "High",
    "confidence": "medium",
    "title": "GatewaySend onCall does not validate outputAmount >= amount for swap paths",
    "locations": [
      "GatewaySend.sol:362"
    ],
    "claim": "When fromToken != toToken, the code performs _doMixSwap but does not validate that outputAmount >= amount (or a minimum threshold), trusting the swap output directly.",
    "impact": "If the DODO swap path returns less than input (or zero) due to pool exhaustion or manipulation, the contract transfers_less to the recipient while the full amount is accounted as processed. Combined with fee treatment, this can result in losses for users.",
    "paths": [
      "User initiates cross-chain swap → swap pool is manipulated/drained → outputAmount

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
