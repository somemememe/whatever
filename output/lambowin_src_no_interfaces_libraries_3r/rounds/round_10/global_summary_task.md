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
- Core recurring scope: `VirtualToken.sol`, `LamboFactory.sol`, `LamboVEthRouter.sol`, and `rebalance/LamboRebalanceOnUniwap.sol`, with emphasis on debt accounting, launch wiring, cashout/redemption routes, and rebalance sizing/execution bounds.
- Supporting structural scope: `LamboToken.sol`, `Utils/LaunchPadUtils.sol`, and Uniswap V2 pair/router-facing interfaces; repeatedly used to validate end-to-end assumptions.
- Durable high-value flow lens: factory authorization and launch mechanics -> virtual debt mint/repay + transfer constraints -> router swap/cashout paths -> LP burn/withdrawal behavior and rebalance interactions.

## Issue Directions Seen
- Debt-authority/accounting drift remains the strongest direction: factory-authorized debt operations can violate borrower/pair isolation and create pair balance-vs-reserve desync surfaces.
- Debt-floor transfer constraints on launch pairs are now a confirmed durability point: retained `F-020` shows launch-pair vETH debt locking can make publicly provided LP effectively non-burnable (withdrawal lock risk).
- Rebalance-control drift remains durable: permissionless execution can accept caller-chosen sizing beyond preview-intended bounds while still passing validity checks.
- Router boundary weakening remains recurring: composable quoteToken/vETH routing can erode whitelist/redemption intent if boundary assumptions are weak.
- Liquidity lifecycle assumptions remain fragile: Uniswap V2 protocol-fee (`feeTo`) mint behavior can invalidate naive LP-burn finality assumptions.

## Useful Context
- Cross-round convergence continues to favor invariant/boundary failures (authorization, accounting-state sync, execution bounds, transfer constraints) over isolated arithmetic tuning.
- Round 9 reinforced existing hotspots; no clearly new hotspot emerged outside established debt-loan/debt-floor and rebalance-size surfaces.
- Tooling/compile environment friction appeared in Round 9 but was not retained as a security direction.


## Latest Round Summary
# Round 10 Summary

## Agent: codex_1
- files touched: `LamboFactory.sol`, `LamboToken.sol`, `LamboVEthRouter.sol`, `VirtualToken.sol`, `Utils/LaunchPadUtils.sol`, `rebalance/LamboRebalanceOnUniwap.sol`, plus supporting `interfaces/**` and `libraries/**` reads
- files revisited / highest-attention files: `LamboVEthRouter.sol` (primary), `rebalance/LamboRebalanceOnUniwap.sol`, `LamboToken.sol`
- main issue directions investigated: router fee mechanics vs slippage protection in initial buy flow; per-call fee rounding; implementation-contract initialization exposure; rebalance approval/allowance lifecycle to OKX proxy
- promising but not retained directions: fee-rounding bypass (`F-022`), implementation self-initialize confusion (`F-023`), residual approve risk in rebalancer (`F-024`)

## Agent: opencode_1
- files touched: all in-scope Solidity files, plus `libraries/UniswapV2Library.sol` and `interfaces/Uniswap/IPool.sol`; also read prior round summary
- files revisited / highest-attention files: broad pass across all in-scope files, with notable focus on `LamboToken.sol`, `LamboFactory.sol`, `LamboVEthRouter.sol`, `VirtualToken.sol`, `rebalance/LamboRebalanceOnUniwap.sol`
- main issue directions investigated: `initialize()` access/front-run concerns; factory loan flow assumptions; router pair existence/empty-liquidity handling; rebalance minimum amount behavior; `cashIn` value-handling concerns
- promising but not retained directions: clone-token initialize front-run path, `takeLoan` return-validation concern, router pair-existence check concern, low-amount rebalance griefing, `cashIn` mixed ETH/ERC20 path concern

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `LamboVEthRouter.sol` and launch/buy flow behavior, and both reviewed full core contract set
- notable differences in attention: codex_1 centered on fee/slippage semantics and ownership-controlled fee effects; opencode_1 emphasized initialization race-style claims and generic validation gaps across factory/router/rebalance
- underexplored but suspicious files/functions if clearly supported by the logs: `rebalance/LamboRebalanceOnUniwap.sol` approval lifecycle remained a low-confidence concern; `LamboToken.initialize` behavior remained contentious (implementation-vs-clone risk framing differed)

## Retained Findings
- `F-021` retained: in `LamboVEthRouter`, `createLaunchPadAndInitialBuy` hardcodes `minReturn=0` while owner-controlled fee updates can drastically reduce effective swap input, enabling dust outcomes (and at max fee, buy-path DoS) without caller slippage-floor protection.


Output only markdown.
