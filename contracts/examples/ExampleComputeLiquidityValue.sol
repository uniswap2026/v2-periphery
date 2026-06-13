pragma solidity =0.6.6;

import '../libraries/UniswapV2LiquidityMathLibrary.sol';

/// @title 计算流动性价值示例合约
/// @notice 演示如何使用 UniswapV2LiquidityMathLibrary 计算流动性价值
/// @dev 此合约用于演示目的，包含计算流动性价值的各种方法
contract ExampleComputeLiquidityValue {
    using SafeMath for uint256;

    /// @dev Uniswap V2 工厂合约地址
    address public immutable factory;

    /// @dev 构造函数：初始化工厂地址
    /// @param factory_ Uniswap V2 工厂合约地址
    constructor(address factory_) public {
        factory = factory_;
    }

    /// @notice 获取套利后的储备金
    /// @dev 参见 UniswapV2LiquidityMathLibrary#getReservesAfterArbitrage
    /// @param tokenA 代币A地址
    /// @param tokenB 代币B地址
    /// @param truePriceTokenA 代币A的真实价格
    /// @param truePriceTokenB 代币B的真实价格
    /// @return reserveA 套利后的代币A储备金
    /// @return reserveB 套利后的代币B储备金
    function getReservesAfterArbitrage(
        address tokenA,
        address tokenB,
        uint256 truePriceTokenA,
        uint256 truePriceTokenB
    ) external view returns (uint256 reserveA, uint256 reserveB) {
        return UniswapV2LiquidityMathLibrary.getReservesAfterArbitrage(
            factory,
            tokenA,
            tokenB,
            truePriceTokenA,
            truePriceTokenB
        );
    }

    /// @notice 获取流动性价值
    /// @dev 参见 UniswapV2LiquidityMathLibrary#getLiquidityValue
    /// @param tokenA 代币A地址
    /// @param tokenB 代币B地址
    /// @param liquidityAmount LP代币数量
    /// @return tokenAAmount 对应的代币A数量
    /// @return tokenBAmount 对应的代币B数量
    function getLiquidityValue(
        address tokenA,
        address tokenB,
        uint256 liquidityAmount
    ) external view returns (
        uint256 tokenAAmount,
        uint256 tokenBAmount
    ) {
        return UniswapV2LiquidityMathLibrary.getLiquidityValue(
            factory,
            tokenA,
            tokenB,
            liquidityAmount
        );
    }

    /// @notice 获取套利到目标价格后的流动性价值
    /// @dev 参见 UniswapV2LiquidityMathLibrary#getLiquidityValueAfterArbitrageToPrice
    /// @param tokenA 代币A地址
    /// @param tokenB 代币B地址
    /// @param truePriceTokenA 代币A的真实价格
    /// @param truePriceTokenB 代币B的真实价格
    /// @param liquidityAmount LP代币数量
    /// @return tokenAAmount 套利后对应的代币A数量
    /// @return tokenBAmount 套利后对应的代币B数量
    function getLiquidityValueAfterArbitrageToPrice(
        address tokenA,
        address tokenB,
        uint256 truePriceTokenA,
        uint256 truePriceTokenB,
        uint256 liquidityAmount
    ) external view returns (
        uint256 tokenAAmount,
        uint256 tokenBAmount
    ) {
        return UniswapV2LiquidityMathLibrary.getLiquidityValueAfterArbitrageToPrice(
            factory,
            tokenA,
            tokenB,
            truePriceTokenA,
            truePriceTokenB,
            liquidityAmount
        );
    }

    /// @notice 测试函数：测量 getLiquidityValueAfterArbitrageToPrice 的Gas消耗
    /// @dev 用于测试目的，测量函数的Gas成本
    /// @param tokenA 代币A地址
    /// @param tokenB 代币B地址
    /// @param truePriceTokenA 代币A的真实价格
    /// @param truePriceTokenB 代币B的真实价格
    /// @param liquidityAmount LP代币数量
    /// @return Gas消耗量
    function getGasCostOfGetLiquidityValueAfterArbitrageToPrice(
        address tokenA,
        address tokenB,
        uint256 truePriceTokenA,
        uint256 truePriceTokenB,
        uint256 liquidityAmount
    ) external view returns (
        uint256
    ) {
        uint gasBefore = gasleft();
        UniswapV2LiquidityMathLibrary.getLiquidityValueAfterArbitrageToPrice(
            factory,
            tokenA,
            tokenB,
            truePriceTokenA,
            truePriceTokenB,
            liquidityAmount
        );
        uint gasAfter = gasleft();
        return gasBefore - gasAfter;
    }
}
