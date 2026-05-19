You maintain a concise global audit memory for future audit agents.

Update the existing global memory by folding in durable observations from the
latest round summary. The goal is an accumulated cross-round audit view, not a
per-round recap.

This memory is optional context only. Findings are stored separately.

Write the updated memory in this exact structure:

# Global Audit Memory

## Scope Touched
- files/contracts/flows that have mattered across rounds, with short issue-direction notes

## Issue Directions Seen
- recurring or promising vulnerability directions seen across the audit

## Useful Context
- compact cross-round observations 

Rules:
- keep it compact
- preserve useful prior context while integrating new durable observations
- prefer stable cross-round patterns over latest-round details
- fold repeated wording into a single clearer observation
- keep the memory descriptive rather than prescriptive

## Existing Global Memory
# Global Audit Memory

## Scope Touched
- Queue lifecycle and claimability path stayed central: `queues/DepositQueue.sol`, `queues/RedeemQueue.sol`, `queues/SignatureRedeemQueue.sol` (queue removal, settle/claim continuity, redeem progression).
- Share mint/allocation control path remained hot: `modules/ShareModule.sol`, `managers/ShareManager.sol`, `interfaces/managers/IShareManager.sol` (mint authority, allocation consumption, post-processing claim effects).
- Role/authorization fallbacks in accounting flows were directly stressed: queue-or-role guarded manager paths (notably `managers/RiskManager.sol`).
- Redeem liquidity accounting touched ETH/native-asset compatibility edges: `libraries/TransferLibrary.sol`, redeem liquidity checks.
- Broader but lighter sweeps continued across fee/oracle/verifier/hooks/factory/consensus/config surfaces; limited retained signal this round.

## Issue Directions Seen
- Confirmed: deposit-queue removal can strand already-processed-but-unclaimed deposits when claim minting still depends on queue authorization.
- Confirmed: ETH-sentinel/native-asset mode can conflict with ERC20 `balanceOf`-based redeem liquidity checks, causing revert-driven processing blockage.
- Confirmed: `onlyQueueOrRole`-style authorization can revert before role fallback, breaking role-authorized emergency accounting calls.
- Recurring high-signal direction: share-allocation/mint authorization boundary misuse across manager/module/queue interactions.
- Recurring direction: redeem batch solvency and claim-time DoS risk when accounting assumes exact asset receipt.
- Still recurring but lower retained signal this round: verifier intent/encoding mismatch, fee/oracle timing races, signature vs standard queue parity.

## Useful Context
- Cross-agent convergence remains strongest on queue/share/risk/redeem-liquidity interactions; deepest retained evidence is concentrated there.
- `ShareModule.sol`, `DepositQueue.sol`, `ShareManager.sol`, and `RiskManager.sol` were repeatedly revisited and continue to be high-context hubs.
- Round-wide broad scans produced many hypotheses, but merged retained outcomes narrowed to three concrete queue/risk/native-asset exploit paths.
- Prior transfer/accounting fragility under non-standard ERC20 behavior remains unresolved context, not clearance.
- Hooks/strategy/factory-adjacent logic has been touched with less depth relative to core queue/share paths; context exists but evidence density is lower.


## Latest Round Summary
# Round 8 Summary

## Agent: codex_1
- files touched  
  `modules/ShareModule.sol`, `modules/VaultModule.sol`, `managers/ShareManager.sol`, plus finding-linked files: `managers/TokenizedShareManager.sol`, `queues/RedeemQueue.sol`, `queues/SignatureDepositQueue.sol`, `queues/DepositQueue.sol`, `oracles/Oracle.sol`
- files revisited / highest-attention files  
  `managers/ShareManager.sol` and queue/manager interaction paths tied to `_update`, `claimShares`, and mint/update checks
- main issue directions investigated  
  lockup/cooldown enforcement ordering, signature-deposit whitelist enforcement parity, blacklist enforcement on transfer recipient, first-report oracle handling for newly added assets
- promising but not retained directions  
  no additional retained candidates beyond the four submitted findings

## Agent: opencode_1
- files touched  
  broad sweep across most in-scope contracts (factories, hooks, libraries, managers, modules, oracle, permissions, queues, strategy, vaults), including `hooks/BasicRedeemHook.sol`, `managers/FeeManager.sol`, `managers/ShareManager.sol`, `oracles/Oracle.sol`, `modules/ShareModule.sol`, `queues/*`
- files revisited / highest-attention files  
  `hooks/BasicRedeemHook.sol` and `managers/FeeManager.sol` were explicitly revisited after initial pass
- main issue directions investigated  
  broad cross-surface scan for auth, role-gating, queue flow, vault/module integration, and hook behavior inconsistencies
- promising but not retained directions  
  `BasicRedeemHook.getLiquidAssets` using `msg.sender` (reported by agent as F-104) was not retained in merged round findings

## Cross-Agent Status
- main overlap in file/area attention  
  managers/queues/share-flow surfaces (`ShareManager`, `TokenizedShareManager`, `Deposit/Redeem` queue interactions) and oracle path review
- notable differences in attention  
  `codex_1` concentrated on concrete exploitable state-transition paths and produced all retained findings; `opencode_1` performed wider one-pass coverage with one non-retained hook-centric issue
- underexplored but suspicious files/functions if clearly supported by the logs  
  `hooks/BasicRedeemHook.sol:getLiquidAssets` remains a flagged-but-unretained hotspot from this round’s logs

## Retained Findings
- Retained set is entirely from `codex_1`:  
  `F-201` high-severity lockup bypass via `_update` check/claim ordering;  
  `F-202` signature-deposit caller whitelist bypass route;  
  `F-203` missing blacklist enforcement on transfer recipient;  
  `F-204` first report for new oracle asset always marked suspicious, creating dependency on `acceptReport`.


Output only markdown.
