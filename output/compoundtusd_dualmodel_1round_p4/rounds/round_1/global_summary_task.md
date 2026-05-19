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
- files touched: `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol`, `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CErc20.sol`, `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CErc20Delegate.sol`, `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CTokenInterfaces.sol`, `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/ComptrollerInterface.sol`, `0x12392f67bdf24fae0af363c24ac620a2f67dad86/contracts/CErc20Delegator.sol`, `0x12392f67bdf24fae0af363c24ac620a2f67dad86/contracts/CTokenInterfaces.sol`
- files revisited / highest-attention files: `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol` and `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CErc20.sol`; `0x12392f67bdf24fae0af363c24ac620a2f67dad86/contracts/CErc20Delegator.sol` received targeted delegatecall/implementation review
- main issue directions investigated: `doTransferIn`/`doTransferOut` behavior, live-balance `exchangeRateStoredInternal()` accounting, mint/redeem/borrow/repay/liquidation paths, accrual-linked state flows, and delegator delegatecall/implementation edges
- promising but not retained directions: omitted/disabled Comptroller `*Verify` hooks; delegator upgrade/admin surface was inspected but not retained after merge

## Agent: opencode_1
- files touched: `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol`, `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CTokenInterfaces.sol`, `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CErc20.sol`, `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/ComptrollerInterface.sol`, `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/InterestRateModel.sol`, `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/ErrorReporter.sol`, `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/ExponentialNoError.sol`, `0x12392f67bdf24fae0af363c24ac620a2f67dad86/contracts/CErc20Delegator.sol`, `0x12392f67bdf24fae0af363c24ac620a2f67dad86/contracts/CTokenInterfaces.sol`
- files revisited / highest-attention files: log shows primary reading emphasis on `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol`, `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CErc20.sol`, and `0x12392f67bdf24fae0af363c24ac620a2f67dad86/contracts/CErc20Delegator.sol`
- main issue directions investigated: admin/upgrade authority, reserve factor and reserve reduction controls, interest-rate-model control, liquidation trust in Comptroller, generic precision/reentrancy/transfer-handling concerns
- promising but not retained directions: admin-can-upgrade/admin-can-drain style claims, verify-hook omissions, ERC-777 `sweepToken` reentrancy, compiler pragma/rounding issues, and generic pause/control concerns were proposed but not retained

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol`, `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CErc20.sol`, and `0x12392f67bdf24fae0af363c24ac620a2f67dad86/contracts/CErc20Delegator.sol`
- notable differences in attention: `codex_1` focused on mutable-underlying behavior, live cash/exchange-rate accounting, and transfer-driven state changes; `opencode_1` focused more on admin powers, upgradeability, and generic control-surface risks
- underexplored but suspicious files/functions if clearly supported by the logs: `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CErc20Delegate.sol` and the interface-heavy files in `0x12392f67bdf24fae0af363c24ac620a2f67dad86/contracts/` saw comparatively limited direct analysis; delegatecall/implementation pathways in `CErc20Delegator.sol` were examined but not retained

## Retained Findings
- retained issues all came from `codex_1` and cluster around the protocol’s dependence on raw/live underlying balances and mutable underlying token behavior
- retained findings cover: over-crediting via balance-delta accounting in `doTransferIn`, collateral inflation from unsolicited underlying balance increases, market freeze from negative balance changes underflowing exchange-rate math, and protocol-wide lock risk from underlying transfer controls/blacklisting


Output only markdown.
