# 分析信息成本变化对FPA vs SPA的影响
# 检查η*差异和收入计算的合理性

using Printf, Plots
include("ProVer0813.jl")

function analyze_cost_sensitivity()
    println("🔍 信息成本敏感性分析")
    println("="^60)
    
    # 固定其他参数，只变化成本
    base_params = (μ=0.5, σ=0.4, ρ=0.9, vmin=0.0, vmax=1.0, 
                   ηmin=0.01, ηmax=50.0)
    
    # 成本参数范围：从很低到很高
    c2_range = [1e-8, 5e-8, 1e-7, 5e-7, 1e-6, 5e-6, 1e-5, 5e-5, 1e-4]
    
    println("测试成本范围: c₂ ∈ [1e-8, 1e-4]")
    println("固定参数: ρ=0.9, σ=0.4, μ=0.5")
    println()
    
    results = []
    
    for (i, c2) in enumerate(c2_range)
        c3 = c2/5  # 保持比例
        
        @printf("测试 %d/%d: c₂=%.1e\n", i, length(c2_range), c2)
        
        try
            m = make_model(; base_params..., c2=c2, c3=c3, tol=1e-10)
            
            # 求解均衡 - 使用中等精度
            ηF, gapF, seF = solve_eta_star_CI(:FPA, m; N=50_000, K=3, 
                                              h_frac=0.015, tol_abs=5e-5, tol_se=1e-4, max_iter=25)
            ηS, gapS, seS = solve_eta_star_CI(:SPA, m; N=50_000, K=3, seed=12345,
                                              h_frac=0.015, tol_abs=5e-5, tol_se=1e-4, max_iter=25)
            
            # 检查收敛
            converged_F = abs(gapF) < 1e-3 && seF < 1e-3
            converged_S = abs(gapS) < 1e-3 && seS < 1e-3
            
            if !converged_F || !converged_S
                @printf("  ⚠️  收敛性差: |gapF|=%.1e, |gapS|=%.1e\n", abs(gapF), abs(gapS))
                continue
            end
            
            # 计算收入 - 仔细验证
            D = make_draws(m; N=80_000, seed=54321, antithetic=true)
            
            # FPA收入：winner pays own bid
            cacheF = precompute_bids_FPA(ηF, m, nx=800)  # 更精细网格
            RF = revenue(ηF, :FPA, m, D; cacheFPA=cacheF)
            
            # SPA收入：winner pays second-highest bid  
            RS = revenue(ηS, :SPA, m, D)
            
            # 边际成本验证
            mcF = MC(ηF, m)
            mcS = MC(ηS, m)
            
            result = (c2=c2, ηF=ηF, ηS=ηS, RF=RF, RS=RS, 
                     gapF=gapF, gapS=gapS, mcF=mcF, mcS=mcS,
                     ratio_eta=ηF/ηS, ratio_revenue=RF/RS)
            push!(results, result)
            
            @printf("  η*: FPA=%.3f, SPA=%.3f, 比率=%.2f\n", ηF, ηS, ηF/ηS)
            @printf("  收入: FPA=%.4f, SPA=%.4f, 比率=%.4f\n", RF, RS, RF/RS)
            @printf("  MC验证: FPA=%.2e, SPA=%.2e\n", mcF, mcS)
            
            # 异常检查
            if ηF/ηS > 10 || ηF/ηS < 0.8
                println("  ⚠️  η*比率异常！")
            end
            if abs(RF/RS - 1) > 0.5
                println("  ⚠️  收入差异过大！")
            end
            
        catch e
            @printf("  ❌ 错误: %s\n", string(e))
        end
        println()
    end
    
    return results
end

function detailed_revenue_check(c2_test)
    """详细检查特定成本下的收入计算"""
    println("\n🔍 详细收入计算检查")
    println("="^50)
    
    c3_test = c2_test/5
    @printf("检查参数: c₂=%.1e, c₃=%.1e\n", c2_test, c3_test)
    
    m = make_model(μ=0.5, σ=0.4, ρ=0.9, vmin=0.0, vmax=1.0,
                   ηmin=0.01, ηmax=50.0, c2=c2_test, c3=c3_test, tol=1e-10)
    
    # 求解均衡
    ηF, gapF, seF = solve_eta_star_CI(:FPA, m; N=100_000, K=4)
    ηS, gapS, seS = solve_eta_star_CI(:SPA, m; N=100_000, K=4, seed=11111)
    
    @printf("均衡: η*_FPA=%.4f, η*_SPA=%.4f\n", ηF, ηS)
    
    # 手工验证收入计算
    D = make_draws(m; N=20_000, seed=99999, antithetic=true)
    
    println("\n手工收入计算验证:")
    
    # FPA: 检查出价和收入
    cacheF = precompute_bids_FPA(ηF, m)
    invs_F = 1/√ηF
    
    fpa_revenues = Float64[]
    fpa_bids_1 = Float64[]
    fpa_bids_2 = Float64[]
    
    for i in 1:min(1000, length(D.v1))  # 检查前1000个样本
        x1 = D.v1[i] + D.e1[i] * invs_F
        x2 = D.v2[i] + D.e2[i] * invs_F
        b1 = bid_fpa(x1, cacheF)
        b2 = bid_fpa(x2, cacheF)
        
        push!(fpa_bids_1, b1)
        push!(fpa_bids_2, b2)
        push!(fpa_revenues, max(b1, b2))  # 卖方获得最高出价
    end
    
    # SPA: 检查出价和收入
    invs_S = 1/√ηS
    
    spa_revenues = Float64[]
    spa_bids_1 = Float64[]
    spa_bids_2 = Float64[]
    
    for i in 1:min(1000, length(D.v1))
        x1 = D.v1[i] + D.e1[i] * invs_S
        x2 = D.v2[i] + D.e2[i] * invs_S
        b1 = bid_spa(x1, ηS, m)  # b1 = v(x1,x1)
        b2 = bid_spa(x2, ηS, m)  # b2 = v(x2,x2)
        
        push!(spa_bids_1, b1)
        push!(spa_bids_2, b2)
        push!(spa_revenues, min(b1, b2))  # 卖方获得次高出价
    end
    
    @printf("FPA出价统计: 均值=%.4f, 标准差=%.4f, 范围=[%.4f, %.4f]\n", 
            mean(fpa_bids_1), std(fpa_bids_1), minimum(fpa_bids_1), maximum(fpa_bids_1))
    @printf("SPA出价统计: 均值=%.4f, 标准差=%.4f, 范围=[%.4f, %.4f]\n",
            mean(spa_bids_1), std(spa_bids_1), minimum(spa_bids_1), maximum(spa_bids_1))
    
    @printf("FPA收入统计: 均值=%.4f, 标准差=%.4f\n", mean(fpa_revenues), std(fpa_revenues))
    @printf("SPA收入统计: 均值=%.4f, 标准差=%.4f\n", mean(spa_revenues), std(spa_revenues))
    
    # 与函数结果比较
    RF_func = revenue(ηF, :FPA, m, D; cacheFPA=cacheF)
    RS_func = revenue(ηS, :SPA, m, D)
    
    @printf("\n函数计算结果:\n")
    @printf("  R_FPA = %.6f (手工验证: %.6f)\n", RF_func, mean(fpa_revenues))
    @printf("  R_SPA = %.6f (手工验证: %.6f)\n", RS_func, mean(spa_revenues))
    
    # 检查一致性
    if abs(RF_func - mean(fpa_revenues)) > 0.001
        println("⚠️  FPA收入计算可能有问题！")
    end
    if abs(RS_func - mean(spa_revenues)) > 0.001
        println("⚠️  SPA收入计算可能有问题！")
    end
    
    return (RF_func, RS_func, ηF, ηS)
end

function analyze_results(results)
    """分析成本敏感性结果"""
    if length(results) == 0
        println("❌ 没有成功的结果进行分析")
        return
    end
    
    println("📊 成本敏感性分析结果")
    println("="^50)
    
    # 按成本排序
    sort!(results, by=r->r.c2)
    
    println("c₂        | η*_FPA | η*_SPA | 比率  | R_FPA  | R_SPA  | R比率")
    println("-"^65)
    
    for r in results
        @printf("%.1e | %6.2f | %6.2f | %5.2f | %6.4f | %6.4f | %6.4f\n",
                r.c2, r.ηF, r.ηS, r.ratio_eta, r.RF, r.RS, r.ratio_revenue)
    end
    
    # 分析趋势
    println("\n趋势分析:")
    
    # η*比率的变化
    eta_ratios = [r.ratio_eta for r in results]
    @printf("η*比率范围: [%.2f, %.2f]\n", minimum(eta_ratios), maximum(eta_ratios))
    
    if maximum(eta_ratios) > 5
        println("⚠️  发现异常高的η*比率，可能有数值问题")
    end
    
    # 收入差异的变化
    rev_ratios = [r.ratio_revenue for r in results]
    @printf("收入比率范围: [%.4f, %.4f]\n", minimum(rev_ratios), maximum(rev_ratios))
    
    # 检查是否有收入逆转
    reversals = sum(r.RF > r.RS for r in results)
    @printf("收入逆转案例: %d/%d\n", reversals, length(results))
end

if abspath(PROGRAM_FILE) == @__FILE__
    # 第一步：成本敏感性分析
    results = analyze_cost_sensitivity()
    analyze_results(results)
    
    # 第二步：详细检查一个中等成本的案例
    println("\n" * "="^60)
    detailed_revenue_check(1e-6)
end

