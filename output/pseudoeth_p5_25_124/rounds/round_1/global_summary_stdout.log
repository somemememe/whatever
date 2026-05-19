# Global Audit Memory

## Scope Touched
- `0x2033b54b6789a963a02bfcbd40a46816770f1161/Contract.sol`: core focus across pair lifecycle paths (`initialize`, `mint`, `burn`, `swap`) and public maintenance hooks (`skim`, `sync`); issue direction centers on unsafe direct pair interactions, initialization validation/replayability, and surplus-balance handling

## Issue Directions Seen
- Pair settlement/accounting relies on live balances in ways that appear unsafe around prefunded or directly transferred assets
- `initialize` remains a key direction due to re-callability / weak validation concerns
- Permissionless maintenance and recovery-style hooks, especially `skim`, are a recurring exposure area for capturing stray, rebasing, or otherwise surplus balances
- Public reserve-management entrypoints (`skim`, `sync`) are a repeated review surface for reserve/accounting manipulation
- Token-trust assumptions around raw `transfer` / `balanceOf` behavior were explored as a secondary direction, but not retained so far

## Useful Context
- Audit attention is concentrated on a single in-scope AMM-style `Contract.sol`
- Cross-round emphasis is strongest on `skim`; `sync` has drawn suspicion but has not been retained
- Broader review has repeatedly centered on whether pair logic safely handles balances that arrive outside intended flow
- LP-token approval race behavior was explored early and not retained as a durable direction
