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
- `GatewaySend.sol`: now a top hotspot across rounds; durable issues around source deposit accounting (`amount` vs actual received), destination payout success semantics, and revert-path refund handling (especially native asset branching)
- `GatewayCrossChain.sol`: persistent cross-chain execution trust boundary; recurring scrutiny on payload-driven swap/withdraw binding, empty/no-op swap behavior, and payout/refund routing correctness
- `GatewayTransferNative.sol`: recurring refund-state integrity and native payout/recovery concerns (`externalId` collision/overwrite surface, `claimRefund` sensitivity, ETH-sentinel/accounting edge paths)
- `libraries/TransferHelper.sol`: continued relevance for ERC20 transfer/approval edge behavior and return-value handling assumptions in gateway payout paths
- `libraries/AccountEncoder.sol`: confirmed-risk area for Solana account decompression/memory-layout correctness and availability impact
- `libraries/UniswapV2Library.sol`, `libraries/SwapDataHelperLib.sol`, plus route/WETH/helper interfaces: secondary context for route assumptions and swap-path behavior; generally lower signal than gateway flow composition

## Issue Directions Seen
- Cross-chain payload trust is still the dominant risk theme: attacker-influenced message fields propagate too directly into asset movement decisions
- Asset/accounting binding gaps are a repeated high-signal class, now including explicit nominal-vs-received deposit mismatch on source-side bridging
- Delivery/finalization semantics remain fragile: execution paths can mark success despite failed token payout, creating silent settlement divergence
- Native-asset handling is a recurring failure mode: ETH-specific payout/refund branch inconsistencies and gas-stipend-driven liveness failures
- Refund integrity remains durable: callback metadata collision/overwrite and refund-claim execution sensitivity (including reentrancy/liveness angles)
- Recipient encoding/casting mismatch risk (non-EVM bytes to EVM address) continues as a payout misdirection direction
- AMM parameter-validation/economic hardening themes (deadline/minOut, MEV/predictability, fee config) recur but remain lower-confidence/non-retained versus execution-path bugs

## Useful Context
- Retained findings continue to cluster in gateway execution composition (`GatewaySend`/`GatewayCrossChain`/`GatewayTransferNative`) rather than isolated math helpers
- `GatewaySend.sol` has become the strongest repeated signal center, with retained high/medium/low issues spanning deposit, payout, and revert flows
- Cross-round high impact usually appears where one flow assumes another flow’s invariant without explicit reconciliation (balances, asset identity, delivery result, native-vs-token branching)
- `AccountEncoder` is established as confirmed-risk for correctness/availability; several helper/interface files remain comparatively shallow and mostly contextual


## Latest Round Summary
# Round 4 Summary

## Agent: codex_1
- files touched: `GatewayCrossChain.sol`, `GatewayTransferNative.sol`, `GatewaySend.sol` (plus targeted line extraction across these); attempted local Foundry repro in `/tmp/ReturnMismatch.t.sol`
- files revisited / highest-attention files: highest attention on `GatewayTransferNative.sol` and `GatewayCrossChain.sol`; revisited specific swap/withdraw sections multiple times
- main issue directions investigated: swap-output/token-binding across DODO swap and payout token usage; withdrawal path accounting checks around `amountInMax`; additional checks on fee handling, callback ABI return compatibility, unchecked ERC20 `transferFrom`, refund event emission
- promising but not retained directions: candidate findings on fee/gross-amount mismatch in `GatewayTransferNative.onCall`, callback return ABI mismatch in `GatewaySend.onCall`, unchecked inbound `transferFrom` in `GatewaySend`, and refund event field ordering were proposed but not retained after merge

## Agent: opencode_1
- files touched: broad read of in-scope Solidity set, including `GatewayCrossChain.sol`, `GatewaySend.sol`, `GatewayTransferNative.sol`, `libraries/*`, and `interfaces/*`; also read prior round summary
- files revisited / highest-attention files: primary attention on the three gateway contracts, with grep-driven pattern sweeps (swap params, auth modifiers, deadlines, refund deletion, approvals)
- main issue directions investigated: parameter validation around swap return limits/deadlines, nonce/time usage, access-control surfaces, amount checks, decode paths, reentrancy absence, and approval usage patterns
- promising but not retained directions: a deadline-enforcement hypothesis (shown in its partial output) was not retained

## Cross-Agent Status
- main overlap in file/area attention: both focused on gateway fund-flow logic, especially swap/withdraw pathways in `GatewayCrossChain.sol` and `GatewayTransferNative.sol`
- notable differences in attention: `codex_1` did deeper exploit-path validation with concrete line-level traces and attempted a behavior repro; `opencode_1` emphasized broad static pattern scanning across all contracts/libraries
- underexplored but suspicious files/functions if clearly supported by the logs: no clearly supported underexplored hotspot beyond already-scanned gateway callback/swap surfaces

## Retained Findings
- `F-018` (Critical): swap output token is not bound to the later payout/withdraw token, enabling reserve-drain via asset mismatch in cross-chain and native transfer flows
- `F-022` (Medium): post-swap sufficiency check uses `amountInMax` instead of actual input spent, causing avoidable withdrawal reverts and liveness degradation


Output only markdown.
