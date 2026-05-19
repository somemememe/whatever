# Global Audit Memory

## Scope Touched
- `onchain_auto/0x8f9036732b9aa9b82d8f35e54b71faeb2f573e2f/contracts/DaoModule.sol` — main hotspot; proposal approval, execution, expiry, invalidation, and resubmission lifecycle drive the meaningful risk surface
- `onchain_auto/0x8f9036732b9aa9b82d8f35e54b71faeb2f573e2f/contracts/interfaces/Realitio.sol` — consulted to pin down oracle timing/finalization and bond semantics behind `DaoModule` checks
- `executeProposal` / `executeProposalWithIndex` flow — central path for both execution-surface review and the retained stranded-prefix execution issue
- proposal expiry / invalidation flow, including `markProposalWithExpiredAnswerAsInvalid` and nonce-based resubmission — relevant to whether partially executed proposals can ever be recovered
- question creation / answerability timing — relevant to whether governance-linked proposals become executable before the intended vote window has actually elapsed

## Issue Directions Seen
- Oracle question timing can decouple from governance timing, especially when proposals are created with immediate answerability and can finalize before the referenced vote truly ends
- Multi-transaction execution is sensitive to expiry boundaries; partial prefix execution plus later approval expiry/invalidation can strand the remainder permanently
- Economic assurance around `minimumBond` is weakened if the module relies on a question’s highest historical bond instead of the bond backing the final accepted answer
- The dominant audit surface is not generic call validation but the interaction between oracle state, approval lifecycle, and indexed multi-step execution

## Useful Context
- `DaoModule.sol` has been the consistent focus across agents; `Realitio.sol` mainly serves as a semantics anchor rather than an independent hotspot
- Cross-round attention keeps converging on lifecycle edges: proposal creation, oracle resolution, execution-by-index, expiry, invalidation, and retry/resubmission behavior
- Several generic execution-risk theories were explored around transaction execution, but the durable signal so far comes from governance/oracle timing and state-machine edge cases rather than broad arbitrary-call concerns
