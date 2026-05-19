# Global Audit Memory

## Scope Touched
- `onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol` — dominant focus across audit; `freeMint`, `publicMint`, `_getRandom`, prize payout, bonus-pool funding, and withdraw paths
- `Contract.sol` inheritance/mint internals (`ERC721L`-driven `_safeMint` flow) — reviewed mainly for receiver-callback rollback and contract-caller behavior during mint/payout resolution

## Issue Directions Seen
- Whitelist authorization is tied to a user-supplied address in `freeMint`, pointing to claim theft / unauthorized consumption of another account’s allowance
- Mint outcome can be made selective via contract-call patterns around `_safeMint` / `onERC721Received`, suggesting rollback of losing mints while keeping winning ones
- `_getRandom` relies on block-derived entropy, a recurring direction for predictable or inclusion-manipulable prize outcomes
- ETH distribution uses `send` and fixed recipients, repeatedly raising payout/withdraw liveness risk if recipients cannot accept 2300-gas transfers
- Admin/config surfaces exist but were secondary compared with mint/randomness exploitability

## Useful Context
- Audit attention has been heavily concentrated in a single file; no meaningful multi-file attack surface emerged yet
- Cross-agent overlap is strongest on mint authorization, randomness, and payout mechanics; config/hygiene observations were less consistently compelling
- Inherited ERC721 mint mechanics mattered mainly insofar as they interact with receiver callbacks and transactional rollback behavior
- Lower-signal ideas such as generic reentrancy, missing events, or simple UX/config complaints did not persist as core audit directions
