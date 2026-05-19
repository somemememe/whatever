# Global Audit Memory

## Scope Touched
- `0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/MarketCapSqrtController.sol` — central rebalance/reindex surface; repeated attention on constituent selection, weight setting, and minimum-balance updates
- `0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/MarketCapSortedTokenCategories.sol` — category sorting and token admission depend on externally derived market-cap signals
- `0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/lib/MCapSqrtLibrary.sol` — supporting market-cap / weight math is part of the same manipulable input chain
- `0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/OwnableProxy.sol` — proxy initialization / ownership setup repeatedly surfaced as an upgradeability risk area
- `0xf00a38376c8668fc1f3cd3daeef42e0e44a7fcdb/temp-contracts/DelegateCallProxyManager.sol` and `0xf00a38376c8668fc1f3cd3daeef42e0e44a7fcdb/temp-contracts/DelegateCallProxyManyToOne.sol` — proxy-manager architecture was inspected and remains a partially resolved flank
- `0x120c6956d292b800a835cb935c9dd326bdb4e011/@indexed-finance/uniswap-v2-oracle/contracts/lib/PriceLibrary.sol` — oracle support code matters as upstream pricing context for controller decisions

## Issue Directions Seen
- Reindex/reweigh flows repeatedly hinge on TWAP-based market-cap inputs that can distort constituent inclusion and target weights
- Weighting logic also trusts live `totalSupply()` as a market-cap component, creating exposure to temporary or non-economic supply expansion
- Permissionless maintenance paths, especially minimum-balance updates during transitions, appear sensitive to manipulable pool-value estimates and griefing
- Proxy deployment/initialization shows a recurring first-caller ownership takeover direction when initialization is not atomic
- Delegatecall proxy-manager behavior was treated as suspicious but is still less resolved than controller/category logic

## Useful Context
- Cross-round attention concentrated most heavily on controller, category, and proxy setup code; these are the main audit gravity centers so far
- The durable pattern is not isolated arithmetic bugs but governance-free or low-friction control paths consuming manipulable oracle/supply signals
- Oracle pricing, market-cap derivation, and rebalance state transitions form one connected attack surface rather than separate issues
- Proxy-side concerns are primarily initialization and control-plane risks, while controller-side concerns are input integrity and transition-time behavior
