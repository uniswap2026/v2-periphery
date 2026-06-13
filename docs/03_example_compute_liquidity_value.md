# ExampleComputeLiquidityValue 合约说明

## 一、合约概述

`ExampleComputeLiquidityValue` 是一个**流动性价值计算工具合约**，演示如何使用 `UniswapV2LiquidityMathLibrary` 库来计算流动性池中的代币价值。

**难度级别**：⭐ 基础  
**功能分类**：流动性工具  
**合约位置**：`contracts/examples/ExampleComputeLiquidityValue.sol`

---

## 二、核心业务逻辑

### 2.1 合约结构

```
┌─────────────────────────────────────────────────┐
│         ExampleComputeLiquidityValue            │
├─────────────────────────────────────────────────┤
│  状态变量：                                      │
│  • factory (工厂地址)                            │
├─────────────────────────────────────────────────┤
│  核心函数：                                      │
│  • getReservesAfterArbitrage()                  │
│  • getLiquidityValue()                          │
│  • getLiquidityValueAfterArbitrageToPrice()     │
│  • getGasCostOfGetLiquidityValueAfter...()      │
└─────────────────────────────────────────────────┘
                    ↓ 调用
┌─────────────────────────────────────────────────┐
│      UniswapV2LiquidityMathLibrary              │
├─────────────────────────────────────────────────┤
│  • computeProfitMaximizingTrade()               │
│  • getReservesAfterArbitrage()                  │
│  • computeLiquidityValue()                      │
│  • getLiquidityValue()                          │
│  • getLiquidityValueAfterArbitrageToPrice()     │
└─────────────────────────────────────────────────┘
```

### 2.2 核心函数详解

#### ① getReservesAfterArbitrage - 获取套利后的储备金

**功能**：计算如果套利者将池价格调整到真实市场价格后，池中的储备金状态。

```solidity
function getReservesAfterArbitrage(
    address tokenA,              // 代币A地址
    address tokenB,              // 代币B地址
    uint256 truePriceTokenA,     // 代币A的真实市场价格
    uint256 truePriceTokenB      // 代币B的真实市场价格
) external view returns (
    uint256 reserveA,            // 套利后的代币A储备金
    uint256 reserveB             // 套利后的代币B储备金
)
```

**业务逻辑**：
1. 获取当前池的储备金状态
2. 计算利润最大化交易的方向和数量
3. 模拟执行套利交易
4. 返回套利后的储备金状态

**用途**：预估套利后的池状态，用于更安全的流动性估值。

---

#### ② getLiquidityValue - 获取流动性价值

**功能**：计算指定数量的 LP 代币对应的底层代币数量。

```solidity
function getLiquidityValue(
    address tokenA,              // 代币A地址
    address tokenB,              // 代币B地址
    uint256 liquidityAmount      // LP代币数量
) external view returns (
    uint256 tokenAAmount,        // 对应的代币A数量
    uint256 tokenBAmount         // 对应的代币B数量
)
```

**业务逻辑**：
1. 获取当前池的储备金
2. 获取 LP 代币总供应量
3. 检查是否开启费用机制（feeTo != 0）
4. 如果开启，计算协议费用对总供应量的影响
5. 按比例计算底层代币数量

**计算公式**：
```
tokenAAmount = reserveA × liquidityAmount / totalSupply
tokenBAmount = reserveB × liquidityAmount / totalSupply
```

**⚠️ 注意**：此函数直接使用当前池状态计算，**容易受到三明治攻击等价格操纵**。

---

#### ③ getLiquidityValueAfterArbitrageToPrice - 获取套利后的流动性价值

**功能**：计算如果池被套利到真实市场价格后，LP 代币的价值。

```solidity
function getLiquidityValueAfterArbitrageToPrice(
    address tokenA,              // 代币A地址
    address tokenB,              // 代币B地址
    uint256 truePriceTokenA,     // 代币A的真实价格
    uint256 truePriceTokenB,     // 代币B的真实价格
    uint256 liquidityAmount      // LP代币数量
) external view returns (
    uint256 tokenAAmount,        // 套利后对应的代币A数量
    uint256 tokenBAmount         // 套利后对应的代币B数量
)
```

**业务逻辑**：
1. 模拟套利者将池价格调整到真实市场价格
2. 在套利后的储备金状态下计算流动性价值
3. 返回更抗操纵的估值结果

**与 getLiquidityValue 的区别**：

| 特性 | getLiquidityValue | getLiquidityValueAfterArbitrageToPrice |
|------|-------------------|----------------------------------------|
| 使用场景 | 正常价格查询 | 需要抗价格操纵的场景 |
| 是否需要真实价格 | ❌ 否 | ✅ 是 |
| 抗操纵性 | ❌ 低 | ✅ 高 |
| Gas 消耗 | 较低 | 较高 |

---

#### ④ getGasCostOfGetLiquidityValueAfterArbitrageToPrice - Gas 消耗测试

**功能**：测量 `getLiquidityValueAfterArbitrageToPrice` 函数的 Gas 消耗。

```solidity
function getGasCostOfGetLiquidityValueAfterArbitrageToPrice(
    address tokenA,
    address tokenB,
    uint256 truePriceTokenA,
    uint256 truePriceTokenB,
    uint256 liquidityAmount
) external view returns (uint256)  // 返回 Gas 消耗量
```

**业务逻辑**：
1. 记录调用前的剩余 Gas：`gasleft()`
2. 执行目标函数
3. 记录调用后的剩余 Gas：`gasleft()`
4. 返回差值

**用途**：开发测试时评估函数的 Gas 成本。

---

## 三、使用场景

### 场景 1：钱包显示 LP 代币价值

用户在钱包中持有 LP 代币，想查看对应的底层代币数量：

```javascript
// 用户持有 100 个 DAI-USDC LP 代币
const liquidityAmount = ethers.utils.parseUnits('100', 18);

// 调用合约查询价值
const [tokenAAmount, tokenBAmount] = await exampleContract.getLiquidityValue(
    DAI_ADDRESS,
    USDC_ADDRESS,
    liquidityAmount
);

console.log(`您的 LP 代币价值：${tokenAAmount} DAI + ${tokenBAmount} USDC`);
```

---

### 场景 2：DeFi 协议计算抵押品价值

DeFi 借贷协议需要计算用户抵押的 LP 代币价值，用于确定可借额度：

```solidity
// 在借贷协议中
function calculateCollateralValue(
    address lpToken,
    uint256 amount
) internal view returns (uint256 usdValue) {
    // 获取 LP 代币的底层代币
    (uint256 tokenAAmount, uint256 tokenBAmount) = 
        liquidityCalculator.getLiquidityValue(tokenA, tokenB, amount);
    
    // 转换为 USD 价值
    usdValue = tokenAPriceOracle.getPrice(tokenAAmount) + 
               tokenBPriceOracle.getPrice(tokenBAmount);
}
```

---

### 场景 3：抗操纵的流动性估值

当需要防止三明治攻击操纵价格时，使用套利后的估值：

```javascript
// 从外部预言机获取真实价格
const truePriceDAI = await externalOracle.getPrice(DAI_ADDRESS);
const truePriceUSDC = await externalOracle.getPrice(USDC_ADDRESS);

// 使用抗操纵的估值
const [tokenA, tokenB] = await exampleContract
    .getLiquidityValueAfterArbitrageToPrice(
        DAI_ADDRESS,
        USDC_ADDRESS,
        truePriceDAI,
        truePriceUSDC,
        liquidityAmount
    );
```

---

### 场景 4：套利机会分析

交易者分析池的套利机会：

```javascript
// 获取当前储备金
const [currentReserveA, currentReserveB] = await pair.getReserves();

// 获取套利后的储备金
const [arbReserveA, arbReserveB] = await exampleContract
    .getReservesAfterArbitrage(
        DAI_ADDRESS,
        USDC_ADDRESS,
        truePriceDAI,
        truePriceUSDC
    );

// 计算套利利润
const profitA = currentReserveA.sub(arbReserveA);
const profitB = currentReserveB.sub(arbReserveB);
```

---

## 四、技术要点

### 4.1 为什么需要真实价格？

Uniswap V2 使用恒定乘积公式 `x * y = k`，池内的价格可能偏离真实市场价格。当池价格偏离时：

```
池价格：1 DAI = 0.99 USDC（被操纵）
真实价格：1 DAI = 1.00 USDC

如果直接使用池价格估值：
  100 LP = 99 USDC（低估）

使用真实价格估值：
  100 LP = 100 USDC（准确）
```

### 4.2 费用机制的影响

当 Uniswap 开启协议费用（feeTo != 0）时：

```
kLast < √k 时，协议会铸造新的 LP 代币
→ totalSupply 增加
→ 单个 LP 代币的价值略微稀释
```

`getLiquidityValue` 函数会考虑这个因素，计算更准确的价值。

### 4.3 安全警告

| 风险 | 说明 | 缓解措施 |
|------|------|----------|
| 价格操纵 | 当前池价格可能被操纵 | 使用 `getLiquidityValueAfterArbitrageToPrice` |
| 依赖单一数据源 | 仅使用链上数据 | 结合外部预言机验证 |
| 仅用于参考 | 计算结果是估值，不是实际可提取数量 | 实际提取需考虑滑点和费用 |

---

## 五、总结

### 核心功能
1. ✅ 查询 LP 代币的底层代币价值
2. ✅ 计算套利后的池状态
3. ✅ 提供抗操纵的估值方法
4. ✅ 测量函数 Gas 消耗

### 适用场景
- 钱包显示 LP 代币价值
- DeFi 协议抵押品估值
- 套利机会分析
- 流动性分析工具

### 学习价值
- 理解 LP 代币价值计算原理
- 学习 Uniswap V2 费用机制
- 掌握抗价格操纵的技术
- 了解 Gas 优化方法

---

[← 返回示例合约概览](02_examples_overview.md)
