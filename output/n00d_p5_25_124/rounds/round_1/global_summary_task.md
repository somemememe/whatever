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
- files touched: `onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol`
- files revisited / highest-attention files: `onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol` with repeated focus on constructor/default operators, `transfer`/`transferFrom`, `_send`, `_burn`, and operator paths
- main issue directions investigated: ERC777 default-operator authority; ERC20-shaped transfers still triggering ERC777 recipient hooks; sender-side hooks firing before balance updates; also token lock risk from bypassed recipient ack, approval race behavior, and ERC1820 registry dependency
- promising but not retained directions: recipient-ack bypass causing stranded tokens; ERC20 approval race; hard-coded ERC1820 registry as chain-compatibility/DoS risk

## Agent: opencode_1
- files touched: `onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol`
- files revisited / highest-attention files: `onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol`
- main issue directions investigated: ERC777 default-operator privilege model; hook-related transfer blocking behavior; inheritance-based mintability concern
- promising but not retained directions: “unlimited minting through inheritance”; hook-triggered permanent transfer lock / griefing angle

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on the single token file and especially ERC777 operator/hook behavior, with clear overlap on default-operator risk
- notable differences in attention: `codex_1` went deeper on ERC20-entrypoint callback reentrancy and pre-debit sender-hook behavior; `opencode_1` was narrower and also explored inheritance minting and transfer-lock ideas that were not retained
- underexplored but suspicious files/functions if clearly supported by the logs: `onchain_auto/src/FlawVerifier.sol` is referenced in retained findings as a local reentrancy demonstration but is not visibly audited in the logs; deployment-time constructor inputs for `defaultOperators` remain unconfirmed in the available local material

## Retained Findings
- retained after merge: deployment-time default operators may create a protocol-wide transfer/burn backdoor if the live deployment used a non-empty operator list
- retained after merge: ERC20-looking `transfer`/`transferFrom` still execute ERC777 recipient hooks, preserving callback reentrancy risk for integrators that treat the token as plain ERC20
- retained after merge: sender-side ERC777 hooks execute before debiting balances in `_send`/`_burn`, exposing pull and burn integrations to pre-state reentrancy


Output only markdown.
