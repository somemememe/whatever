# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 8

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | Owner receives the entire liquidity position and can later rug the pool | codex_1:0.435 Deployer keeps all LP tokens and can rug all liquidity after launch |
| F-002 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Owner-controlled blacklist can freeze individual holders or halt the entire market | codex_1:0.776 Owner blacklist can freeze specific holders or brick the entire market |
| F-003 | exact_agent_candidate | High | high | codex_1,opencode_1 | A hidden 70% transfer tax confiscates ordinary transfers after the first buy | codex_1:1.0 A hidden 70% transfer tax confiscates ordinary transfers after the first buy |
| F-004 | exact_agent_candidate | Medium | medium | codex_1 | Global three-sells-per-block rule enables sell-path denial of service | codex_1:0.865 Global three-sells-per-block rule enables permissionless sell denial of service |

## Rejection Reasons
- other: 5
- trust_or_owner_model: 3

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Owner Can Remove All Transaction Limits Without Timelock | `removeLimits()` only relaxes anti-whale limits globally; this is an admin-privilege/configuration change, not a concrete exploit path that directly causes theft, lockup, or protocol insolvency. |
| trust_or_owner_model | opencode_1 | Owner Can Remove All Transfer Taxes | `removeTransferTax()` sets the 70% transfer tax to zero for everyone, which is beneficial to holders rather than harmful. The owner is already exempt from the taxed branch when sending to or from `owner()`. |
| other | opencode_1 | Tax Wallet Can Drain All Contract Tokens via manualSwap | `manualSwap()` only converts tokens already held by the contract, which are fee accruals under this design. It does not let the tax wallet pull arbitrary user balances from wallets or LP. |
| trust_or_owner_model | opencode_1 | Unlimited Token Approval to Uniswap Router | The approval is on the LP token from the token contract's address, but LP tokens are minted to `owner()`, not to the contract. This approval does not expose the pool reserves or user balances. |
| trust_or_owner_model | opencode_1 | Trading Opening Can Be Front-Run by Owner | The owner already controls launch and initially holds the supply; the reported scenario does not establish a distinct exploitable flaw beyond ordinary centralized launch control. |
| other | opencode_1 | Tax Wallet Can Change Fees Without User Consent | `reduceFee()` can only set `_finalBuyTax` and `_finalSellTax` to a value less than or equal to their current values, and both finals are initialized to zero, so it cannot raise fees or create new harm. |
| other | opencode_1 | Block Timestamp Manipulation Risk | Use of `block.timestamp` as an AMM deadline is standard and any miner skew here does not create a meaningful protocol-level exploit in this contract. |
| other | opencode_1 | Missing Return Value Check for Transfer | `address.transfer()` reverts on failure in Solidity 0.8.x, so there is no unchecked false return path; at most this can fail closed if the tax wallet rejects ETH. |
