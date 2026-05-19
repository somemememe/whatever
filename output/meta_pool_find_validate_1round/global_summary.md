# Global Audit Memory

## Scope Touched
- `FlawVerifier.sol` — primary audit harness; attention centered on `executeOnOpportunity()` and its interaction with live `TARGET_PROXY`
- External staking proxy / `TARGET_PROXY` flow — unresolved core surface because the repo exposes the exploit path assumptions, not the target implementation
- OpenZeppelin proxy stack (`TransparentUpgradeableProxy`, `ProxyAdmin`, `ERC1967*`, `BeaconProxy`, `UpgradeableBeacon`, `Proxy`, `Address`, `StorageSlot`, `Ownable`) — reviewed mainly to exclude local deviations; appears vanilla

## Issue Directions Seen
- Possible unbacked share minting through an inherited ERC4626-style `mint(uint256,address)` path on the live staking proxy
- Potential drain chain from proxy minting into liquid unstake / ETH exit flow if mpETH can be created before backing assets are collected
- Recurrent need to distinguish harness-level exploit hypotheses from issues actually present in the external proxy implementation
- Forced-ETH / balance-based funding-bypass ideas were explored but are currently weaker than the mint-path direction

## Useful Context
- The strongest cross-round theme is that the critical risk, if any, likely sits in the live staking implementation behind `TARGET_PROXY`, not in the local verifier scaffold
- Included OpenZeppelin proxy/admin files have been checked as a baseline and currently serve more as ruled-out infrastructure than as active suspicion
- Confidence is constrained by missing target implementation code; conclusions depend on whether the live proxy exposes ERC4626-like mint semantics as assumed
- The most durable audit context is the hypothesized sequence: unbacked mpETH minting -> swap/unstake path -> ETH extraction
