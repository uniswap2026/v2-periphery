# Uniswap V2 示例合约概览

## 文件列表

| 文档                                                                           | 合约                         | 功能分类       |
| ------------------------------------------------------------------------------ | ---------------------------- | -------------- |
| [03_example_compute_liquidity_value.md](03_example_compute_liquidity_value.md) | ExampleComputeLiquidityValue | 流动性价值计算 |
| [04_example_flash_swap.md](04_example_flash_swap.md)                           | ExampleFlashSwap             | 闪电交换套利   |
| [05_example_oracle_simple.md](05_example_oracle_simple.md)                     | ExampleOracleSimple          | 固定窗口预言机 |
| [06_example_sliding_window_oracle.md](06_example_sliding_window_oracle.md)     | ExampleSlidingWindowOracle   | 滑动窗口预言机 |
| [07_example_swap_to_price.md](07_example_swap_to_price.md)                     | ExampleSwapToPrice           | 目标价格交换   |

## 功能分类

### 1. 流动性工具（基础）
- **ExampleComputeLiquidityValue** - 计算流动性价值的基础工具

### 2. 套利策略（进阶）
- **ExampleFlashSwap** - 使用闪电交换进行 V1/V2 跨版本套利
- **ExampleSwapToPrice** - 将池价格交换到目标价格

### 3. 预言机（高级）
- **ExampleOracleSimple** - 简单固定窗口 TWAP 预言机
- **ExampleSlidingWindowOracle** - 滑动窗口移动平均价格预言机

## 难度递进

```
基础 → 进阶 → 高级
  │       │       │
  ├───────┤       │
  │ 流动性  │       │
  │ 计算   │       │
  │       ├───────┤
  │       │ 套利   │
  │       │ 策略   │
  │       │       ├──────────┐
  │       │       │ 预言机    │
  └───────┴───────┴──────────┘
```

## ⚠️ 重要提示

这些合约**仅用于演示目的**。虽然包含单元测试，但不保证正确性或安全性。
这些合约**不属于漏洞赏金计划范围**。如需在生产环境中使用，请自行进行审计和测试。

---

[查看详细文档 →](03_example_compute_liquidity_value.md)
