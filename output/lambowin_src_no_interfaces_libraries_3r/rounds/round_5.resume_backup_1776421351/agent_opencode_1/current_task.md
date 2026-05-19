You are auditing the smart contracts in /Users/lu/Desktop/Red_V1G/2024-12-lambowin/src.

## Contracts in Scope

# Scope

- LamboFactory.sol (84 LOC) — TODO
- LamboToken.sol (290 LOC) — TODO
- LamboVEthRouter.sol (189 LOC) — TODO
- Utils/LaunchPadUtils.sol (25 LOC) — TODO
- VirtualToken.sol (151 LOC) — TODO
- rebalance/LamboRebalanceOnUniwap.sol (169 LOC) — TODO

# Notes

- Auto-generated file-level map.
- Descriptions are placeholders and can be edited later.
- Excluded from direct audit scope: interfaces/**, libraries/**



## Excluded From Direct Audit Scope

Do not report findings whose root cause exists solely in files matching:
- `interfaces/**`
- `libraries/**`

You may still read those files when they define interfaces, structs, errors, or external integration context used by in-scope implementation files.


## Known Findings (do NOT repeat — find NEW issues)

- F-001: VirtualToken.cashIn mints by msg.value for ERC20 underlyings, enabling unbacked minting/mis-accounting (High, high)
- F-002: Permissionless createLaunchPad can consume per-block vETH loan quota and DoS other launches (Medium, high)
- F-003: Router sell pricing uses full vETH reserves including debt-locked liquidity, causing sell reverts and exit lockups (High, high)
- F-004: buyQuote refund logic withholds 1 wei from overpayments (Low, high)
- F-005: Rebalance initialization can be seized if deployment is non-atomic or proxy is left uninitialized (Medium, low)
- F-006: Launchpad creation reverts because factory transfers LP tokens to the zero address (Critical, high)
- F-007: Predictable clone address enables pair pre-creation that can indefinitely brick targeted launch attempts (High, high)
- F-008: Rebalance ignores caller-provided output target and executes swaps with zero minimum return (Low, high)
- F-009: Router and rebalance flows never enforce that configured vETH is native-backed, enabling full functional DoS via misconfiguration (Low, medium)
- F-010: previewRebalance uses raw pool token balances, allowing donation-based signal manipulation (Low, medium)

## Optional Prior Round Summary

An optional prior round summary is available at:
- `/Users/lu/Desktop/Red_V1G/AuditHoundV2/output/lambowin_src_no_interfaces_libraries_3r/rounds/round_4/round_summary.md`

Read it only if useful, and think it before you use it.It may not be very concise.


## Optional Global Audit Memory

An optional global audit memory is available at:
- `/Users/lu/Desktop/Red_V1G/AuditHoundV2/output/lambowin_src_no_interfaces_libraries_3r/global_summary.md`

Read it only if useful. It is historical context, not a coverage guarantee,
not proof that any area is safe, and not a priority list.


## Task

Find security vulnerabilities in the contracts listed above as more as you can.And there are lots of high severity vulns.

You should look for:
- vulnerabilities
- reportable issues

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
