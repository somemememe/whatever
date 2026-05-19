# Global Audit Memory

## Scope Touched
- `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV1.sol` - primary vault share/accounting logic; repeated attention on deposit, mint, withdraw, and empty-vault behavior
- `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV2.sol` - ERC4626-facing vault paths; rounding/compliance edge cases and helper behavior
- `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultStorage.sol` - core storage/state assumptions tied to vault accounting and initialization safety
- `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/inheritance/GovernableInit.sol` - initializer/governance setup reviewed in takeover-risk context
- `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/inheritance/ControllableInit.sol` - initializer/control wiring reviewed alongside proxy/init safety
- `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/inheritance/Storage.sol` - seen as potentially relevant storage/helper surface but still comparatively underexplored
- `0xf0358e8c3cd5fa238a29301d0bea3d63a17bedbe/Contract.sol` - proxy/deployment path inspected for initialization and takeover exposure

## Issue Directions Seen
- Uninitialized proxy / initializer takeover risk around vault deployment and governance-control setup
- Zero-supply and first-depositor share-accounting edge cases, especially asset capture when supply is empty
- ERC4626 rounding/compliance mismatches in `mint()` and `withdraw()`, including under-mint, short-pay, and zero-share charging behaviors
- Empty-vault ERC4626 helper/view behavior causing reverts instead of graceful previews
- Strategy-reported NAV / `investedUnderlyingBalance()` trust assumptions were explored as a pricing direction, but not retained so far

## Useful Context
- Cross-agent attention is concentrated on vault core contracts plus initialization/governance inheritance rather than peripheral strategy code
- `VaultV1.sol`, `VaultV2.sol`, and `VaultStorage.sol` are the recurring high-signal files across review activity
- Proxy/deployment logic has been examined by only one agent so far, making it notable but less cross-validated
- One retained cluster already emerges around ERC4626 semantics and empty/low-supply state handling
- `Storage.sol` appears adjacent to important state assumptions but has not yet received the same depth as the main vault files
