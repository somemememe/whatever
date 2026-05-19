You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/socketgateway/src/onchain_auto.

## Contracts in Scope

# Scope

- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/lib/solmate/src/tokens/ERC20.sol (206 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/lib/solmate/src/utils/SafeTransferLib.sol (128 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/SocketGateway.sol (2367 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/SocketGatewayDeployment.sol (2367 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/BridgeImplBase.sol (131 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/across/Across.sol (316 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/across/interfaces/across.sol (36 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/anyswap-router-v4/l1/Anyswap.sol (217 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/anyswap-router-v4/l2/Anyswap.sol (212 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/anyswap-router-v6/AnyswapV6.sol (285 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/arbitrum/interfaces/arbitrum.sol (43 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/arbitrum/l1/NativeArbitrum.sol (263 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/cbridge/CelerImpl.sol (491 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/cbridge/CelerImplV2.sol (711 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/cbridge/CelerStorageWrapper.sol (71 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/cbridge/interfaces/ICelerStorageWrapper.sol (41 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/cbridge/interfaces/cbridge.sol (30 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/cctp/Cctp.sol (208 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/cctp/interfaces/cctp.sol (11 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/connnext/Connext.sol (297 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/gnosis-native/gnosisNativeImpl.sol (381 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/gnosis-native/interfaces/gnosisBirdge.sol (27 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/interfaces/IHopL1Bridge.sol (33 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/interfaces/amm.sol (30 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/l1/HopImplL1.sol (306 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/l1/HopImplL1V2.sol (358 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/l2/HopImplL2.sol (326 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/l2/HopImplL2V2.sol (430 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hyphen/Hyphen.sol (242 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hyphen/interfaces/hyphen.sol (35 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/optimism/interfaces/optimism.sol (72 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/optimism/l1/NativeOpStack.sol (336 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/optimism/l1/NativeOptimism.sol (411 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/polygon/NativePolygon.sol (259 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/polygon/interfaces/polygon.sol (28 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/refuel/interfaces/refuel.sol (15 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/refuel/refuel.sol (157 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/stargate/interfaces/IStargateEthVault.sol (18 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/stargate/interfaces/stargate.sol (42 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/stargate/l1/Stargate.sol (337 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/stargate/l2/Stargate.sol (347 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/stargate/l2/StargateV2.sol (445 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/symbiosis/SymbiosisBridgeImp.sol (337 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/symbiosis/interfaces/symbiosis.sol (26 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/synapse/SynapseBridgeImpl.sol (296 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/synapse/interfaces/ISynapseRouter.sol (21 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/zksync/ZkSyncBridgeImpl.sol (318 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/zksync/interfaces/IZkSyncL1ERC20Bridge.sol (23 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/zksync/interfaces/IZkSyncL1Mailbox.sol (24 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/controllers/BaseController.sol (59 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/controllers/FeesTakerController.sol (301 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/controllers/RefuelSwapAndBridgeController.sol (60 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/deployFactory/DisabledSocketRoute.sol (71 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/deployFactory/SocketDeployFactory.sol (341 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/errors/SocketErrors.sol (20 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/interfaces/ISocketBridgeBase.sol (6 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/interfaces/ISocketController.sol (37 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/interfaces/ISocketGateway.sol (24 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/interfaces/ISocketRequest.sol (79 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/interfaces/ISocketRoute.sol (33 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/libraries/LibBytes.sol (170 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/libraries/LibUtil.sol (26 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/libraries/Pb.sol (130 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/static/RouteIdentifiers.sol (39 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/swap/SwapImplBase.sol (156 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/swap/oneinch/OneInchImpl.sol (158 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/swap/rainbow/Rainbow.sol (194 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/swap/wrappedTokenSwapper/swapWrappedImpl.sol (170 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/swap/zerox/ZeroXSwapImpl.sol (222 LOC) — TODO
- 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/utils/Ownable.sol (52 LOC) — TODO

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
