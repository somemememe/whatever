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
      "codex_1",
      "opencode_1"
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
  },
  {
    "id": "F-009",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Locker and Fontaine implementations snapshot pool addresses before setup can complete",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:102",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:105",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:228",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:229",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:337",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:341",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:593",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:682",
      "superfluid-finance/fluid/packages/contracts/src/Fontaine.sol:104",
      "superfluid-finance/fluid/packages/contracts/src/Fontaine.sol:110",
      "superfluid-finance/fluid/packages/contracts/src/Fontaine.sol:111",
      "superfluid-finance/fluid/packages/contracts/src/Fontaine.sol:137",
      "superfluid-finance/fluid/packages/contracts/src/Fontaine.sol:138",
      "superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:130",
      "superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:194"
    ],
    "claim": "`FluidLocker` stores `STAKER_DISTRIBUTION_POOL` and `LP_DISTRIBUTION_POOL` as implementation immutables by reading the controller during the constructor, and `Fontaine` similarly stores pool addresses as immutables. The staker pool is created during controller initialization and the LP pool is created later by `setupLPDistributionPool()`, so implementations deployed before those steps complete can bake zero or stale pool addresses into the code used by all proxies for that beacon implementation.",
    "impact": "Lockers using a stale implementation can have instant/short unlocks, penalty distributions, LP pool connection, and Fontaine flow setup revert against zero or stale pools. Users may be unable to use fast exits or liquidity features until governance replaces the beacon implementation, and already-created lockers inherit the bad implementation state while the beacon points to it.",
    "paths": [
      "Deploy the locker or Fontaine implementation before the controller proxy has initialized the tax pool or before `setupLPDistributionPool()` creates the LP pool.",
      "Create locker proxies through the factory or unlock through a Fontaine beacon that points to the stale implementation.",
      "Call `unlock()` with `unlockPeriod < 365 days`, `provideLiquidity()`, or initialize a Fontaine that needs provider/staker flow distribution.",
      "The operation uses the implementation's baked pool address instead of the controller's current pool and reverts or routes through a stale pool."
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-010",
    "severity": "Medium",
    "confidence": "low",
    "title": "Permissionless base program manager allows irreversible program ID squatting",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:81",
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:94",
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:108"
    ],
    "claim": "The base `EPProgramManager.createProgram()` is permissionless and permanently occupies a `programId` once `programs[programId].distributionPool` is set. Unlike `FluidEPProgramManager`, the base manager has no owner gate and no reclaim or delete path for a squatted ID.",
    "impact": "If the base manager is deployed for production programs, attackers can front-run known or predictable program IDs and force legitimate programs to change identifiers or fail to deploy under the expected off-chain signing/program configuration, causing a persistent program-level DoS.",
    "paths": [
      "Attacker observes or guesses an intended `programId` for a base `EPProgramManager` deployment.",
      "Attacker calls `createProgram(targetProgramId, attackerAdmin, attackerSigner, attackerToken, ...)` first.",
      "The target ID now has a distribution pool recorded.",
      "The legitimate creator's later `createProgram(targetProgramId, ...)` reverts with `PROGRAM_ALREADY_CREATED()`."
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-011",
    "severity": "Medium",
    "confidence": "high",
    "title": "Zero-unit tax pools freeze instant and short unlocks",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:334",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:337",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:341"
    ],
    "claim": "`unlock()` requires both the staker and LP tax distribution pools to have nonzero total units whenever `unlockPeriod < 365 days`, including instant unlocks. If either pool has zero units during bootstrap or after the last participant exits, all fast unlock paths revert before any tax distribution is attempted.",
    "impact": "Locker owners can be forced out of instant or short-duration exits even when they have sufficient available FLUID. During periods with no staker or LP units, the only remaining unlock route is the maximum-duration path, materially degrading withdrawal liveness and user access to funds.",
    "paths": [
      "The staker pool or LP pool has zero total units, such as before the first participant joins or after the last participant removes units.",
      "A locker owner with available FLUID calls `unlock(amount, 0, recipient)` or any valid short unlock period below 365 days.",
      "`unlock()` checks `getTotalUnits()` on both tax pools and reverts when either is zero.",
      "The user cannot perform the requested fast unlock until third-party pool units are restored."
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-012",
    "severity": "Low",
    "confidence": "medium",
    "title": "Permissionless tax adjustment distribution can force an unfavorable reward snapshot",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:178",
      "superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:185",
      "superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:208",
      "superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:209",
      "superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:216",
      "superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:221",
      "superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:222"
    ],
    "claim": "`distributeTaxAdjustment()` is external and permissionless, and distributes the controller's entire FLUID balance using the currently stored tax allocation and current pool units. There is no admin-controlled epoch, snapshot, or initialization guard; after the LP pool exists but before `setTaxAllocation()` is called, the default allocation sends the full adjustment to the staker pool.",
    "impact": "When the controller holds adjustment funds, any account can force distribution before expected tax-allocation or unit updates, causing the adjustment to be allocated to an unintended pool split or participant snapshot. This can misallocate tax adjustment funds, although the issue depends on the controller actually holding such a balance.",
    "paths": [
      "The controller receives or accumulates FLUID intended for a later tax adjustment distribution.",
      "Before an expected `setTaxAllocation()` call or pool-unit update, an advantaged account calls `distributeTaxAdjustment()`.",
      "The function reads the current balance, current `taxAllocation`, and current pool units.",
      "The full balance is distributed immediately to that snapshot, potentially giving all funds to stakers if allocation was still unset."
    ],
    "round": 2,
    "source_agents": [
      "opencode_1"
    ]
  },
  {
    "id": "F-013",
    "severity": "High",
    "confidence": "high",
    "title": "Funding streams are not automatically terminated at program end",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:282",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:296",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:297",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:303",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:315",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:318",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:322",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:339"
    ],
    "claim": "`startFunding()` derives the funding and subsidy flow rates from `totalAmount / programDuration`, stores the intended duration, and starts continuous Superfluid streams from the treasury and to the program/tax pools. No cumulative amount cap or automatic end condition is enforced; the streams are only stopped by a later `stopFunding()` or `cancelProgram()` call.",
    "impact": "If the stop transaction is missed, delayed, or no party is incentivized to submit it, rewards continue beyond the intended end date and budget. The treasury flow can keep funding over-distributions indefinitely until someone stops the program or the treasury becomes insolvent.",
    "paths": [
      "The owner calls `startFunding(programId, totalAmount, duration)` for a valid program.",
      "`startFunding()` starts the treasury-to-manager flow and the manager-to-pool/subsidy flows at rates derived from the intended duration.",
      "The timestamp passes `fundingStartDate + duration` without a successful `stopFunding()` or `cancelProgram()` transaction.",
      "The Superfluid flows continue at the same rates past the intended end date, distributing more than `totalAmount` and draining the treasury."
    ],
    "round": 3,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-014",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Requested subsidy rates can undercut the shared subsidy stream for active programs",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:299",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:322",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:370",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:643",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:648",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:651",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:654",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:658",
      "superfluid-org/protocol-monorepo/packages/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol:1495",
      "superfluid-org/protocol-monorepo/packages/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol:1500",
      "superfluid-org/protocol-monorepo/packages/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol:1547",
      "superfluid-org/protocol-monorepo/packages/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol:1551",
      "superfluid-org/protocol-monorepo/packages/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol:1721"
    ],
    "claim": "`startFunding()` stores each program's configured `subsidyFlowRate`, but `SuperTokenV1Library.distributeFlow()` may set an actual flow rate lower than the requested value depending on pool state. `_updateSubsidyFlowRate()` later reads the current actual shared subsidy flow, adds a requested per-program delta, and clamps negative results to zero. Stopping or cancelling one program can therefore subtract more than that program actually contributed to the shared subsidy stream.",
    "impact": "With concurrent subsidized programs, terminating one program can reduce or zero the subsidy flow owed to still-active programs. Stakers and LPs can lose expected subsidy rewards, and the manager's treasury-flow accounting can diverge from the real GDA subsidy stream.",
    "paths": [
      "Start one or more subsidized programs while the tax distribution pool state causes actual GDA subsidy flow to be lower than the requested rate.",
      "Each program stores the requested subsidy rate in `_fluidProgramDetails`, while the shared GDA flow is only the actual rate returned by the agreement.",
      "Call `stopFunding()` or `cancelProgram()` for one program.",
      "`_updateSubsidyFlowRate()` subtracts that program's requested rate from the lower current actual shared rate and may set the shared subsidy stream too low or to zero for remaining programs."
    ],
    "round": 4,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-016",
    "severity": "Medium",
    "confidence": "low",
    "title": "Non-FLUID program tokens can create unfundable or unwithdrawable locker rewards",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:195",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:199",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:220",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:318",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:322",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:385",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:643",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:655",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:258",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:263",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:265",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:267",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:277",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:285",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:287",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:289",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:300",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:302",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:585",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:600",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:616"
    ],
    "claim": "`FluidEPProgramManager.createProgram()` accepts any `ISuperToken` and creates the program pool for that token, but the surrounding Fluid system is hardwired to FLUID pools and FLUID locker exits. Subsidy flows for arbitrary program tokens are sent to the immutable FLUID tax distribution pool, and lockers connect to program pools through the immutable `FLUID` token while exposing only FLUID lock, unlock, and liquidity withdrawal paths.",
    "impact": "If the owner creates or funds a program with a non-FLUID token, funding can revert or misbehave when subsidy distribution targets the FLUID tax pool. If non-FLUID rewards do accrue to lockers, locker owners have no generic token withdrawal path to extract them, causing funded rewards to become stuck in the locker contract.",
    "paths": [
      "The owner calls `createProgram()` with `token != FLUID`, which is accepted and creates a non-FLUID program pool.",
      "If the subsidy rate is nonzero, `startFunding()` calls `_updateSubsidyFlowRate(program.token, ...)` against the FLUID tax distribution pool, making funding incompatible with the non-FLUID token/pool pairing.",
      "If rewards are streamed to lockers, `claim()` and `connectToPool()` use `FLUID.connectPool(programPool)` and the locker has only FLUID-specific exit paths.",
      "Non-FLUID balances received by the locker cannot be unlocked or otherwise withdrawn by the locker owner."
    ],
    "round": 4,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-017",
    "severity": "Medium",
    "confidence": "low",
    "title": "Treasury flow underflow clamp can stop funding for unrelated active programs after flow drift",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:365",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:374",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:618",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:623",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:633"
    ],
    "claim": "`_updateFundingFlowRateFromTreasury()` subtracts a stopped or cancelled program's stored funding delta from the current treasury-to-manager flow, and if the result is negative it calls `token.flowFrom(fluidTreasury, address(this), 0)`. If the actual current treasury flow has drifted below the contract's stored per-program accounting, stopping one program can zero the shared treasury inflow instead of preserving the portion needed by other active programs.",
    "impact": "After treasury-side flow drift, insolvency handling, or manual intervention, any allowed stop/cancel of one program can interrupt funding for unrelated active programs. Rewards can become unfunded even though the remaining programs still have stored active funding details.",
    "paths": [
      "Multiple programs are active and share the same treasury-to-manager flow.",
      "The actual treasury flow becomes lower than the sum of stored program rates, such as after treasury-side adjustment or stream disruption.",
      "A program whose stored rate exceeds the current actual flow is stopped or cancelled.",
      "`_updateFundingFlowRateFromTreasury()` computes a negative result and sets the global treasury flow to zero, cutting off remaining active programs."
    ],
    "round": 5,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-018",
    "severity": "Low",
    "confidence": "high",
    "title": "Minimum unlock amount can strand sub-10 SUP locker balances",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:156",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:308",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:320"
    ],
    "claim": "`FluidLocker.unlock()` reverts whenever `unlockAmount < MIN_UNLOCK_AMOUNT`, where `MIN_UNLOCK_AMOUNT` is hardcoded to 10 ether. The locker exposes no general FLUID withdrawal path that bypasses this threshold.",
    "impact": "Residual FLUID, small rewards, or user deposits below 10 SUP can remain unusable until the locker receives enough additional FLUID to meet the threshold. This can create dust lockups and force users to top up solely to recover small balances.",
    "paths": [
      "A locker's available FLUID balance is greater than zero but below 10 SUP.",
      "The locker owner calls `unlock(availableBalance, ...)`.",
      "The call reverts with `INSUFFICIENT_UNLOCK_AMOUNT`.",
      "The balance cannot be withdrawn through the normal unlock path unless the user tops the locker up above the minimum."
    ],
    "round": 5,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-019",
    "severity": "Medium",
    "confidence": "high",
    "title": "Liquidity withdrawal applies an extra 5% haircut to caller-provided minimums",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:447",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:465",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:702",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:710",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:712",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:788",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:795"
    ],
    "claim": "`withdrawLiquidity()` forwards caller-supplied removal amounts into `_decreasePosition()`, whose comments describe them as minimum amounts, but `_decreasePosition()` passes them through `_calculateMinAmounts()` and reduces each by the hardcoded `BP_SLIPPAGE_TOLERANCE` of 5% before calling Uniswap `decreaseLiquidity`. Users therefore cannot enforce the exact minima they supplied.",
    "impact": "Withdrawals can execute with up to an additional 5% worse token output than the locker owner intended. MEV searchers or volatile price movement can exploit the widened tolerance to extract value during liquidity removal.",
    "paths": [
      "A locker owner computes acceptable minimum SUP and paired-asset outputs and submits them to `withdrawLiquidity()`.",
      "The contract treats those values as inputs to `_calculateMinAmounts()` instead of final Uniswap minima.",
      "The effective `amount0Min` and `amount1Min` sent to Uniswap are 95% of the user's values.",
      "An adversary moves the pool price within the widened tolerance and the withdrawal succeeds at worse output than the caller requested."
    ],
    "round": 5,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-020",
    "severity": "Low",
    "confidence": "high",
    "title": "Factory ETH fees can become stuck when governor is a contract receiver",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidLockerFactory.sol:151",
      "superfluid-finance/fluid/packages/contracts/src/FluidLockerFactory.sol:152"
    ],
    "claim": "`FluidLockerFactory.withdrawETH()` sends all collected ETH fees to `governor` using Solidity `transfer`, which forwards only the 2300 gas stipend and reverts for many contract-based governor receivers.",
    "impact": "If governance is migrated to a contract wallet or module whose receive path needs more than 2300 gas, locker creation fees accumulated in the factory can become non-withdrawable until governance upgrades or changes the implementation.",
    "paths": [
      "The factory accumulates ETH locker-creation fees.",
      "`governor` is set to a contract account with a non-trivial or reverting receive/fallback function.",
      "The governor calls `withdrawETH()`.",
      "The `transfer` reverts and the ETH remains locked in the factory."
    ],
    "round": 5,
    "source_agents": [
      "codex_1"
    ]
  }
]

## This Round's Agent Outputs
### Agent: codex_1
```
[
  {
    "id": "F-021",
    "severity": "Medium",
    "confidence": "low",
    "title": "Batch unit signatures are hash-ambiguous because dynamic array lengths are not committed",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:206",
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:319"
    ],
    "claim": "The batch signature hash uses `abi.encodePacked(user, newUnits, programIds, nonce)` with two dynamic arrays, so array boundaries are not encoded. If a signer ever signs a non-canonical payload shape, another `(newUnits, programIds)` pair can hash to the same message and pass signature verification.",
    "impact": "A valid signature can be repurposed to apply unintended unit updates across programs, causing reward misallocation.",
    "paths": [
      "Obtain a valid stack signature for one packed byte layout of `(user, newUnits, programIds, nonce)`.",
      "Construct an alternate `(newUnits, programIds)` pair with the same packed bytes but different semantic mapping.",
      "Call `batchUpdateUserUnits` with the alternate arrays; signature check passes and unintended unit updates execute."
    ]
  },
  {
    "id": "F-022",
    "severity": "Medium",
    "confidence": "low",
    "title": "Permissionless signature execution enables nonce-burning frontruns and forced reward snapshot timing",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:151",
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:168",
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:184",
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:225",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:258",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:277"
    ],
    "claim": "`updateUserUnits` and `batchUpdateUserUnits` are public and signatures are not bound to caller identity; once a signature is seen, any third party can execute it first and consume the nonce for that user/program set.",
    "impact": "Attackers can frontrun user claims to force stale or unfavorable unit snapshots and make the victim’s intended transaction revert on nonce checks, creating reward-timing manipulation and repeated gas grief.",
    "paths": [
      "Victim broadcasts a claim/update transaction containing a valid signature and nonce.",
      "Attacker copies calldata and sends the same signed update first.",
      "Manager stores the nonce as used; victim transaction reverts with invalid nonce."
    ]
  },
  {
    "id": "F-023",
    "severity": "Low",
    "confidence": "low",
    "title": "Vesting factory does not validate recipient address, allowing zero-address vesting creation",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/vesting/SupVestingFactory.sol:128",
      "superfluid-finance/fluid/packages/contracts/src/vesting/SupVestingFactory.sol:153",
      "superfluid-finance/fluid/packages/contracts/src/vesting/SupVestingFactory.sol:159"
    ],
    "claim": "`createSupVestingContract` does not reject `recipient == address(0)` before deploying and funding a vesting instance.",
    "impact": "A misconfigured or compromised admin can create and fund a vesting that may stream or release tokens to the zero address, resulting in token loss.",
    "paths": [
      "Admin calls `createSupVestingContract(address(0), amount, cliffAmount, cliffDate, endDate)`.",
      "Factory deploys vesting and transfers `amount` from treasury to it.",
      "Funds are scheduled for an invalid recipient path and can be effectively burned."
    ]
  }
]

```

### Agent: opencode_1
```
Based on my analysis of all the in-scope contracts, I've identified several security vulnerabilities that are not already listed in the known findings. Let me compile the JSON array:
Let me analyze the contracts more deeply to identify NEW security vulnerabilities beyond the known findings (F-001 to F-020).
Based on my analysis of the contracts, I have identified several new security vulnerabilities beyond the previously known findings. Let me compile the JSON array:
[{"id": "F-021", "severity": "Low", "confidence": "high", "title": "Missing event emission in provideLiquidity", "locations": ["superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:443"], "claim": "The provideLiquidity function has a FIXME comment indicating event emission is missing, making it difficult to track liquidity provision events on-chain.", "impact": "Off-chain systems and users cannot easily track when liquidity is provided, reducing transparency and making debugging more difficult.", "paths": []}, {"id": "F-022", "severity": "Low", "confidence": "medium", "title": "Permissionless distributeTaxAdjustment can front-run reward distribution", "locations": ["superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:208"], "claim": "The distributeTaxAdjustment function can be called by anyone, allowing front-running of the tax distribution by MEV searchers who can capture arbitrage opportunities.", "impact": "Attackers can sandwich the distribution call to extract value, reducing intended rewards to stakers and liquidity providers.", "paths": ["1. Attacker monitors mempool for distributeTaxAdjustment call", "2. Attacker front-runs with flash loan to capture value", "3. Distribution happens at worse rate", "4. Attacker back-runs to finalize"]}, {"id": "F-023", "severity": "Medium", "confidence": "high", "title": "No Access Control on MacroForwarder.runMacro", "locations": ["superfluid-org/protocol-monorepo/packages/ethereum-contracts/contracts/utils/MacroForwarder.sol:34"], "claim": "The runMacro function can be called by any external account to execute batch operations through user-defined macros without proper access controls.", "impact": "If a malicious or poorly designed macro is used, attackers can execute arbitrary operations on behalf of the forwarder, potentially draining funds or manipulating state.", "paths": ["1. Attacker calls runMacro with malicious macro contract", "2. Macro executes batch operations with forwarded value", "3. Funds may be stolen or state manipulated"]}, {"id": "F-024", "severity": "Medium", "confidence": "medium", "title": "Vesting emergencyWithdraw can steal unvested tokens", "locations": ["superfluid-finance/fluid/packages/contracts/src/vesting/SupVesting.sol:120"], "claim": "The emergencyWithdraw function transfers ALL remaining balance including cliff amounts and vested tokens to treasury, not just unvested amounts.", "impact": "In case of emergency, the admin can permanently steal all remaining tokens from the vesting contract, including tokens already earned by recipients.", "paths": ["1. Admin calls emergencyWithdraw", "2. All remaining tokens transferred to treasury", "3. Recipients lose vested amounts"]}, {"id": "F-025", "severity": "Low", "confidence": "low", "title": "No validation of lpDistributionPool setupLPDistributionPool timing", "locations": ["superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:194"], "claim": "setupLPDistributionPool can only be called once but there is no protection against calling it before initialization is complete or before the contract has sufficient funds.", "impact": "If called prematurely, the LP distribution pool may be set up without proper configuration, leading to incorrect reward distributions.", "paths": []}, {"id": "F-026", "severity": "Low", "confidence": "high", "title": "Inconsistent access control patterns across contracts", "locations": ["superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:448", "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:459", "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:470"], "claim": "setLockerFactory, setTreasury, and setSubsidyRate functions lack zero-address validation and don't emit events for changes.", "impact": "Misconfiguration can lead to irrecoverable state, and lack of events reduces traceability.", "paths": []}, {"id": "F-027", "severity": "Medium", "confidence": "medium", "title": "Unlock period validation allows instant unlock bypass", "locations": ["superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:346"], "claim": "When unlockPeriod is 0, _instantUnlock is called which applies an 80% penalty (8000 BP), but users can unlock any amount without time lock.", "impact": "Users may bypass the vesting mechanism by choosing period 0, receiving instant liquidity at high cost that may not align with protocol economics.", "paths": ["1. User calls unlock with unlockPeriod=0", "2. 80% penalty applied", "3. User gets immediate access to funds"]}, {"id": "F-028", "severity": "Low", "confidence": "medium", "title": "No deadline validation in provideLiquidity", "locations": ["superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:420"], "claim": "The provideLiquidity function uses LP_OPERATION_DEADLINE for position creation but the deadline is always block.timestamp + 1 minute, not user-controlled.", "impact": "Users cannot set their own deadline, potentially leading to unfavorable execution if the transaction is delayed.", "paths": []}, {"id": "F-029", "severity": "Low", "confidence": "low", "title": "Tax allocation can be set to zero values", "locations": ["superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:178"], "claim": "setTaxAllocation validates sum equals 10000 BP but allows either allocation to be zero, effectively directing all tax to one pool.", "impact": "All tax can be directed to stakers or liquidity providers only, potentially causing unintended economic effects.", "paths": ["1. Owner calls setTaxAllocation with 10000 staker allocation", "2. All tax goes to stakers", "3. LP providers receive no rewards"]}, {"id": "F-030", "severity": "Low", "confidence": "low", "title": "Factory can create vestings for any recipient without recipient consent", "locations": ["superfluid-finance/fluid/packages/contracts/src/vesting/SupVestingFactory.sol:128"], "claim": "The createSupVestingContract function allows admin to create vesting contracts for any address without that address's consent or knowledge.", "impact": "Recipients may not be aware they have a vesting contract, and tokens can be sent to addresses that cannot claim them.", "paths": ["1. Admin calls createSupVestingContract for random address", "2. Tokens locked in vesting contract", "3. Recipient unaware, cannot access"]}]

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
