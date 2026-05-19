# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 8

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | `redeem()` trusts an arbitrary token contract and can release any ERC20 held by the teller | codex_1:0.777 Redeem accepts arbitrary contracts and can drain any ERC20 balance held by the teller |
| F-002 | exact_agent_candidate | High | high | codex_1 | Purchases into undeployed fixed-expiry markets can complete without minting any bond tokens | codex_1:0.854 Purchases into undeployed fixed-expiry markets can succeed while minting no bond tokens |
| F-003 | rewritten_agent_signal | High | medium | codex_1 | `redeem()` burns bond tokens before an unchecked ERC20 transfer, allowing permanent loss on false-return payout tokens | codex_1:0.727 Redeem burns first and ignores ERC20 transfer failures, enabling permanent loss on false-return tokens |
| F-004 | exact_agent_candidate | Medium | low | codex_1 | `purchase()` prices against one market snapshot but settles against a second snapshot | codex_1:0.976 Purchase prices against one market snapshot but settles against a second snapshot |

## Rejection Reasons
- other: 5
- trust_or_owner_model: 2
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | No Access Control on setProtocolFee | Rejected: `setProtocolFee()` is protected by `requiresAuth`, so arbitrary callers cannot change it. |
| other | opencode_1 | Unprotected claimFees allows stealing accumulated fees | Rejected: `claimFees()` only pays out `rewards[msg.sender][token]`; callers cannot withdraw another account's rewards. |
| trust_or_owner_model | opencode_1 | No minimum protocol fee enforcement | Rejected: this is a documentation/governance mismatch, not a realistic exploit path causing protocol-level harm. |
| unsupported_or_speculative | opencode_1 | Fee-on-transfer token handling breaks for legitimate tokens | Rejected: fee-on-transfer tokens are explicitly treated as unsupported and the code reverts rather than silently mis-accounting or losing funds. |
| other | opencode_1 | Missing access control on setReferrerFee | Rejected: letting each referrer set its own fee is the intended design; it does not let third parties alter someone else's fee setting. |
| other | opencode_1 | Unchecked callback return values | Rejected: the teller verifies that its payout-token balance increased by at least `payout_`, so the callback must actually fund the full payout amount or the transaction reverts. |
| other | opencode_1 | ERC20BondToken Mint/Burn Access Control | Rejected: cloned bond tokens embed the teller address in immutable args, and the implementation contract itself does not become freely mintable by arbitrary users. |
| trust_or_owner_model | opencode_1 | Guardian parameter unused in Auth contract | Rejected: `guardian_` is passed into `Auth` as the owner parameter, so it is not unused; this is naming confusion, not a vulnerability. |
