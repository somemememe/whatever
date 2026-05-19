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
- files touched: `contracts/StoneVault.sol`, `contracts/strategies/StrategyController.sol`, `contracts/token/Stone.sol`, plus LayerZero OFT/LzApp files and supporting vault/strategy files
- files revisited / highest-attention files: `contracts/StoneVault.sol`, `contracts/strategies/StrategyController.sol`, `contracts/token/Stone.sol`
- main issue directions investigated: instant-withdraw accounting and forced-withdraw sourcing, bootstrap share-price handling before round 1, post-loss/share-price insolvency behavior, round rollover reentrancy via strategy callbacks, LayerZero custom packet handling, strategy registration validation
- promising but not retained directions: none clearly indicated beyond the retained set

## Agent: opencode_1
- files touched: `contracts/StoneVault.sol`, `contracts/AssetsVault.sol`, `contracts/strategies/StrategyController.sol`, `contracts/token/Stone.sol`, `contracts/strategies/Strategy.sol`, `contracts/token/Minter.sol`, `contracts/libraries/VaultMath.sol`, `@layerzerolabs/solidity-examples/contracts/lzApp/LzApp.sol`
- files revisited / highest-attention files: `contracts/StoneVault.sol`, `contracts/strategies/StrategyController.sol`, `contracts/token/Stone.sol`
- main issue directions investigated: instant-withdraw pricing/fee behavior, strategy rebalancing mechanics, strategy address validation, governance/proposal migration controls, cross-chain quota and transfer controls, math edge cases
- promising but not retained directions: instant-withdraw min/max pricing asymmetry, fee bypass on share-based withdrawals, rebalancing slippage, governance/migration centralization issues, quota-griefing and math edge cases

## Cross-Agent Status
- main overlap in file/area attention: strong overlap on `StoneVault.sol`, `StrategyController.sol`, and `Stone.sol`; both agents concentrated on vault withdrawal paths and controller strategy management
- notable differences in attention: `codex_1` pushed deeper into round accounting, insolvency, and LayerZero packet-type handling; `opencode_1` spent more attention on governance/configuration and fee/pricing hypotheses that were not retained
- underexplored but suspicious files/functions if clearly supported by the logs: `AssetsVault.sol`, `Minter.sol`, and `VaultMath.sol` were read but did not produce retained issues this round

## Retained Findings
- retained issues centered on `StoneVault` and `StrategyController`: partial instant-withdraw payouts after full share burns, controller-balance overpayment during forced withdrawals, bootstrap share mispricing before the first round, insolvency-triggered share-price underflow, and rollover reentrancy
- cross-chain handling in `Stone.sol` was retained for broken custom LayerZero admin/feed packets
- strategy onboarding validation in `StrategyController` was retained as a low-severity protocol-wide DoS risk and was the only retained theme supported by both agents


Output only markdown.
