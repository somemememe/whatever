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
}

interface IStakingLike {
    function stableCoinBalances(address token) external view returns (uint256);
    function deposit(address tokenAddress, uint256 amount, address referrer) external;
    function withdraw(address tokenAddress, uint256 amount) external;
}

interface ICTokenLike {
    function comptroller() external view returns (address);
    function getCash() external view returns (uint256);
    function mint(uint256 mintAmount) external returns (uint256);
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
    }

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;
    address private _profitToken;
    uint256 private _profitAmount;
    TokenState public chosenState;

    constructor() {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        TokenState memory usdcState = _inspect(USDC, CUSDC);
        TokenState memory usdtState = _inspect(USDT, CUSDT);
        TokenState memory daiState = _inspect(DAI, CDAI);

        chosenState = _pickBest(usdcState, usdtState, daiState);

        // Path-strict conclusion for the supplied finding:
        // 1) `deposit(stable)` can indeed credit internal accounting before `_transferToCompound()`.
        // 2) If `cToken.mint(amount)` ever returns non-zero, the exact deposited principal stays idle inside `TARGET`.
        // 3) `withdraw(stable, amount)` decreases internal balances before `_redeemFromCompound()`.
        // 4) If `redeemUnderlying(amount)` returns non-zero, transfer still only succeeds when `TARGET`
        //    already holds idle underlying; the user still cannot withdraw more than `balances[msg.sender][token]`.
        // 5) Both interest paths send any surplus to the hard-coded `TEAM_ADDRESS`, not to the attacker.
        //
        // Therefore the bug is a real accounting / withdrawal-DoS issue, but not a profit primitive by itself.
        // A failed mint only strands the attacker's own principal in `TARGET`; a failed redeem only changes
        // withdrawal ordering for already-accounted depositors. No stage in the reported path mints extra credit
        // to the attacker or routes surplus value to the attacker.

        // The full reported path additionally requires a non-zero Compound `mint()` return.
        // If no listed stable market is mint-paused on the fork, that first stage is not attacker-triggerable
        // with realistic public actions alone from this contract.
        hypothesisValidated = chosenState.mintPaused || chosenState.localIdleBalance > 0
            || chosenState.compoundCash < chosenState.accountedPrincipal;
        profitAchieved = false;
        _profitToken = address(0);
        _profitAmount = 0;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return "deposit(stable)->stableCoinBalances/user credit->_transferToCompound() unchecked; withdraw(stable)->internal balances reduced->_redeemFromCompound() unchecked; economically refuted as profit path at this fork";
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
        uint256 score = 0;
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
39] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0x245a551ee0F55005e510B239c917fA34b41B3461) [staticcall]
    │   │   ├─ [2553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(0x245a551ee0F55005e510B239c917fA34b41B3461) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [6189] 0x39AA39c021dfbaE8faC545936693aC917d5E7563::getCash() [staticcall]
    │   │   ├─ [3339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0x39AA39c021dfbaE8faC545936693aC917d5E7563) [staticcall]
    │   │   │   ├─ [2553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(0x39AA39c021dfbaE8faC545936693aC917d5E7563) [delegatecall]
    │   │   │   │   └─ ← [Return] 16406678602531 [1.64e13]
    │   │   │   └─ ← [Return] 16406678602531 [1.64e13]
    │   │   └─ ← [Return] 16406678602531 [1.64e13]
    │   ├─ [2449] 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9::comptroller() [staticcall]
    │   │   └─ ← [Return] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B
    │   ├─ [3176] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::mintGuardianPaused(0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9) [staticcall]
    │   │   ├─ [2505] 0xBafE01ff935C7305907c33BF824352eE5979B526::mintGuardianPaused(0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9) [delegatecall]
    │   │   │   └─ ← [Return] false
    │   │   └─ ← [Return] false
    │   ├─ [2470] 0x245a551ee0F55005e510B239c917fA34b41B3461::stableCoinBalances(0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 11684844252 [1.168e10]
    │   ├─ [5031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0x245a551ee0F55005e510B239c917fA34b41B3461) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [13242] 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9::getCash() [staticcall]
    │   │   ├─ [11932] 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9::0933c1ed(000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000043b1d21a200000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   ├─ [5863] 0x3363BAe2Fc44dA742Df13CD3ee94b6bB868ea376::getCash() [delegatecall]
    │   │   │   │   ├─ [3031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9) [staticcall]
    │   │   │   │   │   └─ ← [Return] 19984809561604 [1.998e13]
    │   │   │   │   └─ ← [Return] 19984809561604 [1.998e13]
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000122d13798e04
    │   │   └─ ← [Return] 19984809561604 [1.998e13]
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
    │   └─ ← [Stop]
    ├─ [354] FlawVerifier::profitToken() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.79s (786.24ms CPU time)

Ran 1 test suite in 1.84s (1.79s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 244128)

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
