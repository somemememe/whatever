# Global Audit Memory

## Scope Touched
- `contracts/ERC404.sol`: dominant audit surface so far; attention centered on `transferFrom`, `_transfer`, `_preTransferCheck`, `_mint`, `_burn`, and ERC20/ERC721 branch selection
- `contracts/pandorasblock404.sol`: secondary focus on constructor/setup and trading-control configuration, especially pool assignment and admin wiring
- ERC404 transfer/approval flow: recurring concern that fungible and NFT paths are multiplexed through `amountOrId <= minted`, creating fragile mode-selection behavior
- Pool-facing trading restrictions: sell gating around `_uniswapV3Pool` is a consistent issue direction and source of retained findings

## Issue Directions Seen
- Unchecked Solidity 0.7 arithmetic in ERC20 allowance/balance updates, especially in `transferFrom` and `_transfer`
- Honeypot-style or sell-lock behavior implemented through `_preTransferCheck`, including both long-lived pool sell blocking and short post-buy lock windows
- Mixed ERC20/ERC721 semantics in shared transfer/approval paths, with repeated scrutiny on branching keyed by `minted`
- Admin/configuration trust surfaces around pool assignment, whitelist handling, and ownership state
- Standards/integration edge cases around `safeTransferFrom`, `ownerOf`, and gas-heavy mint/burn loops were explored but not retained

## Useful Context
- Cross-agent attention converged heavily on `ERC404.sol`; `_preTransferCheck` and sell restriction logic were the main overlap zone
- One investigation track went deeper on arithmetic safety and fungible/non-fungible mode confusion, while another emphasized admin/configuration and standards behavior
- Durable retained issues to date all come from `ERC404.sol`: arithmetic misuse in ERC20 transfer flow and multiple sell-lock mechanisms tied to pool/trading checks
- `@openzeppelin/contracts/utils/Strings.sol` was touched incidentally and has not emerged as a meaningful audit surface
