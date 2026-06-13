pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

import '../libraries/SafeMath.sol';
import '../libraries/UniswapV2Library.sol';
import '../libraries/UniswapV2OracleLibrary.sol';

// sliding window oracle that uses observations collected over a window to provide moving price averages in the past
// `windowSize` with a precision of `windowSize / granularity`
// note this is a singleton oracle and only needs to be deployed once per desired parameters, which
// differs from the simple oracle which must be deployed once per pair.
// 滑动窗口预言机，使用在窗口期间收集的观察数据来提供过去的移动价格平均值
// 精度为 `windowSize / granularity`
// 注意：这是一个单例预言机，只需要按所需参数部署一次，
// 这与简单预言机不同（简单预言机必须为每个配对部署一次）
contract ExampleSlidingWindowOracle {
    using FixedPoint for *;
    using SafeMath for uint;

    /// @notice 观察数据结构
    /// @param timestamp 时间戳
    /// @param price0Cumulative 代币0累积价格
    /// @param price1Cumulative 代币1累积价格
    struct Observation {
        uint timestamp;
        uint price0Cumulative;
        uint price1Cumulative;
    }

    /// @dev Uniswap V2 工厂合约地址
    address public immutable factory;
    /// @dev 计算移动平均值的时间窗口大小（例如24小时）
    uint public immutable windowSize;
    /// @dev 每个配对存储的观察点数量，即窗口中存储了多少价格观察点
    /// 随着粒度从1增加，需要更频繁的更新，但移动平均值变得更精确
    /// 平均值在以下范围内的大小计算：
    ///   [windowSize - (windowSize / granularity) * 2, windowSize]
    /// 例如：如果窗口大小为24小时，粒度为24，预言机将返回以下期间的平均价格：
    ///   [now - [22小时, 24小时], now]
    uint8 public immutable granularity;
    /// @dev 周期大小（冗余存储，与粒度和窗口大小重复，但为了节省 Gas 和信息目的而存储）
    uint public immutable periodSize;

    /// @dev 从配对地址到该配对价格观察点列表的映射
    mapping(address => Observation[]) public pairObservations;

    /// @dev 构造函数：初始化预言机参数
    /// @param factory_ Uniswap V2 工厂合约地址
    /// @param windowSize_ 时间窗口大小
    /// @param granularity_ 粒度
    constructor(address factory_, uint windowSize_, uint8 granularity_) public {
        require(granularity_ > 1, 'SlidingWindowOracle: GRANULARITY');
        require(
            (periodSize = windowSize_ / granularity_) * granularity_ == windowSize_,
            'SlidingWindowOracle: WINDOW_NOT_EVENLY_DIVISIBLE'
        );
        factory = factory_;
        windowSize = windowSize_;
        granularity = granularity_;
    }

    /// @notice 返回给定时间戳对应的观察点索引
    /// @param timestamp 时间戳
    /// @return index 观察点索引
    function observationIndexOf(uint timestamp) public view returns (uint8 index) {
        uint epochPeriod = timestamp / periodSize;
        return uint8(epochPeriod % granularity);
    }

    /// @notice 返回相对于当前时间，从最旧时期（窗口开始）的观察点
    /// @param pair 配对地址
    /// @return firstObservation 第一个观察点
    function getFirstObservationInWindow(address pair) private view returns (Observation storage firstObservation) {
        uint8 observationIndex = observationIndexOf(block.timestamp);
        // 没有溢出问题。如果 observationIndex + 1 溢出，结果仍然是零
        uint8 firstObservationIndex = (observationIndex + 1) % granularity;
        firstObservation = pairObservations[pair][firstObservationIndex];
    }

    /// @notice 更新当前时间戳观察点的累积价格
    /// @dev 每个观察点每个时期最多更新一次
    /// @param tokenA 代币A地址
    /// @param tokenB 代币B地址
    function update(address tokenA, address tokenB) external {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);

        // 使用空观察点填充数组（仅首次调用）
        for (uint i = pairObservations[pair].length; i < granularity; i++) {
            pairObservations[pair].push();
        }

        // 获取当前时期的观察点
        uint8 observationIndex = observationIndexOf(block.timestamp);
        Observation storage observation = pairObservations[pair][observationIndex];

        // 我们只希望每个周期提交一次更新（即 windowSize / granularity）
        uint timeElapsed = block.timestamp - observation.timestamp;
        if (timeElapsed > periodSize) {
            (uint price0Cumulative, uint price1Cumulative,) = UniswapV2OracleLibrary.currentCumulativePrices(pair);
            observation.timestamp = block.timestamp;
            observation.price0Cumulative = price0Cumulative;
            observation.price1Cumulative = price1Cumulative;
        }
    }

    /// @notice 给定一个时期的开始和结束的累积价格，以及时期的长度，计算平均价格
    /// @dev 以 amountIn 可获得多少 amountOut 的形式计算平均价格
    /// @param priceCumulativeStart 开始累积价格
    /// @param priceCumulativeEnd 结束累积价格
    /// @param timeElapsed 经过的时间
    /// @param amountIn 输入数量
    /// @return amountOut 输出数量
    function computeAmountOut(
        uint priceCumulativeStart, uint priceCumulativeEnd,
        uint timeElapsed, uint amountIn
    ) private pure returns (uint amountOut) {
        // 溢出是预期的
        FixedPoint.uq112x112 memory priceAverage = FixedPoint.uq112x112(
            uint224((priceCumulativeEnd - priceCumulativeStart) / timeElapsed)
        );
        amountOut = priceAverage.mul(amountIn).decode144();
    }

    /// @notice 使用时间范围 [now - [windowSize, windowSize - periodSize * 2], now] 的移动平均值，返回给定代币的输入数量对应的输出数量
    /// @dev 对于时间戳 `now - windowSize` 对应的桶，必须已调用 update
    /// @param tokenIn 输入代币地址
    /// @param amountIn 输入数量
    /// @param tokenOut 输出代币地址
    /// @return amountOut 输出数量
    function consult(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut) {
        address pair = UniswapV2Library.pairFor(factory, tokenIn, tokenOut);
        Observation storage firstObservation = getFirstObservationInWindow(pair);

        uint timeElapsed = block.timestamp - firstObservation.timestamp;
        require(timeElapsed <= windowSize, 'SlidingWindowOracle: MISSING_HISTORICAL_OBSERVATION');
        // 不应该发生
        require(timeElapsed >= windowSize - periodSize * 2, 'SlidingWindowOracle: UNEXPECTED_TIME_ELAPSED');

        (uint price0Cumulative, uint price1Cumulative,) = UniswapV2OracleLibrary.currentCumulativePrices(pair);
        (address token0,) = UniswapV2Library.sortTokens(tokenIn, tokenOut);

        if (token0 == tokenIn) {
            return computeAmountOut(firstObservation.price0Cumulative, price0Cumulative, timeElapsed, amountIn);
        } else {
            return computeAmountOut(firstObservation.price1Cumulative, price1Cumulative, timeElapsed, amountIn);
        }
    }
}
