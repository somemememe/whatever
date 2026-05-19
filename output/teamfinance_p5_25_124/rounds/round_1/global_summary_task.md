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
- files touched: `onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol`, `onchain_auto/0xe2fe530c047f2d85298b07d9333c05737f1435fb/Contract.sol`, `onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/node_modules/@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol`, `onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/node_modules/@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol`
- files revisited / highest-attention files: `LockToken.sol` received the main end-to-end review and targeted line checks; `Ownable.sol` and `Initializable.sol` were revisited to confirm initializer ownership behavior
- main issue directions investigated: proxy/initializer takeover risk, owner-controlled `recoverAssets()` seizure path, arbitrary-recipient lock griefing via `depositsByWithdrawalAddress`, unconditional ERC721 receipt causing stuck NFTs, referral fee miscalculation, and proxy initialization context via `Contract.sol`
- promising but not retained directions: broader `Contract.sol` review was used to support initialization context, but no separate retained proxy-upgrade finding survived merge

## Agent: opencode_1
- files touched: `onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol`, `onchain_auto/0xe2fe530c047f2d85298b07d9333c05737f1435fb/Contract.sol`, `onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/interfaces/IUniswapV3PositionManager.sol`, `onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/interfaces/IERC721Extended.sol`
- files revisited / highest-attention files: `LockToken.sol` and `Contract.sol` were the clear focus
- main issue directions investigated: owner theft via `recoverAssets()`, proxy admin upgrade control, NFT withdrawal / burn ordering, split-lock timing behavior, fee-setting and referral/referrer edge cases, company wallet handling, whitelist admin powers, and array/accounting consistency
- promising but not retained directions: several additional `LockToken.sol` concerns were proposed but not retained after merge, including proxy `upgradeTo`, NFT burn/transfer ordering, `splitLock`, fee-config edge cases, and bookkeeping/event-reporting issues

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `LockToken.sol`, with shared attention on the owner-only `recoverAssets()` path; both also reviewed `Contract.sol`
- notable differences in attention: `codex_1` spent more effort on initializer/ownership flow, arbitrary-recipient deposit-list DoS, NFT receiver behavior, and referral math; `opencode_1` spent more effort on withdrawal sequencing, upgrade admin behavior, and configuration/validation edge cases
- underexplored but suspicious files/functions if clearly supported by the logs: non-`LockToken.sol` interface files saw only light review; within scope, `Contract.sol` was examined by both agents but only retained as initialization context rather than as a standalone merged issue

## Retained Findings
- retained issues center on `LockToken.sol`: uninitialized proxy deployment can be claimed by the first initializer, `recoverAssets()` acts as an owner seizure backdoor, arbitrary-recipient dust locks can bloat victim exit paths, direct ERC721 transfers can strand NFTs, and referral fee math materially undercharges when the referral path is used


Output only markdown.
