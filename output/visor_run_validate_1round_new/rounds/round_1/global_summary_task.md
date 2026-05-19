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
- files touched: `contracts/RewardsHypervisor.sol`, `contracts/vVISR.sol`, `contracts/interfaces/IVisor.sol`, `FlawVerifier.sol`, `@openzeppelin/contracts/token/ERC20/ERC20.sol`, `@openzeppelin/contracts/token/ERC20/ERC20Snapshot.sol`, plus an initial file map across in-scope `.sol` files
- files revisited / highest-attention files: `contracts/RewardsHypervisor.sol` was the clear focus; `FlawVerifier.sol` was reopened after an initially truncated read; `contracts/vVISR.sol` and `contracts/interfaces/IVisor.sol` were supporting reads
- main issue directions investigated: `deposit` authorization for EOAs; trust in contract-based depositors via `IVisor`; first-deposit / pre-seeded balance share pricing; donation-driven share inflation and zero-share deposit outcomes
- promising but not retained directions: supporting review of `vVISR`, `FlawVerifier`, and OpenZeppelin ERC20 / snapshot code during exploit validation did not produce separate retained findings in this round

## Cross-Agent Status
- main overlap in file/area attention: only one agent this round, so attention concentrated on `contracts/RewardsHypervisor.sol` and its deposit/share-accounting flow
- notable differences in attention: no cross-agent differences available in this round
- underexplored but suspicious files/functions if clearly supported by the logs: `withdraw` appears in retained exploit paths and cited locations, but the log emphasis remained primarily on `deposit`; `FlawVerifier.sol` was inspected for validation context and not retained as a finding source

## Retained Findings
- retained findings center on four distinct `RewardsHypervisor` failure modes: unauthorized EOA deposits using prior allowances, unbacked share minting through malicious visor contracts, first-depositor capture of pre-initialization VISR, and donation-based share-price manipulation that can zero out or severely dilute later deposits


Output only markdown.
