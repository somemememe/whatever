You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/doughfina/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x9f54e8eaa9658316bb8006e03fff1cb191aafbe6/@aave/core-v3/contracts/flashloan/base/FlashLoanReceiverBase.sol (21 LOC) — TODO
- 0x9f54e8eaa9658316bb8006e03fff1cb191aafbe6/@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanReceiver.sol (36 LOC) — TODO
- 0x9f54e8eaa9658316bb8006e03fff1cb191aafbe6/@aave/core-v3/contracts/interfaces/IPool.sol (737 LOC) — TODO
- 0x9f54e8eaa9658316bb8006e03fff1cb191aafbe6/@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol (227 LOC) — TODO
- 0x9f54e8eaa9658316bb8006e03fff1cb191aafbe6/@aave/core-v3/contracts/interfaces/IPoolDataProvider.sol (243 LOC) — TODO
- 0x9f54e8eaa9658316bb8006e03fff1cb191aafbe6/@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol (265 LOC) — TODO
- 0x9f54e8eaa9658316bb8006e03fff1cb191aafbe6/@openzeppelin/contracts/token/ERC20/IERC20.sol (79 LOC) — TODO
- 0x9f54e8eaa9658316bb8006e03fff1cb191aafbe6/@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol (90 LOC) — TODO
- 0x9f54e8eaa9658316bb8006e03fff1cb191aafbe6/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol (118 LOC) — TODO
- 0x9f54e8eaa9658316bb8006e03fff1cb191aafbe6/@openzeppelin/contracts/utils/Address.sol (159 LOC) — TODO
- 0x9f54e8eaa9658316bb8006e03fff1cb191aafbe6/@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol (21 LOC) — TODO
- 0x9f54e8eaa9658316bb8006e03fff1cb191aafbe6/@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol (51 LOC) — TODO
- 0x9f54e8eaa9658316bb8006e03fff1cb191aafbe6/@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol (67 LOC) — TODO
- 0x9f54e8eaa9658316bb8006e03fff1cb191aafbe6/contracts/Interfaces.sol (90 LOC) — TODO
- 0x9f54e8eaa9658316bb8006e03fff1cb191aafbe6/contracts/connectors/ConnectorDeleverageParaswap.sol (400 LOC) — TODO
- 0x9f54e8eaa9658316bb8006e03fff1cb191aafbe6/contracts/libraries/DoughCore.sol (257 LOC) — TODO

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
