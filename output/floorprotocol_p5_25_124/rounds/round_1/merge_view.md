# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 12

## Finding Actions
- new_unmatched: 1
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high |  | Periphery mixes balances across users, letting later callers spend stranded ETH or fragment tokens | codex_1:0.592 Periphery pools residual ETH and fragment balances, letting later callers spend prior users' funds |
| F-002 | new_unmatched | Medium | medium |  | An uninitialized UUPS proxy can be seized by the first external caller | codex_1:0.409 The UUPS proxy is takeable if deployment omits initializer calldata |
| F-003 | rewritten_agent_signal | Low | high |  | Directly transferred ERC721s can be permanently trapped in the periphery | codex_1:0.565 Any ERC721 sent to the periphery can be permanently trapped |

## Rejection Reasons
- duplicate_or_subsumed: 1
- low_impact_or_operational: 1
- other: 8
- trust_or_owner_model: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Unlimited ERC20 Approval to Floor Contract | This is the intended trust boundary between the periphery and the core `floor` contract. "If the trusted core is compromised" is not a distinct vulnerability in the periphery. |
| other | opencode_1 | Unlimited ERC721 Approval to Floor Contract | This approval is required for the periphery's normal fragment flow and only empowers the trusted `floor` contract. It is not a standalone exploit path. |
| other | opencode_1 | No Access Control on extsload - Full Storage Exposure | `IFlooring` itself intentionally exposes `extsload` as an external view utility. `FloorGetter` only wraps that public interface in typed getters and does not create a new write or theft primitive. |
| other | opencode_1 | Delegatecall in Multicall Allows Contract Hijacking | `multicall` delegatecalls only into `address(this)`, i.e. `FloorGetter`'s own functions. It does not execute attacker-supplied bytecode, and `FloorGetter` exposes no state-mutating external methods to hijack storage. |
| other | opencode_1 | Missing Reentrancy Guards | No concrete exploit path was identified. The periphery keeps almost no mutable state, and the cited external calls either revert atomically on failure or target trusted immutable dependencies. |
| other | opencode_1 | No Deadline Validation in Swap Execution | The Universal Router already enforces the deadline; its interface explicitly states that `execute` reverts when the deadline has passed. |
| low_impact_or_operational | opencode_1 | Missing Input Size Limits - DoS Vector | Unbounded arrays here only risk the caller exhausting their own gas and reverting their own transaction. They do not create a persistent or permissionless protocol-wide DoS condition. |
| other | opencode_1 | Unchecked Permit2 Permit Results | Permit2 `permit` and `permitTransferFrom` do not return booleans. They revert on failure, so there is no ignored success value. |
| unsupported_or_speculative | opencode_1 | No Signature Expiration in Permit2 Signature Transfer | Permit2 signature-transfer structs include `deadline`, and Permit2 also uses nonce-based replay protection. The claimed indefinite replay issue is not supported by the interface. |
| other | opencode_1 | Inconsistent Validation in Batch Transfer | Supplying malformed transfer parameters only misconfigures the caller's own transaction. No protocol-level exploit or third-party harm follows from the cited code. |
| trust_or_owner_model | opencode_1 | Missing Emit on Ownership Transfer | `setOwner` does emit `OwnerUpdated`, and the broader complaint is about observability rather than a security vulnerability. |
| duplicate_or_subsumed | opencode_1 | Incorrect Balance Check in _executeSwap | A failed router call reverts the whole transaction, so ETH is not stranded by swap failure itself. The real issue is successful refunds and residual pooled balances, which is already captured in F-001. |
