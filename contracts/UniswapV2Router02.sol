pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import './interfaces/IUniswapV2Router02.sol';
import './libraries/UniswapV2Library.sol';
import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';

contract UniswapV2Router02 is IUniswapV2Router02 {
    using SafeMath for uint;

    address public immutable override factory;
    address public immutable override WETH;

    /// @dev 确保交易在截止时间之前执行
    /// @param deadline 交易截止时间戳
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
    }

    /// @dev 仅接受来自WETH合约的ETH（通过回退函数）
    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    // **** ADD LIQUIDITY ****
    // **** 添加流动性 ****

    /// @dev 内部函数：计算添加流动性所需的代币数量
    /// @param tokenA 代币A地址
    /// @param tokenB 代币B地址
    /// @param amountADesired 代币A期望数量
    /// @param amountBDesired 代币B期望数量
    /// @param amountAMin 代币A最小数量
    /// @param amountBMin 代币B最小数量
    /// @return amountA 实际添加的代币A数量
    /// @return amountB 实际添加的代币B数量
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        // 如果配对还不存在，则创建它
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    /// @dev 添加两种代币的流动性
    /// @param tokenA 代币A地址
    /// @param tokenB 代币B地址
    /// @param amountADesired 代币A期望数量
    /// @param amountBDesired 代币B期望数量
    /// @param amountAMin 代币A最小数量
    /// @param amountBMin 代币B最小数量
    /// @param to 流动性接收地址
    /// @param deadline 交易截止时间
    /// @return amountA 实际添加的代币A数量
    /// @return amountB 实际添加的代币B数量
    /// @return liquidity 流动性代币数量
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    /// @dev 添加ETH和代币的流动性
    /// @param token 代币地址
    /// @param amountTokenDesired 代币期望数量
    /// @param amountTokenMin 代币最小数量
    /// @param amountETHMin ETH最小数量
    /// @param to 流动性接收地址
    /// @param deadline 交易截止时间
    /// @return amountToken 实际添加的代币数量
    /// @return amountETH 实际添加的ETH数量
    /// @return liquidity 流动性代币数量
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IUniswapV2Pair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    // **** 移除流动性 ****

    /// @dev 移除两种代币的流动性
    /// @param tokenA 代币A地址
    /// @param tokenB 代币B地址
    /// @param liquidity 流动性代币数量
    /// @param amountAMin 代币A最小数量
    /// @param amountBMin 代币B最小数量
    /// @param to 流动性接收地址
    /// @param deadline 交易截止时间
    /// @return amountA 返回的代币A数量
    /// @return amountB 返回的代币B数量
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);
        (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }

    /// @dev 移除ETH和代币的流动性
    /// @param token 代币地址
    /// @param liquidity 流动性代币数量
    /// @param amountTokenMin 代币最小数量
    /// @param amountETHMin ETH最小数量
    /// @param to 流动性接收地址
    /// @param deadline 交易截止时间
    /// @return amountToken 返回的代币数量
    /// @return amountETH 返回的ETH数量
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    /// @dev 使用permit功能移除流动性（无gas批准）
    /// @param tokenA 代币A地址
    /// @param tokenB 代币B地址
    /// @param liquidity 流动性代币数量
    /// @param amountAMin 代币A最小数量
    /// @param amountBMin 代币B最小数量
    /// @param to 流动性接收地址
    /// @param deadline 交易截止时间
    /// @param approveMax 是否批准最大值
    /// @param v 签名参数v
    /// @param r 签名参数r
    /// @param s 签名参数s
    /// @return amountA 返回的代币A数量
    /// @return amountB 返回的代币B数量
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    /// @dev 使用permit功能移除ETH流动性（无gas批准）
    /// @param token 代币地址
    /// @param liquidity 流动性代币数量
    /// @param amountTokenMin 代币最小数量
    /// @param amountETHMin ETH最小数量
    /// @param to 流动性接收地址
    /// @param deadline 交易截止时间
    /// @param approveMax 是否批准最大值
    /// @param v 签名参数v
    /// @param r 签名参数r
    /// @param s 签名参数s
    /// @return amountToken 返回的代币数量
    /// @return amountETH 返回的ETH数量
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountToken, uint amountETH) {
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    // **** 移除流动性（支持费用转移代币）****

    /// @dev 移除ETH流动性（支持费用转移代币）
    /// @param token 代币地址
    /// @param liquidity 流动性代币数量
    /// @param amountTokenMin 代币最小数量
    /// @param amountETHMin ETH最小数量
    /// @param to 流动性接收地址
    /// @param deadline 交易截止时间
    /// @return amountETH 返回的ETH数量
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    /// @dev 使用permit功能移除ETH流动性（支持费用转移代币）
    /// @param token 代币地址
    /// @param liquidity 流动性代币数量
    /// @param amountTokenMin 代币最小数量
    /// @param amountETHMin ETH最小数量
    /// @param to 流动性接收地址
    /// @param deadline 交易截止时间
    /// @param approveMax 是否批准最大值
    /// @param v 签名参数v
    /// @param r 签名参数r
    /// @param s 签名参数s
    /// @return amountETH 返回的ETH数量
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountETH) {
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    // **** 交易 ****

    /// @dev 内部函数：执行多跳交易
    /// @param amounts 每个步骤的代币数量
    /// @param path 交易路径（代币地址数组）
    /// @param _to 最终接收地址
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    /// @dev 精确输入代币数量交换为精确输出代币数量
    /// @param amountIn 输入代币数量
    /// @param amountOutMin 最小输出数量
    /// @param path 交易路径
    /// @param to 接收地址
    /// @param deadline 交易截止时间
    /// @return amounts 每个步骤的代币数量
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    /// @dev 精确输出代币数量交换为最多输入代币数量
    /// @param amountOut 期望输出数量
    /// @param amountInMax 最大输入数量
    /// @param path 交易路径
    /// @param to 接收地址
    /// @param deadline 交易截止时间
    /// @return amounts 每个步骤的代币数量
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    /// @dev 精确ETH数量交换为精确代币数量
    /// @param amountOutMin 最小输出数量
    /// @param path 交易路径
    /// @param to 接收地址
    /// @param deadline 交易截止时间
    /// @return amounts 每个步骤的代币数量
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    /// @dev 精确代币数量交换为精确ETH数量
    /// @param amountOut 期望输出ETH数量
    /// @param amountInMax 最大输入代币数量
    /// @param path 交易路径
    /// @param to 接收地址
    /// @param deadline 交易截止时间
    /// @return amounts 每个步骤的代币数量
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    /// @dev 精确代币数量交换为精确ETH数量
    /// @param amountIn 输入代币数量
    /// @param amountOutMin 最小输出ETH数量
    /// @param path 交易路径
    /// @param to 接收地址
    /// @param deadline 交易截止时间
    /// @return amounts 每个步骤的代币数量
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    /// @dev 精确ETH数量交换为精确代币数量
    /// @param amountOut 期望输出代币数量
    /// @param path 交易路径
    /// @param to 接收地址
    /// @param deadline 交易截止时间
    /// @return amounts 每个步骤的代币数量
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    // **** 交易（支持费用转移代币）****

    /// @dev 内部函数：执行多跳交易（支持费用转移代币）
    /// @param path 交易路径（代币地址数组）
    /// @param _to 最终接收地址
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = UniswapV2Library.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    /// @dev 精确输入代币数量交换为精确输出代币数量（支持费用转移代币）
    /// @param amountIn 输入代币数量
    /// @param amountOutMin 最小输出数量
    /// @param path 交易路径
    /// @param to 接收地址
    /// @param deadline 交易截止时间
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    /// @dev 精确ETH数量交换为精确代币数量（支持费用转移代币）
    /// @param amountOutMin 最小输出数量
    /// @param path 交易路径
    /// @param to 接收地址
    /// @param deadline 交易截止时间
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        uint amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    /// @dev 精确代币数量交换为精确ETH数量（支持费用转移代币）
    /// @param amountIn 输入代币数量
    /// @param amountOutMin 最小输出ETH数量
    /// @param path 交易路径
    /// @param to 接收地址
    /// @param deadline 交易截止时间
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    // **** 库函数 ****

    /// @dev 计算等价值
    /// @param amountA 代币A数量
    /// @param reserveA 代币A储备金
    /// @param reserveB 代币B储备金
    /// @return amountB 代币B等价值
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    /// @dev 计算最大输出数量
    /// @param amountIn 输入数量
    /// @param reserveIn 输入储备金
    /// @param reserveOut 输出储备金
    /// @return amountOut 最大输出数量
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    /// @dev 计算所需输入数量
    /// @param amountOut 期望输出数量
    /// @param reserveIn 输入储备金
    /// @param reserveOut 输出储备金
    /// @return amountIn 所需输入数量
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return UniswapV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    /// @dev 计算多跳输出数量
    /// @param amountIn 输入数量
    /// @param path 交易路径
    /// @return amounts 每个步骤的输出数量
    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    /// @dev 计算多跳输入数量
    /// @param amountOut 期望输出数量
    /// @param path 交易路径
    /// @return amounts 每个步骤的输入数量
    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}
