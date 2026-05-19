# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 3

## Finding Actions
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex,merge-review | Permissionless market creation lets attackers register arbitrary redemption assets and exchange-rate providers | codex:0.509 Module creation trusts an attacker-controlled rate provider |
| F-002 | rewritten_agent_signal | Critical | high | codex,merge-review | CorkHook.beforeSwap can be called directly with forged swap context | codex:0.446 Swap-hook entrypoint can be driven with spoofed sender and pool metadata |
| F-006 | rewritten_agent_signal | High | high | merge-review | Near-expiry HIYA manipulation can force newly rolled markets to initialize CT at a severely discounted price | codex:0.376 Reserve-asset redemption is not tightly bound to the correct CT/DS series |

## Rejection Reasons
- other: 3

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Reserve-asset redemption is not tightly bound to the correct CT/DS series | Source shows `returnRaWithCtDs` always redeems the current `globalAssetIdx` CT/DS for the selected market id and burns that exact pair; the PoC's mixed ids are explained by the attacker creating a separate fake market, not by a standalone series-binding bug. |
| other | codex | Raw token donations can manipulate accounting before swap and mint flows | The available source and incident writeups support HIYA manipulation plus unauthenticated `beforeSwap` as the loss drivers; there is no concrete evidence here that unsolicited token transfers into the proxy are directly consumed as trusted pricing/accounting inputs. |
| other | codex | Unlock/settle flow exposes transient proxy balances to attacker-controlled callbacks | The callback abuse is already explained by the missing caller/context validation on `beforeSwap`; no distinct transient-balance accounting flaw is supported beyond that root cause. |
