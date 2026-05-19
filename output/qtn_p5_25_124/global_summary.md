# Global Audit Memory

## Scope Touched
- `0xc9fa8f4cfd11559b50c5c7f6672b9eea2757e1bd/Contract.sol` — dominant audit surface; attention centered on transfer flow, launch gating, router-selected recipient paths, and manual AMM pair accounting under rebases
- Pair/live logic in `Contract.sol` — repeated concern area for swap pricing integrity, pre-live protections, cooldown behavior, and buy-side limit enforcement
- Adjacent admin/control functions in `Contract.sol` — secondary attention on public launch-state changes and owner-controlled blacklist/parameter powers, though many centralization angles were not retained

## Issue Directions Seen
- Positive rebase interacting with manually tracked pair balances / AMM accounting, creating persistent economic desync risk
- Permissionless launch-state and trading-path abuse: outsiders can influence live-state transitions or user trading conditions
- Buy-path recipient handling enabling third-party targeting, especially around blacklist and cooldown state applied to arbitrary recipients
- Anti-whale / max-wallet / cooldown checks showing state-gap patterns, especially checks based on pre-transfer state rather than post-buy outcomes
- Broad owner/admin privilege and token-control review remains a recurring backdrop, even where individual centralization concerns were not retained

## Useful Context
- Audit focus is heavily concentrated in a single token contract rather than a multi-file system
- Cross-agent overlap is strongest around pair-accounting plus `updateLive()` / launch logic; this is the clearest durable hot spot
- One agent emphasized permissionless user-targeting through router flows, while another emphasized owner/admin authority; together they frame both outsider abuse and privileged-control risk
- Retained findings cluster around one economic flaw and several launch/trading control gaps rather than isolated code-style or compiler issues
- Non-retained concerns around admin powers, inflation framing, timelock absence, and dead-code exist as background context but currently have weaker cross-round support
