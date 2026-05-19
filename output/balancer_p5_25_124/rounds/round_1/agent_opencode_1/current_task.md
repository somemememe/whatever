You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/balancer/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-asset-manager-utils/contracts/IAssetManager.sol (81 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-pool-utils/contracts/BalancerPoolToken.sol (111 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-pool-utils/contracts/BasePool.sol (710 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-pool-utils/contracts/BasePoolAuthorization.sol (62 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-pool-utils/contracts/interfaces/IRateProvider.sol (23 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-pool-utils/contracts/rates/PriceRateCache.sol (91 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/helpers/Authentication.sol (69 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/helpers/BalancerErrors.sol (235 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/helpers/ERC20Helpers.sol (92 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/helpers/IAuthentication.sol (22 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/helpers/ISignaturesValidator.sol (30 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/helpers/ITemporarilyPausable.sol (37 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/helpers/InputHelpers.sol (55 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/helpers/TemporarilyPausable.sol (136 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/helpers/WordCodec.sol (343 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol (136 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/math/LogExpMath.sol (514 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/math/Math.sol (97 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/misc/IWETH.sol (27 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/openzeppelin/EIP712.sol (87 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ERC20.sol (326 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ERC20Permit.sol (74 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/openzeppelin/IERC20.sol (81 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/openzeppelin/IERC20Permit.sol (59 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/openzeppelin/SafeMath.sol (68 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-vault/contracts/interfaces/IAsset.sol (26 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-vault/contracts/interfaces/IAuthorizer.sol (26 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-vault/contracts/interfaces/IBasePool.sol (91 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-vault/contracts/interfaces/IFlashLoanRecipient.sol (37 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-vault/contracts/interfaces/IGeneralPool.sol (38 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-vault/contracts/interfaces/IPoolSwapStructs.sol (59 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-vault/contracts/interfaces/IProtocolFeesCollector.sol (46 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-vault/contracts/interfaces/IVault.sol (771 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/LinearMath.sol (336 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/LinearPool.sol (669 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/LinearPoolUserData.sol (29 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/aave/AaveLinearPool.sol (65 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/interfaces/ILendingPool.sol (22 LOC) — TODO
- 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/interfaces/IStaticAToken.sol (36 LOC) — TODO

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
