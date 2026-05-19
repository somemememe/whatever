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

## Agent: codex
- files touched: main protocol/token files and helpers, centered on `0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/token/Usd0PP.sol`, `0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/interfaces/token/IUsd0PP.sol`, `0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/constants.sol`, plus OZ helper files `.../SafeERC20.sol` and `.../Address.sol`
- files revisited / highest-attention files: `Usd0PP.sol` was the clear focus, with repeated attention to `IUsd0PP.sol` for interface/spec comparison
- main issue directions investigated: bond mint/deconstruct/reconstruct and unwrap flows; upgrade/reinitializer and dependency initialization safety; helper-call semantics for token interactions; spec/code mismatches around bond timing and early-unlock behavior
- promising but not retained directions: the “burn USUAL” path appearing to transfer rather than burn USUAL, and the documented `bondStart` mint gate not being enforced before start time

## Cross-Agent Status
- main overlap in file/area attention: only one agent participated; attention was concentrated on `Usd0PP.sol` and its interface
- notable differences in attention: no cross-agent differences in this round
- underexplored but suspicious files/functions if clearly supported by the logs: `unlockUSD0ppWithUsual`, `sweepFees`, and the bond-start gating path remained active areas of scrutiny in the log, but were not retained after merge

## Retained Findings
- retained high-severity issues both center on `Usd0PP.sol`: an unprotected `initializeV3` reinitializer that can let a frontrunner seize the `rtusd0` dependency during a mis-sequenced upgrade, and a split-claim design flaw where `bUSD0` redemption paths release backing without requiring the paired `rtUSD0` to be burned


Output only markdown.
