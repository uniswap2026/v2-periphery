# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 开发命令

### 编译合约
```bash
yarn compile
```

### 运行所有测试
```bash
yarn test
```

### 运行单个测试文件
```bash
yarn test test/UniswapV2Router02.spec.ts
```

### 代码格式化
```bash
yarn lint
```

### 修复代码格式
```bash
yarn lint:fix
```

## 代码架构概览

### 核心合约

**Uniswap V2 Router 系统**包含三个主要生产合约：

1. **UniswapV2Router01** (280行) - 基础路由器，提供基本的流动性添加、移除和交易功能
2. **UniswapV2Router02** (447行) - 扩展版路由器，添加了对费用转移代币的支持
3. **UniswapV2Migrator** (50行) - 用于从V1迁移到V2的流动性迁移器

### 关键库函数

**UniswapV2Library** (83行) - 核心实用函数：
- `sortTokens`: 确定代币顺序
- `pairFor`: 通过CREATE2计算配对地址
- `getReserves`: 获取并排序配对储备
- `quote`: 计算代币等价值
- `getAmountOut/getAmountIn`: 计算交易金额（含0.3%费用）
- `getAmountsOut/getAmountsIn`: 多跳计算

**UniswapV2OracleLibrary** (36行) - 时间加权平均价格(TWAP) oracle工具

**UniswapV2LiquidityMathLibrary** (140行) - 流动性价值计算：
- `computeProfitMaximizingTrade`: 计算套利交易
- `getReservesAfterArbitrage`: 套利后的储备状态
- `computeLiquidityValue`: 流动性价值计算

### 测试架构

使用 **Mocha + TypeScript + Ethereum Waffle** 进行测试：
- 共享fixture系统 (`v2Fixture`) 提供一致的测试环境
- 12秒超时设置
- 支持单文件测试运行
- 包含V1/V2工厂、路由器、流动性迁移器等完整测试环境

### 关键设计模式

1. **接口隔离**: Router01 vs Router02 功能分离
2. **库模式**: 可重用逻辑与主合约分离
3. **CREATE2**: 确定性配对地址生成
4. **WETH集成**: 自动ETH包装/解包
5. **安全特性**: 
   - 截止时间验证
   - 滑点保护
   - Permit功能（无gas批准）
   - 溢出安全数学

### 重要注意事项

- **生产 vs 示例**: 只有Router01、Router02和Migrator是生产合约
- **Router02优势**: 添加了对费用转移代币的支持
- **测试fixture**: `v2Fixture` 提供完整的测试环境设置
- **依赖关系**: 依赖 `@uniswap/v2-core` 核心合约和 `@uniswap/lib` 工具库
- **Solidity版本**: 0.6.6，Istanbul EVM版本，优化器运行999,999次

这个代码库实现了Uniswap V2的去中心化交易所外围合约，专注于提供用户友好的接口与核心V2合约交互。