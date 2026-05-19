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
- files touched: `0xfb772316a54dcd439964b561fc2c173697aeeb5b/Contract.sol`, `0x7f3fe9d492a9a60aebb06d82cba23c6f32cad10b/Contract.sol`
- files revisited / highest-attention files: highest attention on `0xfb772316a54dcd439964b561fc2c173697aeeb5b/Contract.sol`; secondary attention on the proxy fallback in `0x7f3fe9d492a9a60aebb06d82cba23c6f32cad10b/Contract.sol`
- main issue directions investigated: mint/burn share accounting, fee-on-transfer handling in mint and borrow/margin-trade flows, first-mint pricing against pre-seeded assets, proxy low-gas ETH fallback behavior
- promising but not retained directions: ETH minting into non-WETH pools creating unbacked shares was reported by the agent but not retained after merge

## Agent: opencode_1
- files touched: `0xfb772316a54dcd439964b561fc2c173697aeeb5b/Contract.sol`, `0x7f3fe9d492a9a60aebb06d82cba23c6f32cad10b/Contract.sol`
- files revisited / highest-attention files: highest attention on `0xfb772316a54dcd439964b561fc2c173697aeeb5b/Contract.sol`, including a revisit around the later admin/loan logic region
- main issue directions investigated: `updateSettings` arbitrary-call authority, proxy target upgrade risk, `flashBorrow` arbitrary external call path, hardcoded critical addresses, `lowerAdmin` privilege scope, burn transfer handling, oracle dependency
- promising but not retained directions: admin-control / malicious-owner theft paths, flash-loan callback risk, hardcoded-address centralization, oracle concerns, and event/pragma/interface issues were proposed but not retained

## Cross-Agent Status
- main overlap in file/area attention: both agents spent most attention on `0xfb772316a54dcd439964b561fc2c173697aeeb5b/Contract.sol`; both also reviewed the proxy contract
- notable differences in attention: `codex_1` focused on user-flow accounting and asset/share correctness; `opencode_1` focused on privileged admin surfaces, upgradeability, and flash-loan call mechanics
- underexplored but suspicious files/functions if clearly supported by the logs: the proxy/admin control surfaces in `0x7f3fe9d492a9a60aebb06d82cba23c6f32cad10b/Contract.sol` and `updateSettings`/`flashBorrow` in `0xfb772316a54dcd439964b561fc2c173697aeeb5b/Contract.sol` drew attention but did not produce retained findings in this round

## Retained Findings
- retained issues from this round all came from `codex_1`
- the merged set kept four themes: mint over-crediting when actual ERC20 receipts are lower than requested, borrow/margin-trade overstatement when fee-on-transfer tokens are used, first-minter capture of assets already sitting in an uninitialized pool, and the proxy accepting low-gas ETH transfers that bypass logic and strand ETH


Output only markdown.
