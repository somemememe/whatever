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
- `hex-otc.sol` — persistent audit center; order creation, discovery, escrow, settlement, and cancellation form the main risk surface
- `hex-otc.sol:newOffer` / `offerETH` / `offerHEX` / `make` — durable concern around offer ID creation, storage bookkeeping, and user-visible/emitted identifiers diverging
- `hex-otc.sol:buyHEX` / `buyETH` / `cancel` — settlement and refund paths remain important because ETH delivery is push-based and recipient behavior affects completion and recovery
- `hex-otc.sol` escrow balance surface — unsolicited ETH/token receipts and stranded-asset behavior were examined as a secondary custody/context area
- `erc20.sol` — supporting file for transfer-semantics, exactness, and token-behavior assumptions rather than a primary standalone source of issues
- `math.sol` — peripheral attention only; no durable issue direction established
- `Contract.sol` — briefly sanity-checked; little enduring audit signal

## Issue Directions Seen
- Order identity / bookkeeping mismatches between stored offers and externally visible IDs, affecting discoverability and normal workflow execution
- ETH settlement liveness risk from fixed-gas `transfer` across maker/taker/cancel payout paths, especially for contract-wallet participants
- Hardcoded HEX token / chain-context assumptions remain a background integration direction, but secondary to lifecycle and payout behavior
- ERC20 exact-transfer assumptions and missing balance-delta validation remain an explored but unconfirmed accounting direction
- Stranded or unsolicited asset handling is a recurring contextual direction around escrowed balances, though not a primary retained issue path so far

## Useful Context
- Audit signal remains concentrated in `hex-otc.sol`; other files mostly provide interface or environmental context
- The strongest cross-round pattern is that risk clusters around workflow integrity, settlement liveness, and custody edges rather than arithmetic complexity
- Creation, fill, escrow, and cancel flows are tightly coupled, so identifier or payout weaknesses tend to propagate through the full order lifecycle
- External dependency trust is simple but rigid: assumptions about the specific HEX token and standard ERC20 behavior shape several secondary directions
- Peripheral files have stayed comparatively low-yield, reinforcing that the contract’s state transitions and payment paths are the main audit lens


## Latest Round Summary
# Round 3 Summary

## Agent: codex
- files touched: `hex-otc.sol`, `erc20.sol`, `math.sol`, `Contract.sol`
- files revisited / highest-attention files: `hex-otc.sol` received the main read-through and line-number follow-up; `erc20.sol` and `math.sol` were checked to validate token-interface and arithmetic assumptions; `Contract.sol` was briefly inspected and identified as JSON data rather than an active Solidity source
- main issue directions investigated: OTC order lifecycle and fund flows; trust assumptions around the hardcoded HEX token address; ERC20 return-value handling in escrow, settlement, and cancellation; token/ETH interaction edge cases
- promising but not retained directions: undercollateralized HEX escrow from recording requested rather than actually received tokens (`F-004` candidate); settlement/cancel paths trusting ERC20 `transfer`/`transferFrom` success without balance-delta verification (`F-005` candidate)

## Cross-Agent Status
- main overlap in file/area attention: only `codex` logged work this round, with attention concentrated on `hex-otc.sol` and its token interaction paths
- notable differences in attention: no cross-agent differences are visible in the provided logs
- underexplored but suspicious files/functions if clearly supported by the logs: `make`, `take`, `offerHEX`, `buyHEX`, `buyETH`, and `cancel` in `hex-otc.sol` were the active hotspots; `math.sol` and `erc20.sol` were only supporting checks, and `Contract.sol` did not appear to be a live contract source in this round

## Retained Findings
- retained after merge: `F-003`, covering the hardcoded HEX token address binding without deployment-chain or code-identity validation, which can make wrong-chain deployments trust attacker-controlled token code and compromise escrow/settlement flows


Output only markdown.
