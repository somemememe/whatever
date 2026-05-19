# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 12

## Finding Actions
- rewritten_agent_signal: 5

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1 | VirtualToken.cashIn mints by msg.value for ERC20 underlyings, enabling unbacked minting/mis-accounting | codex_1:0.741 VirtualToken cashIn mints by msg.value, enabling unbacked minting for ERC20 underlyings |
| F-002 | rewritten_agent_signal | Medium | high | codex_1 | Permissionless createLaunchPad can consume per-block vETH loan quota and DoS other launches | codex_1:0.718 Permissionless createLaunchPad can exhaust MAX_LOAN_PER_BLOCK and deny launches |
| F-003 | rewritten_agent_signal | High | high | codex_1 | Router sell pricing uses full vETH reserves including debt-locked liquidity, causing sell reverts and exit lockups | codex_1:0.495 Sell routing uses reserve math that includes debt-backed vETH that cannot be transferred out |
| F-004 | rewritten_agent_signal | Low | high | codex_1 | buyQuote refund logic withholds 1 wei from overpayments | codex_1:0.806 buyQuote refund logic systematically withholds 1 wei from overpaying users |
| F-005 | rewritten_agent_signal | Medium | low | codex_1 | Rebalance initialization can be seized if deployment is non-atomic or proxy is left uninitialized | codex_1:0.407 Upgradeable rebalance contract is takeover-prone if initialization is not atomic |

## Rejection Reasons
- other: 7
- trust_or_owner_model: 4
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Front-Running Attack: initialize() Can Be Front-Run to Steal All Minted Tokens | For clones, `LamboFactory` performs `clone` and `initialize` in the same transaction flow; an attacker cannot call `initialize` on the just-created clone before factory initialization. |
| trust_or_owner_model | opencode_1 | Owner Can Drain All vETH From The Protocol Via updateFactory | This is privileged-owner behavior; README explicitly states owner roles are trusted, so this is not a distinct trustless vulnerability. |
| trust_or_owner_model | opencode_1 | Unlimited Token Minting via createLaunchPad with Zero Validation | Creating new quote tokens per launchpad is intended factory behavior; claim relies on trusted-owner whitelist management rather than an unintended permission bypass. |
| other | opencode_1 | No Slippage Protection Results in Potential Total Loss of Funds | `buyQuote`/`sellQuote` do enforce `minReturn`; users setting `minReturn=0` is caller choice, not a contract-side bypass. |
| other | opencode_1 | Fee Calculation Precision Loss Favors Protocol Over Users | Integer-division rounding dust is expected in Solidity fee math and does not evidence a meaningful systematic overcharge exploit. |
| other | codex_1 | rebalance ignores `amountOut` and executes OKX swaps with `minReturn = 0` | Although `amountOut` is unused and swap minReturn is zero, `rebalance` reverts unless net WETH balance increases (`profit > 0`), preventing protocol-loss execution. |
| unsupported_or_speculative | opencode_1 | No Slippage Protection in Rebalance Function | Same core issue as above: execution is profit-gated and non-profitable outcomes revert, so reported total-loss claim is unsupported. |
| trust_or_owner_model | opencode_1 | Missing Access Control on Rebalance Functions | `extractProfit` is `onlyOwner`; open `rebalance` entrypoint does not grant fund withdrawal and is consistent with keeper-style triggering. |
| other | opencode_1 | Approval Reset Allows Potential Race Condition | No concrete exploit path shown; approvals are to fixed integration addresses for WETH/vETH flows, and overwriting allowance here is not a standalone vulnerability. |
| trust_or_owner_model | opencode_1 | Unverified underlyingToken Can Break VirtualToken | `underlyingToken` is immutable constructor configuration by deployer/trusted owner; this is deployment misconfiguration risk, not an in-protocol exploit vector. |
| other | opencode_1 | Reentrancy Protection on sellQuote Uses msg.sender.call Without Reentrancy Guard | `sellQuote` is protected by `nonReentrant`; callback-based reentry into guarded paths is blocked. |
| other | codex_1 | Hardcoded external addresses create chain-deployment fund-loss risk | Project context specifies Ethereum-only deployment; hardcoded mainnet integration addresses are intentional chain-locking in this codebase rather than a reportable bug by themselves. |
