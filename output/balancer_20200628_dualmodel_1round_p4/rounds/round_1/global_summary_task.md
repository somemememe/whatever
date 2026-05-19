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
- files touched: `0x0e511aa1a137aad267dfe3a6bfca0b856c1a3682/Contract.sol`
- files revisited / highest-attention files: embedded `BPool.sol` flows; repeated review of embedded `BMath.sol`; additional review of embedded `BToken.sol`
- main issue directions investigated: pool reserve/accounting drift around joins/swaps/`gulp()`; trust in ERC20 `transfer`/`transferFrom` return values without balance-delta checks; finalized-pool exit failure if a bound token later blocks transfers
- promising but not retained directions: pricing/rounding edge checks in `BMath.sol`; BPT allowance race; incorrect `Approval` event emission in `BToken.sol`

## Agent: opencode_1
- files touched: `0x0e511aa1a137aad267dfe3a6bfca0b856c1a3682/Contract.sol`
- files revisited / highest-attention files: embedded `BPool.sol` dominated attention; embedded `BMath.sol`, `BNum.sol`, and `BToken.sol` were also surfaced in the output and discussed
- main issue directions investigated: `gulp()`-driven token balance manipulation; swap/join accounting behavior; ERC20 transfer-handling assumptions; math safety in `bpow`/`bdiv`; controller power and slippage/MEV themes
- promising but not retained directions: math overflow/division issues in `BNum.sol`/`BMath.sol`; controller-privilege concerns; swap slippage/MEV framing; approval helper edge cases

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on embedded `BPool.sol` token accounting, especially reserve desynchronization around swaps/joins and `gulp()`
- notable differences in attention: `codex_1` stayed focused on concrete asset-accounting and exit-path failures, while `opencode_1` spread attention across math primitives, controller powers, MEV/slippage, and ancillary token mechanics
- underexplored but suspicious files/functions if clearly supported by the logs: embedded `BNum.sol` / `BMath.sol` received explicit scrutiny from both logs but produced no merged finding this round; single-asset exit paths in embedded `BPool.sol` were visible and only partially represented via the finalized-exit lockup finding

## Retained Findings
- The merged round retained a critical reserve-accounting issue: Balancer’s internal balances can diverge from actual token balances for fee-on-transfer, deflationary, or rebasing tokens, and `gulp()` can crystallize that mismatch into exploitable pricing/BPT math
- A high-severity transfer-trust issue was retained from `codex_1`: underlying token transfers are accepted based on boolean success alone, enabling a malicious bound token to fake deposits or short-pay transfers while pool accounting proceeds
- A medium-severity lockup issue was retained from `codex_1`: once finalized, a pool has no built-in recovery path if a bound token later blocks outbound transfers, so proportional exits can fail and strand value


Output only markdown.
