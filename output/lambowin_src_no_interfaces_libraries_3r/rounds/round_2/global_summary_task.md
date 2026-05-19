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
# Global Audit Memory

## Scope Touched
- Core launch stack repeatedly examined: `VirtualToken.sol`, `LamboFactory.sol`, `LamboVEthRouter.sol`, `rebalance/LamboRebalanceOnUniwap.sol`.
- Secondary but relevant scope: `LamboToken.sol`, `Utils/LaunchPadUtils.sol`, Uniswap pool interface context.
- Cross-contract flow focus: launch creation -> vETH loan quota usage -> router quote/settlement -> rebalance execution/initialization.

## Issue Directions Seen
- Persistent accounting-consistency risk between mint/burn logic and real asset backing (especially vToken cash in/out paths).
- Economic/DoS pressure around shared per-block launch loan quota consumption.
- Router pricing/quote assumptions diverging from actually transferable reserves, creating sell-path lock/failure risk.
- Repeated edge-case value-leak direction in payment/refund math (small dust accumulation).
- Upgradeable/initializer takeover exposure remained a recurring high-signal direction.
- Frequently explored but lower-signal in this audit: generic owner-privilege, slippage/MEV, reentrancy/approval framing.

## Useful Context
- Highest-confidence work came from concrete cross-contract exploit-path validation rather than generic checklist findings.
- Multiple agents converged on router/rebalance + virtual-asset accounting as the most fertile attack surface.
- Rebalance guard/execution logic and `LamboToken.sol` drew attention but produced limited retained outcomes beyond initialization risk.


## Latest Round Summary
# Round 2 Summary

## Agent: codex_1
- files touched: `LamboFactory.sol`, `LamboToken.sol`, `LamboVEthRouter.sol`, `VirtualToken.sol`, `Utils/LaunchPadUtils.sol`, `rebalance/LamboRebalanceOnUniwap.sol` (plus interface/library context reads and local tooling checks)
- files revisited / highest-attention files: `LamboFactory.sol` (createLaunchPad flow), `VirtualToken.sol`, `rebalance/LamboRebalanceOnUniwap.sol`
- main issue directions investigated: launchpad creation flow correctness, LP mint/burn mechanics, virtual debt lifecycle/repayment paths, rebalance slippage/execution bounds, initializer and deployment-assumption risks
- promising but not retained directions: debt settlement/insolvency framing (F-007), rebalance minReturn concerns (F-008), initializer seize risk (F-009), chain/address guard assumptions (F-010)

## Agent: opencode_1
- files touched: `LamboFactory.sol`, `LamboToken.sol`, `LamboVEthRouter.sol`, `VirtualToken.sol`, `Utils/LaunchPadUtils.sol`, `rebalance/LamboRebalanceOnUniwap.sol` (also read prior round/global summaries)
- files revisited / highest-attention files: router (`LamboVEthRouter.sol`), `VirtualToken.sol`, rebalance contract, factory launch path
- main issue directions investigated: router execution ordering/quote semantics/deadline, virtual token debt and cashIn behavior, rebalance slippage and mask handling, factory pool-creation validation, owner-configurable fee risk
- promising but not retained directions: multiple medium/low operational-risk and centralization-style claims (deadline/pause/100% fee/no-pause/pool validation) that were not merged as retained findings

## Cross-Agent Status
- main overlap in file/area attention: strong overlap on `LamboFactory.sol`, `LamboVEthRouter.sol`, `VirtualToken.sol`, and `rebalance/LamboRebalanceOnUniwap.sol`
- notable differences in attention: `codex_1` concentrated on concrete launchpad breakage with explicit failing call path; `opencode_1` produced a wider set of router/configuration and hygiene-style issues
- underexplored but suspicious files/functions if clearly supported by the logs: `LamboToken.sol` received review attention but produced no retained round-2 finding; rebalance logic was repeatedly examined but no new retained issue this round

## Retained Findings
- `F-006` (Critical, high confidence) retained: launchpad creation can revert because factory mints LP then transfers LP tokens to `address(0)`, which is incompatible with Uniswap V2-style LP transfer semantics, bricking core launch flow.


Output only markdown.
