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
# Global Audit Memory

## Scope Touched
- `FlawVerifier.sol` — dominant audit surface; `executeOnOpportunity()` and related swap / asset-handling logic remain the main source of execution-control, custody, and trade-safety review
- `FlawVerifier.sol` hardcoded counterparty / chain-context path — revisited as a recurring concern around mainnet-specific assumptions and missing environment validation
- `FlawVerifier.sol` AAVE approval / preparation path — repeatedly examined for broad approval exposure to external targets, though not yet a retained issue area
- `Counter.sol` — lightly reviewed across rounds; permissionless state mutation remains more of a low-severity / design-surface note than a primary audit direction

## Issue Directions Seen
- Asset custody / recoverability weaknesses in prefunded verifier flows, especially stranded ETH or residual token balances without a recovery path
- Open execution surfaces where arbitrary callers can trigger treasury-backed or prefunded strategy execution at unintended times
- Economically unsafe swap configuration, especially zero-minimum-output trades that invite slippage, sandwiching, and MEV extraction
- Execution fragility from brittle timing assumptions around AMM interactions, making transactions easier to fail or censor under ordinary delay
- Chain-environment mismatch and hardcoded counterparty assumptions, especially use of mainnet-specific addresses without explicit validation
- Broad approval-scope risk, particularly unlimited approvals granted to external targets during setup or execution

## Useful Context
- Audit attention remains heavily concentrated in `FlawVerifier.sol`; it is still the primary cross-round risk surface
- The most durable pattern is operational-safety risk created by combining prefunding, permissionless triggering, swap brittleness, and external approvals in one flow
- Most meaningful observations are about execution design and integration trust boundaries rather than arithmetic or isolated coding mistakes
- `Counter.sol` stays comparatively underexplored and low-signal versus the verifier flow
- Recent manual edge-case review broadened confidence in the explored fund-flow / execution areas, but did not materially expand the set of durable issue directions beyond approvals, chain assumptions, and execution safety


## Latest Round Summary
# Round 3 Summary

## Agent: codex
- files touched: `FlawVerifier.sol`, `Counter.sol`
- files revisited / highest-attention files: `FlawVerifier.sol` received the clear majority of attention, especially the runtime dependency reads, approval flow, withdrawal path, and profit-check logic; `Counter.sol` was only briefly checked
- main issue directions investigated: hardcoded/external dependency trust boundaries, target-supplied token/pool/reward values, unlimited ERC20 approval scope, native-balance-based profit validation, and basic access control/state integrity in `Counter.sol`
- promising but not retained directions: chain/code validation for hardcoded addresses (`F-004`), spoofable ETH profit accounting (`F-008`), and unrestricted `Counter.sol` mutability (`F-009`) were surfaced in the agent output but were not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: this round’s attention was concentrated almost entirely on `FlawVerifier.sol`, particularly `executeOnOpportunity()` and `_prepareNonZeroAaveInput()`
- notable differences in attention: no cross-agent divergence is present in the logs because only `codex` appears for this round; `Counter.sol` received minimal review compared with `FlawVerifier.sol`
- underexplored but suspicious files/functions if clearly supported by the logs: `Counter.sol` appears underexplored relative to `FlawVerifier.sol`; within `FlawVerifier.sol`, the target-controlled dependency reads and approval/withdrawal flow were the active hotspots

## Retained Findings
- retained focus stayed on `FlawVerifier.sol` trusting `TARGET` for critical runtime addresses (`aave()` and `pool()`), creating exposure if the target is malicious, misconfigured, or upgraded unexpectedly
- retained focus also included the persistent max AAVE allowance granted to `TARGET`, which can extend risk beyond the intended seed deposit and expose the verifier’s broader token inventory


Output only markdown.
