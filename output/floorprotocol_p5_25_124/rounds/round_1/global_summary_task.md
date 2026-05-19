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
- files touched: `src/FloorPeriphery.sol`, `src/FloorGetter.sol`, `src/interface/IFlooring.sol`, with retained-finding attention also on `src/library/OwnedUpgradeable.sol` and `openzeppelin/proxy/ERC1967/ERC1967Proxy.sol`
- files revisited / highest-attention files: `src/FloorPeriphery.sol` was the clear center of attention; upgrade initialization also drew attention through `OwnedUpgradeable.sol` and `ERC1967Proxy.sol`
- main issue directions investigated: periphery asset-flow/accounting across calls, UUPS proxy initialization/ownership takeover risk, and ERC721 receipt/recovery behavior
- promising but not retained directions: broader protocol surface review through `FloorGetter.sol` and `IFlooring.sol` is visible in the logs, but no separate retained issue from those paths survived merge

## Agent: opencode_1
- files touched: `src/FloorPeriphery.sol`, `src/FloorGetter.sol`, `src/Constants.sol`, `src/Errors.sol`, `src/interface/IFlooring.sol`, `src/logic/Structs.sol`, `src/logic/CollectionKey.sol`, `src/library/CurrencyTransfer.sol`, `src/library/ERC721Transfer.sol`, `src/library/OwnedUpgradeable.sol`, `src/logic/SafeBox.sol`, `src/base/Multicall.sol`
- files revisited / highest-attention files: `src/FloorPeriphery.sol` and `src/FloorGetter.sol` received the most visible attention, with targeted greps around approvals, reentrancy, and deadline handling
- main issue directions investigated: approval scope to `floor`, storage exposure via getter patterns, multicall/delegatecall safety, missing reentrancy guards, deadline handling, batch-size DoS, Permit2 handling, and stranded ETH
- promising but not retained directions: unlimited approval concerns, `extsload` exposure, `Multicall` delegatecall risk, generic missing-reentrancy/deadline/DoS themes, and Permit2-related concerns were explored but were not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `src/FloorPeriphery.sol`, especially token/ETH movement, approvals, and external-call paths
- notable differences in attention: `codex_1` produced the retained upgradeability/initialization issue and the trapped-ERC721 issue, while `opencode_1` spread attention more broadly across `FloorGetter`, `Multicall`, helper libraries, and generic control-surface checks
- underexplored but suspicious files/functions if clearly supported by the logs: `src/FloorGetter.sol` and `src/base/Multicall.sol` received attention from `opencode_1` but did not yield retained findings; current status is that they were examined as possible exposure/control hotspots without surviving issues this round

## Retained Findings
- `FloorPeriphery` can mix residual ETH and fragment-token balances across users, allowing later callers to benefit from stranded value
- the periphery’s UUPS deployment path retains an uninitialized-proxy takeover risk if initialization is not performed atomically at deployment
- `FloorPeriphery` accepts direct ERC721 transfers but exposes no rescue path, so mistakenly sent NFTs can become permanently stuck


Output only markdown.
