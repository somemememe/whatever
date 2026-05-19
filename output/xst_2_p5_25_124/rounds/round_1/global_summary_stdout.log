# Global Audit Memory

## Scope Touched
- `XST2.sol` — central audit surface across rounds: initialization, presale/transfer gating, buy/rebase accounting, `_mainPool`-dependent flow, and reserve migration behavior
- `State.sol` / `Getters2.sol` / `Setters2.sol` / `Constants2.sol` — supporting state layout and helper logic tied to unset core addresses/flags, factor math, taxless controls, and pool-sync/accounting assumptions
- proxy/upgradeability stack (`AdminUpgradeabilityProxy.sol`, `UpgradeabilityProxy.sol`, `Proxy.sol`, `OwnableUpgradeable.sol`) — reviewed mainly for initialization/ownership context; upgrade flow itself has not yet produced a durable issue direction
- pool-management helpers such as `createTokenPool`, `silentSyncPair`, and related supported-pool paths — repeatedly checked as possible accounting/control edges, but still secondary to core token-state defects

## Issue Directions Seen
- Missing or incomplete initialization is the dominant cross-round theme: owner, presale state, main pool, and other core addresses/flags appear able to remain unset and lock protocol behavior
- Transfer-path behavior depends heavily on `_mainPool` and presale flags, creating repeated protocol-freeze or unusable-token directions rather than isolated edge cases
- Rebase/mint economics around spot balances, pool snapshots, and factor math remain a strong direction, especially where buy-side state can amplify minting
- Reserve/liquidity migration and other operational flows are sensitive to ordinary taxable transfer logic, creating loss/distortion risk during admin or maintenance actions
- Taxless, supported-pool validation, tranche reassignment, and zero-address handling have appeared repeatedly as candidate control-surface issues, though not yet durable findings

## Useful Context
- Cross-agent attention consistently converged on `XST2.sol` plus the state/getter/setter layer; these files define most meaningful protocol behavior
- Durable retained problems so far are mostly protocol-wide state/configuration failures and one major economic-accounting path, not proxy-upgrade bugs
- Proxy contracts matter mainly because they reinforce the initialization context; direct upgradeability exploitation has not been the main signal
- Several narrower candidates were explored and dropped, suggesting the strongest audit signal remains in core lifecycle state, transfer gating, and rebase/accounting interactions
