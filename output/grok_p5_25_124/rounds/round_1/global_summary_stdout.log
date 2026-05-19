# Global Audit Memory

## Scope Touched
- `0x8390a1da07e376ef7add4be859ba74fb83aa02d5/Contract.sol` - dominant audit surface so far; repeated focus on `_transfer`, `openTrading`, blacklist controls, fee-swap / tax forwarding, and router / approval setup
- Trading lifecycle and liquidity setup flows - attention centered on launch, LP custody, and owner-controlled market access
- Sell-path fee handling - recurrent concern around ETH forwarding during swaps and whether tax-wallet behavior can break sells

## Issue Directions Seen
- Owner-controlled blacklist logic as a trading-freeze / honeypot direction, including selective or broad blocking of transfers
- Initial LP token custody with the owner as a liquidity-rug direction tied to `openTrading`
- Sell denial-of-service if tax ETH forwarding relies on `transfer` and the tax wallet cannot receive ETH that way
- Repeated but lower-signal centralization/configuration themes: hardcoded router assumptions, approval trust, limits removal, anti-bot controls, and single-actor privileged operations

## Useful Context
- Cross-round attention is concentrated almost entirely in one file, with no meaningful expansion to adjacent contracts yet
- `_transfer` and `openTrading` are the highest-attention functions across agents and carry most of the durable risk signal
- One agent focused on concrete execution paths in transfer/swap/liquidity mechanics, while another surveyed broader governance and configuration patterns; retained signal came from the concrete execution-path issues
- Several router/approval/timelock-style concerns were explored but not retained, so they remain background context rather than established issue themes
