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
- `0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol` — dominant audit surface so far; attention centered on initialization/privilege setup, collateral-health accounting, interest accrual around share minting, and borrow/liquidation threshold interactions
- Pool flows: `init`, `lend`, `redeem` / `redeemUnderlying`, `borrow` / `repay`, `liquidation` — repeatedly relevant to state transitions and economic invariant checks
- In-scope utility libraries (`ReentrancyGuard`, `SafeERC20`, `Address`, `SafeMath`, `Counters`, `IERC20`) — noted in scope but not materially explored yet

## Issue Directions Seen
- Privileged setup risk around pool initialization and `onlyCore`-adjacent control assumptions
- Collateral withdrawal validation may rely on pre-transfer balances, creating redeem path accounting gaps
- Interest accrual timing versus lender share minting is a recurring economic dilution/value-capture direction
- Borrow-cap enforcement and liquidation eligibility appear capable of drifting due to mismatched threshold formulas

## Useful Context
- Cross-round attention is currently concentrated almost entirely in `pool.sol`; it is the main source of retained issues so far
- The strongest patterns are economic/accounting inconsistencies rather than library-level implementation bugs
- Health-factor, LTV, and liquidation logic should be viewed together, since multiple issues stem from threshold/accounting mismatch across those paths
- Accrual freshness is an important lens for any flow that mints shares or evaluates solvency


## Latest Round Summary
# Round 1 Summary

## Agent: codex
- files touched: enumerated all scoped Solidity files, with direct inspection concentrated on `onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol`
- files revisited / highest-attention files: `onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol`, especially share-conversion helpers and the `borrow`, `redeemUnderlying`, `liquidateInternal`, and `liquidateMulti` paths
- main issue directions investigated: initializer/control takeover risk; redemption health-check ordering; stale-interest share minting on lend; liquidation-threshold mismatch; rounding/accounting flaws in borrow, redeem, and liquidation flows; batch liquidation netting across token directions
- promising but not retained directions: scoped library files were listed but not developed into separate retained findings in the visible log

## Cross-Agent Status
- main overlap in file/area attention: only one agent is present in this round, so attention is effectively concentrated on `pool.sol`
- notable differences in attention: no cross-agent divergence is visible from the provided logs
- underexplored but suspicious files/functions if clearly supported by the logs: the scoped library files (`ReentrancyGuard.sol`, `IERC20.sol`, `SafeERC20.sol`, `Address.sol`, `Counters.sol`, `SafeMath.sol`) were mapped but not substantively inspected in the visible log; within `pool.sol`, helper-based accounting around `calculateShare` and `getShareByValue` received focused attention and appears to be a recurring hotspot

## Retained Findings
- retained issues span unauthorized pool initialization, redemption health checks using pre-transfer balances, stale-debt share minting on `lend`, and a liquidation threshold mismatch
- the round also retained a broader accounting theme in `pool.sol`: floor-rounded share math lets borrowers, redeemers, and liquidators extract more value than the shares burned or debt assigned
- liquidation logic retained two distinct problems: direct collateral-share underburn during liquidation and cross-token cancellation in `liquidateMulti`
- merged retained findings also include first-borrow debt-share initialization creating orphaned bad debt for position `0`


Output only markdown.
