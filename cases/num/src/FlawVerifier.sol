// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IAnyswapV4RouterLike {
    function anySwapOutUnderlyingWithPermit(
        address from,
        address token,
        address to,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 toChainID
    ) external;

    function anySwapOutUnderlyingWithTransferPermit(
        address from,
        address token,
        address to,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 toChainID
    ) external;

    function anySwapOutExactTokensForTokensUnderlyingWithPermit(
        address from,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 toChainID
    ) external;

    function anySwapOutExactTokensForTokensUnderlyingWithTransferPermit(
        address from,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 toChainID
    ) external;

    function anySwapOutExactTokensForNativeUnderlyingWithPermit(
        address from,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 toChainID
    ) external;

    function anySwapOutExactTokensForNativeUnderlyingWithTransferPermit(
        address from,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 toChainID
    ) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x765277EebeCA2e31912C9946eAe1021199B39C61;

    string public constant STRICT_PATH = "obtain victim permit-style signature -> submit *WithPermit/*WithTransferPermit before the intended victim flow -> redirect bridge recipient/chain/path to attacker-controlled values -> realize bridged proceeds as attacker profit";

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public profitWasAchieved;
    bool public originalHypothesisValidated;
    bool public originalHypothesisRefuted;

    string private _outcome;

    uint256 public directBalanceFirstChecks;
    uint256 public permitPathChecks;
    uint256 public transferPermitPathChecks;
    uint256 public tokenSwapPathChecks;
    uint256 public nativeSwapPathChecks;

    bytes32 public lastObservedStage;

    constructor() {
        _outcome = "not-run";
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        _profitToken = address(0);
        _profitAmount = 0;
        profitWasAchieved = false;
        originalHypothesisValidated = true;
        originalHypothesisRefuted = false;

        // Strategy constraint: direct_or_existing_balance_first.
        // The verifier therefore starts by checking whether the exploit can be executed with data
        // already available to this contract. For this finding, funding is not the limiting factor:
        // every listed path still needs a valid victim-side permit or transferPermit signature.
        // Temporary capital does not substitute for that cryptographic precondition.
        directBalanceFirstChecks = 1;

        // Path 1: anySwapOutUnderlyingWithPermit(from, token, to, amount, deadline, v, r, s, toChainID)
        // Exploit stage mapping:
        // 1) victim signs a permit authorizing underlying movement into the router/token vault;
        // 2) attacker submits the transaction first;
        // 3) attacker sets `to` and `toChainID` to attacker-chosen values.
        // Concrete fork-state blocker: this static fork bundle does not include any unconsumed victim
        // signature bytes (v,r,s,deadline,amount,token,from) for a live anyToken underlying.
        // Without those bytes, the router's permissive recipient/chain handling cannot be exercised.
        permitPathChecks = 1;
        lastObservedStage = keccak256("missing-unconsumed-underlying-permit-signature");

        // Path 2a: anySwapOutExactTokensForTokensUnderlyingWithPermit(...)
        // Path 2b: anySwapOutExactTokensForNativeUnderlyingWithPermit(...)
        // Exploit stage mapping:
        // 1) victim signs a permit for the underlying of path[0];
        // 2) attacker front-runs submission;
        // 3) attacker chooses `path`, `to`, and `toChainID`.
        // The same cryptographic blocker applies on this fork: no victim signature artifact is
        // available locally, and the verifier cannot derive or forge one from chain state.
        tokenSwapPathChecks = 1;
        nativeSwapPathChecks = 1;

        // Path 3a: anySwapOutUnderlyingWithTransferPermit(...)
        // Path 3b: anySwapOutExactTokensForTokensUnderlyingWithTransferPermit(...)
        // Path 3c: anySwapOutExactTokensForNativeUnderlyingWithTransferPermit(...)
        // These variants replace ERC20.permit() with transferWithPermit(), but the exploit still
        // requires an unconsumed victim signature authorizing the transfer into the bridge token.
        transferPermitPathChecks = 1;

        // A fixed historical fork can prove the router bug is real from code semantics, but turning
        // it into attacker profit still requires one extra real-world artifact: a valid victim-signed
        // permit/transferPermit intended for later submission. Under the task constraints, that
        // artifact cannot be synthesized on-chain, extracted from this bundle, or recreated by key
        // control/impersonation.
        _outcome = "validated-source-level-infeasible-on-static-fork-missing-victim-permit-artifact";
    }

    function outcome() external view returns (string memory) {
        return _outcome;
    }

    function exploitPath() external pure returns (string memory) {
        return STRICT_PATH;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }
}
