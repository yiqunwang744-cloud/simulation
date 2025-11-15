# 诊断数值计算中的异常问题
using Printf
include("ProVer0813.jl")

function diagnose_extreme_eta_ratios()
    println("🔬 诊断极端η*比率问题")
    println("="^60)
    
    # 测试有问题的参数设置
    c2_problem = 1e-7
    c3_problem = c2_problem/5
    
    println("问题参数: c₂=1e-7, c₃=2e-8")
    
    m = make_model(μ=0.5, σ=0.4, ρ=0.9, vmin=0.0, vmax=1.0,
                   ηmin=0.01, ηmax=50.0, c2=c2_problem, c3=c3_problem, tol=1e-10)
    
    # 检查成本函数在不同η值下的行为
    println("\n成本函数检查:")
    test_etas = [0.1, 1.0, 3.0, 10.0, 30.0, 45.0]
    
    for η in test_etas
        cost = C_info(η, m)
        mc = MC(η, m)
        @printf("η=%.1f: C(η)=%.2e, MC(η)=%.2e\n", η, cost, mc)
    end
    
    # 手动计算边际收益来检查是否合理
    println("\n手动边际收益检查:")
    
    D = make_draws(m; N=30_000, seed=12345, antithetic=true)
    
    for η_test in [5.0, 10.0, 20.0, 40.0]
        println("\nη = $(η_test):")
        
        # FPA
        mr_fpa = MR_one(η_test, :FPA, m, D, h_frac=0.02)
        mc_val = MC(η_test, m)
        gap_fpa = mr_fpa - mc_val
        @printf("  FPA: MR=%.3e, MC=%.3e, Gap=%.3e\n", mr_fpa, mc_val, gap_fpa)
        
        # SPA  
        mr_spa = MR_one(η_test, :SPA, m, D, h_frac=0.02)
        gap_spa = mr_spa - mc_val
        @printf("  SPA: MR=%.3e, MC=%.3e, Gap=%.3e\n", mr_spa, mc_val, gap_spa)
        
        # 检查是否在边界
        if η_test >= m.ηmax - 1e-3
            println("  ⚠️  接近η上界！")
        end
    end
end

function check_boundary_solutions()
    println("\n🔍 检查边界解问题")
    println("="^50)
    
    c2_test = 1e-7
    c3_test = c2_test/5
    
    m = make_model(μ=0.5, σ=0.4, ρ=0.9, vmin=0.0, vmax=1.0,
                   ηmin=0.01, ηmax=50.0, c2=c2_test, c3=c3_test, tol=1e-10)
    
    # 检查FPA在高η值附近的行为
    println("检查FPA高η值行为:")
    
    D = make_draws(m; N=40_000, seed=99999, antithetic=true)
    
    # 检查η=40-50区间的MR-MC
    for η in [35.0, 40.0, 45.0, 48.0, 49.0, 50.0]
        try
            mr_fpa = MR_one(η, :FPA, m, D, h_frac=0.015)
            mc_val = MC(η, m)
            gap = mr_fpa - mc_val
            
            @printf("η=%.1f: MR=%.3e, MC=%.3e, Gap=%.3e", η, mr_fpa, mc_val, gap)
            
            if abs(gap) < 1e-4
                println(" ← 可能的均衡点")
            elseif gap > 0
                println(" (MR>MC)")
            else
                println(" (MR<MC)")
            end
            
        catch e
            @printf("η=%.1f: 计算错误 %s\n", η, string(e))
        end
    end
    
    # 检查是否FPA的解在边界上
    println("\n角点解检查:")
    
    # 在边界点的一阶条件
    η_boundary = m.ηmax
    mr_boundary = MR_one(η_boundary, :FPA, m, D, h_frac=0.015)
    mc_boundary = MC(η_boundary, m)
    
    @printf("边界点 η=%.1f:\n", η_boundary)
    @printf("  MR = %.3e\n", mr_boundary)
    @printf("  MC = %.3e\n", mc_boundary)
    
    if mr_boundary > mc_boundary + 1e-4
        println("  ⚠️  FPA可能需要更高的η上界！真实均衡可能在边界外")
        
        # 尝试更高的上界
        m_higher = make_model(μ=0.5, σ=0.4, ρ=0.9, vmin=0.0, vmax=1.0,
                              ηmin=0.01, ηmax=100.0, c2=c2_test, c3=c3_test, tol=1e-10)
        
        ηF_higher, gapF_higher, seF_higher = solve_eta_star_CI(:FPA, m_higher; 
                                                               N=40_000, K=3, max_iter=20)
        @printf("  更高边界求解: η*=%.4f, gap=%.3e\n", ηF_higher, gapF_higher)
    end
end

function compare_payoff_magnitudes()
    println("\n💰 期望收益量级比较")
    println("="^50)
    
    # 使用标准参数
    c2_std = 1e-6  
    m_std = make_model(μ=0.5, σ=0.4, ρ=0.9, c2=c2_std, c3=c2_std/5)
    
    # 使用问题参数
    c2_prob = 1e-7
    m_prob = make_model(μ=0.5, σ=0.4, ρ=0.9, c2=c2_prob, c3=c2_prob/5)
    
    D = make_draws(m_std; N=30_000, seed=55555, antithetic=true)
    
    test_etas = [3.0, 10.0, 30.0]
    
    for η in test_etas
        println("\nη = $(η):")
        
        # 标准参数下的期望收益
        eu_fpa_std = EU_gross(η, :FPA, m_std, D)
        eu_spa_std = EU_gross(η, :SPA, m_std, D)
        
        # 问题参数下的期望收益
        eu_fpa_prob = EU_gross(η, :FPA, m_prob, D)
        eu_spa_prob = EU_gross(η, :SPA, m_prob, D)
        
        @printf("  标准参数 (c₂=1e-6): EU_FPA=%.4f, EU_SPA=%.4f\n", eu_fpa_std, eu_spa_std)
        @printf("  问题参数 (c₂=1e-7): EU_FPA=%.4f, EU_SPA=%.4f\n", eu_fpa_prob, eu_spa_prob)
        
        # 成本对比
        cost_std = C_info(η, m_std)
        cost_prob = C_info(η, m_prob)
        @printf("  成本: 标准=%.6f, 问题=%.6f (差异%.1f倍)\n", cost_std, cost_prob, cost_std/cost_prob)
    end
end

function check_spa_vs_fpa_payoff_logic()
    println("\n🧠 SPA vs FPA 收益逻辑检查")
    println("="^50)
    
    # 使用合理的参数
    m = make_model(μ=0.5, σ=0.4, ρ=0.9, c2=1e-6, c3=2e-7)
    
    # 固定一个中等的η值，比较两种机制的期望收益
    η_test = 5.0
    D = make_draws(m; N=50_000, seed=77777, antithetic=true)
    
    println("η = $(η_test) 下的期望收益比较:")
    
    eu_fpa = EU_gross(η_test, :FPA, m, D)
    eu_spa = EU_gross(η_test, :SPA, m, D)
    cost = C_info(η_test, m)
    
    net_fpa = eu_fpa - cost
    net_spa = eu_spa - cost
    
    @printf("总期望收益: EU_FPA=%.4f, EU_SPA=%.4f\n", eu_fpa, eu_spa)
    @printf("信息成本: C(η)=%.6f\n", cost)
    @printf("净期望收益: Net_FPA=%.4f, Net_SPA=%.4f\n", net_fpa, net_spa)
    @printf("FPA vs SPA 收益比: %.4f\n", eu_fpa/eu_spa)
    
    if eu_fpa > eu_spa
        println("✓ FPA期望收益更高（合理，因为FPA激励更多信息获取）")
    else
        println("⚠️ SPA期望收益更高（需要检查）")
    end
    
    # 检查边际收益
    mr_fpa = MR_one(η_test, :FPA, m, D, h_frac=0.02)
    mr_spa = MR_one(η_test, :SPA, m, D, h_frac=0.02)
    mc_val = MC(η_test, m)
    
    @printf("边际收益: MR_FPA=%.3e, MR_SPA=%.3e, MC=%.3e\n", mr_fpa, mr_spa, mc_val)
    
    if mr_fpa > mr_spa
        println("✓ FPA边际收益更高（合理）")
    else
        println("⚠️ SPA边际收益更高（异常）")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    diagnose_extreme_eta_ratios()
    check_boundary_solutions()
    compare_payoff_magnitudes()
    check_spa_vs_fpa_payoff_logic()
end

