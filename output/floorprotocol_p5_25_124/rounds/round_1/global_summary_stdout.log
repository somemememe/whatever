# Global Audit Memory

## Scope Touched
- `src/FloorPeriphery.sol`: main audit hotspot; user asset-flow/accounting, token/ETH handling across calls, approvals, external-call surface, ERC721 receipt behavior, and upgrade deployment/init path all mattered
- `src/library/OwnedUpgradeable.sol` and `openzeppelin/proxy/ERC1967/ERC1967Proxy.sol`: relevant for proxy initialization and ownership-takeover direction around UUPS-style deployment
- `src/FloorGetter.sol` and `src/interface/IFlooring.sol`: reviewed as broader protocol/read-surface context, especially storage/getter exposure, but not yet a source of retained issues
- `src/base/Multicall.sol`: examined as a control-surface hotspot for delegatecall/composability risk without a retained issue so far
- helper/libs around transfers and structs (`src/library/CurrencyTransfer.sol`, `src/library/ERC721Transfer.sol`, `src/logic/Structs.sol`, `src/logic/CollectionKey.sol`, `src/logic/SafeBox.sol`): mostly supporting context for periphery asset movement and collection state handling

## Issue Directions Seen
- Periphery-centric accounting flaws where residual balances or mixed custody across calls can leak value between users
- Upgradeability risk focused on uninitialized proxy windows and atomic initialization assumptions
- Asset custody edge cases, especially contracts accepting tokens/NFTs without a corresponding recovery path
- Repeated screening of approval scope, reentrancy, delegatecall/multicall safety, deadline handling, getter/storage exposure, and batch/DoS patterns; these were notable review directions even when not retained

## Useful Context
- Cross-round attention is heavily concentrated on `FloorPeriphery`; it is the practical hub for both retained findings and most abandoned directions
- The strongest durable pattern is mismatch between what the periphery can receive/hold and what it cleanly attributes or returns to a specific caller
- Getter and multicall surfaces were treated as suspicious exposure/control areas, but current durable context is “worth revisiting if new evidence appears,” not “known issue area”
- Retained issue themes to remember across future rounds: cross-user residual value leakage, init-time upgrade takeover exposure, and permanently stranded ERC721s due to missing rescue flow
