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
    "title": "Consensus threshold can be bypassed with duplicated signer entries",
    "locations": [
      "permissions/Consensus.sol:23",
      "permissions/Consensus.sol:26",
      "permissions/Consensus.sol:47"
    ],
    "claim": "`checkSignatures` only checks `signatures.length >= threshold` and validates each entry independently, but never enforces signer uniqueness; the same signer/signature can be repeated multiple times to satisfy threshold.",
    "impact": "Any flow secured by `Consensus` (notably signature queues) can be authorized with fewer real signers than configured, collapsing multisig security assumptions and enabling unauthorized mint/redeem operations.",
    "paths": [
      "Set threshold to N>1 with one valid signer S in signer set",
      "Submit `signatures` array containing S repeated N times with valid signature bytes",
      "`checkSignatures` returns true and privileged order executes"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Deposit cancellation uses oracle price as Fenwick index, breaking cancellation and accounting",
    "locations": [
      "queues/DepositQueue.sol:107",
      "queues/DepositQueue.sol:114"
    ],
    "claim": "`cancelDepositRequest` reads the third value from `prices.latestCheckpoint()` into `index`, but for `Trace224` that value is the checkpoint value (stored reduced price), not a request index; this value is then used in `requests.modify(index, -assets)`.",
    "impact": "After reports exist, cancellations revert due out-of-bounds index (price-sized index), locking users out of intended cancellation. Before reports, wrong-index subtraction can corrupt request distribution across time buckets, distorting later processing.",
    "paths": [
      "User creates deposit request after at least one report exists",
      "User calls `cancelDepositRequest` before request becomes claimable",
      "`index` resolves to `priceD18`, `requests.modify` reverts with out-of-bounds"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Transfer whitelist logic is inverted, enabling unauthorized senders and blocking authorized ones",
    "locations": [
      "managers/ShareManager.sol:138",
      "managers/ShareManager.sol:139"
    ],
    "claim": "When transfer whitelist is enabled, the condition `if (info.canTransfer || !$.accounts[to].canTransfer) revert` rejects senders that are marked transferable and permits senders that are not, as long as recipient is marked transferable.",
    "impact": "Compliance/permission controls are reversed: intended-whitelisted senders are blocked while non-whitelisted senders can transfer to whitelisted recipients, defeating transfer restriction policy.",
    "paths": [
      "Enable `hasTransferWhitelist`",
      "Set sender A `canTransfer=false`, recipient B `canTransfer=true`",
      "A can transfer despite not being transfer-whitelisted"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "high",
    "title": "Signature queues ignore global queue pause control",
    "locations": [
      "queues/SignatureDepositQueue.sol:11",
      "queues/SignatureRedeemQueue.sol:13"
    ],
    "claim": "Unlike `DepositQueue`/`RedeemQueue`, signature queue entrypoints do not check `IShareModule(vault).isPausedQueue(address(this))`.",
    "impact": "Emergency pause cannot stop signature-based deposit/redeem flows, allowing continued state changes and asset movement during incidents where governance expects queue-level halt.",
    "paths": [
      "Admin pauses queue via `ShareModule.setQueueStatus(queue, true)`",
      "User still calls `SignatureDepositQueue.deposit` or `SignatureRedeemQueue.redeem` successfully",
      "Assets/shares continue moving despite pause"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Unbounded queue iteration in claim path can gas-DoS transfers/mints/burns",
    "locations": [
      "modules/ShareModule.sol:234",
      "modules/ShareModule.sol:238",
      "modules/ShareModule.sol:242",
      "managers/TokenizedShareManager.sol:46",
      "managers/TokenizedShareManager.sol:49",
      "managers/TokenizedShareManager.sol:52"
    ],
    "claim": "`claimShares` iterates all assets and all deposit queues, and `TokenizedShareManager._update` calls `claimShares` on both sender and receiver during every token movement.",
    "impact": "With many queues/assets, routine transfers and share updates can exceed gas limits and become unexecutable, causing protocol-level liveness failures for tokenized share operations.",
    "paths": [
      "System accumulates many deposit queues across assets",
      "Any ERC20 transfer/mint/burn triggers `_update` -> `claimShares(from/to)`",
      "Nested loops and external queue calls exhaust gas and revert"
    ]
  },
  {
    "id": "F-006",
    "severity": "Low",
    "confidence": "low",
    "title": "One-time `setVault` functions are permissionless and can be initialization-hijacked in non-atomic deployments",
    "locations": [
      "managers/ShareManager.sol:167",
      "managers/RiskManager.sol:147",
      "oracles/Oracle.sol:90"
    ],
    "claim": "`setVault` is externally callable by anyone and only protected by one-time initialization check (`vault == address(0)`), with no caller authorization.",
    "impact": "If components are deployed/configured across multiple transactions (outside the atomic configurator flow), a front-runner can bind them to an attacker-controlled vault and permanently block intended initialization.",
    "paths": [
      "Deploy manager/oracle proxy with unset vault",
      "Attacker calls `setVault(attackerVault)` before legitimate configurator call",
      "Legitimate `setVault` reverts `InvalidInitialization`"
    ]
  }
]

```

### Agent: opencode_1
```
[
  {
    "id": "F-001",
    "severity": "High",
    "confidence": "high",
    "title": "Missing Access Control on setVault in RiskManager",
    "locations": ["managers/RiskManager.sol:147-157"],
    "claim": "The setVault function has no access control, allowing anyone to set the vault address. This is a critical vulnerability as it allows attacker to redirect the RiskManager to a malicious vault.",
    "impact": "Attacker can set vault to a malicious contract and manipulate risk management operations, potentially leading to vault balance manipulation and fund loss.",
    "paths": ["Anyone calls RiskManager.setVault() with malicious vault address"]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Missing Access Control on setVault in Oracle",
    "locations": ["oracles/Oracle.sol:90-100"],
    "claim": "The setVault function has no access control, allowing anyone to set the oracle's vault reference.",
    "impact": "Attacker can hijack the oracle to point to a malicious vault, enabling price manipulation and potentially stealing funds through malicious reports.",
    "paths": ["Anyone calls Oracle.setVault() with malicious vault address"]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Missing Access Control on setVault in ShareManager",
    "locations": ["managers/ShareManager.sol:167-177"],
    "claim": "The setVault function has no access control, allowing anyone to set the share manager's vault reference.",
    "impact": "Attacker can redirect the share manager to a malicious vault, enabling unauthorized share minting/burning and potential fund theft.",
    "paths": ["Anyone calls ShareManager.setVault() with malicious vault address"]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "high",
    "title": "VaultConfigurator.create Has No Access Control",
    "locations": ["vaults/VaultConfigurator.sol:49-73"],
    "claim": "The create function can be called by anyone to deploy new vaults with any configuration.",
    "impact": "Unauthorized users can deploy vaults with custom parameters, potentially creating钓鱼 vaults or DoS the system by creating many vaults.",
    "paths": ["Anyone calls VaultConfigurator.create()"]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "medium",
    "title": "Fee Calculation Can Overflow",
    "locations": ["managers/FeeManager.sol:78"],
    "claim": "The performance fee calculation multiplies performanceFeeD6 (up to 1e6) by totalShares (unbounded), which can overflow.",
    "impact": "Fee calculation returns incorrect values, potentially allowingfee evasion or causing accounting errors.",
    "paths": ["Vault with large totalShares triggers performance fee calculation"]
  },
  {
    "id": "F-006",
    "severity": "High",
    "confidence": "high",
    "title": "VaultModule Missing Subvault Validation in Pull/Push Assets",
    "locations": ["modules/VaultModule.sol:112-127"],
    "claim": "The pullAssets and pushAssets functions do not verify that the subvault is connected to this vault before transferring assets.",
    "impact": "Assets can be pushed/pulled to/from any subvault that's registered in the vault module, even if not properly connected or from a different vault.",
    "paths": ["Attacker registers a malicious subvault, then calls pullAssets/pushAssets"]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "high",
    "title": "SignatureQueue Price Validation Allows Price Manipulation",
    "locations": ["queues/SignatureQueue.sol:110-120"],
    "claim": "The validateOrder function calculates price from order parameters instead of using the oracle's authoritative price. An attacker can set arbitrary requested/ordered values.",
    "impact": "Attacker can manipulate the effective price by setting favorable ordered/requested values, then front-run oracle reports to execute favorable orders.",
    "paths": ["Attacker creates order with manipulated price, front-runs oracle report"]
  },
  {
    "id": "F-008",
    "severity": "Medium",
    "confidence": "high",
    "title": "DepositQueue Deposit Can Be Front-Run",
    "locations": ["queues/DepositQueue.sol:59-95"],
    "claim": "Deposit amounts are visible in the transaction data before execution, allowing MEV bots to front-run large deposits.",
    "impact": "Users may receive worse execution prices due to front-running, extracting value from depositors.",
    "paths": ["User submits large deposit, MEV bot front-runs"]
  },
  {
    "id": "F-009",
    "severity": "Medium",
    "confidence": "high",
    "title": "FeeRecipient Can Be Changed to Any Address",
    "locations": ["managers/FeeManager.sol:90-92"],
    "claim": "The setFeeRecipient function only checks for zero address but has no timelock or additional security.",
    "impact": "Malicious or compromised owner can redirect all fees to an attacker-controlled address.",
    "paths": ["Compromised owner calls setFeeRecipient()"]
  },
  {
    "id": "F-010",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Consensus Allows Signature Replay Across Different Orders",
    "locations": ["permissions/Consensus.sol:21-48"],
    "claim": "The checkSignatures function validates signatures against orderHash but doesn't bind signatures to a specific order context, allowing potential reuse.",
    "impact": "If signatures are leaked or reused incorrectly, they could be replayed on different orders.",
    "paths": ["Attacker obtains signatures and replays on different order"]
  },
  {
    "id": "F-011",
    "severity": "Medium",
    "confidence": "high",
    "title": "RiskManager convertToShares Can Revert on Invalid Price",
    "locations": ["managers/RiskManager.sol:108-119"],
    "claim": "The convertToShares function uses oracle price without checking for extreme values that could cause division issues.",
    "impact": "Extreme or manipulated oracle prices could cause calculations to revert, DoS critical operations.",
    "paths": ["Oracle returns extreme price, convertToShares reverts"]
  },
  {
    "id": "F-012",
    "severity": "Medium",
    "confidence": "medium",
    "title": "BasicRedeemHook Potential Reentrancy in Loop",
    "locations": ["hooks/BasicRedeemHook.sol:16-30"],
    "claim": "The callHook function pulls from multiple subvaults in a loop without reentrancy protection between iterations.",
    "impact": "If subvault pull triggers a callback, reentrancy could occur with inconsistent state.",
    "paths": ["Subvault callback during pullAssets triggers reentrancy"]
  },
  {
    "id": "F-013",
    "severity": "Medium",
    "confidence": "high",
    "title": "LidoDepositHook Unchecked Balance Change",
    "locations": ["hooks/LidoDepositHook.sol:33-43"],
    "claim": "The hook calculates assets converted by checking balance difference before/after operations without verifying wrap/withdraw success.",
    "impact": "If wrap or withdraw operations fail silently, incorrect asset amounts are passed to next hook.",
    "paths": ["stETH wrap or WETH withdraw fails silently"]
  },
  {
    "id": "F-014",
    "severity": "Medium",
    "confidence": "high",
    "title": "ShareModule getLiquidAssets Uses msg.sender Without Verification",
    "locations": ["modules/ShareModule.sol:142-151"],
    "claim": "The getLiquidAssets function trusts msg.sender as a queue but only checks if it's in the queue set.",
    "impact": "Any contract can call getLiquidAssets and potentially view liquid asset information that should be restricted.",
    "paths": ["Attacker calls getLiquidAssets with queue address"]
  },
  {
    "id": "F-015",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Factory create Uses Predictable Salt",
    "locations": ["factories/Factory.sol:113"],
    "claim": "The salt for CREATE2 includes entities.length() which is predictable for a given deployment.",
    "impact": "Pre-computed addresses could allow front-running of vault deployments or deterministic address generation.",
    "paths": ["Attacker predicts salt and front-runs create()"]
  },
  {
    "id": "F-016",
    "severity": "Medium",
    "confidence": "high",
    "title": "TokenizedShareManager Auto-Claims Shares Without Access Control",
    "locations": ["managers/TokenizedShareManager.sol:46-55"],
    "claim": "The _update function automatically claims shares for both from and to addresses without checking if caller is authorized.",
    "impact": "Anyone can trigger claim for any address by making a transfer, potentially griefing users with pending shares.",
    "paths": ["Attacker triggers transfer to call claimShares on victim"]
  },
  {
    "id": "F-017",
    "severity": "Medium",
    "confidence": "medium",
    "title": "EigenLayerVerifier Incomplete delegateTo Verification",
    "locations": ["permissions/protocols/EigenLayerVerifier.sol:60-72"],
    "claim": "The delegateTo verification checks operator role but doesn't verify signature expiry or validity.",
    "impact": "Stale signatures could be used for delegation if operator role is granted.",
    "paths": ["Attacker uses expired signature with valid operator role"]
  },
  {
    "id": "F-018",
    "severity": "Medium",
    "confidence": "medium",
    "title": "RiskManager Limit Check After State Modification",
    "locations": ["managers/RiskManager.sol:206-221"],
    "claim": "The modifyPendingAssets function checks limit after calculating new state but before storage, creating a window.",
    "impact": "In a view function context, the limit appears exceeded but actual storage might differ due to race conditions.",
    "paths": ["Concurrent calls to modifyPendingAssets"]
  },
  {
    "id": "F-019",
    "severity": "Medium",
    "confidence": "low",
    "title": "ShareManager claimShares Can Be Called By Anyone",
    "locations": ["managers/ShareManager.sol:180-182"],
    "claim": "The claimShares function can be called by anyone to claim shares on behalf of any account.",
    "impact": "Anyone can trigger claim operation for any account, potentially causing unnecessary gas usage or griefing.",
    "paths": ["Attacker calls claimShares for many accounts"]
  },
  {
    "id": "F-020",
    "severity": "Low",
    "confidence": "medium",
    "title": "BitmaskVerifier Bitmask Length Validation Bug",
    "locations": ["permissions/BitmaskVerifier.sol:71-73"],
    "claim": "The verification function reverts when bitmask length doesn't match data.length + 0x60, but calculation may be off.",
    "impact": "Legitimate verification calls may fail due to bitmask length mismatch.",
    "paths": ["User provides correct but rejected bitmask"]
  },
  {
    "id": "F-021",
    "severity": "Low",
    "confidence": "medium",
    "title": "RedirectingDepositHook May Leave Assets Undeposited",
    "locations": ["hooks/RedirectingDepositHook.sol:8-26"],
    "claim": "If total maxDeposit across subvaults is less than assets, remaining assets stay in main vault with no notification.",
    "impact": "Users may not realize their deposit wasn't fully allocated, leading to unexpected vault state.",
    "paths": ["Deposit exceeds subvault capacity"]
  },
  {
    "id": "F-022",
    "severity": "Low",
    "confidence": "medium",
    "title": "FeeManager calculateFee Has No Access Control",
    "locations": ["managers/FeeManager.sol:69-85"],
    "claim": "The calculateFee function is public and can be called by anyone.",
    "impact": "Potentially sensitive vault information (fee calculations, price history) could be extracted by anyone.",
    "paths": ["Anyone calls calculateFee"]
  },
  {
    "id": "F-023",
    "severity": "Low",
    "confidence": "medium",
    "title": "ShareModule createQueue Does Not Verify Asset Supported by Oracle",
    "locations": ["modules/ShareModule.sol:192-212"],
    "claim": "The createQueue function checks oracle.isSupportedAsset but this is called after getting the oracle reference from storage.",
    "impact": "If oracle hasn't been set yet, the check might not work correctly.",
    "paths": ["Queue created before oracle fully configured"]
  },
  {
    "id": "F-024",
    "severity": "High",
    "confidence": "high",
    "title": "Verifier setMerkleRoot Has Insufficient Access Control",
    "locations": ["permissions/Verifier.sol:140-142"],
    "claim": "Only SET_MERKLE_ROOT_ROLE is required to change merkle root, but role assignment has no additional controls.",
    "impact": "Compromised role holder can change merkle root to allow arbitrary calls through verification.",
    "paths": ["Compromised SET_MERKLE_ROOT_ROLE holder"]
  }
]

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
