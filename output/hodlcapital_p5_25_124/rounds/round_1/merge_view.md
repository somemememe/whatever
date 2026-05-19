# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1 | Reflection math omits the team fee from `rTransferAmount`, inflating balances and creating sellable phantom fee tokens | codex_1:0.717 Reflection math omits the team fee from `rTransferAmount`, minting phantom tokens on every taxed transfer |
| F-002 | exact_agent_candidate | High | high | codex_1 | The Uniswap pair is left reflection-enabled, allowing anyone to skim reflected tokens out of LP | codex_1:0.876 The Uniswap pair remains reflection-enabled, so anyone can skim reflected tokens out of LP |
| F-003 | rewritten_agent_signal | Medium | high | codex_1 | Publicly triggerable swapback sells accumulated fees with `amountOutMin = 0`, making treasury dumps sandwichable | codex_1:0.768 Publicly triggerable swapback uses `amountOutMin = 0`, making accumulated fees sandwichable |
| F-004 | rewritten_agent_signal | Medium | high | codex_1 | Fee-wallet ETH forwarding via `.transfer()` can brick swapback and block sells/transfers once the threshold is reached | codex_1:0.691 ETH forwarding via `.transfer()` can permanently brick sells and transfers once swapback is reached |

## Rejection Reasons
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex_1 | Unbounded `_excluded` iteration lets the owner gas-brick core token operations | The loop is real, but exploitation requires a long sequence of deliberate owner-only `excludeAccount()` calls. This is privileged self-griefing rather than an intrinsic or permissionless protocol vulnerability, so it is not kept as a reportable issue. |
