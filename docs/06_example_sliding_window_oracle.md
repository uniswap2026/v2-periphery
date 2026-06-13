# ExampleSlidingWindowOracle 合约说明

## 一、合约概述

`ExampleSlidingWindowOracle` 是一个**滑动窗口移动平均价格预言机**，比 `ExampleOracleSimple` 更精确和灵活。它使用多个观察点来计算移动平均价格，支持可配置的窗口大小和粒度。

**难度级别**：⭐⭐⭐⭐ 高级  
**功能分类**：预言机  
**合约位置**：`contracts/examples/ExampleSlidingWindowOracle.sol`

---

## 二、滑动窗口原理

### 2.1 固定窗口 vs 滑动窗口

**固定窗口（ExampleOracleSimple）**：
```
时间线：
|-- 24h --|-- 24h --|-- 24h --|
   窗口1     窗口2     窗口3
```
- 每个窗口独立计算
- 更新时必须等待完整周期
- 平均价格可能覆盖超过 24 小时

**滑动窗口（ExampleSlidingWindowOracle）**：
```
时间线：
|---- 24 小时滑动窗口 ----|
|2h|2h|2h|2h|2h|2h|2h|2h|2h|2h|2h|2h|
 o  o  o  o  o  o  o  o  o  o  o  o
观察点（粒度=12，每个2小时）

窗口随时间移动，始终包含最新的 24 小时数据
```
- 观察点定期更新
- 可以随时查询移动平均价格
- 更精确、更及时

### 2.2 合约架构

```
┌──────────────────────────────────────────────────────────┐
│            ExampleSlidingWindowOracle                    │
├──────────────────────────────────────────────────────────┤
│  状态变量：                                              │
│  • factory (Uniswap V2 工厂地址)                        │
│  • windowSize (窗口大小，如 24 hours)                   │
│  • granularity (粒度，如 24)                            │
│  • periodSize (周期大小 = windowSize / granularity)     │
├──────────────────────────────────────────────────────────┤
│  数据结构：                                              │
│  struct Observation {                                   │
│      uint timestamp;                                    │
│      uint price0Cumulative;                             │
│      uint price1Cumulative;                             │
│  }                                                      │
│                                                         │
│  mapping(address => Observation[]) pairObservations     │
├──────────────────────────────────────────────────────────┤
│  核心函数：                                              │
│  • observationIndexOf() - 计算观察点索引                │
│  • getFirstObservationInWindow() - 获取窗口起始观察点   │
│  • update() - 更新当前周期的观察点                      │
│  • computeAmountOut() - 计算平均价格对应的输出          │
│  • consult() - 查询价格                                 │
└──────────────────────────────────────────────────────────┘
```

---

## 三、核心业务逻辑

### 3.1 参数说明

```solidity
windowSize = 24 hours    // 移动平均的时间窗口
granularity = 24         // 窗口中存储的观察点数量
periodSize = 1 hour      // 每个观察点的时间间隔 = windowSize / granularity
```

**参数影响**：
- 粒度越高 → 需要更频繁的更新 → 但价格更精确
- 窗口越大 → 抗操纵性越强 → 但价格响应越慢

### 3.2 观察点索引计算

```solidity
function observationIndexOf(uint timestamp) public view returns (uint8 index) {
    uint epochPeriod = timestamp / periodSize;
    return uint8(epochPeriod % granularity);
}
```

**工作原理**：
```
假设：windowSize = 24h, granularity = 24, periodSize = 1h

时间轴：
0h  1h  2h  3h  ...  23h  24h  25h  ...
[0] [1] [2] [3] ... [23]  [0]  [1]  ...
                     ↑ 索引回绕

观察点存储在一个固定大小的数组中（大小为 granularity）
当时间超过 windowSize 时，最旧的观察点被覆盖
```

### 3.3 获取窗口起始观察点

```solidity
function getFirstObservationInWindow(address pair) private view 
    returns (Observation storage firstObservation) {
    uint8 observationIndex = observationIndexOf(block.timestamp);
    // 下一个索引就是最旧的观察点（因为数组是循环使用的）
    uint8 firstObservationIndex = (observationIndex + 1) % granularity;
    firstObservation = pairObservations[pair][firstObservationIndex];
}
```

**原理**：
```
当前索引：[5]
数组：    [6] [7] [8] ... [4] [5]
          ↑               ↑
      最旧观察点      最新观察点

下一个索引 (observationIndex + 1) % granularity = 最旧的观察点
```

### 3.4 update() - 更新观察点

```solidity
function update(address tokenA, address tokenB) external
```

**业务逻辑流程**：

```
步骤 1：初始化观察点数组（首次调用）
    ↓
    for (uint i = pairObservations[pair].length; i < granularity; i++) {
        pairObservations[pair].push();
    }

步骤 2：获取当前周期的观察点
    ↓
    uint8 observationIndex = observationIndexOf(block.timestamp);
    Observation storage observation = pairObservations[pair][observationIndex];

步骤 3：检查是否需要更新
    ↓
    uint timeElapsed = block.timestamp - observation.timestamp;
    if (timeElapsed > periodSize) {
        // 更新累积价格和时间戳
        observation.timestamp = block.timestamp;
        observation.price0Cumulative = price0Cumulative;
        observation.price1Cumulative = price1Cumulative;
    }
```

**关键检查**：
```solidity
// 每个周期只更新一次（防止重复更新）
if (timeElapsed > periodSize) {
    // 执行更新
}
```

### 3.5 computeAmountOut() - 计算平均价格输出

```solidity
function computeAmountOut(
    uint priceCumulativeStart,     // 起始累积价格
    uint priceCumulativeEnd,       // 结束累积价格
    uint timeElapsed,              // 经过的时间
    uint amountIn                  // 输入数量
) private pure returns (uint amountOut)
```

**计算公式**：
```
priceAverage = (priceCumulativeEnd - priceCumulativeStart) / timeElapsed
amountOut = priceAverage × amountIn
```

### 3.6 consult() - 查询价格

```solidity
function consult(
    address tokenIn,       // 输入代币
    uint amountIn,         // 输入数量
    address tokenOut       // 输出代币
) external view returns (uint amountOut)
```

**业务逻辑流程**：

```
步骤 1：获取配对地址和窗口起始观察点
    ↓
    address pair = UniswapV2Library.pairFor(factory, tokenIn, tokenOut);
    Observation storage firstObservation = getFirstObservationInWindow(pair);

步骤 2：验证时间范围
    ↓
    uint timeElapsed = block.timestamp - firstObservation.timestamp;
    require(timeElapsed <= windowSize);  // 不能太旧
    require(timeElapsed >= windowSize - periodSize * 2);  // 不能太新

步骤 3：获取当前累积价格并计算输出
    ↓
    (uint price0Cumulative, uint price1Cumulative,) = 
        UniswapV2OracleLibrary.currentCumulativePrices(pair);
    
    if (token0 == tokenIn) {
        return computeAmountOut(firstObservation.price0Cumulative, ...);
    } else {
        return computeAmountOut(firstObservation.price1Cumulative, ...);
    }
```

**时间范围检查**：
```
允许的时间范围：[windowSize - periodSize * 2, windowSize]

例如：windowSize = 24h, periodSize = 1h
允许范围：[22h, 24h]

→ 确保观察点覆盖了接近完整窗口的数据
```

---

## 四、使用场景

### 场景 1：高精度 DeFi 协议预言机

需要高精度价格的大型 DeFi 协议：

```solidity
contract HighPrecisionProtocol {
    ExampleSlidingWindowOracle public oracle;
    
    constructor() public {
        // 部署：24小时窗口，24个观察点（每小时更新一次）
        oracle = new ExampleSlidingWindowOracle(
            factory,
            24 hours,    // windowSize
            24           // granularity
        );
    }
    
    function updatePriceFeed() external {
        // 需要有人定期调用 update
        oracle.update(tokenA, tokenB);
    }
    
    function getPrice(address tokenIn, uint amountIn, address tokenOut) 
        external view returns (uint amountOut) 
    {
        return oracle.consult(tokenIn, amountIn, tokenOut);
    }
}
```

### 场景 2：自动更新机器人

使用机器人定期调用 `update()`：

```javascript
class OracleUpdater {
    async start() {
        // 每 periodSize 时间调用一次 update
        const periodSize = await oracle.periodSize();
        const updateInterval = periodSize.mul(1000); // 转换为毫秒
        
        setInterval(async () => {
            try {
                await oracle.update(tokenA, tokenB);
                console.log('Oracle updated successfully');
            } catch (error) {
                console.error('Update failed:', error);
            }
        }, updateInterval);
    }
}
```

### 场景 3：合成资产协议

合成资产协议需要可靠的价格来铸造和赎回：

```solidity
contract SyntheticAsset {
    ExampleSlidingWindowOracle public oracle;
    
    function mintSynthetic(uint collateralAmount) external {
        // 使用 TWAP 价格计算可铸造的合成资产数量
        uint syntheticAmount = oracle.consult(
            collateralToken,
            collateralAmount,
            syntheticToken
        );
        
        // 铸造合成资产
        _mint(msg.sender, syntheticAmount);
    }
}
```

---

## 五、技术要点

### 5.1 为什么是单例设计？

`ExampleOracleSimple` 需要为每个配对部署一个实例，而 `ExampleSlidingWindowOracle` 是单例：

```solidity
// 单例：一个实例支持所有配对
mapping(address => Observation[]) public pairObservations;
```

**优势**：
- 节省部署成本
- 统一管理
- 共享参数配置

### 5.2 循环数组设计

观察点存储使用循环数组，空间复杂度 O(granularity)：

```
数组大小固定为 granularity
索引计算：timestamp % granularity
最旧数据自动被覆盖
```

**优势**：
- 固定存储成本
- 无需删除旧数据
- Gas 效率高

### 5.3 时间验证机制

```solidity
// 确保有历史观察数据
require(timeElapsed <= windowSize, 'MISSING_HISTORICAL_OBSERVATION');

// 确保观察点不会太新（避免窗口不完整）
require(timeElapsed >= windowSize - periodSize * 2, 'UNEXPECTED_TIME_ELAPSED');
```

**为什么需要两个检查？**
1. 第一个检查：确保有足够旧的历史数据
2. 第二个检查：确保窗口覆盖接近完整的时间范围

### 5.4 与固定窗口的对比示例

```
场景：查询 24 小时平均价格，但 update() 在 30 小时前调用

固定窗口（ExampleOracleSimple）：
- 返回 30 小时的平均价格（不精确）
- 无法拒绝过时的数据

滑动窗口（ExampleSlidingWindowOracle）：
- 有 24 个观察点，覆盖 24 小时
- 如果数据缺失，会 revert（'MISSING_HISTORICAL_OBSERVATION'）
- 确保价格数据的时效性
```

---

## 六、部署和配置指南

### 6.1 参数选择建议

| 场景 | windowSize | granularity | periodSize |
|------|------------|-------------|------------|
| 短期交易 | 1 hour | 12 | 5 minutes |
| 一般 DeFi | 24 hours | 24 | 1 hour |
| 高安全需求 | 7 days | 168 | 1 hour |
| 长期平均 | 30 days | 720 | 1 hour |

### 6.2 部署示例

```javascript
// 部署滑动窗口预言机
const oracle = await deploy('ExampleSlidingWindowOracle', [
    factoryAddress,
    24 * 60 * 60,  // 24 hours in seconds
    24              // granularity
]);

// 初始化观察点（首次调用 update 会创建所有观察点）
await oracle.update(tokenA, tokenB);

// 等待数据积累
// 首次有效查询需要等待 windowSize 时间后
```

### 6.3 维护要求

- ⚠️ 需要定期调用 `update()`（建议每 `periodSize` 调用一次）
- ⚠️ 如果更新间隔过长，历史数据可能丢失
- ⚠️ 首次有效查询需要等待至少一个完整窗口时间

---

## 七、风险提示

### 7.1 预言机风险

| 风险类型 | 说明 | 影响 |
|----------|------|------|
| 更新缺失 | 依赖外部调用 `update()` | 查询失败，数据不可用 |
| Gas 成本 | 频繁更新增加成本 | 维护费用高 |
| 流动性不足 | 池流动性低 | TWAP 仍可能被操纵 |
| 复杂度高 | 合约更复杂 | 潜在 bug 风险更高 |

### 7.2 最佳实践

1. **设置监控**：确保 `update()` 被定期调用
2. **准备回退**：有备用预言机方案
3. **选择合适参数**：根据需求平衡精度和成本
4. **测试边界情况**：测试更新缺失、时间回绕等场景

---

## 八、总结

### 核心功能
1. ✅ 滑动窗口移动平均价格
2. ✅ 可配置窗口大小和粒度
3. ✅ 单例设计，支持所有配对
4. ✅ 循环数组存储，节省 Gas
5. ✅ 严格的时间验证

### 适用场景
- 高精度 DeFi 协议
- 合成资产协议
- 期权/衍生品协议
- 需要精确 TWAP 的场景

### 学习价值
- 理解滑动窗口算法
- 学习循环数组设计模式
- 掌握高精度预言机实现
- 了解时间验证机制

---

[← 返回示例合约概览](02_examples_overview.md)  
[← 查看简单预言机](06_example_oracle_simple.md)
