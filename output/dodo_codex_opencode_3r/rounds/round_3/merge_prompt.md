Below are findings from 2 agents auditing the same codebase,
plus accumulated findings from previous rounds.

You are the merge and review layer for a convergence-style audit loop.
You may inspect the source code in the current working directory to validate,
consolidate, or downgrade findings before returning the updated list.

## Accumulated Findings
[
  {
    "id": "C-001",
    "severity": "High",
    "confidence": "high",
    "title": "Cross-chain handlers trust unbound token and swap metadata, enabling withdrawals of unrelated contract-held assets",
    "locations": [
      "GatewaySend.sol:248",
      "GatewaySend.sol:297",
      "GatewaySend.sol:341",
      "GatewaySend.sol:358",
      "GatewaySend.sol:363",
      "GatewaySend.sol:366",
      "GatewaySend.sol:369",
      "GatewaySend.sol:372",
      "GatewayCrossChain.sol:364",
      "GatewayCrossChain.sol:469",
      "GatewayCrossChain.sol:480",
      "GatewayCrossChain.sol:492",
      "GatewayCrossChain.sol:496",
      "GatewayCrossChain.sol:517",
      "GatewayTransferNative.sol:376",
      "GatewayTransferNative.sol:386",
      "GatewayTransferNative.sol:414",
      "GatewayTransferNative.sol:422",
      "GatewayTransferNative.sol:444",
      "GatewayTransferNative.sol:449",
      "GatewayTransferNative.sol:549",
      "GatewayTransferNative.sol:554",
      "GatewayTransferNative.sol:562",
      "GatewayTransferNative.sol:574",
      "libraries/SwapDataHelperLib.sol:56",
      "libraries/SwapDataHelperLib.sol:97",
      "libraries/SwapDataHelperLib.sol:108",
      "libraries/SwapDataHelperLib.sol:112",
      "libraries/SwapDataHelperLib.sol:133",
      "libraries/SwapDataHelperLib.sol:140",
      "libraries/SwapDataHelperLib.sol:144"
    ],
    "claim": "`GatewaySend`, `GatewayCrossChain`, and `GatewayTransferNative` all decode destination-side token metadata and DODO swap parameters directly from user-controlled messages without binding them to the asset and amount actually delivered for that call. `GatewaySend.onCall` trusts user-supplied `amount`, `fromToken`, `toToken`, and `swapData`; the Zeta-side contracts trust decoded `targetZRC20` and `MixSwapParams` without enforcing that `params.fromToken` equals the received `zrc20`, that `params.fromTokenAmount` matches the funded amount, or that the asset produced by `_doMixSwap` matches the later transferred/withdrawn token. Because the empty-swap path simply returns the caller-controlled `amount`, and because sentinel/forged metadata can skip the only input pull, an attacker can make the contracts transfer or withdraw unrelated balances they already hold.",
    "impact": "Any ERC20, ZRC20, WZETA/native, or other residual inventory held by these gateway contracts can be exfiltrated. Attackers can bridge or message in one asset but receive a different contract-held asset, or even withdraw without funding the flow first, causing direct theft of stranded or pooled balances.",
    "paths": [
      "Call either `GatewaySend.depositAndCall(...)` entrypoint with a payload that encodes attacker-chosen `amount`, recipient, `fromToken = _ETH_ADDRESS_`, `toToken = victim asset`, and empty `swapData`; when `GatewaySend.onCall` executes, it skips the gateway pull, treats the forged `amount` as real output, and transfers the victim asset or ETH from its own balance.",
      "Trigger `GatewayCrossChain.onCall` with a message whose decoded `targetZRC20` points to a token already held by the contract and whose `swapDataZ` is empty or forged; `_doMixSwap` returns the nominal amount unchanged, after which `_handleBitcoinWithdraw` or `_handleEvmOrSolanaWithdraw` approves and withdraws/transfers `targetZRC20` from existing balances.",
      "Call `GatewayTransferNative.withdrawToNativeChain(_ETH_ADDRESS_, amount, message)` or reach `GatewayTransferNative.onCall` with forged `targetZRC20`/swap metadata; because the ETH-sentinel path skips `transferFrom` and empty swap data returns `amount`, the contract proceeds to transfer or withdraw attacker-selected assets from its own holdings."
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Refund metadata truncates non-EVM recipients to 20 bytes and misdirects failed native withdrawals",
    "locations": [
      "GatewayCrossChain.sol:304",
      "GatewayCrossChain.sol:318",
      "GatewayCrossChain.sol:544",
      "GatewayCrossChain.sol:550",
      "GatewayTransferNative.sol:305",
      "GatewayTransferNative.sol:319",
      "GatewayTransferNative.sol:626",
      "GatewayTransferNative.sol:631"
    ],
    "claim": "Both gateway contracts encode the revert recipient for `withdraw()` as `bytes.concat(externalId, bytes20(sender))`. If `sender` is a Bitcoin, Solana, or other non-20-byte address, it is silently truncated to 20 bytes. Later, `onRevert()` interprets every 52-byte revert payload as an EVM address and immediately transfers the refund to `address(uint160(bytes20(walletAddress)))` instead of preserving the original foreign-chain recipient bytes for later recovery.",
    "impact": "When a native-chain withdrawal for a non-EVM recipient reverts, the refund can be sent to an unrelated EVM address derived from the first 20 bytes of that foreign address. Users can permanently lose funds through misdirected refunds.",
    "paths": [
      "Initiate a `withdraw()` flow whose `sender` or recipient bytes are longer than 20 bytes, such as a Bitcoin or Solana address.",
      "If the gateway reverts the withdrawal, the revert message is still only 52 bytes long because `bytes20(sender)` was stored.",
      "The contract treats that revert as an EVM refund and transfers the assets to the truncated 20-byte address instead of recording a claimable refund for the real non-EVM recipient."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "high",
    "title": "GatewayTransferNative refund claims are reentrant and can be claimed multiple times before state deletion",
    "locations": [
      "GatewayTransferNative.sol:680",
      "GatewayTransferNative.sol:691",
      "GatewayTransferNative.sol:692"
    ],
    "claim": "`GatewayTransferNative.claimRefund` performs the external token transfer before deleting `refundInfos[externalId]`. If the refund token is a malicious ERC20/ZRC20, its `transfer` logic can reenter `claimRefund` while the refund entry still exists and pull the same refund repeatedly.",
    "impact": "A claimant controlling the refund receiver and token contract can drain the contract's balance of the refunded asset far beyond the intended single refund amount.",
    "paths": [
      "A revert or abort stores a refund entry in `refundInfos`.",
      "The attacker calls `claimRefund` for a refund whose token executes arbitrary code during `transfer`.",
      "The token reenters `claimRefund` before `delete refundInfos[externalId]` runs, allowing repeated transfers against the same refund record."
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Fee-on-transfer tokens are over-credited, letting callers spend prior balances held by the contracts",
    "locations": [
      "GatewaySend.sol:239",
      "GatewaySend.sol:245",
      "GatewaySend.sol:317",
      "GatewaySend.sol:320",
      "GatewayTransferNative.sol:555",
      "GatewayTransferNative.sol:570",
      "GatewayTransferNative.sol:574"
    ],
    "claim": "The direct deposit entrypoints assume `transferFrom(..., amount)` delivers exactly `amount`, then immediately swap, fee, or bridge using the nominal input instead of the actual balance delta. With fee-on-transfer or deflationary tokens, the shortfall is silently sourced from whatever balance of that token the contract already holds.",
    "impact": "A user can underpay while consuming prior users' or protocol-owned token balances. Depending on the token inventory already present, this can produce value extraction, inconsistent accounting, or denial of service when the contract later runs short.",
    "paths": [
      "Call `GatewaySend.depositAndCall(fromToken, amount, ...)` with a fee-on-transfer ERC20 so the contract receives less than `amount` but still swaps or deposits using the full nominal value.",
      "Call `GatewaySend.depositAndCall(targetContract, amount, asset, ...)` with a fee-on-transfer ERC20 so the gateway deposit is funded partly from pre-existing contract balance.",
      "Call `GatewayTransferNative.withdrawToNativeChain(zrc20, amount, ...)` with a fee-on-transfer ZRC20 so platform fee handling and downstream withdrawal logic spend more than was actually received."
    ],
    "round": 2,
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
    "id": "F-001",
    "severity": "High",
    "confidence": "high",
    "title": "GatewaySend cannot receive authenticated gateway calls because `onCall` returns the wrong ABI type",
    "locations": [
      "GatewaySend.sol:341"
    ],
    "claim": "`GatewaySend.onCall` is declared `returns (bytes4)`, but Zeta's authenticated call path invokes destination contracts through `Callable.onCall(... ) returns (bytes memory)`. The ABI decoder on the gateway side expects dynamic-bytes returndata and will revert when `GatewaySend` returns a fixed-size `bytes4` payload instead.",
    "impact": "Any authenticated cross-chain delivery into `GatewaySend` can fail at the gateway boundary, preventing destination-side settlement and forcing the flow into revert/abort handling instead of completing normally.",
    "paths": [
      "GatewayCrossChain/GatewayTransferNative -> GatewayZEVM.withdrawAndCall -> GatewayEVM authenticated call -> GatewaySend.onCall -> ABI decode failure -> delivery reverts"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "ETH revert refunds on GatewaySend are handled as ERC20 transfers and can never be paid out",
    "locations": [
      "GatewaySend.sol:249",
      "GatewaySend.sol:304",
      "GatewaySend.sol:393",
      "GatewaySend.sol:396"
    ],
    "claim": "Source-side ETH flows configure `callOnRevert = true`, but `GatewaySend.onRevert` always refunds via `TransferHelper.safeTransfer(context.asset, sender, context.amount)`. For gas-token reverts, Zeta passes `asset == address(0)` and the refund value as native ETH, so the handler attempts an ERC20 call to the zero address instead of forwarding ETH.",
    "impact": "Reverted ETH bridge operations cannot be refunded through `onRevert`. The revert callback itself fails, leaving ETH refunds stuck until the contract is upgraded or manually recovered through some out-of-band process.",
    "paths": [
      "GatewaySend.depositAndCall(...ETH...) -> remote failure -> GatewayEVM.executeRevert with native ETH + `asset == address(0)` -> GatewaySend.onRevert -> zero-address ERC20 transfer revert"
    ]
  }
]

```

### Agent: opencode_1
```
[]

```

## Tasks

### Task 1: Deduplicate
Identify findings from this round that are NOT duplicates of accumulated findings.
Two items are duplicates only if they are the same reportable issue, even if worded differently.

### Task 2: Synthesize
Look across ALL findings (new + accumulated). Are there findings that
combine into a higher-value composite vulnerability?
If yes, create a new composite finding.

If multiple findings share a similar underlying cause but expose different
mechanisms, affected flows, or exploit paths, do NOT simply drop one of them.
Instead, consolidate them into one richer finding by preserving all relevant
locations and paths.

If you create a new composite finding that fully subsumes existing component findings,
remove the fully subsumed component findings from the final list. Keep child findings
only when they still stand as independently reportable issues after consolidation.

### Task 3: Review
Review the merged findings for practical quality:
- recalibrate severity and confidence when the issue is strongly configuration-dependent,
  requires uncommon preconditions, or is better characterized as liveness/griefing than theft
- remove findings that are no longer defensible after consolidation and review
- do NOT perform external benchmark matching or duplicate filtering against any external corpus;
  work only from the code and the provided findings

### Task 4: Output
Return the COMPLETE updated findings list as a JSON array.

Each element must have:
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
Use a composite `C-XXX` ID only for a genuine merged/composite finding.

Output ONLY valid JSON. No markdown. No prose.
