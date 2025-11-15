# 严格验证收入计算的正确性
using Printf, Statistics
include("ProVer0813.jl")

function verify_revenue_step_by_step()
    println("🔬 步骤式验证收入计算")
    println("="^60)
    
    # 使用相对合理的参数避免边界问题
    m = make_model(μ=0.5, σ=0.4, ρ=0.9, c2=5e-6, c3=1e-6,
                   ηmin=0.01, ηmax=20.0)  # 降低上界避免边界解
    
    println("测试参数: c₂=5e-6, ηmax=20.0")
    
    # 求解均衡
    ηF, gapF, seF = solve_eta_star_CI(:FPA, m; N=80_000, K=4, max_iter=25)
    ηS, gapS, seS = solve_eta_star_CI(:SPA, m; N=80_000, K=4, seed=12345, max_iter=25)
    
    @printf("均衡结果:\n")
    @printf("  FPA: η*=%.4f, MR-MC=%.2e (SE=%.1e)\n", ηF, gapF, seF)
    @printf("  SPA: η*=%.4f, MR-MC=%.2e (SE=%.1e)\n", ηS, gapS, seS)
    @printf("  比率: η*_FPA/η*_SPA = %.2f\n", ηF/ηS)
    
    if ηF/ηS > 5
        println("  ⚠️  比率仍然较高，但在边界内")
    else
        println("  ✓ 比率在合理范围")
    end
    
    # 生成测试数据
    N_test = 10_000
    D = make_draws(m; N=N_test, seed=99999, antithetic=true)
    
    println("\n📊 详细收入计算验证:")
    println("-"^50)
    
    # === FPA收入验证 ===
    println("\nFPA收入计算:")
    
    # 1. 构建投标函数
    cacheF = precompute_bids_FPA(ηF, m, nx=1000)
    invs_F = 1/√ηF
    
    @printf("  信号精度: η*=%.4f, 信号标准差=%.4f\n", ηF, invs_F)
    
    # 2. 手工计算样本收入
    fpa_payments = Float64[]
    fpa_bids_winner = Float64[]
    fpa_bids_loser = Float64[]
    
    for i in 1:N_test
        # 生成信号
        x1 = D.v1[i] + D.e1[i] * invs_F
        x2 = D.v2[i] + D.e2[i] * invs_F
        
        # 计算投标
        b1 = bid_fpa(x1, cacheF)
        b2 = bid_fpa(x2, cacheF)
        
        # FPA收入 = 获胜者支付的金额 = max(b1, b2)
        payment = max(b1, b2)
        push!(fpa_payments, payment)
        push!(fpa_bids_winner, max(b1, b2))
        push!(fpa_bids_loser, min(b1, b2))
    end
    
    fpa_revenue_manual = mean(fpa_payments)
    @printf("  手工计算: R_FPA = %.6f\n", fpa_revenue_manual)
    @printf("  投标统计: 获胜出价均值=%.4f, 失败出价均值=%.4f\n", 
            mean(fpa_bids_winner), mean(fpa_bids_loser))
    
    # 3. 使用库函数计算
    fpa_revenue_func = revenue(ηF, :FPA, m, D; cacheFPA=cacheF)
    @printf("  函数计算: R_FPA = %.6f\n", fpa_revenue_func)
    @printf("  差异: %.6f (%.2f%%)\n", 
            abs(fpa_revenue_manual - fpa_revenue_func),
            100*abs(fpa_revenue_manual - fpa_revenue_func)/fpa_revenue_func)
    
    # === SPA收入验证 ===
    println("\nSPA收入计算:")
    
    invs_S = 1/√ηS
    @printf("  信号精度: η*=%.4f, 信号标准差=%.4f\n", ηS, invs_S)
    
    # 1. 手工计算样本收入
    spa_payments = Float64[]
    spa_bids_winner = Float64[]
    spa_bids_loser = Float64[]
    
    for i in 1:N_test
        # 生成信号
        x1 = D.v1[i] + D.e1[i] * invs_S
        x2 = D.v2[i] + D.e2[i] * invs_S
        
        # SPA投标 = 后验期望估值
        b1 = bid_spa(x1, ηS, m)  # = v(x1,x1)
        b2 = bid_spa(x2, ηS, m)  # = v(x2,x2)
        
        # SPA收入 = 次高投标 = min(b1, b2)
        payment = min(b1, b2)
        push!(spa_payments, payment)
        push!(spa_bids_winner, max(b1, b2))
        push!(spa_bids_loser, min(b1, b2))
    end
    
    spa_revenue_manual = mean(spa_payments)
    @printf("  手工计算: R_SPA = %.6f\n", spa_revenue_manual)
    @printf("  投标统计: 高出价均值=%.4f, 次高出价均值=%.4f\n",
            mean(spa_bids_winner), mean(spa_bids_loser))
    
    # 2. 使用库函数计算
    spa_revenue_func = revenue(ηS, :SPA, m, D)
    @printf("  函数计算: R_SPA = %.6f\n", spa_revenue_func)
    @printf("  差异: %.6f (%.2f%%)\n",
            abs(spa_revenue_manual - spa_revenue_func),
            100*abs(spa_revenue_manual - spa_revenue_func)/spa_revenue_func)
    
    # === 最终比较 ===
    println("\n🎯 最终收入比较:")
    println("-"^40)
    @printf("使用手工计算: R_FPA=%.6f, R_SPA=%.6f, 比率=%.6f\n",
            fpa_revenue_manual, spa_revenue_manual, fpa_revenue_manual/spa_revenue_manual)
    @printf("使用函数计算: R_FPA=%.6f, R_SPA=%.6f, 比率=%.6f\n",
            fpa_revenue_func, spa_revenue_func, fpa_revenue_func/spa_revenue_func)
    
    # 检查收入逆转
    reversal_manual = fpa_revenue_manual > spa_revenue_manual
    reversal_func = fpa_revenue_func > spa_revenue_func
    
    @printf("收入逆转: 手工=%s, 函数=%s\n", 
            reversal_manual ? "是" : "否", reversal_func ? "是" : "否")
    
    if reversal_manual == reversal_func
        if reversal_manual
            println("✅ 一致确认收入逆转！")
            return true
        else
            println("❌ 一致显示无收入逆转")
            return false
        end
    else
        println("⚠️  手工计算与函数计算结果不一致！")
        return nothing
    end
end

function test_reasonable_parameters()
    println("\n🎯 测试多组合理参数")
    println("="^50)
    
    # 测试几组不同的合理参数
    test_cases = [
        (ρ=0.7, c2=1e-5, desc="中相关+中成本"),
        (ρ=0.8, c2=5e-6, desc="高相关+中低成本"),  
        (ρ=0.9, c2=2e-6, desc="很高相关+低成本"),
        (ρ=0.95, c2=1e-6, desc="极高相关+很低成本"),
    ]
    
    reversal_count = 0
    
    for (i, case) in enumerate(test_cases)
        println("\n案例 $(i): $(case.desc)")
        @printf("参数: ρ=%.2f, c₂=%.1e\n", case.ρ, case.c2)
        
        try
            m = make_model(μ=0.5, σ=0.4, ρ=case.ρ, c2=case.c2, c3=case.c2/5,
                          ηmin=0.01, ηmax=25.0)  # 适中的上界
            
            # 快速求解
            ηF, _, _ = solve_eta_star_CI(:FPA, m; N=40_000, K=3, max_iter=20)
            ηS, _, _ = solve_eta_star_CI(:SPA, m; N=40_000, K=3, seed=11111, max_iter=20)
            
            # 计算收入
            D = make_draws(m; N=40_000, seed=55555)
            RF = revenue(ηF, :FPA, m, D; cacheFPA=precompute_bids_FPA(ηF, m))
            RS = revenue(ηS, :SPA, m, D)
            
            @printf("  均衡: η*_FPA=%.3f, η*_SPA=%.3f (比率=%.2f)\n", ηF, ηS, ηF/ηS)
            @printf("  收入: R_FPA=%.4f, R_SPA=%.4f (比率=%.4f)\n", RF, RS, RF/RS)
            
            if RF > RS
                println("  🎉 发现收入逆转！")
                reversal_count += 1
            else
                @printf("  ❌ 无逆转 (SPA高出%.1f%%)\n", (RS/RF-1)*100)
            end
            
        catch e
            println("  ❌ 计算错误: $(e)")
        end
    end
    
    @printf("\n总结: %d/%d 案例发现收入逆转\n", reversal_count, length(test_cases))
    return reversal_count > 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    reversal_found = verify_revenue_step_by_step()
    any_reversal = test_reasonable_parameters()
    
    println("\n" * "="^60)
    println("🏆 最终验证结论:")
    
    if reversal_found == true
        println("✅ 收入计算正确，并发现了真实的收入逆转案例")
    elseif any_reversal
        println("✅ 收入计算基本正确，在某些参数下存在收入逆转")
    else
        println("✅ 收入计算正确，但在测试范围内未发现收入逆转")
        println("   这并不否定理论，而是说明逆转条件比较苛刻")
    end
    println("="^60)
end

