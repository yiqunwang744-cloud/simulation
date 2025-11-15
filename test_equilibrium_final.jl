# Final test to confirm equilibrium finding works

include("aug28.jl")

function test_equilibrium_final()
    # Create environment
    values = AffiliatedValueModel(0.5, 0.2)
    info = InfoAcquisitionModel(1.0, 0.01, 2.0)
    env = AuctionEnvironment(values, info)
    
    println("=== Final Equilibrium Test ===")
    
    mechanisms = [:SPA, :APA, :WOA, :FPA]
    
    for mechanism in mechanisms
        println("\n--- Testing $mechanism ---")
        try
            η_star = find_equilibrium_accuracy(env, mechanism, verbose=true)
            if !isnan(η_star)
                println("✅ SUCCESS: η* = $(@sprintf("%.4f", η_star))")
                
                # Verify it's actually an equilibrium
                mr = marginal_return(env, mechanism, η_star)
                mc = env.info.cost_scale * env.info.cost_exponent * η_star^(env.info.cost_exponent - 1)
                println("   Verification: MR = $(@sprintf("%.6f", mr)), MC = $(@sprintf("%.6f", mc))")
                println("   Difference: $(@sprintf("%.8f", abs(mr - mc)))")
            else
                println("❌ FAILED: Could not find equilibrium")
            end
        catch e
            println("❌ ERROR: $e")
        end
    end
end

test_equilibrium_final()
