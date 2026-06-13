pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

import '../libraries/UniswapV2OracleLibrary.sol';
import '../libraries/UniswapV2Library.sol';

// fixed window oracle that recomputes the average price for the entire period once every period
// note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period
// 固定窗口预言机，每个周期重新计算整个时间段的平均价格
// 注意：价格平均值仅保证至少覆盖1个周期，但可能覆盖更长的周期
contract ExampleOracleSimple {
    using FixedPoint for *;

    /// @dev 预言机更新周期（24小时）
    uint public constant PERIOD = 24 hours;

    /// @dev 交易对合约
    IUniswapV2Pair immutable pair;
    /// @dev 代币0地址
    address public immutable token0;
    /// @dev 代币1地址
    address public immutable token1;

    /// @dev 上次代币0累积价格
    uint    public price0CumulativeLast;
    /// @dev 上次代币1累积价格
    uint    public price1CumulativeLast;
    /// @dev 上次区块时间戳
    uint32  public blockTimestampLast;
    /// @dev 代币0平均价格（uq112x112格式）
    FixedPoint.uq112x112 public price0Average;
    /// @dev 代币1平均价格（uq112x112格式）
    FixedPoint.uq112x112 public price1Average;

    /// @dev 构造函数：初始化合约
    /// @param factory 工厂合约地址
    /// @param tokenA 代币A地址
    /// @param tokenB 代币B地址
    constructor(address factory, address tokenA, address tokenB) public {
        IUniswapV2Pair _pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, tokenA, tokenB));
        pair = _pair;
        token0 = _pair.token0();
        token1 = _pair.token1();
        price0CumulativeLast = _pair.price0CumulativeLast(); // 获取当前累积价格值（1/0）
        price1CumulativeLast = _pair.price1CumulativeLast(); // 获取当前累积价格值（0/1）
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = _pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, 'ExampleOracleSimple: NO_RESERVES'); // 确保配对中有流动性
    }

    /// @notice 更新平均价格
    /// @dev 重新计算代币0和代币1的时间加权平均价格
    function update() external {
        (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // 溢出是预期的

        // 确保自上次更新以来至少经过了一个完整周期
        require(timeElapsed >= PERIOD, 'ExampleOracleSimple: PERIOD_NOT_ELAPSED');

        // 溢出是预期的，转换不会截断
        // 累积价格的单位是（uq112x112价格 * 秒），因此在除以经过的时间后简单地包装它
        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
        price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    /// @notice 查询代币价格
    /// @dev 注意：在首次成功调用update之前，此函数将始终返回0
    /// @param token 查询的代币地址
    /// @param amountIn 输入数量
    /// @return amountOut 输出数量
    function consult(address token, uint amountIn) external view returns (uint amountOut) {
        if (token == token0) {
            amountOut = price0Average.mul(amountIn).decode144();
        } else {
            require(token == token1, 'ExampleOracleSimple: INVALID_TOKEN');
            amountOut = price1Average.mul(amountIn).decode144();
        }
    }
}
