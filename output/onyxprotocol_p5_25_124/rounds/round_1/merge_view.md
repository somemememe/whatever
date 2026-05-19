# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 9

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1 | Direct underlying donations can inflate the exchange rate until later minters receive zero shares | codex_1:0.834 Direct underlying donations can inflate the exchange rate until victim mints round to zero |
| F-002 | exact_agent_candidate | Medium | high | codex_1 | When total supply resets to zero, the next minter can capture stranded underlying at the initial exchange rate | codex_1:0.937 When total supply reaches zero, the next minter can capture any stranded underlying at the initial exchange rate |
| F-003 | rewritten_agent_signal | Medium | medium | codex_1 | Liquidation treats any zero-decimal collateral market as NFT collateral | codex_1:0.797 Liquidation misclassifies any zero-decimal collateral market as an NFT market |
| F-004 | exact_agent_candidate | Low | high | codex_1,opencode_1 | Any account can force-sweep arbitrary non-underlying tokens from a market to the admin | codex_1:0.894 Any account can sweep arbitrary non-underlying tokens out of the market to the admin |

## Rejection Reasons
- other: 8
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Liquidation for ERC721 Collateral Uses Inconsistent Calculations Leading to Undercollateralization | The code repays `possibleRepayAmount` and then computes seized collateral from `actualRepayAmount`; that is internally consistent from the available code. The supported issue here is the `decimals()==0` type check, not a demonstrated under-seizure bug. |
| other | opencode_1 | Implementation Contract Not Validated Before Delegation | This is an admin-only upgradeability trust assumption inherent to the proxy pattern. No permissionless exploit or unexpected privilege bypass is shown. |
| other | opencode_1 | Missing Check for Zero Initial Exchange Rate | The contract already requires `initialExchangeRateMantissa > 0`. Complaining about the absence of an upper bound is an admin-controlled deployment parameter, not a standalone protocol bug. |
| trust_or_owner_model | opencode_1 | Reserve Factor Can Be Set to 100% | This is an explicit governance-controlled parameter bounded by `reserveFactorMaxMantissa`; it is not a hidden vulnerability in the implementation. |
| other | opencode_1 | Division by Zero in exchangeRateStoredInternal if Total Supply is Zero | `exchangeRateStoredInternal()` explicitly returns `initialExchangeRateMantissa` when `totalSupply == 0`, so the claimed division-by-zero path does not exist. |
| other | opencode_1 | Protocol Seize Share is Hardcoded Without Validation | This is a design choice, not a security issue causing realistic protocol harm. |
| other | opencode_1 | No Maximum Borrow Rate Validation in Interest Rate Model | `accrueInterest()` already reverts if `borrowRateMantissa > borrowRateMaxMantissa`. Installing a malicious model is an admin action, and the runtime check prevents silent over-accrual. |
| other | opencode_1 | ERC20 Transfer Handling May Fail Silently for Certain Tokens | `doTransferOut()` inspects returndata and reverts on failure; it does not silently succeed when the token returns false or behaves non-compliantly. |
| other | opencode_1 | Delegatecall Risk in OErc20Delegator Allows Implementation to Modify Delegator Storage | That is the intended behavior of a delegatecall proxy and does not identify a concrete vulnerability beyond the normal trust model of upgradeable contracts. |
