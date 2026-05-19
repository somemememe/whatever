# Global Audit Memory

## Scope Touched
- `onchain_auto/0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/Revest.sol` - persistent center of audit attention; mint/deposit/split flows, collateral accounting, fee handling, lock checks, and some oracle/value-lock assumptions
- `onchain_auto/0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/FNFTHandler.sol` - repeatedly examined for FNFT id allocation/counter behavior and mint-side state interactions
- `onchain_auto/0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/utils/RevestAccessControl.sol` - secondary attention around permissioning / maturity-extension surfaces, not yet a confirmed issue hub
- `onchain_auto/0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/interfaces/{IRevest,ITokenVault,ILockManager,IAddressLock}.sol` - useful for tracing lock semantics, vault assumptions, and external interface expectations around deposits and triggers

## Issue Directions Seen
- Reentrancy and ordering risks around FNFT minting, especially where id assignment/counters interact with external callbacks or hookable token flows
- Collateral accounting mismatches in mint/deposit paths, with fee-on-transfer and WETH/ETH handling as the strongest recurring theme
- Deposit and split lifecycle logic as a repeated bug surface, including deadline/maturity gating and proportionality assumptions
- Lock validation weaknesses, especially address-lock trigger compatibility and external lock-manager assumptions
- Lower-confidence but still notable direction: oracle/value-lock design assumptions in `Revest.sol` remain underexplored compared with mint/deposit mechanics

## Useful Context
- Cross-round attention is heavily concentrated on `Revest.sol` plus `FNFTHandler.sol`; most durable risk comes from their interaction rather than isolated helper code
- The strongest confirmed pattern so far is state/accounting drift caused by unusual token behavior or external control flow during mint/deposit operations
- Broader scans touched access control, arithmetic, approvals, and burn/desync themes, but these have not yet displaced mint/deposit and lock-validation paths as the main audit signal
- Interface review has mainly served to validate assumptions about vault funding, lock triggers, and FNFT lifecycle rather than reveal standalone interface-only issues
