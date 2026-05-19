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
  }
]

## This Round's Agent Outputs
### Agent: codex_1
```
[
  {
    "id": "F-013",
    "severity": "High",
    "confidence": "high",
    "title": "Funding streams are not auto-terminated at program end, so rewards can run indefinitely",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:282",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:315",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:318",
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:339"
    ],
    "claim": "`startFunding` derives a flow rate from `totalAmount/duration` but does not enforce a cumulative cap or auto-stop at `endDate`; flows only stop if someone later calls `stopFunding`/`cancelProgram`.",
    "impact": "If stop is delayed or missed, treasury-funded streams continue past the intended budget window, causing unbounded over-distribution and treasury drain.",
    "paths": [
      "Owner calls `startFunding(programId, totalAmount, duration)`",
      "Program passes `fundingStartDate + duration`",
      "No `stopFunding` transaction is executed, so CFA/GDA flows continue indefinitely"
    ]
  },
  {
    "id": "F-014",
    "severity": "High",
    "confidence": "medium",
    "title": "Proxy ownership can be seized via public initializers if deployment is not atomic",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:179",
      "superfluid-finance/fluid/packages/contracts/src/FluidLockerFactory.sol:107",
      "superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:121"
    ],
    "claim": "Core upgradeable contracts expose unrestricted `initialize(...)` entrypoints; first caller sets privileged roles (owner/governor) if a proxy is left uninitialized.",
    "impact": "A frontrunner can seize admin rights, then upgrade logic or execute privileged fund-moving controls (e.g., emergency withdrawals), resulting in full protocol compromise.",
    "paths": [
      "Proxy is deployed without init calldata",
      "Attacker calls `initialize(...)` first",
      "Attacker invokes privileged functions like `upgradeTo(...)` / treasury-control paths"
    ]
  },
  {
    "id": "F-015",
    "severity": "Low",
    "confidence": "low",
    "title": "Third parties can force locker claims and consume signed nonces for users",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:258",
      "superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:277",
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:151",
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:165",
      "superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol:168"
    ],
    "claim": "`claim(...)` is permissionless on lockers, and program-manager updates are signature-authorized but not caller-bound, so any party with a valid signature can execute and consume that nonce.",
    "impact": "If signatures leak offchain, attackers can submit them first, forcing undesired unit snapshots and invalidating the owner’s pending nonce sequence.",
    "paths": [
      "Attacker obtains a valid Stack signature for victim user + nonce",
      "Attacker calls victim locker `claim(...)`",
      "Program manager updates units and advances nonce before victim acts"
    ]
  },
  {
    "id": "F-016",
    "severity": "Low",
    "confidence": "high",
    "title": "Vesting creation allows zero-address recipient, enabling irreversible token burn",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/vesting/SupVestingFactory.sol:128",
      "superfluid-finance/fluid/packages/contracts/src/vesting/SupVestingFactory.sol:139",
      "superfluid-finance/fluid/packages/contracts/src/vesting/SupVestingFactory.sol:153",
      "superfluid-finance/fluid/packages/contracts/src/vesting/SupVestingFactory.sol:159"
    ],
    "claim": "`createSupVestingContract` does not reject `recipient == address(0)` before deploying vesting and transferring treasury tokens.",
    "impact": "A mistaken admin call can permanently burn an allocation by streaming/cliffing funds toward the zero address.",
    "paths": [
      "Admin calls `createSupVestingContract(address(0), amount, ...)`",
      "Factory deploys vesting and transfers `amount` from treasury",
      "Scheduled payouts target zero address, making funds unrecoverable"
    ]
  },
  {
    "id": "F-017",
    "severity": "Low",
    "confidence": "high",
    "title": "Factory ETH withdrawals can be DoSed by gas-stipend-limited `transfer`",
    "locations": [
      "superfluid-finance/fluid/packages/contracts/src/FluidLockerFactory.sol:151",
      "superfluid-finance/fluid/packages/contracts/src/FluidLockerFactory.sol:152"
    ],
    "claim": "`withdrawETH` uses Solidity `transfer`, which forwards only 2300 gas to the governor.",
    "impact": "If governor is (or becomes) a contract wallet requiring more gas on receive, fee ETH can become non-withdrawable.",
    "paths": [
      "Governor is a smart contract without a 2300-gas-compatible receive path",
      "`withdrawETH()` reverts on every call",
      "Factory ETH balance remains stuck"
    ]
  }
]

```

### Agent: opencode_1
```
Based on my thorough analysis of all contracts in scope, here are the new security vulnerabilities I've identified that are NOT already in the known findings list (F-001 through F-012):
[{"id": "F-013", "severity": "Critical", "confidence": "high", "title": "Pumponomics swap has zero minimum output protection", "locations": ["superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:639-655"], "claim": "The _pump function performs a Uniswap V3 exactInputSingle swap with amountOutMinimum set to 0, providing no protection against price impact or adverse slippage during the swap execution.", "impact": "When providing liquidity, the ETH/SUP swap (Pumponomics) can execute at any rate, including near-zero output, leading to significant token loss for the protocol. The comment claims slippage is covered by _createPosition but that's for position creation, not the swap itself.", "paths": ["1. User calls provideLiquidity(supAmount)", "2. Locker swaps ETH for SUP via _pump with amountOutMinimum=0", "3. Adversary manipulates pool price or uses MEV", "4. User receives near-zero SUP tokens"]}, {"id": "F-014", "severity": "High", "confidence": "medium", "title": "Permissionless stopFunding allows griefing of legitimate programs", "locations": ["superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:339-389"], "claim": "The stopFunding function has no access control modifier, allowing anyone to stop a program's funding during the early-end window.", "impact": "An attacker can grief legitimate programs by calling stopFunding at any time after EARLY_PROGRAM_END, causing premature termination and disrupting distributions to lockers. While the program admin can restart, this creates a persistent griefing surface.", "paths": ["1. Legitimate program is funded and flowing", "2. Attacker calls stopFunding(programId) during early-end window", "3. Program flows are terminated prematurely", "4. Distribution to lockers is disrupted"]}, {"id": "F-015", "severity": "Medium", "confidence": "high", "title": "Instant unlock penalty distribution can be griefed via front-running", "locations": ["superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:585-603"], "claim": "The _instantUnlock function distributes penalty amounts via FLUID.distribute() which is susceptible to front-running when the distribution pool has existing units.", "impact": "An attacker can front-run instant unlocks by depositing small amounts to trigger pool unit changes, affecting the distribution calculation. While the actual distribution may not be loss-making, the timing and allocation can be manipulated.", "paths": ["1. User calls unlock with unlockPeriod=0", "2. Attacker observes mempool", "3. Attacker front-runs with pool unit update", "4. Distribution allocation is manipulated"]}, {"id": "F-016", "severity": "Medium", "confidence": "medium", "title": "No event emission on provideLiquidity creates observability gap", "locations": ["superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol:419-444"], "claim": "The provideLiquidity function has a FIXME comment indicating missing event emission (line 443: '/// FIXME : add event emit here').", "impact": "Off-chain systems and Indexer protocols cannot track liquidity provision events, creating a observability gap that hinders protocol monitoring and user experience.", "paths": ["1. User calls provideLiquidity", "2. Position is created with activePositionCount incremented", "3. No event is emitted for external tracking"]}, {"id": "F-017", "severity": "Medium", "confidence": "medium", "title": "Permissionless distributeTaxAdjustment enables timing manipulation", "locations": ["superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol:208-223"], "claim": "The distributeTaxAdjustment function has no access control, allowing anyone to trigger distribution of the controller's token balance.", "impact": "Although distribution is the intended behavior, the permissionless nature allows MEV extraction or timing manipulation. An attacker can frontrun the call when large balances accumulate to capture favorable distribution timing, potentially extracting value through pool composition.", "paths": ["1. Controller accumulates token balance over time", "2. Attacker monitors balance growth", "3. Attacker calls distributeTaxAdjustment to trigger distribution at favorable moment", "4. Attacker may capture timing advantage"]}, {"id": "F-018", "severity": "Low", "confidence": "low", "title": "Potential division truncation in flow rate calculations", "locations": ["superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol:292-297"], "claim": "The startFunding function calculates flow rates via integer division: subsidyAmount / programDuration and fundingAmount / programDuration.", "impact": "Integer truncation may result in slightly underflowing flow rates when totalAmount is not evenly divisible by duration, causing minor dust amount accumulation in the contract over time.", "paths": ["1. Owner calls startFunding with non-divisible amount/duration", "2. Flow rates are truncated", "3. Dust accumulates in contract"]}]

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
