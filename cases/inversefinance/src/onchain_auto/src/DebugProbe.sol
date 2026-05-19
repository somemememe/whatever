// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Probe {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function allowance(address,address) external view returns (uint256);
    function decimals() external view returns (uint8);
}

interface ICTokenProbe {
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function totalBorrows() external view returns (uint256);
    function totalReserves() external view returns (uint256);
    function getCash() external view returns (uint256);
    function exchangeRateStored() external view returns (uint256);
    function comptroller() external view returns (address);
    function underlying() external view returns (address);
    function balanceOf(address) external view returns (uint256);
}

interface IFactoryProbe {
    function getPair(address,address) external view returns (address);
}

contract DebugProbe {
    address constant TARGET = 0x7Fcb7DAC61eE35b3D4a51117A7c58D53f0a8a670;
    address constant UNDER = 0x865377367054516e17014CcdED1e7d814EDC9ce4;
    address constant UNI = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address constant SUSHI = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    function probeMeta() external view returns (
        string memory underName,
        string memory underSymbol,
        uint8 underDecimals,
        string memory cSymbol,
        address comptroller
    ) {
        underName = IERC20Probe(UNDER).name();
        underSymbol = IERC20Probe(UNDER).symbol();
        underDecimals = IERC20Probe(UNDER).decimals();
        cSymbol = ICTokenProbe(TARGET).symbol();
        comptroller = ICTokenProbe(TARGET).comptroller();
    }

    function probeMarket() external view returns (uint256,uint256,uint256,uint256,uint256) {
        return (
            ICTokenProbe(TARGET).totalSupply(),
            ICTokenProbe(TARGET).totalBorrows(),
            ICTokenProbe(TARGET).totalReserves(),
            ICTokenProbe(TARGET).getCash(),
            ICTokenProbe(TARGET).exchangeRateStored()
        );
    }

    function probePairs() external view returns (address,address,address,address,address,address,address,address,address,address) {
        return (
            IFactoryProbe(UNI).getPair(UNDER, WETH),
            IFactoryProbe(SUSHI).getPair(UNDER, WETH),
            IFactoryProbe(UNI).getPair(UNDER, USDC),
            IFactoryProbe(SUSHI).getPair(UNDER, USDC),
            IFactoryProbe(UNI).getPair(UNDER, USDT),
            IFactoryProbe(SUSHI).getPair(UNDER, USDT),
            IFactoryProbe(UNI).getPair(UNDER, DAI),
            IFactoryProbe(SUSHI).getPair(UNDER, DAI),
            IFactoryProbe(UNI).getPair(UNDER, FRAX),
            IFactoryProbe(SUSHI).getPair(UNDER, FRAX)
        );
    }
}
