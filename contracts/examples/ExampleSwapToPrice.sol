pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/Babylonian.sol';
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import '../libraries/UniswapV2LiquidityMathLibrary.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/IUniswapV2Router01.sol';
import '../libraries/SafeMath.sol';
import '../libraries/UniswapV2Library.sol';

/// @title 交换到目标价格示例合约
/// @notice 给定外部真实价格，交换代币以使交易利润最大化
contract ExampleSwapToPrice {
    using SafeMath for uint256;

    /// @dev Uniswap V2 路由器合约地址
    IUniswapV2Router01 public immutable router;
    /// @dev Uniswap V2 工厂合约地址
    address public immutable factory;

    /// @dev 构造函数：初始化合约
    /// @param factory_ Uniswap V2 工厂合约地址
    /// @param router_ Uniswap V2 路由器合约地址
    constructor(address factory_, IUniswapV2Router01 router_) public {
        factory = factory_;
        router = router_;
    }

    /// @notice 交换到目标价格
    /// @dev 给定外部真实价格，交换任一代币的数量以使交易利润最大化
    /// 真实价格以代币A与代币B的比率表示
    /// 调用者必须批准此合约花费打算交换的代币
    /// @param tokenA 代币A地址
    /// @param tokenB 代币B地址
    /// @param truePriceTokenA 代币A的真实价格
    /// @param truePriceTokenB 代币B的真实价格
    /// @param maxSpendTokenA 代币A的最大支出数量
    /// @param maxSpendTokenB 代币B的最大支出数量
    /// @param to 接收地址
    /// @param deadline 交易截止时间
    function swapToPrice(
        address tokenA,
        address tokenB,
        uint256 truePriceTokenA,
        uint256 truePriceTokenB,
        uint256 maxSpendTokenA,
        uint256 maxSpendTokenB,
        address to,
        uint256 deadline
    ) public {
        // 真实价格表示为比率，因此两个值都必须非零
        require(truePriceTokenA != 0 && truePriceTokenB != 0, "ExampleSwapToPrice: ZERO_PRICE");
        // 调用者可以为任一方向指定0，如果他们只希望在一个方向交换，但不能两者都为0
        require(maxSpendTokenA != 0 || maxSpendTokenB != 0, "ExampleSwapToPrice: ZERO_SPEND");

        bool aToB;
        uint256 amountIn;
        {
            (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
            (aToB, amountIn) = UniswapV2LiquidityMathLibrary.computeProfitMaximizingTrade(
                truePriceTokenA, truePriceTokenB,
                reserveA, reserveB
            );
        }

        require(amountIn > 0, 'ExampleSwapToPrice: ZERO_AMOUNT_IN');

        // 花费不超过代币的允许额度
        uint256 maxSpend = aToB ? maxSpendTokenA : maxSpendTokenB;
        if (amountIn > maxSpend) {
            amountIn = maxSpend;
        }

        address tokenIn = aToB ? tokenA : tokenB;
        address tokenOut = aToB ? tokenB : tokenA;
        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        TransferHelper.safeApprove(tokenIn, address(router), amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        router.swapExactTokensForTokens(
            amountIn,
            0, // amountOutMin: 我们可以跳过计算这个数字，因为数学已经过测试
            path,
            to,
            deadline
        );
    }
}
