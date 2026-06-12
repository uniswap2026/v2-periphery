# Uniswap V2 Periphery 合约架构文档

## 部署

| 网络    | Factory 合约                                 | Router02 合约                                |
| ------- | -------------------------------------------- | -------------------------------------------- |
| Mainnet | `0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f` | `0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D` |
| Sepolia | `0xF62c03E08ada871A0bEb309762E260a7a6a880E6` | `0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3` |

---

## 一、合约主入口点

### 1.1 主要入口合约

Uniswap V2 Periphery 的**主入口点**是路由器合约，用户通过它们与 Uniswap V2 协议进行交互：

| 合约 | 位置 | 角色 | 状态 |
|------|------|------|------|
| **UniswapV2Router02** | `contracts/UniswapV2Router02.sol` | 主入口，推荐使用 | ✅ 生产环境 |
| **UniswapV2Router01** | `contracts/UniswapV2Router01.sol` | 旧版入口 | ⚠️ 已弃用 |
| **UniswapV2Migrator** | `contracts/UniswapV2Migrator.sol` | V1→V2 迁移工具 | ✅ 生产环境 |

**为什么 Router02 是主入口？**
- 继承 Router01 的所有功能
- 添加了对**费用转移代币**（Fee-on-Transfer Tokens）的支持
- 使用 SafeMath 库防止溢出
- 修复了 Router01 中的一个小 bug（`getAmountIn` 调用了错误的函数）

### 1.2 架构层次图

```
┌─────────────────────────────────────────────────────────────┐
│                      用户交互层                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   Router02   │  │   Router01   │  │    Migrator      │  │
│  │  (推荐入口)   │  │  (旧版入口)   │  │  (迁移工具)       │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                      核心逻辑层                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              UniswapV2Library                         │  │
│  │  • 代币排序 • 配对地址计算 • 储备金获取                 │  │
│  │  • 价格计算 • 输入/输出数量计算                         │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                      辅助工具层                              │
│  ┌────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │ SafeMath   │  │ OracleLibrary   │  │LiquidityMathLib │  │
│  │ 安全数学    │  │ 价格预言机       │  │ 流动性价值计算   │  │
│  └────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   Uniswap V2 Core (外部依赖)                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Factory    │  │     Pair     │  │    ERC20     │      │
│  │  工厂合约     │  │   配对合约    │  │   代币合约    │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、核心业务逻辑分类

### 2.1 流动性管理（Liquidity Management）

#### 功能概述
允许用户向交易对池添加或移除流动性，赚取交易手续费。

#### 核心函数

**添加流动性**
```solidity
// 添加两种 ERC20 代币的流动性
function addLiquidity(
    address tokenA,           // 代币A地址
    address tokenB,           // 代币B地址
    uint amountADesired,      // 期望添加的代币A数量
    uint amountBDesired,      // 期望添加的代币B数量
    uint amountAMin,          // 代币A最小数量（滑点保护）
    uint amountBMin,          // 代币B最小数量（滑点保护）
    address to,               // LP代币接收地址
    uint deadline             // 交易截止时间
) returns (uint amountA, uint amountB, uint liquidity)

// 添加 ETH + ERC20 代币的流动性
function addLiquidityETH(
    address token,            // 代币地址
    uint amountTokenDesired,  // 期望添加的代币数量
    uint amountTokenMin,      // 代币最小数量
    uint amountETHMin,        // ETH最小数量
    address to,               // LP代币接收地址
    uint deadline             // 交易截止时间
) payable returns (uint amountToken, uint amountETH, uint liquidity)
```

**移除流动性**
```solidity
// 移除流动性，返回两种代币
function removeLiquidity(
    address tokenA,
    address tokenB,
    uint liquidity,           // 要移除的LP代币数量
    uint amountAMin,          // 代币A最小数量
    uint amountBMin,          // 代币B最小数量
    address to,
    uint deadline
) returns (uint amountA, uint amountB)

// 使用 Permit（无Gas批准）移除流动性
function removeLiquidityWithPermit(
    address tokenA,
    address tokenB,
    uint liquidity,
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline,
    bool approveMax, uint8 v, bytes32 r, bytes32 s  // EIP-2612 签名参数
) returns (uint amountA, uint amountB)
```

#### 业务逻辑流程

**添加流动性流程：**
1. 检查配对是否存在，不存在则创建
2. 获取当前储备金比例
3. 计算最优添加比例（保持储备金比例不变）
4. 检查是否满足最小数量要求（滑点保护）
5. 转移代币到配对合约
6. 调用配对合约的 `mint()` 铸造 LP 代币

**关键设计：**
- **自动创建配对**：如果配对不存在，会自动调用 Factory 创建
- **最优比例计算**：确保添加的代币比例与当前储备金比例一致
- **滑点保护**：通过 `amountAMin` 和 `amountBMin` 防止价格操纵

#### 使用场景

| 场景 | 函数选择 | 示例 |
|------|----------|------|
| 用户想为 DAI/USDC 池提供流动性 | `addLiquidity` | 添加 1000 DAI + 1000 USDC |
| 用户想为 ETH/USDT 池提供流动性 | `addLiquidityETH` | 添加 1 ETH + 3000 USDT |
| 用户想退出流动性池 | `removeLiquidity` | 燃烧 100 LP 代币 |
| 用户想节省 Gas 费用退出 | `removeLiquidityWithPermit` | 使用签名而非 approve |

---

### 2.2 代币交换（Token Swaps）

#### 功能概述
允许用户在不同的 ERC20 代币之间进行交换，支持单跳和多跳交易。

#### 核心函数

**精确输入交换（Exact Input）**
```solidity
// 精确输入代币，交换为另一种代币
function swapExactTokensForTokens(
    uint amountIn,            // 精确的输入数量
    uint amountOutMin,        // 最小输出数量（滑点保护）
    address[] calldata path,  // 交易路径 [tokenA, tokenB, ...]
    address to,               // 输出代币接收地址
    uint deadline             // 交易截止时间
) returns (uint[] memory amounts)

// 精确输入 ETH，交换为代币
function swapExactETHForTokens(
    uint amountOutMin,
    address[] calldata path,  // path[0] 必须是 WETH
    address to,
    uint deadline
) payable returns (uint[] memory amounts)

// 精确输入代币，交换为 ETH
function swapExactTokensForETH(
    uint amountIn,
    uint amountOutMin,
    address[] calldata path,  // path[last] 必须是 WETH
    address to,
    uint deadline
) returns (uint[] memory amounts)
```

**精确输出交换（Exact Output）**
```solidity
// 交换代币以获得精确的输出数量
function swapTokensForExactTokens(
    uint amountOut,           // 精确的输出数量
    uint amountInMax,         // 最大输入数量（滑点保护）
    address[] calldata path,
    address to,
    uint deadline
) returns (uint[] memory amounts)

// 交换代币以获得精确的 ETH
function swapTokensForExactETH(
    uint amountOut,
    uint amountInMax,
    address[] calldata path,
    address to,
    uint deadline
) returns (uint[] memory amounts)

// 使用精确的 ETH 交换代币
function swapETHForExactTokens(
    uint amountOut,
    address[] calldata path,
    address to,
    uint deadline
) payable returns (uint[] memory amounts)
```

#### 业务逻辑流程

**单跳交易流程（Token A → Token B）：**
1. 计算预期输出数量（使用 `getAmountOut`）
2. 检查是否满足最小输出要求
3. 转移输入代币到配对合约
4. 调用配对合约的 `swap()` 执行交易
5. 配对合约验证 `x * y >= k` 不变式

**多跳交易流程（Token A → Token B → Token C）：**
1. 计算每个步骤的预期输出（使用 `getAmountsOut`）
2. 依次执行每个配对的交易
3. 中间代币自动路由到下一个配对
4. 最终代币发送到接收地址

**关键设计：**
- **路径路由**：支持任意长度的交易路径
- **自动路由**：中间配对地址自动计算
- **费用机制**：每笔交易收取 0.3% 手续费（997/1000）

#### 使用场景

| 场景 | 函数选择 | 示例 |
|------|----------|------|
| 用户想用 100 USDC 买 DAI | `swapExactTokensForTokens` | path: [USDC, DAI] |
| 用户想用 1 ETH 买 USDT | `swapExactETHForTokens` | path: [WETH, USDT] |
| 用户想卖出 1000 DAI 换 ETH | `swapExactTokensForETH` | path: [DAI, WETH] |
| 用户想获得精确的 1000 DAI | `swapTokensForExactTokens` | 可能花费 ~1005 USDC |
| 用户想进行跨池交易 | 多跳路径 | path: [USDC, WETH, DAI] |

---

### 2.3 费用转移代币支持（Fee-on-Transfer Tokens）

#### 功能概述
Router02 新增功能，支持在转移时收取费用的代币（如 SafeMoon、Saitama 等）。

#### 核心函数

```solidity
// 支持费用转移代币的交换
function swapExactTokensForTokensSupportingFeeOnTransferTokens(
    uint amountIn,
    uint amountOutMin,
    address[] calldata path,
    address to,
    uint deadline
)

// 支持费用转移代币的 ETH 交换
function swapExactETHForTokensSupportingFeeOnTransferTokens(
    uint amountOutMin,
    address[] calldata path,
    address to,
    uint deadline
) payable

// 支持费用转移代币交换为 ETH
function swapExactTokensForETHSupportingFeeOnTransferTokens(
    uint amountIn,
    uint amountOutMin,
    address[] calldata path,
    address to,
    uint deadline
)

// 支持费用转移代币的流动性移除
function removeLiquidityETHSupportingFeeOnTransferTokens(
    address token,
    uint liquidity,
    uint amountTokenMin,
    uint amountETHMin,
    address to,
    uint deadline
) returns (uint amountETH)
```

#### 与普通交换的区别

| 特性 | 普通交换 | 费用转移代币交换 |
|------|----------|------------------|
| 输入数量计算 | 精确使用 `amountIn` | 检查实际收到的余额 |
| 输出数量验证 | 使用计算的 `amountOut` | 检查接收地址的余额增量 |
| 适用代币 | 标准 ERC20 | 所有代币（包括收费代币） |
| Gas 消耗 | 较低 | 略高（额外的余额查询） |

#### 业务逻辑

**普通交换的问题：**
```solidity
// 假设有 10% 转移费用的代币
TransferHelper.safeTransferFrom(token, msg.sender, pair, 1000);
// 配对合约实际只收到 900 代币，但计算基于 1000
```

**费用转移代币交换的解决方案：**
```solidity
// 转移前记录余额
uint balanceBefore = IERC20(outputToken).balanceOf(to);
// 执行交换
_swapSupportingFeeOnTransferTokens(path, to);
// 检查实际收到的数量
uint actualOutput = IERC20(outputToken).balanceOf(to) - balanceBefore;
require(actualOutput >= amountOutMin, 'INSUFFICIENT_OUTPUT');
```

#### 使用场景

| 场景 | 推荐函数 |
|------|----------|
| 交易 SafeMoon 等收费代币 | `swapExactTokensForTokensSupportingFeeOnTransferTokens` |
| 不确定代币是否收费 | 使用 `SupportingFeeOnTransferTokens` 版本（更安全） |
| 标准代币（如 USDC、DAI） | 使用普通版本（更省 Gas） |

---

### 2.4 价格计算与查询（Price Calculation）

#### 功能概述
提供价格计算工具，帮助用户预估交易结果。

#### 核心函数

**单池价格计算**
```solidity
// 计算等价值（不考虑费用）
function quote(
    uint amountA,
    uint reserveA,
    uint reserveB
) pure returns (uint amountB)

// 计算最大输出数量（含 0.3% 费用）
function getAmountOut(
    uint amountIn,
    uint reserveIn,
    uint reserveOut
) pure returns (uint amountOut)

// 计算所需输入数量（含 0.3% 费用）
function getAmountIn(
    uint amountOut,
    uint reserveIn,
    uint reserveOut
) pure returns (uint amountIn)
```

**多跳价格计算**
```solidity
// 计算多跳交易的输出数量
function getAmountsOut(
    uint amountIn,
    address[] memory path
) view returns (uint[] memory amounts)

// 计算多跳交易所需的输入数量
function getAmountsIn(
    uint amountOut,
    address[] memory path
) view returns (uint[] memory amounts)
```

#### 价格计算公式

**quote（等价值）：**
```
amountB = amountA × reserveB / reserveA
```

**getAmountOut（含费用）：**
```
amountInWithFee = amountIn × 997
numerator = amountInWithFee × reserveOut
denominator = reserveIn × 1000 + amountInWithFee
amountOut = numerator / denominator
```

**getAmountIn（含费用）：**
```
numerator = reserveIn × amountOut × 1000
denominator = (reserveOut - amountOut) × 997
amountIn = numerator / denominator + 1
```

#### 使用场景

| 场景 | 函数选择 | 示例 |
|------|----------|------|
| 前端显示预估输出 | `getAmountsOut` | 输入 100 USDC，显示可获得 ~99.7 DAI |
| 前端显示所需输入 | `getAmountsIn` | 想获得 100 DAI，需要 ~100.3 USDC |
| 计算流动性添加比例 | `quote` | 计算添加 1000 tokenA 需要多少 tokenB |

---

### 2.5 V1 到 V2 迁移（Migration）

#### 功能概述
帮助用户将流动性从 Uniswap V1 迁移到 V2。

#### 核心函数

```solidity
function migrate(
    address token,            // 代币地址
    uint amountTokenMin,      // 最小代币数量
    uint amountETHMin,        // 最小 ETH 数量
    address to,               // 新 LP 代币接收地址
    uint deadline             // 截止时间
)
```

#### 业务逻辑流程

1. 获取用户在 V1 交易所的流动性余额
2. 从用户转移 V1 LP 代币到迁移器
3. 调用 V1 交易所的 `removeLiquidity()` 获取 ETH 和代币
4. 批准路由器使用代币
5. 调用 V2 路由器的 `addLiquidityETH()` 添加到 V2
6. 退还多余的代币或 ETH 给用户

#### 使用场景

| 场景 | 说明 |
|------|------|
| 历史遗留 | 用户在 V1 有流动性，想迁移到 V2 |
| 批量迁移 | 项目方帮助用户迁移流动性 |

**注意：** 此功能主要用于 Uniswap V1→V2 迁移时期，现在使用场景较少。

---

## 三、核心库函数详解

### 3.1 UniswapV2Library

#### 代币排序
```solidity
function sortTokens(address tokenA, address tokenB) 
    pure returns (address token0, address token1)
```
- **作用**：确保代币对顺序一致（按地址大小排序）
- **用途**：配对合约中的 token0/token1 顺序是固定的

#### 配对地址计算（CREATE2）
```solidity
function pairFor(address factory, address tokenA, address tokenB) 
    pure returns (address pair)
```
- **作用**：通过 CREATE2 计算配对合约地址，无需链上查询
- **优势**：节省 Gas，提高安全性
- **原理**：`address = keccak256(0xff + factory + salt + initCodeHash)`

#### 储备金获取
```solidity
function getReserves(address factory, address tokenA, address tokenB) 
    view returns (uint reserveA, uint reserveB)
```
- **作用**：获取并排序配对合约的储备金
- **返回**：按 `tokenA, tokenB` 顺序返回储备金

---

### 3.2 SafeMath

#### 安全数学运算
```solidity
function add(uint x, uint y) pure returns (uint z)
function sub(uint x, uint y) pure returns (uint z)
function mul(uint x, uint y) pure returns (uint z)
```
- **作用**：防止整数溢出和下溢
- **原理**：在运算后检查结果是否合理
- **注意**：Solidity 0.8.0+ 已内置溢出检查，但 V2 使用 0.6.6

---

### 3.3 UniswapV2OracleLibrary

#### 时间加权平均价格（TWAP）
```solidity
function currentCumulativePrices(address pair) 
    view returns (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp)
```
- **作用**：获取累积价格，用于计算 TWAP
- **原理**：累积价格 = 价格 × 时间，通过差值计算平均价格
- **用途**：防止价格操纵的预言机

---

### 3.4 UniswapV2LiquidityMathLibrary

#### 流动性价值计算
```solidity
function getLiquidityValue(
    address factory,
    address tokenA,
    address tokenB,
    uint256 liquidityAmount
) view returns (uint256 tokenAAmount, uint256 tokenBAmount)
```
- **作用**：计算 LP 代币对应的底层代币数量
- **考虑因素**：储备金、总供应量、费用开关

#### 套利后流动性价值
```solidity
function getLiquidityValueAfterArbitrageToPrice(
    address factory,
    address tokenA,
    address tokenB,
    uint256 truePriceTokenA,
    uint256 truePriceTokenB,
    uint256 liquidityAmount
) view returns (uint256 tokenAAmount, uint256 tokenBAmount)
```
- **作用**：计算套利到真实价格后的流动性价值
- **优势**：防止三明治攻击操纵价格
- **用途**：更安全的流动性估值

---

## 四、安全特性

### 4.1 截止时间保护（Deadline Protection）

```solidity
modifier ensure(uint deadline) {
    require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
    _;
}
```
- **作用**：防止交易被矿工延迟执行
- **场景**：用户设置 5 分钟后过期，避免价格变化后仍被执行

### 4.2 滑点保护（Slippage Protection）

```solidity
require(amounts[amounts.length - 1] >= amountOutMin, 'INSUFFICIENT_OUTPUT_AMOUNT');
require(amounts[0] <= amountInMax, 'EXCESSIVE_INPUT_AMOUNT');
```
- **作用**：防止价格操纵导致用户损失
- **场景**：用户设置最大 1% 滑点，超出则交易失败

### 4.3 Permit 功能（EIP-2612）

```solidity
function removeLiquidityWithPermit(
    ...,
    bool approveMax, uint8 v, bytes32 r, bytes32 s
)
```
- **作用**：无需发送 approve 交易即可授权
- **优势**：节省一次交易的 Gas 费用
- **原理**：使用链下签名进行链上验证

### 4.4 安全转移（Safe Transfers）

```solidity
TransferHelper.safeTransferFrom(token, from, to, value);
TransferHelper.safeTransfer(token, to, value);
TransferHelper.safeTransferETH(to, value);
```
- **作用**：处理不标准的 ERC20 代币
- **优势**：兼容返回 bool 和不返回 bool 的代币

---

## 五、合约交互流程

### 5.1 添加流动性完整流程

```
用户 → Router02.addLiquidityETH()
         ↓
    Router02._addLiquidity()
         ↓
    [如果配对不存在] Factory.createPair()
         ↓
    UniswapV2Library.getReserves()
         ↓
    UniswapV2Library.quote() [计算最优比例]
         ↓
    TransferHelper.safeTransferFrom() [转移代币]
         ↓
    IWETH.deposit() [包装 ETH]
         ↓
    IWETH.transfer() [转移 WETH]
         ↓
    Pair.mint() [铸造 LP 代币]
         ↓
    [如果有剩余 ETH] TransferHelper.safeTransferETH() [退还]
```

### 5.2 多跳交易完整流程

```
用户 → Router02.swapExactTokensForTokens(path: [A, B, C])
         ↓
    UniswapV2Library.getAmountsOut() [计算每步输出]
         ↓
    检查 amountOut >= amountOutMin
         ↓
    TransferHelper.safeTransferFrom() [转移 A 到 Pair(A,B)]
         ↓
    Router02._swap()
         ↓
    [第一步] Pair(A,B).swap() [A → B]
         ↓
    [第二步] Pair(B,C).swap() [B → C]
         ↓
    代币 C 到达用户地址
```

---

## 六、最佳实践建议

### 6.1 选择正确的 Router 版本

| 场景 | 推荐版本 | 原因 |
|------|----------|------|
| 新开发项目 | Router02 | 功能更全，支持费用转移代币 |
| 与旧系统集成 | Router01 | 保持兼容性 |
| 不确定代币类型 | Router02 + FeeOnTransfer 版本 | 更安全 |

### 6.2 设置合理的滑点保护

```javascript
// 示例：设置 0.5% 滑点
const amountOutMin = expectedOutput.mul(995).div(1000);
```

### 6.3 设置合理的截止时间

```javascript
// 示例：5 分钟后过期
const deadline = Math.floor(Date.now() / 1000) + 300;
```

### 6.4 使用多跳路径优化价格

```javascript
// 直接路径可能价格差
path: [USDC, DAI]

// 通过 WETH 中转可能更优
path: [USDC, WETH, DAI]
```

---

## 七、总结

### 核心入口点
- **主入口**：`UniswapV2Router02`（推荐）
- **辅助入口**：`UniswapV2Migrator`（V1→V2 迁移）

### 核心业务逻辑
1. **流动性管理**：添加/移除流动性
2. **代币交换**：单跳/多跳交易
3. **费用转移代币支持**：兼容特殊代币
4. **价格计算**：预估交易结果
5. **V1→V2 迁移**：历史迁移工具

### 关键特性
- ✅ 截止时间保护
- ✅ 滑点保护
- ✅ Permit 无 Gas 授权
- ✅ 安全转移
- ✅ CREATE2 地址计算
- ✅ 多跳路由

### 使用场景
- DeFi 应用集成
- 钱包内置交换
- 流动性挖矿
- 价格查询与预估
- 历史数据迁移
