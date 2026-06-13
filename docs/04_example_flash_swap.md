# ExampleFlashSwap 合约说明

## 一、合约概述

`ExampleFlashSwap` 是一个**闪电交换套利合约**，演示如何使用 Uniswap V2 的闪电交换功能，在 V1 和 V2 两个版本之间进行无本金套利。

**难度级别**：⭐⭐⭐⭐ 高级  
**功能分类**：套利策略  
**合约位置**：`contracts/examples/ExampleFlashSwap.sol`

---

## 二、闪电交换原理

### 2.1 什么是闪电交换？

闪电交换（Flash Swap）允许用户**先借后还**：

```
传统交易：                  闪电交换：
1. 先支付代币A              1. 先借入代币B（无抵押）
2. 收到代币B                2. 使用代币B进行其他操作
                           3. 在同一笔交易中归还代币A
                           4. 保留利润
```

**核心特点**：
- ✅ 无需本金即可借入大量代币
- ✅ 必须在同一笔交易中归还
- ✅ 如果无法归还，整个交易回滚
- ✅ 风险极低（失败则回滚，无损失）

### 2.2 合约架构

```
┌──────────────────────────────────────────────────────────┐
│                    ExampleFlashSwap                       │
│  实现 IUniswapV2Callee 接口                               │
├──────────────────────────────────────────────────────────┤
│  状态变量：                                               │
│  • factoryV1 (V1 工厂地址)                               │
│  • factory (V2 工厂地址)                                 │
│  • WETH (WETH 地址)                                     │
├──────────────────────────────────────────────────────────┤
│  核心函数：                                               │
│  • uniswapV2Call() - 闪电交换回调函数                    │
└──────────────────────────────────────────────────────────┘
           ↓                          ↓
┌──────────────────┐    ┌──────────────────┐
│  Uniswap V2 Pair │    │  Uniswap V1      │
│  (借出代币)      │    │  Exchange        │
│                  │    │  (套利交易)      │
└──────────────────┘    └──────────────────┘
```

---

## 三、核心业务逻辑

### 3.1 触发闪电交换

用户需要先调用 V2 配对合约的 `swap()` 函数来触发闪电交换：

```solidity
// 触发闪电交换
IUniswapV2Pair(pairAddress).swap(
    amount0Out,    // 借出的代币0数量
    amount1Out,    // 借出的代币1数量
    to,            // 接收地址（ExampleFlashSwap 合约）
    data           // 额外数据（包含滑点参数）
);
```

### 3.2 uniswapV2Call - 闪电交换回调函数

当闪电交换被触发时，V2 配对合约会调用此函数：

```solidity
function uniswapV2Call(
    address sender,          // 触发闪电交换的调用者
    uint amount0,            // 借出的代币0数量
    uint amount1,            // 借出的代币1数量
    bytes calldata data      // 额外数据（滑点参数）
) external override
```

**业务逻辑流程**：

```
步骤 1：验证调用者
    ↓
    assert(msg.sender == V2 Pair)  // 确保来自真实的 V2 配对
    assert(amount0 == 0 || amount1 == 0)  // 单向借入

步骤 2：确定代币和方向
    ↓
    如果借入的是代币：amountToken > 0, amountETH = 0
    如果借入的是 ETH：amountETH > 0, amountToken = 0

步骤 3：在 V1 上进行套利交易
    ↓
    代币→ETH 路径：
      token.approve(V1 Exchange)
      exchangeV1.tokenToEthSwapInput()
    
    ETH→代币 路径：
      WETH.withdraw()
      exchangeV1.ethToTokenSwapInput()

步骤 4：计算需要偿还的数量
    ↓
    amountRequired = getAmountsIn()  // 计算需要多少输入才能产生借出量

步骤 5：验证利润并偿还
    ↓
    assert(amountReceived > amountRequired)  // 确保有利润
    偿还 V2 配对合约
    将利润转给调用者
```

### 3.3 套利路径详解

#### 路径 A：代币 → ETH（从 V2 借代币，在 V1 卖）

```
┌─────────────────────────────────────────────────────────┐
│                    套利路径：代币→ETH                     │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. 从 V2 借入代币（如 1000 DAI）                        │
│     ↓                                                   │
│  2. 在 V1 卖出代币换 ETH                                 │
│     1000 DAI → 收到 ETH（假设价值 1000.5 DAI）          │
│     ↓                                                   │
│  3. 计算需要偿还的 WETH 数量                             │
│     amountRequired = getAmountsIn(1000 DAI)             │
│     = 需要多少 WETH 才能在 V2 换出 1000 DAI             │
│     ↓                                                   │
│  4. 用收到的 ETH 购买 WETH                               │
│     WETH.deposit{value: amountRequired}()               │
│     ↓                                                   │
│  5. 偿还 V2 WETH                                        │
│     WETH.transfer(V2 Pair, amountRequired)              │
│     ↓                                                   │
│  6. 将剩余 ETH 转给调用者                                │
│     sender.call{value: profit}()                        │
│                                                         │
│  利润 = 收到的ETH - 偿还的WETH                            │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

#### 路径 B：ETH → 代币（从 V2 借 ETH，在 V1 买）

```
┌─────────────────────────────────────────────────────────┐
│                    套利路径：ETH→代币                     │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. 从 V2 借入 WETH（如 1 WETH）                         │
│     ↓                                                   │
│  2. 将 WETH 兑换为 ETH                                   │
│     WETH.withdraw(1 WETH) → 1 ETH                       │
│     ↓                                                   │
│  3. 在 V1 用 ETH 买代币                                  │
│     1 ETH → 收到代币（假设价值 1.0005 WETH）            │
│     ↓                                                   │
│  4. 计算需要偿还的代币数量                               │
│     amountRequired = getAmountsIn(1 WETH)               │
│     = 需要多少代币才能在 V2 换出 1 WETH                 │
│     ↓                                                   │
│  5. 偿还 V2 代币                                        │
│     token.transfer(V2 Pair, amountRequired)             │
│     ↓                                                   │
│  6. 将剩余代币转给调用者                                 │
│     token.transfer(sender, profit)                      │
│                                                         │
│  利润 = 收到的代币 - 偿还的代币                           │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 3.4 关键安全检查

```solidity
// 1. 确保调用者是真实的 V2 配对合约
assert(msg.sender == UniswapV2Library.pairFor(factory, token0, token1));

// 2. 确保是单向借入（只能借一种代币）
assert(amount0 == 0 || amount1 == 0);

// 3. 确保策略只适用于 WETH 配对
assert(path[0] == address(WETH) || path[1] == address(WETH));

// 4. 确保套利利润足够偿还闪电贷款
assert(amountReceived > amountRequired);
```

---

## 四、使用场景

### 场景 1：V1/V2 价格差异套利

当同一代币对在 V1 和 V2 上存在价格差异时：

```javascript
// 假设 DAI/ETH 价格：
// V1: 1 ETH = 3000 DAI
// V2: 1 ETH = 3010 DAI
// 差异：10 DAI

// 触发闪电交换
const data = ethers.utils.defaultAbiCoder.encode(['uint'], [minETH]);

await pair.swap(
    0,                    // 不借 token0
    ethers.utils.parseUnits('1000', 18),  // 借 1000 DAI
    flashSwapContract.address,
    data
);

// 合约自动：
// 1. 借入 1000 DAI
// 2. 在 V1 卖出，获得 0.3333 ETH
// 3. 计算偿还：V2 上 1000 DAI 需要 0.3322 ETH
// 4. 用 0.3322 ETH 买 WETH 偿还 V2
// 5. 利润：0.3333 - 0.3322 = 0.0011 ETH
```

### 场景 2：无本金套利策略

交易者没有本金，但发现套利机会：

```javascript
// 交易者监控到套利机会
// V1 的 DAI 价格偏低，V2 的 DAI 价格偏高

// 无需任何本金，直接触发闪电交换
await flashSwapContract.triggerFlashSwap(
    DAI_ADDRESS,
    WETH_ADDRESS,
    amountToBorrow,
    minProfit
);

// 如果套利成功：获得利润
// 如果套利失败：交易回滚，无损失（仅损失 Gas）
```

### 场景 3：自动套利机器人

集成到自动套利机器人中：

```javascript
class ArbitrageBot {
    async checkOpportunity() {
        // 监控 V1 和 V2 的价格差异
        const v1Price = await this.getV1Price();
        const v2Price = await this.getV2Price();
        
        // 计算扣除费用后的利润
        const profit = this.calculateProfit(v1Price, v2Price);
        
        // 如果利润 > Gas 成本，执行套利
        if (profit > gasCost) {
            await this.executeFlashSwap();
        }
    }
}
```

---

## 五、技术要点

### 5.1 闪电交换的偿还机制

闪电交换的偿还不是直接归还借入的代币，而是归还**等值的另一种代币**：

```
借入：1000 DAI
归还：等值的 WETH（按 V2 的价格计算）

计算方式：
amountRequired = getAmountsIn(factory, 1000, [WETH, DAI])[0]
= 在 V2 上，需要多少 WETH 才能换出 1000 DAI
```

### 5.2 套利利润来源

利润来自 V1 和 V2 的价格差异：

```
V1 价格：1 ETH = 3000 DAI
V2 价格：1 ETH = 3010 DAI

套利操作：
1. 从 V2 借 1000 DAI
2. 在 V1 卖出：1000 / 3000 = 0.3333 ETH
3. V2 需要偿还：1000 / 3010 = 0.3322 ETH（约）
4. 利润：0.3333 - 0.3322 = 0.0011 ETH
```

### 5.3 滑点保护

调用者通过 `data` 参数传入滑点保护值：

```javascript
// 设置最小接受的 ETH 数量（防止滑点过大）
const minETH = expectedETH.mul(99).div(100); // 1% 滑点

// 编码到 data 中
const data = ethers.utils.defaultAbiCoder.encode(['uint'], [minETH]);
```

---

## 六、风险提示

### 6.1 套利风险

| 风险类型 | 说明 | 影响 |
|----------|------|------|
| 价格变化 | 交易执行期间价格变化 | 可能导致亏损，交易回滚 |
| Gas 成本 | 套利失败仍需支付 Gas | 损失 Gas 费用 |
| 竞争 | 其他机器人抢先执行 | 失去套利机会 |
| MEV | 矿工/验证者提取价值 | 利润被截获 |

### 6.2 合约限制

- ⚠️ 仅支持包含 WETH 的配对
- ⚠️ 仅支持单向借入（不能同时借两种代币）
- ⚠️ 依赖 V1 交易所的存在和流动性
- ⚠️ 示例合约，未经审计，不建议用于生产环境

---

## 七、总结

### 核心功能
1. ✅ 无抵押借入大量代币
2. ✅ V1/V2 跨版本套利
3. ✅ 自动计算利润并偿还
4. ✅ 失败则自动回滚

### 适用场景
- V1/V2 价格差异套利
- 无本金套利策略
- 自动套利机器人
- DeFi 策略研究

### 学习价值
- 理解闪电交换机制
- 学习跨版本套利策略
- 掌握套利利润计算方法
- 了解 MEV 和套利竞争

---

[← 返回示例合约概览](02_examples_overview.md)
