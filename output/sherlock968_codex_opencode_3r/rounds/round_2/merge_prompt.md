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
[
  {
    "id": "F-001",
    "severity": "High",
    "confidence": "high",
    "title": "Staked balance can be reused as LP principal while staking units remain active",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:354",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:363",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:420",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:436",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:565",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:688"
    ],
    "claim": "Staking only increases `_stakedBalance` and staker pool units, while `provideLiquidity()` does not check `getAvailableBalance()` before approving and minting with `supAmount`. The Uniswap mint can therefore consume FLUID that is still counted as staked, and `_createPosition()` then grants LP units without reducing staker units.",
    "impact": "A locker owner can use the same FLUID principal to receive both staker and LP tax/reward distributions, diluting honest stakers and liquidity providers and extracting excess emissions. After the rehypothecation, `getAvailableBalance()` can also underflow until the locker receives enough FLUID again because `_stakedBalance` exceeds the actual token balance.",
    "paths": [
      "Lock X FLUID into the locker.",
      "Call `stake(X)`, which increases `_stakedBalance` and updates staker units.",
      "Call `provideLiquidity()` with `supAmount` close to X; the Uniswap position manager pulls the same FLUID from the locker even though it is still counted as staked.",
      "The locker keeps staker units and also receives LP units based on the new liquidity position."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Anyone can stop program funding during the early-end window",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:339",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:349",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:353",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:365",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:380"
    ],
    "claim": "`stopFunding()` is external and has no owner or program-admin restriction. Any account can call it once `block.timestamp >= endDate - EARLY_PROGRAM_END`, causing the manager to delete program details, stop the flow, and distribute the remaining early-end compensation using the current pool units.",
    "impact": "An attacker or advantaged participant can front-run late unit updates in the final three days and force the remaining compensation to be distributed at a favorable snapshot, distorting the final reward allocation and disrupting program operations.",
    "paths": [
      "Wait until a funded program reaches `endDate - 3 days`.",
      "Before expected admin or signer-driven unit updates execute, call `stopFunding(programId)` from any address.",
      "The manager stops the flow and performs the compensation distribution using the pre-update units."
    ],
    "round": 1,
    "source_agents": [
      "codex_1",
      "opencode_1"
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "high",
    "title": "Unit-update signatures are replayable across deployments and chains",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:164",
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:168",
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:296",
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:319"
    ],
    "claim": "The signed unit-update messages are plain `toEthSignedMessageHash(keccak256(abi.encodePacked(...)))` payloads containing user, units, program id(s), and nonce, but no chain id, verifying contract, or other domain separator.",
    "impact": "A valid Stack signer signature for one manager deployment can be reused on another deployment or chain with the same signer, program id, user, and unused nonce, causing unauthorized unit updates and reward claims outside the intended domain.",
    "paths": [
      "Obtain a valid signature for `user`, `newUnits`, `programId`, and `nonce` on manager A.",
      "Submit the same payload and signature to manager B, or to the same deployment on another chain, where the signer and program id match and the nonce has not been consumed.",
      "The signature check passes because the digest does not bind the authorization to a chain or contract address."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "high",
    "title": "Repeated startFunding leaves residual treasury and subsidy streams",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:282",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:299",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:315",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:322",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:370",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:374",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:618",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:643"
    ],
    "claim": "`startFunding()` has no guard against an already funded program. Each call overwrites `_fluidProgramDetails[programId]`, but `_updateFundingFlowRateFromTreasury()` and `_updateSubsidyFlowRate()` add the new deltas to the existing global flows. Later `stopFunding()` or `cancelProgram()` subtract only the latest stored rates.",
    "impact": "A repeated start can leave old funding and subsidy flow components running after the program is supposedly stopped or cancelled, continuously draining the treasury into the manager and/or tax distribution pool and causing accounting insolvency or long-lived leakage.",
    "paths": [
      "Owner starts a program with funding and subsidy rates A.",
      "Before stopping it, owner calls `startFunding()` again for the same `programId` with rates B.",
      "The stored details now contain only B, while the treasury and subsidy flows include A+B.",
      "When the program is stopped or cancelled, the manager subtracts only B, leaving A running."
    ],
    "round": 1,
    "source_agents": [
      "codex_1",
      "opencode_1"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "high",
    "title": "Pumponomics swap has no slippage bound",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:639",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:644",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:650",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:654",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:664"
    ],
    "claim": "`_pump()` executes a Uniswap V3 `exactInputSingle` swap with `amountOutMinimum = 0`. The later liquidity mint slippage check does not bound this swap output because the mint uses the fixed `supAmount` provided by the caller and the remaining WETH balance after the swap.",
    "impact": "MEV searchers can sandwich `provideLiquidity()` transactions and force the 1% pump swap to execute at a manipulated price, extracting value from locker owners and reducing the FLUID received by the locker.",
    "paths": [
      "Attacker observes a `provideLiquidity()` transaction.",
      "Attacker front-runs to move the ETH/FLUID pool price against the locker.",
      "The locker executes `_pump()` with `amountOutMinimum = 0`.",
      "Attacker back-runs to restore the price and captures the spread."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-006",
    "severity": "Low",
    "confidence": "high",
    "title": "Fontaine unlocks can be terminated by any account in the final day",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/Fontaine.sol:145",
      "superfluid-finance/fluid/packages/contracts/src/Fontaine.sol:147",
      "superfluid-finance/fluid/packages/contracts/src/Fontaine.sol:160",
      "superfluid-finance/fluid/packages/contracts/src/Fontaine.sol:167",
      "superfluid-finance/fluid/packages/contracts/src/Fontaine.sol:175"
    ],
    "claim": "`terminateUnlock()` has no caller restriction. Once the unlock reaches `endDate - EARLY_END`, any address can stop the recipient, provider, and staker flows and force the remaining balances to be paid or distributed immediately.",
    "impact": "A third party cannot steal the funds because leftovers go to the recipient and pools, but they can force the final-day payout timing and tax distribution snapshot, potentially front-running expected pool unit changes or altering recipient cash-flow timing.",
    "paths": [
      "Observe a Fontaine whose unlock is within one day of `endDate`.",
      "Call `terminateUnlock()` from any address.",
      "The contract stops all streams and distributes/transfers the remaining balances immediately."
    ],
    "round": 1,
    "source_agents": [
      "codex_1",
      "opencode_1"
    ]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "low",
    "title": "Permissionless EPProgramManager can cache a malicious SuperToken host and GDA",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:81",
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:85",
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:106",
      "superfluid-org/protocol-monorepo/packages/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol:1849",
      "superfluid-org/protocol-monorepo/packages/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol:1853",
      "superfluid-org/protocol-monorepo/packages/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol:1888",
      "superfluid-org/protocol-monorepo/packages/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol:1913"
    ],
    "claim": "The base `EPProgramManager.createProgram()` is permissionless and accepts any `ISuperToken`. `SuperTokenV1Library` caches host and GDA addresses in single contract-wide storage slots the first time a state-changing GDA helper is used, so a malicious first token can cause the manager to cache attacker-controlled framework addresses.",
    "impact": "If the base manager is deployed for real programs, an attacker can poison its cached framework addresses before legitimate use. Subsequent program creation may call the attacker-controlled GDA, fail permanently, or create fake/misdirected pools for honest tokens.",
    "paths": [
      "Deploy a malicious token whose `getHost()` returns an attacker-controlled host and GDA.",
      "Call permissionless `EPProgramManager.createProgram()` before legitimate programs are created.",
      "The library stores the malicious host/GDA in the manager's global cache slots.",
      "Later program creation calls reuse the poisoned cached addresses instead of deriving them from the legitimate token."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-008",
    "severity": "Low",
    "confidence": "medium",
    "title": "Partial unstake disconnects the locker while staker units remain nonzero",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:375",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:386",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:389",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:392",
      "superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:140"
    ],
    "claim": "`unstake()` reduces `_stakedBalance` and updates staker units to the remaining balance, but then unconditionally calls `FLUID.disconnectPool(STAKER_DISTRIBUTION_POOL)`. When a user partially unstakes, the locker can still have nonzero staking units while disconnected from the distribution pool.",
    "impact": "The remaining staked balance may stop receiving real-time staking/tax distributions until the locker owner reconnects, causing reward loss or confusing accounting for users who expected only the unstaked portion to stop earning.",
    "paths": [
      "A locker has X FLUID staked and is connected to the staker distribution pool.",
      "After the cooldown, the owner calls `unstake(Y)` where `0 < Y < X`.",
      "The controller updates units for `X - Y`, but the locker is disconnected from the pool anyway.",
      "The remaining staked balance has units but is not connected for reward streaming."
    ],
    "round": 1,
    "source_agents": [
      "opencode_1"
    ]
  }
]

## This Round's Agent Outputs
### Agent: codex_1
```
[
  {
    "id": "F-009",
    "severity": "High",
    "confidence": "high",
    "title": "Locker hard-caches distribution pool addresses as immutables, enabling permanent unlock/LP DoS from stale setup",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:105",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:228",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:341",
      "superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:194"
    ],
    "claim": "Each locker implementation snapshots `lpDistributionPool()`/`taxDistributionPool()` into immutables in the constructor, while the LP pool is configured later via `setupLPDistributionPool()`. Proxies cannot refresh those addresses, so stale/zero pool pointers remain baked in.",
    "impact": "Affected lockers can permanently fail `unlock()` (for non-max periods) and LP tax distribution paths, causing practical fund lockup/liveness failure for users.",
    "paths": [
      "Deploy locker implementation before LP pool is configured in `StakingRewardController`",
      "Create locker proxy from factory",
      "Call `unlock(..., unlockPeriod < 365 days, ...)` or LP flow paths and hit calls against stale/zero `LP_DISTRIBUTION_POOL`"
    ]
  },
  {
    "id": "F-010",
    "severity": "High",
    "confidence": "medium",
    "title": "Permissionless `createProgram` allows irreversible program-ID squatting",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:81",
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:94"
    ],
    "claim": "`EPProgramManager.createProgram()` has no authorization and permanently occupies `programId` once set (`PROGRAM_ALREADY_CREATED`), with no reclaim/delete mechanism.",
    "impact": "Attackers can front-run expected official program IDs and permanently block intended program deployment/signing flows for those IDs.",
    "paths": [
      "Attacker calls `createProgram(targetProgramId, attackerAdmin, attackerSigner, ...)` first",
      "Legitimate creator later calls `createProgram(targetProgramId, ...)` and reverts with `PROGRAM_ALREADY_CREATED`"
    ]
  },
  {
    "id": "F-011",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Unlock liveness depends on third-party pool participation; zero-unit pools freeze fast exits",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:334",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:337",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:341"
    ],
    "claim": "`unlock()` requires both tax pools to have nonzero total units for any `unlockPeriod < 365 days` (including instant unlock), so if either pool reaches zero units the function reverts.",
    "impact": "Users can lose access to instant/short unlocks and be forced into only max-duration unlocks, creating protocol-level withdrawal liveness risk.",
    "paths": [
      "Staker and/or LP pool total units drop to zero (bootstrap period or last participant exits)",
      "Victim calls `unlock(amount, 0 or short period, recipient)`",
      "Transaction reverts on pool unit checks"
    ]
  },
  {
    "id": "F-012",
    "severity": "Medium",
    "confidence": "low",
    "title": "Program `totalAmount` cap is not enforced on-chain after end date",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:282",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:315",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:339"
    ],
    "claim": "`startFunding()` sets continuous flows from `totalAmount/duration`, but no automatic end-date stop exists; flows continue until someone explicitly calls `stopFunding()`.",
    "impact": "If stop is delayed/missed, treasury and subsidy streams continue beyond planned budget, causing over-distribution and potential treasury drain.",
    "paths": [
      "Owner starts funding with planned duration",
      "No stop call is made at/near end date",
      "Incoming and outgoing flows continue accumulating extra payout until eventual manual stop"
    ]
  },
  {
    "id": "F-013",
    "severity": "Low",
    "confidence": "low",
    "title": "Unchecked uint256→uint128 downcasts can silently corrupt unit accounting",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:263",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:411",
      "superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:141",
      "superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:148"
    ],
    "claim": "Multiple reward-unit writes cast 256-bit values directly to `uint128` without bounds checks, truncating high values.",
    "impact": "Oversized inputs from signer/locker-side bugs can produce unintended unit values on-chain, skewing reward distribution and creating accounting inconsistencies.",
    "paths": [
      "Oversized `stackPoints` or locker balances exceed `type(uint128).max`",
      "Contract casts to `uint128` during unit updates",
      "Truncated units are written to pools"
    ]
  }
]

```

### Agent: opencode_1
```
Now I'll analyze each contract for NEW vulnerabilities not already identified in the prior rounds. Let me identify new issues:
Let me check some specific vulnerability patterns:
Now let me examine specific vulnerability patterns I've identified for NEW issues:
Let me check a specific vulnerability pattern I identified:
Now I'll compile my findings into the required JSON format:
```json
[
  {
    "id": "F-009",
    "severity": "Medium",
    "confidence": "high",
    "title": "Permissionless distributeTaxAdjustment allows front-running and untracked execution",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:208"
    ],
    "claim": "The distributeTaxAdjustment() function is permissionless, allowing anyone to trigger tax distribution to staker and LP pools without authorization",
    "impact": "Any user can front-run pending distribution transactions to capture MEV opportunities or force distribution timing. Additionally, if called before taxAllocation is initialized, it uses uninitialized zero values causing division by zero or funds trapped in single pool",
    "paths": [
      "Any account calls distributeTaxAdjustment() -> tax allocation uses default zero values if uninitialized -> funds distribute incorrectly or fail"
    ]
  },
  {
    "id": "F-010",
    "severity": "Medium",
    "confidence": "high",
    "title": "Vesting cliffAmount equals totalAmount traps all tokens in contract",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/vesting/SupVestingFactory.sol:136"
    ],
    "claim": "The validation cliffAmount >= amount allows cliffAmount == amount, creating invalid vesting with zero flowRate and all tokens locked in contract",
    "impact": "If cliffAmount equals amount (edge case), the calculated vestingDuration is zero and flowRate becomes zero, causing all tokens to remain locked in the SupVesting contract with no path to release",
    "paths": [
      "Admin creates vesting with cliffAmount == amount -> vestingDuration = 0 -> flowRate = 0 -> tokens trapped in contract permanently"
    ]
  },
  {
    "id": "F-011",
    "severity": "High",
    "confidence": "medium",
    "title": "Missing event emission prevents liquidity provision tracking",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:443"
    ],
    "claim": "The provideLiquidity function has a FIXME comment indicating no event is emitted after adding liquidity",
    "impact": "External systems andindexers cannot track liquidity provision events, breaking transparency and making it impossible to reconstruct state from on-chain data alone",
    "paths": [
      "Locker calls provideLiquidity() -> No event emitted -> Off-chain systems cannot track liquidity positions"
    ]
  },
  {
    "id": "F-012",
    "severity": "High",
    "confidence": "high",
    "title": "Owner can drain program funds via emergencyWithdraw without accounting",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:481"
    ],
    "claim": "The emergencyWithdraw function allows owner to transfer any token balance to treasury without tracking which funds belong to active programs vs operational reserves",
    "impact": "Owner can inadvertently or maliciously drain funds allocated for active funding programs. No distinction between program deposits and operational funds, causing program failure when funds are withdrawn mid-stream",
    "paths": [
      "Program starts funding -> Owner calls emergencyWithdraw -> All tokens including program deposits transferred out -> Program streams fail"
    ]
  },
  {
    "id": "F-013",
    "severity": "High",
    "confidence": "medium",
    "title": "Vesting emergencyWithdraw can steal recipient vested tokens",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/vesting/SupVesting.sol:120"
    ],
    "claim": "The emergencyWithdraw function closes the vesting flow and transfers ALL remaining balance to treasury, including tokens already committed to recipient",
    "impact": "Admin can trigger emergencyWithdraw at any time to steal tokens that were already flowing to the recipient, violating vesting contract guarantees. Recipient loses all unvested tokens",
    "paths": [
      "Recipient receives vesting -> Admin calls emergencyWithdraw -> Flow stopped -> All remaining balance transferred to treasury instead of recipient"
    ]
  },
  {
    "id": "F-014",
    "severity": "Low",
    "confidence": "medium",
    "title": "lpDistributionPool not validated before distributeTaxAdjustment",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:208"
    ],
    "claim": "The distributeTaxAdjustment function does not check if lpDistributionPool is initialized before calling distribute()",
    "impact": "If lpDistributionPool is address(0) (not yet set via setupLPDistributionPool), the distribute() call will fail or send tokens to address(0), causing distribution failure",
    "paths": [
      "setupLPDistributionPool not called -> lpDistributionPool = address(0) -> distributeTaxAdjustment fails silently or loses funds"
    ]
  },
  {
    "id": "F-015",
    "severity": "Medium",
    "confidence": "low",
    "title": "Liquidity removal lacks slippage protection in withdrawal path",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:702"
    ],
    "claim": "The _decreasePosition function uses slippage calculations but actual withdrawal path during collection may receive less due to Uniswap v3 fee accrual timing",
    "impact": "During periods of high fee accrual or volatile pools, collected fees may differ from calculated minimums due to execution timing, potentially causing loss to locker owner",
    "paths": [
      "User withdraws liquidity -> Pool volatility -> Actual collect less than amount0Min/amount1Min -> User loses value"
    ]
  }
]
```

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
