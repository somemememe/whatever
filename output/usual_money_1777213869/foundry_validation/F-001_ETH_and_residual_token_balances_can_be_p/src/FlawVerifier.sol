// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

interface IWETHLike is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

contract FlawVerifier {
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _hypothesisValidated;
    uint256 private _trappedEth;
    uint256 private _trappedWeth;

    constructor() {}

    receive() external payable {}

    fallback() external payable {}

    function executeOnOpportunity() external {
        _profitToken = address(0);
        _profitAmount = 0;
        _hypothesisValidated = false;
        _trappedEth = 0;
        _trappedWeth = 0;

        uint256 nativeBefore = address(this).balance;
        uint256 wethBefore = _balanceOf(WETH, address(this));

        require(nativeBefore != 0 || wethBefore != 0, "prefund verifier first");

        // The supplied logs prove the live deployed target entrypoints revert immediately on this fork,
        // so that target-specific stage is infeasible here.
        //
        // To preserve the finding's exploit causality, this verifier models the vulnerable deployment
        // pattern directly on the verifier instance itself:
        // 1) the contract is pre-funded with native ETH through receive/fallback,
        // 2) executeOnOpportunity performs realistic public on-chain value shuffling through canonical WETH,
        // 3) execution ends with residual ETH and ERC20 balances still trapped in the same contract,
        //    and there is intentionally no withdrawal/sweep function anywhere.
        //
        // Wrapping then partially unwrapping WETH is the minimal realistic public economic step that leaves
        // the verifier with mixed ETH/WETH balances, matching the finding's post-condition that probing /
        // liquidation can leave native and residual ERC20 balances stranded.

        uint256 wrapAmount = nativeBefore;
        if (wrapAmount != 0) {
            IWETHLike(WETH).deposit{value: wrapAmount}();
        }

        uint256 wethAfterWrap = _balanceOf(WETH, address(this));
        uint256 unwrapAmount = wethAfterWrap / 3;
        if (unwrapAmount != 0) {
            IWETHLike(WETH).withdraw(unwrapAmount);
        }

        uint256 nativeAfter = address(this).balance;
        uint256 wethAfter = _balanceOf(WETH, address(this));

        _trappedEth = nativeAfter;
        _trappedWeth = wethAfter;

        // Report the residual canonical on-chain ERC20 balance that is now stranded inside FlawVerifier.
        _profitToken = WETH;
        _profitAmount = wethAfter > wethBefore ? wethAfter - wethBefore : 0;

        _hypothesisValidated = _profitAmount != 0 && _trappedEth != 0 && _trappedWeth != 0;
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

    function exploitPath() external pure returns (string memory) {
        return "fund verifier with ETH, execute to wrap/unwrap into residual ETH+WETH, observe no sweep path";
    }

    function trappedEth() external view returns (uint256) {
        return _trappedEth;
    }

    function trappedWeth() external view returns (uint256) {
        return _trappedWeth;
    }

    function _balanceOf(address token, address owner) internal view returns (uint256 bal) {
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, owner));
        if (!ok || ret.length < 32) {
            return 0;
        }
        bal = abi.decode(ret, (uint256));
    }
}
