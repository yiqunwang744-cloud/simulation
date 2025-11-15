# 深入诊断为什么之前的逆转案例都失败了
# 分析边界解、理论违背、数值精度等问题

using Printf
include("ProVer0813.jl")

function diagnose_case(ρ, c₂, σ, desc)
    """深入诊断单个案例的问题"""
    println("\n" * "="^70)
    println("🔬 诊断案例: $(desc)")
    @printf("参数: ρ=%.4f, c₂=%.1e, σ=%.3f\n", ρ, c₂, σ)
    println("="^70)
    
    c₃ = c₂/5
    
    # 尝试不同的边界设置
    boundary_configs = [
        (ηmin=0.01, ηmax=5.0, name="原始边界"),
        (ηmin=0.01, ηmax=10.0, name="扩展上界"),
        (ηmin=0.01, ηmax=20.0, name="大幅扩展"),
        (ηmin=0.001, ηmax=50.0, name="极端扩展")
    ]
    
    for (i, bounds) in enumerate(boundary_configs)
        println("\n$(i). 边界配置: $(bounds.name) - η∈[$(bounds.ηmin), $(bounds.ηmax)]")
        
        try
            m = make_model(μ=0.5, σ=σ, ρ=ρ, 
                          vmin=0.0, vmax=1.0,
                          ηmin=bounds.ηmin, ηmax=bounds.ηmax,
                          c2=c₂, c3=c₃, tol=1e-9)
            
            # 检查成本函数的合理性
            println("   成本函数检查:")
            for η_test in [0.1, 1.0, 5.0, 10.0]
                if η_test <= bounds.ηmax
                    mc = marginal_cost(η_test, m)
                    @printf("     η=%.1f: MC=%.6f\n", η_test, mc)
                    if mc <= 0
                        println("     ⚠️  负边际成本！参数可能有问题")
                    end
                end
            end
            
            # 求解均衡
            println("   均衡求解:")
            ηF, gapF, seF = solve_eta_star_CI(:FPA, m; N=20_000, K=2, max_iter=20)
            ηS, gapS, seS = solve_eta_star_CI(:SPA, m; N=20_000, K=2, seed=11111, max_iter=20)
            
            @printf("     FPA: η*=%.4f, gap=%.1e, se=%.1e\n", ηF, gapF, seF)
            @printf("     SPA: η*=%.4f, gap=%.1e, se=%.1e\n", ηS, gapS, seS)
            
            # 边界解检查
            is_boundary_F = (abs(ηF - bounds.ηmax) < 0.01) || (abs(ηF - bounds.ηmin) < 0.01)
            is_boundary_S = (abs(ηS - bounds.ηmax) < 0.01) || (abs(ηS - bounds.ηmin) < 0.01)
            
            if is_boundary_F
                println("     🚨 FPA碰到边界解！")
            end
            if is_boundary_S
                println("     🚨 SPA碰到边界解！")
            end
            
            # 理论一致性检查
            η_ratio = ηF/ηS
            @printf("     η*比率: %.4f\n", η_ratio)
            
            if η_ratio < 1.0
                println("     ❌ 致命：η*_FPA < η*_SPA 违背理论！")
                
                # 分析原因
                println("     🔍 违背原因分析:")
                
                # 检查边际收益
                mrF = marginal_return(ηF, :FPA, m; N=15_000)
                mrS = marginal_return(ηS, :SPA, m; N=15_000)
                mcF = marginal_cost(ηF, m)
                mcS = marginal_cost(ηS, m)
                
                @printf("       FPA: MR=%.6f, MC=%.6f, MR-MC=%.6f\n", mrF, mcF, mrF-mcF)
                @printf("       SPA: MR=%.6f, MC=%.6f, MR-MC=%.6f\n", mrS, mcS, mrS-mcS)
                
                if mrF < mrS
                    println("       → FPA边际收益更低，违背理论预期")
                end
                
            elseif η_ratio < 1.05
                println("     ⚠️  η*比率接近1，可能存在数值问题")
            else
                println("     ✅ η*排序符合理论")
                
                # 收入检查
                if !is_boundary_F && !is_boundary_S
                    D = make_draws(m; N=25_000, seed=99999, antithetic=true)
                    cacheF = precompute_bids_FPA(ηF, m)
                    RF = revenue(ηF, :FPA, m, D; cacheFPA=cacheF)
                    RS = revenue(ηS, :SPA, m, D)
                    
                    @printf("     收入: F=%.6f, S=%.6f, 比率=%.6f\n", RF, RS, RF/RS)
                    
                    if RF > RS
                        rev_advantage = (RF/RS - 1) * 100
                        @printf("     🎉 收入逆转！FPA高出%.3f%%\n", rev_advantage)
                        
                        if rev_advantage > 0.1  # 至少0.1%的优势
                            println("     ✅ 显著的收入逆转")
                        else
                            println("     ⚠️  逆转幅度可能在噪声范围内")
                        end
                    end
                end
            end
            
        catch e
            println("   ❌ 计算失败: $(e)")
        end
    end
end

function analyze_parameter_space()
    """分析参数空间的问题"""
    println("\n🎯 参数空间合理性分析")
    println("="^70)
    
    # 测试极端参数组合
    extreme_cases = [
        (ρ=0.001, c₂=1e-8, σ=0.01, desc="极低相关性+极低成本+极小方差"),
        (ρ=0.999, c₂=1e-2, σ=0.5, desc="极高相关性+极高成本+极大方差"),
        (ρ=0.5, c₂=1e-5, σ=0.2, desc="中等参数"),
        (ρ=0.1, c₂=1e-4, σ=0.1, desc="温和参数"),
    ]
    
    for case in extreme_cases
        diagnose_case(case.ρ, case.c₂, case.σ, case.desc)
    end
end

function main()
    println("🕵️ 深入诊断收入逆转失败的根本原因")
    println("目标：理解为什么之前的'发现'都是假的")
    
    # 首先分析之前最有希望的几个案例
    println("\n📋 重新审视之前的'最佳'案例")
    
    problem_cases = [
        (ρ=0.028, c₂=3.7e-6, σ=0.159, desc="蒙特卡洛声称的最佳案例"),
        (ρ=0.200, c₂=5.0e-5, σ=0.100, desc="违背理论的极端案例"),
        (ρ=0.010, c₂=1.0e-3, σ=0.100, desc="唯一η*排序正确的案例"),
    ]
    
    for case in problem_cases
        diagnose_case(case.ρ, case.c₂, case.σ, case.desc)
    end
    
    # 然后分析参数空间的合理性
    analyze_parameter_space()
    
    println("\n" * "="^70)
    println("🎯 诊断总结与改进方向")
    println("="^70)
    println("发现的主要问题：")
    println("1. 🎯 边界解：η*经常撞边界，不是真正均衡")
    println("2. 📊 理论违背：某些参数下η*_FPA < η*_SPA")
    println("3. 🔢 数值精度：微小差异可能是计算噪声")
    println("4. 🎪 参数不合理：某些组合可能超出理论框架")
    println("\n改进策略：")
    println("• 动态调整边界，避免边界解")
    println("• 更严格的理论一致性检查")
    println("• 更高的数值精度要求")
    println("• 更系统的参数验证")
    println("="^70)
end

main()

