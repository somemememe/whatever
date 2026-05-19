# Merge View - Round 7

## Summary
- total findings: 18
- new findings: 0
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- existing_preserved: 18

## New Or Updated Findings
- none

## Rejection Reasons
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | codex | Uninitialized clones can be permanently hijacked because `init()` is public and unrestricted | The codebase exposes BentoBox's `deploy(masterContract, data, useCreate2)` interface, which is the expected atomic clone-deploy-plus-init path for these master contracts. The reported risk depends on an unsupported non-atomic deployment flow rather than a realistic protocol path evidenced here. |
| unsupported_or_speculative | codex | Fresh clones expose a pre-init `cook(ACTION_CALL)` window that bypasses the intended BentoBox blacklist | This depends on the same speculative pre-initialization window as the unrestricted-`init()` report. With BentoBox-style atomic deployment/initialization, there is no evidenced period where a live clone exists with empty blacklists, so this is not a reportable protocol issue from the provided code. |
