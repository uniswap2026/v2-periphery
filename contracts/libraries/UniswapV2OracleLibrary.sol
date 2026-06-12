pragma solidity >=0.5.0;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

// library with helper methods for oracles that are concerned with computing average prices
// 用于计算平均价格的oracle辅助方法库
library UniswapV2OracleLibrary {
    using FixedPoint for *;

    /// @dev 返回当前区块时间戳，限制在uint32范围内 [0, 2**32 - 1]
    /// @return 当前区块时间戳
    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2 ** 32);
    }

    /// @dev 使用反事实计算累积价格，节省gas并避免调用sync
    /// @param pair 配对合约地址
    /// @return price0Cumulative 代币0的累积价格
    /// @return price1Cumulative 代币1的累积价格
    /// @return blockTimestamp 当前区块时间戳
    function currentCumulativePrices(
        address pair
    ) internal view returns (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) {
        blockTimestamp = currentBlockTimestamp();
        price0Cumulative = IUniswapV2Pair(pair).price0CumulativeLast();
        price1Cumulative = IUniswapV2Pair(pair).price1CumulativeLast();

        // 如果自上次更新以来已过去时间，则模拟累积价格值
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
        if (blockTimestampLast != blockTimestamp) {
            // 减法溢出是预期的（时间差计算）
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;
            // 加法溢出是预期的（累积价格更新）
            // 反事实计算
            price0Cumulative += uint(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
            // 反事实计算
            price1Cumulative += uint(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsed;
        }
    }
}
