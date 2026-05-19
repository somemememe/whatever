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
None yet.

## This Round's Agent Outputs
### Agent: codex_1
```
[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "L1StandardBridge can be reinitialized at any time to swap in an attacker-controlled messenger",
    "locations": [
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/L1/L1StandardBridge.sol:81",
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/L1/L1StandardBridge.sol:90",
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/StandardBridge.sol:47",
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/StandardBridge.sol:109"
    ],
    "claim": "`initialize()` is guarded by `reinitializer(2)`, but the preceding `clearLegacySlot` modifier unconditionally executes `sstore(0, 0)`, which resets OpenZeppelin `Initializable` state on every call because `_initialized` and `_initializing` live in slot 0. Any account can therefore call `initialize()` repeatedly after deployment and overwrite the trusted `messenger` address.",
    "impact": "Once `messenger` is replaced, the attacker can satisfy `onlyOtherBridge` with a fake messenger that returns `OTHER_BRIDGE` from `xDomainMessageSender()`, then invoke `finalizeETHWithdrawal` / `finalizeERC20Withdrawal` to release arbitrary escrowed ETH and ERC20s to themselves. This is a direct bridge takeover and fund-drain.",
    "paths": [
      "Call `L1StandardBridge.initialize(attackerMessenger)` after deployment; `clearLegacySlot` zeroes slot 0 before the reinitializer check and the bridge stores the attacker-controlled messenger.",
      "Make `attackerMessenger.xDomainMessageSender()` return `address(OTHER_BRIDGE)` and call `finalizeETHWithdrawal(...)` or `finalizeERC20Withdrawal(...)` with attacker-chosen recipients and amounts.",
      "Because `onlyOtherBridge` only checks `msg.sender == address(messenger)` and `messenger.xDomainMessageSender() == address(OTHER_BRIDGE)`, the forged messenger is sufficient to drain escrow."
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "ERC20 deposits are overcredited for fee-on-transfer / deflationary tokens",
    "locations": [
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/StandardBridge.sol:347",
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/StandardBridge.sol:348",
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/StandardBridge.sol:280",
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/StandardBridge.sol:281"
    ],
    "claim": "For non-mintable tokens, the bridge records `deposits[_localToken][_remoteToken] += _amount` immediately after `safeTransferFrom`, but never measures how many tokens were actually received. Tokens with transfer fees, burns, or other deflationary mechanics can deliver less than `_amount` while the bridge still mints or accounts for the full `_amount` on the remote side.",
    "impact": "The bridge becomes undercollateralized for that token pair. Remote-side bridged supply can exceed the real escrow held locally, and later withdrawals will revert when `finalizeBridgeERC20` tries to transfer more tokens than the bridge actually owns. Users end up holding unredeemable bridge tokens and the pair becomes insolvent.",
    "paths": [
      "Deposit a fee-on-transfer token with nominal amount `N`; the bridge receives only `N - fee` but records `deposits += N` and sends a cross-chain message for `N`.",
      "The remote bridge finalizes the deposit for the full `N`, creating `N` units of withdrawable bridged supply backed by less than `N` real tokens.",
      "When withdrawals return to the original chain, `finalizeBridgeERC20` attempts to transfer `N` out of escrow and fails once the shortfall is hit, permanently locking withdrawals for that pair."
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "high",
    "title": "Bridge escrow can be broken by rebasing, confiscation, or blocklist-style ERC20 behavior after deposit",
    "locations": [
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/StandardBridge.sol:42",
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/StandardBridge.sol:280",
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/StandardBridge.sol:281",
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/L1/L1StandardBridge.sol:16"
    ],
    "claim": "Escrow accounting is purely nominal: `deposits` tracks the historical deposited amount, but `finalizeBridgeERC20` assumes the bridge can always transfer that amount later. If a token can reduce balances after transfer (negative rebases, confiscations) or selectively block transfers from/to the bridge, the recorded deposit stays unchanged while the real redeemable balance disappears.",
    "impact": "Previously bridged assets can become permanently unwithdrawable even though the bridge still reports deposits for the pair. This creates protocol-level lockups and selective withdrawal denial for any permissionlessly bridged token with mutable balance or transfer-permission semantics.",
    "paths": [
      "Users bridge a rebasing or admin-controlled token; the bridge records the nominal deposited amount in `deposits`.",
      "After escrow is established, the token negatively rebases the bridge, confiscates its balance, or blocklists bridge-related transfers.",
      "A later withdrawal hits `finalizeBridgeERC20`, which decrements the deposit record and then fails on `safeTransfer`, leaving the message unfinalizable and the remote-side asset effectively stranded."
    ]
  }
]

```

### Agent: opencode_1
```
Now I'll compile my findings based on the comprehensive code review.

```json
[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "Integer Underflow in finalizeBridgeERC20 Allows Permanent DoS of Withdrawals",
    "locations": [
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/StandardBridge.sol:280"
    ],
    "claim": "In finalizeBridgeERC20, the code subtracts the withdrawal amount from deposits mapping without checking if sufficient deposits exist, causing underflow and blocking all future withdrawals for that token pair.",
    "impact": "If a withdrawal is triggered with amount exceeding the deposited amount (due to malicious L2 messages or bugs), all subsequent withdrawals for that token pair will permanently fail. Funds become locked indefinitely.",
    "paths": [
      "Attacker crafts malicious L2->L1 message with large withdrawal amount > deposits",
      "First withdrawal triggers underflow, marking all future withdrawals as permanently blocked",
      "All legitimate users unable to withdraw their funds"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "medium",
    "title": "ETH Can Be Permanently Locked in finalizeBridgeETH Due to Failed Transfer",
    "locations": [
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/StandardBridge.sol:247"
    ],
    "claim": "finalizeBridgeETH transfers ETH to recipient via SafeCall.call() without checking return value properly, and if the recipient is a contract without receive() or if call fails, ETH becomes permanently locked.",
    "impact": "ETH sent to contracts that don't implement receive() or that revert on receipt becomes permanently locked in the bridge. Users lose access to their funds permanently.",
    "paths": [
      "User initiates withdrawal to a contract address without receive() function",
      "SafeCall.call() succeeds but ETH transfer fails silently or contract reverts",
      "ETH becomes locked in the bridge with no recovery mechanism"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "No Validation That Deposits Sufficiently Cover Withdrawal in finalizeBridgeERC20",
    "locations": [
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/StandardBridge.sol:280-281"
    ],
    "claim": "The finalizeBridgeERC20 function attempts to deduct the withdrawal amount from deposits without first verifying that deposits are sufficient, allowing underflow to occur.",
    "impact": "Any discrepancy between L1 and L2 state (due to bugs, reorgs, or malicious L2 messages) can cause the entire bridge to halt for that token pair, blocking all future legitimate withdrawals.",
    "paths": [
      "L2 state divergence causes mismatch between L1 deposits and L2 burn events",
      "Withdrawal attempt triggers underflow",
      "Bridge becomes inoperable for that token pair"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "high",
    "title": "initialize() Function Lacks Access Control Allowing Potential Front-Running",
    "locations": [
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/L1/L1StandardBridge.sol:90"
    ],
    "claim": "The L1StandardBridge.initialize() function can be called by any external address until initialized, as only the reinitializer modifier provides protection after first initialization.",
    "impact": "If initialization is not completed atomically in the same transaction as deployment, a front-running attacker could initialize with their own CrossDomainMessenger address, potentially redirecting bridge messages.",
    "paths": [
      "Deployer submits initialization transaction",
      "Attacker front-runs with same initialization using different messenger",
      "Bridge initialized with attacker-controlled messenger"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Gas Estimation in CrossDomainMessenger May Cause Message Relay Failures",
    "locations": [
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/libraries/SafeCall.sol:60-73",
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/CrossDomainMessenger.sol:263-280"
    ],
    "claim": "The hasMinGas function in SafeCall has documented 'FOOTGUN ALERT' limitations - users can specify insufficient gas leading to failed message relay. Failed messages can be replayed but cause user experience issues and potential fund delays.",
    "impact": "Users specifying incorrect _minGasLimit may experience failed message relay. While failed messages can be replayed, this causes delays and potential confusion. In extreme cases, if the target contract changes, replay may also fail.",
    "paths": [
      "User specifies _minGasLimit that doesn't account for memory expansion and code execution costs",
      "Message relay fails due to insufficient gas",
      "Message marked as failed, requires manual replay"
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "low",
    "title": "Token Blocklist Not Supported - May Trap User Funds",
    "locations": [
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/L1/L1StandardBridge.sol:17-18"
    ],
    "claim": "The contract documentation explicitly states tokens with blocklists are not properly supported, yet the bridge accepts any ERC20 without validation.",
    "impact": "Users bridging tokens with blocklists (e.g., USDC) may find their funds permanently inaccessible if they become blocked. The bridge doesn't check or warn about this limitation.",
    "paths": [
      "User bridges a token with blocklist functionality (e.g., USDC)",
      "User address becomes blocked by token issuer",
      "User cannot withdraw blocked tokens from L2 back to L1"
    ]
  },
  {
    "id": "F-007",
    "severity": "Low",
    "confidence": "medium",
    "title": "OptimismMintableERC20 Allows Zero Address for Bridge and Remote Token",
    "locations": [
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/OptimismMintableERC20.sol:43-54"
    ],
    "claim": "The OptimismMintableERC20 constructor accepts address(0) for bridge and remoteToken parameters without validation.",
    "impact": "If deployed with zero addresses, the token becomes non-functional - mint/burn calls will fail silently or send tokens to address(0), causing permanent fund loss.",
    "paths": [
      "Deployer mistakenly passes address(0) for bridge or remoteToken",
      "Minting/Burning operations target address(0) or use zero address",
      "Tokens permanently lost or non-transferable"
    ]
  },
  {
    "id": "F-008",
    "severity": "Low",
    "confidence": "low",
    "title": "onlyEOA Modifier Bypass Via Recently Created EOAs",
    "locations": [
      "0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/StandardBridge.sol:103-106"
    ],
    "claim": "The onlyEOA modifier uses Address.isContract() which only checks if address has code at the time of call. Addresses that just executed a contract creation (with code) but where the call happens after the code is removed could bypass this check.",
    "impact": "Minimal security impact as this is a timing-dependent edge case, but allows certain smart contract wallets to potentially bypass intended EOA-only restrictions.",
    "paths": [
      "Smart contract executes a call in the same transaction as its creation",
      "Contract deletes its code after execution",
      "Subsequent bridge call passes isContract() check"
    ]
  }
]
```

```



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
