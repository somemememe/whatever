# Global Audit Memory

## Scope Touched
- `0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol` - dominant focus across the audit; core deposit, withdraw, withdrawal processing, rebase, and legacy queued-withdrawal paths drive the main risk surface
- `0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/helpers/Utils.sol` - supporting transfer/payment helper reviewed alongside core accounting and payout behavior
- `0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/interfaces/IRestakedETH.sol` - important trust-boundary surface for restaked token interactions and withdrawal assumptions
- `0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/interfaces/IDelegator.sol` - relevant to delegation and legacy withdrawal-completion behavior
- `0xbaa87546cf87b5de1b0b52353a86792d40b8ba70/Contract.sol` - lightly explored peripheral contract with no durable issue direction yet

## Issue Directions Seen
- Asset accounting mismatch between requested, received, and share-priced amounts is a central recurring direction, especially around deposits before rebases
- Trust assumptions around external restaked token contracts/interfaces are a key attack surface
- Withdrawal lifecycle robustness is a major theme, including queue ordering, liveness, and completion correctness under changing delegation state
- Manual or delayed rebase mechanics appear tightly coupled to fairness/correctness of minting and redemption
- Broader generic themes like slippage protection, loop/gas DoS, transfer helper behavior, and access control were explored but are secondary to the protocol-specific accounting and withdrawal issues

## Useful Context
- Retained issues so far cluster heavily in Astrid’s core asset-accounting and withdrawal machinery rather than in generic admin or validation patterns
- Cross-agent overlap was strongest on `AstridProtocol.sol`; supporting helpers/interfaces mainly mattered insofar as they affected accounting, payouts, and delegation-linked withdrawals
- The strongest durable pattern is mismatch between protocol assumptions and real external/stateful behavior: token amounts actually received, rebases not yet reflected, untrusted restaked token inputs, and legacy EigenLayer withdrawal state after redelegation
