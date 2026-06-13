# ExampleOracleSimple 合约说明

## 一、合约概述

`ExampleOracleSimple` 是一个**固定窗口时间加权平均价格（TWAP）预言机**，演示如何使用 Uniswap V2 的累积价格数据来计算 24 小时的平均价格。

**难度级别**：⭐⭐ 中级  
**功能分类**：预言机  
**合约位置**：`contracts/examples/ExampleOracleSimple.sol`

---

## 二、核心业务逻辑

### 2.1 合约架构

```
┌──────────────────────────────────────────────────────┐
│               ExampleOracleSimple                    │
├──────────────────────────────────────────────────────┤
│  常量：                                               │
│  • PERIOD = 24 hours (更新周期)                      │
├──────────────────────────────────────────────────────┤
│  状态变量：                                           │
│  • pair (交易对合约)                                 │
│  • token0, token1 (代币地址)                         │
│  • price0CumulativeLast (上次代币0累积价格)          │
│  • price1CumulativeLast (上次代币1累积价格)          │
│  • blockTimestampLast (上次更新时间戳)               │
│  • price0Average, price1Average (平均价格)           │
├──────────────────────────────────────────────────────┤
│  核心函数：                                           │
│  • update() - 更新平均价格                           │
│  • consult() - 查询价格                              │
└──────────────────────────────────────────────────────┘
```

### 2.2 TWAP 原理

**时间加权平均价格（Time-Weighted Average Price）**：

```
累积价格 = 当前价格 × 时间

如果我们在两个时间点记录累积价格：
  T1: priceCumulative1 = P1 × T1
  T2: priceCumulative2 = P2 × T2

平均价格 = (priceCumulative2 - priceCumulative1) / (T2 - T1)
```

**为什么使用 TWAP？**
- ✅ 防止短期价格操纵
- ✅ 提供更稳定的价格参考
- ✅ 适用于借贷协议等需要可靠价格的场景

### 2.3 核心函数详解

#### ① 构造函数 - 初始化预言机

```solidity
constructor(address factory, address tokenA, address tokenB) public
```

**业务逻辑**：
1. 通过 `UniswapV2Library.pairFor()` 计算配对地址
2. 获取 token0 和 token1 地址
3. 记录当前累积价格：`price0CumulativeLast`、`price1CumulativeLast`
4. 记录当前区块时间戳：`blockTimestampLast`
5. 验证配对中有流动性：`reserve0 != 0 && reserve1 != 0`

**⚠️ 注意**：此预言机是针对特定代币对的，每个代币对需要单独部署一个实例。

---

#### ② update() - 更新平均价格

```solidity
function update() external
```

**业务逻辑流程**：

```
步骤 1：获取当前累积价格
    ↓
    (price0Cumulative, price1Cumulative, blockTimestamp) =
        UniswapV2OracleLibrary.currentCumulativePrices(pair)

步骤 2：计算经过的时间
    ↓
    timeElapsed = blockTimestamp - blockTimestampLast
    要求：timeElapsed >= PERIOD (24小时)

步骤 3：计算平均价格
    ↓
    price0Average = (price0Cumulative - price0CumulativeLast) / timeElapsed
    price1Average = (price1Cumulative - price1CumulativeLast) / timeElapsed

步骤 4：更新状态
    ↓
    price0CumulativeLast = price0Cumulative
    price1CumulativeLast = price1Cumulative
    blockTimestampLast = blockTimestamp
```

**关键检查**：
```solidity
// 确保至少经过了一个完整周期（24小时）
require(timeElapsed >= PERIOD, 'ExampleOracleSimple: PERIOD_NOT_ELAPSED');
```

**计算说明**：
```
累积价格单位：uq112x112 价格 × 秒

例如：
  price0Cumulative 在 T1 = 1000 × 2^112
  price0Cumulative 在 T2 = 2000 × 2^112
  timeElapsed = 86400 秒（24小时）

  price0Average = (2000 - 1000) × 2^112 / 86400
                = 0.01157 × 2^112
                = 平均价格（uq112x112 格式）
```

---

#### ③ consult() - 查询价格

```solidity
function consult(
    address token,       // 查询的代币地址
    uint amountIn        // 输入数量
) external view returns (uint amountOut)  // 输出数量
```

**业务逻辑**：
1. 确定查询的是 token0 还是 token1
2. 使用对应的平均价格计算输出数量
3. 通过 FixedPoint 库的 `decode144()` 转换结果

**⚠️ 注意**：在首次成功调用 `update()` 之前，此函数将始终返回 0。

---

## 三、使用场景

### 场景 1：借贷协议价格预言机

DeFi 借贷协议使用 TWAP 作为抵押品价格参考：

```solidity
// 在借贷协议中
contract LendingProtocol {
    ExampleOracleSimple public priceOracle;
    
    function getCollateralValue(address collateral, uint amount) 
        public view returns (uint value) 
    {
        // 使用 24 小时 TWAP 价格，防止瞬时价格操纵
        value = priceOracle.consult(collateral, amount);
    }
    
    function checkLiquidation(address borrower) public {
        uint collateralValue = getCollateralValue(
            collateralToken, 
            getCollateralBalance(borrower)
        );
        uint debtValue = getDebtValue(borrower);
        
        // 如果抵押品价值 < 债务的 150%，触发清算
        if (collateralValue < debtValue.mul(150).div(100)) {
            liquidate(borrower);
        }
    }
}
```

### 场景 2：稳定币协议

稳定币协议使用 TWAP 来调整发行和赎回价格：

```javascript
// 稳定币协议示例
class StablecoinProtocol {
    async getMintPrice() {
        // 使用 TWAP 价格计算铸造数量
        const twapPrice = await oracle.consult(COLLATERAL_TOKEN, amountIn);
        return this.calculateMintAmount(twapPrice);
    }
}
```

### 场景 3：去中心化指数基金

指数基金使用 TWAP 来计算资产权重：

```javascript
// 指数基金重新平衡
async function rebalance() {
    // 获取每个资产的 TWAP 价格
    for (const token of indexTokens) {
        const twapPrice = await oracle.consult(token, unitAmount);
        prices[token] = twapPrice;
    }
    
    // 根据 TWAP 价格计算目标权重并重新平衡
    await executeRebalance(prices);
}
```

---

## 四、技术要点

### 4.1 累积价格机制

Uniswap V2 配对合约维护两个累积价格变量：

```solidity
// 在 UniswapV2Pair 合约中
uint price0CumulativeLast;  // 代币0的累积价格（代币1/代币0）
uint price1CumulativeLast;  // 代币1的累积价格（代币0/代币1）
```

**更新时机**：
- 每次发生交易时（`swap()` 被调用）
- 如果自上次交易以来时间已过，在 `getReserves()` 调用时也会更新

**累积价格的计算**：
```
priceCumulative += currentPrice × timeElapsed

currentPrice = reserve1 / reserve0 (对于 price0)
timeElapsed = currentTimestamp - lastTimestamp
```

### 4.2 FixedPoint 格式

Uniswap 使用定点数格式 `uq112x112` 来表示价格：

```
uq112x112 = value × 2^112

例如：
  价格 = 1.5
  uq112x112 表示 = 1.5 × 2^112 = 7786373219937833833436736

转换回小数：
  value = uq112x112_value / 2^112
        = 7786373219937833833436736 / 2^112
        = 1.5
```

**decode144() 函数**：
```
将 uq112x112 格式的乘积结果转换为普通 uint
input: uq112x112 格式的乘积
output: input >> 144 (右移144位)
```

### 4.3 为什么平均价格可能覆盖超过 24 小时？

```
如果 update() 在 24 小时后没有被及时调用：

T0: 上次更新
T1: 24小时后（应该更新）
T2: 30小时后（实际更新）

timeElapsed = T2 - T0 = 30小时
priceAverage = (cumulativePrice[T2] - cumulativePrice[T0]) / 30小时

→ 平均价格实际上覆盖了 30 小时，而不是 24 小时
```

**解决方案**：使用 `ExampleSlidingWindowOracle` 提供更精确的移动平均。

### 4.4 溢出处理

```solidity
uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
```

**为什么需要溢出？**
- 区块时间戳是 `uint256`，但存储在 `uint32` 中
- 当 `blockTimestampLast` 接近 `2^32-1` 时会发生回绕
- 减法溢出是预期的，确保在回绕后仍然正确计算时间差

---

## 五、与滑动窗口预言机对比

| 特性 | ExampleOracleSimple | ExampleSlidingWindowOracle |
|------|---------------------|----------------------------|
| 更新频率 | 每 24 小时 | 每 `windowSize/granularity` |
| 精度 | 固定 24 小时窗口 | 可配置窗口和粒度 |
| 部署方式 | 每对部署一个 | 单例，支持所有配对 |
| 抗操纵性 | 中等 | 高 |
| Gas 成本 | 较低 | 较高 |
| 适用场景 | 简单价格查询 | 需要高精度的场景 |

---

## 六、风险提示

### 6.1 预言机风险

| 风险类型 | 说明 | 影响 |
|----------|------|------|
| 更新不及时 | 依赖外部调用 `update()` | 价格数据过期 |
| 窗口漂移 | 平均价格覆盖时间不固定 | 价格精度下降 |
| 流动性不足 | 低流动性池价格易被操纵 | TWAP 仍可能被长期操纵 |
| 单一数据源 | 仅依赖一个池的价格 | 缺乏冗余验证 |

### 6.2 最佳实践

1. **定期调用 `update()`**：确保价格数据及时更新
2. **监控流动性**：确保池中有足够的流动性
3. **结合其他预言机**：使用多个数据源验证价格
4. **考虑使用滑动窗口**：需要更高精度时使用 `ExampleSlidingWindowOracle`

---

## 七、总结

### 核心功能
1. ✅ 计算 24 小时时间加权平均价格
2. ✅ 使用 Uniswap V2 累积价格机制
3. ✅ 提供抗短期价格操纵的参考
4. ✅ 简单的 API（update + consult）

### 适用场景
- DeFi 借贷协议价格预言机
- 稳定币协议
- 去中心化指数基金
- 需要稳定价格参考的场景

### 学习价值
- 理解 TWAP 原理
- 学习 Uniswap V2 累积价格机制
- 掌握 FixedPoint 定点数运算
- 了解预言机设计模式

---

[← 返回示例合约概览](02_examples_overview.md)  
[→ 查看滑动窗口预言机](06_example_sliding_window_oracle.md)
