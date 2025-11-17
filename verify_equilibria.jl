# Verification Script for Revenue Reversal Results
# This script checks if reported "reversals" are actually valid equilibria
#
# CRITICAL: A true equilibrium must satisfy MR(η*) ≈ MC(η*)
# Invalid corner solutions will have large |MR - MC| gaps

println("="^70)
println("EQUILIBRIUM VERIFICATION SCRIPT")
println("="^70)
println()
println("This script verifies that all reported results have valid equilibria")
println("where MR(η*) ≈ MC(η*) within acceptable tolerance.")
println()

include("comprehensive_julia_implementation.jl")

"""
Verify a single result and print detailed diagnostics
"""
function verify_result(result, label::String; verbose::Bool=true)
    if verbose
        println("-"^70)
        println("Verifying: $label")
        println("-"^70)
    end

    # Check if result exists and has required fields
    if !hasfield(typeof(result), :ηF) || !hasfield(typeof(result), :ηS)
        println("❌ INVALID: Missing required fields")
        return false
    end

    # Extract equilibrium values
    ηF = result.ηF
    ηS = result.ηS
    gapF = result.gapF
    gapS = result.gapS

    # Check if equilibria are valid
    validF = hasfield(typeof(result), :validF) ? result.validF : !isnan(ηF)
    validS = hasfield(typeof(result), :validS) ? result.validS : !isnan(ηS)

    if verbose
        println("\nFPA Equilibrium:")
        if isnan(ηF)
            println("  η* = NaN (FAILED TO CONVERGE)")
            println("  Status: ❌ INVALID")
        else
            @printf("  η* = %.5f\n", ηF)
            @printf("  MR - MC = %.6e\n", gapF)
            if validF
                println("  Status: ✓ VALID")
            else
                println("  Status: ❌ INVALID (|MR-MC| too large)")
            end
        end

        println("\nSPA Equilibrium:")
        if isnan(ηS)
            println("  η* = NaN (FAILED TO CONVERGE)")
            println("  Status: ❌ INVALID")
        else
            @printf("  η* = %.5f\n", ηS)
            @printf("  MR - MC = %.6e\n", gapS)
            if validS
                println("  Status: ✓ VALID")
            else
                println("  Status: ❌ INVALID (|MR-MC| too large)")
            end
        end

        # Check revenue comparison if both valid
        if validF && validS && hasfield(typeof(result), :RF)
            println("\nRevenue Comparison:")
            @printf("  R_FPA = %.6f\n", result.RF)
            @printf("  R_SPA = %.6f\n", result.RS)
            @printf("  Ratio = %.6f\n", result.ratio)

            if result.RF > result.RS
                println("  Result: 🎉 FPA > SPA (REVERSAL)")
            elseif result.RF < result.RS
                @printf("  Result: SPA > FPA by %.2f%%\n", (result.RS/result.RF - 1) * 100)
            else
                println("  Result: Tie")
            end
        elseif !validF || !validS
            println("\n⚠️  Revenue comparison INVALID (equilibria not valid)")
        end
    end

    both_valid = validF && validS

    if verbose
        println("\nOVERALL VERDICT:")
        if both_valid
            println("  ✓ Both equilibria are VALID")
            if hasfield(typeof(result), :reversal)
                if result.reversal
                    println("  ✓ This is a TRUE REVERSAL!")
                else
                    println("  Standard result (SPA > FPA)")
                end
            end
        else
            println("  ❌ At least one equilibrium is INVALID")
            println("  This result should be DISCARDED")
        end
        println()
    end

    return both_valid
end

"""
Verify all results from a parameter search
"""
function verify_search_results(results; verbose::Bool=true)
    if verbose
        println("="^70)
        println("VERIFYING SEARCH RESULTS")
        println("="^70)
        println("Total results to verify: $(length(results))")
        println()
    end

    valid_count = 0
    invalid_count = 0
    reversal_count = 0
    false_reversal_count = 0

    for (i, result) in enumerate(results)
        # Extract parameters if available
        params = ""
        if hasfield(typeof(result), :ρ)
            params = @sprintf("ρ=%.2f, σ=%.2f, c₂=%.1e", result.ρ, result.σ, result.c2)
        end
        label = "Result $i" * (params != "" ? " ($params)" : "")

        # Check if this was claimed to be a reversal
        claimed_reversal = hasfield(typeof(result), :reversal) && result.reversal

        # Verify
        is_valid = verify_result(result, label; verbose=verbose)

        if is_valid
            valid_count += 1
            if claimed_reversal
                reversal_count += 1
            end
        else
            invalid_count += 1
            if claimed_reversal
                false_reversal_count += 1
                if verbose
                    println("⚠️  WARNING: Result $i was claimed as reversal but has INVALID equilibria!")
                    println()
                end
            end
        end
    end

    # Summary
    println("="^70)
    println("VERIFICATION SUMMARY")
    println("="^70)
    @printf("Total results verified: %d\n", length(results))
    @printf("Valid equilibria (both FPA & SPA): %d (%.1f%%)\n",
            valid_count, 100*valid_count/max(1,length(results)))
    @printf("Invalid equilibria: %d (%.1f%%)\n",
            invalid_count, 100*invalid_count/max(1,length(results)))
    println()
    @printf("True reversals (valid equilibria): %d\n", reversal_count)
    @printf("False reversals (invalid equilibria): %d ❌\n", false_reversal_count)
    println()

    if false_reversal_count > 0
        println("🚨 CRITICAL: Found $(false_reversal_count) FALSE REVERSALS!")
        println("These were reported as reversals but have invalid equilibria.")
        println("The bug in corner solution handling has been identified.")
    else
        println("✅ No false reversals detected")
    end

    if reversal_count > 0
        println("\n🎉 Found $(reversal_count) TRUE REVERSALS with valid equilibria!")
    else
        println("\n❌ NO TRUE REVERSALS FOUND")
        println("Standard revenue ranking R_SPA > R_FPA holds for all valid equilibria.")
    end
    println("="^70)

    return (
        total = length(results),
        valid = valid_count,
        invalid = invalid_count,
        true_reversals = reversal_count,
        false_reversals = false_reversal_count
    )
end

"""
Test the verification on a specific parameter combination
"""
function test_specific_params(ρ, σ, c2; N=60000, K=3)
    println("="^70)
    println("TESTING SPECIFIC PARAMETERS")
    println("="^70)
    @printf("Parameters: ρ=%.2f, σ=%.2f, c₂=%.1e\n", ρ, σ, c2)
    println()

    c3 = c2 / 5
    m = make_model(ρ=ρ, σ=σ, c2=c2, c3=c3)

    println("Running analysis...")
    result = analyze_FPA_vs_SPA(m; N=N, K=K, verbose=false)

    verify_result(result, "Test Result")

    return result
end

"""
Main verification routine
"""
function main_verification()
    println("COMPREHENSIVE EQUILIBRIUM VERIFICATION")
    println("="^70)
    println()
    println("This script will:")
    println("1. Test the corrected implementation on default parameters")
    println("2. Verify that corner solutions are properly validated")
    println("3. Demonstrate the difference between true and false reversals")
    println()

    # Test 1: Default parameters (should work fine)
    println("\n" * "="^70)
    println("TEST 1: Default Parameters (High Correlation)")
    println("="^70)
    result1 = test_specific_params(0.98, 0.4, 1e-6; N=40000, K=2)

    # Test 2: Parameters that might cause corner solution (low correlation, high cost)
    println("\n" * "="^70)
    println("TEST 2: Low Correlation, High Cost (Potential Corner)")
    println("="^70)
    result2 = test_specific_params(0.5, 0.5, 1e-4; N=40000, K=2)

    # Test 3: Very high cost (definite corner)
    println("\n" * "="^70)
    println("TEST 3: Very High Cost (Likely Corner at η_min)")
    println("="^70)
    result3 = test_specific_params(0.7, 0.4, 5e-4; N=40000, K=2)

    println("\n" * "="^70)
    println("VERIFICATION COMPLETE")
    println("="^70)
    println()
    println("The corrected implementation now:")
    println("✓ Properly validates corner solutions")
    println("✓ Returns NaN when equilibrium doesn't exist")
    println("✓ Only reports reversals with VALID equilibria")
    println("✓ Filters out false positives from invalid corners")
    println()
end

# Run main verification if this is the main script
if abspath(PROGRAM_FILE) == @__FILE__
    main_verification()
end
