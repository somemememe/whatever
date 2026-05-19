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
- `GatewaySend.sol`: persistent hotspot for source-side deposit accounting (`amount` vs actual received), callback settlement semantics, and revert/refund branching (especially native paths)
- `GatewayCrossChain.sol`: core cross-chain execution boundary; repeated issues around swap-to-payout asset binding and payload-driven fund movement decisions
- `GatewayTransferNative.sol`: recurring hotspot for native-flow payout/refund integrity, plus swap/withdraw accounting checks and refund-state sensitivity
- Gateway swap/withdraw compositions across `GatewayCrossChain` + `GatewayTransferNative`: now a confirmed high-risk seam (token-identity mismatch and post-swap sufficiency logic)
- `libraries/TransferHelper.sol`: still relevant context for ERC20 call/return-value behavior assumptions in payout/transfer paths
- `libraries/AccountEncoder.sol`: established confirmed-risk area for Solana account decode correctness/availability
- `libraries/UniswapV2Library.sol`, `libraries/SwapDataHelperLib.sol`, route/helper interfaces: secondary context for route/swap assumptions; generally lower signal than gateway flow composition

## Issue Directions Seen
- Cross-chain payload trust and execution binding remains the dominant theme: decoded fields influence token movement with weak invariant enforcement
- Asset identity/accounting binding gaps are the strongest recurring class, now clearly including unbound swap output token vs downstream payout/withdraw token
- Post-swap accounting/finalization checks are fragile: logic keyed to bounds/config values (e.g., `amountInMax`) instead of actual spent/received values drives liveness failures
- Delivery/result semantics remain a durable concern: flows can diverge between “execution success” and real asset delivery outcomes
- Native-asset branches continue to produce disproportionate risk (refund routing, payout behavior, gas/liveness edge cases)
- Refund integrity remains recurring (state collision/overwrite sensitivity and claim-path execution robustness)
- AMM hardening themes (deadline/minOut/MEV/fee config) recur in exploration but remain lower-confidence versus concrete gateway execution-path bugs

## Useful Context
- Cross-round retained signal is concentrated in gateway composition (`GatewaySend`/`GatewayCrossChain`/`GatewayTransferNative`), not isolated helper math
- `GatewayCrossChain` and `GatewayTransferNative` swap/withdraw pathways now have repeated, convergent evidence from multiple rounds/agents
- Highest-impact bugs repeatedly appear where one stage assumes another stage’s invariant without explicit reconciliation (token identity, actual balances, actual swap spend/receive, delivery result)
- Recent broad static sweeps added coverage, but durable retained findings still came from deep flow-trace reasoning on gateway callbacks and settlement paths


## Latest Round Summary
# Round 5 Summary

## Agent: codex_1
- files touched: `GatewayCrossChain.sol`, `GatewaySend.sol`, `GatewayTransferNative.sol`, all listed interfaces/libraries, plus `mocks/GatewayZEVMMock.sol` and `mocks/DODORouteProxyMock.sol` for integration context
- files revisited / highest-attention files: `GatewayTransferNative.sol` (onCall fee/swap flow, revert handlers, claimRefund), `GatewaySend.sol` (onCall/onRevert), `GatewayCrossChain.sol` (refund record handling)
- main issue directions investigated: pre-fee vs swap amount accounting, revert callback payload parsing robustness, refund-record collision logic (`externalId == 0`), callback success return-value semantics, source authentication via `MessageContext`, refund event correctness
- promising but not retained directions: low-confidence gateway return-selector mismatch hypothesis, low-confidence missing source allowlist hypothesis, and an informational event-field zeroing observation

## Agent: opencode_1
- files touched: `GatewayCrossChain.sol`, `GatewaySend.sol`, `GatewayTransferNative.sol`, `libraries/SwapDataHelperLib.sol`, `libraries/AccountEncoder.sol`, `libraries/TransferHelper.sol`, `libraries/UniswapV2Library.sol`, `libraries/BytesHelperLib.sol`
- files revisited / highest-attention files: primary focus remained the three gateway contracts, especially swap/fee/slippage paths in `GatewaySend.sol` and `GatewayTransferNative.sol`
- main issue directions investigated: slippage/min-output enforcement, fee-timing/economic effects, `onCall` trust/access-control assumptions, token/chain binding checks
- promising but not retained directions: owner fee-parameter abuse framing, “fee before swap” efficiency concerns, destination-asset compatibility concerns, and additional slippage/min-return claims

## Cross-Agent Status
- main overlap in file/area attention: strong overlap on `GatewayCrossChain.sol`, `GatewaySend.sol`, and `GatewayTransferNative.sol`, with emphasis on cross-chain call handlers and swap/fee paths
- notable differences in attention: codex_1 concentrated on callback/revert/refund edge cases and gateway-context assumptions; opencode_1 concentrated on slippage/economic-policy and configuration-style risks
- underexplored but suspicious files/functions if clearly supported by the logs: library-level helpers (`SwapDataHelperLib`, `UniswapV2Library`, `BytesHelperLib`) were read but did not produce retained outcomes this round

## Retained Findings
- None retained from this round after merge.


Output only markdown.
