# Merge View - Round 1

## Summary
- total findings: 7
- new findings: 7
- updated existing findings: 0
- rejected candidates: 10

## Finding Actions
- exact_agent_candidate: 7

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1,opencode_1 | MasterChef migrator can replace real LP collateral with worthless tokens and steal all staked funds | codex_1:1.0 MasterChef migrator can replace real LP collateral with worthless tokens and steal all staked funds |
| F-002 | exact_agent_candidate | High | high | codex_1 | SUSHI governance votes are not updated on transfers, enabling double-counted voting power | codex_1:1.0 SUSHI governance votes are not updated on transfers, enabling double-counted voting power |
| F-003 | exact_agent_candidate | High | high | codex_1 | First xSUSHI minter can steal all SUSHI sent to SushiBar before staking starts | codex_1:1.0 First xSUSHI minter can steal all SUSHI sent to SushiBar before staking starts |
| F-004 | exact_agent_candidate | Low | medium | codex_1 | Transient xSUSHI holders can capture SushiMaker fee conversions meant for long-term stakers | codex_1:1.0 Transient xSUSHI holders can capture SushiMaker fee conversions meant for long-term stakers |
| F-005 | exact_agent_candidate | Medium | high | codex_1 | Stale `pendingOwner` survives direct ownership transfer and can later seize SushiMaker | codex_1:1.0 Stale `pendingOwner` survives direct ownership transfer and can later seize SushiMaker |
| F-006 | exact_agent_candidate | Medium | medium | codex_1 | Reentrant pool tokens can double-claim rewards because MasterChef updates debt after external token transfer | codex_1:0.928 Reentrant pool tokens can double-claim rewards because MasterChef updates debt after external calls |
| F-007 | exact_agent_candidate | Medium | medium | codex_1 | MasterChef over-credits fee-on-transfer tokens, creating withdrawal insolvency and cross-user loss | codex_1:1.0 MasterChef over-credits fee-on-transfer tokens, creating withdrawal insolvency and cross-user loss |

## Rejection Reasons
- factually_incorrect: 1
- other: 6
- trust_or_owner_model: 2
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Missing Parentheses in SushiMaker._swap Causes Incorrect Amount Calculation | False positive: Solidity member-call precedence makes the denominator `reserve*.mul(1000).add(amountInWithFee)`, so the swap formula is already parsed correctly. |
| other | opencode_1 | Timelock Allows Arbitrary Contract Execution Without Validation | By design: a timelock intentionally performs arbitrary queued admin actions after delay; requiring admin compromise is not a distinct contract vulnerability. |
| other | opencode_1 | SushiRoll Migration Lacks Slippage Protection for New Pools | Not a clear vulnerability: the function effectively removes liquidity and re-adds it at current reserves while returning leftovers to the caller; no protocol-side loss mechanism is shown. |
| trust_or_owner_model | opencode_1 | MasterChef Dev Fee Not Transparent | This is a tokenomics/governance choice, not an implementation flaw that creates an exploit path. |
| unsupported_or_speculative | opencode_1 | MasterChef SafeSushiTransfer May Distribute Incorrect Amounts | Not supported as a standalone issue: `safeSushiTransfer` only caps payouts to the contract's actual SUSHI balance to avoid dust/rounding failures and cannot transfer more than it holds. |
| trust_or_owner_model | opencode_1 | MasterChef Pool Allocation Points Have No Upper Bound | Speculative/non-material: SafeMath protects arithmetic, and no realistic exploit or protocol harm is demonstrated from large owner-set allocation points alone. |
| other | opencode_1 | SushiToken Uses Deprecated `now` Keyword | Code-quality concern only; it does not create a realistic security impact in this deployed Solidity version. |
| other | opencode_1 | SushiBar Enter/Leave Functions Subject to Rounding Loss | Expected integer truncation in share accounting; any loss is negligible and not reportable as a security issue. |
| factually_incorrect | opencode_1 | SushiMaker onlyEOA Modifier Can Be Bypassed Via Smart Contract | Incorrect: `require(msg.sender == tx.origin)` rejects calls made through contracts, including the cited mock, so no bypass is demonstrated. |
| other | opencode_1 | Timelock Receive Function Allows Direct ETH Transfers | Accepting ETH is intentional and recoverable through normal timelock-controlled execution; no adversarial exploit path is shown. |
