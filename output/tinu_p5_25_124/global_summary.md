# Global Audit Memory

## Scope Touched
- `0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol` — dominant focus across rounds; scrutiny centers on `_transfer` gating, owner/admin setters, fee and cooldown controls, swap/payout paths, and reflection accounting
- Transfer-control surface in `Contract.sol` — repeated attention on blacklist logic, trading enable/disable, max-tx limits, and buyer cooldown as owner-controlled mechanisms that can freeze or heavily constrain user transfers
- Fee/reflection/swap surface in `Contract.sol` — recurring concern around fee escalation, team-fee/reflection bookkeeping, and contract auto-swap/manual payout flows as value-extraction or DoS vectors

## Issue Directions Seen
- Owner-controlled transfer restrictions remain a primary direction: blacklist freezes, trading shutdown, zeroed max-tx, and abusive cooldown configuration
- Reflection/accounting correctness is a major vulnerability direction, especially team-fee handling that may mint/inflate value later extractable through swap logic
- Fee-path abuse is a recurring theme: elevated transfer fees, unsafe fee-wallet configuration, and swap-triggered payout behavior creating extraction or liveness risks
- Manual swap/send and adjacent payout helpers were repeatedly flagged as suspicious supporting surfaces, even when not retained as standalone findings

## Useful Context
- Audit attention is highly concentrated in a single file, with repeated passes over later administrative and transfer-accounting sections rather than broader contract discovery
- Cross-agent overlap is strongest around `_transfer` and nearby owner setters, suggesting the contract’s core risk is centralized control over transferability and fee behavior
- A stable split in focus emerged: one line of review emphasized honeypot/freeze controls, while another emphasized accounting integrity and swap-side consequences
- No additional files became relevant; underexplored but repeatedly mentioned functions inside `Contract.sol` include `manualSwap()`, `manualSend()`, and `deliver()`
