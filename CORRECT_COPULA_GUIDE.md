# 正确的Copula实现 - 使用指南

## 概述

这是**理论上正确**的copula实现，修复了之前实现的所有根本性缺陷。

## 与错误实现的关键区别

### ❌ 错误实现（已废弃）

```julia
# 文件：copula_affiliation_extension.jl
# 问题：使用线性高斯后验公式

function posterior_value_copula(x, η, m, D)
    weight = prior_var / (prior_var + signal_var)
    E_v = m.μ + weight * (x - m.μ)  # ❌ 只对Normal有效！
    return E_v
end
```

**后果：**
- Clayton/Gumbel的非线性尾部依赖完全丢失
- 90个"copula"测试实际等同于Bivariate Normal
- 0个reversals（预期结果，因为根本没测试copula）

### ✅ 正确实现（当前）

```julia
# 文件：copula_correct_implementation.jl + copula_correct_part2.jl

function conditional_expectation_correct(x, η, m)
    # 计算 E[V|X=x] = ∫ v · f_{V|X}(v|x) dv
    # 其中 f_{V|X}(v|x) = c(F_V(v), F_X(x)) · f_V(v) / f_X(x)
    # c 是copula密度

    function integrand(v)
        u_v = cdf(Normal(m.μ, m.σ), v)
        u_x = cdf(Normal(m.μ, σ_x), x)

        # 使用真实的copula密度
        if m.copula_type == :clayton
            c = clayton_density(u_v, u_x, m.θ)  # ✓ 非线性！
        else
            c = gumbel_density(u_v, u_x, m.θ)   # ✓ 非线性！
        end

        return v * c * pdf(Normal(m.μ, m.σ), v) / f_x
    end

    # 数值积分
    result, err = quadgk(integrand, v_low, v_high)
    return result / normalizer
end
```

**关键改进：**

1. **真实的copula条件期望**（不是线性公式）
   - Clayton: 下尾更陡，上尾更平
   - Gumbel: 上尾更陡，下尾更平
   - 非对称性被正确捕捉

2. **正确的Gumbel采样**
   - 使用稳定分布（Stable distribution）
   - 不是Gamma近似

3. **经验hazard rate**
   - h(x) = f(x)/(1-F(x)) 从数据计算
   - 不是常数

4. **高质量kernel density**
   - Epanechnikov kernel
   - 自适应带宽

## 计算代价

### 错误实现
- 每个测试：~5-6分钟
- 90个组合：~8分钟总计

### 正确实现
- **每个测试：30-60分钟** ⚠️
- 原因：
  - 每次计算E[V|X=x]需要数值积分（~100次函数评估）
  - 每个FPA投标ODE有150个网格点 → 15,000次积分
  - 每个MR计算需要4-5个FPA解 → 75,000次积分
  - 每个均衡需要10-25次MR计算 → 数百万次积分

**预期总时间：**
- 默认设置（15个组合）：**6-15小时**
- 如果扩展到50个组合：**25-50小时**

## 使用方法

### 快速测试单个配置

```julia
include("copula_correct_part2.jl")

# 测试Clayton强下尾依赖
result = test_reversal_correct(:clayton, 4.0, 0.4, c2=1e-6, N=40000)

# 检查结果
if result.reversal
    println("找到reversal!")
    println("FPA revenue: ", result.R_FPA)
    println("SPA revenue: ", result.R_SPA)
    println("Ratio: ", result.ratio)
end
```

**预期时间：** 30-60分钟

### 小规模搜索

```julia
# 测试最有希望的配置
results = search_copula_correct(
    copula_types = [:clayton],        # 只测Clayton
    θ_clayton = [2.0, 4.0],           # 强下尾依赖
    σ_range = [0.4, 0.5],             # 中等不确定性
    c2_range = [1e-6],                 # 标准成本
    N = 40000
)
# 4个组合，预期时间：2-4小时
```

### 完整搜索

```julia
# 全面测试（谨慎使用！）
results = search_copula_correct(
    copula_types = [:clayton, :gumbel],
    θ_clayton = [1.0, 2.0, 4.0, 8.0],
    θ_gumbel = [1.5, 2.0, 3.0],
    σ_range = [0.3, 0.4, 0.5],
    c2_range = [1e-6, 5e-7],
    N = 40000
)
# 30个组合，预期时间：15-30小时！
```

## 最优策略建议

### 第一阶段：验证实现（1-2小时）

```julia
# 测试1个Clayton配置，确保代码运行正确
test_reversal_correct(:clayton, 2.0, 0.4, N=40000)
```

**目的：** 确保没有bug，数值积分收敛

### 第二阶段：高潜力区域（4-6小时）

```julia
# 测试最有理论依据的配置
search_copula_correct(
    copula_types = [:clayton],
    θ_clayton = [2.0, 4.0, 8.0],     # 递增的下尾依赖
    σ_range = [0.4, 0.5],             # 中高不确定性
    c2_range = [1e-6],
    N = 40000
)
# 6个组合
```

**理由：**
- Clayton强下尾 = 低值区域winner's curse强
- σ较高 = 信息valuable
- 这是最可能产生reversal的区域

### 第三阶段（如果第二阶段无果）：Gumbel测试（3-4小时）

```julia
search_copula_correct(
    copula_types = [:gumbel],
    θ_gumbel = [2.0, 3.0],
    σ_range = [0.4, 0.5],
    N = 40000
)
# 4个组合
```

### 第四阶段（如果仍无果）：扩展参数（8-12小时）

```julia
# 测试更极端的参数
search_copula_correct(
    copula_types = [:clayton],
    θ_clayton = [6.0, 8.0, 10.0],    # 极强下尾
    σ_range = [0.5, 0.6, 0.7],        # 高不确定性
    c2_range = [5e-7, 1e-7],          # 更低成本
    N = 40000
)
```

## 理论预测

### Clayton θ=4, σ=0.5 最有希望

**机制：**

1. **强下尾依赖** (θ=4 → λ_L = 0.80)
   - 当V_1, V_2都低时，高度相关
   - 低值bidder面临严重winner's curse
   - E[V_i | X_i=x, win] >> x 当x较低时

2. **信息价值非线性增加**
   - 在低值区域，精确信号大幅减少winner's curse
   - FPA bidders更愿意投资信息
   - η*_FPA可能显著高于η*_SPA

3. **可能的均衡：**
   - FPA: η* ≈ 3-5 (高精度)
   - SPA: η* ≈ 1-2 (中等精度)
   - FPA的高信息+低bid shading可能胜过SPA的linkage

### Gumbel θ=3, σ=0.5 次优

**机制：**
- 强上尾依赖 (λ_U = 0.79)
- 竞争在高值区域最激烈
- FPA信息优势在竞争区域放大

但上尾机制通常对revenue影响较小（大多数交易在中低值）。

## 诊断输出

运行时你会看到：

```
======================================================================
Testing clayton copula: θ=4.00, σ=0.40
======================================================================
Generating draws...
  Solving FPA equilibrium...
    Iteration 1: η=5.005
    Computing FPA bids at η=4.905...
    Computing FPA bids at η=4.955...
    Computing FPA bids at η=5.055...
    Computing FPA bids at η=5.105...
      MR=0.0034, MC=0.0028, gap=0.0006
    Iteration 2: η=5.127
    ...
    ✓ Converged!
  Solving SPA equilibrium...
    ...
Computing revenues...
======================================================================
RESULTS:
  FPA: η*=5.234, R=0.3456
  SPA: η*=2.123, R=0.3512
  Ratio: 0.9841 (no reversal)
======================================================================
```

## 如果找到Reversal

立即：
1. **保存结果**
2. **重新运行N=80000验证**
3. **测试周围参数（fine grid）**
4. **分析机制**：为什么这个参数组合产生reversal？

## 如果所有测试都无Reversal

那么结论是：
> Krishna-Morgan revenue ranking在Persico框架下极其稳健，即使引入非对称尾部依赖（通过copulas）也无法reverse。

这本身是**重要的理论贡献**。

## 计算资源建议

- **CPU:** 单核即可（代码未并行化）
- **内存:** 2-4 GB足够（N=40000）
- **时间:** 预留完整的24小时连续运行窗口
- **监控:** 保存中间结果以防中断

---

**准备好了吗？运行 `search_copula_correct()` 开始寻找reversals！**
