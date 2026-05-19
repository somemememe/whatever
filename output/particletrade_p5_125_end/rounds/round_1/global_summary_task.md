You maintain a concise global audit memory for future audit agents.

Update the existing global memory by folding in durable observations from the
latest round summary. The goal is an accumulated cross-round audit view, not a
per-round recap.

This memory is optional context only. Findings are stored separately.

Write the updated memory in this exact structure:

# Global Audit Memory

## Scope Touched
- files/contracts/flows that have mattered across rounds, with short issue-direction notes

## Issue Directions Seen
- recurring or promising vulnerability directions seen across the audit

## Useful Context
- compact cross-round observations 

Rules:
- keep it compact
- preserve useful prior context while integrating new durable observations
- prefer stable cross-round patterns over latest-round details
- fold repeated wording into a single clearer observation
- keep the memory descriptive rather than prescriptive

## Existing Global Memory
No global memory yet.

## Latest Round Summary
# Round 1 Summary

## Agent: codex_1
- files touched: `contracts/protocol/ParticleExchange.sol`, `contracts/interfaces/IParticleExchange.sol`, `lib/openzeppelin-contracts/contracts/utils/Multicall.sol`
- files revisited / highest-attention files: `contracts/protocol/ParticleExchange.sol` was the clear focus; attention clustered around payable entrypoints, refinance logic, repayment/settlement paths, and lien/NFT state rewrites
- main issue directions investigated: `msg.value` reuse through OZ `Multicall`; refinance state transitions and lien aliasing; token ID handling across repayment, buyback, auction, and receiver flows; auction/liquidation gating
- promising but not retained directions: immediate lender-triggered auction / missing maturity-health checks was reported by the agent but not retained after merge

## Agent: opencode_1
- files touched: `output/particletrade_p5_125_end/rounds/round_1/agent_opencode_1/current_task.md`, `contracts/protocol/ParticleExchange.sol`
- files revisited / highest-attention files: `contracts/protocol/ParticleExchange.sol`
- main issue directions investigated: only initial contract intake is visible from the logs
- promising but not retained directions: none visible in the logs

## Cross-Agent Status
- main overlap in file/area attention: both agents focused on `contracts/protocol/ParticleExchange.sol`
- notable differences in attention: `codex_1` also traced interface and library interactions, especially `Multicall` and lien/token ID handling; `opencode_1` only shows a first-pass read of the main protocol contract and produced no visible findings
- underexplored but suspicious files/functions if clearly supported by the logs: auction-related paths in `ParticleExchange.sol` appear only lightly supported across agents; they were examined by `codex_1` but not retained

## Retained Findings
- Retained issues concentrated in `ParticleExchange.sol` around three themes: batched payable calls reusing one `msg.value`, refinance corrupting lien-to-NFT association so replacement collateral can be withdrawn by the wrong party, and closeout flows treating NFTs as collection-fungible so a cheaper token can replace a rarer escrowed one.


Output only markdown.
