# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 8

## Finding Actions
- rewritten_agent_signal: 5

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Positive rebases desynchronize the AMM pair balance and let sellers extract excess ETH | codex_1:0.785 Positive rebases desynchronize the AMM pair balance and enable ETH drain |
| F-002 | rewritten_agent_signal | High | high | codex_1 | Pre-live buys can permanently blacklist arbitrary victim addresses | codex_1:0.649 Anyone can permanently blacklist arbitrary victims before launch by buying to them |
| F-003 | rewritten_agent_signal | Medium | high | codex_1 | Dust buys can repeatedly reset a holder's cooldown and block timely sells | codex_1:0.589 Dust buys can repeatedly freeze any holder for 5 minutes |
| F-004 | rewritten_agent_signal | Medium | medium | codex_1,opencode_1 | Anyone can permanently disable the intended pre-launch protection | codex_1:0.531 Anyone can permanently blacklist arbitrary victims before launch by buying to them |
| F-005 | rewritten_agent_signal | Low | high | codex_1 | The max-wallet check uses the pre-buy balance, so buyers can exceed the cap | codex_1:0.699 The max-wallet check is performed before the incoming buy, so wallets can exceed the cap |

## Rejection Reasons
- other: 4
- trust_or_owner_model: 4

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | Owner can blacklist any address to permanently block transfers | The owner has no function that sets `blacklist[address] = true`; blacklist entries are only created automatically on pair-to-user buys while `_live` is false. |
| other | opencode_1 | Unlimited token supply expansion via rebase function | The contract does have a positive rebase, but the standalone 'unlimited minting' claim is overstated and does not by itself show protocol-level loss; the real exploitable consequence is the LP balance desynchronization captured in F-001. |
| trust_or_owner_model | opencode_1 | Owner bypasses all transaction limits | The owner exemption is an explicit privileged design choice, not a distinct vulnerability absent a stronger trust-minimization requirement. |
| trust_or_owner_model | opencode_1 | No timelock on critical ownership functions | Lack of a timelock is a governance/design preference and is not a concrete exploitable bug in this contract. |
| other | opencode_1 | First-time buyers bypass time restriction | `_buyInfo == 0` only exempts addresses that have never bought from the pair; that matches the implemented cooldown model rather than exposing a permissionless bypass against tracked buyers. |
| other | opencode_1 | Deprecated Solidity version 0.6.0 | Using an older compiler version is too generic to be a reportable finding without a contract-specific exploit path. |
| trust_or_owner_model | opencode_1 | Permanent ownership renouncement possible | `renounceOwnership()` is standard Ownable behavior; the claimed harm is speculative and not a vulnerability by itself. |
| other | opencode_1 | Inconsistent taxFee parameter not used | `taxFee` is always passed as zero, so this is dead tokenomics code rather than a security-impacting issue. |
