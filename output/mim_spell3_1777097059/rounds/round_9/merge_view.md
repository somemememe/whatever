# Merge View - Round 9

## Summary
- total findings: 20
- new findings: 0
- updated existing findings: 0
- rejected candidates: 3

## Finding Actions
- existing_preserved: 20

## New Or Updated Findings
- none

## Rejection Reasons
- trust_or_owner_model: 2
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | Privileged debt injection bypasses both global and per-user borrow caps | `addBorrowPosition()` does bypass `_borrow()`'s cap checks, but the same owner can already call `changeBorrowLimit()` arbitrarily and already has the stronger debt-injection/backdoor power captured in `F-009`; this does not add a distinct reportable harm. |
| trust_or_owner_model | codex | Privileged debt injection relies on a stale cached exchange rate and can bypass its own solvency check | This is an owner-only operational footgun on top of an already privileged debt-injection primitive. The owner can refresh the rate directly and already has stronger market-shaping powers; the stale-price aspect is not a distinct reportable issue here. |
| unsupported_or_speculative | codex | Checkpoint-token failures are silently ignored in privileged collateral and liquidation hooks | The code ignores the boolean return, but without a concrete checkpoint-token implementation this remains too integration-specific and speculative to show realistic protocol-level harm; reverting failures already bubble normally. |
