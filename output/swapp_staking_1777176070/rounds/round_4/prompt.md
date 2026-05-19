You are auditing the smart contracts in /Users/zhanglongqin/audithoundv2/cases/swapp_staking/src.

## Contracts in Scope

# Scope

- Contract.sol (1 LOC) — TODO

# Notes

- Auto-generated file-level map.
- Descriptions are placeholders and can be edited later.




## Known Findings (do not duplicate)

- F-001: Unchecked ERC20 transfer return values allow phantom deposits and silent failed withdrawals (High, high)
- F-002: Deposits credit the requested amount instead of the tokens actually received (High, high)
- F-003: Emergency withdrawal lets users recover principal while retaining stale epoch stake, and untouched pools are immediately eligible (High, high)
- F-004: Any small withdrawal can indefinitely grief the emergency-exit timer for an entire token pool (Medium, high)
- F-005: Dormant pools become unusable until every missed epoch is initialized one transaction at a time (Medium, high)
- F-006: Ignored Compound error codes can desynchronize stablecoin accounting from real liquidity (Medium, high)
- F-007: Anyone can reinitialize epoch 0 to zero and corrupt pre-launch stake snapshots (Medium, low)
- F-008: Direct token transfers or rebases permanently poison non-stable pool-size accounting (Medium, high)
- F-009: Uninitialized historical epochs read mutable current balances instead of fixed snapshots (Low, medium)
- F-010: Permissionless interest-skimming sweeps accidental stablecoin or cToken transfers to the team wallet (Low, high)
- F-011: A failed Compound mint can leave a non-zero allowance that blocks all future stablecoin deposits (Medium, high)

## Optional Prior Round Summary

An optional prior round summary is available at:
- `/Users/zhanglongqin/AuditHoundV2/output/swapp_staking_1777176070/rounds/round_3/round_summary.md`

Read it only if useful, and think it before you use it.It may not be very concise.


## Optional Global Audit Memory

An optional global audit memory is available at:
- `/Users/zhanglongqin/AuditHoundV2/output/swapp_staking_1777176070/global_summary.md`

Read it only if useful. It is historical context, not a coverage guarantee,
not proof that any area is safe, and not a priority list.


## Task

Find security vulnerabilities in the contracts listed above as more as you can.And there are lots of high severity vulns.

You should look for:
- vulnerabilities
- reportable issues

Known findings are not proof that a file, function, or theme is fully audited.
Do not repeat the same root cause, but keep investigating nearby code and related mechanisms.
Report a new finding when it has a distinct root cause, exploit path, impact, or materially stronger version of an existing issue.

Audit only Solidity source files under the target directory above.
Do not inspect or rely on files outside that directory, including README, docs, audit reports, discord exports, scripts, broadcasts, or other repository context, unless they are explicitly included in the target directory.

If you identify a problem that is not fully proven, still report it as a low-confidence finding.
Be skeptical of documented behavior and pure owner-only configuration issues, but you may still report them when they create realistic protocol-level harm such as fund loss, theft, insolvency, permanent lockup, economic manipulation, or permissionless denial of service.

## Output Format

Return ONLY a JSON array.

Each element must have:
- `id`: local finding id such as `F-001`
- `severity`: `Critical` / `High` / `Medium` / `Low` / `Informational`
- `confidence`: `high` / `medium` / `low`
- `title`: one-line summary
- `locations`: array of `file:line`
- `claim`: core mechanism statement
- `impact`: why it matters
- `paths`: array of trigger/exploit paths, may be empty

If there are no findings, return `[]`.
