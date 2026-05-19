# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 10

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex_1 | Small withdrawals can redeem assets while burning zero shares | codex_1:1.0 Small withdrawals can redeem assets while burning zero shares |
| F-002 | rewritten_agent_signal | High | medium | codex_1 | Configured sub-strategy can arbitrarily mint unbacked shares and drain vault assets | codex_1:0.848 Configured sub-strategy can mint unbacked shares and drain the vault |
| F-003 | rewritten_agent_signal | Medium | medium | codex_1 | Deposit share pricing can under-mint users by valuing the vault after their ETH is transferred | codex_1:0.432 Deposit share pricing uses a post-transfer asset snapshot and can under-mint new depositors |
| F-004 | exact_agent_candidate | Medium | high | codex_1 | Deposits can succeed while minting zero shares | codex_1:1.0 Deposits can succeed while minting zero shares |
| F-005 | rewritten_agent_signal | Low | high | merge_review | Excess ETH sent to deposit is silently accepted and not credited | opencode_1:0.369 Inconsistent Asset Handling - ERC20 Vault Accepts ETH Instead of ERC20 Tokens |

## Rejection Reasons
- duplicate_or_subsumed: 1
- low_impact_or_operational: 1
- other: 7
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Inconsistent Asset Handling - ERC20 Vault Accepts ETH Instead of ERC20 Tokens | `IVault.deposit` is explicitly `payable`, and the implementation consistently uses ETH transfers on deposit. The `asset` variable appears to be metadata/accounting context, not proof that ERC20 transfers were intended here. |
| trust_or_owner_model | opencode_1 | No Validation of Controller Implementation - Rogue Owner Can Steal All Funds | This is owner-controlled configuration risk rather than a distinct vulnerability. A trusted owner can already redirect protocol behavior by choosing the controller. |
| other | opencode_1 | Insufficient Validation of Withdraw Amount | No concrete exploit is established from vault code alone. The controller API intentionally returns `(withdrawn, fee)`, so `withdrawn < assets` can be part of expected controller semantics rather than a vault bug. |
| other | opencode_1 | Division by Zero in Share Calculation When Total Assets Returns Zero | This requires an already broken or inconsistent controller state (`totalSupply() > 0` while `totalAssets() == 0`). It is not an independently exploitable protocol bug from the vault logic itself. |
| duplicate_or_subsumed | opencode_1 | No Slippage Protection in Deposit Function | Generic lack of a `minShares` parameter is not reportable by itself here. The concrete harmful pricing bugs are already captured in separate findings. |
| other | opencode_1 | Missing Input Validation in convertToShares and convertToAssets | Potential view-function reverts under pathological controller states do not create meaningful standalone protocol harm. |
| other | opencode_1 | Missing Zero Address Check for SubStrategy | `setSubStrategy` already rejects the zero address. Lack of contract-code validation is an admin-trust concern, not a separate exploit. |
| low_impact_or_operational | opencode_1 | Console.log Statements Left in Production Code | Gas/debug residue is not a security finding with realistic protocol-level harm. |
| other | opencode_1 | Inconsistent Return Value in Withdraw Function | This is an integration ergonomics issue, not a vulnerability affecting funds or protocol safety. |
| other | opencode_1 | Controller Can Be Set to Address(0) After Initialization | `setController` forbids the zero address. An unset controller after initialization is deployment misconfiguration, not an exploitable vulnerability. |
