You are generating a Foundry PoC contract.

Target source root:
/Users/zhanglongqin/audithoundv2/cases/mim_spell3/src

Target contract address:
0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c

Finding:
- id: F-001
- severity: Critical
- confidence: high
- title: `cook()` solvency enforcement can be cleared by `ACTION_ACCRUE` or any unsupported action
- claim: `cook()` sets `status.needsSolvencyCheck = true` after `ACTION_BORROW` and `ACTION_REMOVE_COLLATERAL`, but any unhandled action falls through to `_additionalCookAction()`. In `CauldronV4` that hook has an empty implementation and does not revert, yet `cook()` blindly replaces the current `status` with its return value. Because `ACTION_ACCRUE` is declared but never handled, and arbitrary unsupported action IDs also route there, a user can append one of those actions after borrowing or removing collateral to reset `needsSolvencyCheck` to `false` and skip the final insolvency check entirely.
- impact: An attacker can borrow MIM or withdraw collateral and finish the transaction undercollateralized, creating immediate bad debt and potentially draining the cauldron's available MIM.

Exploit paths:
- Call `cook()` with `ACTION_BORROW` followed by `ACTION_ACCRUE`; the borrow succeeds, the empty hook returns a zeroed `CookStatus`, and the final solvency check is skipped.
- Call `cook()` with `ACTION_REMOVE_COLLATERAL` followed by any unsupported action ID; collateral is removed, `needsSolvencyCheck` is cleared, and the transaction can end insolvent.

Relevant locations:
- cauldrons/CauldronV4.sol:369
- cauldrons/CauldronV4.sol:456
- cauldrons/CauldronV4.sol:488
- cauldrons/CauldronV4.sol:527
- cauldrons/CauldronV4.sol:538

Task:
Create COMPLETE Solidity source code for file `src/FlawVerifier.sol`.

Hard requirements:
1. Must compile standalone with pragma ^0.8.20.
2. Must define contract `FlawVerifier`.
3. Must define function `executeOnOpportunity()` external.
4. Must target the real on-chain contract address above.
5. Should attempt the exploit path in executable code (not only comments).
6. Include any needed interfaces inside the same file.
7. Include `receive()` if needed.
8. Do not use imports.
9. Output ONLY Solidity code, no markdown.
