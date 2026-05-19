# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 10

## Finding Actions
- exact_agent_candidate: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1,opencode_1 | Public `_burn` lets anyone destroy arbitrary LAND and corrupt balances | codex_1:1.0 Public `_burn` lets anyone destroy arbitrary LAND and corrupt balances |
| F-002 | exact_agent_candidate | High | high | codex_1 | Burning one child LAND permanently breaks transfers of enclosing quads | codex_1:1.0 Burning one child LAND permanently breaks transfers of enclosing quads |
| F-003 | exact_agent_candidate | Medium | medium | codex_1 | Quad mints and quad transfers can silently lock LAND in contracts that lack the custom batch receiver interface | codex_1:1.0 Quad mints and quad transfers can silently lock LAND in contracts that lack the custom batch receiver interface |

## Rejection Reasons
- other: 5
- trust_or_owner_model: 5

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | Super Operators can arbitrarily transfer any user's tokens | This is an explicit admin-controlled trust role by design: transfer authorization intentionally includes `_superOperators[msg.sender]`. It is a centralization/property-of-privileged-role concern, not a permissionless vulnerability. |
| trust_or_owner_model | opencode_1 | approveFor allows setting approval on tokens user doesn't own | `approveFor` requires `msg.sender` to be the `sender`, a trusted meta-tx processor, a super operator, or an already-approved operator-for-all, and separately requires `owner == sender`. The cited unauthorized path is not supported by the code. |
| trust_or_owner_model | opencode_1 | setApprovalForAllFor allows super operators to self-approve | Super operators already have global transfer power, so self-approval adds no new capability or exploitable permissionless path. This is redundant with the intended privileged role. |
| other | opencode_1 | Missing zero-address validation when changing admin | Setting admin to `address(0)` is an admin-only misconfiguration risk, not an externally exploitable protocol vulnerability. It does not create realistic permissionless fund loss by itself. |
| other | opencode_1 | Land contract does not implement ERC-165 supportsInterface correctly | `supportsInterface` correctly returns true for the three advertised interface IDs and false otherwise. The claim about 'multiple interface IDs' is not meaningful for ERC-165, which checks one `bytes4` at a time. |
| trust_or_owner_model | opencode_1 | batchTransferFrom does not verify token existence before transfer | `_batchTransferFrom` loads `(owner, operatorEnabled)` via `_ownerAndOperatorEnabledOf(id)` and requires `owner == from`, while `from` must be nonzero. Unminted tokens resolve to `owner == address(0)` and cannot pass the check. |
| trust_or_owner_model | opencode_1 | No two-step process for admin transfer creates permanent lockup risk | This is a governance best-practice issue only. It depends on operator mistake and does not describe a concrete exploitable protocol flaw. |
| other | opencode_1 | mintQuad can overflow when calculating token count | `size` is strictly constrained to `1`, `3`, `6`, `12`, or `24`, so `size * size` is at most `576`. The proposed overflow cannot occur in the reachable code path. |
| other | opencode_1 | setMinter lacks zero-address validation | Allowing `address(0)` in the minter mapping is benign configuration noise; it does not grant power or create an exploitable state transition. |
| other | opencode_1 | MetaTransactionReceiver allows setting any address as meta transaction processor | This is an admin-trusted configuration choice. Pointing the processor to an EOA may disable or centralize meta-tx handling, but it is not a standalone permissionless vulnerability. |
