# Merge View - Round 1

## Summary
- total findings: 0
- new findings: 0
- updated existing findings: 0
- rejected candidates: 3

## Finding Actions
- none

## New Or Updated Findings
- none

## Rejection Reasons
- other: 2
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | Unsafe delegatecall path allows arbitrary wallet storage corruption | `Bybit.sol` is a PoC that invokes an external Safe via `execTransaction`; it does not implement the victim wallet logic. Allowing owner-approved `DelegateCall` is an expected Safe capability, and this code shows an attack workflow that depends on externally obtained signatures rather than a missing on-chain authorization check in the audited source. |
| other | codex | Slot-0 storage collision in Trojan replaces the proxy implementation | `Trojan` is an explicitly malicious attacker helper contract included to demonstrate the exploit. Its slot-0 overwrite is intentional payload behavior, not an unintended vulnerability in the audited codebase. |
| other | codex | Backdoor implementation exposes unrestricted ETH and token sweeping | `Backdoor` is likewise an attacker-controlled drain contract in the PoC. Public sweep functions on a malicious contract are expected behavior and do not constitute a reportable issue in the audited source. |
