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
    "title": "User-controlled swap params can spend arbitrary token balances held by gateway contracts",
    "locations": [
      "GatewayCrossChain.sol:373",
      "GatewayCrossChain.sol:492",
      "GatewayTransferNative.sol:453",
      "GatewayTransferNative.sol:414",
      "GatewayTransferNative.sol:574",
      "GatewaySend.sol:199",
      "GatewaySend.sol:245",
      "GatewaySend.sol:366"
    ],
    "claim": "The contracts decode `MixSwapParams` from attacker-controlled calldata and approve/swap `params.fromToken` without enforcing that it matches the actually received input token/amount.",
    "impact": "An attacker can drain valuable tokens already stored in these contracts (fees, refunds, leftovers) by supplying crafted swap data that spends those balances and routes outputs to attacker-controlled recipients.",
    "paths": [
      "Craft swapData so `params.fromToken` is a token currently held by the contract and `params.fromTokenAmount` is attacker-chosen.",
      "Trigger `onCall` / `withdrawToNativeChain` / `depositAndCall` with cheap or unrelated input token.",
      "Contract approves DODO and executes `mixSwap`, spending unrelated balances and forwarding outputs to attacker."
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
    "claim": "In `claimRefund`, `receiver` defaults to `msg.sender` when `walletAddress.length != 20`, and the authorization check then trivially passes for any caller.",
    "impact": "Refunds intended for non-EVM recipients (e.g., BTC/Solana-style addresses) can be front-run and stolen by arbitrary users.",
    "paths": [
      "A cross-chain operation fails and stores refund info with a non-20-byte wallet address.",
      "Attacker observes `externalId` and calls `claimRefund(externalId)` before intended claimant.",
      "Funds transfer to attacker because `msg.sender == receiver` is always true in this branch."
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
    "claim": "`withdraw` encodes revert data as `bytes20(sender)`, truncating non-20-byte recipient bytes; `onRevert` then treats it as an EVM address and transfers funds there.",
    "impact": "Failed non-EVM withdrawals can refund to an unintended EVM address (or effectively burn funds), causing permanent user fund loss.",
    "paths": [
      "User initiates withdrawal with non-20-byte recipient bytes.",
      "Downstream withdrawal reverts.",
      "Gateway calls `onRevert`; contract decodes 52-byte message and transfers refund to truncated EVM address."
    ]
  },
  {
    "id": "F-004",
    "severity": "Critical",
    "confidence": "high",
    "title": "ETH sentinel path in `withdrawToNativeChain` allows free withdrawal of escrowed tokens",
    "locations": [
      "GatewayTransferNative.sol:549",
      "GatewayTransferNative.sol:554",
      "GatewayTransferNative.sol:570",
      "GatewayTransferNative.sol:574",
      "GatewayTransferNative.sol:477"
    ],
    "claim": "When `zrc20 == 0xEeee...`, the function skips any real token transfer-in, yet still processes `amount`, executes swaps/approvals, and withdraws `decoded.targetZRC20` from contract balances.",
    "impact": "Attackers can withdraw real tokens from contract inventory without providing corresponding input assets.",
    "paths": [
      "Call `withdrawToNativeChain(_ETH_ADDRESS_, amount, craftedMessage)` with zero/insufficient real funding.",
      "Function skips `transferFrom` and `_doMixSwap` can return attacker-chosen amount path.",
      "Internal withdraw logic approves gateway and transfers out real `targetZRC20` held by the contract."
    ]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "medium",
    "title": "Destination payout amount in `GatewaySend.onCall` is fully trusted from payload",
    "locations": [
      "GatewaySend.sol:248",
      "GatewaySend.sol:347",
      "GatewaySend.sol:363",
      "GatewaySend.sol:370"
    ],
    "claim": "`onCall` uses `amount` decoded from message payload to determine payout, instead of reconciling against assets actually delivered by gateway in this call.",
    "impact": "A crafted cross-chain payload can overstate payout and drain pre-existing ETH/token balances from the destination contract.",
    "paths": [
      "Attacker sends a cross-chain call with payload encoding inflated `amount` and favorable token flags (e.g., ETH->ETH).",
      "Destination `onCall` sets `outputAmount = amount` and pays out from contract balance.",
      "Any surplus funds already held by the destination contract are siphoned."
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Reentrancy in `GatewayTransferNative.claimRefund` allows repeated refund withdrawal",
    "locations": [
      "GatewayTransferNative.sol:691",
      "GatewayTransferNative.sol:692"
    ],
    "claim": "`claimRefund` performs external token transfer before deleting `refundInfos[externalId]`.",
    "impact": "A malicious refund token can reenter `claimRefund` and pull the same refund multiple times before state is cleared.",
    "paths": [
      "Create refund entry with attacker-controlled token contract.",
      "Invoke `claimRefund`; token `transfer` callback reenters `claimRefund(externalId)`.",
      "Multiple transfers occur before storage deletion."
    ]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Pair existence detection is balance-based and can be dust-poisoned into swap DoS",
    "locations": [
      "GatewayCrossChain.sol:234",
      "GatewayCrossChain.sol:245",
      "GatewayTransferNative.sol:235",
      "GatewayTransferNative.sol:246",
      "libraries/UniswapV2Library.sol:44"
    ],
    "claim": "`_existsPairPool` checks token balances at computed pair address instead of verifying an actual pair contract exists.",
    "impact": "Attackers can dust non-contract pair addresses so path selection chooses invalid direct pools, causing reserve lookup/swap reverts and denial of service for affected routes.",
    "paths": [
      "For a token pair with no real pool, send dust of both tokens to computed pair address.",
      "`_existsPairPool` returns true due non-zero balances.",
      "Subsequent swaps use direct path and revert when `getReserves` is called on non-pair address."
    ]
  },
  {
    "id": "F-008",
    "severity": "Medium",
    "confidence": "low",
    "title": "Public `withdraw` in GatewayTransferNative can abuse leftover gateway allowances",
    "locations": [
      "GatewayTransferNative.sol:305",
      "GatewayTransferNative.sol:354",
      "GatewayTransferNative.sol:355",
      "GatewayTransferNative.sol:477",
      "GatewayTransferNative.sol:496"
    ],
    "claim": "`withdraw` is externally callable by anyone, while other flows continuously grant gateway allowances; if any allowance remains, an attacker can trigger unauthorized withdrawals.",
    "impact": "Residual approvals may let arbitrary users route contract-held assets out via gateway to attacker-chosen recipient bytes.",
    "paths": [
      "Wait for contract to set non-zero approval to gateway for a token.",
      "Call public `withdraw` with attacker-controlled `sender` bytes and amount within remaining allowance.",
      "Gateway pulls approved funds from contract and withdraws to attacker destination."
    ]
  }
]

```

### Agent: opencode_1
```
I'll start by reading the main contract files in scope to identify security vulnerabilities.
Now let me read the library and interface files to complete the audit:
Now I have reviewed all the contract files. Let me compile my security findings:

[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "Reentrancy Vulnerability in GatewayTransferNative.claimRefund",
    "locations": [
      "GatewayTransferNative.sol:680-700"
    ],
    "claim": "The claimRefund function performs a state update (delete refundInfos) AFTER the external call (safeTransfer), violating Check-Effects-Interactions pattern",
    "impact": "An attacker can repeatedly call claimRefund in a reentrant manner within a single transaction to drain all refund funds for a given externalId",
    "paths": [
      "1. Call claimRefund with a contract that implements a receiver hook",
      "2. In receiver hook, call claimRefund again before state is deleted",
      "3. Repeat to drain all funds"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Owner Can Drain All Contract Funds via superWithdraw",
    "locations": [
      "GatewayCrossChain.sol:188-196",
      "GatewayTransferNative.sol:185-193"
    ],
    "claim": "The superWithdraw function allows the owner to withdraw any amount of any token (including native ETH) from the contract to EddyTreasurySafe without any restrictions",
    "impact": "The owner (or a compromised owner key/EOA) can drain all protocol funds. Combined with the ability to set DODORouteProxy and DODOApprove to malicious contracts, this creates a complete rug-pull vector",
    "paths": [
      "1. Owner calls superWithdraw with arbitrary token and amount",
      "2. All funds moved to EddyTreasurySafe"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Owner Can Set Malicious DODORouteProxy to Steal User Funds",
    "locations": [
      "GatewayCrossChain.sol:142-146",
      "GatewaySend.sol:86-88",
      "GatewayTransferNative.sol:144-147"
    ],
    "claim": "The setDODORouteProxy function allows owner to change the router proxy address without any timelock or delay",
    "impact": "Owner can redirect all swaps through a malicious DODORouteProxy that steals user funds during the swap execution. Users lose all tokens sent through the contract",
    "paths": [
      "1. Owner calls setDODORouteProxy with attacker-controlled address",
      "2. User performs cross-chain swap",
      "3. Malicious router steals tokens"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "high",
    "title": "Owner Can Set Malicious DODOApprove to Steal User Tokens",
    "locations": [
      "GatewayCrossChain.sol:148-152",
      "GatewaySend.sol:68-80",
      "GatewayTransferNative.sol:149-152"
    ],
    "claim": "The setDODOApprove function allows owner to change the DODOApprove address which receives ERC20 approvals from the contract",
    "impact": "DODOApprove receives ERC20 approvals from the contract. A malicious owner can set DODOApprove to then steal any tokens approved to the contract. All user tokens sent to the contract can be drained",
    "paths": [
      "1. Owner calls setDODOApprove with attacker-controlled address",
      "2. User tokens are approved to contract",
      "3. Attacker calls transferFrom using DODOApprove to drain"
    ]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "medium",
    "title": "Owner Can Set Excessive FeePercent Degrading User Swaps",
    "locations": [
      "GatewayCrossChain.sol:154-158",
      "GatewayTransferNative.sol:154-158"
    ],
    "claim": "setFeePercent allows owner to set feePercent up to 1000 (100%) after initialization, though initialization has a validation",
    "impact": "Owner can continuously increase the platform fee to extract maximum value from users, making the protocol economically hostile. Combined with other owner privileges, this enables maximum value extraction",
    "paths": [
      "1. Owner calls setFeePercent(1000)",
      "2. All cross-chain swaps take 100% fee"
    ]
  },
  {
    "id": "F-006",
    "severity": "High",
    "confidence": "medium",
    "title": "Owner Can Set Excessive Slippage Causing User Loss",
    "locations": [
      "GatewayCrossChain.sol:160-164",
      "GatewayTransferNative.sol:175-179"
    ],
    "claim": "setSlippage allows setting slippage up to 500 (50%)",
    "impact": "Owner can set very high slippage tolerance causing users to receive significantly less output than expected. Though slippage is applied to user-side swaps internally, the owner can cause suboptimal execution",
    "paths": [
      "1. Owner sets slippage to 500",
      "2. User swaps execute with 50% slippage worst case"
    ]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "high",
    "title": "Arbitrary Gateway Address Can Be Set by Owner",
    "locations": [
      "GatewayCrossChain.sol:172-176",
      "GatewaySend.sol:91-94",
      "GatewayTransferNative.sol:165-168"
    ],
    "claim": "setGateway allows owner to change the GatewayZEVM/GatewayEVM contract address",
    "impact": "If gateway is changed to a malicious contract, the onCall/onRevert callbacks can be manipulated by the attacker to steal funds. While gateway is a protocol contract, misconfiguration or compromise leads to fund loss",
    "paths": [
      "1. Owner sets malicious gateway",
      "2. Gateway callbacks manipulate state"
    ]
  },
  {
    "id": "F-008",
    "severity": "Medium",
    "confidence": "high",
    "title": "Missing Deadline Validation in Uniswap Swaps",
    "locations": [
      "GatewayCrossChain.sol:346-353",
      "GatewayTransferNative.sol:342-349"
    ],
    "claim": "The _swapAndSendERC20Tokens function uses block.timestamp + MAX_DEADLINE as deadline but does not validate block.timestamp against user's intended deadline",
    "impact": "Transactions can be held in mempool and executed at a later time when Uniswap rates are unfavorable, causing user loss. No user-controlled deadline enforcement",
    "paths": [
      "1. User submits swap transaction",
      "2. Transaction sits in mempool",
      "3. Executed later at worse Uniswap rate"
    ]
  },
  {
    "id": "F-009",
    "severity": "Medium",
    "confidence": "low",
    "title": "AccountEncoder.decompressAccounts Lacks Bounds Checking",
    "locations": [
      "AccountEncoder.sol:19-53"
    ],
    "claim": "The decompressAccounts function reads accounts length from input bytes without proper bounds checking on len before allocating memory",
    "impact": "Malicious calldata with crafted len could cause memory corruption or Out-of-Gas. However, this is only used in cross-chain message processing which may have external safeguards",
    "paths": [
      "1. Pass malicious calldata with len > actual data",
      "2. Memory corruption or OOG"
    ]
  },
  {
    "id": "F-010",
    "severity": "Medium",
    "confidence": "low",
    "title": "SwapDataHelperLib Uses Unchecked Arithmetic Without Validation",
    "locations": [
      "SwapDataHelperLib.sol:162-270"
    ],
    "claim": "decodeCompressedMixSwapParams uses unchecked blocks for all arithmetic when parsing calldata",
    "impact": "Malicious calldata could cause overflow in length calculations leading to incorrect parsing or truncated data. While not directly exploitable for theft, could cause unexpected behavior",
    "paths": [
      "1. Pass calldata causing overflow in offsets",
      "2. Incorrect parsing or truncated data"
    ]
  },
  {
    "id": "F-011",
    "severity": "Low",
    "confidence": "high",
    "title": "Missing Zero Address Validation in setDODORouteProxy GatewaySend.sol",
    "locations": [
      "GatewaySend.sol:86-88"
    ],
    "claim": "setDODORouteProxy in GatewaySend.sol lacks zero address validation unlike other contracts",
    "impact": "Owner could accidentally set zero address breaking the protocol functionality",
    "paths": [
      "1. Owner calls setDODORouteProxy(address(0))",
      "2. Protocol functionality broken"
    ]
  },
  {
    "id": "F-012",
    "severity": "Low",
    "confidence": "medium",
    "title": "Inconsistent CEI Pattern Between claimRefund Implementations",
    "locations": [
      "GatewayCrossChain.sol:602-629",
      "GatewayTransferNative.sol:680-700"
    ],
    "claim": "GatewayCrossChain.claimRefund deletes state before transfer (correct CEI), while GatewayTransferNative.claimRefund deletes after transfer (incorrect)",
    "impact": "Inconsistent security patterns make the codebase harder to audit and increases chance of bugs. GatewayTransferNative is vulnerable to reentrancy as noted in F-001",
    "paths": [
      "See F-001 for exploitation"
    ]
  },
  {
    "id": "F-013",
    "severity": "Low",
    "confidence": "low",
    "title": "Inconsistent Zero Address Validation in setEddyTreasurySafe",
    "locations": [
      "GatewayTransferNative.sol:170-173"
    ],
    "claim": "setEddyTreasurySafe in GatewayTransferNative lacks zero address validation unlike GatewayCrossChain",
    "impact": "Inconsistent validation patterns across similar functions",
    "paths": [
      "1. Owner sets zero address",
      "2. Functions revert"
    ]
  },
  {
    "id": "F-014",
    "severity": "Informational",
    "confidence": "high",
    "title": "Unsafe Type Casting from Bytes to Address",
    "locations": [
      "GatewayCrossChain.sol:356",
      "GatewaySend.sol:356",
      "GatewayTransferNative.sol:390"
    ],
    "claim": "Multiple locations cast bytes to address via address(bytes20(recipient)) without validating input length",
    "impact": "If bytes length is not exactly 20, wrong address is derived. This is intentional for different receiver types but worth noting",
    "paths": []
  },
  {
    "id": "F-015",
    "severity": "Informational",
    "confidence": "high",
    "title": "External ID Collision Risk in _calcExternalId",
    "locations": [
      "GatewaySend.sol:160-162",
      "GatewayTransferNative.sol:195-197"
    ],
    "claim": "_calcExternalId uses globalNonce which can be front-run, and blockhash in GatewayTransferNative can be manipulated by miner",
    "impact": "External IDs could collide if transactions are mined in certain order. While nonce helps, blockhash is not unpredictable. This is a design consideration rather than vulnerability",
    "paths": []
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
