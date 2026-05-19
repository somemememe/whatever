You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/88mph/src.

## Contracts in Scope

# Scope

- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/GSN/Context.sol (27 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/access/Roles.sol (36 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/access/roles/SignerRole.sol (44 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/drafts/Counters.sol (38 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/introspection/ERC165.sol (52 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/introspection/IERC165.sol (22 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/math/Math.sol (29 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/math/SafeMath.sol (156 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/ownership/Ownable.sol (77 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/token/ERC20/ERC20.sol (230 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol (27 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol (54 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/token/ERC20/IERC20.sol (76 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/token/ERC20/SafeERC20.sol (75 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/token/ERC721/ERC721.sol (366 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/token/ERC721/ERC721Metadata.sol (129 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/token/ERC721/IERC721.sol (53 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/token/ERC721/IERC721Metadata.sol (13 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol (25 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/utils/Address.sol (70 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/@openzeppelin/contracts/utils/ReentrancyGuard.sol (55 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol (943 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterestWithDepositFee.sol (978 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/NFT.sol (101 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/NFTFactory.sol (36 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/fractionals/FractionalDeposit.sol (161 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/fractionals/FractionalDepositFactory.sol (83 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/fractionals/ZeroCouponBond.sol (205 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/fractionals/ZeroCouponBondFactory.sol (43 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/libs/CloneFactory.sol (59 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/libs/DecMath.sol (18 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/mocks/ATokenMock.sol (56 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/mocks/CERC20Mock.sol (78 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/mocks/ComptrollerMock.sol (21 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/mocks/ERC20Mock.sol (16 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/mocks/HarvestStakingMock.sol (228 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/mocks/LendingPoolAddressesProviderMock.sol (14 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/mocks/LendingPoolMock.sol (56 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/mocks/VaultMock.sol (40 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/mocks/VaultWithDepositFeeMock.sol (52 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/models/fee/IFeeModel.sol (10 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/models/fee/PercentageFeeModel.sol (31 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/models/interest/IInterestModel.sol (11 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/models/interest/LinearInterestModel.sol (32 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/models/interest-oracle/EMAOracle.sol (75 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/models/interest-oracle/IInterestOracle.sol (9 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/models/issuance/IMPHIssuanceModel.sol (95 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/models/issuance/MPHIssuanceModel01.sol (260 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/moneymarkets/IMoneyMarket.sol (26 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/moneymarkets/aave/AaveMarket.sol (93 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/moneymarkets/aave/imports/ILendingPool.sol (51 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/moneymarkets/aave/imports/ILendingPoolAddressesProvider.sol (13 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/moneymarkets/compound/CompoundERC20Market.sol (106 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/moneymarkets/compound/imports/ICERC20.sol (73 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/moneymarkets/compound/imports/IComptroller.sol (9 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/moneymarkets/cream/CreamERC20Market.sol (85 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/moneymarkets/cream/imports/ICERC20.sol (73 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/moneymarkets/harvest/HarvestMarket.sol (112 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/moneymarkets/harvest/imports/HarvestStaking.sol (15 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/moneymarkets/harvest/imports/HarvestVault.sol (40 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/moneymarkets/yvault/YVaultMarket.sol (82 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/moneymarkets/yvault/imports/Vault.sol (40 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/rewards/IRewards.sol (6 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/rewards/MPHMinter.sol (272 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/rewards/MPHToken.sol (29 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/rewards/Rewards.sol (228 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/rewards/Vesting.sol (101 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/rewards/dumpers/Dumper.sol (14 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/rewards/dumpers/OneSplitDumper.sol (74 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/rewards/dumpers/imports/Curve.sol (45 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/rewards/dumpers/imports/OneSplitAudit.sol (25 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/rewards/dumpers/imports/yERC20.sol (14 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/rewards/dumpers/withdrawers/CurveLPWithdrawer.sol (69 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/rewards/dumpers/withdrawers/YearnWithdrawer.sol (13 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/zaps/ZapCurve.sol (164 LOC) — TODO
- onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/zaps/imports/CurveZapIn.sol (20 LOC) — TODO

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
