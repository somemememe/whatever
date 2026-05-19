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
- `GatewayCrossChain.sol`: primary cross-chain execution trust boundary; repeated focus on swap-to-withdraw asset/amount binding, empty `swapDataZ` behavior, payout/refund routing
- `GatewaySend.sol`: source-side asset provenance/binding gap between declared bridged asset and actual swap output
- `GatewayTransferNative.sol`: refund callback storage/overwrite behavior (`externalId` collisions), `claimRefund` reentrancy/authorization sensitivity, native payout paths
- `libraries/AccountEncoder.sol`: Solana account decompression path flagged for malformed `Account[]` memory layout (correctness/availability impact)
- `libraries/UniswapV2Library.sol`, `libraries/SwapDataHelperLib.sol`, `libraries/TransferHelper.sol`: secondary but recurring context for route assumptions, swap handling, and transfer/approval edge behavior
- Supporting helpers/interfaces (`BytesHelperLib`, route/WETH interfaces): mostly contextual; some remain lightly analyzed versus gateway hotspots

## Issue Directions Seen
- Persistent high-signal theme: attacker-influenced cross-chain payload data is trusted too far into swap, withdrawal, and payout/refund execution
- Strong recurring direction: missing asset-binding invariants across composed flows (swap output vs declared/expected bridged asset), including no-op/empty swap paths
- Recipient encoding/casting mismatches (non-EVM bytes, truncation/padding to EVM address) repeatedly map to payout misdirection risk
- Refund state integrity is a durable issue class: callback metadata overwrite/collision and `claimRefund` reentrancy sensitivity
- Native/ETH sentinel and accounting path inconsistencies remain a recurring avenue for withdrawal/accounting bypass narratives
- AMM route/pair assumption and poisoning/DoS themes persist as secondary directions; several slippage/deadline variants remained lower confidence

## Useful Context
- Cross-round retained signal is concentrated in gateway flow composition, not isolated arithmetic/parsing helpers
- Highest-impact findings consistently occur where cross-chain payload trust directly controls asset movement
- Medium-severity cluster remains around refund state handling, recipient encoding, and availability/correctness breakage in non-EVM account encoding
- `AccountEncoder` moved from underexplored to confirmed-risk territory; several other helper/interface files remain comparatively shallowly tested


## Latest Round Summary
# Round 3 Summary

## Agent: codex_1
- files touched
  - `GatewaySend.sol`, `GatewayTransferNative.sol`, `GatewayCrossChain.sol`, `libraries/TransferHelper.sol` (plus scope enumeration of interfaces/libraries)
- files revisited / highest-attention files
  - Highest attention on `GatewaySend.sol` (source deposit path, destination `onCall`, and `onRevert`)
  - Secondary attention on `GatewayTransferNative.sol` and `GatewayCrossChain.sol` for pattern comparison
- main issue directions investigated
  - ERC20 accounting vs nominal `amount` usage in source deposits
  - Unchecked ERC20 return values in destination payout paths
  - ETH delivery/refund handling edge cases (`.transfer` gas stipend, native revert refund handling)
  - Additional low-confidence probes on callback gas exhaustion and ETH-sentinel handling
- promising but not retained directions
  - Large `receiver` bytes causing revert-callback gas exhaustion
  - ETH-sentinel withdrawal liveness issue in `GatewayTransferNative`
  - A separate `onCall transferFrom`-result issue variant that was not kept in merged retained set

## Agent: opencode_1
- files touched
  - Read all in-scope Solidity files (`GatewayCrossChain.sol`, `GatewayTransferNative.sol`, `GatewaySend.sol`, all listed `libraries/*.sol`, `interfaces/*.sol`) and prior round summary
- files revisited / highest-attention files
  - Emphasis in proposed findings was mostly `GatewaySend.sol`, with additional checks in `GatewayTransferNative.sol` and `GatewayCrossChain.sol`
- main issue directions investigated
  - Swap parameter validation themes (deadline/min output)
  - Message decoding bounds safety
  - `externalId` predictability/MEV angle
  - Access-control and fee-configuration/economic checks
  - Swap accounting consistency in native-transfer flow
- promising but not retained directions
  - Deadline/min-output swap protections, decode bounds, predictability, fee/access-control, and accounting concerns were proposed but not retained after merge

## Cross-Agent Status
- main overlap in file/area attention
  - Both agents concentrated on `GatewaySend.sol`, especially cross-chain execution, payout, and revert-related logic.
- notable differences in attention
  - `codex_1` produced concrete transfer/refund execution-path bugs that became retained findings.
  - `opencode_1` focused more on parameter-validation/economic/design concerns, none retained in final merge.
- underexplored but suspicious files/functions if clearly supported by the logs
  - `GatewayCrossChain.sol` and `GatewayTransferNative.sol` received review attention but yielded no retained findings this round despite multiple low-confidence probes.

## Retained Findings
- `F-014` (High): `GatewaySend` ERC20 source deposit can bridge nominal `amount` without reconciling actual received balance, enabling reserve-backed shortfall drain.
- `F-015` (Medium): `GatewaySend.onCall` treats destination delivery as success even if ERC20 payout `transfer` returns `false`.
- `F-016` (Low): `GatewaySend` ETH payout uses `.transfer` (2300 gas), causing deterministic failures for some contract recipients.
- `F-017` (High): `GatewaySend.onRevert` lacks a native-asset refund branch, risking stranded reverted ETH.


Output only markdown.
