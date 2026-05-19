Below are findings and vulnerability signals from 2 agents auditing the same codebase,
plus accumulated findings from previous rounds. You need to inspect the source code when needed.

You are the merge and review layer for a audit.

Your task:
- merge new or materially improved reportable issues into the accumulated findings
- reconstruct plausible but poorly written findings or signals into low-confidence findings when the code supports them
- reject clearly non-reportable candidates with your reasons
- try to use this round's signals and the source code to look for additional findings yourself

Prefer downgrading severity or confidence over discarding a plausible issue.
Keep findings that can cause realistic protocol-level harm, including fund loss,
theft, insolvency, permanent lockup, economic manipulation, or permissionless DoS and some other realistic issues.

## Accumulated Findings
None yet.

## This Round's Agent Outputs
### Agent: codex_1
```
[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "Staked balance can be rehypothecated into LP while still earning staking rewards",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:354",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:363",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:420",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:688"
    ],
    "claim": "Staking only updates `_stakedBalance`/units accounting, but `provideLiquidity` can spend the same FLUID without checking unstaked availability, so the same capital is counted for both staking and LP rewards.",
    "impact": "A locker owner can double-dip rewards (staker + LP) with the same tokens, diluting reward pools and extracting disproportionate emissions from honest participants.",
    "paths": [
      "Lock X FLUID -> stake X (staker units set)",
      "Call provideLiquidity with supAmount ~= X (moves staked tokens into LP)",
      "Continue receiving staking rewards while also receiving LP rewards"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Any account can forcibly stop active program funding during early-end window",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:339",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:349",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:380"
    ],
    "claim": "`stopFunding` is externally callable without owner/admin checks, so anyone can terminate a program once `block.timestamp >= endDate - EARLY_PROGRAM_END`.",
    "impact": "Attackers can front-run expected late-period unit updates and force compensation distribution at a favorable snapshot, altering final reward allocation and griefing program operation.",
    "paths": [
      "Wait until a funded program enters its 3-day early-end window",
      "Call `stopFunding(programId)` from any address",
      "Flow stops and one-shot compensation is distributed using current units only"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "Unit-update signatures are replayable across contracts/chains",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:296",
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:319"
    ],
    "claim": "Signed messages do not include domain separation (no chainId, no verifying contract), only user/units/programId/nonce payload.",
    "impact": "A valid signature for one deployment/network can be replayed on another deployment/network with the same signer and unused nonce, causing unauthorized unit updates and reward claims.",
    "paths": [
      "Obtain valid Stack signature intended for manager A",
      "Submit same payload/signature to manager B (or another chain) where nonce is still unused"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "high",
    "title": "Repeated startFunding on same program leaves untracked residual treasury/subsidy streams",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:282",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:300",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:315",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:374"
    ],
    "claim": "`startFunding` overwrites stored program details but adds new flow deltas on top of existing flows; later stop/cancel subtract only the latest stored rates.",
    "impact": "If started twice, legacy flow components remain active and can keep draining treasury/misrouting subsidy after supposed stop, creating accounting insolvency and long-lived leakage.",
    "paths": [
      "Owner calls `startFunding(programId, ...)`",
      "Owner calls `startFunding(programId, ...)` again before stop",
      "Later `stopFunding`/`cancelProgram` removes only latest rates, leaving residual streams"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "high",
    "title": "Pumponomics swap uses zero minimum output and is sandwichable",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:644",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:650",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:654"
    ],
    "claim": "`_pump` executes `exactInputSingle` with `amountOutMinimum = 0`, providing no slippage bound.",
    "impact": "MEV bots can sandwich liquidity provisioning transactions and extract value from users by forcing poor execution on the swap leg.",
    "paths": [
      "Attacker front-runs to worsen price",
      "Victim calls `provideLiquidity` and `_pump` executes at manipulated price",
      "Attacker back-runs to restore price and captures spread"
    ]
  },
  {
    "id": "F-006",
    "severity": "Low",
    "confidence": "medium",
    "title": "Fontaine unlock termination is permissionless",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/Fontaine.sol:145",
      "superfluid-finance/fluid/packages/contracts/src/Fontaine.sol:147",
      "superfluid-finance/fluid/packages/contracts/src/Fontaine.sol:175"
    ],
    "claim": "`terminateUnlock` has no caller restriction, so any address may terminate someone else’s unlock once in the allowed window.",
    "impact": "Third parties can force premature end-of-stream behavior and alter recipient payout timing (stream -> lump sum/compensation).",
    "paths": [
      "Observe target Fontaine nearing `endDate - 1 day`",
      "Call `terminateUnlock()` from arbitrary address"
    ]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "low",
    "title": "Global SuperToken host/GDA cache can be poisoned in permissionless EPProgramManager flow",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:81",
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:85",
      "superfluid-org/protocol-monorepo/packages/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol:1849",
      "superfluid-org/protocol-monorepo/packages/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol:1893"
    ],
    "claim": "SuperTokenV1Library caches host/GDA in single contract-wide slots (not per token); EPProgramManager lets arbitrary callers supply arbitrary tokens on first `createProgram`.",
    "impact": "A malicious first token can poison cached framework addresses, causing later program creation calls to execute against wrong host/GDA or fail (DoS/misdirection).",
    "paths": [
      "Attacker calls permissionless `createProgram` with crafted token returning attacker-controlled host",
      "Library caches attacker host/GDA",
      "Subsequent `createProgram` attempts use poisoned cache"
    ]
  },
  {
    "id": "F-008",
    "severity": "Low",
    "confidence": "high",
    "title": "Factory ETH withdrawal can fail permanently due transfer stipend",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidLockerFactory.sol:151",
      "superfluid-finance/fluid/packages/contracts/src/FluidLockerFactory.sol:152"
    ],
    "claim": "`withdrawETH` uses Solidity `transfer`, which hard-limits gas forwarded to the governor receiver.",
    "impact": "If governor is a contract with non-trivial receive logic, fee withdrawals can revert and ETH can become stuck in the factory.",
    "paths": [
      "Set governor to a contract requiring >2300 gas in `receive`",
      "Call `withdrawETH()` and observe persistent revert"
    ]
  }
]

```

### Agent: opencode_1
```
[{"id":"F-001","severity":"Critical","confidence":"high","title":"Missing Access Control on Fontaine.terminateUnlock()","locations":["Fontaine.sol:145"],"claim":"The terminateUnlock() function has no access control and can be called by anyone","impact":"Any user can prematurely terminate another user's unlock stream, stealing the remaining tokens in the Fontaine contract and stopping the recipient's unlock flow","paths":["Attacker calls terminateUnlock() on any Fontaine contract they know the address of"]},{"id":"F-002","severity":"Critical","confidence":"high","title":"Missing Access Control on FluidEPProgramManager.stopFunding()","locations":["FluidEPProgramManager.sol:339"],"claim":"The stopFunding() function is publicly callable with no access control","impact":"Anyone can stop any program's funding, causing immediate flow termination and disrupting token distribution to all lockers in the program","paths":["Attacker calls stopFunding(programId) on any active program"]},{"id":"F-003","severity":"High","confidence":"high","title":"Missing Reentrancy Guard on FluidLocker.withdrawLiquidity()","locations":["FluidLocker.sol:446"],"claim":"The withdrawLiquidity() function lacks nonReentrant protection despite performing external calls and state changes","impact":"Potential reentrancy attack leading to double-withdrawal of liquidity or manipulation of accounting","paths":["Attacker calls withdrawLiquidity() in a reentrant manner to extract more tokens"]},{"id":"F-004","severity":"High","confidence":"medium","title":"Missing Access Control on StakingRewardController.distributeTaxAdjustment()","locations":["StakingRewardController.sol:208"],"claim":"The distributeTaxAdjustment() function is callable by anyone","impact":"While not directly harmful, anyone can trigger the distribution which may front-run intended administrative actions or cause unintended tax distribution","paths":["Anyone calls distributeTaxAdjustment()"]},{"id":"F-005","severity":"High","confidence":"medium","title":"FluidEPProgramManager.startFunding() Can Be Called Multiple Times","locations":["FluidEPProgramManager.sol:282"],"claim":"No check to prevent calling startFunding() on an already funded program","impact":"Owner can accidentally start the same program multiple times, causing duplicate funding flows and incorrect token distribution","paths":["Owner accidentally calls startFunding() twice on the same program"]},{"id":"F-006","severity":"High","confidence":"high","title":"Missing Event Emission in FluidLocker.provideLiquidity()","locations":["FluidLocker.sol:420"],"claim":"The provideLiquidity() function has a FIXME comment indicating missing event emission","impact":"No on-chain record of liquidity provision events, making it difficult to track and audit liquidity additions","paths":["N/A - Visibility/audit issue"]},{"id":"F-007","severity":"Medium","confidence":"high","title":"FluidLocker.unstake() Always Disconnects from Pool","locations":["FluidLocker.sol:392"],"claim":"The unstake() function disconnects from the staker pool regardless of whether all tokens are unstaked","impact":"If a user unstakes partially, they lose staking rewards because they're disconnected from the distribution pool while still having staked balance","paths":["User unstakes partially, pool disconnects, remaining staked balance receives no rewards"]},{"id":"F-008","severity":"Medium","confidence":"medium","title":"MacroForwarder.runMacro() is Permissionless","locations":["MacroForwarder.sol:34"],"claim":"The runMacro() function can be called by anyone without access control","impact":"Anyone can execute user-defined macros which may perform arbitrary operations on SuperToken flows, potentially causing unexpected fund movements","paths":["Attacker runs a malicious macro that drains permissions or performs undesired operations"]},{"id":"F-009","severity":"Medium","confidence":"high","title":"Potential Division Rounding in Vesting Flow Rate Calculation","locations":["SupVestingFactory.sol:146"],"claim":"Flow rate calculation uses integer division which truncates remainder, then adds remainder to cliffAmount","impact":"If vesting amount is not evenly divisible by duration, the math may result in slightly incorrect flow rates, and the remainder addition to cliffAmount may cause cliffAmount to exceed total amount","paths":["When amount % duration != 0, precision loss occurs"]},{"id":"F-010","severity":"Medium","confidence":"medium","title":"FluidEPProgramManager - Inconsistent Program Admin Assignment","locations":["FluidEPProgramManager.sol:195"],"claim":"createProgram() requires onlyOwner but programAdmin can be any address, creating confusion about program ownership","impact":"Owner creates program with arbitrary programAdmin, but onlyOwner can update program parameters, creating inconsistent permission model","paths":["Owner creates program with programAdmin = address(0), but onlyOwner can manage it"]},{"id":"F-011","severity":"Low","confidence":"high","title":"Division Precision Loss in Flow Rate Calculations","locations":["FluidEPProgramManager.sol:296-297"],"claim":"Funding and subsidy flow rates are calculated using integer division, losing precision","impact":"Small amounts may be lost due to truncation, causing slight discrepancy between intended and actual flow rates","paths":["When totalAmount is not evenly divisible by programDuration"]},{"id":"F-012","severity":"Low","confidence":"medium","title":"Missing Zero Address Check in FluidLocker.unlock()","locations":["FluidLocker.sol:325"],"claim":"Recipient address(0) check exists but may be insufficient - no check for contract that cannot receive ERC777 tokens","impact":"Unlock may fail silently if recipient is a contract that doesn't implement tokensReceived hook, or tokens could be stuck","paths":["User specifies a non-ERC777 compatible contract as recipient"]},{"id":"F-013","severity":"Low","confidence":"low","title":"Potential Token Approval Front-Running in SupVesting","locations":["SupVesting.sol:97-98"],"claim":"Constructor sets max flow permissions and infinite approval for vestingScheduler","impact":"If the vestingScheduler is upgraded to a malicious contract, it would have infinite approval over the vesting contract's tokens","paths":["VestingScheduler upgraded to malicious implementation"]},{"id":"F-014","severity":"Informational","confidence":"high","title":"StakingRewardController Tax Allocation Not Initialized","locations":["StakingRewardController.sol:178"],"claim":"setTaxAllocation() has no default value - if not called after initialization, tax distribution will use uninitialized values","impact":"Tax distribution may fail or distribute incorrectly if taxAllocation is not set","paths":["Owner forgets to call setTaxAllocation after deployment"]}]

```



## Output
Return a JSON object with:
- `findings`: the COMPLETE updated findings list
- `rejected_candidates`: candidates rejected from this round, with concise reasons

Each `findings` element must have:
- `id`
- `severity`
- `confidence`
- `title`
- `locations`
- `claim`
- `impact`
- `paths`
- `round`
- `source_agents`

Preserve existing IDs for surviving findings whenever possible.
`source_agents` must include every agent that materially supports the final finding.

Each `rejected_candidates` element must have:
- `title`
- `source_agents`
- `reason`

Output ONLY valid JSON. No markdown. No prose.
