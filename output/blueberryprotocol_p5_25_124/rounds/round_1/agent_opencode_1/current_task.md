You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/blueberryprotocol/src/onchain_auto.

## Contracts in Scope

# Scope

- 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/BToken.sol (1398 LOC) — TODO
- 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/BTokenInterfaces.sol (563 LOC) — TODO
- 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/CarefulMath.sol (104 LOC) — TODO
- 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol (1570 LOC) — TODO
- 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/ComptrollerInterface.sol (124 LOC) — TODO
- 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/ComptrollerStorage.sol (153 LOC) — TODO
- 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/EIP20Interface.sol (79 LOC) — TODO
- 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/EIP20NonStandardInterface.sol (82 LOC) — TODO
- 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/ERC3156FlashBorrowerInterface.sol (20 LOC) — TODO
- 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/ErrorReporter.sol (191 LOC) — TODO
- 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Exponential.sol (586 LOC) — TODO
- 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/InterestRateModel.sol (38 LOC) — TODO
- 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/LiquidityMiningInterface.sol (11 LOC) — TODO
- 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/PriceOracle/PriceOracle.sol (13 LOC) — TODO
- 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Unitroller.sol (187 LOC) — TODO

# Notes

- Auto-generated file-level map.
- Descriptions are placeholders and can be edited later.




## Known Findings (do not duplicate)

None yet.



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
