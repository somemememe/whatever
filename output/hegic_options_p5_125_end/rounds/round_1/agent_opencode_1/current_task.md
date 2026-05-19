You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/hegic_options/src.

## Contracts in Scope

# Scope

- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@chainlink/contracts/src/v0.7/interfaces/AggregatorV3Interface.sol (34 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/access/AccessControl.sol (250 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/access/Ownable.sol (71 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/security/ReentrancyGuard.sol (62 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/token/ERC20/ERC20.sol (354 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/token/ERC20/IERC20.sol (81 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol (27 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol (98 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/token/ERC721/ERC721.sol (411 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/token/ERC721/IERC721.sol (142 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol (26 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol (26 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/utils/Address.sol (210 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/utils/Context.sol (23 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/utils/Strings.sol (66 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/utils/introspection/ERC165.sol (28 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/utils/introspection/IERC165.sol (24 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@uniswap/lib/contracts/libraries/TransferHelper.sol (27 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@uniswap/v2-core/contracts/interfaces/IERC20.sol (17 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol (5 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@uniswap/v2-core/contracts/interfaces/IUniswapV2ERC20.sol (23 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol (17 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol (52 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@uniswap/v2-periphery/contracts/interfaces/IERC20.sol (17 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol (95 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@uniswap/v2-periphery/contracts/interfaces/IWETH.sol (7 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/BondingCurve/ETHBondingCurve.sol (99 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/BondingCurve/Erc20BondingCurve.sol (107 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/BondingCurve/IBondingCurve.sol (13 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/BondingCurve/Linear.sol (47 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/BondingCurve/buysell.sol (26 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Exerciser.sol (46 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol (244 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/HLTPs.sol (69 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Interfaces/IOptionsManager.sol (49 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Interfaces/Interfaces.sol (264 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Mocks/ERC20Mock.sol (46 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Mocks/UniswapRouterMock.sol (82 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Mocks/WETH.sol (33 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Options/AdaptivePriceCalculator.sol (125 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Options/OptionsManager.sol (98 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Options/PriceCalculatorWtihUtilizationRate.sol (156 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Options/SimplePriceCalculator.sol (127 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicCall.sol (64 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol (512 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPut.sol (96 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/HegicStaking.sol (258 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/SettlementFeeDistributor.sol (68 LOC) — TODO
- onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/utils/Math.sol (32 LOC) — TODO
- onchain_auto/src/FlawVerifier.sol (790 LOC) — TODO

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
