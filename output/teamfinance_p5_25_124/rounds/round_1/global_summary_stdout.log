# Global Audit Memory

## Scope Touched
- `onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol` — dominant review surface; issues cluster around initialization/ownership control, asset recovery authority, lock/accounting griefing, NFT handling, and fee logic
- `onchain_auto/0xe2fe530c047f2d85298b07d9333c05737f1435fb/Contract.sol` — mainly relevant as proxy/initialization context rather than a standalone issue source
- OpenZeppelin `Ownable.sol` / `Initializable.sol` under `node_modules/@openzeppelin/contracts-ethereum-package/...` — checked to confirm initializer-to-owner takeover behavior
- `contracts/interfaces/IUniswapV3PositionManager.sol` and `contracts/interfaces/IERC721Extended.sol` — lightly touched supporting interfaces tied to NFT/position-manager interactions

## Issue Directions Seen
- Uninitialized proxy / initializer capture remains a core direction, with ownership establishment dependent on first successful initialization
- Strong owner privilege concentration in `recoverAssets()` suggests an admin seizure/backdoor pattern rather than narrow rescue semantics
- User-facing lock bookkeeping may be griefable through arbitrary-recipient or dust lock creation that bloats victim withdrawal/exit paths
- ERC721 reception/handling is a recurring risk area: unconditional receipt or transfer-flow mismatches can strand NFTs
- Referral and fee accounting logic is a meaningful economic direction; math and config edge cases can materially undercharge or misroute fees
- Secondary but so far unretained directions include withdrawal sequencing, split-lock timing/state behavior, upgrade/admin controls, whitelist/config powers, and general array/accounting consistency

## Useful Context
- Cross-round attention is heavily concentrated on `LockToken.sol`; other files mainly serve as supporting context
- The clearest overlap across agents is the combination of initializer ownership risk plus owner-controlled asset recovery
- `Contract.sol` has been reviewed by multiple agents, but mostly to explain deployment and initialization assumptions behind `LockToken.sol`
- Several candidate issues were explored but not retained, so the durable memory should emphasize control-plane, accounting/griefing, NFT custody, and fee-math patterns rather than one-off edge cases
