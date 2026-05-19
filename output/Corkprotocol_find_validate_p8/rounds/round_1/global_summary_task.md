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
No global memory yet.

## Latest Round Summary
# Round 1 Summary

## Agent: codex
- files touched: `Corkprotocol.sol`
- files revisited / highest-attention files: `Corkprotocol.sol` only; repeated attention on the exploit setup, `unlockCallback`, forged `beforeSwap` calls, and redemption paths
- main issue directions investigated: attacker-controlled module/rate-provider setup; direct swap-hook invocation with forged sender/pool context; CT/DS-to-market binding during redemption; reserve/accounting skew from direct token donations; transient-balance exposure during unlock/settle
- promising but not retained directions: redemption mismatch in `returnRaWithCtDs`; donation-based reserve manipulation; callback-time extraction from transient proxy balances during unlock settlement

## Cross-Agent Status
- main overlap in file/area attention: both codex and merge-review contributed retained findings on permissionless market setup / attacker-controlled rate-provider usage and on direct `CorkHook.beforeSwap` abuse
- notable differences in attention: codex’s visible work stayed anchored to the `Corkprotocol.sol` PoC and produced several extra exploit hypotheses that were not retained, while merge-review uniquely retained the near-expiry HIYA / rollover-pricing issue in `ModuleCore.sol`
- underexplored but suspicious files/functions if clearly supported by the logs: retained findings point to `CorkConfig.initializeModuleCore`, `CorkConfig.issueNewDs`, `ModuleCore.initializeModuleCore`, `ModuleCore.issueNewDs`, `CorkHook.beforeSwap`, and the rollover/HIYA pricing path in `ModuleCore.sol` as current hotspots; the visible codex log did not directly inspect those source files

## Retained Findings
- permissionless market creation / issuance appears to let an attacker register arbitrary redemption assets and an attacker-controlled exchange-rate provider, enabling counterfeit market setup around real protocol assets
- `CorkHook.beforeSwap` appears directly callable without authenticating the Uniswap v4 `PoolManager` context, allowing forged swap metadata to drive privileged hook/router behavior
- rollover initialization appears vulnerable to late-expiry HIYA manipulation, allowing new CT supply to start at a sharply discounted price after a near-expiry premium spike


Output only markdown.
