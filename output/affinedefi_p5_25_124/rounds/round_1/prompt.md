You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/affinedefi/src/onchain_auto.

## Contracts in Scope

# Scope

- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/@aave/core-v3/contracts/interfaces/IPool.sol (737 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol (227 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol (264 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/@openzeppelin/contracts/access/AccessControl.sol (247 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/@openzeppelin/contracts/access/IAccessControl.sol (88 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/@openzeppelin/contracts/utils/Context.sol (24 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/@openzeppelin/contracts/utils/Strings.sol (75 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/@openzeppelin/contracts/utils/introspection/ERC165.sol (29 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/@openzeppelin/contracts/utils/introspection/IERC165.sol (25 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/@openzeppelin/contracts/utils/math/Math.sol (226 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol (260 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol (88 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol (138 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol (195 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol (37 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol (75 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol (42 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol (25 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/solmate/src/tokens/ERC20.sol (206 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/solmate/src/tokens/WETH.sol (35 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/solmate/src/utils/FixedPointMathLib.sol (222 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/node_modules/solmate/src/utils/SafeTransferLib.sol (124 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/interfaces/AggregatorV3Interface.sol (23 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/interfaces/balancer/IBalancerVault.sol (14 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/interfaces/balancer/IFlashLoanRecipient.sol (22 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/interfaces/balancer.sol (5 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/interfaces/curve/ICurvePool.sol (29 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/interfaces/lido/IWSTETH.sol (13 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/libs/SlippageUtils.sol (18 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/libs/Unchecked.sol (9 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/AccessStrategy.sol (27 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/BaseStrategy.sol (72 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol (347 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/deployed/LidoLevEthStrategy.sol (17 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/utils/AffineGovernable.sol (16 LOC) — TODO
- 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/vaults/AffineVault.sol (522 LOC) — TODO

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
