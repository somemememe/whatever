You are generating a Foundry PoC contract.

Target source root:
/Users/zhanglongqin/audithoundv2/cases/mim_spell3/src

Target contract address:
0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c

Finding:
- id: F-003
- severity: Critical
- confidence: medium
- title: Zero oracle rates are accepted and make any borrower with nonzero collateral appear solvent
- claim: Neither `init()` nor `updateExchangeRate()` validates that the oracle returned success or that the returned rate is nonzero before storing or using it. If the cached `exchangeRate` becomes zero, `_isSolvent()` reduces the debt side of the solvency inequality to zero, so any account with positive collateral passes solvency checks, and `liquidate()` also stops treating those borrowers as insolvent.
- impact: During a zero-rate oracle event, users can post dust collateral, borrow out the cauldron's MIM, and remain effectively unliquidatable until a valid price is restored.

Exploit paths:
- At initialization, `oracle.get()` can return `(false, 0)` or another zero rate and the clone stores `exchangeRate = 0` without reverting.
- Later, a user borrows through `borrow()` or `cook(ACTION_BORROW, ...)`; the post-action solvency check uses the zero cached rate, so the position is accepted despite being deeply undercollateralized.

Relevant locations:
- cauldrons/CauldronV4.sol:158
- cauldrons/CauldronV4.sol:201
- cauldrons/CauldronV4.sol:227
- cauldrons/CauldronV4.sol:230
- cauldrons/CauldronV4.sol:578

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
