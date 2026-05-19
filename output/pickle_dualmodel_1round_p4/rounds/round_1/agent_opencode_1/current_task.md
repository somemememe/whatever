You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/pickle/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/controller-v4.sol (369 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/governance/timelock.sol (122 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/interfaces/compound.sol (298 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/interfaces/controller.sol (19 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/interfaces/converter.sol (6 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/interfaces/curve.sol (177 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/interfaces/jar-converter.sol (10 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/interfaces/jar.sol (20 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/interfaces/masterchef.sol (83 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/interfaces/onesplit.sol (24 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/interfaces/proxy.sol (13 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/interfaces/staking-rewards.sol (81 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/interfaces/strategy.sol (42 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/interfaces/uniswapv2.sol (214 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/interfaces/usdt.sol (11 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/interfaces/weth.sol (31 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/lib/careful-math.sol (85 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/lib/context.sol (24 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/lib/enumerableSet.sol (243 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/lib/erc20.sol (596 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/lib/exponential.sol (349 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/lib/ownable.sol (68 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/lib/owned.sol (43 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/lib/pausable.sol (48 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/lib/reentrancy-guard.sol (62 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/lib/safe-math.sol (159 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/pickle-jar.sol (130 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/pickle-swap.sol (99 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/proxy-logic/curve.sol (55 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/proxy-logic/uniswapv2.sol (245 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/staking-rewards.sol (200 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/strategies/compound/strategy-cmpd-dai-v2.sol (393 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/strategies/curve/crv-locker.sol (89 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/strategies/curve/scrv-voter.sol (175 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/strategies/curve/strategy-curve-3crv-v2.sol (126 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/strategies/curve/strategy-curve-rencrv-v2.sol (108 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/strategies/curve/strategy-curve-scrv-v3_2.sol (153 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/strategies/curve/strategy-curve-scrv-v4_1.sol (198 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/strategies/strategy-base.sol (301 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/strategies/strategy-curve-base.sol (87 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/strategies/strategy-staking-rewards-base.sol (52 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/strategies/strategy-uni-farm-base.sol (109 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/strategies/uniswapv2/strategy-uni-eth-dai-lp-v4.sol (35 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/strategies/uniswapv2/strategy-uni-eth-usdc-lp-v4.sol (35 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/strategies/uniswapv2/strategy-uni-eth-usdt-lp-v4.sol (35 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/strategies/uniswapv2/strategy-uni-eth-wbtc-lp-v2.sol (35 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/jar-converters/curve-curve.test.sol (559 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/jar-converters/curve-uni.sol (735 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/jar-converters/uni-curve.sol (944 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/jar-converters/uni-uni.test.sol (388 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/lib/hevm.sol (7 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/lib/mock-erc20.sol (16 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/lib/test-approx.sol (30 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/lib/test-defi-base.sol (247 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/lib/test-strategy-curve-farm-base.sol (101 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/lib/test-strategy-uni-farm-base.sol (121 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/lib/test.sol (144 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/lib/user.sol (31 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/pickle-swap.test.sol (50 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/staking-rewards.test.sol (95 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/strategies/compound/strategy-cmpnd-dai-v2.sol (377 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/strategies/curve/strategy-curve-3crv-v2.test.sol (83 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/strategies/curve/strategy-curve-rencrv-v2.test.sol (83 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/strategies/curve/strategy-curve-scrv-v3_2.test.sol (83 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/strategies/curve/strategy-curve-scrv-v4_1.test.sol (217 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/strategies/uniswapv2/strategy-uni-eth-dai-lp-v4.test.sol (73 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/strategies/uniswapv2/strategy-uni-eth-usdc-lp-v4.test.sol (73 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/strategies/uniswapv2/strategy-uni-eth-usdt-lp-v4.test.sol (73 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/strategies/uniswapv2/strategy-uni-eth-wbtc-lp-v2.test.sol (73 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/tests/uni-curve-converter.sol (58 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/uni-curve-converter.sol (181 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/voting/PicklesInTheCitadel.sol (86 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/yield-farming/masterchef.sol (292 LOC) — TODO
- 0x6847259b2b3a4c17e7c43c54409810af48ba5210/src/yield-farming/pickle-token.sol (12 LOC) — TODO

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
