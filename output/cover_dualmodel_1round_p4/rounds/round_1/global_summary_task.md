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
- files touched: all in-scope Solidity files were read; deepest inspection centered on `onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol`, with follow-up reads of `Migrator.sol`, `Vesting.sol`, `COVER.sol`, `ERC20/ERC20.sol`, `ERC20/SafeERC20.sol`, `utils/Ownable.sol`, `utils/Address.sol`, `utils/MerkleProof.sol`, and `utils/ReentrancyGuard.sol`
- files revisited / highest-attention files: `Blacksmith.sol` received the most attention by far; `Migrator.sol`, `Vesting.sol`, and `COVER.sol` were the main secondary focus
- main issue directions investigated: staking reward accounting in `deposit()`/`claimRewards()`, bonus-token isolation across pools, fee-on-transfer LP accounting, retroactive reward-parameter changes, migration-cap enforcement in `Migrator.sol`, and arbitrary-token release in `Vesting.sol`
- promising but not retained directions: the stale-accumulator `deposit()` issue was initially framed as affecting both COVER and bonus emissions, but only the COVER-reward variant was retained after merge

## Agent: opencode_1
- files touched: all 17 Solidity files in scope were read, including `Counter.sol`, `FlawVerifier.sol`, the `Blacksmith.sol`/`COVER.sol`/`Migrator.sol`/`Vesting.sol` core contracts, ERC20 helpers, interfaces, and utils
- files revisited / highest-attention files: logs show broad first-pass coverage rather than explicit revisits; candidate findings concentrated on `Blacksmith.sol`, `COVER.sol`, `Migrator.sol`, and `Vesting.sol`
- main issue directions investigated: fee-on-transfer deposit accounting, migrator privilege/minting behavior in `COVER.sol`, emergency-withdraw reward loss, Merkle-claim edge cases, reward precision/truncation, vesting reentrancy, third-party claim triggering, and governance-controlled reward shutdown
- promising but not retained directions: `COVER.sol` migrator self-reassignment/unlimited minting, `Blacksmith.sol` emergency-withdraw reward forfeiture, `Migrator.sol` bitmap overflow and third-party claim griefing, `Vesting.sol` reentrancy, and `Blacksmith.sol` precision-loss / zero-weekly-total concerns were surfaced by this agent but not retained in the merged set

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `Blacksmith.sol`, especially deposit/reward accounting; both also reviewed `Migrator.sol`, `Vesting.sol`, and `COVER.sol`
- notable differences in attention: `codex_1` produced tightly traced economic/accounting findings that largely survived merge, while `opencode_1` cast a wider net across privilege, reentrancy, griefing, and precision themes with fewer retained results
- underexplored but suspicious files/functions if clearly supported by the logs: `COVER.sol` migrator role transitions and `Vesting.sol:vest()` were each flagged by only one agent and not retained; `Counter.sol` and `FlawVerifier.sol` were read but saw no sustained attention in the logs

## Retained Findings
- retained issues center on `Blacksmith.sol` reward-accounting flaws: stale deposit accounting letting new stake capture prior rewards, cross-pool bonus-token balance sharing, fee-on-transfer over-crediting, and retroactive application of changed emission parameters
- non-Blacksmith findings retained were a missing migration-cap check in `Migrator.sol:migrateSafe2()` and arbitrary-ERC20 withdrawal through `Vesting.sol:vest()`
- overlap after merge was strongest on the fee-on-transfer deposit issue; the other retained findings came from `codex_1` only


Output only markdown.
