# Global Audit Memory

## Scope Touched
- `0xfb772316a54dcd439964b561fc2c173697aeeb5b/Contract.sol`: primary audit focus; user-flow accounting around mint/burn/borrow/margin trade, initialization pricing, and privileged surfaces like `updateSettings` / `flashBorrow`
- `0x7f3fe9d492a9a60aebb06d82cba23c6f32cad10b/Contract.sol`: proxy/admin wrapper reviewed for fallback ETH handling, upgrade/control surfaces, and low-level forwarding behavior

## Issue Directions Seen
- Asset/share accounting repeatedly looks fragile when token transfers do not match nominal amounts, especially with fee-on-transfer behavior in mint and debt-opening flows
- Uninitialized or pre-seeded pool state creates first-user pricing/capture risk if share issuance keys off stale or incomplete balances
- Proxy fallback behavior is a recurring concern, especially ETH reception paths that can bypass intended logic and strand value
- Privileged control planes (`updateSettings`, proxy target/admin controls, `flashBorrow` external call path) remain a standing review direction even though round-1 ideas there were not retained

## Useful Context
- Most cross-round attention concentrated on the main pool contract, with secondary attention on the proxy shell
- Investigation split has been consistent: one track on user-facing accounting correctness, another on admin/upgrade/external-call authority
- Durable retained themes so far are concrete balance-accounting mismatches and proxy ETH-handling edge cases, not generic centralization or oracle concerns
