# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 8

## Finding Actions
- exact_agent_candidate: 4
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | Anyone can invoke the Balancer callback and force arbitrary leveraging or deleveraging | codex_1:0.832 Anyone can invoke the Balancer callback and force unauthorized deleveraging |
| F-002 | exact_agent_candidate | Critical | high | codex_1 | Idle ETH is excluded from NAV, so deposits can mint massively underpriced shares | codex_1:1.0 Idle ETH is excluded from NAV, so deposits can mint massively underpriced shares |
| F-003 | exact_agent_candidate | Critical | high | codex_1,opencode_1 | Unpaused withdrawals transfer the vault's entire ETH balance to the caller | codex_1:1.0 Unpaused withdrawals transfer the vault's entire ETH balance to the caller |
| F-004 | exact_agent_candidate | High | medium | codex_1,opencode_1 | All Curve swaps use `min_dy = 0`, enabling sandwich extraction and arbitrary bad execution | codex_1:1.0 All Curve swaps use `min_dy = 0`, enabling sandwich extraction and arbitrary bad execution |
| F-005 | exact_agent_candidate | High | medium | codex_1 | Withdrawals and emergency pause can become impossible during a stETH depeg or severe pool illiquidity | codex_1:1.0 Withdrawals and emergency pause can become impossible during a stETH depeg or severe pool illiquidity |

## Rejection Reasons
- other: 3
- trust_or_owner_model: 4
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Division by zero in getVirtualPrice when totalSupply is zero | `getVirtualPrice()` explicitly returns 0 when `totalSupply() == 0`, so this division-by-zero claim is false. |
| trust_or_owner_model | opencode_1 | Division by zero in _earnReward when volume equals st_fee | This only arises from owner-controlled fee configuration or extreme parameter choices; it is not a realistic unprivileged protocol bug under the contract's trust model. |
| trust_or_owner_model | opencode_1 | Owner can steal all funds via callWithData with delegatecall | This is an explicit owner backdoor/admin power, not an unintended permissionless vulnerability. |
| unsupported_or_speculative | opencode_1 | Inconsistent debt calculation in _withdraw causes incorrect token redemption | `steth_amount = amount * aStETH / getDebt()` is the intended proportional redemption calculation before repayment; the reported inconsistency is unsupported. |
| other | opencode_1 | Owner can set fee_pool to any address including EOA | Minting fee shares to an EOA does not lock them; EOAs can hold and transfer ERC20-like tokens normally. |
| trust_or_owner_model | opencode_1 | No access control on critical Aave operations allows griefing | `reduceActualLTV()` and `raiseActualLTV()` are both protected by `onlyOwner`, so the claim is factually incorrect. |
| other | opencode_1 | Hardcoded protocol addresses create centralization risk | Hardcoded integration addresses are a design choice and do not by themselves create a concrete reportable vulnerability. |
| trust_or_owner_model | opencode_1 | block_rate initialized to zero, no rewards until configured | A zero default fee rate before owner configuration is expected initialization behavior, not a security issue. |
