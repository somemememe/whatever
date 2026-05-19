# Global Audit Memory

## Scope Touched
- `cauldrons/CauldronV4.sol` — dominant review surface; recurring concern around oracle/exchange-rate handling, solvency gates, borrow/withdraw flows, repay semantics, and liquidation/bad-debt behavior
- `cauldrons/PrivilegedCauldronV4.sol` — secondary watch area for privileged debt/accounting helpers and borrow-position adjustment paths; several leads reviewed but not retained
- `cauldrons/PrivilegedCheckpointCauldronV4.sol` — distinct liveness surface where checkpoint-token hooks interact with collateral operations and liquidation
- `interfaces/IOracle.sol` plus surrounding `interfaces/*.sol` — mainly contextual for oracle assumptions, token/strategy integration points, and call-surface understanding rather than primary issue sources
- `FlawVerifier.sol` — supporting exploit/context harness; useful for scenario framing but not a core source of durable findings

## Issue Directions Seen
- Oracle/exchange-rate fragility is the main audit theme: zero-rate acceptance, stale-rate reuse after oracle failure, and decimal/precision mismatches all point to weak input validation around solvency-critical pricing
- Liquidation correctness remains a recurring direction, especially edge cases where invalid/stale rates distort solvency checks or residual debt becomes stranded after collateral exhaustion
- Solvency-sensitive actions in `CauldronV4` repeatedly cluster around the same dependency: price freshness and correctness drive borrow, withdraw, and liquidation safety
- Checkpoint-token hook behavior is a separate, durable liveness/DoS direction affecting collateral adjustments and liquidations in the checkpoint extension
- Privileged debt/accounting paths and `repay(..., skim=true)` were investigated as potential issue families, but have weaker signal than the retained oracle/liquidation themes

## Useful Context
- Audit attention is concentrated heavily in the cauldron contracts, with `CauldronV4` receiving the deepest line-by-line scrutiny across rounds
- Retained findings so far consolidate into two broad buckets: oracle/rate-validation weaknesses in `CauldronV4` and hook-induced operational breakage in `PrivilegedCheckpointCauldronV4`
- The most durable cross-round pattern is not isolated arithmetic mistakes but protocol-state failures caused by bad external inputs, stale cached values, or revert-prone external hooks
- Interface files and `FlawVerifier.sol` have mostly served as context for assumptions and exploit modeling; they should inform reasoning without outweighing direct implementation evidence
