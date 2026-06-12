pragma solidity >=0.5.0;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/lib/contracts/libraries/Babylonian.sol';
import '@uniswap/lib/contracts/libraries/FullMath.sol';

import './SafeMath.sol';
import './UniswapV2Library.sol';

// library containing some math for dealing with the liquidity shares of a pair, e.g. computing their exact value
// in terms of the underlying tokens
// 包含处理配对流动性份额的数学计算，例如计算其精确价值的库
library UniswapV2LiquidityMathLibrary {
    using SafeMath for uint256;

    /// @dev 计算利润最大化交易的方向和数量
    /// @param truePriceTokenA 代币A的真实价格
    /// @param truePriceTokenB 代币B的真实价格
    /// @param reserveA 代币A的储备金
    /// @param reserveB 代币B的储备金
    /// @return aToB 交易方向（true表示A到B）
    /// @return amountIn 所需输入数量
    function computeProfitMaximizingTrade(
        uint256 truePriceTokenA,
        uint256 truePriceTokenB,
        uint256 reserveA,
        uint256 reserveB
    ) pure internal returns (bool aToB, uint256 amountIn) {
        aToB = FullMath.mulDiv(reserveA, truePriceTokenB, reserveB) < truePriceTokenA;

        uint256 invariant = reserveA.mul(reserveB);

        uint256 leftSide = Babylonian.sqrt(
            FullMath.mulDiv(
                invariant.mul(1000),
                aToB ? truePriceTokenA : truePriceTokenB,
                (aToB ? truePriceTokenB : truePriceTokenA).mul(997)
            )
        );
        uint256 rightSide = (aToB ? reserveA.mul(1000) : reserveB.mul(1000)) / 997;

        if (leftSide < rightSide) return (false, 0);

        // 计算将价格移动到利润最大化价格所需的数量
        amountIn = leftSide.sub(rightSide);
    }

    /// @dev 获取套利后将价格移动到利润最大化比率后的储备金
    /// @param factory 工厂合约地址
    /// @param tokenA 代币A地址
    /// @param tokenB 代币B地址
    /// @param truePriceTokenA 代币A的真实价格
    /// @param truePriceTokenB 代币B的真实价格
    /// @return reserveA 套利后的代币A储备金
    /// @return reserveB 套利后的代币B储备金
    function getReservesAfterArbitrage(
        address factory,
        address tokenA,
        address tokenB,
        uint256 truePriceTokenA,
        uint256 truePriceTokenB
    ) view internal returns (uint256 reserveA, uint256 reserveB) {
        // 首先获取交换前的储备金
        (reserveA, reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);

        require(reserveA > 0 && reserveB > 0, 'UniswapV2ArbitrageLibrary: ZERO_PAIR_RESERVES');

        // 然后计算套利到真实价格所需的交换数量
        (bool aToB, uint256 amountIn) = computeProfitMaximizingTrade(truePriceTokenA, truePriceTokenB, reserveA, reserveB);

        if (amountIn == 0) {
            return (reserveA, reserveB);
        }

        // 现在将交易应用到储备金
        if (aToB) {
            uint amountOut = UniswapV2Library.getAmountOut(amountIn, reserveA, reserveB);
            reserveA += amountIn;
            reserveB -= amountOut;
        } else {
            uint amountOut = UniswapV2Library.getAmountOut(amountIn, reserveB, reserveA);
            reserveB += amountIn;
            reserveA -= amountOut;
        }
    }

    /// @dev 计算流动性价值，给定配对的所有参数
    /// @param reservesA 代币A的储备金
    /// @param reservesB 代币B的储备金
    /// @param totalSupply 总供应量
    /// @param liquidityAmount 流动性数量
    /// @param feeOn 是否开启费用机制
    /// @param kLast 上次k值
    /// @return tokenAAmount 代币A的数量
    /// @return tokenBAmount 代币B的数量
    function computeLiquidityValue(
        uint256 reservesA,
        uint256 reservesB,
        uint256 totalSupply,
        uint256 liquidityAmount,
        bool feeOn,
        uint kLast
    ) internal pure returns (uint256 tokenAAmount, uint256 tokenBAmount) {
        if (feeOn && kLast > 0) {
            uint rootK = Babylonian.sqrt(reservesA.mul(reservesB));
            uint rootKLast = Babylonian.sqrt(kLast);
            if (rootK > rootKLast) {
                uint numerator1 = totalSupply;
                uint numerator2 = rootK.sub(rootKLast);
                uint denominator = rootK.mul(5).add(rootKLast);
                uint feeLiquidity = FullMath.mulDiv(numerator1, numerator2, denominator);
                totalSupply = totalSupply.add(feeLiquidity);
            }
        }
        return (reservesA.mul(liquidityAmount) / totalSupply, reservesB.mul(liquidityAmount) / totalSupply);
    }

    /// @dev 从配对获取所有当前参数并计算流动性数量的价值
    /// **注意：这容易受到操纵，例如三明治攻击**。建议传递抗操纵价格给 #getLiquidityValueAfterArbitrageToPrice
    /// @param factory 工厂合约地址
    /// @param tokenA 代币A地址
    /// @param tokenB 代币B地址
    /// @param liquidityAmount 流动性数量
    /// @return tokenAAmount 代币A的数量
    /// @return tokenBAmount 代币B的数量
    function getLiquidityValue(
        address factory,
        address tokenA,
        address tokenB,
        uint256 liquidityAmount
    ) internal view returns (uint256 tokenAAmount, uint256 tokenBAmount) {
        (uint256 reservesA, uint256 reservesB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, tokenA, tokenB));
        bool feeOn = IUniswapV2Factory(factory).feeTo() != address(0);
        uint kLast = feeOn ? pair.kLast() : 0;
        uint totalSupply = pair.totalSupply();
        return computeLiquidityValue(reservesA, reservesB, totalSupply, liquidityAmount, feeOn, kLast);
    }

    /// @dev 给定两个代币及其"真实价格"（即代币A与代币B的价值比率）和流动性数量，返回流动性在代币A和代币B中的价值
    /// @param factory 工厂合约地址
    /// @param tokenA 代币A地址
    /// @param tokenB 代币B地址
    /// @param truePriceTokenA 代币A的真实价格
    /// @param truePriceTokenB 代币B的真实价格
    /// @param liquidityAmount 流动性数量
    /// @return tokenAAmount 代币A的数量
    /// @return tokenBAmount 代币B的数量
    function getLiquidityValueAfterArbitrageToPrice(
        address factory,
        address tokenA,
        address tokenB,
        uint256 truePriceTokenA,
        uint256 truePriceTokenB,
        uint256 liquidityAmount
    ) internal view returns (
        uint256 tokenAAmount,
        uint256 tokenBAmount
    ) {
        bool feeOn = IUniswapV2Factory(factory).feeTo() != address(0);
        IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, tokenA, tokenB));
        uint kLast = feeOn ? pair.kLast() : 0;
        uint totalSupply = pair.totalSupply();

        // 这也检查了totalSupply > 0
        require(totalSupply >= liquidityAmount && liquidityAmount > 0, 'ComputeLiquidityValue: LIQUIDITY_AMOUNT');

        (uint reservesA, uint reservesB) = getReservesAfterArbitrage(factory, tokenA, tokenB, truePriceTokenA, truePriceTokenB);

        return computeLiquidityValue(reservesA, reservesB, totalSupply, liquidityAmount, feeOn, kLast);
    }
}
