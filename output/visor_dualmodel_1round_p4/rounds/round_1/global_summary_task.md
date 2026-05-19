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
- files touched: `contracts/RewardsHypervisor.sol`, `contracts/vVISR.sol`, `contracts/interfaces/IVisor.sol`, `FlawVerifier.sol`, selected OpenZeppelin ERC20 / SafeERC20 / snapshot / EIP712 / ECDSA utilities
- files revisited / highest-attention files: `contracts/RewardsHypervisor.sol` was repeatedly revisited; `FlawVerifier.sol` was used to cross-check exploit mechanics
- main issue directions investigated: contract-path deposits via `IVisor`, first-depositor share initialization, donation-driven share-price manipulation, and share minting based on requested rather than proven received VISR
- promising but not retained directions: a generalized short-transfer / non-standard token over-mint angle was raised separately, but after merge the retained set kept the stronger fake-visor version rather than that broader formulation

## Agent: opencode_1
- files touched: `FlawVerifier.sol`, `contracts/RewardsHypervisor.sol`, `contracts/interfaces/IVisor.sol`, `contracts/vVISR.sol`, plus a broad `**/*.sol` scan
- files revisited / highest-attention files: attention centered on `contracts/RewardsHypervisor.sol`; `contracts/vVISR.sol` also received focused review
- main issue directions investigated: first-depositor drain, unchecked `delegatedTransferERC20` on the contract deposit path, slippage / front-running around deposits, and possible access-control weaknesses in `vVISR`
- promising but not retained directions: the claimed `vVISR` mint/burn access-control failure, a generic post-transfer balance-accounting concern, and withdraw-side validation concerns were explored in output but were not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `contracts/RewardsHypervisor.sol`, especially `deposit()` share pricing, contract-vs-EOA deposit paths, and the relationship between `deposit()` and `withdraw()`
- notable differences in attention: `codex_1` spent more effort validating exploit causality with `FlawVerifier.sol` and separating distinct share-accounting root causes; `opencode_1` spent relatively more attention on `contracts/vVISR.sol` and broader candidate issues that were later discarded
- underexplored but suspicious files/functions if clearly supported by the logs: current visible attention was heavily skewed toward `RewardsHypervisor.deposit()`; `withdraw()` and `contracts/vVISR.sol` were reviewed but did not produce retained findings from the logged work

## Retained Findings
- retained issues center on `RewardsHypervisor` share-accounting and authorization failures: fake or short-paying visor deposits can mint unbacked shares, pre-seeded VISR can be captured by the first depositor, and direct VISR donations can manipulate pricing to under-mint later deposits
- after merge, an additional retained issue was that the EOA deposit path lets any caller pull VISR from another user who has approved the Hypervisor and mint the resulting shares to the attacker


Output only markdown.
