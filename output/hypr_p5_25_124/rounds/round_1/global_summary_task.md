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
- files touched: `src/universal/StandardBridge.sol`, `src/L1/L1StandardBridge.sol`, OpenZeppelin `proxy/utils/Initializable.sol`
- files revisited / highest-attention files: `src/universal/StandardBridge.sol` was the clear focal file; `src/L1/L1StandardBridge.sol` and `Initializable.sol` were central to the retained initialization issue
- main issue directions investigated: bridge initialization / messenger trust replacement; ERC20 escrow accounting for fee-on-transfer or deflationary tokens; post-deposit token behavior that breaks escrow redeemability
- promising but not retained directions: no additional non-retained directions were explicit in the visible log

## Agent: opencode_1
- files touched: `src/L1/L1StandardBridge.sol`, `src/universal/StandardBridge.sol`, `src/universal/CrossDomainMessenger.sol`, `src/universal/OptimismMintableERC20.sol`, `src/universal/IOptimismMintableERC20.sol`, `contracts/legacy/L1ChugSplashProxy.sol`, `src/libraries/Encoding.sol`, `src/libraries/Hashing.sol`, `src/libraries/SafeCall.sol`, `src/libraries/Constants.sol`, `src/libraries/Arithmetic.sol`, `src/libraries/Burn.sol`, `src/libraries/Predeploys.sol`, `src/libraries/Types.sol`, `src/L1/ResourceMetering.sol`
- files revisited / highest-attention files: `src/universal/StandardBridge.sol` and `src/L1/L1StandardBridge.sol` were the main focus, with supporting review of messenger, token, proxy, and gas-call utility code
- main issue directions investigated: withdrawal/accounting behavior in `finalizeBridgeERC20`; ETH finalization transfer behavior; initialization exposure on `L1StandardBridge`; gas / relay edge cases in `CrossDomainMessenger` and `SafeCall`; unsupported token semantics such as blocklists
- promising but not retained directions: `finalizeBridgeERC20` underflow / insufficient-deposit framing; ETH lockup on `finalizeBridgeETH`; gas-estimation / relay-failure concerns; zero-address constructor validation in `OptimismMintableERC20`; `onlyEOA` bypass angle

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `StandardBridge` and `L1StandardBridge`, especially bridge authentication, token custody, and withdrawal/finalization behavior
- notable differences in attention: `codex_1` stayed tightly focused on retained high-signal bridge takeover and escrow-accounting issues; `opencode_1` spread attention across messenger, proxy, token, and library surfaces and explored more edge-case hypotheses
- underexplored but suspicious files/functions if clearly supported by the logs: `CrossDomainMessenger` relay/gas paths and `SafeCall` gas-checking logic were examined by `opencode_1` but did not produce retained findings in this round

## Retained Findings
- `F-001`: retained the bridge-takeover path where `L1StandardBridge.initialize()` can be re-invoked because the legacy-slot clearing resets `Initializable` state, enabling messenger replacement and downstream withdrawal forgery
- `F-002`: retained the insolvency issue where non-mintable ERC20 deposits credit the nominal amount without measuring actual received tokens, breaking collateralization for fee-on-transfer / deflationary assets
- `F-003`: retained the lockup risk for permissionlessly accepted ERC20s whose balances or transfer permissions can change after deposit, such as rebasing, confiscatable, allowlist, or blocklist-controlled tokens


Output only markdown.
