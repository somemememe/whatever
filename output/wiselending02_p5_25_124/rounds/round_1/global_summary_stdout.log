# Global Audit Memory

## Scope Touched
- `WiseLending.sol`: primary hotspot for deposit, payback, liquidation, and position state/accounting paths; repeated concern around asset/state consistency
- `WiseCore.sol`: paired with lending flows for core accounting/bookkeeping and liquidation share allocation
- `MainHelper.sol`: helper-layer influence on lending/liquidation state transitions and token-list maintenance behavior
- `TransferHub/TransferHelper.sol`, `TransferHub/CallOptionalReturn.sol`: ERC20 transfer semantics and non-standard token handling; return-value trust is a recurring direction
- `PoolManager.sol`, `WiseLendingDeclaration.sol`: protocol-control and configuration surface with meaningful but still relatively underexplored risk area
- `WiseLowLevelHelper.sol`: low-level support logic touched across review but not yet yielding much retained output relative to surface area
- `InterfaceHub/IWiseSecurity.sol`, `OwnableMaster.sol`: security/governance boundary and privileged-control assumptions relevant to system safety

## Issue Directions Seen
- Core lending-flow accounting can diverge from actual asset movement, especially on deposits/paybacks and inbound token handling
- Non-standard ERC20 behavior remains a strong direction, particularly where helpers or integrations trust nominal transfer success/amounts
- Liquidation paths show recurring bookkeeping/state-allocation risk rather than only pricing risk
- Position management has state-cleanup and scaling/DoS-style edge cases, especially around token-list maintenance
- Isolation/security control surfaces may apply effects too broadly or register locks/state too loosely
- Governance/oracle/configuration themes exist, but the strongest retained signal so far is still concrete accounting/state inconsistency in core flows

## Useful Context
- Cross-round attention is concentrated on `WiseLending.sol` and `WiseCore.sol`; these are the protocol’s main bug-density areas so far
- Retained findings skew toward deterministic logic/accounting flaws over speculative governance-only concerns
- WETH-specific synchronization behavior is a notable subtheme inside deposit/mint flow review
- Underexplored but suspicious areas relative to control surface include `PoolManager.sol`, `WiseLendingDeclaration.sol`, and `WiseLowLevelHelper.sol`
- No separate durable promising direction stood out beyond the retained findings cluster; the audit signal is currently coherent around asset accounting and state consistency
