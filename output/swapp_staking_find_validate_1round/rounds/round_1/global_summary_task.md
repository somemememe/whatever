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
- `test/ExploitPOC.t.sol` — primary attention on staking `deposit()` / `withdraw()` accounting and liquidity-drain behavior
- `FlawVerifier.sol` — secondary attention on execution/configuration surfaces and swap flow handling
- epoch / `manualEpochInit` surfaces — seen in scope but still lightly explored

## Issue Directions Seen
- Staking accounting trusts requested amounts and token call success too much, creating phantom-credit and unpaid-withdrawal directions
- Insolvency / theft paths depend on later honest liquidity entering after bad accounting state is created
- Token integration assumptions remain a recurring risk area, especially around unchecked `transferFrom()` / `transfer()` behavior
- Verifier execution/configuration misuse and swap/slippage handling were investigated as plausible but not yet retained directions

## Useful Context
- Audit attention so far is concentrated much more on staking balance accounting than on verifier or epoch logic
- The durable cross-round theme is mismatch between internal balances and actual token movement
- Several initially promising variants folded into the same broader pattern: non-standard token behavior can break staking assumptions without immediate reverts
- No multi-agent divergence yet; current memory is shaped by a single round focused on staking paths


## Latest Round Summary
# Round 1 Summary

## Agent: codex
- files touched: `FlawVerifier.sol`, `test/ExploitPOC.t.sol`; a temporary `ReentrancyTmp.t.sol` file was created during exploration and then deleted
- files revisited / highest-attention files: highest attention was on `FlawVerifier.sol` and `test/ExploitPOC.t.sol`, with repeated line-by-line inspection of verifier flow, staking interfaces, and mock staking functions
- main issue directions investigated: deposit/withdraw accounting safety, unsafe ERC20 interaction assumptions, reentrancy via callback-enabled tokens, epoch initialization and arbitrary-token onboarding surface, and verifier helper/drain-round logic
- promising but not retained directions: a reentrancy-based repeated drain path (`withdraw()`/`deposit()` interplay) and permissionless arbitrary-token market creation were surfaced in the agent output but were not retained in the round’s merged findings

## Cross-Agent Status
- main overlap in file/area attention: only one agent logged activity this round, concentrated on `test/ExploitPOC.t.sol` deposit/withdraw behavior and related verifier support code in `FlawVerifier.sol`
- notable differences in attention: no cross-agent differences are available for this round
- underexplored but suspicious files/functions if clearly supported by the logs: `FlawVerifier.sol` helper paths around round execution and epoch checks/init were inspected, but no merged finding from those areas was retained in this round

## Retained Findings
- retained issues focused on unsafe token-transfer handling in `MockStaking`: `deposit()` can over-credit stake without verifying actual receipt of tokens, and `withdraw()` can burn user balances before confirming token payout succeeded
- together, the retained findings describe both insolvency creation on deposit and permanent user loss on withdrawal when interacting with soft-failing or non-standard tokens


Output only markdown.
