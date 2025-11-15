# 系统性比较所有主要实现，找出最正确的η*排序
# 重点：理论一致性检查

using Printf

function test_implementation(file_path, description)
    """测试单个实现文件"""
    println("\n" * "="^80)
    println("🧪 测试: $(description)")
    println("文件: $(file_path)")
    println("="^80)
    
    if !isfile(file_path)
        println("❌ 文件不存在")
        return false
    end
    
    try
        # 包含文件
        println("📂 加载文件...")
        include(file_path)
        println("✅ 文件加载成功")
        
        # 尝试基本的均衡计算
        success = test_equilibrium_calculation(file_path)
        return success
        
    catch e
        println("❌ 文件加载失败: $(e)")
        return false
    end
end

function test_equilibrium_calculation(file_path)
    """针对不同实现尝试计算均衡"""
    
    # 根据文件名判断使用的接口
    filename = basename(file_path)
    
    try
        if filename == "ProVer0813.jl"
            return test_prover0813()
        elseif filename == "0707ver.jl"
            return test_0707ver()
        elseif filename == "simulation0808.jl"
            return test_simulation0808()
        elseif filename == "final_corrected_simulation.jl"
            return test_final_corrected()
        elseif filename == "exact_equilibrium_implementation.jl"
            return test_exact_equilibrium()
        else
            println("⚠️  未知接口，尝试通用测试")
            return test_generic()
        end
    catch e
        println("❌ 均衡计算失败: $(e)")
        return false
    end
end

function test_prover0813()
    """测试ProVer0813.jl"""
    try
        println("🔬 ProVer0813接口测试...")
        
        # 使用默认参数
        m = make_model(μ=0.5, σ=0.2, ρ=0.3, c2=1e-5, c3=2e-6)
        
        println("  求解FPA和SPA均衡...")
        ηF, gapF, seF = solve_eta_star_CI(:FPA, m; N=10_000, K=2, max_iter=10)
        ηS, gapS, seS = solve_eta_star_CI(:SPA, m; N=10_000, K=2, seed=11111, max_iter=10)
        
        @printf "  结果: η*_FPA=%.4f, η*_SPA=%.4f\n" ηF ηS
        @printf "  收敛: FPA(gap=%.1e), SPA(gap=%.1e)\n" gapF gapS
        
        # 理论检查
        if ηF > ηS
            println("  ✅ 理论正确: η*_FPA > η*_SPA")
            
            # 快速收入计算
            D = make_draws(m; N=20_000, seed=99999)
            cacheF = precompute_bids_FPA(ηF, m)
            RF = revenue(ηF, :FPA, m, D; cacheFPA=cacheF)
            RS = revenue(ηS, :SPA, m, D)
            
            @printf "  收入: FPA=%.6f, SPA=%.6f, 比率=%.6f\n" RF RS RF/RS
            
            if RF > RS
                println("  🎉 发现收入逆转！")
            else
                println("  📊 SPA收入更高（符合常见情况）")
            end
            
            return true
        else
            println("  ❌ 理论错误: η*_FPA ≤ η*_SPA")
            return false
        end
        
    catch e
        println("  ❌ ProVer0813测试失败: $(e)")
        return false
    end
end

function test_0707ver()
    """测试0707ver.jl"""
    try
        println("🔬 0707ver接口测试...")
        
        # 尝试使用OptimizedAuctionModel
        if isdefined(Main, :OptimizedAuctionModel) && isdefined(Main, :run_comparative_analysis)
            model = OptimizedAuctionModel(
                μ=0.5, σ=0.3, ρ=0.4, v_min=0.0, v_max=1.0,
                η_min=0.1, η_max=10.0, c₂=1e-4, c₃=2e-5,
                n_mc=5000, n_quad=50, tol=1e-8, seed=12345
            )
            
            println("  运行比较分析...")
            results = run_comparative_analysis(model; verbose=false)
            
            # 检查结果
            if haskey(results, :eta_star)
                ηs = results[:eta_star]
                @printf "  η*结果: FPA=%.4f, SPA=%.4f\n" ηs[:FPA] ηs[:SPA]
                
                if ηs[:FPA] > ηs[:SPA]
                    println("  ✅ 理论正确")
                    return true
                else
                    println("  ❌ 理论错误")
                    return false
                end
            else
                println("  ⚠️  结果格式未知")
                return false
            end
        else
            println("  ❌ 预期的函数或类型不存在")
            return false
        end
        
    catch e
        println("  ❌ 0707ver测试失败: $(e)")
        return false
    end
end

function test_simulation0808()
    """测试simulation0808.jl"""
    try
        println("🔬 simulation0808接口测试...")
        
        # 检查是否有主要函数
        if isdefined(Main, :AffiliatedValueModel) && isdefined(Main, :run_full_analysis)
            model = AffiliatedValueModel(α=0.3, μ_v=0.5, σ_v=0.2, v_min=0.0, v_max=1.0)
            
            println("  运行完整分析...")
            results = run_full_analysis(model; quiet=true)
            
            # 尝试提取结果（结构可能不同）
            println("  🎯 尝试分析结果结构...")
            println("  结果keys: ", keys(results))
            return true
            
        else
            println("  ❌ 预期的函数不存在")
            return false
        end
        
    catch e
        println("  ❌ simulation0808测试失败: $(e)")
        return false
    end
end

function test_final_corrected()
    """测试final_corrected_simulation.jl"""
    try
        println("🔬 final_corrected接口测试...")
        
        if isdefined(Main, :FinalModel) && isdefined(Main, :find_equilibrium_corrected)
            model = FinalModel(μ=0.5, σ=0.2, η=2.0, c=0.1, γ=2.0)
            
            println("  查找均衡...")
            # 这里需要根据实际接口调整
            println("  ⚠️  接口需要进一步确定")
            return false
            
        else
            println("  ❌ 预期的函数不存在")
            return false
        end
        
    catch e
        println("  ❌ final_corrected测试失败: $(e)")
        return false
    end
end

function test_exact_equilibrium()
    """测试exact_equilibrium_implementation.jl"""
    try
        println("🔬 exact_equilibrium接口测试...")
        
        if isdefined(Main, :AuctionParams) && isdefined(Main, :compute_paper_marginal_returns)
            params = AuctionParams(1.0, 0.3, 0.25, 0.08, 0.1, 2.0, 0.5, 5.0)
            
            println("  计算边际收益...")
            mr_dict = compute_paper_marginal_returns(params, 2.0; δη=0.1, verbose=false)
            
            @printf "  边际收益: FPA=%.6f, SPA=%.6f\n" mr_dict["FPA"] mr_dict["SPA"]
            
            return true
            
        else
            println("  ❌ 预期的函数不存在")
            return false
        end
        
    catch e
        println("  ❌ exact_equilibrium测试失败: $(e)")
        return false
    end
end

function test_generic()
    """通用测试"""
    try
        println("🔬 通用接口搜索...")
        
        # 列出当前定义的主要符号
        main_names = names(Main)
        relevant_names = filter(name -> 
            occursin("eta", string(name)) || 
            occursin("equilibrium", string(name)) ||
            occursin("auction", string(name)) ||
            occursin("solve", string(name)), 
            main_names)
        
        if !isempty(relevant_names)
            println("  可能相关的函数:")
            for name in relevant_names[1:min(10, end)]
                println("    - $(name)")
            end
        end
        
        return false
        
    catch e
        println("  ❌ 通用测试失败: $(e)")
        return false
    end
end

function main()
    println("🔍 系统性比较所有主要Julia实现")
    println("目标：找到能正确产生η*排序的实现")
    println("="^80)
    
    # 候选实现列表（按优先级排序）
    candidates = [
        ("/Users/simulateone/Downloads/ProVer0813.jl", "ProVer0813 - Clean & Robust"),
        ("/Users/simulateone/Downloads/0707ver.jl", "0707ver - Improved Model"),
        ("/Users/simulateone/Downloads/simulation0808.jl", "simulation0808 - Latest Simulation"),
        ("/Users/simulateone/Downloads/final_corrected_simulation.jl", "Final Corrected Version"),
        ("/Users/simulateone/Downloads/exact_equilibrium_implementation.jl", "Exact Equilibrium Implementation"),
    ]
    
    successful_implementations = []
    
    for (file_path, description) in candidates
        success = test_implementation(file_path, description)
        if success
            push!(successful_implementations, (file_path, description))
        end
        
        # 清理Main命名空间（避免冲突）
        try
            for name in names(Main)
                if !(name in [:Base, :Core, :Main, :InteractiveUtils])
                    try
                        eval(:($(name) = nothing))
                    catch
                    end
                end
            end
        catch
        end
    end
    
    # 总结
    println("\n" * "="^80)
    println("📊 测试总结")
    println("="^80)
    println("测试实现数量: ", length(candidates))
    println("成功实现数量: ", length(successful_implementations))
    
    if !isempty(successful_implementations)
        println("\n✅ 成功的实现:")
        for (i, (file_path, description)) in enumerate(successful_implementations)
            println("  $(i). $(description)")
            println("     文件: $(basename(file_path))")
        end
        
        println("\n🎯 推荐使用第一个成功的实现")
    else
        println("\n💔 没有找到完全成功的实现")
        println("建议：")
        println("1. 检查和修复现有实现")
        println("2. 基于理论重新实现")
        println("3. 使用最接近成功的版本进行改进")
    end
    
    return successful_implementations
end

# 运行测试
successful = main()
println("\n程序结束")

