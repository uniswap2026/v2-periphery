pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol';

import '../libraries/UniswapV2Library.sol';
import '../interfaces/V1/IUniswapV1Factory.sol';
import '../interfaces/V1/IUniswapV1Exchange.sol';
import '../interfaces/IUniswapV2Router01.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/IWETH.sol';

/// @title 闪电交换示例合约
/// @notice 演示如何使用闪电交换在 V1 和 V2 之间进行套利
/// @dev 实现 IUniswapV2Callee 接口以接收闪电交换回调
contract ExampleFlashSwap is IUniswapV2Callee {
    /// @dev Uniswap V1 工厂合约地址
    IUniswapV1Factory immutable factoryV1;
    /// @dev Uniswap V2 工厂合约地址
    address immutable factory;
    /// @dev WETH 合约地址
    IWETH immutable WETH;

    /// @dev 构造函数：初始化 V1 工厂、V2 工厂和 WETH 地址
    /// @param _factory Uniswap V2 工厂合约地址
    /// @param _factoryV1 Uniswap V1 工厂合约地址
    /// @param router Uniswap V2 路由器合约地址（用于获取 WETH 地址）
    constructor(address _factory, address _factoryV1, address router) public {
        factoryV1 = IUniswapV1Factory(_factoryV1);
        factory = _factory;
        WETH = IWETH(IUniswapV2Router01(router).WETH());
    }

    /// @dev 接收 ETH（来自任何 V1 交易所和 WETH）
    /// 理想情况下可以像路由器中那样强制执行，但由于需要调用 V1 工厂，这会消耗太多 gas，所以无法实现
    receive() external payable {}

    /// @notice 闪电交换回调函数
    /// @dev 通过 V2 闪电交换获取代币/WETH，在 V1 上交换为 ETH/代币，偿还 V2，并保留剩余部分
    /// @param sender 调用者地址
    /// @param amount0 代币0的数量
    /// @param amount1 代币1的数量
    /// @param data 额外数据（包含滑点参数）
    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external override {
        address[] memory path = new address[](2);
        uint amountToken;
        uint amountETH;
        { // 作用域用于 token{0,1}，避免堆栈过深错误
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();
        assert(msg.sender == UniswapV2Library.pairFor(factory, token0, token1)); // 确保 msg.sender 实际上是 V2 配对
        assert(amount0 == 0 || amount1 == 0); // 此策略是单向的
        path[0] = amount0 == 0 ? token0 : token1;
        path[1] = amount0 == 0 ? token1 : token0;
        amountToken = token0 == address(WETH) ? amount1 : amount0;
        amountETH = token0 == address(WETH) ? amount0 : amount1;
        }

        assert(path[0] == address(WETH) || path[1] == address(WETH)); // 此策略仅适用于 V2 WETH 配对
        IERC20 token = IERC20(path[0] == address(WETH) ? path[1] : path[0]);
        IUniswapV1Exchange exchangeV1 = IUniswapV1Exchange(factoryV1.getExchange(address(token))); // 获取 V1 交易所

        if (amountToken > 0) {
            // 代币 → ETH 套利路径
            (uint minETH) = abi.decode(data, (uint)); // V1 的滑点参数，由调用者传入
            token.approve(address(exchangeV1), amountToken);
            uint amountReceived = exchangeV1.tokenToEthSwapInput(amountToken, minETH, uint(-1));
            uint amountRequired = UniswapV2Library.getAmountsIn(factory, amountToken, path)[0];
            assert(amountReceived > amountRequired); // 如果我们没有收到足够的 ETH 来偿还闪电贷款则失败
            WETH.deposit{value: amountRequired}();
            assert(WETH.transfer(msg.sender, amountRequired)); // 将 WETH 返回给 V2 配对
            (bool success,) = sender.call{value: amountReceived - amountRequired}(new bytes(0)); // 保留剩余部分（ETH）
            assert(success);
        } else {
            // ETH → 代币套利路径
            (uint minTokens) = abi.decode(data, (uint)); // V1 的滑点参数，由调用者传入
            WETH.withdraw(amountETH);
            uint amountReceived = exchangeV1.ethToTokenSwapInput{value: amountETH}(minTokens, uint(-1));
            uint amountRequired = UniswapV2Library.getAmountsIn(factory, amountETH, path)[0];
            assert(amountReceived > amountRequired); // 如果我们没有收到足够的代币来偿还闪电贷款则失败
            assert(token.transfer(msg.sender, amountRequired)); // 将代币返回给 V2 配对
            assert(token.transfer(sender, amountReceived - amountRequired)); // 保留剩余部分（代币）
        }
    }
}
