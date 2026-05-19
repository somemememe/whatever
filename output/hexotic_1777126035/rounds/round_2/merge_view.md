# Merge View - Round 2

## Summary
- total findings: 2
- new findings: 0
- updated existing findings: 0
- rejected candidates: 3

## Finding Actions
- existing_preserved: 2

## New Or Updated Findings
- none

## Rejection Reasons
- other: 2
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Hardcoded mainnet HEX address can brick or mis-settle the market on the wrong chain | This is a deployment/configuration hazard rather than an in-protocol exploit: the code is explicitly pinned to one token address, and harm arises only if operators deploy it on an unintended chain or fork. |
| unsupported_or_speculative | codex | Settlement trusts ERC20 return values instead of verifying exact token movement | The contract is not token-agnostic; it hardcodes a single HEX address. The proposed short-transfer/malicious-token scenarios require either a non-standard token at that address or an already-misdeployed market, making the issue too speculative as a standalone finding. |
| other | codex | ETH or HEX sent outside offer flows becomes permanently stranded | This only affects unsolicited or accidental transfers outside the supported offer workflow, and does not create protocol-level insolvency, theft, or permissionless DoS within intended usage. |
