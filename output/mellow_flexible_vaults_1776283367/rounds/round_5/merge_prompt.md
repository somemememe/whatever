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
    "title": "Consensus threshold can be bypassed with duplicated signer entries",
    "locations": [
      "permissions/Consensus.sol:23",
      "permissions/Consensus.sol:26",
      "permissions/Consensus.sol:47"
    ],
    "claim": "`checkSignatures` only enforces `signatures.length >= threshold` and validates each element independently; it never enforces signer uniqueness. The same authorized signer/signature can be repeated to satisfy threshold.",
    "impact": "Multisig guarantees collapse for all `Consensus`-gated flows. Operations meant to require N distinct signers can be executed with fewer real signers, enabling unauthorized signature-queue deposits/redeems.",
    "paths": [
      "Configure threshold > 1 with at least one valid signer",
      "Submit signatures array containing duplicate entries for that signer",
      "`checkSignatures` returns true and privileged order executes"
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
    "title": "Deposit cancellation uses oracle checkpoint value as Fenwick index",
    "locations": [
      "queues/DepositQueue.sol:107",
      "queues/DepositQueue.sol:114"
    ],
    "claim": "`cancelDepositRequest` reads `(exists, timestamp, index)` from `prices.latestCheckpoint()`, but for `Checkpoints.Trace224` the third return value is the checkpoint value (`priceD18`), not the request-tree index. That value is incorrectly used in `requests.modify(index, -assets)`.",
    "impact": "Cancellations can revert (out-of-bounds Fenwick index) after reports exist, causing effective lockup of pending requests. In other states, subtraction may hit the wrong bucket and corrupt aggregate queue accounting.",
    "paths": [
      "User creates deposit request",
      "Before claimability, user calls `cancelDepositRequest`",
      "Function uses `priceD18` as Fenwick index in `requests.modify`, causing revert or wrong-bucket mutation"
    ],
    "round": 1,
    "source_agents": [
      "codex_1",
      "opencode_1"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Transfer whitelist check is inverted",
    "locations": [
      "managers/ShareManager.sol:138",
      "managers/ShareManager.sol:139"
    ],
    "claim": "With transfer whitelist enabled, `updateChecks` reverts when `from.canTransfer` is true or `to.canTransfer` is false. This inverts sender policy: non-transferable senders can pass if receiver is transferable, while transferable senders are blocked.",
    "impact": "Transfer restriction policy is mis-enforced, allowing unauthorized transfers and blocking authorized ones.",
    "paths": [
      "Enable `hasTransferWhitelist`",
      "Set sender `canTransfer=false` and recipient `canTransfer=true`",
      "Sender transfer passes despite being non-transfer-whitelisted"
    ],
    "round": 1,
    "source_agents": [
      "codex_1",
      "opencode_1"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "high",
    "title": "Signature queues bypass global queue pause",
    "locations": [
      "queues/SignatureDepositQueue.sol:11",
      "queues/SignatureRedeemQueue.sol:13",
      "modules/ShareModule.sol:183"
    ],
    "claim": "Standard deposit/redeem queues check `isPausedQueue(address(this))`, but signature queue entrypoints do not. Pausing a queue in `ShareModule` does not stop `SignatureDepositQueue.deposit` / `SignatureRedeemQueue.redeem`.",
    "impact": "Emergency queue pause is ineffective for signature-based flows, allowing continued state-changing operations during incidents.",
    "paths": [
      "Admin pauses queue with `setQueueStatus(queue, true)`",
      "User submits signature-queue order",
      "Order still executes because entrypoint lacks pause check"
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Auto-claim on token updates can become gas-prohibitive with many queues/assets",
    "locations": [
      "modules/ShareModule.sol:234",
      "modules/ShareModule.sol:238",
      "modules/ShareModule.sol:242",
      "managers/TokenizedShareManager.sol:46",
      "managers/TokenizedShareManager.sol:49",
      "managers/TokenizedShareManager.sol:52"
    ],
    "claim": "`claimShares` iterates all assets and all deposit queues. `TokenizedShareManager._update` calls `claimShares` for both `from` and `to` on every transfer/mint/burn, creating O(assets*queues) overhead per token movement.",
    "impact": "As queue/asset count grows, ordinary share transfers can exceed gas limits and fail, creating liveness failures for tokenized share operations.",
    "paths": [
      "Protocol accumulates many assets/queues",
      "Any transfer triggers `_update` -> `claimShares(from)` and `claimShares(to)`",
      "Nested iteration and external queue calls make transfers revert from gas exhaustion"
    ],
    "round": 1,
    "source_agents": [
      "codex_1",
      "opencode_1"
    ]
  },
  {
    "id": "F-006",
    "severity": "Low",
    "confidence": "medium",
    "title": "Permissionless one-time `setVault` can be initialization-hijacked in non-atomic deployments",
    "locations": [
      "managers/ShareManager.sol:167",
      "managers/RiskManager.sol:147",
      "oracles/Oracle.sol:90",
      "vaults/VaultConfigurator.sol:70"
    ],
    "claim": "`setVault` is externally callable and only guarded by one-time initialization (`vault == 0`). If deployment/configuration is not atomic, an external caller can front-run and permanently bind a component to the wrong vault.",
    "impact": "Initialization can be griefed or hijacked, potentially bricking intended deployment flows and forcing redeployments.",
    "paths": [
      "Component proxy is deployed with unset vault",
      "Attacker calls `setVault(attackerVault)` first",
      "Legitimate configurator call reverts with `InvalidInitialization`"
    ],
    "round": 1,
    "source_agents": [
      "codex_1",
      "opencode_1"
    ]
  },
  {
    "id": "F-007",
    "severity": "High",
    "confidence": "high",
    "title": "Protocol fee can be minted multiple times per period by reporting non-base assets",
    "locations": [
      "managers/FeeManager.sol:81",
      "managers/FeeManager.sol:83",
      "managers/FeeManager.sol:119",
      "modules/ShareModule.sol:281",
      "modules/ShareModule.sol:285"
    ],
    "claim": "`calculateFee` applies protocol time-based accrual for every `handleReport` call using `timestamps[vault]`, but `updateState` only advances that timestamp when `asset == baseAsset`. Non-base asset reports therefore repeatedly charge the same elapsed interval before a base-asset report updates the checkpoint.",
    "impact": "Repeated reporting across non-base assets can over-mint fee shares for the same time window, causing material dilution and value extraction to the fee recipient.",
    "paths": [
      "Timestamp checkpoint is stale for a vault",
      "Oracle submits report(s) for non-base asset(s): each `handleReport` mints protocol fee from the same elapsed interval",
      "Only later base-asset report updates timestamp, after over-accrual has already occurred"
    ],
    "round": 2,
    "source_agents": [
      "codex_1",
      "opencode_1"
    ]
  },
  {
    "id": "F-008",
    "severity": "High",
    "confidence": "high",
    "title": "Performance fee is charged on price drawdowns instead of gains",
    "locations": [
      "managers/FeeManager.sol:77",
      "managers/FeeManager.sol:78",
      "managers/FeeManager.sol:123",
      "managers/FeeManager.sol:124"
    ],
    "claim": "`calculateFee` mints performance fee when `priceD18 < minPriceD18`, and `updateState` tracks/updates a running minimum. This charges performance fees on new lows rather than on appreciation.",
    "impact": "Users are diluted during negative performance; repeated lower prices can trigger repeated performance-fee minting, inverting expected fee economics.",
    "paths": [
      "Base-asset min price exists from prior reports",
      "New lower base-asset report arrives and `calculateFee` mints performance fee",
      "`updateState` lowers `minPriceD18`, enabling repeated fee minting on subsequent lower lows"
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-009",
    "severity": "Medium",
    "confidence": "high",
    "title": "Disallowing a subvault asset can permanently lock already-held funds",
    "locations": [
      "managers/RiskManager.sol:242",
      "managers/RiskManager.sol:243",
      "modules/VaultModule.sol:147",
      "modules/VaultModule.sol:148"
    ],
    "claim": "`modifySubvaultBalance` reverts for any asset not in `allowedAssets[subvault]`, regardless of direction. After governance removes an asset via `disallowSubvaultAssets`, later negative balance updates needed for pulls (`_pullAssets`) also revert.",
    "impact": "Assets already held in a subvault can become non-withdrawable after disallowing, creating permanent lockup unless special recovery exists.",
    "paths": [
      "Subvault holds asset X",
      "Governance disallows X for that subvault",
      "Any later pull path calling `modifySubvaultBalance(subvault, X, negative)` reverts with `NotAllowedAsset`"
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-010",
    "severity": "Medium",
    "confidence": "high",
    "title": "Redeem hook can be griefed by dusting disallowed subvaults",
    "locations": [
      "hooks/BasicRedeemHook.sol:19",
      "hooks/BasicRedeemHook.sol:24",
      "hooks/BasicRedeemHook.sol:39",
      "managers/RiskManager.sol:242",
      "queues/RedeemQueue.sol:178",
      "queues/RedeemQueue.sol:194"
    ],
    "claim": "`BasicRedeemHook` treats raw ERC20 balances in all subvaults as liquid and tries to pull from any subvault with positive balance. If a subvault is not allowed for that asset, `hookPullAssets` reaches `modifySubvaultBalance` and reverts with `NotAllowedAsset`.",
    "impact": "An attacker can dust tokens into a disallowed subvault and cause redemption batch handling to revert, creating permissionless DoS on affected redeem flows using this hook.",
    "paths": [
      "Attacker transfers dust of redeem asset A to subvault S that disallows A",
      "Hook counts S balance as liquid and attempts pull during redeem processing",
      "RiskManager rejects pull for disallowed asset, reverting batch handling"
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
    "title": "Deposit accounting assumes exact ERC20 transfers and breaks on fee-on-transfer tokens",
    "locations": [
      "libraries/TransferLibrary.sol:46",
      "queues/DepositQueue.sol:77",
      "queues/DepositQueue.sol:91",
      "queues/SignatureDepositQueue.sol:14",
      "queues/SignatureDepositQueue.sol:18"
    ],
    "claim": "ERC20 receive paths trust requested amount and do not check actual token delta after transfer. For taxed/deflationary tokens, internal accounting and minted shares are based on nominal amount while actual received amount is lower.",
    "impact": "If such assets are supported, the protocol can mint excess shares versus real assets received, causing dilution and potential insolvency/failed redemptions.",
    "paths": [
      "User deposits fee-on-transfer token",
      "Queue records/mints against full requested amount",
      "Vault receives less than accounted, creating an accounting deficit"
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-013",
    "severity": "Medium",
    "confidence": "low",
    "title": "Signature redeem can burn shares from arbitrary recipients without recipient-bound authorization",
    "locations": [
      "queues/SignatureRedeemQueue.sol:22",
      "queues/SignatureQueue.sol:98"
    ],
    "claim": "`validateOrder` only binds `order.caller` to `msg.sender` and nonce/signatures, while `SignatureRedeemQueue.redeem` burns `order.recipient` shares. There is no on-chain requirement that the burned account authorized this redemption (e.g., recipient signature or `recipient == caller`).",
    "impact": "If signer policy/process is compromised or misconfigured, third-party accounts can be forcibly redeemed at signer-approved terms, causing involuntary exits and economic harm.",
    "paths": [
      "Submit a consensus-signed redeem order with `caller=executor` and `recipient=victim`",
      "Validation passes because caller/nonce/signatures are valid",
      "Queue burns victim shares and transfers redemption assets to victim, forcing an unwanted unwind"
    ],
    "round": 3,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-014",
    "severity": "Medium",
    "confidence": "high",
    "title": "Removing an oracle-supported asset can brick queue/risk flows and lock funds",
    "locations": [
      "oracles/Oracle.sol:64",
      "oracles/Oracle.sol:153",
      "managers/RiskManager.sol:108",
      "queues/DepositQueue.sol:113",
      "queues/RedeemQueue.sol:195",
      "queues/SignatureDepositQueue.sol:20"
    ],
    "claim": "`removeSupportedAssets` deletes support/report state without checking for active queues, pending requests, or existing balances. `RiskManager.convertToShares` hard-reverts via `oracle.getReport(asset)` for unsupported assets, and several core queue settlement/cancellation paths depend on it.",
    "impact": "After removal, affected operations can revert (pending deposit cancellation, redeem batch handling, vault balance updates), creating stuck accounting and realistic fund lockup for that asset.",
    "paths": [
      "Privileged actor removes an asset still used by queues/positions",
      "Subsequent flows call `RiskManager.convertToShares(asset, ...)`",
      "`oracle.getReport(asset)` reverts `UnsupportedAsset`, bricking settlement/cancelation paths"
    ],
    "round": 3,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-015",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Permissionless claiming allows third parties to impose targeted-lockup timing on victims",
    "locations": [
      "modules/ShareModule.sol:234",
      "queues/DepositQueue.sol:120",
      "managers/ShareManager.sol:180",
      "managers/ShareManager.sol:229"
    ],
    "claim": "`ShareModule.claimShares(account)` and `DepositQueue.claim(account)` are callable by anyone for arbitrary users. When claim mints shares, `ShareManager.mint` sets `accounts[account].lockedUntil = block.timestamp + targetedLockup`, letting third parties choose when that lock window starts.",
    "impact": "If `targetedLockup` is enabled, attackers can front-run user actions and force lock activation at adverse times, temporarily blocking victim transfers/burns (including previously-held active shares) and causing targeted denial-of-use.",
    "paths": [
      "Victim has claimable deposit shares and `targetedLockup` is non-zero",
      "Attacker calls `claimShares(victim)` or `DepositQueue.claim(victim)` before victim’s planned transfer/redeem",
      "Claim mints and refreshes `lockedUntil`, making victim’s next transfer/burn revert until expiry"
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
    "id": "F-016",
    "severity": "Medium",
    "confidence": "high",
    "title": "Signature queues bypass configured deposit/redeem fee logic",
    "locations": [
      "queues/SignatureDepositQueue.sol:11",
      "queues/SignatureDepositQueue.sol:21",
      "queues/SignatureRedeemQueue.sol:13",
      "queues/SignatureRedeemQueue.sol:22",
      "queues/DepositQueue.sol:167",
      "queues/RedeemQueue.sol:100"
    ],
    "claim": "The signature-based execution paths mint/burn shares directly without applying `FeeManager.calculateDepositFee` / `calculateRedeemFee`, unlike normal deposit/redeem queues.",
    "impact": "Users routed through signature queues can avoid protocol/user fee policy, causing fee-recipient revenue loss and inconsistent share economics versus standard queue users.",
    "paths": [
      "Obtain valid consensus signatures for a deposit order and execute via `SignatureDepositQueue.deposit` to mint `order.requested` shares without deposit fee deduction.",
      "Obtain valid signatures for a redeem order and execute via `SignatureRedeemQueue.redeem` to redeem without redeem fee deduction."
    ]
  },
  {
    "id": "F-017",
    "severity": "Medium",
    "confidence": "medium",
    "title": "CUSTOM_VERIFIER payload decoding is incompatible with documented encoding and can DoS authorized calls",
    "locations": [
      "interfaces/permissions/IVerifier.sol:81",
      "permissions/Verifier.sol:115",
      "permissions/Verifier.sol:119"
    ],
    "claim": "The interface documents `verificationData` as `abi.encodePacked(address customVerifier, customVerifierSpecificData)`, but runtime parsing assumes a 32-byte-prefixed verifier (`calldataload`) and slices custom data from offset `0x20`, which is a different wire format.",
    "impact": "If governance/signers build Merkle leaves per documented format, CUSTOM_VERIFIER checks fail at execution time, potentially blocking protocol operations (e.g., strategy withdraw/claim calls) and causing operational lockups until roots are rebuilt.",
    "paths": [
      "Generate Merkle leaves using documented packed encoding.",
      "Submit call with valid proof.",
      "Verifier extracts wrong verifier/data layout and the custom check fails, reverting `CallModule.call`."
    ]
  },
  {
    "id": "F-018",
    "severity": "Medium",
    "confidence": "high",
    "title": "Vault↔subvault accounting assumes exact token transfers and breaks for fee-on-transfer assets",
    "locations": [
      "modules/VaultModule.sol:147",
      "modules/VaultModule.sol:153",
      "modules/SubvaultModule.sol:33",
      "libraries/TransferLibrary.sol:27"
    ],
    "claim": "`_pushAssets`/`_pullAssets` update RiskManager balances using requested `value`, while actual transferred amount is not measured; fee-on-transfer/deflationary tokens can move less than accounted.",
    "impact": "Risk state can drift from real balances, leading to understated deficits, limit-check inaccuracies, and eventual redeem/withdraw failures or insolvency-like shortfalls.",
    "paths": [
      "Push fee-on-transfer asset from vault to subvault: RiskManager adds full `value`, subvault receives less.",
      "Later pull/redeem based on inflated accounting and fail to source expected amount."
    ]
  },
  {
    "id": "F-019",
    "severity": "Informational",
    "confidence": "high",
    "title": "Revoked compact calls are not deleted from `compactCalls` mapping",
    "locations": [
      "permissions/Verifier.sol:168"
    ],
    "claim": "`disallowCalls` removes the hash from the active set but reassigns `compactCalls_[hash]` instead of deleting it, leaving stale call metadata in storage.",
    "impact": "On-chain authorization remains correct (set membership), but stale metadata can mislead off-chain tooling/auditing automation that inspects mapping storage.",
    "paths": [
      "Allow a compact call, then disallow it.",
      "Hash is removed from set but mapping entry remains populated."
    ]
  },
  {
    "id": "F-020",
    "severity": "Low",
    "confidence": "high",
    "title": "ERC20 deposit entrypoints are payable and can trap accidental ETH permanently",
    "locations": [
      "queues/DepositQueue.sol:59",
      "queues/SignatureDepositQueue.sol:11",
      "libraries/TransferLibrary.sol:40"
    ],
    "claim": "For non-ETH assets, `receiveAssets` does not enforce `msg.value == 0`; both deposit entrypoints are `payable`, so accidental ETH is accepted but not recoverable through queue logic.",
    "impact": "Users/integrators can irreversibly lose ETH by sending value alongside ERC20 deposits.",
    "paths": [
      "Call ERC20 deposit with nonzero `msg.value`.",
      "ERC20 transfer path executes and ETH remains stranded in queue contract."
    ]
  }
]

```

### Agent: opencode_1
```
I'll audit the smart contracts in the specified directory. Let me first explore the contract files to understand the codebase structure.
Let me read the prior round summary and global audit memory to understand what's already been found, and then systematically review key contracts.
Now I'll systematically audit the contracts. Based on the global summary, files that received limited attention are: ACLModule.sol, CallModule.sol, SubvaultModule.sol, and TokenizedShareManager.sol. Let me also check other files for new vulnerabilities.
Let me continue reading key contracts to find vulnerabilities:
Based on my complete audit of the smart contracts, I've identified several vulnerabilities. Some are already known from prior rounds (F-001 through F-015), and I've found multiple new issues. Let me provide the JSON array:
Let me re-examine and fix some of these findings - some may have been overstated or duplicates. Let me check the FeeManager more carefully:
Let me reconsider the findings more carefully and trim to the most accurate and significant issues:
[{"id": "F-016", "severity": "Medium", "confidence": "high", "title": "TokenizedShareManager Transfer Causes Unbounded Claim Loop", "locations": ["managers/TokenizedShareManager.sol:46-55"], "claim": "The _update function calls claimShares on both from and to addresses during every transfer. The claim loop iterates through all assets and queues for each account, creating unbounded gas consumption that can cause transfers to revert for accounts with complex deposit histories.", "impact": "Transfers fail when users have deposits across multiple assets/queues due to unbounded gas consumption. Users with extensive deposit activity cannot transfer their shares.", "paths": ["User with deposits across multiple assets/queues attempts transfer, runs out of gas"]}, {"id": "F-017", "severity": "Medium", "confidence": "medium", "title": "SignatureQueue Nonce Allows Non-Sequential Orders", "locations": ["queues/SignatureQueue.sol:101-103"], "claim": "The validateOrder function checks order.nonce != nonces(order.caller), allowing any nonce greater than the stored nonce. This allows non-sequential order execution and does not enforce strict ordering.", "impact": "Orders with outdated parameters but higher nonces can still be executed, potentially at unfavorable prices that have since changed.", "paths": ["User creates order with outdated price, increments nonce, submits stale order"]}, {"id": "F-018", "severity": "Medium", "confidence": "low", "title": "Factory Accepts Arbitrary Implementation Addresses", "locations": ["factories/Factory.sol:80-90"], "claim": "The proposeImplementation function accepts any address without code existence validation. Non-contract or EOAs can be proposed and later accepted.", "impact": "If a non-contract implementation is accepted, vault deployments will fail or behave unpredictably.", "paths": ["Attacker proposes EOA address as implementation"]}, {"id": "F-019", "severity": "Medium", "confidence": "medium", "title": "LidoDepositHook Ignores Return Values From External Calls", "locations": ["hooks/LidoDepositHook.sol:29-48"], "claim": "The callHook function performs external calls to Lido contracts (wrap/withdraw) without checking return values. The IERC20.safeIncreaseAllowance and Address.sendValue may fail silently.", "impact": "Failed Lido operations that return false do not revert the transaction, potentially trapping user assets in the hook without clear indication of failure.", "paths": ["Lido wrap/withdraw operations fail due to rate limits or contracts, assets trapped"]}, {"id": "F-020", "severity": "Low", "confidence": "medium", "title": "Oracle SubmitReports Has No Rate Limiting Per Oracle", "locations": ["oracles/Oracle.sol:103-121"], "claim": "The submitReports function allows unlimited submissions by any oracle with the role, without per-oracle rate limiting.", "impact": "Oracles can spam submissions to cause unnecessary state updates and increase protocol gas costs.", "paths": ["Attacker oracle role spams submitReports"]}, {"id": "F-021", "severity": "Low", "confidence": "high", "title": "SignatureQueue Order Price Validation Uses Requested/Ordered Ratio", "locations": ["queues/SignatureQueue.sol:111-118"], "claim": "The order price is validated using requested/ordered ratio, which differs from actual executed price that includes fees.", "impact": "Price validation may pass even though actual execution price is lower due to fees. This is an informational issue rather than security vulnerability.", "paths": []}]

```


## Excluded From Direct Audit Scope
Do not keep findings whose reportable root cause exists solely in files matching:
- `interfaces/**`

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
