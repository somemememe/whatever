You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/indexedfinance/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x120c6956d292b800a835cb935c9dd326bdb4e011/@indexed-finance/proxies/contracts/CodeHashes.sol (14 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/@indexed-finance/proxies/contracts/SaltyLib.sol (144 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/@indexed-finance/proxies/contracts/interfaces/IDelegateCallProxyManager.sol (221 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/@indexed-finance/uniswap-v2-oracle/contracts/interfaces/IIndexedUniswapV2Oracle.sol (100 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/@indexed-finance/uniswap-v2-oracle/contracts/lib/FixedPoint.sol (84 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/@indexed-finance/uniswap-v2-oracle/contracts/lib/PriceLibrary.sol (196 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/@indexed-finance/uniswap-v2-oracle/contracts/lib/UniswapV2Library.sol (54 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/@indexed-finance/uniswap-v2-oracle/contracts/lib/UniswapV2OracleLibrary.sol (145 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/@openzeppelin/contracts/GSN/Context.sol (24 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/@openzeppelin/contracts/math/SafeMath.sol (159 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/@openzeppelin/contracts/token/ERC20/IERC20.sol (77 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/@openzeppelin/contracts/utils/Create2.sol (59 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol (52 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/MarketCapSortedTokenCategories.sol (364 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/MarketCapSqrtController.sol (642 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/OwnableProxy.sol (100 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/interfaces/IIndexPool.sol (202 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/interfaces/IPoolFactory.sol (35 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/interfaces/IPoolInitializer.sol (60 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/interfaces/IUnboundTokenSeller.sol (71 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/lib/Babylonian.sol (31 LOC) — TODO
- 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/lib/MCapSqrtLibrary.sol (103 LOC) — TODO
- 0xf00a38376c8668fc1f3cd3daeef42e0e44a7fcdb/@openzeppelin/contracts/GSN/Context.sol (24 LOC) — TODO
- 0xf00a38376c8668fc1f3cd3daeef42e0e44a7fcdb/@openzeppelin/contracts/access/Ownable.sol (68 LOC) — TODO
- 0xf00a38376c8668fc1f3cd3daeef42e0e44a7fcdb/@openzeppelin/contracts/proxy/Proxy.sol (83 LOC) — TODO
- 0xf00a38376c8668fc1f3cd3daeef42e0e44a7fcdb/@openzeppelin/contracts/utils/Address.sol (141 LOC) — TODO
- 0xf00a38376c8668fc1f3cd3daeef42e0e44a7fcdb/@openzeppelin/contracts/utils/Create2.sol (59 LOC) — TODO
- 0xf00a38376c8668fc1f3cd3daeef42e0e44a7fcdb/temp-contracts/CodeHashes.sol (14 LOC) — TODO
- 0xf00a38376c8668fc1f3cd3daeef42e0e44a7fcdb/temp-contracts/DelegateCallProxyManager.sol (514 LOC) — TODO
- 0xf00a38376c8668fc1f3cd3daeef42e0e44a7fcdb/temp-contracts/DelegateCallProxyManyToOne.sol (51 LOC) — TODO
- 0xf00a38376c8668fc1f3cd3daeef42e0e44a7fcdb/temp-contracts/DelegateCallProxyOneToOne.sol (73 LOC) — TODO
- 0xf00a38376c8668fc1f3cd3daeef42e0e44a7fcdb/temp-contracts/ManyToOneImplementationHolder.sol (47 LOC) — TODO
- 0xf00a38376c8668fc1f3cd3daeef42e0e44a7fcdb/temp-contracts/SaltyLib.sol (144 LOC) — TODO
- 0xf00a38376c8668fc1f3cd3daeef42e0e44a7fcdb/temp-contracts/interfaces/IDelegateCallProxyManager.sol (221 LOC) — TODO

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
