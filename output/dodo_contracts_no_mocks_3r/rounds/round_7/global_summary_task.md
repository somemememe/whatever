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
- `GatewaySend.sol`: persistent source-side accounting hotspot (`amount` intent vs actual forwarded value), callback settlement/revert branching, and native deposit flow edge cases
- `GatewayCrossChain.sol`: core execution boundary where payload-decoded inputs drive swap/payout/refund behavior; recurring focus on exact-output swap settlement and allowance lifecycle
- `GatewayTransferNative.sol`: recurring hotspot for `onCall` fee/swap flow, native payout/refund integrity, revert handlers, `claimRefund`, and exact-output allowance behavior
- Gateway seam across `GatewaySend` + `GatewayCrossChain` + `GatewayTransferNative`: sustained high-risk boundary for invariant drift (asset identity, actual balances, swap spent/received, delivery outcome)
- `libraries/AccountEncoder.sol`, `TransferHelper.sol`, `SwapDataHelperLib.sol`, `BytesHelperLib.sol`, `UniswapV2Library.sol` (+ `IDODORouteProxy` interface): repeatedly revisited as supporting context; generally secondary signal versus gateway flow logic

## Issue Directions Seen
- Cross-chain payload trust/binding remains dominant: decoded payload fields can steer token movement with limited end-to-end invariant reconciliation
- Asset/accounting binding gaps remain the strongest recurring class, including exact-output swap accounting and downstream token/amount assumptions
- Approval/allowance lifecycle is now a retained direction: exact-output Uniswap paths can leave residual allowance and create future strict-approve DoS conditions
- Source-side ETH amount semantics are now a retained direction: `depositAndCall` overload behavior can diverge between checked `amount` and full `msg.value` forwarded
- Execution-success vs delivery-success divergence remains a durable callback/result concern
- Native-asset branches continue to carry disproportionate risk (refund routing, payout behavior, liveness edge cases)
- Refund record integrity/collision/claim-path behavior is repeatedly investigated, though many variants remain non-retained

## Useful Context
- Cross-round signal remains concentrated in deep tracing of gateway swap/callback/revert/refund paths; the same three gateway contracts continue to attract highest-confidence risk
- Highest-impact findings repeatedly emerge at stage boundaries where one phase assumes another phase’s invariant without explicit reconciliation
- Latest round reinforced prior patterns and converted two recurring themes into retained findings (exact-output allowance residuals; ETH over-forwarding semantics), while many callback/refund edge hypotheses remained unretained


## Latest Round Summary
# Round 7 Summary

## Agent: codex_1
- files touched: `GatewaySend.sol`, `GatewayTransferNative.sol`, `GatewayCrossChain.sol` (targeted line-level inspection; no edits)
- files revisited / highest-attention files: highest attention on `GatewayTransferNative.sol` and `GatewaySend.sol` (`withdrawToNativeChain`, `onCall`, `onRevert`, `onAbort`, `claimRefund`, packed message decoding)
- main issue directions investigated: nominal-vs-actual ERC20 intake validation, ETH sentinel fee-transfer behavior, refund/event consistency, calldata length/slice safety in packed decoders and revert handlers
- promising but not retained directions: proposed F-025 to F-029 (including `onCall` intake mismatch and decoder/revert-message bounds concerns) were surfaced but not retained in merged round output

## Agent: opencode_1
- files touched: broad read across in-scope Solidity (`GatewayCrossChain.sol`, `GatewaySend.sol`, `GatewayTransferNative.sol`, `libraries/*`, key interfaces), plus prior round/global summaries
- files revisited / highest-attention files: emphasis on core gateway contracts, with targeted greps around `claimRefund`, `onlyGateway`, and `externalId == bytes32(0)`
- main issue directions investigated: refund record overwrite/collision themes, token/address validation in `onCall`, fee timing around swaps, slippage protection, empty swap-data handling, externalId predictability
- promising but not retained directions: proposed F-025 to F-030, but none were retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both concentrated on `GatewaySend.sol` and `GatewayTransferNative.sol`, especially `onCall`/refund/externalId-related flows
- notable differences in attention: `codex_1` did deeper line-level checks on parser/revert-handler mechanics; `opencode_1` scanned more broadly across libraries/interfaces and incorporated prior summaries
- underexplored but suspicious files/functions if clearly supported by the logs: `GatewayCrossChain.sol` appears comparatively less deeply examined this round versus the other two gateway contracts

## Retained Findings
- None retained from this round after merge.


Output only markdown.
