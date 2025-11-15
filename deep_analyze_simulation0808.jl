# 深入分析simulation0808.jl，理解为什么η*排序与理论相反

using Printf
include("simulation0808.jl")

function analyze_marginal_returns()
    """分析边际收益计算，找出排序反转的原因"""
    println("🔍 深入分析simulation0808中的边际收益计算")
    println("="^70)
    
    # 重新运行边际收益计算，但更详细
    model = AffiliatedValueModel(0.3, 0.5, 0.2, 0.0, 1.0)  # α, μ_v, σ_v, v_min, v_max
    
    η_values = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]
    
    println("分析不同η值下各机制的边际收益:")
    println("η值     FPA_MR      SPA_MR      APA_MR      WOA_MR")
    println("-"^60)
    
    for η in η_values
        try
            # 计算各机制的边际收益
            fpa_mr = compute_fpa_marginal_return(model, η)
            spa_mr = compute_spa_marginal_return(model, η)
            apa_mr = compute_apa_marginal_return(model, η)
            woa_mr = compute_woa_marginal_return(model, η)
            
            @printf "%.1f     %8.4f    %8.4f    %8.4f    %8.4f\n" η fpa_mr spa_mr apa_mr woa_mr
            
        catch e
            @printf "%.1f     计算失败: %s\n" η e
        end
    end
    
    println("\n🎯 分析边际成本:")
    for η in η_values
        try
            mc = marginal_cost(η, 0.1, 2.0)  # 使用合理的成本参数
            @printf "η=%.1f: MC=%.6f\n" η mc
        catch e
            @printf "η=%.1f: MC计算失败: %s\n" η e
        end
    end
end

function investigate_why_ranking_reversed()
    """调查为什么排序与理论相反"""
    println("\n🕵️ 调查排序反转的根本原因")
    println("="^70)
    
    model = AffiliatedValueModel(0.3, 0.5, 0.2, 0.0, 1.0)
    
    println("1. 检查参数设置的合理性:")
    @printf "   α (affiliation) = %.3f\n" model.α
    @printf "   μ_v (mean value) = %.3f\n" model.μ_v
    @printf "   σ_v (std dev) = %.3f\n" model.σ_v
    
    println("\n2. 检查信号生成机制:")
    # 测试信号生成
    test_v = 0.6
    signal_struct = SignalStructure(2.0)
    
    signals = [generate_signal(signal_struct, test_v, model.v_min, model.v_max) for _ in 1:10]
    @printf "   V=%.1f时的信号样本: " test_v
    for s in signals[1:5]
        @printf "%.3f " s
    end
    println("...")
    
    println("\n3. 检查出价策略实现:")
    η = 2.0
    v_test = 0.7
    
    try
        # 检查各种出价策略
        if isdefined(Main, :fpa_bid_strategy)
            fpa_bid = fpa_bid_strategy(v_test, η, model)
            @printf "   FPA bid(v=%.1f, η=%.1f) = %.4f\n" v_test η fpa_bid
        else
            println("   ❌ FPA出价策略函数未找到")
        end
        
        if isdefined(Main, :spa_bid_strategy)
            spa_bid = spa_bid_strategy(v_test, η, model)
            @printf "   SPA bid(v=%.1f, η=%.1f) = %.4f\n" v_test η spa_bid
        else
            println("   ❌ SPA出价策略函数未找到")
        end
        
    catch e
        println("   ❌ 出价策略检查失败: $(e)")
    end
    
    println("\n4. 检查效用函数实现:")
    try
        if isdefined(Main, :expected_payoff_fpa)
            payoff_fpa = expected_payoff_fpa(η, model; n_sim=1000)
            @printf "   E[U_FPA](η=%.1f) = %.6f\n" η payoff_fpa
        else
            println("   ❌ FPA期望效用函数未找到")
        end
        
        if isdefined(Main, :expected_payoff_spa)  
            payoff_spa = expected_payoff_spa(η, model; n_sim=1000)
            @printf "   E[U_SPA](η=%.1f) = %.6f\n" η payoff_spa
        else
            println("   ❌ SPA期望效用函数未找到")
        end
        
    catch e
        println("   ❌ 效用函数检查失败: $(e)")
    end
end

function check_theory_implementation()
    """检查理论实现的正确性"""
    println("\n📖 检查理论实现正确性")
    println("="^70)
    
    println("理论要求:")
    println("1. FPA: 胜者诅咒较轻，'money left on table'效应")
    println("2. SPA: 胜者诅咒，但支付第二高价") 
    println("3. APA: 'all-pay rule'抑制信息获取")
    println("4. WOA: 'all-pay rule' + 持续成本，抑制最强")
    
    println("\n实际观察到的问题:")
    println("• η* ranking: WOA > SPA > FPA > APA (与理论相反)")
    println("• 可能的原因:")
    println("  - 效用函数实现错误")
    println("  - 出价策略不正确")
    println("  - 参数设置不合理")
    println("  - 边际收益计算有bias")
    
    # 尝试找出具体问题
    model = AffiliatedValueModel(0.3, 0.5, 0.2, 0.0, 1.0)
    
    println("\n🔬 诊断性检查:")
    for mechanism in ["FPA", "SPA", "APA", "WOA"]
        println("\n$(mechanism):")
        
        for η in [1.0, 2.0, 3.0]
            try
                # 尝试计算该机制在不同η下的表现
                if mechanism == "FPA" && isdefined(Main, :expected_payoff_fpa)
                    payoff = expected_payoff_fpa(η, model; n_sim=500)
                    @printf "  η=%.1f: E[U]=%.6f\n" η payoff
                elseif mechanism == "SPA" && isdefined(Main, :expected_payoff_spa)
                    payoff = expected_payoff_spa(η, model; n_sim=500)  
                    @printf "  η=%.1f: E[U]=%.6f\n" η payoff
                else
                    println("  函数不可用")
                    break
                end
            catch e
                println("  计算失败: $(e)")
                break
            end
        end
    end
end

function suggest_fixes()
    """建议修复方案"""
    println("\n🔧 建议的修复方案")
    println("="^70)
    
    println("基于分析，可能的问题和解决方案:")
    
    println("\n1. 参数问题:")
    println("   • 当前α=0.3可能过高，导致外部性主导")
    println("   • 建议测试α∈[0.05, 0.2]范围")
    println("   • 成本函数参数可能不合适")
    
    println("\n2. 实现问题:")
    println("   • 检查FPA出价策略是否正确实现胜者诅咒缓解")
    println("   • 验证APA/WOA的'all-pay'惩罚是否充分")
    println("   • 确认边际收益计算的数值稳定性")
    
    println("\n3. 理论应用:")
    println("   • 可能需要更精确地实现Persico (2000)的framework")
    println("   • 检查是否遗漏了关键的理论条件")
    println("   • 考虑使用更robust的均衡求解方法")
    
    println("\n4. 下一步行动:")
    println("   • 从simulation0808.jl开始，系统性修复")
    println("   • 对比ProVer0813.jl的方法论")
    println("   • 重点修复边际收益计算的准确性")
end

function main()
    println("🎯 深入分析simulation0808.jl中的η*排序问题")
    println("发现：实际排序与理论预期完全相反")
    
    analyze_marginal_returns()
    investigate_why_ranking_reversed() 
    check_theory_implementation()
    suggest_fixes()
    
    println("\n" * "="^70)
    println("🎯 结论：simulation0808.jl确实有理论实现问题")
    println("但它是目前运行最完整的版本，值得深入修复")
    println("="^70)
end

main()
