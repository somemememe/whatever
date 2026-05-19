# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 12

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | Per-creator index / global swapId confusion lets callers withdraw other users' escrowed assets | codex_1:0.621 Global swap index mismatch lets attackers withdraw assets from other users' escrows |
| F-002 | rewritten_agent_signal | Critical | high | codex_1 | User-controlled `typeStd` can route whitelisted assets through an unset custom bridge and bypass escrow entirely | codex_1:0.677 User-controlled `typeStd` can bypass escrow through the custom bridge path |
| F-003 | exact_agent_candidate | High | high | codex_1,opencode_1 | ERC20 transfers are treated as successful even when the token signals failure | codex_1:0.87 ERC20 transfers are treated as successful even when the token returns `false` |
| F-004 | rewritten_agent_signal | High | medium | codex_1 | `cancelSwapIntent` is reentrant through token or bridge callbacks before the swap is marked cancelled | codex_1:0.411 Reentrancy in `cancelSwapIntent` can pay out the same ETH escrow multiple times |
| F-005 | rewritten_agent_signal | Medium | high | codex_1 | Using Solidity `transfer` for ETH payouts can permanently brick swaps involving contract recipients | codex_1:0.84 Using `transfer` for ETH payouts can permanently brick swaps for contract accounts |

## Rejection Reasons
- factually_incorrect: 1
- low_impact_or_operational: 1
- other: 7
- trust_or_owner_model: 2
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| low_impact_or_operational | opencode_1 | Reentrancy Vulnerability in ETH Transfers | `closeSwapIntent` sets the swap status to `Closed` before any ETH payout, and Solidity `transfer` forwards only 2300 gas, so the claimed fallback-based reentrancy path is not viable. |
| trust_or_owner_model | opencode_1 | Owner Can Steal All Assets via Address Changes | This is an owner-trust/governance concern, not an unintended protocol bug. Changing `VAULT` redirects future fees, not existing user escrow, and malicious owner address changes are outside the normal threat model. |
| other | opencode_1 | Swap Creator Can Edit Counterpart After Asset Deposit | There is no prior counterparty deposit to steal. `nftsTwo` and `valueTwo` are pulled atomically from the caller during `closeSwapIntent`, so changing `addressTwo` does not confiscate already-escrowed assets from someone else. |
| other | opencode_1 | PunkProxy Reinitialization Vulnerability | This describes user key-management / recovery limitations, not an exploitable protocol flaw. |
| trust_or_owner_model | opencode_1 | Owner Can Pause and Set Malicious Payment Configuration | This is another owner-trust concern rather than an unintended permissionless exploit. |
| unsupported_or_speculative | opencode_1 | Missing Expiration Check for Swaps | `swapEnd` is used as a completion timestamp, not an expiry promise. Counterparty assets are not pre-deposited, so the described permanent lockup path is not supported by the code. |
| other | opencode_1 | No Slippage Protection for NFT Swaps | This is inherent market risk in fixed-term OTC swaps, not a smart-contract vulnerability. |
| other | opencode_1 | Missing check for contract existence before external calls | As written this mostly relies on admin miswhitelisting. The materially reportable user-triggerable version is the `typeStd` custom-bridge bypass captured in F-002. |
| factually_incorrect | opencode_1 | Inconsistent Access Control on WhiteList Management | The claim is factually incorrect: `setWhitelist(address,bool)` can both add and remove whitelist entries by setting the boolean status. |
| other | opencode_1 | Missing Event Emission for Critical State Changes | Lack of events is a transparency issue, not a realistic protocol-level asset loss or lockup vulnerability. |
| other | opencode_1 | Incorrect ERC20 Interface Definition | The parameter name `tokenId` is irrelevant to the ABI; the function selector matches `transferFrom(address,address,uint256)`. |
| other | opencode_1 | Missing Contract Balance Recovery Function | Accidental direct transfers to the contract are a usability issue, not an exploitable protocol vulnerability in the swap flow. |
