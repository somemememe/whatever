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
