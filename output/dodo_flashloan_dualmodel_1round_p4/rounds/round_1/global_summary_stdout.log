# Global Audit Memory

## Scope Touched
- `onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol` — dominant focus across rounds; attention clusters around `init()`, DVM swap/flash-loan reserve accounting, LP mint/burn bootstrap paths, TWAP cumulative-price updates, and fee-tier logic
- DVM vault/trade/liquidity/TWAP/init regions in `Contract.sol` — repeatedly revisited as the main source of state-accounting, oracle-ordering, and initialization/control risk

## Issue Directions Seen
- Permissionless or replayable initialization / live pool reconfiguration remains a central control-plane risk
- Reserve and balance-delta accounting is a recurring theme: logic appears sensitive to ambient token balances during swaps, flash loans, and LP actions
- Oracle/TWAP update ordering is a durable concern, especially where cumulative pricing may observe post-update reserves instead of the intended prior state
- Fee differentiation tied to `tx.origin` is a repeated trust-boundary issue because privileged treatment can be inherited through intermediaries
- Empty-pool / bootstrap minting paths are noteworthy when share issuance does not fully reflect both-sided pool value, especially with trapped balances
- Flash-loan repayment validation and pricing edge cases were repeatedly investigated, but mostly as extensions of the broader accounting/invariant theme rather than as isolated retained issues

## Useful Context
- Cross-round attention has stayed almost entirely within a single large `Contract.sol`, so most durable context is function-level rather than file-level
- The strongest overlap between agents was `init()` reinitialization risk; secondary overlap came from accounting/invariant concerns
- Investigation split has been consistent: one line of review emphasized swaps, LP flows, and TWAP mechanics, while another emphasized flash-loan repayment, pricing math, fee model behavior, and permit-related edges
- Several one-off directions were explored but not retained; the durable signal is that accounting, initialization, oracle ordering, and fee-identity assumptions are the recurring high-value surfaces
