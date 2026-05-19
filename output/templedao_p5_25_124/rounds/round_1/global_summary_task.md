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
- files touched: `onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol`, `onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol`, `onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/@openzeppelin/contracts/utils/Address.sol`, plus scoped file listing for the included OZ contracts
- files revisited / highest-attention files: `onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol` was the clear focus, with repeated reads around staking, withdrawal, rewards, and migration paths
- main issue directions investigated: untrusted migration flow in `migrateStake`, stake accounting vs actual tokens received, reward funding/accounting vs actual transfers, reward-rate truncation/dust, and gas growth from unbounded `rewardTokens`
- promising but not retained directions: reviewed OZ transfer helpers (`SafeERC20`, `Address`) and adjacent token-interaction edge cases, but no separate retained issue was attributed to the library files themselves

## Agent: opencode_1
- files touched: `onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol`, `onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/@openzeppelin/contracts/token/ERC20/IERC20.sol`, `onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/@openzeppelin/contracts/token/ERC20/ERC20.sol`, and its round output file
- files revisited / highest-attention files: `onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol` dominated attention
- main issue directions investigated: token-callback/reentrancy theories, arbitrary migration target risk, reward distributor / migrator configuration edge cases, unrestricted `stakeFor`, reward token validation, reward precision loss, and growth of the reward-token list
- promising but not retained directions: callback-based reentrancy, zero-address distributor/migrator handling, `stakeFor` griefing, reward-token validation/eventing, and other config-oriented concerns were raised by this agent but not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol`, especially `migrateStake`, reward scheduling, reward rounding, and the unbounded `rewardTokens` array
- notable differences in attention: `codex_1` emphasized accounting mismatches tied to token transfer semantics and checked OZ helper code; `opencode_1` emphasized broader callback/reentrancy and admin/configuration edge cases
- underexplored but suspicious files/functions if clearly supported by the logs: current logs show some attention on `setRewardDistributor`, `setMigrator`, and reward-token admission paths, but these areas were not retained as findings in this round

## Retained Findings
- retained issues center on `StaxLPStaking.sol`: a critical arbitrary-source migration flaw that can mint unbacked stake, accounting assumptions that over-credit stake or rewards when transfers deliver less than requested, reward-rate truncation that can strand deposits, and unbounded reward-token iteration that can gas-brick core user flows


Output only markdown.
