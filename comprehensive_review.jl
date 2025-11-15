# 全面审查所有Julia实现，找出真正最好的
# 不遗漏任何可能的优秀实现

using Printf

function quick_test_file(filepath)
    """快速测试单个文件的可用性"""
    if !isfile(filepath)
        return false, "文件不存在"
    end
    
    try
        # 尝试加载文件
        include(filepath)
        return true, "加载成功"
    catch e
        return false, "加载失败: $(first(split(string(e), '\n')))"
    end
end

function analyze_file_by_name(filepath)
    """根据文件名分析可能的质量和用途"""
    filename = basename(filepath)
    
    # 高优先级关键词
    high_priority = ["ProVer", "contrmap", "solution", "corrected", "final", "exact"]
    medium_priority = ["auction", "equilibrium", "revenue", "theory", "simulation"]  
    low_priority = ["test", "debug", "validate", "verify"]
    
    priority = "low"
    if any(occursin(kw, lowercase(filename)) for kw in high_priority)
        priority = "high"
    elseif any(occursin(kw, lowercase(filename)) for kw in medium_priority)
        priority = "medium"
    end
    
    return priority
end

function extract_key_functions(filepath)
    """提取文件中的关键函数名"""
    if !isfile(filepath)
        return []
    end
    
    try
        content = read(filepath, String)
        lines = split(content, '\n')
        
        functions = []
        for line in lines[1:min(100, length(lines))]  # 只看前100行
            line = strip(line)
            if startswith(line, "function ") && !startswith(line, "function(")
                func_name = split(replace(line, "function " => ""), "(")[1]
                push!(functions, func_name)
            end
        end
        
        return functions[1:min(10, length(functions))]  # 最多返回10个
    catch
        return []
    end
end

function comprehensive_review()
    """全面审查所有Julia文件"""
    println("🔍 全面审查所有Julia实现文件")
    println("="^80)
    
    # 获取所有Julia文件
    all_files = [
        "diagnose_reversal_failures.jl", "quick_reversal_check.jl", "review_claimed_reversals.jl",
        "exhaustive_reversal_search.jl", "verify_revenue_calculation.jl", "diagnose_numerical_issues.jl",
        "analyze_cost_sensitivity.jl", "final_extreme_search.jl", "strict_reversal_verification.jl",
        "verify_reversal_case.jl", "find_revenue_reversal.jl", "check_correct_params.jl",
        "validate_ProVer0813.jl", "debug_fpa_spa.jl", "rigorous_theoretical_implementation.jl",
        "persico_theoretical_correct.jl", "rigorous_implementation.jl", "theoretical_correct_implementation.jl",
        "aug28_strict_correct.jl", "test_equilibrium_final.jl", "aug28.jl", "test_bisection.jl",
        "debug_equilibrium.jl", "test_run.jl", "setup_dependencies.jl", "run_auction_analysis.jl",
        "ProVer0813.jl", "0707ver.jl", "simulation0808.jl", "bidding_strategies.jl",
        "robustness_testing.jl", "proper_execution.jl", "exact_equilibrium_implementation.jl",
        "final_corrected_simulation.jl", "revenue_analysis.jl", "theory_based_implementation.jl",
        "fundamental_analysis.jl", "equilibrium_bidding.jl", "corrected_exact_implementation.jl",
        "corrected_bidding_strategies.jl", "corrected_simulation.jl", "debug_endogenous_simulation.jl",
        "verbose_endogenous_simulation.jl", "improved_endogenous_simulation.jl", "corrected_endogenous_choice.jl",
        "auction_simulation_comprehensive.jl", "corrected_main_simulation.jl", "theoretical_corrections.jl",
        "run_complete_simulation.jl", "verify_assumptions.jl", "auction_theory_verification.jl",
        "auction_revenue_analysis.jl", "auction_equilibrium_analysis.jl", "auction_computation_module.jl",
        "0707.jl", "using Distributions.jl", "verify.jl", "auction_analysis_extended.jl",
        "auction_model_improved.jl", "mechanism.jl", "Untitled-4.jl", "module AuctionEquilibrium.jl",
        "module EndogenousEtaClosedForm.jl", "module AuctionTheory.jl", "module AuctionTheory1.jl",
        "module AuctionTheoryEndogenousEta.jl", "module AuctionTheory4.jl", "module AuctionTheory3.jl",
        "module AuctionFPA_BestResponse.jl", "module AuctionSimulation.jl", "auction_truncation.jl",
        "auctionfirst.jl", "Untitled-2.jl", "import Pkg; Pkg.add([\"DelimitedFiles\",\"K.jl",
        "contrmap_solutions.jl"
    ]
    
    # 按优先级分类
    high_priority = []
    medium_priority = []
    low_priority = []
    
    for filename in all_files
        filepath = "/Users/simulateone/Downloads/$(filename)"
        priority = analyze_file_by_name(filepath)
        
        if priority == "high"
            push!(high_priority, filepath)
        elseif priority == "medium" 
            push!(medium_priority, filepath)
        else
            push!(low_priority, filepath)
        end
    end
    
    println("📊 文件分类统计:")
    println("  高优先级: $(length(high_priority)) 个")
    println("  中优先级: $(length(medium_priority)) 个") 
    println("  低优先级: $(length(low_priority)) 个")
    
    # 重点测试高优先级和部分中优先级文件
    candidates = vcat(high_priority, medium_priority[1:min(15, length(medium_priority))])
    
    println("\n🧪 重点测试 $(length(candidates)) 个候选文件:")
    println("="^80)
    
    successful_files = []
    for filepath in candidates
        filename = basename(filepath)
        @printf "%-40s " filename
        
        success, message = quick_test_file(filepath)
        if success
            println("✅ $(message)")
            push!(successful_files, filepath)
            
            # 提取关键函数
            functions = extract_key_functions(filepath)
            if !isempty(functions)
                println("    主要函数: $(join(functions[1:min(3,end)], ", "))...")
            end
        else
            println("❌ $(message)")
        end
    end
    
    println("\n" * "="^80)
    println("📈 成功加载的文件 ($(length(successful_files))/$(length(candidates))):")
    
    for (i, filepath) in enumerate(successful_files)
        filename = basename(filepath)
        println("  $(i). $(filename)")
    end
    
    if isempty(successful_files)
        println("💔 没有找到可成功加载的高质量实现")
        println("建议检查语法错误或依赖问题")
    else
        println("\n🎯 推荐进一步测试前 $(min(3, length(successful_files))) 个文件")
    end
    
    return successful_files
end

# 运行全面审查
successful_files = comprehensive_review()

# 如果找到了可用文件，进行更详细的测试
if !isempty(successful_files)
    println("\n" * "="^80)
    println("🔬 详细测试最有希望的文件")
    println("="^80)
    
    for (i, filepath) in enumerate(successful_files[1:min(3, end)])
        filename = basename(filepath)
        println("\n$(i). 详细测试: $(filename)")
        println("-"^50)
        
        try
            # 清理命名空间
            for name in names(Main)
                if !(name ∈ [:Base, :Core, :Main, :InteractiveUtils])
                    try
                        eval(:($(name) = nothing))
                    catch
                    end
                end
            end
            
            # 重新加载文件
            include(filepath)
            
            # 查找可能的主函数或测试函数
            main_names = names(Main)
            potential_mains = filter(name -> 
                occursin("main", lowercase(string(name))) ||
                occursin("test", lowercase(string(name))) ||
                occursin("run", lowercase(string(name))) ||
                occursin("analyze", lowercase(string(name))), 
                main_names)
            
            if !isempty(potential_mains)
                println("  可能的入口函数: $(join(potential_mains[1:min(5,end)], ", "))")
            else
                println("  未找到明显的入口函数")
            end
            
        catch e
            println("  详细测试失败: $(e)")
        end
    end
end

println("\n程序结束")
