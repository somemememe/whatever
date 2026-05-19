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
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IStakingLike {
    function stableCoinBalances(address token) external view returns (uint256);
    function deposit(address tokenAddress, uint256 amount, address referrer) external;
    function withdraw(address tokenAddress, uint256 amount) external;
    function balanceOf(address user, address token) external view returns (uint256);
}

interface ICTokenLike {
    function comptroller() external view returns (address);
    function getCash() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function balanceOfUnderlying(address owner) external returns (uint256);
    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
}

interface ICompoundComptrollerLike {
    function mintGuardianPaused(address cToken) external view returns (bool);
}

contract FlawVerifier {
    address public constant TARGET = 0x245a551ee0F55005e510B239c917fA34b41B3461;

    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address public constant CUSDC = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address public constant CUSDT = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9;
    address public constant CDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;

    struct TokenState {
        address token;
        address cToken;
        bool mintPaused;
        uint256 accountedPrincipal;
        uint256 localIdleBalance;
        uint256 compoundCash;
        uint256 compoundUnderlying;
        uint256 cTokenBalance;
    }

    bool public executed;
    bool public hypothesisValidated;
    bool public depositPathReachable;
    bool public withdrawPathReachable;
    bool public exercisedPath;
    bool public profitAchieved;

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

        // Report-aligned mechanics:
        //
        // Path 1:
        // deposit(stable)
        // -> stableCoinBalances[token] increments
        // -> user balance / checkpoint is credited
        // -> _transferToCompound()
        // -> cToken.mint(amount) may return non-zero instead of reverting
        // -> principal remains idle on TARGET while accounting assumes investment.
        //
        // Path 2:
        // withdraw(stable, amount)
        // -> balances[msg.sender][token] and stableCoinBalances[token] decrease first
        // -> _redeemFromCompound()
        // -> cToken.redeemUnderlying(amount) may return non-zero instead of reverting
        // -> transfer then depends only on whatever idle local stablecoins TARGET already holds.
        //
        // This verifier intentionally does not turn its own starting ETH into a reported ERC20 balance,
        // because that would not be exploit profit for F-001. It only reports realized verifier-held
        // profit, and F-001 is fundamentally an accounting / withdrawal-ordering bug unless the fork
        // already exposes a failing Compound leg.

        depositPathReachable = chosenState.mintPaused;
        withdrawPathReachable =
            chosenState.localIdleBalance > 0 ||
            chosenState.compoundUnderlying < chosenState.accountedPrincipal;
        hypothesisValidated = depositPathReachable || withdrawPathReachable;

        _profitToken = address(0);
        _profitAmount = 0;
        profitAchieved = false;
        exercisedPath = false;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return "deposit(stable)->stableCoinBalances/user credit->_transferToCompound() unchecked; withdraw(stable)->internal balances reduced->_redeemFromCompound() unchecked; fork-specific profit stage is not publicly realizable unless the fork already exposes a failing Compound market state";
    }

    function _inspect(address token, address cToken) internal returns (TokenState memory state) {
        state.token = token;
        state.cToken = cToken;
        state.mintPaused = ICompoundComptrollerLike(ICTokenLike(cToken).comptroller()).mintGuardianPaused(cToken);
        state.accountedPrincipal = IStakingLike(TARGET).stableCoinBalances(token);
        state.localIdleBalance = IERC20Like(token).balanceOf(TARGET);
        state.compoundCash = ICTokenLike(cToken).getCash();
        state.cTokenBalance = ICTokenLike(cToken).balanceOf(TARGET);

        if (state.cTokenBalance > 0) {
            try ICTokenLike(cToken).balanceOfUnderlying(TARGET) returns (uint256 underlyingAmount) {
                state.compoundUnderlying = underlyingAmount;
            } catch {
                state.compoundUnderlying = 0;
            }
        }
    }

    function _pickBest(
        TokenState memory a,
        TokenState memory b,
        TokenState memory c
    ) internal pure returns (TokenState memory) {
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
        if (state.compoundUnderlying < state.accountedPrincipal) {
            score += 1 << 253;
        }
        score += state.accountedPrincipal;
        return score;
    }
}

```

forge stdout (tail):
```
  │   └─ ← [Return] 19984809561604 [1.998e13]
    │   │   │   └─ ← [Return] 11962877371 [1.196e10]
    │   │   └─ ← [Return] 11962877371 [1.196e10]
    │   ├─ [2449] 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643::comptroller() [staticcall]
    │   │   └─ ← [Return] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B
    │   ├─ [3176] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::mintGuardianPaused(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643) [staticcall]
    │   │   ├─ [2505] 0xBafE01ff935C7305907c33BF824352eE5979B526::mintGuardianPaused(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643) [delegatecall]
    │   │   │   └─ ← [Return] false
    │   │   └─ ← [Return] false
    │   ├─ [2470] 0x245a551ee0F55005e510B239c917fA34b41B3461::stableCoinBalances(0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 2917676061731548336912 [2.917e21]
    │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0x245a551ee0F55005e510B239c917fA34b41B3461) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [11168] 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643::getCash() [staticcall]
    │   │   ├─ [9003] 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643::0933c1ed(000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000043b1d21a200000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   ├─ [5434] 0x3363BAe2Fc44dA742Df13CD3ee94b6bB868ea376::getCash() [delegatecall]
    │   │   │   │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643) [staticcall]
    │   │   │   │   │   └─ ← [Return] 11252220389768391957128617 [1.125e25]
    │   │   │   │   └─ ← [Return] 11252220389768391957128617 [1.125e25]
    │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000094ec016ef9baa7db7a5a9
    │   │   └─ ← [Return] 11252220389768391957128617 [1.125e25]
    │   ├─ [6773] 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643::balanceOf(0x245a551ee0F55005e510B239c917fA34b41B3461) [staticcall]
    │   │   ├─ [4257] 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643::0933c1ed(0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002470a08231000000000000000000000000245a551ee0f55005e510b239c917fa34b41b346100000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   ├─ [2600] 0x3363BAe2Fc44dA742Df13CD3ee94b6bB868ea376::balanceOf(0x245a551ee0F55005e510B239c917fA34b41B3461) [delegatecall]
    │   │   │   │   └─ ← [Return] 12064373028859 [1.206e13]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000af8f4ab37fb
    │   │   └─ ← [Return] 12064373028859 [1.206e13]
    │   ├─ [44252] 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643::balanceOfUnderlying(0x245a551ee0F55005e510B239c917fA34b41B3461)
    │   │   ├─ [42894] 0x3363BAe2Fc44dA742Df13CD3ee94b6bB868ea376::balanceOfUnderlying(0x245a551ee0F55005e510B239c917fA34b41B3461) [delegatecall]
    │   │   │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643) [staticcall]
    │   │   │   │   └─ ← [Return] 11252220389768391957128617 [1.125e25]
    │   │   │   ├─ [2708] 0xFB564da37B41b2F6B6EDcc3e56FbF523bD9F2012::15f24053(000000000000000000000000000000000000000000094ec016ef9baa7db7a5a90000000000000000000000000000000000000000001230b23e34c8c9e113583400000000000000000000000000000000000000000006e02e4c88491c9a44a75b) [staticcall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000e5644cabe
    │   │   │   ├─  emit topic 0: 0x4dec04e750ca11537cabcd8a9eab06494de08da3735bc8871cd41250e190bc04
    │   │   │   │           data: 0x000000000000000000000000000000000000000000094ec016ef9baa7db7a5a900000000000000000000000000000000000000000000002097b2a89c2b22588800000000000000000000000000000000000000000000000012fcd0b97a48f2cb0000000000000000000000000000000000000000001230d2d5e771660c35b0bc
    │   │   │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643) [staticcall]
    │   │   │   │   └─ ← [Return] 11252220389768391957128617 [1.125e25]
    │   │   │   └─ ← [Return] 2984316882086071788993 [2.984e21]
    │   │   └─ ← [Return] 2984316882086071788993 [2.984e21]
    │   └─ ← [Stop]
    ├─ [376] FlawVerifier::profitToken() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.14s (2.08s CPU time)

Ran 1 test suite in 2.18s (2.14s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 463804)

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
