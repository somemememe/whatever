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
- `GatewayCrossChain.sol`: central hotspot for cross-chain payload trust, destination payout accounting, revert/refund handling, and non-EVM recipient encoding edge cases
- `GatewaySend.sol`: involved in gateway flow invariants and payload-to-execution trust boundaries
- `GatewayTransferNative.sol`: repeated focus on `claimRefund` behavior (authorization/reentrancy) and ETH/native refund/withdraw paths
- `libraries/UniswapV2Library.sol`: route/pair selection logic tied to poisoning/DoS and swap-path assumptions
- `libraries/SwapDataHelperLib.sol`, `libraries/AccountEncoder.sol`: reviewed but still comparatively less-settled risk posture after low-confidence parsing/encoding concerns
- Supporting libs/interfaces (`TransferHelper`, `BytesHelperLib`, route/WETH interfaces): mainly contextual to gateway exploitability rather than primary independent issue centers

## Issue Directions Seen
- Recurring high-signal theme: attacker-controlled cross-chain payload fields are trusted too far into swap/spend/payout/refund execution
- Refund/revert authorization mismatches around recipient encoding (especially non-20-byte/non-EVM addresses) repeatedly map to theft or misdirection risk
- Native/ETH sentinel path inconsistencies are a persistent direction for unfunded withdrawal or accounting bypass behavior
- Gateway refund logic shows recurring reentrancy sensitivity (`claimRefund`) with cross-agent convergence
- AMM route/pair existence assumptions (including dust poisoning) remain a practical DoS/manipulation direction
- Residual approvals/allowance lifecycle hygiene appears as a secondary but durable abuse surface
- Owner-centralization/configuration-risk narratives appeared often but were generally lower-confidence vs concrete permissionless exploit paths

## Useful Context
- Cross-round signal is concentrated in gateway contracts; most retained impact comes from flow-composition bugs, not isolated helper-library math/parsing errors
- Strongest retained findings cluster at critical/high where payload trust crosses chain boundaries and directly controls asset movement
- Medium-severity pattern cluster: reentrancy, DoS via route poisoning, and allowance-edge abuse
- `SwapDataHelperLib`/`AccountEncoder` remain underexplored relative to gateway files, with prior attention mostly non-retained and confidence-limited


## Latest Round Summary
# Round 2 Summary

## Agent: codex_1
- files touched: `GatewayCrossChain.sol`, `GatewaySend.sol`, `GatewayTransferNative.sol`; spot checks in `libraries/*` and `interfaces/*` (line-count/inventory + targeted reads)
- files revisited / highest-attention files: highest attention on `GatewayTransferNative.sol` and `GatewayCrossChain.sol`; repeated reads around `_doMixSwap`, withdraw/payout, and refund handlers
- main issue directions investigated: asset/amount binding across swap-to-withdraw flows, empty-swap behavior, recipient address casting, refund state handling, Solana account encoding path
- promising but not retained directions: ERC20 return-value handling in `GatewaySend.onCall`; alternative critical framing around `withdrawToNativeChain` nominal-amount trust (not retained as final merged round finding)

## Agent: opencode_1
- files touched: `GatewayCrossChain.sol`, `GatewaySend.sol`, `GatewayTransferNative.sol`, `libraries/SwapDataHelperLib.sol`, `libraries/TransferHelper.sol` (plus prior round summary)
- files revisited / highest-attention files: core gateway contracts (broad pass); no clear evidence of deep iterative revisits in the log snippet
- main issue directions investigated: swap fee/approval math, slippage/min-return enforcement, refund overwrite collisions, reentrancy in refund claims, chain-id validation, deadline/staleness controls
- promising but not retained directions: several proposed issues were not carried into retained set; overlap that survived merge was refund overwrite on duplicate `externalId`

## Cross-Agent Status
- main overlap in file/area attention: both concentrated on the three gateway contracts and refund callback storage behavior (`onRevert`/`onAbort` overwrite risk)
- notable differences in attention: `codex_1` drove retained findings on empty `swapDataZ` cross-asset withdrawal, asset-binding failure in `GatewaySend`, recipient truncation, and `AccountEncoder` memory-layout bug; `opencode_1` explored more generalized slippage/deadline/reentrancy themes that were not retained
- underexplored but suspicious files/functions if clearly supported by the logs: in-scope interfaces and some helper libs (`BytesHelperLib.sol`, `SafeMath.sol`, `UniswapV2Library.sol`) had little explicit deep analysis in this round’s logs

## Retained Findings
- Critical: empty `swapDataZ` path can bypass real conversion and enable cross-asset reserve withdrawal (`GatewayCrossChain`/`GatewayTransferNative`) (`F-009`)
- Critical: `GatewaySend` source path does not bind bridged `asset` to actual swap output asset (`F-010`)
- Medium: refund metadata can be overwritten for the same `externalId` in `GatewayTransferNative` callbacks (`F-011`)
- Medium: `AccountEncoder.decompressAccounts` builds invalid `Account[]` memory layout, breaking Solana payload correctness/availability (`F-012`)
- Medium: recipient bytes are truncated/padded into EVM addresses in payout paths, enabling misdirected payouts (`F-013`)


Output only markdown.
