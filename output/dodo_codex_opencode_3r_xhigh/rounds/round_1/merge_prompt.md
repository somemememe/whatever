Below are findings from 2 agents auditing the same codebase,
plus accumulated findings from previous rounds.

You are the merge layer for a audit loop. You can inspect the source code when needed.

Your task is to read all findings from this round, merge them into the 
summary of distinct issues, compare that round summary against accumulated findings,
and keep new or materially improved findings in the updated list. And you are encouraged to find more based on these findings and source code.

If an issue already exists in accumulated findings, do not add a duplicate. 
Remove findings that are not defensible after checking the code.
Downgrade severity or confidence when the issue depends on unusual configuration or weak
assumptions. 
Treat each finding carefully.

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
    "title": "Unbound swap and settlement tokens let callers redeem unrelated balances already held by the gateways",
    "locations": [
      "GatewayCrossChain.sol:492",
      "GatewayCrossChain.sol:497",
      "GatewayCrossChain.sol:517",
      "GatewayTransferNative.sol:414",
      "GatewayTransferNative.sol:422",
      "GatewayTransferNative.sol:574",
      "GatewaySend.sol:245",
      "GatewaySend.sol:257",
      "GatewaySend.sol:266"
    ],
    "claim": "The contracts never bind the token produced by the current bridge/swap step to the token they later transfer, withdraw, or deposit. `outputAmount` is treated as a raw number and then applied to user-controlled `targetZRC20`/`asset`, so empty or mismatched swap data can spend balances that were already sitting in the contract rather than the token just bridged in.",
    "impact": "Any refundable balance, accidental transfer, dust, or stranded token/ETH already resident in these contracts can be stolen. An attacker only needs to supply a different input token and point settlement at a valuable token that the contract already holds.",
    "paths": [
      "GatewayTransferNative.onCall -> decodeNativeMessage(targetZRC20=victimToken, swapData='') -> _doMixSwap returns input amount -> safeTransfer(victimToken, attacker, outputAmount)",
      "GatewayCrossChain.onCall -> decodeMessage(targetZRC20=victimToken, swapDataZ='') -> withdraw/withdrawAndCall(victimToken, outputAmount)",
      "GatewaySend.depositAndCall -> _doMixSwap(swapData for some other token) -> _handleERC20Deposit(..., asset=victimToken, outputAmount)"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "GatewaySend cannot refund reverted native-ETH transfers",
    "locations": [
      "GatewaySend.sol:299",
      "GatewaySend.sol:303",
      "GatewaySend.sol:393",
      "GatewaySend.sol:396"
    ],
    "claim": "When a gas-token transfer reverts, Zeta's EVM gateway sends native ETH back to this contract and reports `asset == address(0)`, but `GatewaySend.onRevert` always treats `context.asset` as an ERC20 and calls `TransferHelper.safeTransfer(context.asset, sender, context.amount)`.",
    "impact": "Any reverted ETH bridge/call path cannot complete its refund. The revert callback itself reverts, so the user's native funds are not returned through the intended path and can become stuck upstream.",
    "paths": [
      "GatewaySend.depositAndCall(asset=ETH or swapped-to-ETH) -> destination failure -> GatewayEVM.executeRevert(msg.value, asset=0) -> GatewaySend.onRevert -> safeTransfer(address(0), sender, amount) reverts"
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "high",
    "title": "Dusting an undeployed pair address can permanently force a nonexistent Uniswap route",
    "locations": [
      "GatewayCrossChain.sol:234",
      "GatewayCrossChain.sol:253",
      "GatewayTransferNative.sol:235",
      "GatewayTransferNative.sol:254",
      "libraries/UniswapV2Library.sol:42"
    ],
    "claim": "Pair existence is inferred only from token balances at the deterministic CREATE2 pair address. Anyone can pre-send dust to that address before the pair is deployed, making `_existsPairPool` return true and forcing `getPathForTokens` onto a direct pair that has no code/reserves.",
    "impact": "Withdrawals that should have fallen back through `WZETA` can be DoSed for chosen token pairs. The attack is cheap, permissionless, and persists until the contract is upgraded or an actual pair is deployed at that address.",
    "paths": [
      "Attacker transfers dust of tokenA and tokenB to uniswapv2PairFor(factory, tokenA, tokenB) while no pair exists -> _existsPairPool returns true -> _swapAndSendERC20Tokens -> UniswapV2Library.getAmountsIn -> getReserves on nonexistent pair reverts"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "high",
    "title": "Solana account decompression builds an invalid in-memory `Account[]` and corrupts outbound payloads",
    "locations": [
      "libraries/AccountEncoder.sol:19",
      "libraries/AccountEncoder.sol:48",
      "GatewayCrossChain.sol:425",
      "GatewayCrossChain.sol:455",
      "GatewayTransferNative.sol:505",
      "GatewayTransferNative.sol:535"
    ],
    "claim": "`AccountEncoder.decompressAccounts` writes pointers into the array body instead of laying out `Account` structs inline. `abi.encode(Input(accounts, data))` therefore serializes memory addresses as public keys and corrupts `isWritable` flags.",
    "impact": "Solana `withdrawAndCall` messages are malformed. Calls can fail, abort into refund flow, or target unintended accounts, effectively breaking Solana routes.",
    "paths": [
      "decoded.dstChainId == SOLANA_EDDY -> AccountEncoder.decompressAccounts(decoded.accounts) -> AccountEncoder.encodeInput(...) -> malformed payload passed to withdrawAndCall"
    ]
  },
  {
    "id": "F-005",
    "severity": "Low",
    "confidence": "medium",
    "title": "GatewayTransferNative refund claims remain reentrant until after the external token transfer",
    "locations": [
      "GatewayTransferNative.sol:680",
      "GatewayTransferNative.sol:691",
      "GatewayTransferNative.sol:692"
    ],
    "claim": "`claimRefund` transfers `refundInfo.token` before deleting `refundInfos[externalId]`. A malicious or non-standard refundable token can call back into `claimRefund` while the same refund record is still live.",
    "impact": "If a malicious asset ever becomes refundable, the same refund can be claimed multiple times and drain other balances held by the contract.",
    "paths": [
      "onRevert/onAbort stores refundInfo for a malicious token -> claimRefund -> token.transfer reenters claimRefund(externalId) before `delete refundInfos[externalId]`"
    ]
  }
]

```

### Agent: opencode_1
```
[
  {
    "id": "F-001",
    "severity": "Medium",
    "confidence": "high",
    "title": "Missing zero address validation in setDODOApprove",
    "locations": [
      "GatewayCrossChain.sol:148",
      "GatewayTransferNative.sol:149"
    ],
    "claim": "The setDODOApprove function does not validate against zero address, while setDODORouteProxy properly validates with require(_dodoRouteProxy != address(0)). This inconsistency allows the owner to accidentally set DODOApprove to zero address.",
    "impact": "If DODOApprove is set to zero address, all subsequent swaps through DODO Router will fail, effectively breaking the protocol's swap functionality. The typo in GatewayTransferNative.sol line 149 shows 'setDODOApprove' (camelCase) instead of 'setDODOApprove' expected.",
    "paths": []
  },
  {
    "id": "F-002",
    "severity": "Medium",
    "confidence": "high",
    "title": "Unsafe ERC20 approval pattern without resetting allowance",
    "locations": [
      "GatewayCrossChain.sol:343",
      "GatewayCrossChain.sol:358-359",
      "GatewayTransferNative.sol:339",
      "GatewayTransferNative.sol:354-355"
    ],
    "claim": "The contract uses approve() without first setting allowance to 0, which violates the safe approval pattern (EIP-712). This can cause approval failures with tokens like USDT that require resetting allowance before increasing.",
    "impact": "Swaps will fail for certain tokens (USDT, BNB, etc.) that require setting allowance to 0 before increasing. This can cause cross-chain transactions to get stuck.",
    "paths": []
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "high",
    "title": "Incorrect slippage validation uses wrong amount in _swapAndSendERC20Tokens",
    "locations": [
      "GatewayCrossChain.sol:356",
      "GatewayTransferNative.sol:352"
    ],
    "claim": "The slippage check uses wrong amount in validation: 'targetAmount - amounts[0] > 0' (GatewayTransferNative) vs 'targetAmount - amounts[0] > 0' (GatewayCrossChain). amounts[0] is input amount, should check amounts[1] (output) or actual received vs expected.",
    "impact": "The validation incorrectly reverts valid transactions or passes invalid ones based on input vs output amount mismatch.",
    "paths": []
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "medium",
    "title": "Missing zero address validation in setBot function",
    "locations": [
      "GatewayCrossChain.sol:184",
      "GatewayTransferNative.sol:181"
    ],
    "claim": "The setBot function allows setting bot address to zero (address(0)), which could accidentally disable the bot if set with isAllowed=false for address(0).",
    "impact": "A user could accidentally disable a valid bot by calling setBot(address(0), false). While not a direct exploit, can cause operational issues.",
    "paths": []
  },
  {
    "id": "F-005",
    "severity": "Informational",
    "confidence": "high",
    "title": "Inconsistent event emission for non-swap token transfer",
    "locations": [
      "GatewaySend.sol:329-338"
    ],
    "claim": "In the second depositAndCall overload (no swap scenario), the event emits 'asset' as both fromToken and toToken, but amount is unchanged, misrepresenting the event as a swap when it's a direct transfer.",
    "impact": "Event logs show misleading data - no actual swap occurs but fields suggest it did. Minor data inconsistency in logs.",
    "paths": []
  },
  {
    "id": "F-006",
    "severity": "Low",
    "confidence": "medium",
    "title": "Potential hash collision in externalId calculation",
    "locations": [
      "GatewaySend.sol:160-162",
      "GatewayTransferNative.sol:195-197"
    ],
    "claim": "_calcExternalId uses block.timestamp in the hash. If globalNonce is not incremented in all paths, two transactions in the same block could have hash collisions.",
    "impact": "Low probability - globalNonce is incremented before in some paths but the hash includes timestamp as additional input, reducing collision risk but not eliminating it.",
    "paths": []
  },
  {
    "id": "F-007",
    "severity": "Low",
    "confidence": "high",
    "title": "Missing deadline validation in depositAndCall",
    "locations": [
      "GatewaySend.sol:218-285"
    ],
    "claim": "The depositAndCall function passes deadline to _doMixSwap but doesn't validate block.timestamp against the deadline before executing.",
    "impact": "Transactions can be executed long after submission with outdated prices, causing unexpected execution prices.",
    "paths": []
  },
  {
    "id": "F-008",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Missing reentrancy guard on external functions",
    "locations": [
      "GatewayCrossChain.sol:469-537",
      "GatewayCrossChain.sol:544-577",
      "GatewaySend.sol:341-386",
      "GatewayTransferNative.sol:376-442"
    ],
    "claim": "External functions like onCall, onRevert perform external calls (IERC20 transfer) without reentrancy modifier or checks-effects-interactions pattern.",
    "impact": "While the contract deletes refund info before transfer in claimRefund (good), other paths may be vulnerable to reentrancy if malicious tokens call back.",
    "paths": []
  },
  {
    "id": "F-009",
    "severity": "Low",
    "confidence": "high",
    "title": "Inconsistent feePercent limit validation",
    "locations": [
      "GatewayCrossChain.sol:121",
      "GatewayCrossChain.sol:155"
    ],
    "claim": "feePercent validation exists in initialize() as

```

## Output
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
`source_agents` must include every agent that materially supports the final finding.

Output ONLY valid JSON. No markdown. No prose.
