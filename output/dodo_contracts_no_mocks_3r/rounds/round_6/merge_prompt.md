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
    "title": "Refund records can be overwritten in callback handlers",
    "locations": [
      "GatewayTransferNative.sol:642",
      "GatewayTransferNative.sol:648",
      "GatewayTransferNative.sol:664",
      "GatewayTransferNative.sol:670",
      "GatewayCrossChain.sol:561",
      "GatewayCrossChain.sol:585"
    ],
    "claim": "`GatewayTransferNative` `onRevert`/`onAbort` overwrite `refundInfos[externalId]` without existence checks. `GatewayCrossChain` adds a collision check, but it is bypassable for key `externalId == 0x0` because the sentinel condition relies on `refundInfos[externalId].externalId == 0`.",
    "impact": "Duplicate/colliding callbacks can replace earlier refund metadata, causing refund loss, misdirection, or permanent unclaimability for the original claimant.",
    "paths": [
      "First callback stores refund info for `externalId = X`.",
      "Second callback with same `X` stores different wallet/token/amount and overwrites prior data (`GatewayTransferNative`).",
      "For `GatewayCrossChain`, use `externalId = 0x0` to bypass duplicate guard and replace prior zero-key refund metadata."
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
  }
]

## This Round's Agent Outputs
### Agent: codex_1
```
[
  {
    "id": "F-023",
    "severity": "High",
    "confidence": "medium",
    "title": "Refund-slot collision on `externalId` can block later revert/abort refunds",
    "locations": [
      "GatewayCrossChain.sol:476",
      "GatewayCrossChain.sol:561",
      "GatewayCrossChain.sol:585"
    ],
    "claim": "`externalId` is taken from message data and used as a global refund key, while `onRevert`/`onAbort` hard-revert if that key is already populated.",
    "impact": "An attacker can pre-poison a victim `externalId`, causing later refund callback handling for that `externalId` to revert and potentially leaving reverted funds unclaimable.",
    "paths": [
      "Attacker routes a crafted message with chosen `externalId` and non-52-byte revert payload path so `refundInfos[externalId]` is created first.",
      "Victim transfer later reverts/aborts with same `externalId`.",
      "`onRevert`/`onAbort` hits `REFUND_INFO_ALREADY_EXISTS` and aborts refund recording."
    ]
  },
  {
    "id": "F-024",
    "severity": "High",
    "confidence": "medium",
    "title": "Swap return value is trusted without balance-delta validation",
    "locations": [
      "GatewaySend.sol:202",
      "GatewaySend.sol:245",
      "GatewaySend.sol:266",
      "GatewayCrossChain.sol:374",
      "GatewayCrossChain.sol:492",
      "GatewayTransferNative.sol:454",
      "GatewayTransferNative.sol:414"
    ],
    "claim": "All gateway flows treat `mixSwap`'s returned amount as authoritative output and immediately deposit/withdraw/transfer based on it, without checking actual token balance increase.",
    "impact": "If swap execution under-delivers while returning a larger amount, the difference can be paid from contract reserves, enabling reserve drain via repeated calls.",
    "paths": [
      "GatewaySend: `_doMixSwap` -> `outputAmount` -> `_handleERC20Deposit`/`_handleETHDeposit`.",
      "GatewayCrossChain: `_doMixSwap` -> `outputAmount` -> `_handleBitcoinWithdraw`/`_handleEvmOrSolanaWithdraw`.",
      "GatewayTransferNative: `_doMixSwap` -> `outputAmount` -> direct payout or gateway withdraw paths."
    ]
  },
  {
    "id": "F-025",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Exact-output Uniswap flow can leave residual allowance and DoS strict-approve tokens",
    "locations": [
      "GatewayCrossChain.sol:343",
      "GatewayCrossChain.sol:347",
      "GatewayTransferNative.sol:339",
      "GatewayTransferNative.sol:343"
    ],
    "claim": "Contracts approve `amountInMax` then execute `swapTokensForExactTokens`, which typically spends less (`amounts[0]`), leaving non-zero router allowance; next non-zero approve is attempted without zero-reset.",
    "impact": "For tokens requiring allowance reset to zero before a new non-zero approve, subsequent swaps/withdrawals hard-revert (token-specific permanent DoS).",
    "paths": [
      "First swap spends `< amountInMax`, leaving allowance residue.",
      "Later call performs `approve(UniswapRouter, newAmountInMax)` from non-zero state.",
      "Strict token reverts approve, blocking that route."
    ]
  },
  {
    "id": "F-026",
    "severity": "Low",
    "confidence": "high",
    "title": "ETH `depositAndCall` overload ignores `amount` and bridges full `msg.value`",
    "locations": [
      "GatewaySend.sol:308",
      "GatewaySend.sol:311"
    ],
    "claim": "The ETH overload only checks `msg.value >= amount` but deposits `msg.value` (not `amount`) to gateway.",
    "impact": "Callers/integrators can unintentionally bridge more ETH than intended, creating direct user fund loss and accounting mismatches.",
    "paths": [
      "Call `depositAndCall(target, amount, ETH, ...)` with `msg.value > amount`.",
      "Contract forwards full `msg.value` cross-chain while emitting event fields keyed to `amount`."
    ]
  },
  {
    "id": "F-027",
    "severity": "Low",
    "confidence": "low",
    "title": "Missing revert-message length guards can revert callback handlers",
    "locations": [
      "GatewaySend.sol:394",
      "GatewayTransferNative.sol:628",
      "GatewayTransferNative.sol:661"
    ],
    "claim": "Callback handlers slice fixed ranges (`[0:32]`, `[32:]`) without checking minimum `revertMessage` length.",
    "impact": "Malformed callbacks can panic and fail refund processing paths, potentially stranding funds in failed cross-chain operations.",
    "paths": [
      "Gateway invokes callback with short `revertMessage`.",
      "Slice operation reverts before refund logic runs."
    ]
  },
  {
    "id": "F-028",
    "severity": "Informational",
    "confidence": "high",
    "title": "`claimRefund` emits cleared values after deleting storage",
    "locations": [
      "GatewayTransferNative.sol:692",
      "GatewayTransferNative.sol:694",
      "GatewayTransferNative.sol:696",
      "GatewayTransferNative.sol:697"
    ],
    "claim": "`refundInfo` is a storage pointer; after `delete refundInfos[externalId]`, emitted `refundInfo.token` and `refundInfo.amount` are zeroed.",
    "impact": "Refund event telemetry is incorrect, degrading monitoring, reconciliation, and incident response quality.",
    "paths": [
      "`claimRefund` transfers funds, deletes storage entry, then emits using the deleted storage pointer."
    ]
  },
  {
    "id": "F-029",
    "severity": "Low",
    "confidence": "low",
    "title": "Refund entry at `externalId == 0x0` is unclaimable",
    "locations": [
      "GatewayTransferNative.sol:664",
      "GatewayTransferNative.sol:683"
    ],
    "claim": "Handlers can store `refundInfos[0x0]`, but `claimRefund` rejects when `refundInfo.externalId == \"\"`.",
    "impact": "Any refund recorded under zero externalId becomes permanently stuck in contract state.",
    "paths": [
      "`onRevert`/`onAbort` stores record where parsed externalId is zero.",
      "`claimRefund(0x0)` always reverts with `REFUND_NOT_EXIST`."
    ]
  }
]

```

### Agent: opencode_1
```
Let me read all the contract files to find security vulnerabilities.
Based on my analysis, I'll now compile the JSON output with new distinct security vulnerabilities. Let me verify a few more edge cases to ensure these are distinct from known findings.
Based on my analysis of the contracts, I found several potential new security vulnerabilities. Let me compile the JSON output:
[
  {
    "id": "F-023",
    "severity": "Medium",
    "confidence": "high",
    "title": "GatewaySend.onCall returns incorrect success value causing callback failure",
    "locations": ["GatewaySend.sol:385"],
    "claim": "The onCall function returns an empty bytes memory (return \"\") which is not the required bytes4 success selector (0x00000000). The ZetaChain gateway expects a valid bytes4 return value for successful execution.",
    "impact": "When the gateway processes a successful onCall execution, it may interpret the incorrect return value as a failure, potentially triggering unnecessary revert handling or preventing proper callback completion.",
    "paths": ["User initiates cross-chain transfer -> gateway calls onCall -> onCall returns wrong value -> gateway misinterprets success as failure"]
  },
  {
    "id": "F-024",
    "severity": "Medium",
    "confidence": "medium",
    "title": "GatewaySend.onCall does not validate fromToken transfer quantity",
    "locations": ["GatewaySend.sol:358-360"],
    "claim": "The onCall function transfers fromToken from msg.sender using a fixed amount value without validating that the actual transferred amount matches the expected amount. If the token transfer returns true but transfers less (or more), no validation occurs.",
    "impact": "Mismatched token amounts could lead to incorrect accounting in subsequent swap or payout operations, potentially causing user fund loss or protocol insolvency.",
    "paths": ["Malicious/buggy ERC20 returns true but transfers less -> swap uses wrong amount -> user receives incorrect amount"]
  },
  {
    "id": "F-025",
    "severity": "Medium",
    "confidence": "high",
    "title": "GatewaySend.depositAndCall does not use swapData for output token calculation",
    "locations": ["GatewaySend.sol:218-285"],
    "claim": "In the first depositAndCall function overload (lines 218-285), swapData is passed to _doMixSwap to get outputAmount, but the deposit is always made with outputAmount regardless of whether the swap succeeded or whether the output token matches the destination asset parameter.",
    "impact": "Users may pay for a swap but receive the original token if the swap fails silently or returns 0, leading to fund loss or unexpected token transfers to destination.",
    "paths": ["User calls depositAndCall with swapData -> swap fails/returns 0 -> deposit uses outputAmount (0 or original) -> funds sent incorrectly"]
  },
  {
    "id": "F-026",
    "severity": "Medium",
    "confidence": "medium",
    "title": "GatewaySend._doMixSwap missing validation for fromToken amount",
    "locations": ["GatewaySend.sol:195-216"],
    "claim": "The _doMixSwap function uses params.fromTokenAmount from the compressed swap params without validating that this matches the amount actually transferred to the contract or received from the gateway.",
    "impact": "User-specified fromTokenAmount in swap params could differ from actual token amounts, allowing manipulation of swap calculations and potentially draining protocol funds.",
    "paths": ["User provides mismatched fromTokenAmount in swapData -> swap calculates with wrong amount -> output amount is incorrect"]
  },
  {
    "id": "F-027",
    "severity": "Low",
    "confidence": "medium",
    "title": "GatewaySend depositAndCall lacks slippage protection for swap output",
    "locations": ["GatewaySend.sol:244-245"],
    "claim": "The swap is executed using _doMixSwap without any minimum return amount validation. If the DODO router returns less than expected due to slippage or manipulation, the full outputAmount is used for deposit without check.",
    "impact": "Users could receive significantly less than expected on the destination chain due to unfavorable swap execution, with no on-chain protection.",
    "paths": ["Market moves -> router returns less than expected -> user receives less on destination -> no recourse"]
  },
  {
    "id": "F-028",
    "severity": "Medium",
    "confidence": "medium",
    "title": "GatewayTransferNative.onCall fee calculation uses input amount not output amount",
    "locations": ["GatewayTransferNative.sol:389"],
    "claim": "The platform fee is calculated on the input amount (zrc20 amount) before the swap occurs, not on the actual output amount after the swap. If the swap results in loss, the fee is still taken from the larger input amount.",
    "impact": "Users effectively pay more fee when swaps underperform, creating a worse user experience. Additionally, if swap results in 0 output, fee is still taken on input, potentially leaving user with nothing.",
    "paths": ["User initiates cross-chain swap -> fee calculated on input -> swap underperforms -> user loses fee on failed swap"]
  },
  {
    "id": "F-029",
    "severity": "Low",
    "confidence": "medium",
    "title": "GatewayTransferNative._swapAndSendERC20Tokens approval uses amountInMax not actual swapped amount",
    "locations": ["GatewayTransferNative.sol:339,355,359"],
    "claim": "The function approves targetZRC20 for amountInMax (slippage-adjusted) to the Uniswap router, and later approves targetZRC20 for targetAmount - amounts[0]. If the swap uses less than amountInMax but more than amounts[0], there could be unnecessary allowance granted.",
    "impact": "Unnecessary token approvals could lead to larger allowance exposure if the contract is compromised, though the amounts are bounded by swap parameters.",
    "paths": ["Swap executes with less input than max -> approvals remain higher than actual usage"]
  },
  {
    "id": "F-030",
    "severity": "Low",
    "confidence": "low",
    "title": "GatewayTransferNative withdraw function is public not internal",
    "locations": ["GatewayTransferNative.sol:305-323"],
    "claim": "The withdraw function is declared as public rather than internal, allowing any external caller to trigger withdrawals from the gateway.",
    "impact": "While the function requires valid parameters and the gateway likely validates, unnecessary external call surface could be exploited if gateway validation has edge cases.",
    "paths": ["External caller invokes withdraw -> gateway processes withdrawal with caller-provided parameters"]
  },
  {
    "id": "F-031",
    "severity": "High",
    "confidence": "medium",
    "title": "GatewayTransferNative.withdrawToNativeChain allows arbitrary recipient addresses without validation",
    "locations": ["GatewayTransferNative.sol:549-619"],
    "claim": "The withdrawToNativeChain function processes swapData and withdraw parameters without validating that decoded.receiver is a valid address format for the destination chain. The receiver is passed directly to withdrawAndCall or withdraw.",
    "impact": "Invalid receiver addresses could cause withdrawals to fail at the protocol level, permanently losing user funds, or route to unpredictable addresses.",
    "paths": ["User provides invalid receiver bytes -> withdrawal executes -> funds lost or stuck on destination chain"]
  },
  {
    "id": "F-032",
    "severity": "Medium",
    "confidence": "medium",
    "title": "GatewayCrossChain._swapAndSendERC20Tokens calculates amountInMax with slippage on quote not actual",
    "locations": ["GatewayCrossChain.sol:342-346"],
    "claim": "The amountInMax is calculated using the quoted amount plus slippage percentage: amountsQuote[0] + (slippage * amountsQuote[0]) / 1000. This is applied to the quote from getAmountsIn, not the actual amounts after swap.",
    "impact": "If the actual swap requires more than the quoted amount (due to path changes or timing), the swap could fail. If it succeeds with less, excess approval remains.",
    "paths": ["Quote differs from actual -> swap may fail or leave excess approvals"]
  },
  {
    "id": "F-033",
    "severity": "Medium",
    "confidence": "medium",
    "title": "GatewayCrossChain onCall does not validate message length before decoding",
    "locations": ["GatewayCrossChain.sol:476-477"],
    "claim": "The onCall function directly decodes message[0:32] as externalId without validating that message has sufficient length. If message is shorter than 32 bytes, the decode could read garbage or revert unexpectedly.",
    "impact": "Gateway calls with malformed messages could cause unpredictable contract behavior, potentially leading to reverts or incorrect processing.",
    "paths": ["Gateway calls with short message -> decode reads out of bounds or garbage -> undefined behavior"]
  },
  {
    "id": "F-034",
    "severity": "Medium",
    "confidence": "low",
    "title": "GatewayCrossChain claimRefund allows anyone to claim if walletAddress is 20 bytes and caller is bot",
    "locations": ["GatewayCrossChain.sol:602-629"],
    "claim": "The claimRefund function allows claiming if msg.sender is in bots mapping OR if msg.sender equals the derived receiver address. But it does not verify that the original walletAddress was meant for the caller.",
    "impact": "A bot operator could claim refunds for any 20-byte walletAddress recipients if they are registered as bots, potentially misappropriating refunds.",
    "paths": ["Owner registers bot -> bot claims any refund where walletAddress is 20 bytes -> funds stolen"]
  },
  {
    "id": "F-035",
    "severity": "Low",
    "confidence": "low",
    "title": "SwapDataHelperLib.decodeCompressedMixSwapParams has unchecked arithmetic in offset calculations",
    "locations": ["SwapDataHelperLib.sol:162-270"],
    "claim": "The function uses unchecked {} block for offset calculations. While bounds checking on data.length exists, malformed input could cause offset to wrap or read beyond calldata boundaries.",
    "impact": "If malicious data is passed, the decoding could read from unintended memory locations, potentially causing memory corruption or incorrect parameter parsing.",
    "paths": ["Attacker passes crafted swapData -> offset wraps or goes out of bounds -> memory corruption or incorrect parsing"]
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
