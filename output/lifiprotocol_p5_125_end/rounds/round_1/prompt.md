You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/lifiprotocol/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x1231deb6f5749ef6ce6943a275a1d3e7486f4eae/src/Errors/GenericErrors.sol (41 LOC) — TODO
- 0x1231deb6f5749ef6ce6943a275a1d3e7486f4eae/src/Interfaces/IDiamondCut.sol (31 LOC) — TODO
- 0x1231deb6f5749ef6ce6943a275a1d3e7486f4eae/src/LiFiDiamond.sol (67 LOC) — TODO
- 0x1231deb6f5749ef6ce6943a275a1d3e7486f4eae/src/Libraries/LibBytes.sol (514 LOC) — TODO
- 0x1231deb6f5749ef6ce6943a275a1d3e7486f4eae/src/Libraries/LibDiamond.sol (270 LOC) — TODO
- 0x1231deb6f5749ef6ce6943a275a1d3e7486f4eae/src/Libraries/LibUtil.sol (22 LOC) — TODO
- 0xa74c9c1b2194f27c372b0892839624852de21687/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol (78 LOC) — TODO
- 0xa74c9c1b2194f27c372b0892839624852de21687/lib/solady/src/utils/SafeTransferLib.sol (559 LOC) — TODO
- 0xa74c9c1b2194f27c372b0892839624852de21687/src/Errors/GenericErrors.sol (42 LOC) — TODO
- 0xa74c9c1b2194f27c372b0892839624852de21687/src/Facets/GenericSwapFacet.sol (60 LOC) — TODO
- 0xa74c9c1b2194f27c372b0892839624852de21687/src/Helpers/ReentrancyGuard.sol (52 LOC) — TODO
- 0xa74c9c1b2194f27c372b0892839624852de21687/src/Helpers/SwapperV2.sol (328 LOC) — TODO
- 0xa74c9c1b2194f27c372b0892839624852de21687/src/Helpers/Validatable.sol (76 LOC) — TODO
- 0xa74c9c1b2194f27c372b0892839624852de21687/src/Interfaces/ILiFi.sol (76 LOC) — TODO
- 0xa74c9c1b2194f27c372b0892839624852de21687/src/Libraries/LibAllowList.sol (109 LOC) — TODO
- 0xa74c9c1b2194f27c372b0892839624852de21687/src/Libraries/LibAsset.sol (210 LOC) — TODO
- 0xa74c9c1b2194f27c372b0892839624852de21687/src/Libraries/LibBytes.sol (128 LOC) — TODO
- 0xa74c9c1b2194f27c372b0892839624852de21687/src/Libraries/LibSwap.sol (109 LOC) — TODO
- 0xa74c9c1b2194f27c372b0892839624852de21687/src/Libraries/LibUtil.sol (34 LOC) — TODO

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
