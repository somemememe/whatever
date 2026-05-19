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
- files touched: `0xe7597f774fd0a15a617894dc39d45a28b97afa4f/Contract.sol`
- files revisited / highest-attention files: `0xe7597f774fd0a15a617894dc39d45a28b97afa4f/Contract.sol` with repeated focus on `write`, `_sellACOTokens`, `receive`, and ERC20 helper paths
- main issue directions investigated: WETH unwrap vs `receive()` restrictions, caller-controlled `acoToken` metadata, payout of full contract token/ETH balances, mismatch between mint destination and sale source, and `transfer`-based ETH payout DoS
- promising but not retained directions: none clearly beyond the retained set in this round

## Agent: opencode_1
- files touched: `0xe7597f774fd0a15a617894dc39d45a28b97afa4f/Contract.sol`
- files revisited / highest-attention files: `0xe7597f774fd0a15a617894dc39d45a28b97afa4f/Contract.sol` read multiple times end-to-end
- main issue directions investigated: reentrancy around exchange call/payout, missing SafeMath, `msg.value` / collateral validation, arbitrary `acoToken` acceptance, ERC20/ETH refund handling, and ERC20 return-data assumptions
- promising but not retained directions: reentrancy, overflow/underflow, ETH value mismatch, ERC20-collateral ETH retention, and empty return-data handling were explored but not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated entirely on `0xe7597f774fd0a15a617894dc39d45a28b97afa4f/Contract.sol`, especially the `write` → `_sellACOTokens` flow and trust in caller-supplied `acoToken`
- notable differences in attention: `codex_1` focused on concrete flow/accounting failures in premium delivery and token sale mechanics; `opencode_1` focused more on generic patterns such as reentrancy, SafeMath, and input/value validation
- underexplored but suspicious files/functions if clearly supported by the logs: the low-level ERC20 helper calls in the same file were reviewed indirectly, but only the `acoToken` trust boundary from that area was retained

## Retained Findings
- ETH-strike premium payout can revert because WETH unwrapping sends ETH from the WETH contract, which the restricted `receive()` rejects
- Caller-controlled `acoToken` metadata can redirect arbitrary ERC20 balances already held by the writer to the next attacker-controlled call
- Premium and ETH payout logic uses whole-contract balances, so leftover assets can be drained by a later caller
- Newly minted options go to the user while sale logic only sells the writer’s own balance, breaking the intended write-and-sell flow and exposing stranded ACO balances
- Final ETH payout uses `transfer`, creating a denial-of-service path for contract callers that cannot accept 2300-gas ETH sends


Output only markdown.
