# 用ProVer0813.jl的实际运行参数来验证
using Distributions, LinearAlgebra, QuadGK, Random, Statistics, Printf

include("ProVer0813.jl")

function test_with_actual_params()
    println("🔍 用ProVer0813.jl的实际参数测试")
    println("="^60)
    
    # 使用实际运行的参数，不是默认参数！
    m = make_model(μ=0.5, σ=0.4, ρ=0.98, c2=1e-6, c3=2e-7, 
                   ηmin=0.005, ηmax=100.0)
    
    println("实际参数:")
    println("  ρ = $(m.ρ)")
    println("  c2 = $(m.c2)")
    println("  c3 = $(m.c3)")
    println("  ηmin = $(m.ηmin)")
    
    # 测试几个η值的MR和MC
    η_tests = [1.0, 2.0, 3.0, 5.0, 8.0]
    
    D = make_draws(m, N=10000, seed=12345)
    
    println("\nη值测试 (MR vs MC):")
    println("η      | MR_FPA   | MR_SPA   | MC       | Gap_FPA  | Gap_SPA")
    println("-"^65)
    
    for η in η_tests
        mr_fpa = MR_one(η, :FPA, m, D, h_frac=0.01)
        mr_spa = MR_one(η, :SPA, m, D, h_frac=0.01)
        mc_val = MC(η, m)
        
        @printf("%.1f    | %.6f | %.6f | %.6f | %.6f | %.6f\n", 
                η, mr_fpa, mr_spa, mc_val, mr_fpa-mc_val, mr_spa-mc_val)
    end
    
    println("\n寻找大致的均衡点:")
    
    # 寻找FPA均衡点
    println("FPA均衡搜索:")
    for η in 4.0:0.5:8.0
        mr_fpa = MR_one(η, :FPA, m, D, h_frac=0.01)
        mc_val = MC(η, m)
        gap = mr_fpa - mc_val
        @printf("  η=%.1f: MR=%.6f, MC=%.6f, Gap=%.6f\n", η, mr_fpa, mc_val, gap)
        if abs(gap) < 0.002
            println("    ⭐ 接近均衡!")
        end
    end
    
    # 寻找SPA均衡点
    println("\nSPA均衡搜索:")
    for η in 2.0:0.3:4.0
        mr_spa = MR_one(η, :SPA, m, D, h_frac=0.01)
        mc_val = MC(η, m)
        gap = mr_spa - mc_val
        @printf("  η=%.1f: MR=%.6f, MC=%.6f, Gap=%.6f\n", η, mr_spa, mc_val, gap)
        if abs(gap) < 0.002
            println("    ⭐ 接近均衡!")
        end
    end
end

function compare_cost_functions()
    println("\n💰 比较不同成本参数的影响")
    println("="^60)
    
    η_test = 3.0
    
    # 默认参数
    m1 = make_model(c2=2e-5, c3=5e-6)
    mc1 = MC(η_test, m1)
    
    # 实际参数  
    m2 = make_model(c2=1e-6, c3=2e-7)
    mc2 = MC(η_test, m2)
    
    println("在η = $(η_test)时的边际成本:")
    @printf("  默认参数 (c2=2e-5, c3=5e-6): MC = %.6f\n", mc1)
    @printf("  实际参数 (c2=1e-6, c3=2e-7): MC = %.6f\n", mc2)
    @printf("  倍数差异: %.1f倍\n", mc1/mc2)
    
    println("\n这解释了为什么我之前的验证脚本显示MR >> MC!")
    println("用错误的(更大的)成本参数会导致均衡点在更低的η值。")
end

if abspath(PROGRAM_FILE) == @__FILE__
    test_with_actual_params()
    compare_cost_functions()
end
