# Global Audit Memory

## Scope Touched
- `0x2405913d54fc46eeaf3fb092bfb099f46803872f/Contract.sol`: single focal file so far; repeated scrutiny on `initialize()`, `borrow()`, `repay()`, `flashLoan()`, and `withdrawERC721()`
- Loan lifecycle paths: borrowing, repayment, liquidation, and loan-cap accounting repeatedly surfaced as the main correctness-risk area
- Flash-loan and funding-source handling: attention centered on repayment enforcement and exposure created by `_fundSource` token allowances
- Valuation / signature checks: examined around borrow authorization and replay scope, but not yet retained

## Issue Directions Seen
- Repayment accounting and token-flow mismatches, especially where lender-rate vs client-rate state updates can diverge from actual ERC20 transfers
- Liquidation correctness gaps: authority / validation assumptions, unhealthy-loan gating, and failure to fully reconcile outstanding loan accounting
- Global loan-limit / `_currentLoanAmount` consistency as a recurring state-accounting direction across borrow and liquidation flows
- Initialization / deployment safety, specifically risk from uninitialized instances being claimable
- Flash-loan safety around insufficient repayment enforcement and arbitrary use of approved `_fundSource` allowances
- Signature-validation scope and replay resistance remained a recurring but currently unretained direction

## Useful Context
- Cross-round attention is highly concentrated in one contract rather than spread across multiple modules
- The most durable pattern is state/accounting drift between intended loan semantics and on-chain balance / limit tracking
- Several retained issues depend on trusting external actors or components (`_fundSource`, `_controlPlane`, PineWallet / valuation signer assumptions) without enough on-chain reconciliation
- Signature replay and block-throttling logic were investigated enough to remain background context, even though not retained in the latest round
