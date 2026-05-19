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
- files touched: `onchain_auto/0xe7597f774fd0a15a617894dc39d45a28b97afa4f/Contract.sol`, `onchain_auto/src/FlawVerifier.sol`
- files revisited / highest-attention files: highest attention on `Contract.sol`; `FlawVerifier.sol` used to validate exploit paths and relevant line anchors
- main issue directions investigated: caller-controlled `acoToken` trust boundaries, caller-controlled `exchangeAddress` and ETH forwarding, ETH-collateral underfunding against writer balance, whole-balance premium payout instead of per-trade deltas, WETH-withdraw interaction with `receive()`
- promising but not retained directions: no separate discarded line of reasoning is clearly visible beyond source/interface extraction used to support the retained issues

## Agent: opencode_1
- files touched: `onchain_auto/0xe7597f774fd0a15a617894dc39d45a28b97afa4f/Contract.sol`, `onchain_auto/src/FlawVerifier.sol`, `onchain_auto/0xe7597f774fd0a15a617894dc39d45a28b97afa4f/_etherscan_meta.json`
- files revisited / highest-attention files: repeated focus on `Contract.sol`, especially `write()`, `_sellACOTokens()`, and `receive()`
- main issue directions investigated: ETH-strike/WETH-withdraw revert path, public `write()` access, missing `acoToken` validation, unchecked `WETH.withdraw()`
- promising but not retained directions: generic “public write()” access-control concern, generic `acoToken` validation concern, and unchecked-return-value framing were proposed but not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `ACOWriter` in `Contract.sol`, especially `write()`, `_sellACOTokens()`, and the `receive()` gate; both also referenced `FlawVerifier.sol` for exploit confirmation
- notable differences in attention: `codex_1` explored broader accounting and trust-boundary abuse paths that produced the merged critical findings, while `opencode_1` stayed narrower on the WETH/ETH-strike revert and generic validation/access-control concerns
- underexplored but suspicious files/functions if clearly supported by the logs: `ACOWriter` helper flows (`_approveERC20`, `_transferFromERC20`, `_balanceOfERC20`) were part of the retained untrusted-token/accounting issues, but did not receive standalone issue treatment in the logs

## Retained Findings
- Caller-controlled `acoToken` handling was retained as the main asset-theft vector: forged collateral/mint behavior plus untrusted `strikeAsset()` can sweep arbitrary writer-held ERC20 balances.
- Caller-controlled exchange routing and balance accounting were retained as separate fund-loss issues: the writer can forward its full ETH balance to an attacker-controlled exchange target, and later premium settlement can pay out whole contract balances rather than only the current trade’s proceeds.
- ETH funding assumptions were retained as broken in two ways: ETH-collateral writes can consume protocol-held ETH when underpaid, and any residual WETH can brick ETH-strike writes because `receive()` rejects ETH arriving from `WETH.withdraw()`.


Output only markdown.
