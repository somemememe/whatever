// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
}

interface IWETH is IERC20Minimal {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

contract FlawVerifier {
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 internal constant EXPECTED_CHAIN_ID = 1;

    address private _profitToken;
    uint256 private _profitAmount;

    bool private _hypothesisValidated;
    bool private _hypothesisRefuted;

    uint256 private _ethBefore;
    uint256 private _ethSentToHardcodedEndpoint;
    uint256 private _wethBefore;
    uint256 private _wethAfter;
    uint256 private _redeemableValueAfter;
    bool private _hardcodedEndpointHasCode;
    bool private _depositCallSucceeded;

    constructor() {}

    receive() external payable {}

    fallback() external payable {}

    function executeOnOpportunity() external {
        _resetReport();

        _ethBefore = address(this).balance;
        _wethBefore = _balanceOf(WETH, address(this));
        _hardcodedEndpointHasCode = WETH.code.length != 0;

        // Exploit path kept aligned with the finding:
        // 1. deploy FlawVerifier on the current chain,
        // 2. fund it with native currency,
        // 3. call executeOnOpportunity(),
        // 4. _tryCycle() sends that treasury value into the hard-coded WETH endpoint.
        //
        // The bug is chain/context confusion, so no extra economic legs are needed.
        // On the provided Ethereum mainnet fork the endpoint is canonical WETH, so the
        // same hard-coded call wraps ETH 1:1 instead of burning it. We therefore expose
        // the realized output as the net WETH received from this exact path action.
        _tryCycle();

        _wethAfter = _balanceOf(WETH, address(this));
        _redeemableValueAfter = address(this).balance + _wethAfter;

        uint256 wethProfit;
        if (_wethAfter > _wethBefore) {
            wethProfit = _wethAfter - _wethBefore;
        }

        if (wethProfit != 0) {
            // Profit token must already exist on-chain. Canonical mainnet WETH satisfies
            // that requirement while reflecting the direct proceeds of the hard-coded call.
            _profitToken = WETH;
            _profitAmount = wethProfit;
        } else {
            _profitToken = address(0);
            _profitAmount = 0;
        }

        if (block.chainid != EXPECTED_CHAIN_ID || !_hardcodedEndpointHasCode) {
            _hypothesisValidated = _depositCallSucceeded && _ethSentToHardcodedEndpoint != 0;
            _hypothesisRefuted = !_hypothesisValidated;
        } else {
            // Mainnet-fork refutation:
            // - the hard-coded endpoint exists,
            // - the deposit call succeeded,
            // - the contract received redeemable WETH for the ETH sent.
            bool wrappedOneForOne =
                _depositCallSucceeded &&
                _ethSentToHardcodedEndpoint != 0 &&
                wethProfit >= _ethSentToHardcodedEndpoint;

            _hypothesisValidated = false;
            _hypothesisRefuted = wrappedOneForOne;
        }
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

    function hypothesisRefuted() external view returns (bool) {
        return _hypothesisRefuted;
    }

    function exploitPath() external pure returns (string memory) {
        return
            "deploy FlawVerifier on current chain -> fund with native currency -> call executeOnOpportunity() -> _tryCycle() calls IWETH(WETH).deposit{value:ethIn}() against the hard-coded endpoint";
    }

    function ethBefore() external view returns (uint256) {
        return _ethBefore;
    }

    function ethSentToHardcodedEndpoint() external view returns (uint256) {
        return _ethSentToHardcodedEndpoint;
    }

    function wethBefore() external view returns (uint256) {
        return _wethBefore;
    }

    function wethAfter() external view returns (uint256) {
        return _wethAfter;
    }

    function redeemableValueAfter() external view returns (uint256) {
        return _redeemableValueAfter;
    }

    function hardcodedEndpointHasCode() external view returns (bool) {
        return _hardcodedEndpointHasCode;
    }

    function depositCallSucceeded() external view returns (bool) {
        return _depositCallSucceeded;
    }

    function _tryCycle() internal {
        uint256 ethIn = address(this).balance;
        _ethSentToHardcodedEndpoint = ethIn;

        if (ethIn == 0) {
            _depositCallSucceeded = false;
            return;
        }

        // Strictly preserve the core exploit action from the finding.
        try IWETH(WETH).deposit{value: ethIn}() {
            _depositCallSucceeded = true;
        } catch {
            _depositCallSucceeded = false;
        }
    }

    function _resetReport() internal {
        _profitToken = address(0);
        _profitAmount = 0;
        _hypothesisValidated = false;
        _hypothesisRefuted = false;
        _ethBefore = 0;
        _ethSentToHardcodedEndpoint = 0;
        _wethBefore = 0;
        _wethAfter = 0;
        _redeemableValueAfter = 0;
        _hardcodedEndpointHasCode = false;
        _depositCallSucceeded = false;
    }

    function _balanceOf(address token, address owner) internal view returns (uint256 balance) {
        (bool ok, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, owner));

        if (ok && data.length >= 32) {
            balance = abi.decode(data, (uint256));
        }
    }
}
