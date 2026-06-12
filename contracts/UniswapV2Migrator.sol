pragma solidity =0.6.6;

import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import './interfaces/IUniswapV2Migrator.sol';
import './interfaces/V1/IUniswapV1Factory.sol';
import './interfaces/V1/IUniswapV1Exchange.sol';
import './interfaces/IUniswapV2Router01.sol';
import './interfaces/IERC20.sol';

contract UniswapV2Migrator is IUniswapV2Migrator {
    IUniswapV1Factory immutable factoryV1;
    IUniswapV2Router01 immutable router;

    /// @dev 构造函数：初始化V1工厂和V2路由器
    /// @param _factoryV1 V1工厂合约地址
    /// @param _router V2路由器合约地址
    constructor(address _factoryV1, address _router) public {
        factoryV1 = IUniswapV1Factory(_factoryV1);
        router = IUniswapV2Router01(_router);
    }

    // needs to accept ETH from any v1 exchange and the router. ideally this could be enforced, as in the router,
    // but it's not possible because it requires a call to the v1 factory, which takes too much gas
    /// @dev 接收ETH（从任何V1交易所和路由器）
    /// 理想情况下可以像路由器中那样强制执行，但由于需要调用V1工厂，这会消耗太多gas，所以无法实现
    receive() external payable {}

    /// @dev 迁移流动性从V1到V2
    /// @param token 代币地址
    /// @param amountTokenMin 最小代币数量
    /// @param amountETHMin 最小ETH数量
    /// @param to 流动性接收地址
    /// @param deadline 交易截止时间
    function migrate(address token, uint amountTokenMin, uint amountETHMin, address to, uint deadline)
        external
        override
    {
        IUniswapV1Exchange exchangeV1 = IUniswapV1Exchange(factoryV1.getExchange(token));
        uint liquidityV1 = exchangeV1.balanceOf(msg.sender);
        require(exchangeV1.transferFrom(msg.sender, address(this), liquidityV1), 'TRANSFER_FROM_FAILED');
        (uint amountETHV1, uint amountTokenV1) = exchangeV1.removeLiquidity(liquidityV1, 1, 1, uint(-1));
        TransferHelper.safeApprove(token, address(router), amountTokenV1);
        (uint amountTokenV2, uint amountETHV2,) = router.addLiquidityETH{value: amountETHV1}(
            token,
            amountTokenV1,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );
        if (amountTokenV1 > amountTokenV2) {
            TransferHelper.safeApprove(token, address(router), 0); // be a good blockchain citizen, reset allowance to 0
            TransferHelper.safeTransfer(token, msg.sender, amountTokenV1 - amountTokenV2);
        } else if (amountETHV1 > amountETHV2) {
            // addLiquidityETH guarantees that all of amountETHV1 or amountTokenV1 will be used, hence this else is safe
            // addLiquidityETH保证amountETHV1或amountTokenV1全部被使用，因此这个else是安全的
            TransferHelper.safeTransferETH(msg.sender, amountETHV1 - amountETHV2);
        }
    }
}
