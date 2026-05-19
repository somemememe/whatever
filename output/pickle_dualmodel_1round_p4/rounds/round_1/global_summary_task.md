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
- files touched: broad pass across the Solidity tree, with explicit focus on `src/controller-v4.sol`, `src/proxy-logic/uniswapv2.sol`, `src/proxy-logic/curve.sol`, `src/strategies/strategy-base.sol`, `src/strategies/strategy-uni-farm-base.sol`, `src/strategies/curve/strategy-curve-3crv-v2.sol`, `src/strategies/curve/strategy-curve-rencrv-v2.sol`, `src/strategies/curve/strategy-curve-scrv-v4_1.sol`, `src/pickle-swap.sol`, `src/uni-curve-converter.sol`, `src/strategies/curve/scrv-voter.sol`, `src/strategies/curve/crv-locker.sol`, and `src/governance/timelock.sol`
- files revisited / highest-attention files: highest attention on `src/controller-v4.sol` and swap/converter helpers; specifically revisited `src/strategies/curve/strategy-curve-rencrv-v2.sol` to pin exact harvest/liquidity lines before finalizing
- main issue directions investigated: controller-context `delegatecall` during jar swaps; public harvest MEV from zero-min swaps and zero-min liquidity adds; public LP conversion MEV; missing authorization on `SCRVVoter.deposit()`; timelock bootstrap/admin handoff behavior
- promising but not retained directions: none clearly visible beyond the issues that were ultimately retained

## Agent: opencode_1
- files touched: read a broad set including `src/controller-v4.sol`, `src/yield-farming/masterchef.sol`, `src/staking-rewards.sol`, `src/pickle-jar.sol`, `src/uni-curve-converter.sol`, `src/governance/timelock.sol`, `src/strategies/strategy-base.sol`, `src/proxy-logic/uniswapv2.sol`, `src/strategies/strategy-uni-farm-base.sol`, `src/strategies/strategy-staking-rewards-base.sol`, `src/strategies/curve/strategy-curve-3crv-v2.sol`, `src/pickle-swap.sol`, `src/strategies/curve/scrv-voter.sol`, `src/strategies/curve/crv-locker.sol`, `src/strategies/compound/strategy-cmpd-dai-v2.sol`, `src/voting/PicklesInTheCitadel.sol`, and `src/proxy-logic/curve.sol`
- files revisited / highest-attention files: strongest attention appears on controller/swap/strategy surfaces that overlap retained findings, especially `src/controller-v4.sol`, `src/strategies/strategy-base.sol`, `src/pickle-swap.sol`, `src/uni-curve-converter.sol`, `src/scrv-voter.sol`, and `src/crv-locker.sol`
- main issue directions investigated: delegatecall and execution surfaces in controller/strategy components; zero-slippage swap and conversion paths; voter/locker authority flows; governance/timelock handling; additional review of jar, staking, and farming modules
- promising but not retained directions: strategy `execute()`/generic delegatecall risk, governance centralization/admin powers, `pickle-jar` reentrancy/share-pricing concerns, `masterchef` reward-parameter abuse, and several broad privileged-call themes were raised but not kept after merge

## Cross-Agent Status
- main overlap in file/area attention: strong overlap on `src/controller-v4.sol`, `src/proxy-logic/{uniswapv2,curve}.sol`, `src/strategies/strategy-base.sol`, `src/strategies/strategy-uni-farm-base.sol`, `src/pickle-swap.sol`, `src/uni-curve-converter.sol`, `src/strategies/curve/scrv-voter.sol`, `src/strategies/curve/crv-locker.sol`, and `src/governance/timelock.sol`
- notable differences in attention: `codex_1` concentrated on proving exploit paths for retained controller/MEV/voter findings and pinned exact Curve harvest lines; `opencode_1` spread attention more broadly across jar, staking, farming, voting, and compound strategy files, with many extra candidate issues not retained
- underexplored but suspicious files/functions if clearly supported by the logs: `src/pickle-jar.sol`, `src/staking-rewards.sol`, `src/yield-farming/masterchef.sol`, and `src/strategies/compound/strategy-cmpd-dai-v2.sol` received attention in logs/output but produced no retained finding in this round

## Retained Findings
- `swapExactJarForJar()` in `controller-v4.sol` was retained as the top issue: it trusts attacker-controlled jar/converter behavior and can expose controller-held tokens through fake jars and delegatecalled helper gadgets
- public `harvest()` flows were retained as MEV-leaky because reward swaps and reinvestment steps use zero minimums across shared strategy code and several Curve/UNI strategies
- public LP migration/conversion paths in `pickle-swap.sol` and `uni-curve-converter.sol` were retained as user-principal MEV exposure because all legs execute with zero min-out protection
- `SCRVVoter.deposit()` was retained for missing authorization, enabling arbitrary routing of voter/locker-held compatible tokens into attacker-chosen gauges
- the timelock bootstrap admin handoff was retained as a low-confidence governance weakness: the first `setPendingAdmin()` can bypass the intended delay if initialization is still incomplete


Output only markdown.
