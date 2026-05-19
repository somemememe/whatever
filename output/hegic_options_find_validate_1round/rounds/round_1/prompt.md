You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/hegic_options/src.

## Contracts in Scope

# Scope

- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@chainlink/contracts/src/v0.7/interfaces/AggregatorV3Interface.sol (34 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/access/AccessControl.sol (250 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/access/Ownable.sol (71 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/security/ReentrancyGuard.sol (62 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/token/ERC20/ERC20.sol (354 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/token/ERC20/IERC20.sol (81 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol (27 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol (98 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/token/ERC721/ERC721.sol (411 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/token/ERC721/IERC721.sol (142 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol (26 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol (26 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/utils/Address.sol (210 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/utils/Context.sol (23 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/utils/Strings.sol (66 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/utils/introspection/ERC165.sol (28 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/utils/introspection/IERC165.sol (24 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@uniswap/lib/contracts/libraries/TransferHelper.sol (27 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@uniswap/v2-core/contracts/interfaces/IERC20.sol (17 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol (5 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@uniswap/v2-core/contracts/interfaces/IUniswapV2ERC20.sol (23 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol (17 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol (52 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@uniswap/v2-periphery/contracts/interfaces/IERC20.sol (17 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol (95 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@uniswap/v2-periphery/contracts/interfaces/IWETH.sol (7 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/BondingCurve/ETHBondingCurve.sol (99 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/BondingCurve/Erc20BondingCurve.sol (107 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/BondingCurve/IBondingCurve.sol (13 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/BondingCurve/Linear.sol (47 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/BondingCurve/buysell.sol (26 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Exerciser.sol (46 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol (244 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/HLTPs.sol (69 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Interfaces/IOptionsManager.sol (49 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Interfaces/Interfaces.sol (264 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Mocks/ERC20Mock.sol (46 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Mocks/UniswapRouterMock.sol (82 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Mocks/WETH.sol (33 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Options/AdaptivePriceCalculator.sol (125 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Options/OptionsManager.sol (98 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Options/PriceCalculatorWtihUtilizationRate.sol (156 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Options/SimplePriceCalculator.sol (127 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicCall.sol (64 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol (512 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPut.sol (96 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/HegicStaking.sol (258 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/SettlementFeeDistributor.sol (68 LOC) — TODO
- 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/utils/Math.sol (32 LOC) — TODO

# Notes

- Auto-generated file-level map.
- Descriptions are placeholders and can be edited later.




## Known Findings (do not duplicate)

- F-001: Utilization is enforced on partial collateral, allowing option liabilities to exceed pool assets (Critical, high)
- F-002: Settlement fees are permanently stranded if rewards are distributed before any staking supply exists (Medium, high)
- F-003: Active option premiums are excluded from NAV, letting late LPs buy underpriced shares (Medium, high)
- F-004: Chainlink oracle reads are used without freshness or round-validity checks (High, medium)
- F-005: Anyone can approve attacker-controlled pools to spend arbitrary Facade token balances (High, high)
- F-007: Invalid settlement-fee shares can be stored and later brick distributions (Low, high)
- F-008: Closed liquidity tranches can be withdrawn repeatedly because tranche state is never enforced (Critical, high)
- F-009: LP withdrawals are not limited to unlocked liquidity, so active option collateral can be removed before expiry (High, high)
- F-011: Exact-output option swaps keep unused user input in the Facade (Medium, high)
- F-012: Facade accepts arbitrary payment paths and can spend its own pool-token balance to subsidize options (High, high)
- F-013: Anyone can force early exercise through the public Exerciser once it is approved (Low, high)
- F-014: Zero-value staking-token transfers can indefinitely reset other users' lockups (Medium, high)
- F-101: ETH deposit helper trusts arbitrary pools and can spend the Facade’s internal token balances (High, high)
- F-103: Bonding-curve trades lack slippage protection and are easy to sandwich (Medium, high)


## Optional Global Audit Memory

An optional global audit memory is available at:
- `/Users/zhanglongqin/AuditHoundV2/output/hegic_options_find_validate_1round/global_summary.md`

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
