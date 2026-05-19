# Global Audit Memory

## Scope Touched
- `0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol` — central audit surface across rounds; repeated focus on buy paths, claim/claim-and-stake flows, `startClaim` accounting, staking integration, and upgradeable setup
- OpenZeppelin upgradeable bases (`OwnableUpgradeable`, `PausableUpgradeable`, `ReentrancyGuardUpgradeable`) — relevant mainly for initializer / proxy-state assumptions around `PresaleV5`
- `0x1f006f43f57c45ceb3659e543352b4fae4662df7/contracts/proxy/*` — deployment/proxy side noted as relevant but still lightly explored
- `0x1f006f43f57c45ceb3659e543352b4fae4662df7/contracts/import.sol` — briefly checked, no durable issue direction retained

## Issue Directions Seen
- Upgradeable deployment / initializer gaps leading to unset ownership or core configuration
- Buy-path gating failures: configured sale-window variables appear disconnected from actual purchase enforcement
- Claim-path gating failures: claim functions appear insufficiently tied to intended unlock timing
- Token accounting mismatches between sold allocations and claim funding readiness
- Unsafe external token/payment assumptions, especially low-level USDT `transferFrom` handling
- Weak validation of staking-manager integrations causing successful user flows without real downstream staking effects
- Secondary directions seen but not retained: reentrancy posture on buy paths, approval-drain surfaces, precision loss, and admin/event hygiene

## Useful Context
- Cross-round attention has concentrated overwhelmingly on `PresaleV5`; most durable risk comes from control-flow disconnects between configured state and enforced behavior
- Claim activation, funding preparation, and buy accounting are tightly coupled and have repeatedly produced the strongest issue candidates
- External integrations are a recurring trust boundary: both payment-token behavior and staking-manager behavior can diverge from optimistic assumptions made by the sale logic
- Proxy/deployment context matters because several core findings become higher impact when initialization is missing or incomplete
