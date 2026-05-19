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
- title: Permissionless fee liquidation uses `amountOutMin = 0`, enabling MEV to drain protocol fee value
- claim: Any non-pool token transfer can trigger `_feeSwap`, and `_feeSwap` sells accumulated index-fee inventory through the V2 router with `amountOutMin` hardcoded to `0`. Because the trigger is public and the sale has no price protection, a searcher can move the IDX/DAI pool immediately before the swap and force the contract to dump fee inventory at an arbitrarily bad spot price.
- impact: Protocol fee inventory can be systematically siphoned away from LP stakers and token holders into MEV profit. The larger the accumulated fee balance, the larger the extractable loss.
- exploit_paths: ["Accumulate fee tokens in the index contract via normal bond/debond activity.", "Front-run by pushing the IDX/DAI V2 price against the contract.", "Trigger any qualifying transfer from a non-pool address so `_feeSwap` executes.", "Back-run to unwind the manipulation and capture the value the contract lost on the forced sale."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
  function balanceOf(address account) external view returns (uint256);

  function totalSupply() external view returns (uint256);
}

interface IIndexToken is IERC20Like {
  function BOND_FEE() external view returns (uint256);

  function DEBOND_FEE() external view returns (uint256);

  function lpStakingPool() external view returns (address);
}

interface IStakingPoolTokenLike {
  function stakingToken() external view returns (address);
}

interface IUniswapV2PairLike {
  function token0() external view returns (address);

  function token1() external view returns (address);

  function getReserves()
    external
    view
    returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

contract FlawVerifier {
  address public constant TARGET =
    0xdbB20A979a92ccCcE15229e41c9B082D5b5d7E31;

  address public immutable pair;
  address public immutable dai;

  uint256 private _profitAmount;

  bool public executed;
  bool public hypothesisValidated;
  bool public hypothesisRefuted;

  uint256 public feeInventoryAtExecution;
  uint256 public feeSwapTriggerThreshold;
  uint256 public pairIdxReserveAtExecution;
  uint256 public pairDaiReserveAtExecution;
  uint256 public bondFeeBpsAtExecution;
  uint256 public debondFeeBpsAtExecution;

  constructor() {
    address stakingPool = IIndexToken(TARGET).lpStakingPool();
    address v2Pair = IStakingPoolTokenLike(stakingPool).stakingToken();
    pair = v2Pair;

    address token0 = IUniswapV2PairLike(v2Pair).token0();
    address token1 = IUniswapV2PairLike(v2Pair).token1();
    dai = token0 == TARGET ? token1 : token0;
  }

  function executeOnOpportunity() external {
    executed = true;

    feeInventoryAtExecution = IIndexToken(TARGET).balanceOf(TARGET);
    feeSwapTriggerThreshold = IIndexToken(TARGET).totalSupply() / 10000;
    bondFeeBpsAtExecution = IIndexToken(TARGET).BOND_FEE();
    debondFeeBpsAtExecution = IIndexToken(TARGET).DEBOND_FEE();

    (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair)
      .getReserves();
    if (IUniswapV2PairLike(pair).token0() == TARGET) {
      pairIdxReserveAtExecution = uint256(reserve0);
      pairDaiReserveAtExecution = uint256(reserve1);
    } else {
      pairIdxReserveAtExecution = uint256(reserve1);
      pairDaiReserveAtExecution = uint256(reserve0);
    }

    /*
      Mechanical refutation of the claimed path at this deployment:

      1. The proposed front-run must worsen the IDX/DAI spot price before `_feeSwap`.
         On a constant-product V2 pool, that requires net IDX to enter the pair
         or net DAI to leave it.

      2. Any realistic "push price down" route necessarily reaches the pair through
         an IDX transfer from a non-pool address:
           - direct sell: attacker -> pair
           - donate+sync: attacker -> pair
           - flashswap settlement that repays in IDX: attacker -> pair

      3. The target token's `_transfer` executes `_feeSwap(...)` *before* the IDX
         transfer updates pair balances whenever `_from != V2_POOL`.

      4. Therefore the attacker's own IDX-in step cannot first move the price
         against the protocol and then trigger `_feeSwap`; the trigger fires on the
         pre-manipulation reserves instead.

      5. The obvious flashswap workaround is also mechanically blocked: if the pair
         is already inside `swap`, any IDX repayment transfer back into the locked
         pair would again invoke `_feeSwap`, which attempts another router swap
         against the same pair and reverts under the Uniswap V2 pair lock.

      Because the exploit path depends on stage ordering that the token's transfer
      hook prevents, the original hypothesis is refuted on this fork state.
    */

    _profitAmount = 0;
    hypothesisValidated = false;
    hypothesisRefuted = true;
  }

  function profitToken() external view returns (address) {
    return dai;
  }

  function profitAmount() external view returns (uint256) {
    return _profitAmount;
  }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.05s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 216262)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x6B175474E89094C44Da98b954EedeAC495271d0F
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 7904

Traces:
  [216262] FlawVerifierTest::testExploit()
    ├─ [318] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [175541] FlawVerifier::executeOnOpportunity()
    │   ├─ [2687] 0xdbB20A979a92ccCcE15229e41c9B082D5b5d7E31::balanceOf(0xdbB20A979a92ccCcE15229e41c9B082D5b5d7E31) [staticcall]
    │   │   └─ ← [Return] 18962873888275452765844 [1.896e22]
    │   ├─ [2374] 0xdbB20A979a92ccCcE15229e41c9B082D5b5d7E31::totalSupply() [staticcall]
    │   │   └─ ← [Return] 293877894759882629745878 [2.938e23]
    │   ├─ [338] 0xdbB20A979a92ccCcE15229e41c9B082D5b5d7E31::BOND_FEE() [staticcall]
    │   │   └─ ← [Return] 100
    │   ├─ [295] 0xdbB20A979a92ccCcE15229e41c9B082D5b5d7E31::DEBOND_FEE() [staticcall]
    │   │   └─ ← [Return] 300
    │   ├─ [2504] 0x617Ef52FE266cC3079835A334a99f00B6Df4c052::getReserves() [staticcall]
    │   │   └─ ← [Return] 4037036133052131713807 [4.037e21], 207646995277433034245930 [2.076e23], 1706497583 [1.706e9]
    │   ├─ [2381] 0x617Ef52FE266cC3079835A334a99f00B6Df4c052::token0() [staticcall]
    │   │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    │   └─ ← [Stop]
    ├─ [318] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    ├─ [431] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x6B175474E89094C44Da98b954EedeAC495271d0F)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 19109652 [1.91e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 7904)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 5.74s (365.81ms CPU time)

Ran 1 test suite in 5.75s (5.74s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 216262)

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
