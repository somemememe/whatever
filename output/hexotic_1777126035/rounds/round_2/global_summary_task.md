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
- `hex-otc.sol` — primary audit focus; order lifecycle around creation, discovery, settlement, and cancellation remains the core risk surface
- `hex-otc.sol:newOffer` / `offerETH` / `offerHEX` / `make` — ID creation and propagation mismatch surfaced as a durable direction, especially between internal storage IDs and externally returned/emitted IDs
- `hex-otc.sol:buyHEX` / `buyETH` / `cancel` — ETH payout and refund flows depend on push-based `transfer`, making recipient behavior part of liveness and recoverability
- `erc20.sol` — lightly checked for token interface assumptions; relevant mainly as support for transfer-semantics and exactness questions
- `math.sol` — only peripheral attention so far; no durable issue direction yet
- `Contract.sol` — briefly inspected, but not a meaningful source of audit signal to date

## Issue Directions Seen
- Order identity / bookkeeping mismatches between stored offers and user-visible IDs, affecting discoverability and normal workflow execution
- ETH settlement liveness risk from fixed-gas `transfer` in maker/taker/cancel payout paths, especially for contract-wallet participants
- Token integration assumptions around the hardcoded HEX token address and strict ERC20 behavior remain a background direction, though not retained yet
- Non-exact ERC20 transfer behavior and lack of balance-delta validation were explored as a possible accounting direction, but remain unconfirmed

## Useful Context
- Audit attention is concentrated heavily in `hex-otc.sol`; other files have mostly served as supporting context
- The most durable cross-round pattern so far is that market mechanics risk comes more from workflow and payment-path behavior than from complex math
- Creation, fill, and cancel flows are tightly coupled; issues found in ID exposure or ETH delivery propagate across the full order lifecycle
- Hardcoded external dependency trust and token-behavior assumptions were notable but secondary compared with the retained lifecycle and payout issues


## Latest Round Summary
# Round 2 Summary

## Agent: codex
- files touched: `hex-otc.sol`, `erc20.sol`, `math.sol`, `Contract.sol`; also read the optional prior-round summary for context
- files revisited / highest-attention files: `hex-otc.sol` received the main attention, with revisits around `buyETH` and broader settlement / escrow paths; `erc20.sol` was rechecked for interface assumptions; `Contract.sol` was sanity-checked as a tiny nonstandard blob
- main issue directions investigated: OTC execution and settlement flows, hardcoded HEX token address / chain-context assumptions, ERC20 transfer semantics and exact-movement assumptions, compiler-era/state-model edge cases, and stranded-asset behavior for unsolicited ETH / token transfers
- promising but not retained directions: no findings were retained after merge; investigated but unretained directions included wrong-chain hardcoded token risk, non-exact / malicious ERC20 behavior, and stranded funds from direct transfers or forced ETH

## Cross-Agent Status
- main overlap in file/area attention: only one agent logged this round; attention centered heavily on `hex-otc.sol`, especially settlement and escrow-related functions
- notable differences in attention: no cross-agent differences are available in this round
- underexplored but suspicious files/functions if clearly supported by the logs: `math.sol` and `erc20.sol` were comparatively light-touch; `Contract.sol` appeared to be a blob/placeholder and was only briefly checked

## Retained Findings
- none retained from this round after merge


Output only markdown.
