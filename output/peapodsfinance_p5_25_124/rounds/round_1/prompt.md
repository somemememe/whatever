You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/peapodsfinance/src/onchain_auto.

## Contracts in Scope

# Scope

- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/@openzeppelin/contracts/access/Ownable.sol (68 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/@openzeppelin/contracts/math/SafeMath.sol (214 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/@openzeppelin/contracts/token/ERC20/ERC20.sol (306 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/@openzeppelin/contracts/token/ERC20/IERC20.sol (77 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/@openzeppelin/contracts/token/ERC20/SafeERC20.sol (75 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/@openzeppelin/contracts/utils/Address.sol (189 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/@openzeppelin/contracts/utils/Context.sol (24 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol (21 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/@uniswap/v3-core/contracts/libraries/FixedPoint96.sol (10 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol (12 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol (67 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol (48 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/DecentralizedIndex.sol (281 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/StakingPoolToken.sol (93 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/TokenRewards.sol (238 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/WeightedIndex.sol (189 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/interfaces/IDecentralizedIndex.sol (84 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/interfaces/IERC20Metadata.sol (6 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/interfaces/IFlashLoanRecipient.sol (6 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/interfaces/IPEAS.sol (10 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/interfaces/IStakingPoolToken.sol (20 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/interfaces/ITokenRewards.sol (34 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/interfaces/IUniswapV2Factory.sol (14 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/interfaces/IUniswapV2Pair.sol (13 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/interfaces/IUniswapV2Router02.sol (44 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/interfaces/IV3TwapUtilities.sol (25 LOC) — TODO
- 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/libraries/BokkyPooBahsDateTimeLibrary.sol (79 LOC) — TODO

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
