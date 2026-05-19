You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/sushi_badger_digg/src/onchain_auto.

## Contracts in Scope

# Scope

- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/@openzeppelin/contracts/GSN/Context.sol (24 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/@openzeppelin/contracts/access/Ownable.sol (68 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/@openzeppelin/contracts/math/SafeMath.sol (159 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/@openzeppelin/contracts/token/ERC20/ERC20.sol (306 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/@openzeppelin/contracts/token/ERC20/IERC20.sol (77 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/@openzeppelin/contracts/token/ERC20/SafeERC20.sol (75 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/@openzeppelin/contracts/utils/Address.sol (165 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/@openzeppelin/contracts/utils/EnumerableSet.sol (297 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/BoringOwnable.sol (64 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol (265 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/Migrator.sol (47 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiBar.sol (51 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiMaker.sol (199 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiRoll.sol (140 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiToken.sol (246 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/Timelock.sol (134 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/interfaces/IERC20.sol (14 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/libraries/BoringERC20.sol (31 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/libraries/BoringMath.sol (17 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/mocks/ERC20Mock.sol (15 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/mocks/SushiMakerExploitMock.sol (15 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/mocks/SushiSwapFactoryMock.sol (9 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/mocks/SushiSwapPairMock.sol (9 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/uniswapv2/UniswapV2ERC20.sol (95 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/uniswapv2/UniswapV2Factory.sol (62 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/uniswapv2/UniswapV2Pair.sol (215 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/uniswapv2/UniswapV2Router02.sol (448 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/uniswapv2/interfaces/IERC20.sol (19 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/uniswapv2/interfaces/IUniswapV2Callee.sol (7 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/uniswapv2/interfaces/IUniswapV2ERC20.sol (25 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/uniswapv2/interfaces/IUniswapV2Factory.sol (21 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/uniswapv2/interfaces/IUniswapV2Pair.sol (54 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/uniswapv2/interfaces/IUniswapV2Router01.sol (97 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/uniswapv2/interfaces/IUniswapV2Router02.sol (46 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/uniswapv2/interfaces/IWETH.sol (9 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/uniswapv2/libraries/Math.sol (25 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/uniswapv2/libraries/SafeMath.sol (19 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/uniswapv2/libraries/TransferHelper.sol (29 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/uniswapv2/libraries/UQ112x112.sol (22 LOC) — TODO
- 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/uniswapv2/libraries/UniswapV2Library.sol (84 LOC) — TODO

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
