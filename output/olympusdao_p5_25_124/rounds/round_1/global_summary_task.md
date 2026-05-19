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
- files touched: read all scoped Solidity files, with repeated attention on `onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol`, `onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/bases/BondBaseTeller.sol`, `onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/ERC20BondToken.sol`, `onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/lib/CloneERC20.sol`, and `onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/lib/TransferHelper.sol`
- files revisited / highest-attention files: `BondFixedExpiryTeller.sol` and `bases/BondBaseTeller.sol`
- main issue directions investigated: mint/redeem flow safety, undeployed bond-token paths, arbitrary token handling in `redeem()`, unchecked transfer behavior, and market-info consistency across `purchase()`
- promising but not retained directions: broader clone/token edge-case review and zero-address external-call sanity checking were explored, but only the purchase/redeem issues above were retained

## Agent: opencode_1
- files touched: read all 17 scoped `.sol` files under `onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156`, including libs, interfaces, and the core teller/token contracts
- files revisited / highest-attention files: emphasis appears on `onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/bases/BondBaseTeller.sol` and `onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol`; targeted grep on `guardian` and `claimFees`
- main issue directions investigated: fee claiming and fee-setting controls, fee-on-transfer token handling, callback settlement checks, ERC20 bond token mint/burn access assumptions, and guardian/auth-role wiring
- promising but not retained directions: `claimFees`, protocol/referrer fee configuration, callback accounting, fee-on-transfer incompatibility, and guardian/Auth mismatch were raised but not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents centered on the teller core, especially `BondFixedExpiryTeller.sol` and `bases/BondBaseTeller.sol`, after reading the full scoped contract set
- notable differences in attention: `codex_1` concentrated on purchase/redeem lifecycle flaws and bond-token deployment/state consistency; `opencode_1` concentrated on fee/accounting/auth surfaces and token-behavior edge cases
- underexplored but suspicious files/functions if clearly supported by the logs: callback/fee-setting surfaces in `bases/BondBaseTeller.sol` and auth assumptions around `src/ERC20BondToken.sol` were investigated but ended the round unretained rather than resolved

## Retained Findings
- `redeem()` accepts an arbitrary token contract and can be abused to transfer out any ERC20 balance currently held by the teller
- purchases for future-dated markets can complete before the corresponding bond token is deployed, leaving buyers with no minted claim token
- `redeem()` burns bond tokens before an unchecked ERC20 transfer, so false-return payout tokens can cause permanent user loss
- `purchase()` prices using one market snapshot and settles using a later snapshot, creating a mutation window if the auctioneer changes market metadata


Output only markdown.
