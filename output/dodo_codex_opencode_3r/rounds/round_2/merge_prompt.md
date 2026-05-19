Below are findings from 2 agents auditing the same codebase,
plus accumulated findings from previous rounds.

You are the merge and review layer for a convergence-style audit loop.
You may inspect the source code in the current working directory to validate,
consolidate, or downgrade findings before returning the updated list.

## Accumulated Findings
[
  {
    "id": "F-001",
    "severity": "High",
    "confidence": "high",
    "title": "GatewaySend trusts fully user-supplied destination token metadata and can pay out arbitrary contract-held assets",
    "locations": [
      "GatewaySend.sol:248",
      "GatewaySend.sol:297",
      "GatewaySend.sol:341",
      "GatewaySend.sol:354",
      "GatewaySend.sol:359",
      "GatewaySend.sol:366",
      "GatewaySend.sol:369",
      "GatewaySend.sol:372"
    ],
    "claim": "Both `depositAndCall` entrypoints forward a user-controlled `payload` to the destination without binding it to the actual bridged asset or amount. On the destination, `onCall` decodes `amount`, `fromToken`, `toToken`, and `swapData` directly from that payload and trusts them. An attacker can encode `fromToken = _ETH_ADDRESS_` to skip the gateway pull entirely, use empty `swapData` so `_doMixSwap` returns the forged `amount`, and force the contract to transfer any `toToken` or ETH it already holds to an attacker-chosen recipient.",
    "impact": "Any ERC20 or ETH balance already sitting in the destination `GatewaySend` contract can be drained. The payout is funded from the contract's own balances rather than the asset actually bridged for this message.",
    "paths": [
      "Call either `GatewaySend.depositAndCall(...)` variant with a payload that encodes an attacker recipient, a chosen `amount`, `fromToken = _ETH_ADDRESS_`, `toToken = victim asset`, and empty `swapData`.",
      "When the destination `GatewaySend.onCall` executes, it skips `transferFrom` because `fromIsETH` is true, `_doMixSwap` returns the attacker-controlled `amount` because `swapData.length == 0`, and the contract transfers `toToken` or ETH from its own balance to the attacker."
    ],
    "round": 1,
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
      "Initiate a `withdraw()` flow whose `sender`/recipient bytes are longer than 20 bytes, such as a Bitcoin or Solana address.",
      "If the gateway reverts the withdrawal, the revert message is still only 52 bytes long because `bytes20(sender)` was stored.",
      "The contract treats that revert as an EVM refund and transfers the assets to the truncated 20-byte address instead of recording a claimable refund for the real non-EVM recipient."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "GatewayTransferNative accepts the ETH sentinel as a funded input and can withdraw contract-held ZRC20 without any deposit",
    "locations": [
      "GatewayTransferNative.sol:360",
      "GatewayTransferNative.sol:444",
      "GatewayTransferNative.sol:449",
      "GatewayTransferNative.sol:549",
      "GatewayTransferNative.sol:554",
      "GatewayTransferNative.sol:570",
      "GatewayTransferNative.sol:574"
    ],
    "claim": "In `withdrawToNativeChain`, supplying `zrc20 == _ETH_ADDRESS_` skips the only deposit step. The function still proceeds as if `amount` were funded: `_handleFeeTransfer` performs a no-op call against the sentinel address, empty `swapDataZ` makes `_doMixSwap` return `amount`, and the function then approves and withdraws `decoded.targetZRC20` from the contract's own existing balances.",
    "impact": "Attackers can bridge out ZRC20 already held by `GatewayTransferNative` without depositing equivalent value first. Any stranded balances, accidental transfers, or residual funds in the contract are exposed.",
    "paths": [
      "Call `withdrawToNativeChain(_ETH_ADDRESS_, amount, message)` with a message whose `swapDataZ` is empty and whose `decoded.targetZRC20` points to a token balance already held by the contract.",
      "Because the sentinel path skips `transferFrom`, no input asset is collected from the caller.",
      "The function treats the unfunded `amount` as real output and reaches `_handleBitcoinWithdraw` or `_handleEvmOrSolanaWithdraw`, which approve the gateway to pull `decoded.targetZRC20` from the contract and withdraw it to the attacker-controlled destination."
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
    "id": "F-004",
    "severity": "High",
    "confidence": "high",
    "title": "Zeta-side swap metadata is unconstrained and can spend or pay out unrelated contract-held assets",
    "locations": [
      "GatewayCrossChain.sol:364",
      "GatewayCrossChain.sol:469",
      "GatewayTransferNative.sol:376",
      "GatewayTransferNative.sol:444",
      "GatewayTransferNative.sol:549",
      "libraries/SwapDataHelperLib.sol:112",
      "libraries/SwapDataHelperLib.sol:144"
    ],
    "claim": "Both Zeta-side gateway contracts fully trust user-controlled `swapData`/`swapDataZ` and decoded `targetZRC20` values without checking that `params.fromToken` matches the asset just received or that `params.toToken` matches the asset later withdrawn/transferred. Because `_doMixSwap` simply approves `params.fromToken` and the empty-swap case returns `amount` unchanged, an attacker can route the operation through arbitrary tokens already held by the contract or skip the swap entirely and still receive `decoded.targetZRC20`/native value from pre-existing balances.",
    "impact": "Any residual inventory held by `GatewayCrossChain` or `GatewayTransferNative` can be exfiltrated. A malicious caller can convert an inbound deposit of one token into a withdrawal/transfer of another token the contract already holds, including gas tokens or WZETA/native balances, causing direct theft of pooled funds.",
    "paths": [
      "GatewayTransferNative.withdrawToNativeChain -> decodeMessage -> _doMixSwap(empty or forged params) -> _handleBitcoinWithdraw/_handleEvmOrSolanaWithdraw",
      "GatewayCrossChain.onCall -> decodeMessage -> _doMixSwap(empty or forged params) -> withdraw/withdrawAndCall",
      "GatewayTransferNative.onCall -> decodeNativeMessage -> _doMixSwap(empty or forged params) -> safeTransfer/safeTransferETH"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "high",
    "title": "GatewayTransferNative refund claims are reentrant and can be claimed multiple times before state deletion",
    "locations": [
      "GatewayTransferNative.sol:680"
    ],
    "claim": "`GatewayTransferNative.claimRefund` performs the external token transfer before deleting `refundInfos[externalId]`. If the refund token is a malicious ERC20/ZRC20, its `transfer` logic can reenter `claimRefund` while the refund entry still exists and pull the same refund repeatedly.",
    "impact": "A claimant controlling the refund receiver and token contract can drain the contract's balance of the refunded asset far beyond the intended single refund amount.",
    "paths": [
      "onRevert/onAbort stores refund -> attacker calls claimRefund -> malicious token transfer reenters claimRefund before delete -> repeated transfers"
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Fee-on-transfer tokens are over-credited, letting callers spend prior balances held by the contracts",
    "locations": [
      "GatewaySend.sol:237",
      "GatewaySend.sol:245",
      "GatewaySend.sol:316",
      "GatewaySend.sol:320",
      "GatewayTransferNative.sol:554",
      "GatewayTransferNative.sol:569",
      "GatewayTransferNative.sol:574"
    ],
    "claim": "The direct deposit entrypoints assume `transferFrom(..., amount)` delivers exactly `amount`, then immediately swap, fee, or bridge using the nominal input instead of the actual balance delta. With fee-on-transfer or deflationary tokens, the shortfall is silently sourced from whatever balance of that token the contract already holds.",
    "impact": "A user can underpay while consuming prior users' or protocol-owned token balances. Depending on the token inventory already present, this can produce value extraction, inconsistent accounting, or denial of service when the contract later runs short.",
    "paths": [
      "GatewaySend.depositAndCall(fromToken, amount, ...) with a fee-on-transfer ERC20",
      "GatewaySend.depositAndCall(targetContract, amount, asset, ...) with a fee-on-transfer ERC20",
      "GatewayTransferNative.withdrawToNativeChain(zrc20, amount, ...) with a fee-on-transfer ZRC20"
    ]
  },
  {
    "id": "F-007",
    "severity": "Low",
    "confidence": "low",
    "title": "GatewayTransferNative allows gateway-assisted withdrawals through a public helper",
    "locations": [
      "GatewayTransferNative.sol:305"
    ],
    "claim": "`GatewayTransferNative.withdraw` is publicly callable even though it makes the contract itself invoke `gateway.withdraw(...)`. If the gateway retains any allowance from previous operations or consumes less than the pre-approved amount, any external caller can reuse this helper to withdraw contract-held ZRC20 to an arbitrary `sender` payload.",
    "impact": "Under leftover-allowance conditions, an attacker can drain approved balances without going through the intended swap flow. Even if the current gateway implementation usually spends the full allowance, this remains a brittle trust assumption around an externally callable asset-moving primitive.",
    "paths": [
      "normal flow leaves nonzero allowance from GatewayTransferNative to gateway -> attacker calls public withdraw(externalId, attackerReceiver, token, amount)"
    ]
  }
]

```

### Agent: opencode_1
```
After analyzing the contract codebase, I've identified several security vulnerabilities beyond the known findings. Let me compile the new findings:

(Note: I need to verify a few more patterns in the code to ensure accuracy of my findings)
Based on my comprehensive security analysis of the contracts in scope, I've identified new security vulnerabilities:
[
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "high",
    "title": "Unchecked externalId collision in refund claim allows attacker to drain refunds",
    "locations": [
      "GatewayCrossChain.sol:602-629",
      "GatewayTransferNative.sol:680-700"
    ],
    "claim": "The refund claim check uses `refundInfo.externalId == externalId` which can be bypassed with trivial collisions since externalId is predictable from on-chain data (nonce, timestamp, contract address)",
    "impact": "Attacker can predict externalId for refunds (derived from nonce/timestamp in GatewaySend.sol:161 and nonce in GatewayTransferNative.sol:196), front-run legitimate refund claims to drain pending refunds meant for other users",
    "paths": [
      "1. User initiates cross-chain swap that may fail and create refundInfo (onRevert/onAbort)",
      "2. Attacker monitors mempool for onRevert events, calculates predicted externalId",
      "3. Attacker front-runs the legitimate user's claimRefund call using the same externalId",
      "4. Attacker claims the refund to themselves since bot allowance or receiver check passes"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "high",
    "title": "Slippage protection ineffective - approves more tokens than necessary for swap",
    "locations": [
      "GatewayCrossChain.sol:338-356",
      "GatewayTransferNative.sol:325-358"
    ],
    "claim": "The code calculates amountInMax = amountsQuote[0] + (slippage * amountsQuote[0]) / 1000 but then approves amountInMax to the router without verifying the actual swap output meets minimum threshold after the swap executes",
    "impact": "User may receive significantly less output than expected due to price movement during swap execution, despite slippage protection being in place. The approve is set to more than necessary but the return amount is not checked",
    "paths": [
      "1. User calls withdrawToNativeChain with a destination requiring token swap",
      "2. Pre-swap quote calculates amountInMax with slippage buffer",
      "3. During swap execution, price moves unfavorably",
      "4. User receives less than expected with no actual slippage check on output"
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Missing zero-address validation in superWithdraw enables accidental loss of funds",
    "locations": [
      "GatewayCrossChain.sol:188-196"
    ],
    "claim": "The superWithdraw function does not validate that _EddyTreasurySafe (the destination address) is not address(0), and does not check if the token address is valid ERC20 before attempting transfer",
    "impact": "If EddyTreasurySafe is accidentally set to address(0) or an invalid address via setEddyTreasurySafe, calls to superWithdraw will permanently lose all funds with no recovery mechanism",
    "paths": [
      "1. Owner calls setEddyTreasurySafe with wrong address (typo or fat-finger)",
      "2. Owner later calls superWithdraw to drain contract",
      "3. All funds sent to address(0) or invalid address are permanently lost"
    ]
  },
  {
    "id": "F-007",
    "severity": "Low",
    "confidence": "high",
    "title": "External call with msg.value forwarded but no compensation mechanism",
    "locations": [
      "GatewaySend.sol:195-216"
    ],
    "claim": "The _doMixSwap function includes {value: msg.value} to forward surplus ETH to the DODO route proxy, but there is no accounting of excess ETH balance after the operation completes",
    "impact": "Any surplus ETH sent by the user in msg.value beyond what's needed for the swap may remain in the contract indefinitely or be trapped",
    "paths": [
      "1. User sends msg.value larger than needed for swap + gas",
      "2. Excess ETH remains in contract after swap completes",
      "3. Funds trapped in contract with no withdrawal mechanism"
    ]
  },
  {
    "id": "F-008",
    "severity": "Low",
    "confidence": "medium",
    "title": "No deadline enforcement in onCall message processing allows stale swaps",
    "locations": [
      "GatewaySend.sol:341-386"
    ],
    "claim": "The onCall function that receives cross-chain messages has no deadline parameter and uses block.timestamp (or no timestamp check), allowing stale swap data to execute much later than intended",
    "impact": "If a swap message is delayed in relay or stuck in mempool, it may execute hours/days later with drastically different market conditions causing unexpected output amounts",
    "paths": [
      "1. User initiates cross-chain swap with message encoded",
      "2. Message gets delayed in transit (bridge congestion, attack)",
      "3. Message executes with stale swap params when market prices have moved",
      "4. User receives significantly less or more than expected"
    ]
  },
  {
    "id": "F-009",
    "severity": "Low",
    "confidence": "low",
    "title": "Protocol fee calculation vulnerable to rounding down at small amounts",
    "locations": [
      "GatewayCrossChain.sol:324-327",
      "GatewayTransferNative.sol:360-366"
    ],
    "claim": "Platform fee calculation (amount * feePercent) / 1000 uses integer division which rounds down, potentially allowing transactions with small amounts to pay zero fees",
    "impact": "Users transacting amounts less than 1000/feePercent (e.g., less than 200 if feePercent = 5) pay effectively 0% fee instead of the intended fee percentage",
    "paths": [
      "1. User performs small value cross

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
