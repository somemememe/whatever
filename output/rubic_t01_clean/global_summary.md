# Global Audit Memory

## Scope Touched
- `FlawVerifier.sol` — strongest recurring attention on the `routerCallNative` exploit path, especially proxy-mediated token movement via attacker-chosen router/call data
- `interface.sol` — reviewed as a code-bearing helper surface rather than a pure interface; notable areas included transfer/approve wrappers, ETH send helpers, math helpers, and clone/deployment utilities, but no retained issue yet

## Issue Directions Seen
- Rubic proxy abuse where attacker-controlled external call parameters can make the proxy execute as an already-approved spender and pull tokens from victims with lingering allowances
- Trust-boundary risk around arbitrary router targets plus user-controlled calldata in native-routing flows
- Secondary helper-library footgun review around token-call assumptions, approval semantics, ETH forwarding behavior, tolerant math edge cases, and clone validation; investigated but not yet retained

## Useful Context
- Cross-round memory currently centers on allowance-driven draining risk, not on isolated token/helper bugs
- `interface.sol` contains meaningful executable helper logic and remains worth treating as attack surface despite lacking a retained finding so far
- The most durable pattern from the round is abuse of existing approvals through proxy call composition, rather than creation of new approvals or balance accounting flaws
