# Round 2 Summary

## Agent: codex_1
- files touched  
  `managers/FeeManager.sol`, `modules/ShareModule.sol`, `managers/RiskManager.sol`, `modules/VaultModule.sol`, `hooks/BasicRedeemHook.sol`, `queues/RedeemQueue.sol`, `queues/DepositQueue.sol`, `queues/SignatureDepositQueue.sol`, `libraries/TransferLibrary.sol` (plus broad initial scope reads).
- files revisited / highest-attention files  
  Highest attention was on `FeeManager`, `ShareModule`, `RiskManager`, `VaultModule`, `BasicRedeemHook`, and deposit/redeem queue + transfer paths (with line-level rechecks).
- main issue directions investigated  
  Fee accrual/state-update coupling across report assets; performance-fee trigger logic; subvault allowlist effects on pull flows; redeem hook liquidity assumptions vs risk checks; ERC20 transfer-accounting assumptions.
- promising but not retained directions  
  No additional non-retained direction was explicit in the log beyond the five finalized findings.

## Agent: opencode_1
- files touched  
  Very broad sweep across most in-scope modules, managers, queues, hooks, factory, oracle, permissions, verifier/protocol adapters, and strategy files.
- files revisited / highest-attention files  
  Notable focus on `FeeManager`, `ShareModule`, `RiskManager`, `VaultModule`, queue contracts, `TransferLibrary`, `Oracle`, and permissions/verifier stack.
- main issue directions investigated  
  Setup/control-plane risks (`setVault`), hook `delegatecall` execution model, fee/state update behavior, oracle timeout/suspicion logic, gas/DoS surfaces, queue accounting/precision paths.
- promising but not retained directions  
  Reported hypotheses around permissionless vault replacement, hook delegatecall abuse/silent failure, oracle timeout bypass, factory race, and rounding/gas concerns were not retained in merged findings for this round.

## Cross-Agent Status
- main overlap in file/area attention  
  Strong overlap on `FeeManager`, `ShareModule`, `RiskManager`, `VaultModule`, `DepositQueue`/`RedeemQueue`, and `TransferLibrary`.
- notable differences in attention  
  `codex_1` concentrated on concrete exploitable accounting/lockup/DoS paths tied to fee logic and subvault asset handling; `opencode_1` covered a wider architecture surface (oracle, factory, permissions/verifiers) with more speculative outputs.
- underexplored but suspicious files/functions if clearly supported by the logs  
  `Oracle.sol` and `Factory.sol` received attention mainly from `opencode_1` but produced no retained findings this round.

## Retained Findings
- `F-007`/`F-008`: high-severity fee logic flaws in `FeeManager` causing repeated protocol over-accrual and performance-fee charging on drawdowns.
- `F-009`/`F-010`: subvault allowlist interactions can lock disallowed-held assets and enable redeem-flow DoS via dusting disallowed subvaults.
- `F-011`: deposit accounting assumes exact ERC20 transfer amounts, creating dilution/deficit risk for fee-on-transfer assets.
