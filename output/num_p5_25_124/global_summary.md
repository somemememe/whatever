# Global Audit Memory

## Scope Touched
- `onchain_auto/0x765277eebeca2e31912c9946eae1021199b39c61/Contract.sol` — core attention stays on cross-chain swap/bridge entrypoints, especially `anySwapOutExact*` / `anySwapInExact*`, permit-assisted outflows, and source-burn vs destination-execution behavior
- MPC transition logic in the same contract (`_newMPCEffectiveTime`, `_oldMPC`, `mpc()` change flow) — reviewed as a secondary governance/control-plane risk area, but not yet established as a retained issue
- Batch `anySwapOut` / `anySwapIn` helpers in the same contract — lightly explored for validation and array-handling edge cases, still lower-confidence than the main trade-flow issues

## Issue Directions Seen
- Permit and transfer-permit entrypoints are a recurring abuse surface: valid signatures may be reusable by unintended callers to steer recipient, route, or chain selection
- Cross-chain “Exact” trade flows repeatedly center on irreversible source-side burn/lock before destination execution, creating fund-loss risk when downstream execution fails
- Deadline handling is a durable theme: user intent can expire on the source side while destination-side execution remains live later
- Inbound execution replayability around `anySwapIn*` and bridge transaction identifiers was investigated and remains a noteworthy direction even though it was not retained this round
- MPC transition timing and authority handoff remain a background direction, with potential security impact if role changes or grace periods interact poorly with privileged flows

## Useful Context
- Audit attention is concentrated almost entirely in a single contract, so cross-function interactions inside that file matter more than file-to-file boundaries
- Both agents converged on the same high-value area: cross-chain trade entrypoints and the consequences of separating source-side asset destruction from destination-side execution success
- The strongest cross-round pattern is mismatch between user-signed/user-supplied intent at initiation and what is actually enforced or recoverable after bridging
- Permit abuse, destination failure without recovery, and deadline desynchronization currently form the clearest durable issue cluster
- MPC-transition and batch-helper paths are comparatively underexplored and remain useful secondary surfaces for future rounds
