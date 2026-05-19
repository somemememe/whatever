# Merge View - Round 1

## Summary
- total findings: 0
- new findings: 0
- updated existing findings: 0
- rejected candidates: 5

## Finding Actions
- none

## New Or Updated Findings
- none

## Rejection Reasons
- other: 5

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Arbitrary router target in `routerCallNative` enables theft from users who approved the proxy | `FlawVerifier.sol` is an exploit harness that assumes historical Rubic proxy behavior at hardcoded external addresses; the vulnerable `routerCallNative` implementation is not present in scope, so this repository does not itself evidence a reportable arbitrary-call root cause. |
| other | codex | Provider-aware `routerCallNative` variant also forwards attacker-controlled calldata into token `transferFrom` | Same issue as above: the file only models an attack against an external deployed proxy overload, but the actual provider-aware proxy implementation is absent from the in-scope codebase, so the claim cannot be verified here as a repository finding. |
| other | codex | Zero-input route parameters indicate the downstream call can execute without any real swap funding | This is only an exploit assumption encoded in the verifier contract; without the target proxy implementation, there is no in-scope evidence that zeroed route parameters are accepted, and even if true it would be a facet of the same external arbitrary-call issue rather than a separate finding. |
| other | codex | No withdrawal or rescue path permanently locks all value obtained by `FlawVerifier` | `FlawVerifier` is a one-off exploit/verification contract, not a user-facing protocol component. The lack of a sweep function only strands the exploit contract's own proceeds and does not create realistic protocol-level harm to users. |
| other | codex | Liquidation uses `amountOutMin = 0`, allowing MEV bots to capture most or all proceeds | The zero-slippage swap is part of the exploit monetization path in `FlawVerifier`, so any adverse execution only affects the attacker contract's optional liquidation step rather than protocol funds, solvency, or user assets. |
