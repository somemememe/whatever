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
- other: 3

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Unvalidated conversion paths let malicious converters fabricate outputs and drain BancorNetwork-held tokens | The cited behavior is present in `onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol`, but the reportable root cause exists solely in excluded Solidity files (`**/*.sol`). The repository contains no in-scope implementation files that independently introduce or preserve this issue. |
| other | codex | Inbound BancorX completions pull source tokens from the caller instead of BancorX, locking bridged funds | The candidate is supported by excluded Solidity in `onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol`, and there are no non-Solidity implementation files in scope that create a separate reportable root cause. |
| other | codex | ERC20 helper treats calls to non-contract addresses as successful, letting attackers bypass source-funding checks | This is the known Bancor Solidity bug pattern and is supported by excluded code in `onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol`, but findings whose root cause exists solely in `**/*.sol` must be excluded. No in-scope files provide an alternate root cause. |
