pragma solidity >=0.5.0;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import "./SafeMath.sol";

library UniswapV2Library {
    using SafeMath for uint;

    /// @dev 对两个代币地址进行排序，确保返回的顺序是确定的
    /// @param tokenA 第一个代币地址
    /// @param tokenB 第二个代币地址
    /// @return token0 排序后的第一个代币地址（较小值）
    /// @return token1 排序后的第二个代币地址（较大值）
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS');
    }

    /// @dev 通过CREATE2计算配对合约地址，无需外部调用
    /// @param factory 工厂合约地址
    /// @param tokenA 第一个代币地址
    /// @param tokenB 第二个代币地址
    /// @return pair 配对合约地址
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff', // CREATE2前缀
                factory, // 工厂地址
                keccak256(abi.encodePacked(token0, token1)), // 代币哈希
                hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f' // 初始化代码哈希
            ))));
    }

    /// @dev 获取并排序配对合约的储备金
    /// @param factory 工厂合约地址
    /// @param tokenA 第一个代币地址
    /// @param tokenB 第二个代币地址
    /// @return reserveA 第一个代币的储备金
    /// @return reserveB 第二个代币的储备金
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /// @dev 根据储备金计算等价值
    /// @param amountA 代币A的数量
    /// @param reserveA 代币A的储备金
    /// @param reserveB 代币B的储备金
    /// @return amountB 代币B的等价值
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'UniswapV2Library: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    /// @dev 计算输入代币的最大输出数量（含0.3%费用）
    /// @param amountIn 输入代币数量
    /// @param reserveIn 输入代币储备金
    /// @param reserveOut 输出代币储备金
    /// @return amountOut 最大输出数量
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997); // 0.3%费用 = 1000 - 3
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    /// @dev 计算达到输出数量所需的输入数量（含0.3%费用）
    /// @param amountOut 期望的输出数量
    /// @param reserveIn 输入代币储备金
    /// @param reserveOut 输出代币储备金
    /// @return amountIn 所需的输入数量
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }

    /// @dev 对路径中的多个配对执行连续的getAmountOut计算
    /// @param factory 工厂合约地址
    /// @param amountIn 输入数量
    /// @param path 交易路径（代币地址数组）
    /// @return amounts 每个步骤的输出数量数组
    function getAmountsOut(address factory, uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    /// @dev 对路径中的多个配对执行连续的getAmountIn计算
    /// @param factory 工厂合约地址
    /// @param amountOut 期望的输出数量
    /// @param path 交易路径（代币地址数组）
    /// @return amounts 每个步骤所需的输入数量数组
    function getAmountsIn(address factory, uint amountOut, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
