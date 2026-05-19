# Merge View - Round 1

## Summary
- total findings: 7
- new findings: 7
- updated existing findings: 0
- rejected candidates: 10

## Finding Actions
- exact_agent_candidate: 5
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Broken reflection math mints team-fee tokens out of thin air | codex_1:0.975 Broken reflection math mints `teamFee` tokens out of thin air |
| F-002 | exact_agent_candidate | High | high | codex_1,opencode_1 | Owner can arbitrarily blacklist holders and freeze both inbound and outbound transfers | codex_1:1.0 Owner can arbitrarily blacklist holders and freeze both inbound and outbound transfers |
| F-003 | exact_agent_candidate | High | high | codex_1,opencode_1 | Owner can disable DEX trading at any time and turn the token into a honeypot | codex_1:1.0 Owner can disable DEX trading at any time and turn the token into a honeypot |
| F-004 | exact_agent_candidate | High | high | codex_1,opencode_1 | Owner can set max transaction size to zero and freeze all non-owner transfers | codex_1:1.0 Owner can set max transaction size to zero and freeze all non-owner transfers |
| F-005 | exact_agent_candidate | Medium | medium | codex_1 | Unvalidated fee-wallet updates can brick transfers once auto-swap is triggered | codex_1:0.929 Unvalidated fee-wallet updates can permanently brick transfers once auto-swap is triggered |
| F-006 | rewritten_agent_signal | Medium | medium | opencode_1 | Owner can set an arbitrary cooldown and trap new buyers for an unbounded period | opencode_1:0.492 Owner can arbitrarily blacklist any address |
| F-007 | rewritten_agent_signal | Medium | high | opencode_1 | Owner can raise total transfer fees to 21% at any time | opencode_1:0.673 Owner can set excessive transfer fees up to 21% |

## Rejection Reasons
- low_impact_or_operational: 1
- other: 5
- trust_or_owner_model: 4

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | Owner can steal all contract ETH via manualSend | `manualSend()` only forwards ETH already held by the contract to the configured fee wallets, which is the same destination used by the normal fee-distribution flow; it does not let the owner seize arbitrary user balances. |
| trust_or_owner_model | opencode_1 | Owner can steal all contract tokens via manualSwap | `manualSwap()` only swaps tokens already accumulated by the contract itself, primarily fee tokens intended for later distribution. This is an owner-controlled timing knob, not a distinct theft primitive over user-held funds. |
| trust_or_owner_model | opencode_1 | No transaction limit for owner | Exempting the owner from `_maxTxAmount` is a centralization choice but not, by itself, a realistic exploit causing protocol-level harm to others. |
| other | opencode_1 | Automatic token swap sends ETH to team wallets | This is the intended fee-tokenomics path, not a standalone vulnerability. It only becomes security-relevant in combination with other issues such as the reflection inflation bug or misconfigured fee wallets. |
| other | opencode_1 | Deprecated Solidity version | Using Solidity 0.6.12 is not, on its own, a reportable issue without a concrete exploit path in this contract. |
| other | opencode_1 | Use of deprecated 'now' keyword | `now` is an alias for `block.timestamp` in Solidity 0.6.x and does not create a concrete security issue here. |
| trust_or_owner_model | opencode_1 | Lock function can permanently lock contract | `lock()` stores `_previousOwner` and `unlock()` allows that address to restore ownership after `_lockTime`; this is a standard temporary-lock pattern, not an irreversible loss of control by itself. |
| other | opencode_1 | Blacklist not enforced in all functions | The cited `deliver()` path does not allow blacklisted addresses to transfer, sell, or extract value; at most it lets them voluntarily reduce their reflected balance. |
| other | opencode_1 | Duplicate blacklist entries in constructor | This is a minor code-quality issue with no meaningful security impact. |
| low_impact_or_operational | opencode_1 | Missing event emissions for critical functions | Lack of events is an observability concern, not a realistic protocol-level vulnerability. |
