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
- files touched: broad Solidity sweep, with explicit reads of `contracts/MasterChef.sol`, `contracts/Migrator.sol`, `contracts/SushiMaker.sol`, `contracts/SushiRoll.sol`, `contracts/SushiToken.sol`, `contracts/SushiBar.sol`, `contracts/Timelock.sol`, `contracts/BoringOwnable.sol`, and core `contracts/uniswapv2/*` files
- files revisited / highest-attention files: `contracts/MasterChef.sol`, `contracts/Migrator.sol`, `contracts/SushiMaker.sol`, `contracts/SushiBar.sol`, `contracts/SushiToken.sol`, `contracts/BoringOwnable.sol`
- main issue directions investigated: MasterChef LP custody and reward accounting, migrator trust, SushiBar share pricing/bootstrap state, SushiMaker fee flow into SushiBar, SushiToken governance delegation accounting, BoringOwnable ownership handoff
- promising but not retained directions: `contracts/Timelock.sol`, `contracts/SushiRoll.sol`, and reviewed `contracts/uniswapv2/*` paths did not produce retained findings in this round

## Agent: opencode_1
- files touched: `contracts/MasterChef.sol`, `contracts/SushiMaker.sol`, `contracts/SushiRoll.sol`, `contracts/Timelock.sol`, `contracts/SushiToken.sol`, `contracts/SushiBar.sol`, `contracts/Migrator.sol`, `contracts/uniswapv2/UniswapV2Pair.sol`, `contracts/uniswapv2/UniswapV2Router02.sol`, `contracts/uniswapv2/libraries/UniswapV2Library.sol`, `contracts/mocks/SushiMakerExploitMock.sol`, `contracts/BoringOwnable.sol`
- files revisited / highest-attention files: `contracts/MasterChef.sol`, `contracts/SushiMaker.sol`, `contracts/Timelock.sol`, `contracts/SushiRoll.sol`
- main issue directions investigated: MasterChef migrator exposure and reward payout behavior, SushiMaker swap/conversion logic and EOA gating, Timelock execution authority, SushiRoll migration slippage, SushiBar rounding/share mechanics
- promising but not retained directions: SushiMaker swap formula, Timelock arbitrary execution / ETH receipt, SushiRoll slippage, MasterChef dev-fee and `safeSushiTransfer` behavior, SushiBar rounding, and `onlyEOA` bypass ideas were proposed but not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: strongest overlap was around `contracts/MasterChef.sol` + `contracts/Migrator.sol`; both also reviewed `contracts/SushiMaker.sol`, `contracts/SushiBar.sol`, `contracts/SushiToken.sol`, `contracts/SushiRoll.sol`, and `contracts/Timelock.sol`
- notable differences in attention: `codex_1` concentrated more on retained protocol-state issues around governance, xSUSHI economics, ownership, reentrancy, and fee-on-transfer accounting; `opencode_1` spent more visible attention on Timelock, SushiRoll, Uniswap swap math, and the exploit mock
- underexplored but suspicious files/functions if clearly supported by the logs: `contracts/Timelock.sol`, `contracts/SushiRoll.sol`, and adjacent Uniswap migration/swap code received review from one or both agents but ended the round without merged findings

## Retained Findings
- retained issues centered on MasterChef and closely connected components: malicious migrator-driven LP theft, reentrant reward double-claim risk, and fee-on-transfer accounting insolvency
- governance/accounting findings were also retained: `SushiToken` transfer paths do not update delegated voting power
- xSUSHI/SushiBar economics produced two retained findings: bootstrap-balance capture by the first minter and short-term fee capture around SushiMaker conversions
- ownership handling also yielded a retained issue: stale `pendingOwner` in `BoringOwnable` can later seize `SushiMaker` after a direct transfer


Output only markdown.
