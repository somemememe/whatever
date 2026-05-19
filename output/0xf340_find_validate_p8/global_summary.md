# Global Audit Memory

## Scope Touched
- `0xf340.sol` — sole in-scope contract so far; attention centers on initialization/configuration and the downstream payout/claim path
- `initVRF(address,address)` — persistent issue direction around externally reachable reconfiguration of critical recipient/token state
- selector `0x607d60e6(0)` flow — treated as the repeatable payout/claim entrypoint; internal logic remains partially opaque but is central to the drain direction

## Issue Directions Seen
- Access-control weakness on one-time or privileged setup, especially arbitrary caller control over VRF/payout-related configuration
- Reusable payout/claim execution after malicious setup, suggesting replay or missing consumption/state-invalidation on distribution logic
- Chaining risk between configuration functions and payout functions, where unsafe initialization appears to unlock downstream fund redirection

## Useful Context
- Audit attention has remained concentrated on a single contract and a single configuration-to-payout flow, so these observations are currently the strongest durable context
- No separate secondary file or independent issue family has emerged yet beyond the access-control plus replay/drain cluster
- The downstream function behind selector `0x607d60e6` is not yet fully transparent from available traces, but it consistently appears as the mechanism enabling repeated extraction once configuration is attacker-controlled
