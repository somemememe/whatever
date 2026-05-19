Below are findings from 2 agents auditing the same codebase,
plus accumulated findings from previous rounds.

You are the merge and review layer for a convergence-style audit loop.
You may inspect the source code in the current working directory to validate,
consolidate, or downgrade findings before returning the updated list.

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
    "title": "Destination-side payout token is fully user-controlled, enabling balance drain from GatewaySend",
    "locations": [
      "GatewaySend.sol:248",
      "GatewaySend.sol:297",
      "GatewaySend.sol:341",
      "GatewaySend.sol:358",
      "GatewaySend.sol:369"
    ],
    "claim": "GatewaySend forwards the user-supplied `payload` cross-chain without binding it to the actually bridged asset, then `onCall` trusts the decoded `fromToken`/`toToken`. An attacker can encode `fromToken == _ETH_ADDRESS_` to skip pulling the bridged asset from the gateway and force the contract to pay `toToken` or ETH from its own existing balances.",
    "impact": "Any tokens or ETH already held by the destination GatewaySend contract can be drained to an attacker-chosen recipient. The real bridged asset remains unpulled at the gateway while the contract self-funds the payout.",
    "paths": [
      "Call `GatewaySend.depositAndCall(..., payload)` with a payload whose packed destination data sets `fromToken = _ETH_ADDRESS_`, `toToken = victim token`, and `recipient = attacker`.",
      "On the destination chain, `GatewaySend.onCall` skips `transferFrom(msg.sender, ...)` because `fromIsETH` is true, sets `outputAmount = amount` when `fromToken == toToken` or performs a swap using contract-held funds, and finally transfers `toToken`/ETH to the attacker."
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Refund metadata truncates non-EVM recipients to 20 bytes, misdirecting failed native-chain withdrawals",
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
    "claim": "Both gateway contracts encode `revertMessage` for `withdraw()` as `bytes.concat(externalId, bytes20(sender))`, which truncates arbitrary-length recipient bytes to 20 bytes. `onRevert()` then treats any 52-byte revert message as an EVM address and transfers the refund to `address(uint160(bytes20(walletAddress)))`.",
    "impact": "If a Bitcoin or other non-20-byte withdrawal fails and the gateway reverts, the refund is sent to an unrelated EVM address derived from the first 20 bytes of the foreign recipient instead of being stored for later recovery. This can permanently misdirect user funds.",
    "paths": [
      "Initiate a withdrawal to a non-20-byte recipient via `withdraw()`.",
      "If the gateway reverts that withdrawal, `onRevert()` sees a 52-byte revert payload and immediately transfers the refund to the truncated 20-byte address."
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "GatewayTransferNative allows zero-deposit withdrawals when `zrc20` is spoofed as the ETH sentinel",
    "locations": [
      "GatewayTransferNative.sol:360",
      "GatewayTransferNative.sol:364",
      "GatewayTransferNative.sol:444",
      "GatewayTransferNative.sol:449",
      "GatewayTransferNative.sol:470",
      "GatewayTransferNative.sol:486",
      "GatewayTransferNative.sol:549",
      "GatewayTransferNative.sol:554"
    ],
    "claim": "In `withdrawToNativeChain`, passing `zrc20 == _ETH_ADDRESS_` skips any token transfer from the caller, yet the function still computes fees, skips swapping when `swapDataZ` is empty, and proceeds to approve and withdraw real `decoded.targetZRC20` from the contract's own balances.",
    "impact": "Any ZRC20 balances already present in GatewayTransferNative, including stuck funds, leftovers, or accidentally sent tokens, can be bridged out by an attacker without depositing equivalent value.",
    "paths": [
      "Call `withdrawToNativeChain(_ETH_ADDRESS_, amount, message)` with empty `swapDataZ` and a `message` targeting an attacker-controlled recipient on the destination chain.",
      "Because no deposit is enforced for the ETH sentinel path, the function uses `amount` as if it were funded and eventually calls `_handleBitcoinWithdraw` or `_handleEvmOrSolanaWithdraw`, which approve and withdraw the contract's own `decoded.targetZRC20` balance."
    ]
  }
]

```

### Agent: opencode_1
```
Now let me check the interfaces and mocks:
Based on my comprehensive analysis of all contracts in scope, here is the JSON array of security findings:
[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "Token Approvals Not Reset After Use Leading to Drain",
    "locations": [
      "GatewayCrossChain.sol:343",
      "GatewayCrossChain.sol:358-359",
      "GatewayTransferNative.sol:339",
      "GatewayTransferNative.sol:354-355"
    ],
    "claim": "IZRC20 approvals to UniswapRouter and Gateway are set but never reset to zero after use",
    "impact": "Approved tokens can be drained by anyone who obtains control of the contract (e.g., through future proxy upgrades or if the approval is exploited). Stale approvals remain active indefinitely.",
    "paths": [
      "1. User initiates cross-chain swap",
      "2. Contract approves tokens to UniswapRouter for swap (line 343)",
      "3. Contract approves tokens to gateway for withdrawal (lines 358-359)",
      "4. Approvals remain active after transaction completes",
      "5. Attacker exploits stale approvals to drain funds"
    ]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "medium",
    "title": "Incorrect Token Transfer in onCall - Transfers From Wrong Address",
    "locations": [
      "GatewaySend.sol:359"
    ],
    "claim": "In onCall function, IERC20(fromToken).transferFrom(msg.sender, address(this), amount) uses msg.sender (gateway) instead of the actual sender",
    "impact": "The function will fail for ERC20 tokens since the gateway address likely has no balance/allowance. Cross-chain receives will always fail for ERC20 tokens.",
    "paths": [
      "1. Gateway calls onCall with message containing token transfer instructions",
      "2. Function attempts transferFrom(msg.sender=Gateway, ...)",
      "3. Transaction fails as Gateway has no tokens"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Unauthorized Bot Can Claim Refunds",
    "locations": [
      "GatewayCrossChain.sol:612",
      "GatewayTransferNative.sol:689"
    ],
    "claim": "claimRefund allows any address marked as bot to claim refunds regardless of the actual refund receiver",
    "impact": "Owner can set any address as a bot, allowing unauthorized withdrawal of user refund funds",
    "paths": [
      "1. User initiates cross-chain swap that fails",
      "2. RefundInfo is stored with user's wallet address",
      "3. Owner adds attacker address as bot",
      "4. Attacker calls claimRefund and steals funds"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "medium",
    "title": "No Slippage Protection in depositAndCall",
    "locations": [
      "GatewaySend.sol:244-245"
    ],
    "claim": "The swap via DODORouteProxy.mixSwap has no minReturnAmount validation",
    "impact": "Users can suffer massive slippage losses as the transaction will succeed even if the swap returns very little due to adverse price movement",
    "paths": [
      "1. User calls depositAndCall with swapData",
      "2. mixSwap executes with minReturnAmount=0",
      "3. Uniswap price moves unfavorably during transaction",
      "4. User receives minimal output tokens with no protection"
    ]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "medium",
    "title": "ETH Transfer Uses Limited Gas (2300 gas)",
    "locations": [
      "GatewaySend.sol:370"
    ],
    "claim": "Direct .transfer() calls use only 2300 gas which is insufficient for most contract receivers",
    "impact": "ETH transfers to smart contract wallets will fail, causing user funds to be locked or revert",
    "paths": [
      "1. Cross-chain swap completes to an EVM contract address",
      "2. onCall attempts payable(evmWalletAddress).transfer(outputAmount)",
      "3. Transfer fails due to insufficient gas for receiver contract"
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "high",
    "title": "External Id Collision in GatewayTransferNative",
    "locations": [
      "GatewayTransferNative.sol:196"
    ],
    "claim": "_calcExternalId uses msg.sender which can be manipulated by callers to create identical externalIds",
    "impact": "Users could potentially cause externalId collisions affecting refund tracking and processing",
    "paths": [
      "1. User A calls withdrawToNativeChain",
      "2. externalId = keccak256(address(this), sender, globalNonce, msg.sender, blockhash(block.number-1))",
      "3. User A could front-run by sending from different address to create collision"
    ]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Potential Integer Underflow in _swapAndSendERC20Tokens",
    "locations": [
      "GatewayCrossChain.sol:356",
      "GatewayTransferNative.sol:352"
    ],
    "claim": "targetAmount - amounts[0] can underflow if swap returns more than targetAmount",
    "impact": "Transaction reverts due to underflow panic, blocking user withdrawals",
    "paths": [
      "1. Swap returns more tokens than expected (amounts[0] > targetAmount)",
      "2. targetAmount - amounts[0] underflows",
      "3. Transaction reverts"
    ]
  },
  {
    "id": "F-008",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Missing Zero Address Validation in Setters",
    "locations": [
      "GatewaySend.sol:86-88",
      "GatewaySend.sol:91-94"
    ],
    "claim": "setDODORouteProxy and setGateway lack zero address validation",
    "impact": "Owner can accidentally set zero address, breaking all functionality",
    "paths": [
      "1. Owner calls setDODORouteProxy(address(0))",
      "2. All subsequent swaps will fail"
    ]
  },
  {
    "id": "F-009",
    "severity": "Medium",
    "confidence": "low",
    "title": "Missing Access Control on withdraw Function",
    "locations": [
      "GatewayTransferNative.sol:305-322"
    ],
    "claim": "withdraw function is public with no access control",
    "impact": "Anyone can trigger withdrawals which may interfere with contract accounting",
    "paths": [
      "1. Any external caller calls withdraw()",
      "2. Withdrawal is executed through gateway"
    ]
  },
  {
    "id": "F-010",
    "severity": "Low",
    "confidence": "high",
    "title": "Refund Claim Allows Empty ExternalId",
    "locations": [
      "GatewayCrossChain.sol:605"
    ],
    "claim": "claimRefund only checks externalId matches but not if externalId is non-zero",
    "impact": "Could allow claiming refunds with zero bytes32 externalId if accidentally stored",
    "paths": [
      "1. RefundInfo.externalId accidentally set to bytes32(0)",
      "2. User calls claimRefund(bytes32(0))",
      "3. Check passes and empty refund claimed"
    ]
  },
  {
    "id": "F-011",
    "severity": "Low",
    "confidence": "medium",
    "title": "Unsafe External Call to Arbitrary Contract",
    "locations": [
      "GatewayTransferNative.sol:418"
    ],
    "claim": "IWETH9(WZETA).withdraw(outputAmount) calls an external contract address that could be malicious",
    "impact": "If WZETA address is compromised or malicious, funds could be stolen",
    "paths": [
      "1. Attacker gains control of WZETA contract at 0x5F0b1a82749cb4E2278EC87F8BF6B618dC71a8bf",
      "2. Calls to withdraw() steal user funds"
    ]
  },
  {
    "id": "F-012",
    "severity": "Informational",
    "confidence": "low",
    "title": "Unsafe Use of blockhash in External Id Generation",
    "locations": [
      "GatewayTransferNative.sol:196"
    ],
    "claim": "blockhash(block.number - 1) can be manipulated by miners",
    "impact": "External IDs could be predicted to some extent by miners",
    "paths": [
      "1. Miner constructs transaction with controlled blockhash",
      "2. Predictable external ID generated"
    ]
  }
]

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
