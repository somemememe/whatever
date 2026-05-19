# Global Audit Memory

## Scope Touched
- `0x31a4f372aa891b46ba44dc64be1d8947c889e9c6/Contract.sol` — dominant focus across rounds; attention clusters around `_transfer`, fee/reflection accounting, cooldown checks, blacklist/sniper controls, LP-pair treatment, ownership lock/unlock, and auto-swap / fee-recipient flows

## Issue Directions Seen
- Fee/reflection accounting inconsistencies, especially paths where taxed-transfer bookkeeping may mint synthetic contract-side value
- Buy-path trading controls causing availability failures, notably cooldown enforcement and blacklist/sniper gating around pair interactions
- Privileged trading/admin controls with outsized market impact, including LP-pair blacklisting, mutable config toggles, and effectively reclaimable ownership after apparent renounce-style actions
- Auto-swap execution hazards tied to zero-min-out pricing exposure and brittle downstream payout behavior
- Lower-confidence but repeatedly examined directions: reflection edge-case math, fee withdrawal / wallet redirection centralization, removable tx-limit controls, and missing config-change event coverage

## Useful Context
- Audit activity has stayed entirely within a single token-style `Contract.sol`; no adjacent files or integrations were explored
- Cross-round convergence is strongest on transfer-path mechanics rather than deployment/setup concerns
- Durable risk pattern is the combination of accounting complexity with owner-controlled trading restrictions and swap-side fund handling
- Several centralization/transparency concerns were investigated repeatedly, but the more durable audit signal is where those powers intersect with trading liveness or value accounting
