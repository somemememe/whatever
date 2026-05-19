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
- `GatewaySend.sol`: persistent hotspot for source-side accounting (quoted `amount` vs actual received/spent), callback settlement semantics, and revert/refund branching (notably native paths)
- `GatewayCrossChain.sol`: core execution boundary where payload-decoded fields drive payout/refund behavior; repeated attention on execution/result handling and refund-record lifecycle
- `GatewayTransferNative.sol`: recurring hotspot for `onCall` fee/swap flow, native payout/refund integrity, revert handlers, and `claimRefund` state interactions
- Gateway composition across `GatewaySend` + `GatewayCrossChain` + `GatewayTransferNative`: sustained high-risk seam for cross-stage invariant breaks (token identity, actual balances, actual swap spend/receive, delivery outcome)
- `libraries/AccountEncoder.sol`: established confirmed-risk context (Solana account decode correctness/availability)
- `libraries/TransferHelper.sol`: ongoing context for ERC20 transfer/call-return assumptions in payout paths
- `libraries/SwapDataHelperLib.sol`, `libraries/UniswapV2Library.sol`, `libraries/BytesHelperLib.sol`: repeatedly reviewed as secondary context; lower retained signal versus gateway flow logic

## Issue Directions Seen
- Cross-chain payload trust/binding remains dominant: decoded payload inputs influence token movement with limited hard invariant reconciliation
- Asset identity and accounting binding gaps are the strongest recurring class, including swap output vs downstream payout/withdraw token assumptions
- Post-swap/finalization fragility persists when checks key off config/bounds rather than actual spent/received values
- Execution-success vs delivery-success divergence remains a durable concern in callback/result semantics
- Native-asset branches continue to carry disproportionate risk (refund routing, payout behavior, liveness edge cases)
- Refund integrity/state-collision sensitivity remains recurring (including overwrite/collision-style record handling)
- Slippage/fee/economic-policy hypotheses recur in review but remain mostly lower-confidence unless tied to concrete execution-path violations

## Useful Context
- Cross-round signal remains concentrated in deep gateway flow tracing, especially callback/revert/refund and swap/fee settlement paths
- Multiple rounds/agents converged on the same three gateway contracts; this overlap is itself a stable risk indicator
- Highest-impact issues repeatedly emerge at stage boundaries where one contract assumes another stage’s invariant without explicit reconciliation
- Recent round expanded scrutiny (context/auth assumptions, payload parsing, refund-event/record handling) but added no new retained findings; prior gateway-centric patterns remain the durable memory baseline


## Latest Round Summary
# Round 6 Summary

## Agent: codex_1
- files touched: `GatewayCrossChain.sol`, `GatewayTransferNative.sol`, `GatewaySend.sol`
- files revisited / highest-attention files: `GatewayCrossChain.sol` and `GatewayTransferNative.sol` (multiple targeted reads around swap/withdraw/refund logic)
- main issue directions investigated: refund keying/callback behavior, swap output trust vs balance reality, Uniswap exact-output allowance lifecycle, ETH deposit overload amount handling, callback message-length edge cases
- promising but not retained directions: refund-slot collision/poisoning, swap return-value trust without balance-delta checks, callback length-guard issues, refund bookkeeping edge cases (`externalId == 0`, post-delete event fields)

## Agent: opencode_1
- files touched: `GatewaySend.sol`, `GatewayTransferNative.sol`, `GatewayCrossChain.sol`, `libraries/SwapDataHelperLib.sol`, `libraries/AccountEncoder.sol`, `libraries/BytesHelperLib.sol`, `libraries/TransferHelper.sol`, `libraries/UniswapV2Library.sol`, `interfaces/IDODORouteProxy.sol`
- files revisited / highest-attention files: the three gateway contracts, especially `GatewaySend.sol` and `GatewayTransferNative.sol`
- main issue directions investigated: callback return/decoding behavior, swap parameter/amount validation, slippage/approval handling, withdraw recipient validation, public withdraw surface, parser safety in swap-data decoding
- promising but not retained directions: multiple medium/low hypotheses across callback semantics, amount validation, and decoding robustness; overlap with retained allowance-residual DoS theme in exact-output Uniswap flow

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on gateway swap/withdraw paths, with direct overlap on exact-output Uniswap approval behavior in `GatewayCrossChain.sol` and `GatewayTransferNative.sol`
- notable differences in attention: `codex_1` was more line-focused on exploit paths in core flows; `opencode_1` scanned more broadly across libraries/interfaces and produced more speculative edge-case candidates
- underexplored but suspicious files/functions if clearly supported by the logs: callback/refund handling paths (`onRevert`/`onAbort`/`claimRefund`) drew repeated scrutiny but did not persist as retained findings this round

## Retained Findings
- `F-023` (Medium): exact-output Uniswap approval pattern can leave residual allowance and later DoS strict-approve tokens (`GatewayCrossChain.sol`, `GatewayTransferNative.sol`)
- `F-024` (Low): ETH `depositAndCall` overload in `GatewaySend.sol` checks `msg.value >= amount` but forwards full `msg.value`, enabling unintended over-bridging


Output only markdown.
