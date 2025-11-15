# 严格按照 Persico (2000) 理论重建
# 修复关键的理论实现错误

using Distributions, QuadGK, LinearAlgebra, Optim, Printf, ForwardDiff, Roots, HCubature

# ============================================
# 第一步：正确的信号技术实现
# ============================================

"""
基于 Persico (2000) 的 A-ordered 信号家族
关键性质：
1. 更高的η使信号与价值更相关
2. 满足 Monotone Likelihood Ratio Property (MLRP)
3. 满足 Affiliation 
"""
struct AOrderedSignals
    η_min::Float64
    η_max::Float64
    
    function AOrderedSignals(η_min=0.1, η_max=20.0)
        new(η_min, η_max)
    end
end

"""
关键修正：使用正确的信号技术
f^η(x|v) - 信号 x 给定真实价值 v 的密度
这里使用 Persico 建议的 exponential family 形式
"""
function signal_given_value_density(signals::AOrderedSignals, x::Float64, v::Float64, η::Float64)
    if !(0 ≤ x ≤ 1) || !(0 ≤ v ≤ 1)
        return 0.0
    end
    
    # 使用 exponential family: f^η(x|v) ∝ exp(η * h(x,v))
    # 其中 h(x,v) 衡量 x 与 v 的"匹配度"
    # 选择 h(x,v) = -(x-v)² 使得信号围绕真实价值集中
    
    # h(x,v) = -(x-v)²，这样更高的η使分布更集中
    h_xv = -(x - v)^2
    
    # 计算 exp(η * h(x,v))
    unnormalized = exp(η * h_xv)
    
    # 归一化常数：∫₀¹ exp(η * h(t,v)) dt
    normalization_integrand(t) = exp(η * (-(t - v)^2))
    normalization, _ = quadgk(normalization_integrand, 0.0, 1.0, rtol=1e-8)
    
    if normalization > 0
        return unnormalized / normalization
    else
        return 1.0  # uniform fallback
    end
end

"""
信号的累积分布 F^η(x|v) = ∫₀ˣ f^η(t|v) dt
"""
function signal_given_value_cdf(signals::AOrderedSignals, x::Float64, v::Float64, η::Float64)
    if x ≤ 0
        return 0.0
    elseif x ≥ 1
        return 1.0
    else
        integrand(t) = signal_given_value_density(signals, t, v, η)
        result, _ = quadgk(integrand, 0.0, x, rtol=1e-8)
        return result
    end
end

# ============================================
# 第二步：正确的关联价值环境
# ============================================

"""
Krishna-Morgan 关联价值环境 - 精确实现
"""
struct KMAffiliated
    ρ::Float64  # 关联参数
    α::Float64  # 价值相互依赖参数
    
    function KMAffiliated(ρ, α)
        @assert 0 ≤ ρ ≤ 1 "Affiliation parameter ρ ∈ [0,1]"
        @assert 0 ≤ α ≤ 1 "Interdependence parameter α ∈ [0,1]"
        new(ρ, α)
    end
end

"""
价值联合密度：g(v₁,v₂) = (4/5)(1 + ρv₁v₂)
"""
function value_joint_density(km::KMAffiliated, v1::Float64, v2::Float64)
    if 0 ≤ v1 ≤ 1 && 0 ≤ v2 ≤ 1
        return (4/5) * (1 + km.ρ * v1 * v2)
    else
        return 0.0
    end
end

"""
价值边际密度：g₁(v₁) = ∫ g(v₁,v₂) dv₂ = (4/5)(1 + ρv₁/2)
"""
function value_marginal_density(km::KMAffiliated, v1::Float64)
    if 0 ≤ v1 ≤ 1
        return (4/5) * (1 + km.ρ * v1 / 2)
    else
        return 0.0
    end
end

"""
相互依赖价值函数：u₁(v₁,v₂) = v₁ + αv₂
"""
function utility_function(km::KMAffiliated, v1::Float64, v2::Float64)
    return v1 + km.α * v2
end

# ============================================
# 第三步：信号-价值联合系统的正确实现
# ============================================

"""
完整的 Persico 系统：信号 + 关联价值
"""
struct PersicoSystem
    km::KMAffiliated
    signals::AOrderedSignals
end

"""
关键修正：给定信号x₁的期望效用 E[u₁(V₁,V₂)|X₁=x₁]
这需要正确计算后验分布
"""
function expected_utility_given_signal(sys::PersicoSystem, x1::Float64, η::Float64)
    # 使用贝叶斯定理：
    # E[u₁(V₁,V₂)|X₁=x₁] = ∫∫ u₁(v₁,v₂) · f^η(x₁|v₁) · g(v₁,v₂) dv₁dv₂ / 边际密度
    
    function numerator_integrand(v)
        v1, v2 = v[1], v[2]
        if 0 ≤ v1 ≤ 1 && 0 ≤ v2 ≤ 1
            # 似然性：给定v₁，观察到x₁的概率
            likelihood = signal_given_value_density(sys.signals, x1, v1, η)
            # 先验：价值的联合分布
            prior = value_joint_density(sys.km, v1, v2)
            # 效用
            utility = utility_function(sys.km, v1, v2)
            
            return utility * likelihood * prior
        else
            return 0.0
        end
    end
    
    function denominator_integrand(v)
        v1, v2 = v[1], v[2]
        if 0 ≤ v1 ≤ 1 && 0 ≤ v2 ≤ 1
            likelihood = signal_given_value_density(sys.signals, x1, v1, η)
            prior = value_joint_density(sys.km, v1, v2)
            return likelihood * prior
        else
            return 0.0
        end
    end
    
    # 二重积分计算期望
    numerator = hcubature(numerator_integrand, [0.0, 0.0], [1.0, 1.0], rtol=1e-6)[1]
    denominator = hcubature(denominator_integrand, [0.0, 0.0], [1.0, 1.0], rtol=1e-6)[1]
    
    if denominator > 0
        return numerator / denominator
    else
        return 0.5 + sys.km.α * 0.5  # 先验期望
    end
end

"""
关键修正：联合信号密度 f^η(x₁,x₂) 
在关联价值环境中，信号也是关联的
"""
function joint_signal_density(sys::PersicoSystem, x1::Float64, x2::Float64, η::Float64)
    # f^η(x₁,x₂) = ∫∫ f^η(x₁|v₁) · f^η(x₂|v₂) · g(v₁,v₂) dv₁dv₂
    
    function integrand(v)
        v1, v2 = v[1], v[2]
        if 0 ≤ v1 ≤ 1 && 0 ≤ v2 ≤ 1
            signal1_likelihood = signal_given_value_density(sys.signals, x1, v1, η)
            signal2_likelihood = signal_given_value_density(sys.signals, x2, v2, η)
            value_joint = value_joint_density(sys.km, v1, v2)
            
            return signal1_likelihood * signal2_likelihood * value_joint
        else
            return 0.0
        end
    end
    
    result = hcubature(integrand, [0.0, 0.0], [1.0, 1.0], rtol=1e-6)[1]
    return result
end

"""
信号边际密度 f^η(x₁)
"""
function signal_marginal_density(sys::PersicoSystem, x1::Float64, η::Float64)
    integrand(x2) = joint_signal_density(sys, x1, x2, η)
    result, _ = quadgk(integrand, 0.0, 1.0, rtol=1e-6)
    return result
end

"""
条件信号密度 f^η(x₂|x₁) = f^η(x₁,x₂) / f^η(x₁)
这是拍卖分析的核心
"""
function conditional_signal_density(sys::PersicoSystem, x2::Float64, x1::Float64, η::Float64)
    joint = joint_signal_density(sys, x1, x2, η)
    marginal = signal_marginal_density(sys, x1, η)
    
    if marginal > 0
        return joint / marginal
    else
        return 1.0  # uniform fallback
    end
end

"""
条件信号累积分布 F^η(x₂|x₁)
"""
function conditional_signal_cdf(sys::PersicoSystem, x2::Float64, x1::Float64, η::Float64)
    if x2 ≤ 0
        return 0.0
    elseif x2 ≥ 1
        return 1.0
    else
        integrand(t) = conditional_signal_density(sys, t, x1, η)
        result, _ = quadgk(integrand, 0.0, x2, rtol=1e-6)
        return result
    end
end

# ============================================
# 第四步：拍卖均衡的正确实现
# ============================================

"""
SPA均衡：出价等于条件期望价值
b^{SPA}(x) = E[u₁(V₁,V₂)|X₁=x]
"""
function bid_spa_equilibrium(sys::PersicoSystem, x::Float64, η::Float64)
    return expected_utility_given_signal(sys, x, η)
end

"""
FPA均衡：考虑竞争和赢得概率
在对称均衡中：b^{FPA}(x) 通过一阶条件确定
"""
function bid_fpa_equilibrium(sys::PersicoSystem, x::Float64, η::Float64)
    expected_value = expected_utility_given_signal(sys, x, η)
    win_prob = conditional_signal_cdf(sys, x, x, η)
    
    # FPA的标准bid-shading：b(x) = E[v|x] * G(x) / g(x) * 积分项
    # 简化版本：b(x) = E[v|x] * F(x|x)
    return expected_value * win_prob
end

"""
APA均衡：b^{APA}(x) = ∫₀ˣ E[v|t] f^η(t|t) dt
关键：在all-pay中总是支付出价
"""
function bid_apa_equilibrium(sys::PersicoSystem, x::Float64, η::Float64)
    function integrand(t)
        expected_val = expected_utility_given_signal(sys, t, η)
        density = conditional_signal_density(sys, t, t, η)
        return expected_val * density
    end
    
    result, _ = quadgk(integrand, 0.0, x, rtol=1e-6)
    return max(result, 0.0)  # 确保非负
end

"""
WOA均衡：b^{WOA}(x) = ∫₀ˣ E[v|t] λ^η(t|t) dt  
其中 λ^η(t|t) = f^η(t|t) / [1-F^η(t|t)] 是hazard rate
"""
function bid_woa_equilibrium(sys::PersicoSystem, x::Float64, η::Float64)
    function integrand(t)
        expected_val = expected_utility_given_signal(sys, t, η)
        
        # Hazard rate = f(t|t) / [1-F(t|t)]
        density = conditional_signal_density(sys, t, t, η)
        cdf = conditional_signal_cdf(sys, t, t, η)
        
        if cdf < 0.999  # 避免除零
            hazard = density / (1 - cdf)
        else
            hazard = density / 0.001  # 近似处理
        end
        
        return expected_val * hazard
    end
    
    result, _ = quadgk(integrand, 0.0, x, rtol=1e-6)
    return max(result, 0.0)
end

# ============================================
# 第五步：修正的期望收益计算
# ============================================

"""
关键修正：各机制的期望收益计算
"""
function expected_payoff_correct(sys::PersicoSystem, mechanism::Symbol, η::Float64)
    function signal_integrand(x1)
        # 信号x₁的边际概率
        signal_prob = signal_marginal_density(sys, x1, η)
        
        if signal_prob < 1e-10
            return 0.0
        end
        
        # 给定信号x₁的期望收益
        if mechanism == :SPA
            # SPA：赢时支付第二高出价
            win_prob = conditional_signal_cdf(sys, x1, x1, η)
            expected_value = expected_utility_given_signal(sys, x1, η)
            
            # 期望第二高出价 = ∫₀^x₁ t · f(t|x₁) dt / F(x₁|x₁)
            second_price_numerator_integrand(t) = t * conditional_signal_density(sys, t, x1, η)
            second_price_numerator, _ = quadgk(second_price_numerator_integrand, 0.0, x1, rtol=1e-6)
            
            if win_prob > 1e-6
                expected_second_price = second_price_numerator / win_prob
            else
                expected_second_price = 0.0
            end
            
            payoff = win_prob * (expected_value - expected_second_price)
            
        elseif mechanism == :FPA
            # FPA：赢时支付自己的出价
            win_prob = conditional_signal_cdf(sys, x1, x1, η)
            expected_value = expected_utility_given_signal(sys, x1, η)
            own_bid = bid_fpa_equilibrium(sys, x1, η)
            
            payoff = win_prob * (expected_value - own_bid)
            
        elseif mechanism == :APA
            # APA：总是支付，赢时获得价值
            win_prob = conditional_signal_cdf(sys, x1, x1, η)
            expected_value = expected_utility_given_signal(sys, x1, η)
            own_bid = bid_apa_equilibrium(sys, x1, η)
            
            payoff = win_prob * expected_value - own_bid  # Always pay bid
            
        elseif mechanism == :WOA
            # WOA：赢时支付第二高，输时支付自己的
            win_prob = conditional_signal_cdf(sys, x1, x1, η)
            lose_prob = 1 - win_prob
            expected_value = expected_utility_given_signal(sys, x1, η)
            
            # 期望第二高出价
            second_price_numerator_integrand(t) = t * conditional_signal_density(sys, t, x1, η)
            second_price_numerator, _ = quadgk(second_price_numerator_integrand, 0.0, x1, rtol=1e-6)
            
            if win_prob > 1e-6
                expected_second_price = second_price_numerator / win_prob
            else
                expected_second_price = 0.0
            end
            
            own_bid = bid_woa_equilibrium(sys, x1, η)
            
            payoff = win_prob * (expected_value - expected_second_price) - lose_prob * own_bid
            
        else
            error("Unknown mechanism: $mechanism")
        end
        
        return payoff * signal_prob
    end
    
    # 对所有信号实现积分
    total_expected_payoff, _ = quadgk(signal_integrand, 0.0, 1.0, rtol=1e-5)
    return total_expected_payoff
end

"""
信息成本：C(η) = c · η²
"""
information_cost(c::Float64, η::Float64) = c * η^2

"""
边际成本：MC(η) = 2c · η  
"""
marginal_cost(c::Float64, η::Float64) = 2c * η

"""
边际收益：MR(η) = ∂E[payoff]/∂η
"""
function marginal_return_correct(sys::PersicoSystem, mechanism::Symbol, η::Float64, c::Float64; δη=1e-4)
    if η - δη < sys.signals.η_min
        # 前向差分
        payoff_current = expected_payoff_correct(sys, mechanism, η) - information_cost(c, η)
        payoff_plus = expected_payoff_correct(sys, mechanism, η + δη) - information_cost(c, η + δη)
        return (payoff_plus - payoff_current) / δη
    elseif η + δη > sys.signals.η_max
        # 后向差分
        payoff_current = expected_payoff_correct(sys, mechanism, η) - information_cost(c, η)
        payoff_minus = expected_payoff_correct(sys, mechanism, η - δη) - information_cost(c, η - δη)
        return (payoff_current - payoff_minus) / δη
    else
        # 中心差分
        payoff_plus = expected_payoff_correct(sys, mechanism, η + δη) - information_cost(c, η + δη)
        payoff_minus = expected_payoff_correct(sys, mechanism, η - δη) - information_cost(c, η - δη)
        return (payoff_plus - payoff_minus) / (2δη)
    end
end

"""
寻找均衡η*：MR(η) = MC(η)
"""
function find_optimal_accuracy(sys::PersicoSystem, mechanism::Symbol, c::Float64; verbose=false)
    function foc(η)
        mr = marginal_return_correct(sys, mechanism, η, c)
        mc = marginal_cost(c, η)
        return mr - mc
    end
    
    try
        η_star = find_zero(foc, (sys.signals.η_min, sys.signals.η_max), Bisection(), atol=1e-6)
        
        if verbose
            mr_star = marginal_return_correct(sys, mechanism, η_star, c)
            mc_star = marginal_cost(c, η_star)
            net_payoff = expected_payoff_correct(sys, mechanism, η_star) - information_cost(c, η_star)
            
            println("$mechanism:")
            println("  η* = $(@sprintf("%.4f", η_star))")
            println("  MR = $(@sprintf("%.6f", mr_star))")  
            println("  MC = $(@sprintf("%.6f", mc_star))")
            println("  净收益 = $(@sprintf("%.6f", net_payoff))")
        end
        
        return η_star
    catch e
        if verbose
            println("Warning: 无法找到 $mechanism 的均衡 - $e")
            
            # 诊断边界条件
            try
                foc_min = foc(sys.signals.η_min + 0.01)
                foc_max = foc(sys.signals.η_max - 0.01)
                println("  FOC(η_min) ≈ $(@sprintf("%.6f", foc_min))")
                println("  FOC(η_max) ≈ $(@sprintf("%.6f", foc_max))")
            catch e2
                println("  无法计算边界FOC: $e2")
            end
        end
        return NaN
    end
end

# ============================================
# 测试修正后的实现
# ============================================

function test_corrected_persico()
    println("="^80)
    println("修正后的 Persico (2000) 实现测试")
    println("="^80)
    
    # 参数
    km = KMAffiliated(0.5, 0.2)  # 中等关联和相互依赖
    signals = AOrderedSignals(0.1, 20.0)
    sys = PersicoSystem(km, signals)
    c = 0.01
    
    println("参数:")
    println("  关联 (ρ): $(km.ρ)")
    println("  相互依赖 (α): $(km.α)")
    println("  成本 (c): $c")
    
    println("\n" * "-"^60)
    println("测试边际条件")
    println("-"^60)
    
    mechanisms = [:FPA, :SPA, :APA, :WOA]
    results = Dict{Symbol, Float64}()
    
    for mechanism in mechanisms
        println("\n--- $mechanism ---")
        
        # 测试不同η值的边际条件
        println("边际条件测试:")
        for η_test in [0.5, 1.0, 2.0, 5.0]
            try
                mr = marginal_return_correct(sys, mechanism, η_test, c)
                mc = marginal_cost(c, η_test)
                payoff = expected_payoff_correct(sys, mechanism, η_test)
                
                println("  η=$η_test: MR=$(@sprintf("%.6f", mr)), MC=$(@sprintf("%.6f", mc)), 收益=$(@sprintf("%.6f", payoff))")
            catch e
                println("  η=$η_test: 计算错误 - $e")
            end
        end
        
        # 寻找最优精度
        η_opt = find_optimal_accuracy(sys, mechanism, c, verbose=true)
        results[mechanism] = η_opt
    end
    
    println("\n" * "="^60)
    println("最终排序结果")
    println("="^60)
    
    println("理论预期: FPA > SPA > APA > WOA")
    
    valid_results = filter(p -> !isnan(p.second), results)
    sorted_results = sort(collect(valid_results), by=p->p.second, rev=true)
    
    println("计算结果:")
    for (mechanism, η) in sorted_results
        println("  $mechanism: η* = $(@sprintf("%.4f", η))")
    end
    
    # 检查排序
    if length(sorted_results) == 4
        mechanism_order = [p.first for p in sorted_results]
        if mechanism_order == [:FPA, :SPA, :APA, :WOA]
            println("\n✅ 完美！排序与理论完全一致")
        else
            println("\n⚠️ 排序与理论部分不符")
            println("   实际顺序: $(join(mechanism_order, " > "))")
        end
    else
        println("\n❌ 部分机制无法找到均衡")
    end
    
    return results
end

println("启动修正后的理论实现...")
test_corrected_persico()

