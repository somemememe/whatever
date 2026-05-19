# Round 1 Summary

## Agent: codex_1
- files touched: `XST2.sol`, `State.sol`, `Getters2.sol`, `Setters2.sol`, `Constants2.sol`, `AdminUpgradeabilityProxy.sol`, `UpgradeabilityProxy.sol`, `Proxy.sol`, `OwnableUpgradeable.sol`
- files revisited / highest-attention files: `XST2.sol` was the main focus, with repeated attention on `Getters2.sol`, `Setters2.sol`, and `State.sol`
- main issue directions investigated: missing upgradeable initialization / unset ownership and core state; transfer-path behavior around `_mainPool`; rebase/mint math tied to pool snapshots; reserve migration behavior and tax handling
- promising but not retained directions: proxy upgrade flow was reviewed but did not produce a retained finding; sell-side burn distortion adjacent to the flash-loanable rebase path was noted but not kept as a separate merged finding

## Agent: opencode_1
- files touched: `XST2.sol`, `State.sol`, `Setters2.sol`, `Getters2.sol`, `Constants2.sol`, `AdminUpgradeabilityProxy.sol`, `Proxy.sol`
- files revisited / highest-attention files: attention centered on `XST2.sol` and the supporting state/getter/setter files
- main issue directions investigated: presale lifecycle and transfer gating; missing initialization of key addresses/state; factor/accounting behavior; taxless and pool-sync related controls
- promising but not retained directions: candidate issues were raised around `setTaxless`, `getFactor` math/div-by-zero, `createTokenPool`, `reassignTranche`, `silentSyncPair`, supported-pool validation, and reserve/stabilizer zero-address handling, but these were not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `XST2.sol` plus `State.sol`, `Getters2.sol`, and `Setters2.sol`, especially around initialization gaps and presale/transfer-state handling
- notable differences in attention: `codex_1` went deeper on transfer-path DOS, pool-sync/rebase economics, and reserve migration; `opencode_1` cast a wider net across several additional candidate checks and surfaced the missing presale completion path that was retained
- underexplored but suspicious files/functions if clearly supported by the logs: proxy contracts were read by both/one agent but yielded no retained issue this round; `createTokenPool`, `setTaxless`, and pool-sync helper paths were investigated as candidates but remained unretained

## Retained Findings
- retained issues center on core state never being initialized, including no usable owner/presale/main pool setup
- the merged set also keeps two protocol-locking paths: `_mainPool` remaining unset for ordinary transfers, and `_presaleDone` having no code path to become true
- the main economic exploit retained is the spot-balance-driven, uncapped quadratic rebase mint on buys
- one operational loss issue was retained for liquidity reserve migration being executed through taxable transfer logic
