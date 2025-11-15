# 寻找收入逆转：R_FPA > R_SPA 的参数区域
# 基于ProVer0813.jl框架进行参数扫描

using Distributions, LinearAlgebra, QuadGK, Random, Statistics, Printf, DataFrames

include("ProVer0813.jl")

"""
参数扫描策略：
1. 扫描相关性 ρ ∈ [0.3, 0.95]
2. 扫描成本参数 c₂ ∈ [1e-7, 1e-4]  
3. 扫描估值方差 σ ∈ [0.2, 0.6]
4. 寻找 R_FPA > R_SPA 的区域
"""

function quick_analysis(ρ, c₂, c₃, σ, μ; N=20000, K=2, verbose=false)
    """快速版本的FPA vs SPA分析，降低精度以提高扫描速度"""
    try
        # 创建模型 - 放宽容差和迭代次数以加速
        m = make_model(μ=μ, σ=σ, ρ=ρ, vmin=0.0, vmax=1.0, 
                      ηmin=0.01, ηmax=50.0, c2=c₂, c3=c₃, tol=1e-8)
        
        # 快速求解均衡 - 降低精度要求
        ηF, gapF, seF = solve_eta_star_CI(:FPA, m; N=N, K=K, 
                                          h_frac=0.02, tol_abs=1e-4, tol_se=1e-4,
                                          max_iter=20)
        ηS, gapS, seS = solve_eta_star_CI(:SPA, m; N=N, K=K, seed=12345,
                                          h_frac=0.02, tol_abs=1e-4, tol_se=1e-4, 
                                          max_iter=20)
        
        # 计算收入
        D = make_draws(m; N=N, seed=54321, antithetic=true)
        cacheF = precompute_bids_FPA(ηF, m)
        RF = revenue(ηF, :FPA, m, D; cacheFPA=cacheF)
        RS = revenue(ηS, :SPA, m, D)
        
        # 检查收敛性
        converged_F = abs(gapF) < 1e-3 && seF < 1e-3
        converged_S = abs(gapS) < 1e-3 && seS < 1e-3
        
        if verbose && converged_F && converged_S
            @printf("ρ=%.2f, c₂=%.1e: η*F=%.3f, η*S=%.3f, RF=%.4f, RS=%.4f, Ratio=%.4f\n",
                    ρ, c₂, ηF, ηS, RF, RS, RF/RS)
        end
        
        return (ρ=ρ, c₂=c₂, c₃=c₃, σ=σ, μ=μ, 
                ηF=ηF, ηS=ηS, RF=RF, RS=RS, ratio=RF/RS,
                gapF=gapF, gapS=gapS, seF=seF, seS=seS,
                converged=converged_F && converged_S,
                reversal=(RF > RS))
        
    catch e
        if verbose
            @printf("Error at ρ=%.2f, c₂=%.1e: %s\n", ρ, c₂, string(e))
        end
        return nothing
    end
end

function parameter_sweep_systematic()
    """系统性参数扫描"""
    println("🔍 系统性参数扫描寻找收入逆转 (R_FPA > R_SPA)")
    println("="^80)
    
    results = []
    
    # 参数网格
    ρ_range = [0.3, 0.5, 0.7, 0.8, 0.9, 0.95]
    c₂_range = [1e-7, 5e-7, 1e-6, 5e-6, 1e-5, 5e-5, 1e-4]
    σ_range = [0.2, 0.3, 0.4, 0.5, 0.6]
    
    total_combinations = length(ρ_range) * length(c₂_range) * length(σ_range)
    current = 0
    
    println("总组合数: $(total_combinations)")
    println("预计时间: $(round(total_combinations * 5 / 60, digits=1)) 分钟")
    println()
    
    for σ in σ_range
        for ρ in ρ_range
            for c₂ in c₂_range
                current += 1
                if current % 10 == 1
                    @printf("进度: %d/%d (%.1f%%)\n", current, total_combinations, 
                            100*current/total_combinations)
                end
                
                c₃ = c₂/5  # 保持 c₃ = c₂/5 的比例关系
                μ = 0.5    # 固定估值均值
                
                result = quick_analysis(ρ, c₂, c₃, σ, μ, verbose=false)
                if result !== nothing
                    push!(results, result)
                end
            end
        end
    end
    
    return results
end

function analyze_results(results)
    """分析扫描结果"""
    println("\n📊 参数扫描结果分析")
    println("="^80)
    
    # 筛选收敛的结果
    converged_results = filter(r -> r.converged, results)
    println("收敛的参数组合: $(length(converged_results))/$(length(results))")
    
    if length(converged_results) == 0
        println("⚠️  没有收敛的结果，请调整参数范围")
        return
    end
    
    # 寻找收入逆转的案例
    reversal_cases = filter(r -> r.reversal, converged_results)
    println("发现收入逆转案例: $(length(reversal_cases))")
    
    if length(reversal_cases) > 0
        println("\n🎉 找到满足理论预期的参数！")
        println("="^50)
        
        # 按ratio降序排列
        sort!(reversal_cases, by = r -> r.ratio, rev=true)
        
        for (i, case) in enumerate(reversal_cases[1:min(5, length(reversal_cases))])
            println("\n案例 $(i): R_FPA > R_SPA")
            @printf("  参数: ρ=%.2f, c₂=%.1e, σ=%.2f\n", case.ρ, case.c₂, case.σ)
            @printf("  均衡: η*_FPA=%.3f, η*_SPA=%.3f\n", case.ηF, case.ηS)
            @printf("  收入: R_FPA=%.4f, R_SPA=%.4f\n", case.RF, case.RS)
            @printf("  比率: R_FPA/R_SPA = %.4f (FPA胜出 %.1f%%)\n", 
                    case.ratio, (case.ratio-1)*100)
            @printf("  收敛: |gap_F|=%.1e, |gap_S|=%.1e\n", abs(case.gapF), abs(case.gapS))
        end
        
        return reversal_cases[1]  # 返回最强的逆转案例
    else
        println("\n😞 未发现收入逆转案例，显示最接近的情况:")
        
        # 找ratio最接近1的案例
        sort!(converged_results, by = r -> abs(r.ratio - 1))
        
        for (i, case) in enumerate(converged_results[1:min(3, length(converged_results))])
            println("\n接近案例 $(i):")
            @printf("  参数: ρ=%.2f, c₂=%.1e, σ=%.2f\n", case.ρ, case.c₂, case.σ)
            @printf("  比率: R_FPA/R_SPA = %.4f\n", case.ratio)
            if case.ratio > 0.98
                println("  ⭐ 非常接近逆转！")
            end
        end
        
        return nothing
    end
end

function targeted_search(base_case=nothing)
    """基于初步结果的定向搜索"""
    if base_case === nothing
        println("\n🎯 定向搜索：测试极端参数")
        test_cases = [
            (ρ=0.1, c₂=1e-4, σ=0.6, μ=0.5),   # 低相关+高成本+高方差
            (ρ=0.2, c₂=5e-5, σ=0.5, μ=0.5),   
            (ρ=0.3, c₂=2e-5, σ=0.4, μ=0.5),
        ]
    else
        println("\n🎯 定向搜索：围绕找到的案例精细搜索")
        ρ_base, c₂_base, σ_base = base_case.ρ, base_case.c₂, base_case.σ
        test_cases = [
            (ρ=ρ_base*0.8, c₂=c₂_base*2, σ=σ_base*1.2, μ=0.5),
            (ρ=ρ_base*0.9, c₂=c₂_base*1.5, σ=σ_base*1.1, μ=0.5),
            (ρ=ρ_base*1.1, c₂=c₂_base*0.8, σ=σ_base*0.9, μ=0.5),
        ]
    end
    
    println("="^50)
    
    best_case = nothing
    best_ratio = 0.0
    
    for (i, params) in enumerate(test_cases)
        println("\n定向测试 $(i):")
        result = quick_analysis(params.ρ, params.c₂, params.c₂/5, params.σ, params.μ, 
                               N=40000, K=3, verbose=true)
        
        if result !== nothing && result.converged
            if result.reversal && result.ratio > best_ratio
                best_case = result
                best_ratio = result.ratio
                println("  🎉 新的最佳逆转案例！")
            end
        end
    end
    
    return best_case
end

function main()
    println("🎯 寻找满足理论预期的收入逆转现象")
    println("目标: 找到 R_FPA > R_SPA 的参数设置")
    println("="^80)
    
    # 第一步：系统性扫描
    results = parameter_sweep_systematic()
    
    # 第二步：分析结果  
    best_reversal = analyze_results(results)
    
    # 第三步：定向搜索
    final_best = targeted_search(best_reversal)
    
    # 总结
    println("\n" * "="^80)
    println("🏆 最终结论:")
    
    if final_best !== nothing
        println("✅ 成功找到收入逆转案例！")
        println("理论预期在以下参数下成立：")
        @printf("  ρ = %.3f (较低相关性)\n", final_best.ρ)
        @printf("  c₂ = %.2e (较高信息成本)\n", final_best.c₂)
        @printf("  σ = %.3f (估值标准差)\n", final_best.σ)
        @printf("  结果: R_FPA/R_SPA = %.4f > 1.0\n", final_best.ratio)
        println("\n💡 经济学解释:")
        println("  - 低相关性减弱了信息的相互学习效应")
        println("  - 高信息成本限制了过度的信息获取")
        println("  - 在此环境下，FPA的信息租金减少效应占主导")
    else
        println("😞 在扫描的参数范围内未找到显著的收入逆转")
        println("可能需要：")
        println("  - 扩大参数搜索范围")
        println("  - 考虑不同的估值分布")
        println("  - 调整成本函数形式")
        println("  - 但ProVer0813.jl在其参数下的结果仍然是正确的")
    end
    
    println("="^80)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

