# Global Audit Memory

## Scope Touched
- `Contract.sol` — core Balancer `exitPool` callback / exit-path state-transition surface; repeated focus on whether transient LP state can be consumed before pricing, solvency, collateral-disable, withdrawal, or borrow checks settle
- `FlawVerifier.sol` — main exploit-reachability harness for inflated collateral valuation, health-factor decisions, collateral removal sequencing, and possible same-window borrow reachability
- `interface.sol` — secondary support surface for confirming lending/oracle/collateral-management entrypoints and helper routines; reviewed more as connective plumbing than as a primary bug locus
- Balancer exit → oracle/LP valuation → lending solvency/collateral action flow — enduring cross-contract flow of interest, especially when in-transaction LP pricing feeds immediate protocol decisions

## Issue Directions Seen
- Read-only or callback-enabled reentrancy during Balancer pool exit can expose transient LP state to downstream pricing logic
- Temporary inflation of Balancer-LP collateral value is the dominant recurring direction, especially when consumed immediately by health checks or collateral-management decisions
- Collateral-state transitions in the same manipulated transaction remain the strongest retained pattern, particularly disable/remove or withdraw behavior gated by inflated health
- Direct over-borrowing during the same transient-pricing window is a retained but lower-confidence extension of the same core valuation issue
- Liquidation-related paths were explored as adjacent fallout, but the stronger accumulated direction remains unsafe collateral removal rather than durable liquidation abuse
- Generic helper-library risk in `interface.sol` was examined but has not emerged as a retained vulnerability direction

## Useful Context
- Audit attention has remained tightly concentrated on the Balancer exit callback and Sturdy collateral/oracle integration rather than the broader interface surface
- The durable pattern is a timing-sensitive cross-protocol sequencing issue, not a generic standalone oracle bug: transient Balancer exit state becomes usable inside lending solvency logic before normalization
- `interface.sol` has mainly served to confirm reachable collateral-management, borrowing, liquidation, and transfer-helper surfaces once the manipulated pricing window is reached
- Across rounds, the most stable hypothesis is that Balancer exit transient state can temporarily overstate LP collateral value, and Sturdy trusts that value immediately for solvency-sensitive actions in the same transaction
