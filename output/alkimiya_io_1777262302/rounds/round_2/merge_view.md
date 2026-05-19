# Merge View - Round 2

## Summary
- total findings: 2
- new findings: 0
- updated existing findings: 0
- rejected candidates: 6

## Finding Actions
- existing_preserved: 2

## New Or Updated Findings
- none

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 3
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | codex | Pool lifecycle actions appear callable with attacker-forged parameters | Unsupported by the available source: `FlawVerifier` only issues unchecked low-level calls to an external address and ignores the return values, so the code does not show that `startPool`/`endPool` actually succeed for attacker-chosen parameters. |
| other | codex | Pools can apparently be started and ended in the same transaction | Same issue as above: the PoC attempts back-to-back calls, but without the target contract or execution evidence there is no proof that both calls can succeed in one transaction. |
| other | codex | Predictable pool parameter space enables protocol-wide brute-force sweeping | The hardcoded loops only show one guessed search strategy inside the PoC; they do not establish that the underlying protocol keys pools solely by these parameters or that enumeration is actually sufficient to sweep real pools. |
| duplicate_or_subsumed | codex | The exploit entrypoint is permissionless and trivially front-runnable | Anyone can call `executeOnOpportunity()`, but the caller does not receive the proceeds; front-running only triggers the same contract path and is largely subsumed by the existing locked-funds issue rather than creating a distinct theft vector. |
| unsupported_or_speculative | codex | The exhaustive 1,800-call sweep can become unexecutable from gas exhaustion | Too speculative and mainly affects this PoC's own execution path. The available code does not show the callee gas cost, and any failure here does not by itself demonstrate protocol-level fund loss or permissionless DoS. |
| other | codex | Counter state is completely attacker-controlled | `Counter.sol` is a standalone toy/template contract with no integration shown anywhere else in the codebase; unrestricted setters here are expected and not a reportable protocol issue on the available evidence. |
