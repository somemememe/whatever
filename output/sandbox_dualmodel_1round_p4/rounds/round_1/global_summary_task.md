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
- files touched: all 10 in-scope Solidity files, with focused rereads of `src/Land/erc721/ERC721BaseToken.sol`, `src/Land/erc721/LandBaseToken.sol`, `src/Land.sol`, and receiver/interface helpers under `contracts_common/src`
- files revisited / highest-attention files: `src/Land/erc721/ERC721BaseToken.sol` and `src/Land/erc721/LandBaseToken.sol` received the most line-by-line review and targeted searches
- main issue directions investigated: burn authorization and accounting corruption, burn sentinel interactions with quad regroup/transfer logic, quad mint/transfer receiver checks, and nearby approval / transfer surfaces
- promising but not retained directions: approval and super-operator related paths were searched around `approveFor`, `setApprovalForAllFor`, and transfer flows, but only the burn/quad/receiver issues were retained after merge

## Agent: opencode_1
- files touched: all 10 in-scope Solidity files were read once, including all helper/access-control contracts plus `src/Land.sol`, `src/Land/erc721/ERC721BaseToken.sol`, and `src/Land/erc721/LandBaseToken.sol`
- files revisited / highest-attention files: no explicit revisits are visible in the log; output emphasis centered on `src/Land/erc721/ERC721BaseToken.sol`, `src/Land/erc721/LandBaseToken.sol`, `contracts_common/src/BaseWithStorage/SuperOperators.sol`, and `contracts_common/src/BaseWithStorage/Admin.sol`
- main issue directions investigated: super-operator privilege model, approval flows, admin-change safety, ERC-165/interface behavior, batch transfer existence checks, burn underflow, and basic zero-address validation
- promising but not retained directions: the agent raised multiple access-control and validation concerns, but after merge only the externally callable burn issue overlapped with retained findings

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `src/Land/erc721/ERC721BaseToken.sol` and `src/Land/erc721/LandBaseToken.sol`, especially transfer/burn-related behavior
- notable differences in attention: `codex_1` drilled into burn sentinel mechanics, quad regrouping, and receiver-check lockups; `opencode_1` focused more on super-operator, approval, admin, and interface-validation themes
- underexplored but suspicious files/functions if clearly supported by the logs: approval and privileged-transfer entry points in `src/Land/erc721/ERC721BaseToken.sol` were examined by both agents but did not produce retained findings in this round; helper contracts under `contracts_common/src/BaseWithStorage/` were reviewed but remain without merged issues from the visible logs

## Retained Findings
- retained set centers on LAND burn/transfer mechanics in the ERC721/Land base contracts
- the merged critical issue is the public `_burn` path allowing unauthorized destruction of LAND and balance corruption
- additional retained issues are burn-sentinel induced permanent quad-transfer breakage and unsafe quad receiver validation that can lock LAND in incompatible contracts


Output only markdown.
