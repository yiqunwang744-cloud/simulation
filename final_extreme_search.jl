# 最后尝试：极端参数条件寻找收入逆转
using Printf
include("ProVer0813.jl")

function test_extreme_cases()
    println("🔬 最终尝试：极端参数条件")
    println("="^60)
    
    # 测试更极端的参数组合
    extreme_cases = [
        # 案例1: 极低相关性 + 极高成本
        (ρ=0.1, c₂=1e-4, c₃=2e-5, σ=0.3, desc="极低相关+极高成本"),
        
        # 案例2: 中低相关性 + 高成本 + 高方差
        (ρ=0.3, c₂=5e-5, c₃=1e-5, σ=0.8, desc="低相关+高成本+高方差"),
        
        # 案例3: 低相关性 + 中等成本 + 极高方差
        (ρ=0.2, c₂=1e-5, c₃=2e-6, σ=1.0, desc="低相关+中等成本+极高方差"),
        
        # 案例4: 极低相关性 + 中等成本
        (ρ=0.05, c₂=2e-5, c₃=4e-6, σ=0.5, desc="极低相关+中等成本"),
    ]
    
    println("测试 $(length(extreme_cases)) 个极端案例...")
    
    any_reversal = false
    
    for (i, case) in enumerate(extreme_cases)
        println("\n" * "-"^50)
        println("案例 $(i): $(case.desc)")
        @printf("参数: ρ=%.3f, c₂=%.1e, σ=%.3f\n", case.ρ, case.c₂, case.σ)
        
        try
            # 创建模型
            m = make_model(μ=0.5, σ=case.σ, ρ=case.ρ, vmin=0.0, vmax=1.0,
                          ηmin=0.01, ηmax=50.0, c2=case.c₂, c3=case.c₃, tol=1e-8)
            
            # 求解均衡 - 使用中等精度快速检查
            ηF, gapF, seF = solve_eta_star_CI(:FPA, m; N=50_000, K=3, 
                                              h_frac=0.02, tol_abs=1e-4, tol_se=1e-4, max_iter=20)
            ηS, gapS, seS = solve_eta_star_CI(:SPA, m; N=50_000, K=3, seed=12345,
                                              h_frac=0.02, tol_abs=1e-4, tol_se=1e-4, max_iter=20)
            
            # 检查收敛
            if abs(gapF) > 1e-3 || abs(gapS) > 1e-3
                println("  ⚠️ 收敛性差，跳过")
                continue
            end
            
            # 计算收入
            D = make_draws(m; N=50_000, seed=54321, antithetic=true)
            cacheF = precompute_bids_FPA(ηF, m)
            RF = revenue(ηF, :FPA, m, D; cacheFPA=cacheF)
            RS = revenue(ηS, :SPA, m, D)
            
            @printf("  均衡: η*_FPA=%.4f, η*_SPA=%.4f (比率=%.2f)\n", ηF, ηS, ηF/ηS)
            @printf("  收入: R_FPA=%.6f, R_SPA=%.6f\n", RF, RS)
            @printf("  比率: R_FPA/R_SPA = %.6f\n", RF/RS)
            
            if RF > RS
                println("  🎉 潜在逆转！需要高精度验证")
                any_reversal = true
                
                # 立即进行高精度验证
                println("  ⚡ 高精度验证中...")
                ηF_hp, gapF_hp, seF_hp = solve_eta_star_CI(:FPA, m; N=150_000, K=5, 
                                                           h_frac=0.01, tol_abs=1e-5, tol_se=5e-6, max_iter=30)
                ηS_hp, gapS_hp, seS_hp = solve_eta_star_CI(:SPA, m; N=150_000, K=5, seed=98765,
                                                           h_frac=0.01, tol_abs=1e-5, tol_se=5e-6, max_iter=30)
                
                D_hp = make_draws(m; N=150_000, seed=11111, antithetic=true)
                cacheF_hp = precompute_bids_FPA(ηF_hp, m)
                RF_hp = revenue(ηF_hp, :FPA, m, D_hp; cacheFPA=cacheF_hp)
                RS_hp = revenue(ηS_hp, :SPA, m, D_hp)
                
                @printf("  高精度结果: R_FPA=%.8f, R_SPA=%.8f, 比率=%.8f\n", RF_hp, RS_hp, RF_hp/RS_hp)
                
                if RF_hp > RS_hp
                    println("  ✅ 确认逆转！")
                    return (found=true, params=case, ηF=ηF_hp, ηS=ηS_hp, RF=RF_hp, RS=RS_hp)
                else
                    println("  ❌ 高精度验证未确认")
                end
            else
                @printf("  ❌ 无逆转 (SPA胜出 %.2f%%)\n", (RS/RF-1)*100)
            end
            
        catch e
            println("  ❌ 计算错误: $(e)")
        end
    end
    
    return (found=false, params=nothing)
end

function theoretical_analysis()
    println("\n📚 理论分析：为什么难以找到逆转？")
    println("="^60)
    
    println("可能的理论解释:")
    println("1. 竞争加剧效应通常占主导:")
    println("   - FPA中更多信息 → 更激烈竞争 → 更高出价 → 更低卖方剩余")
    println("   - 这个效应可能比信息租金减少效应更强")
    
    println("\n2. 支付规则的根本差异:")
    println("   - FPA: 支付自己的出价 (直接受竞争影响)")
    println("   - SPA: 支付对手的出价 (间接受竞争影响)")
    
    println("\n3. 理论文献中的'可能性'条件:")
    println("   - 文献说'it is then possible'，意味着条件性结果")
    println("   - 可能需要非常特殊的参数组合或模型设定")
    
    println("\n4. 数值实现的局限:")
    println("   - 可能需要不同的估值分布(非正态)")
    println("   - 可能需要不同的信号技术")
    println("   - 可能需要多于两个竞标者的设定")
end

if abspath(PROGRAM_FILE) == @__FILE__
    result = test_extreme_cases()
    theoretical_analysis()
    
    println("\n" * "="^60)
    println("🎯 最终结论:")
    if result.found
        println("✅ 找到收入逆转！")
    else
        println("❌ 在广泛的参数扫描后，未能找到显著的收入逆转案例")
        println("   理论预期可能需要本实现未涵盖的特殊条件")
    end
    println("="^60)
end

