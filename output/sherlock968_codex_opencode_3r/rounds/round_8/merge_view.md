# Merge View - Round 8

## Summary
- total findings: 27
- new findings: 1
- updated existing findings: 0
- rejected candidates: 13

## Finding Actions
- existing_preserved: 26
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-028 | rewritten_agent_signal | Low | medium | codex_1 | Max-nonce signatures can permanently freeze unit updates for a user/program | codex_1:0.384 Unchecked uint256-to-uint128 casts can silently corrupt unit accounting |

## Rejection Reasons
- duplicate_or_subsumed: 4
- factually_incorrect: 2
- other: 2
- trust_or_owner_model: 5

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex_1 | LP fee collection bypasses locker unlock gating | Lower-impact variant of existing F-022; the core missing-gate issue on LP paths is already captured. |
| duplicate_or_subsumed | opencode_1 | Pumponomics swap executes with zero minimum output leading to sandwich attack | Already captured by F-005. |
| other | codex_1 | Unchecked uint256-to-uint128 casts can silently corrupt unit accounting | Requires unrealistic magnitudes or trusted signer/admin misuse; no realistic external exploit path was established. |
| other | codex_1 | Factory allows zero-address locker owner, creating irrecoverable approved lockers | Creates a self-inflicted unusable locker/sink but does not provide a realistic cross-user or protocol-level exploit. |
| trust_or_owner_model | codex_1 | uint16 `fontaineCount` can overflow and disable future vest unlock creation | Requires 65,535 vest unlock creations by the same owner and only self-DoSes vest unlock creation; practical risk is negligible. |
| trust_or_owner_model | opencode_1 | emergencyWithdraw allows owner to drain all tokens including protocol funds | Owner-privileged emergency path to treasury; trust/governance risk already contextually covered by F-026 residue-sweep behavior. |
| trust_or_owner_model | opencode_1 | Vesting factory admin can frontrun recipient vesting creation | `createSupVestingContract` is `onlyAdmin`; admin is already the authorized creator, so this is not a distinct frontrun vulnerability. |
| factually_incorrect | opencode_1 | No slippage protection on Uniswap V3 position creation | Incorrect: `_createPosition` uses `amount0Min/amount1Min` from `_calculateMinAmounts` (5% tolerance). |
| trust_or_owner_model | opencode_1 | SupVestingFactory allows setting any admin without timelock | Governance policy/design choice, not a contract vulnerability by itself. |
| duplicate_or_subsumed | opencode_1 | Active program funding can be interrupted by treasury flow rate changes | Primarily expected behavior under treasury-side flow changes/insolvency; specific unintended clamp edge case is already captured in F-017. |
| trust_or_owner_model | opencode_1 | Tax allocation can be updated while tax is being distributed | Owner-authorized economic parameter update; no concrete unintended state corruption or bypass shown. |
| factually_incorrect | opencode_1 | LP pool units not updated when liquidity is fully removed | Incorrect: `_decreasePosition` decrements `_liquidityBalance` and updates LP units; remaining connection with zero units does not accrue rewards. |
| duplicate_or_subsumed | opencode_1 | No Access Control on distributeTaxAdjustment | Already captured by F-012. |
