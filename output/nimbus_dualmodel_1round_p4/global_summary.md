# Global Audit Memory

## Scope Touched
- `0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol` — dominant focus across rounds; attention repeatedly converged on `initialize()`, `swap()`, `burn()`, `skim()`, `_mintFee()`, and `permit()`/`DOMAIN_SEPARATOR`
- Pair lifecycle and reserve-accounting paths — recurring concern around initialization control, swap invariant enforcement, fee handling, and LP redemption semantics
- Swap callback / external integration surfaces — examined mainly through referral hooks and callback-assisted swap flow, with mixed signal after merge

## Issue Directions Seen
- Swap invariant math/scaling errors in core pair logic, especially around reserve accounting and drainability
- External-call coupling inside `swap()`, particularly referral-program dependence creating abuse or denial-of-service angles
- Pair initialization / reinitialization control weaknesses at the factory-pair boundary
- LP token redemption edge cases, including pair-held LP tokens and protocol-fee LP mishandling
- Fee-recipient and `_mintFee()` interactions as a recurring source of odd pair-state behavior
- Secondary but non-retained attention on callback-driven swap abuse, `skim()` interactions, and `permit()` / domain-separator replay concerns

## Useful Context
- So far the audit has been effectively single-file heavy: nearly all meaningful attention concentrated on one pair-style contract rather than multi-file integration complexity
- Cross-agent overlap is strongest around `swap()` and burn/fee mechanics; this appears to be the contract’s highest-risk surface
- Durable retained issues cluster around concrete state-transition flaws rather than generic callback theories or style-level concerns
- Non-retained ideas still worth remembering as background context include callback + `skim()` compositions and cross-chain/fork permit replay, but they currently have weaker support than the core pair-logic issues
