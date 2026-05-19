# Global Audit Memory

## Scope Touched
- `0x765b8d7cd8ff304f796f4b6fb1bcf78698333f6d/Contract.sol`: dominant audit surface so far; attention centered on `doExchange()` and its `issue -> approve -> exchange_underlying -> transfer` path
- `Contract.sol` constructor/external setup: secondary attention area because deployment/runtime behavior depends on bank and Curve integrations
- Cross-bank migration flow (`from_bank` issuance to `to_bank` funding): repeatedly examined for authorization, accounting, and integration assumptions

## Issue Directions Seen
- Public `doExchange()` as the main control-risk direction: permissionless triggering of issuance/migration across external bank contracts
- Economic-extraction direction around Curve usage: `min_dy = 0`, timing/slippage exposure, and flash-loan-assisted price manipulation
- Cross-contract state/accounting assumptions after the swap: whether raw token transfer to the destination bank matches expected deposit/accounting semantics
- External dependency robustness: reliance on hardcoded Curve/bank integrations, external-call behavior, and output/balance assumptions

## Useful Context
- Audit attention has converged strongly on a single contract and mostly a single function, with `doExchange()` treated as the primary risk surface
- The contract’s risk profile is integration-heavy rather than purely internal, combining external bank issuance, token approvals, Curve execution, and post-swap token movement
- Repeated lower-confidence themes include constructor integration safety, unreliable external balance/output signals, and post-swap accounting handoff behavior, but these were not retained as findings in the first round
