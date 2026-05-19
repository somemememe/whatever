You are fixing a failing Foundry PoC for finding F-002.

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
- title: Minting trusts the requested ERC20 deposit amount instead of the amount actually received
- claim: The mint path prices shares from the caller-supplied `depositAmount` before any transfer happens, then only checks whether `transferFrom` returned success. It never measures the contract's actual balance delta, so a fee-on-transfer or otherwise deflationary `loanTokenAddress` can deliver fewer tokens than `depositAmount` while the minter still receives shares as if the full amount arrived.
- impact: An attacker can over-mint iTokens, diluting existing lenders and later redeeming more underlying than they contributed. If enough liquidity exists, this can make the pool insolvent.
- exploit_paths: ["Use a pool whose `loanTokenAddress` burns, taxes, or otherwise transfers less than the requested amount.", "Call `mint(receiver, X)` so `_safeTransferFrom` succeeds but the contract receives less than `X`.", "Receive shares computed from `X`, then burn them later for a disproportionate amount of underlying."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface ILoanTokenLike {
    function loanTokenAddress() external view returns (address);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

contract FlawVerifier {
    address internal constant TARGET = 0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    ILoanTokenLike internal constant POOL = ILoanTokenLike(TARGET);

    bool public executed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    string public status;
    string public exploitPathUsed;

    address internal _profitToken;
    uint256 internal _profitAmount;

    uint256 public attackerSpendAmount;
    uint256 public poolReceiveAmount;
    uint256 public burnReturnAmount;

    address public flashPair;
    address public exitPair;
    address public loanToken;

    constructor() {
        status = "not-run";
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        require(!executed, "ALREADY_EXECUTED");
        executed = true;

        loanToken = POOL.loanTokenAddress();
        _profitToken = loanToken;

        if (loanToken == address(0)) {
            _refute("refuted:missing-loan-token", "stage1-infeasible:no-underlying");
            return;
        }

        (flashPair, exitPair) = _selectPairs(loanToken);
        if (flashPair == address(0) || exitPair == address(0) || flashPair == exitPair) {
            _refute("refuted:no-distinct-v2-pairs", "flashswap-funding-unavailable");
            return;
        }

        // The implementation behind TARGET exposes a nonpayable `mint(address,uint256)`.
        // The failing attempt used flash-borrowed WETH, unwrapped to ETH, and sent value
        // into `mint`, which necessarily reverts before any transfer logic executes.
        //
        // To stay aligned with the finding, the core exploit path must still be:
        // 1. use a loan token whose transfer can deliver less than the requested amount,
        // 2. call `mint(receiver, X)` and receive shares priced from nominal X,
        // 3. burn those shares for more underlying than actually contributed.
        //
        // This concrete pool's underlying is YFI. Its mint path for this pool is therefore
        // the ERC20 `transferFrom` branch, not the payable WETH branch. Because stage 1
        // requires a deflationary / fee-on-transfer loan token and this target is backed by
        // YFI, the required shortfall condition is not available here. The correct fix for
        // the PoC is to stop forcing the reverted ETH path and mark the exploit as refuted
        // on this fork/target rather than fabricating profit through an invalid route.
        if (loanToken == YFI) {
            attackerSpendAmount = 0;
            poolReceiveAmount = IERC20Like(loanToken).balanceOf(TARGET);
            burnReturnAmount = 0;
            _refute(
                "refuted:stage1-requires-deflationary-underlying",
                "use-deflationary-loanTokenAddress->mint(receiver,X)->burn-overminted-shares:stage1-infeasible-on-this-YFI-pool"
            );
            return;
        }

        _refute(
            "refuted:unsupported-underlying-for-f002",
            "use-deflationary-loanTokenAddress->mint(receiver,X)->burn-overminted-shares:stage1-not-provable"
        );
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _selectPairs(address token) internal view returns (address flash, address exit) {
        address sushi = IUniswapV2FactoryLike(SUSHISWAP_FACTORY).getPair(token, WETH);
        address uni = IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(token, WETH);

        if (sushi != address(0) && uni != address(0) && sushi != uni) {
            return (sushi, uni);
        }

        return (address(0), address(0));
    }

    function _refute(string memory newStatus, string memory path) internal {
        hypothesisValidated = false;
        hypothesisRefuted = true;
        status = newStatus;
        exploitPathUsed = path;
        _profitAmount = 0;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.75s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 360583)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 6419

Traces:
  [360583] FlawVerifierTest::testExploit()
    ├─ [2412] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [321612] FlawVerifier::executeOnOpportunity()
    │   ├─ [2377] 0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b::loanTokenAddress() [staticcall]
    │   │   └─ ← [Return] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x088ee5007C98a9677165D78dD2109AE4a3D04d0C
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x2fDbAdf3C4D5A8666Bc06645B8358ab803996E28
    │   ├─ [2541] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e::balanceOf(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b) [staticcall]
    │   │   └─ ← [Return] 5
    │   └─ ← [Stop]
    ├─ [412] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e
    ├─ [432] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [2541] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 18695728 [1.869e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 6419)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 370.26ms (21.84ms CPU time)

Ran 1 test suite in 520.56ms (370.26ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 360583)

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
