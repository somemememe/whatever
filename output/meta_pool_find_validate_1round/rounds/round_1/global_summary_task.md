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
- files touched: `FlawVerifier.sol`; OpenZeppelin proxy/util files including `@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol`, `@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol`, `@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol`, `@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol`, `@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol`, `@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol`, `@openzeppelin/contracts/proxy/Proxy.sol`, `@openzeppelin/contracts/utils/Address.sol`, `@openzeppelin/contracts/utils/StorageSlot.sol`, `@openzeppelin/contracts/access/Ownable.sol`, and related interfaces
- files revisited / highest-attention files: `FlawVerifier.sol` received the most line-by-line attention; `TransparentUpgradeableProxy.sol`, `ProxyAdmin.sol`, and `ERC1967Upgrade.sol` were revisited to rule out local modifications
- main issue directions investigated: exploitability of `FlawVerifier.executeOnOpportunity()` against `TARGET_PROXY`; whether an inherited ERC4626-style `mint(uint256,address)` path could mint mpETH before collecting backing assets; whether the local OZ proxy stack was modified or contributed a distinct issue
- promising but not retained directions: a forced-ETH / balance-based funding-bypass theory tied to `ForceEther.boom`, `_fundingShortfall`, and `TARGET_PROXY.balance` was reported by the agent but not retained after merge; suspected issues in the OZ proxy stack were investigated and effectively ruled out as vanilla

## Cross-Agent Status
- main overlap in file/area attention: this round had a single agent, with attention concentrated on `FlawVerifier.sol` and verification that the included OpenZeppelin proxy files were standard
- notable differences in attention: no cross-agent differences in this round
- underexplored but suspicious files/functions if clearly supported by the logs: the live external `TARGET_PROXY` implementation remains the key unresolved hotspot because the repo only contains the exploit harness in `FlawVerifier.sol`, not the target staking implementation needed to confirm the mint path directly

## Retained Findings
- retained one critical, low-confidence finding: `FlawVerifier.sol` encodes a plausible drain path where a live staking proxy may expose an inherited ERC4626 `mint` route that mints unbacked mpETH, which can then be swapped through the liquid unstake pool for ETH if the external target behaves as assumed


Output only markdown.
