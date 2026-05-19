# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 11

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Team fee is never removed from reflected transfers, minting unbacked tokens on every taxed transfer | codex_1:1.0 Team fee is never removed from reflected transfers, minting unbacked tokens on every taxed transfer |
| F-002 | rewritten_agent_signal | High | high | codex_1 | The Uniswap pair is left reflection-eligible, allowing surplus LP tokens to be skimmed | codex_1:0.643 The Uniswap pair is reward-eligible, allowing anyone to skim reflected tokens from LP |
| F-003 | exact_agent_candidate | High | high | codex_1,opencode_1 | Auto-swaps are trivially sandwichable because contract sells use `amountOutMin = 0` | codex_1:0.899 Auto-swaps are trivially sandwichable because the contract market-sells with `amountOutMin = 0` |
| F-004 | rewritten_agent_signal | Medium | medium | codex_1 | ETH payouts use `.transfer()`, so a reverting team wallet can block auto-swaps and non-buy transfers at the threshold | codex_1:0.7 ETH forwarding via `.transfer()` can DOS auto-swaps and block non-buy transfers at the fee threshold |

## Rejection Reasons
- other: 8
- trust_or_owner_model: 3

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | Owner Can Exclude Accounts From Fees and Drain Liquidity | `setExcludeFromFee()` is an explicit privileged configuration knob. Fee exemption by itself does not create an unauthorized drain path or a distinct protocol bug under a standard owner-trusted threat model. |
| other | opencode_1 | Owner Can Change Fee Parameters to 0% | False. The external setters enforce `1..25`; `removeAllFee()` is private and only used transiently during fee-exempt transfers. |
| trust_or_owner_model | opencode_1 | Insufficient Access Control on Manual Send Functions | `manualSend()` is an intended `onlyOwner` treasury forwarding function, not an access-control mistake. |
| other | opencode_1 | No Events Emitted for Critical Parameter Changes | Informational only and not a realistic protocol-impact vulnerability. |
| other | opencode_1 | Missing Validation for Zero Address in setExcludeFromFee | No realistic exploit or protocol harm follows from toggling fee exclusion on `address(0)`. |
| other | opencode_1 | Hardcoded Swap Router Address with No Migration Path | This is a design tradeoff, not a concrete exploitable vulnerability in the deployed logic. |
| other | opencode_1 | receive() Function Accepts Any ETH Without Conditions | Accepting ETH is required for swap proceeds and accidental ETH receipts do not create protocol harm on their own. |
| other | opencode_1 | Lack of Input Validation in includeAccount | No exploit path was substantiated; including an address with zero balance does not create meaningful harm. |
| other | opencode_1 | Token Burns Through Deliver Break Reflection Model | `deliver()` is a standard reflection-token mechanism where callers voluntarily reduce their own reflected balance to benefit other holders; no protocol-breaking flaw is shown. |
| other | opencode_1 | Unlimited Token Mint Through includeAccount | False. `excludeAccount()`/`includeAccount()` only convert between reflected and token-denominated bookkeeping and `includeAccount()` explicitly zeroes `_tOwned[account]`; they do not mint tokens. |
| trust_or_owner_model | opencode_1 | Owner Can Disable All Transfers Through maxTxAmount | False. `_setMaxTxAmount()` only allows values greater than or equal to `100000000000000e9`, which is above the token's total supply, so the owner cannot lower it to freeze transfers. |
