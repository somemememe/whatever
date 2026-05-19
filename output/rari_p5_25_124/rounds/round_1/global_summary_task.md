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

## Agent: codex_1
- files touched: `onchain_auto/0x3f2d1bc6d02522dbcdb216b2e75edddafe04b16f/Contract.sol`, `onchain_auto/0xe16db319d9da7ce40b666dd2e365a4b8b3c18217/Contract.sol`, both `_etherscan_meta.json` files; also enumerated repo files
- files revisited / highest-attention files: highest attention was `onchain_auto/0xe16db319d9da7ce40b666dd2e365a4b8b3c18217/Contract.sol`
- main issue directions investigated: unrestricted oracle pricing, rewards distributor reentrancy / transfer-failure handling, distributor-hook DoS on core market actions, reservoir silent-transfer accounting, and admin / upgrade control paths in the other scoped contract
- promising but not retained directions: Unitroller auto-implementation hot-swap and hardcoded `fuseAdmin` superuser control were raised by this agent but not retained after merge

## Agent: opencode_1
- files touched: `onchain_auto/0x3f2d1bc6d02522dbcdb216b2e75edddafe04b16f/Contract.sol`, `onchain_auto/0xe16db319d9da7ce40b666dd2e365a4b8b3c18217/Contract.sol`, `FlawVerifier.sol`
- files revisited / highest-attention files: emphasis appears to be on `onchain_auto/0xe16db319d9da7ce40b666dd2e365a4b8b3c18217/Contract.sol` and its oracle/liquidation behavior
- main issue directions investigated: missing access control on oracle price setters and the downstream liquidation/solvency consequences of oracle manipulation
- promising but not retained directions: a separate comptroller-side liquidation finding based on the same unsecured oracle theme was proposed, but the merged round retained the oracle root cause instead

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `onchain_auto/0xe16db319d9da7ce40b666dd2e365a4b8b3c18217/Contract.sol`, especially the oracle pricing surface
- notable differences in attention: `codex_1` went much broader into rewards, distributor hooks, reservoir behavior, and admin/upgrade control; `opencode_1` stayed narrow and oracle-centric, with an extra read of `FlawVerifier.sol`
- underexplored but suspicious files/functions if clearly supported by the logs: `onchain_auto/0x3f2d1bc6d02522dbcdb216b2e75edddafe04b16f/Contract.sol` received comparatively less cross-agent scrutiny, while its upgrade/admin-control paths were only surfaced by one agent

## Retained Findings
- retained issues center on `onchain_auto/0xe16db319d9da7ce40b666dd2e365a4b8b3c18217/Contract.sol`
- merged findings kept the critical unrestricted `SimplePriceOracle` pricing issue
- merged findings also kept three rewards/distribution accounting issues: reentrant reward claims, silent reward-transfer failure clearing accruals, and reservoir drip accounting advancing despite failed transfers
- the round additionally retained a comptroller-level DoS risk where a reverting rewards distributor can brick core market actions once added


Output only markdown.
