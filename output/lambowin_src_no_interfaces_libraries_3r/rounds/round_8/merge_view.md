# Merge View - Round 8

## Summary
- total findings: 19
- new findings: 2
- updated existing findings: 0
- rejected candidates: 3

## Finding Actions
- exact_agent_candidate: 2
- existing_preserved: 17

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-018 | exact_agent_candidate | Medium | medium | codex_1 | Valid factories can mint debt into existing pairs as phantom swap input | codex_1:1.0 Valid factories can mint debt into existing pairs as phantom swap input |
| F-019 | exact_agent_candidate | Low | low | codex_1 | Permissionless rebalance accepts arbitrary trade sizes unrelated to the preview target | codex_1:0.942 Permissionless rebalance can use arbitrary trade sizes unrelated to the preview target |

## Rejection Reasons
- other: 2
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | LamboToken implementation can be initialized and minted by anyone | The code supports direct initialization of the implementation contract, but clone storage is separate and factory-created clones still initialize normally. The impact is limited to a counterfeit-looking standalone implementation token/social confusion, not protocol-level fund loss or invariant break. |
| other | codex_1 | Router has no ERC20 recovery path for stuck token balances | Direct ERC20 transfers to almost any contract can become stuck, and no standard router flow was shown to leave recoverable ERC20 residuals. The native ETH recovery/dust issue is already tracked in F-015; this broader ERC20 version is not a distinct protocol-level vulnerability. |
| trust_or_owner_model | codex_1 | Fee configuration permits 100% sell-fee confiscation and buy-side DoS | This is an owner-controlled fee-policy parameter rather than a permissionless exploit. Users can observe feeRate and protect sells with minReturn; buy disablement or confiscatory fees require privileged admin action, so it is not retained as a reportable vulnerability. |
