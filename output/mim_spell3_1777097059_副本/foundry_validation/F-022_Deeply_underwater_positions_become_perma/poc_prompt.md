You are generating a Foundry PoC contract.

Target source root:
/Users/zhanglongqin/audithoundv2/cases/mim_spell3/src

Target contract address:
0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c

Finding:
- id: F-022
- severity: High
- confidence: high
- title: Deeply underwater positions become permanently unliquidatable and leave irrecoverable bad debt
- claim: `liquidate()` computes the collateral to seize from the requested `borrowPart` and then blindly subtracts that `collateralShare` from `userCollateralShare[user]` without capping it to the borrower's remaining collateral. Once a position is so underwater that the required collateral exceeds the collateral left on the account, the subtraction reverts instead of seizing all remaining collateral and recognizing the shortfall.
- impact: After sufficiently adverse price moves, borrowers can be left with positive debt that no liquidator can clear through the protocol's liquidation path. That bad debt remains embedded in `totalBorrow`, can render the market insolvent, and any liquidation batch that includes such an account reverts wholesale.

Exploit paths:
- A user borrows near the limit and the collateral price later falls sharply.
- Liquidators partially liquidate until the remaining debt still outstanding would require more collateral than the user has left.
- The next liquidation attempt reaches `userCollateralShare[user].sub(collateralShare)` with `collateralShare > userCollateralShare[user]` and reverts.
- The account keeps residual `userBorrowPart` that cannot be fully cleaned up through `liquidate()`.

Relevant locations:
- cauldrons/CauldronV4.sol:584
- cauldrons/CauldronV4.sol:593

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
