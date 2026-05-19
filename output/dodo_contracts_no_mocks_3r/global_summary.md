# Global Audit Memory

## Scope Touched
- `GatewaySend.sol`: persistent hotspot for authenticated cross-chain entry (`onCall`), settlement routing, swap execution, and amount/value handling.
- `GatewayTransferNative.sol`: highest repeated attention on native withdrawal/refund execution and payout asset semantics; `onCall` recipient-asset behavior remains critical.
- `GatewayCrossChain.sol`: consistently reviewed as a core leg in cross-chain execution/state flow and routing assumptions.
- `libraries/SwapDataHelperLib.sol`, `libraries/TransferHelper.sol`, `libraries/AccountEncoder.sol` (+ lighter `interfaces/*`/utility libs): recurring support surface for swap input decoding, transfer behavior, and message/account interpretation.

## Issue Directions Seen
- Gateway callback interface/ABI compatibility at `onCall` boundaries is a proven high-signal class (confirmed revert-inducing incompatibility previously retained).
- Amount/accounting correctness is a recurring direction: nominal vs actual received, fee-adjusted amounts, and `amount` vs `msg.value`/native-fee semantics.
- Asset-type/payout semantics across branch paths (same-token vs swap, wrapped vs native delivery) remain a durable risk direction; now includes retained WZETA/native mismatch behavior.
- Cross-chain routing and execution invariants (`dstChainId`/asset pairing, authenticated message assumptions) continue to be repeatedly tested.
- Refund/failure-path behavior remains a standing theme, including payout transfer assumptions and downstream-call edge handling.

## Useful Context
- Cross-round overlap is strongest in `GatewaySend.sol` + `GatewayTransferNative.sol`; most durable signal concentrates in callback compatibility and value/asset-handling correctness rather than broad hypothesis lists.
- Retained confirmed issues now include: (1) `GatewaySend.onCall` return-type incompatibility (`bytes4` vs expected dynamic `bytes`) that can brick authenticated settlement delivery, and (2) `GatewayTransferNative.onCall` same-token WZETA path sending wrapped token instead of expected native ZETA.
- Repeated broad scans produced many candidates, but merge survival has been low; stable patterns come from path-sensitive callback/payout branches.
- Compared with core gateway contracts, some interface/utility surfaces have seen lighter direct scrutiny and remain secondary context areas.
