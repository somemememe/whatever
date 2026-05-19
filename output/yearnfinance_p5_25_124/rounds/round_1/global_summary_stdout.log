# Global Audit Memory

## Scope Touched
- `0x83f798e925bcd4017eb265844fddabb448f1707d/Contract.sol`: core focus across rounds; vault share mint/burn accounting, lender valuation, provider/withdraw flow, and public strategy entrypoints
- `deposit()` / share pricing paths: bootstrap behavior and minting against mismeasured pool value repeatedly surfaced
- `_calcPoolValueInToken()` and lender balance reads: Compound exchange-rate handling and dYdX balance interpretation are key accounting-risk surfaces
- public `supply*`, `rebalance`, provider interactions: moving idle funds across lenders without synchronized withdrawal support remains a central flow concern
- `approveToken` / config-address handling: reviewed as an exposure surface, but not yet tied to a retained issue

## Issue Directions Seen
- Asset/share accounting can diverge from real value, especially around initialization and lender valuation
- Cross-lender state changes by public entrypoints can strand liquidity relative to the withdrawal path
- External protocol balance adapters are a recurring risk area when local accounting assumes favorable semantics
- Broader public strategy/config entrypoint manipulation was explored, but concrete retained issues concentrated on accounting and liquidity mismatches rather than generic access concerns

## Useful Context
- Audit attention is concentrated almost entirely in a single `Contract.sol`, with strongest signal in deposit/withdraw and lender-accounting logic
- Retained findings cluster around four durable themes: stale Compound valuation, zero-supply bootstrap breakage, public `supply*` withdrawal mismatch, and dYdX sign handling
- Investigation repeatedly contrasted concrete vault math failures against more speculative manipulation theories; the durable cross-round signal is stronger on accounting correctness than on generalized rebalance/oracle abuse
