# Verification Script for Claimed Reversals
# Run this to check if reported reversals are actually valid

include("extended_reversal_search.jl")

println("="^70)
println("VERIFYING CLAIMED REVERSALS")
println("="^70)
println()

# Test the specific parameters claimed
test_cases = [
    # Low correlation claims
    (ρ=0.10, σ=0.10, cost=QuadraticCubicCost(1e-6, 2e-7), label="Low ρ, QC"),
    (ρ=0.10, σ=0.10, cost=PowerCost(1e-6, 2.0), label="Low ρ, Power"),
    (ρ=0.20, σ=0.10, cost=QuadraticCubicCost(1e-6, 2e-7), label="ρ=0.2, QC"),

    # High correlation claims (SUSPICIOUS!)
    (ρ=0.95, σ=0.40, cost=PureQuadraticCost(5e-7), label="High ρ, Pure Quad 1"),
    (ρ=0.95, σ=0.40, cost=PureQuadraticCost(1e-6), label="High ρ, Pure Quad 2"),
    (ρ=0.95, σ=0.40, cost=LinearQuadraticCost(1e-7, 5e-7), label="High ρ, Lin-Quad 1"),
    (ρ=0.95, σ=0.40, cost=LinearQuadraticCost(5e-8, 2e-7), label="High ρ, Lin-Quad 2"),
    (ρ=0.95, σ=0.40, cost=PowerCost(1e-6, 2.0), label="High ρ, Power"),
]

println("Testing $(length(test_cases)) claimed reversal cases...")
println("Using high precision: N=80000, K=4")
println()

results = []

for (i, tc) in enumerate(test_cases)
    println("-"^70)
    println("Test Case $i: $(tc.label)")
    println("Parameters: ρ=$(tc.ρ), σ=$(tc.σ)")
    println()

    try
        em = make_extended_model(ρ=tc.ρ, σ=tc.σ, cost_fn=tc.cost)
        result = analyze_extended(em; N=80000, K=4, verbose=true)

        push!(results, merge(result, (label=tc.label,)))

        # Detailed verification
        println("\nVERIFICATION:")
        if result.validF && result.validS
            println("  ✓ Both equilibria are VALID")

            # Check for corner solutions
            if result.ηF > 90
                println("  ⚠️  WARNING: η*_FPA = $(result.ηF) is close to η_max!")
                println("     This might be an unconstrained corner!")
            end

            if result.reversal
                println("  🎉 REVERSAL CONFIRMED!")
                @printf("     R_FPA/R_SPA = %.4f (FPA wins by %.2f%%)\n",
                        result.ratio, (result.ratio - 1) * 100)
            else
                println("  ❌ NO REVERSAL")
                @printf("     R_FPA/R_SPA = %.4f (SPA wins by %.2f%%)\n",
                        result.ratio, (1/result.ratio - 1) * 100)
            end

            # Check equilibrium quality
            if abs(result.gapF) > 1e-4 || abs(result.gapS) > 1e-4
                println("  ⚠️  WARNING: Equilibrium gaps are large!")
                @printf("     |gap_FPA| = %.2e, |gap_SPA| = %.2e\n",
                        abs(result.gapF), abs(result.gapS))
            end
        else
            println("  ❌ INVALID EQUILIBRIA - cannot verify reversal")
            if !result.validF
                @printf("     FPA: η*=%.3f, gap=%.2e (INVALID)\n",
                        result.ηF, result.gapF)
            end
            if !result.validS
                @printf("     SPA: η*=%.3f, gap=%.2e (INVALID)\n",
                        result.ηS, result.gapS)
            end
        end

    catch e
        println("  ❌ ERROR: $e")
        push!(results, (label=tc.label, validF=false, validS=false, reversal=false))
    end

    println()
end

# Summary
println("="^70)
println("VERIFICATION SUMMARY")
println("="^70)

valid_results = filter(r -> hasfield(typeof(r), :validF) && r.validF && r.validS, results)
true_reversals = filter(r -> hasfield(typeof(r), :reversal) && r.reversal, valid_results)

@printf("Cases tested: %d\n", length(test_cases))
@printf("Valid equilibria: %d\n", length(valid_results))
@printf("TRUE REVERSALS: %d\n", length(true_reversals))

if length(true_reversals) > 0
    println("\n✅ CONFIRMED REVERSALS:")
    for r in true_reversals
        @printf("  - %s: ratio=%.4f, η_F=%.2f, η_S=%.2f\n",
                r.label, r.ratio, r.ηF, r.ηS)
    end
else
    println("\n❌ NO REVERSALS CONFIRMED")

    if length(valid_results) > 0
        println("\nClosest valid cases:")
        sort!(valid_results, by=r->abs(get(r, :ratio, NaN) - 1))
        for r in valid_results[1:min(3, length(valid_results))]
            if hasfield(typeof(r), :ratio) && !isnan(r.ratio)
                @printf("  - %s: ratio=%.4f\n", r.label, r.ratio)
            end
        end
    end
end

println("="^70)
println("\nVerification complete!")
println("Run this script with Julia to test the claimed results.")
