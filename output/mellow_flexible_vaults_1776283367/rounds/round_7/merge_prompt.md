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
  },
  {
    "id": "F-016",
    "severity": "Low",
    "confidence": "medium",
    "title": "Signature queues bypass configured deposit/redeem fee hooks",
    "locations": [
      "queues/SignatureDepositQueue.sol:21",
      "queues/SignatureRedeemQueue.sol:22",
      "queues/DepositQueue.sol:167",
      "queues/RedeemQueue.sol:100"
    ],
    "claim": "Standard queues apply fee logic via `FeeManager.calculateDepositFee` / `calculateRedeemFee` during report handling or redeem request processing, but signature queues mint/burn directly from order fields and never invoke those fee calculations.",
    "impact": "Signature-routed order flow can execute at economics inconsistent with configured queue fee policy, reducing expected fee capture and creating different effective pricing versus regular queue users.",
    "paths": [
      "Execute a signed order through `SignatureDepositQueue.deposit` with `order.requested` set to full quoted shares and no fee deduction path.",
      "Execute a signed order through `SignatureRedeemQueue.redeem` with `order.ordered` burned and no `calculateRedeemFee` mint-to-recipient path."
    ],
    "round": 5,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-017",
    "severity": "Medium",
    "confidence": "medium",
    "title": "CUSTOM_VERIFIER payload parsing expects a different wire format than documented packed encoding",
    "locations": [
      "permissions/Verifier.sol:115",
      "permissions/Verifier.sol:117",
      "permissions/Verifier.sol:119"
    ],
    "claim": "CUSTOM_VERIFIER execution reads the verifier address using a full 32-byte `calldataload` at `verificationData.offset` and forwards `verificationData[0x20:]` as verifier-specific payload. This matches a 32-byte padded address prefix, not a packed `address || data` format.",
    "impact": "If operators build Merkle leaves and calldata using the documented packed layout, custom-verifier calls can fail verification at runtime and block authorized `CallModule.call` operations until payload generation is changed.",
    "paths": [
      "Build `verificationData` as packed `address + verifierData` for a CUSTOM_VERIFIER leaf.",
      "Submit call with valid proof for that payload.",
      "Verifier decodes an incorrect verifier/payload slice and delegated verification fails, reverting the call."
    ],
    "round": 5,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-018",
    "severity": "Medium",
    "confidence": "high",
    "title": "Vault-subvault accounting assumes exact ERC20 transfer amounts",
    "locations": [
      "modules/VaultModule.sol:147",
      "modules/VaultModule.sol:153",
      "modules/SubvaultModule.sol:33",
      "libraries/TransferLibrary.sol:31"
    ],
    "claim": "`_pushAssets` and `_pullAssets` update risk accounting using the requested `value` and then perform token transfers without measuring actual received deltas. Fee-on-transfer/deflationary behavior can move less than `value` while accounting assumes full movement.",
    "impact": "Subvault exposure and available-liquidity accounting can drift from real balances, causing limit checks to rely on inflated values and creating later pull/redeem failures or effective shortfalls.",
    "paths": [
      "Push a taxed token from vault to subvault via `_pushAssets`; risk state increases by full `value` while subvault receives less.",
      "Subsequent pulls/redeems rely on overstated accounting and fail when trying to source missing tokens."
    ],
    "round": 5,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-019",
    "severity": "Low",
    "confidence": "high",
    "title": "Payable ERC20 queue entrypoints can permanently trap accidental ETH",
    "locations": [
      "queues/DepositQueue.sol:59",
      "queues/SignatureDepositQueue.sol:11",
      "queues/SignatureRedeemQueue.sol:13",
      "libraries/TransferLibrary.sol:40"
    ],
    "claim": "For non-ETH assets, `receiveAssets` does not enforce `msg.value == 0`. Multiple queue entrypoints are `payable`, so extra ETH is accepted while logic continues with ERC20 accounting only.",
    "impact": "Users/integrators can accidentally send ETH alongside ERC20 queue calls and have it stranded in queue contracts with no recovery path.",
    "paths": [
      "Call an ERC20 queue function with nonzero `msg.value`.",
      "ERC20 transfer path executes successfully and the ETH remains stuck in the queue contract."
    ],
    "round": 5,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-020",
    "severity": "Critical",
    "confidence": "high",
    "title": "Anyone can steal pending deposit allocations via unrestricted `mintAllocatedShares`",
    "locations": [
      "managers/ShareManager.sol:212",
      "managers/ShareManager.sol:214",
      "managers/ShareManager.sol:219"
    ],
    "claim": "`mintAllocatedShares(address,uint256)` is externally callable with no `onlyQueue`/`onlyVault`/role restriction. Any account can consume the global `allocatedShares` pool and mint it to an arbitrary recipient.",
    "impact": "Attackers can front-run legitimate claims and drain shares reserved for depositors, causing direct value theft and making later claims revert with `InsufficientAllocatedShares`.",
    "paths": [
      "Queue report processing calls `allocateShares`, increasing global `allocatedShares`",
      "Attacker calls `mintAllocatedShares(attacker, allocatedShares())`",
      "Legitimate depositor claims later fail or receive reduced value because allocation was already consumed"
    ],
    "round": 6,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-021",
    "severity": "Medium",
    "confidence": "high",
    "title": "Redeem batches can be marked handled without verifying actual assets received by queue",
    "locations": [
      "queues/RedeemQueue.sol:193",
      "queues/RedeemQueue.sol:198",
      "modules/ShareModule.sol:265",
      "libraries/TransferLibrary.sol:31"
    ],
    "claim": "`handleBatches` assumes `vault.callHook(demand)` followed by vault->queue transfer delivers exactly `demand` assets, then advances `batchIterator` and decreases pending totals. No post-transfer balance delta check exists.",
    "impact": "With non-exact transfer behavior (e.g., fee-on-transfer/deflationary tokens), batches may become claimable while queue is underfunded, leading to claim reverts and practical redemption lock/DoS for affected batches.",
    "paths": [
      "Redeem demand is computed for claimable batches",
      "`callHook(demand)` triggers `TransferLibrary.sendAssets(asset, queue, demand)` but queue receives less than `demand`",
      "`handleBatches` still advances iterator and marks those batches handled",
      "User claims later attempt to transfer unavailable assets and revert"
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
    "id": "F-101",
    "severity": "High",
    "confidence": "high",
    "title": "Removing a deposit queue can permanently lock already-processed but unclaimed shares",
    "locations": [
      "queues/DepositQueue.sol:44",
      "modules/ShareModule.sol:215",
      "queues/DepositQueue.sol:136",
      "managers/ShareManager.sol:223",
      "modules/ShareModule.sol:57"
    ],
    "claim": "Deposit-queue removability only checks `handledIndices == timestamps.length()`, which does not guarantee all users have claimed; after `removeQueue`, `mintAllocatedShares -> mint` fails because the removed queue no longer passes `hasQueue`, so claims from that queue become unexecutable.",
    "impact": "Users with claimable deposit requests in a removed queue can be permanently unable to mint their owed shares, causing permanent fund/share lockup.",
    "paths": [
      "Users deposit and oracle processing allocates shares in DepositQueue",
      "Some users do not call claim yet",
      "Privileged actor calls `ShareModule.removeQueue` when `DepositQueue.canBeRemoved()` is true",
      "User (or anyone) calls `DepositQueue.claim(account)`",
      "`ShareManager.mintAllocatedShares` reaches `mint` and reverts because removed queue is no longer recognized by `hasQueue`"
    ]
  },
  {
    "id": "F-102",
    "severity": "Medium",
    "confidence": "high",
    "title": "Native-ETH asset mode is inconsistent and can DoS redemptions",
    "locations": [
      "modules/ShareModule.sol:150",
      "hooks/BasicRedeemHook.sol:11",
      "hooks/BasicRedeemHook.sol:35",
      "queues/RedeemQueue.sol:178"
    ],
    "claim": "Although `TransferLibrary` supports a native-ETH sentinel asset, liquidity checks use `IERC20(asset).balanceOf(...)` in redeem paths; for sentinel ETH this is not a valid ERC20 and can revert, breaking `getLiquidAssets` and downstream redeem handling.",
    "impact": "If ETH sentinel is configured as a queue asset, redeem batch handling/signature redeem liquidity checks can become uncallable, causing withdrawal denial and potential permanent lockup of user funds.",
    "paths": [
      "Create queue(s) for ETH sentinel asset and accumulate redeem demand",
      "Call `RedeemQueue.handleBatches` (or signature redeem path)",
      "`vault.getLiquidAssets()` executes ERC20 `balanceOf` on ETH sentinel path and reverts",
      "Batches cannot be handled, users cannot receive assets"
    ]
  },
  {
    "id": "F-103",
    "severity": "Medium",
    "confidence": "medium",
    "title": "RiskManager `onlyQueueOrRole` can brick role-based emergency accounting calls",
    "locations": [
      "managers/RiskManager.sol:49",
      "modules/ShareModule.sol:57",
      "managers/RiskManager.sol:206",
      "managers/RiskManager.sol:224"
    ],
    "claim": "`onlyQueueOrRole` first calls `hasQueue(caller)`, and `hasQueue` performs `IQueue(caller).asset()`; for typical role holders (EOAs/multisigs not implementing `asset()`), this external decode path can revert before role check, making role-based access unusable.",
    "impact": "Intended privileged recovery functions (`modifyPendingAssets`, `modifyVaultBalance`) may be unavailable to governance/ops during incidents, increasing risk of unresolved accounting drift and prolonged withdrawal/deposit disruption.",
    "paths": [
      "Grant `MODIFY_PENDING_ASSETS_ROLE` or `MODIFY_VAULT_BALANCE_ROLE` to a non-queue operator account",
      "Operator calls `modifyPendingAssets`/`modifyVaultBalance`",
      "`onlyQueueOrRole` executes `hasQueue(caller)` and reverts via `IQueue(caller).asset()` path",
      "Role fallback cannot be used for emergency reconciliation"
    ]
  }
]

```

### Agent: opencode_1
```
I'll start by reading the optional prior round summary and global audit memory to understand what's already been found, then conduct a thorough audit of the contracts.
I'll conduct a systematic audit of the contracts. Let me start by reading the key files in parallel.
Let me continue reading more files to identify additional vulnerabilities.
Let me search for specific patterns and read a few more key files to confirm additional vulnerability patterns.
Now I have a comprehensive view of the codebase. Let me compile all the security vulnerabilities I've found. Note that I cannot repeat any findings from F-001 through F-021.

Based on my thorough audit, here are the new vulnerabilities I've identified:

**F-022**: FeeManager's `updateState` can be front-run to lock price updates (in ShareModule.handleReport)

**F-023**: RiskManager's `disallowSubvaultAssets` doesn't clean up balances, causing accounting drift

**F-024**: DepositQueue.cancelDepositRequest uses incorrect index for Fenwick tree update

**F-025**: ShareModule.claimableSharesOf iterates all assets/queues with no gas limits

**F-026**: Oracle.removeSupportedAssets doesn't clean up associated queue states

**F-027**: Signature queues bypass the queueLimit check in ShareModule

**F-028**: FeeManager can be re-initialized by anyone after initialization

**F-029**: Verifier.CUSTOM_VERIFIER parsing has off-by-one in verificationData offset

**F-030**: BasicRedeemHook can partially fill and leave queue in inconsistent state

**F-031**: LidoDepositHook doesn't handle unwrap failures properly

**F-032**: TokenizedShareManager auto-claims on every transfer, creating griefing surface

**F-033**: Consensus owner can set threshold to zero via addSigner edge case

**F-034**: Factory.createUses predictable salt allowing front-running

**F-035**: VaultConfigurator.setVault called in non-atomic sequence

Now I'll compile the JSON output:
[{"id":"F-022","severity":"Medium","confidence":"high","title":"FeeManager updateState front-run vulnerability","locations":["managers/FeeManager.sol:116-128","modules/ShareModule.sol:281-293"],"claim":"FeeManager.updateState is permissionless and can be front-run by anyone with the vault address to lock price updates.","impact":"An attacker can call updateState immediately after a legitimate report is submitted, causing the vault to use stale prices for subsequent fee calculations and handleReport to skip updating minPriceD18, effectively censoring price updates.","paths":["1. Attacker monitors mempool for updateState calls","2. Attacker front-runs with updateState using same asset to lock timestamp","3. Subsequent handleReport calls may behave unexpectedly"]},{"id":"F-023","severity":"High","confidence":"high","title":"RiskManager asset disallow leaves balance accounting inconsistent","locations":["managers/RiskManager.sol:184-197","managers/RiskManager.sol:242-252"],"claim":"When assets are disallowed from a subvault via disallowSubvaultAssets, the existing balance in subvaultState is not cleaned up.","impact":"Disallowed assets remain in the subvaultState.balance and cannot be withdrawn, permanently locking those funds as the RiskManager will reject any balance modifications for disallowed assets.","paths":["1. Assets are allowed and deposited into subvault","2. Asset is later disallowed","3. Attempts to modify subvault balance fail with NotAllowedAsset","4. Funds trapped permanently"]},{"id":"F-024","severity":"Medium","confidence":"medium","title":"DepositQueue cancelDepositRequest uses wrong index","locations":["queues/DepositQueue.sol:98-117"],"claim":"cancelDepositRequest uses latestCheckpoint index for Fenwick tree update instead of the request timestamp index.","impact":"This can cause incorrect accounting in the Fenwick tree, potentially affecting subsequent deposit processing or claim operations.","paths":["1. User has pending deposit request","2. Oracle report is submitted before cancellation","3. cancelDepositRequest uses wrong index","4. Fenwick tree state corrupted"]},{"id":"F-025","severity":"Medium","confidence":"high","title":"ShareModule claimableSharesOf unbounded loop vulnerability","locations":["modules/ShareModule.sol:116-132","modules/ShareModule.sol:234-250"],"claim":"claimableSharesOf and claimShares iterate over all assets and all deposit queues with no pagination or gas limits.","impact":"If the vault has many assets and queues, these functions can exceed gas limits and revert, preventing users from claiming their shares. Additionally, this creates a griefing attack surface where the owner can add many empty queues/assets to make claiming impossible.","paths":["1. Owner adds many assets with many queues","2. User attempts to claim shares","3. Operation reverts due to out-of-gas"]},{"id":"F-026","severity":"High","confidence":"high","title":"Oracle removeSupportedAssets leaves queue states in inconsistent state","locations":["oracles/Oracle.sol:153-164","modules/ShareModule.sol:286-292"],"claim":"When Oracle.removeSupportedAssets is called, the associated queues in ShareModule are not notified and may retain stale state.","impact":"Queues for removed assets will retain stale price data and cannot process new reports, causing deposit/redeem operations to fail or use invalid prices.","paths":["1. Asset is supported and used in queues","2. Asset is removed from Oracle","3. Queue still holds stale price data","4. Subsequent queue operations fail or use invalid prices"]},{"id":"F-027","severity":"Medium","confidence":"high","title":"Signature queues bypass queueLimit cap","locations":["queues/SignatureDepositQueue.sol:11-23","queues/SignatureRedeemQueue.sol:13-27","modules/ShareModule.sol:192-212"],"claim":"Signature queues do not go through ShareModule.createQueue and bypass the queueLimit check entirely.","impact":"An attacker can bypass the vault-wide queue limit by using signature queues, potentially causing gas exhaustion or economic manipulation.","paths":["1. Owner sets queueLimit","2. Attacker deploys signature queue directly","3. queueLimit is bypassed","4. Unlimited signature queues can be created"]},{"id":"F-028","severity":"Medium","confidence":"medium","title":"FeeManager lacks proper initialization guard","locations":["managers/FeeManager.sol:130-144"],"claim":"FeeManager.initialize uses initializer modifier but has no protection against anyone calling it after initial setup if proxy is not properly configured.","impact":"If the proxy admin is compromised or improperly configured, an attacker could re-initialize FeeManager with malicious fee parameters.","paths":["1. FeeManager deployed via proxy","2. Proxy configuration allows reinit","3. Attacker re-initializes with changed fees"]},{"id":"F-029","severity":"Medium","confidence":"medium","title":"Verifier CUSTOM_VERIFIER verificationData parsing off-by-one","locations":["permissions/Verifier.sol:114-119"],"claim":"The CUSTOM_VERIFIER verificationData parsing uses calldataload at verificationData.offset which may read past the provided data if not properly encoded.","impact":"This can cause verification failures or unexpected behavior when using CUSTOM_VERIFIER type.","paths":["1. Attacker crafts malformed verificationData","2. Verification incorrectly succeeds or fails"]},{"id":"F-030","severity":"Medium","confidence":"medium","title":"BasicRedeemHook partial fill causes inconsistent state","locations":["hooks/BasicRedeemHook.sol:9-31"],"claim":"BasicRedeemHook.callHook may partially fill from subvaults but the vault may not have enough to satisfy the full request.","impact":"If partial fill occurs, the vault hook may return without completing the full asset transfer, leading to inconsistent state between vault balance and queue accounting.","paths":["1. Redeem request triggers hook","2. Hook pulls partial assets from subvaults","3. Not enough assets available","4. Queue state becomes inconsistent"]},{"id":"F-031","severity":"Medium","confidence":"medium","title":"LidoDepositHook silent failure on wrap/withdraw","locations":["hooks/LidoDepositHook.sol:29-48"],"claim":"LidoDepositHook.callHook silently continues if wrap or withdraw operations fail, without any error propagation.","impact":"Failed wrap/withdraw operations are silently ignored, causing the hook to proceed with potentially incorrect asset amounts.","paths":["1. Deposit with stETH or WETH","2. wrap/withdraw operation fails silently","3. Hook continues with incorrect balance"]},{"id":"F-032","severity":"Medium","confidence":"high","title":"TokenizedShareManager auto-claim on every transfer creates griefing surface","locations":["managers/TokenizedShareManager.sol:46-55"],"claim":"TokenizedShareManager._update automatically calls claimShares for both sender and recipient on every transfer, even for normal ERC20 transfers.","impact":"This creates a griefing attack where an attacker can force expensive claim operations on every transfer, potentially causing transaction failures.","paths":["1. Attacker knows victim has pending claims","2. Attacker transfers 1 share to victim","3. claimShares iterates all queues","4. Victim forced to pay high gas"]},{"id":"F-033","severity":"Medium","confidence":"medium","title":"Consensus threshold can be zero through threshold validation gap","locations":["permissions/Consensus.sol:86-100","permissions/Consensus.sol:115-122"],"claim":"setThreshold validates threshold > signers.length() but addSigner can call _setThreshold in the same transaction allowing threshold to be set to signers.length() first, then have signer removed in same tx via smart contract.","impact":"In particular deployment patterns, threshold could be manipulated to bypass signature requirements.","paths":["1. Attacker controls signer contract","2. Crafts transaction to bypass threshold","3. Signatures requirement bypassed"]},{"id":"F-034","severity":"Medium","confidence":"medium","title":"Factory.create uses predictable salt enabling front-running","locations":["factories/Factory.sol:103-121"],"claim":"Factory.create uses keccak256(abi.encodePacked(version, owner, initParams, entities.length)) as salt, which is predictable.","impact":"An attacker can front-run create calls to deploy their own proxy with the same implementation, causing the original create to fail or use different address.","paths":["1. Victim calls Factory.create","2. Attacker monitors mempool","3. Attacker front-runs with same params","4. Original create fails or gets different address"]},{"id":"F-035","severity":"High","confidence":"high","title":"VaultConfigurator setVault called in non-atomic sequence enabling hijack","locations":["vaults/VaultConfigurator.sol:49-73"],"claim":"VaultConfigurator.create calls setVault on ShareManager, RiskManager, and Oracle AFTER the Vault is created, in non-atomic sequence.","impact":"If Vault creation succeeds but setVault calls fail (e.g., due to out-of-gas), the managers are left pointing to address(0), enabling initialization hijacking.","paths":["1. VaultConfigurator.create is called","2. Vault created successfully","3. setVault calls fail mid-way","4. Managers left with invalid vault addresses"]}]

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
