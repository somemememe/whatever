# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 12

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Owner-controlled blacklist can freeze holders and disable trading | codex_1:0.548 Owner-controlled blacklist can turn the token into a selective or global honeypot |
| F-002 | exact_agent_candidate | Critical | high | codex_1 | Initial LP tokens are minted to the owner, enabling an unrestricted liquidity rug pull | codex_1:1.0 Initial LP tokens are minted to the owner, enabling an unrestricted liquidity rug pull |
| F-003 | rewritten_agent_signal | Medium | medium | codex_1 | Sells can become permanently unexecutable if the immutable tax wallet rejects ETH transfers | codex_1:0.645 Sells can be permanently DOSed once tax swaps start if the tax wallet cannot receive `transfer` |

## Rejection Reasons
- other: 6
- trust_or_owner_model: 5
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | No function to remove liquidity - liquidity permanently locked | Incorrect. `openTrading()` sends LP tokens to `owner()`, not to the contract, so liquidity is not locked; the real issue is the opposite rug-pull risk captured in F-002. |
| trust_or_owner_model | opencode_1 | No timelock on critical owner actions - instant rug pull possible | Generic governance-centralization criticism, not a distinct exploitable bug beyond the specific blacklist and LP-control findings already reported. |
| trust_or_owner_model | opencode_1 | Tax collected goes to single EOA wallet with no multisig | Single-key trust and treasury-governance concerns are not by themselves protocol vulnerabilities here. |
| other | opencode_1 | Uniswap V2 router hardcoded - no upgrade path | Lack of upgradeability is a design choice, not a concrete exploit path for this target. |
| trust_or_owner_model | opencode_1 | Owner can remove all transaction limits enabling large transfers | This is a privileged tokenomics control, but by itself it does not create a concrete protocol-level exploit or loss scenario distinct from the other owner-abuse findings. |
| trust_or_owner_model | opencode_1 | Infinite approval to Uniswap router on LP token | `IERC20(uniswapV2Pair).approve(...)` is granted from the token contract, but LP tokens from `openTrading()` are minted to `owner()`, so the contract does not receive LP tokens to be drained through that approval. |
| other | opencode_1 | Trading can only be opened once - no recovery if stuck | `openTrading()` is atomic; if any step fails, the whole transaction reverts, so there is no partial stuck state from a failed call. |
| other | opencode_1 | Bot check bypassable - returns false for contracts in first 3 blocks | Ineffective anti-bot logic is not a reportable vulnerability without a concrete exploit causing protocol-level harm. |
| other | opencode_1 | Swap threshold and amounts are fixed constants | Parameter rigidity and price-impact tuning are design concerns, not concrete security vulnerabilities. |
| other | opencode_1 | Public isBot() function exposes blacklist | Public visibility of blacklist status does not create meaningful protocol harm. |
| other | opencode_1 | SafeMath library is obsolete - Solidity 0.8+ has built-in overflow checks | Informational code-style observation only; not a vulnerability. |
| unsupported_or_speculative | codex_1 | Hardcoded router plus unlimited approvals can hand contract-held tokens to arbitrary code off-mainnet | Too deployment-dependent and speculative for this target. Without evidence the contract is intended for or deployed on a chain where `0x7a250...` is untrusted, this is not a concrete reportable issue. |
