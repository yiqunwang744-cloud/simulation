# ============================================================================
# EXTENDED REVENUE REVERSAL SEARCH
# Theoretically-grounded exploration of broader parameter space
# ============================================================================
#
# This module extends the search for revenue reversals by:
# 1. Exploring much broader parameter ranges
# 2. Testing alternative (but theoretically valid) cost functions
# 3. Maintaining strict equilibrium validation (MR = MC)
# 4. All extensions are theoretically justified
#
# ============================================================================

include("comprehensive_julia_implementation.jl")

using Printf

# ============================================================================
# 1. ALTERNATIVE COST FUNCTION SPECIFICATIONS
# ============================================================================

"""
Cost function family
All must satisfy: C(η) convex, C'(η) > 0 for η > η_min
"""
abstract type CostFunction end

"""
Original: C(η) = c₂(η - η_min)² + c₃(η - η_min)³
"""
struct QuadraticCubicCost <: CostFunction
    c2::Float64
    c3::Float64
end

function cost_value(cf::QuadraticCubicCost, η::Float64, η_min::Float64)
    Δη = η - η_min
    return cf.c2 * Δη^2 + cf.c3 * Δη^3
end

function marginal_cost_value(cf::QuadraticCubicCost, η::Float64, η_min::Float64)
    Δη = η - η_min
    return 2 * cf.c2 * Δη + 3 * cf.c3 * Δη^2
end

"""
Pure quadratic: C(η) = c₂(η - η_min)²
More aggressive diminishing returns
"""
struct PureQuadraticCost <: CostFunction
    c2::Float64
end

function cost_value(cf::PureQuadraticCost, η::Float64, η_min::Float64)
    Δη = η - η_min
    return cf.c2 * Δη^2
end

function marginal_cost_value(cf::PureQuadraticCost, η::Float64, η_min::Float64)
    Δη = η - η_min
    return 2 * cf.c2 * Δη
end

"""
Linear-Quadratic: C(η) = c₁(η - η_min) + c₂(η - η_min)²
Less aggressive than pure quadratic
"""
struct LinearQuadraticCost <: CostFunction
    c1::Float64
    c2::Float64
end

function cost_value(cf::LinearQuadraticCost, η::Float64, η_min::Float64)
    Δη = η - η_min
    return cf.c1 * Δη + cf.c2 * Δη^2
end

function marginal_cost_value(cf::LinearQuadraticCost, η::Float64, η_min::Float64)
    Δη = η - η_min
    return cf.c1 + 2 * cf.c2 * Δη
end

"""
Power cost: C(η) = c × (η - η_min)^α, α ∈ (1, 3]
Flexible curvature
"""
struct PowerCost <: CostFunction
    c::Float64
    α::Float64

    function PowerCost(c::Float64, α::Float64)
        @assert α > 1.0 "Power α must be > 1 for convexity"
        @assert α ≤ 3.0 "Power α should be ≤ 3 for numerical stability"
        new(c, α)
    end
end

function cost_value(cf::PowerCost, η::Float64, η_min::Float64)
    Δη = η - η_min
    return cf.c * Δη^cf.α
end

function marginal_cost_value(cf::PowerCost, η::Float64, η_min::Float64)
    Δη = η - η_min
    if Δη < 1e-10
        return 0.0
    end
    return cf.c * cf.α * Δη^(cf.α - 1)
end

# ============================================================================
# 2. EXTENDED MODEL WITH FLEXIBLE COST FUNCTION
# ============================================================================

"""
Extended auction model with pluggable cost function
"""
struct ExtendedAuctionModel
    # Value distribution parameters
    μ::Float64
    σ::Float64
    ρ::Float64

    # Bounds
    vmin::Float64
    vmax::Float64
    ηmin::Float64
    ηmax::Float64

    # Cost function (polymorphic)
    cost_fn::CostFunction

    # Numerical tolerance
    tol::Float64
end

"""
Create extended model from standard parameters
"""
function make_extended_model(;
    μ = 0.5,
    σ = 0.4,
    ρ = 0.98,
    vmin = 0.0,
    vmax = 1.0,
    ηmin = 0.005,
    ηmax = 100.0,
    cost_fn = QuadraticCubicCost(1e-6, 2e-7),
    tol = 1e-10
)
    return ExtendedAuctionModel(μ, σ, ρ, vmin, vmax, ηmin, ηmax, cost_fn, tol)
end

"""
Convert extended model to standard model for compatibility
Creates a standard model with cost function baked in
"""
function to_standard_model(em::ExtendedAuctionModel)
    # For standard model, we need c2 and c3 values
    # Extract them from the cost function if possible
    if typeof(em.cost_fn) == QuadraticCubicCost
        c2 = em.cost_fn.c2
        c3 = em.cost_fn.c3
    elseif typeof(em.cost_fn) == PureQuadraticCost
        c2 = em.cost_fn.c2
        c3 = 0.0
    elseif typeof(em.cost_fn) == LinearQuadraticCost
        # Approximate with c2, ignore linear term for standard model
        c2 = em.cost_fn.c2
        c3 = 0.0
    else
        # For power costs, approximate with quadratic
        c2 = em.cost_fn.c
        c3 = 0.0
    end

    return make_model(
        μ = em.μ,
        σ = em.σ,
        ρ = em.ρ,
        vmin = em.vmin,
        vmax = em.vmax,
        ηmin = em.ηmin,
        ηmax = em.ηmax,
        c2 = c2,
        c3 = c3,
        tol = em.tol
    )
end

"""
Marginal cost for extended model
"""
function MC_extended(η::Float64, em::ExtendedAuctionModel)
    return marginal_cost_value(em.cost_fn, η, em.ηmin)
end

"""
Solve equilibrium with extended model
Adapts the standard solver to use custom cost function
"""
function solve_eta_star_extended(mech::Symbol, em::ExtendedAuctionModel;
                                 N::Int=120000, K::Int=4, seed::Int=42,
                                 h_frac::Float64=0.01,
                                 tol_abs::Float64=1e-5, tol_se::Float64=5e-6,
                                 max_iter::Int=60)

    # Convert to standard model for signal/bidding calculations
    m = to_standard_model(em)

    a = em.ηmin + 1e-4
    b = em.ηmax

    # Evaluate at boundaries
    μFa, seFa = MR_with_CI(a, mech, m; K=K, N=N, seed=seed, h_frac=h_frac)
    μFa -= MC_extended(a, em)  # Use extended MC!

    μFb, seFb = MR_with_CI(b, mech, m; K=K, N=N, seed=seed+1, h_frac=h_frac)
    μFb -= MC_extended(b, em)  # Use extended MC!

    sL = sign_CI(μFa, seFa)
    sR = sign_CI(μFb, seFb)

    # Validate corner solutions
    if sL == +1 && sR == +1
        if abs(μFb) ≤ tol_abs && seFb ≤ tol_se
            return b, μFb, seFb
        else
            return NaN, μFb, seFb
        end
    end

    if sL == -1 && sR == -1
        if abs(μFa) ≤ tol_abs && seFa ≤ tol_se
            return a, μFa, seFa
        else
            return NaN, μFa, seFa
        end
    end

    # Bisection
    for iter in 1:max_iter
        c = (a + b) / 2
        μFc, seFc = MR_with_CI(c, mech, m; K=K, N=N, seed=seed+iter+10, h_frac=h_frac)
        μFc -= MC_extended(c, em)  # Use extended MC!
        sc = sign_CI(μFc, seFc)

        if abs(μFc) ≤ tol_abs && seFc ≤ tol_se
            return c, μFc, seFc
        end

        sLa = (sL == 0) ? (μFa ≥ 0 ? +1 : -1) : sL
        scm = (sc == 0) ? (μFc ≥ 0 ? +1 : -1) : sc

        if sLa * scm < 0
            b = c
            μFb = μFc
            seFb = seFc
            sR = sc
        else
            a = c
            μFa = μFc
            seFa = seFc
            sL = sc
        end

        if b - a < 1e-6
            return c, μFc, seFc
        end
    end

    # Max iterations
    c = (a + b) / 2
    μFc, seFc = MR_with_CI(c, mech, m; K=K, N=N, seed=seed+max_iter+100, h_frac=h_frac)
    μFc -= MC_extended(c, em)

    return c, μFc, seFc
end

"""
Full analysis with extended model
"""
function analyze_extended(em::ExtendedAuctionModel;
                         N::Int=120000, K::Int=4, verbose::Bool=true)

    if verbose
        println("="^70)
        println("EXTENDED ANALYSIS WITH CUSTOM COST FUNCTION")
        println("="^70)
        println("Parameters:")
        @printf("  Value distribution: N(%.2f, %.2f²) with correlation ρ=%.3f\n", em.μ, em.σ, em.ρ)
        println("  Cost function: $(typeof(em.cost_fn))")
        println()
    end

    # Solve equilibria
    if verbose
        println("Solving for equilibrium information acquisition...")
    end

    ηF, gapF, seF = solve_eta_star_extended(:FPA, em; N=N, K=K)
    ηS, gapS, seS = solve_eta_star_extended(:SPA, em; N=N, K=K, seed=12345)

    # Validate
    validF = is_valid_equilibrium(ηF, gapF, seF)
    validS = is_valid_equilibrium(ηS, gapS, seS)

    if verbose
        println("-"^70)
        println("EQUILIBRIUM RESULTS (MR = MC):")

        if isnan(ηF)
            println("FPA: ❌ FAILED - No equilibrium found")
        else
            @printf("FPA: η* = %.5f | MR-MC = %+.3e (SE ≈ %.2e)", ηF, gapF, seF)
            println(validF ? " ✓" : " ❌ INVALID (|MR-MC| too large)")
        end

        if isnan(ηS)
            println("SPA: ❌ FAILED - No equilibrium found")
        else
            @printf("SPA: η* = %.5f | MR-MC = %+.3e (SE ≈ %.2e)", ηS, gapS, seS)
            println(validS ? " ✓" : " ❌ INVALID (|MR-MC| too large)")
        end

        if validF && validS
            println(ηF > ηS ? "\n✓ Theoretical ranking: η*_FPA > η*_SPA" : "\n⚠ Unexpected: η*_FPA ≤ η*_SPA")
        else
            println("\n⚠ Cannot verify ranking - invalid equilibria")
        end
        println()
    end

    # Calculate revenues if both valid
    if validF && validS
        if verbose
            println("Calculating seller revenues at equilibrium...")
        end

        m = to_standard_model(em)
        D = make_draws(m; N=N, seed=54321, antithetic=true)
        cacheF = precompute_bids_FPA(ηF, m)

        RF = revenue(ηF, :FPA, m, D; cacheFPA=cacheF)
        RS = revenue(ηS, :SPA, m, D)

        if verbose
            println("-"^70)
            println("SELLER REVENUE:")
            @printf("R_FPA(η*) = %.6f\n", RF)
            @printf("R_SPA(η*) = %.6f\n", RS)
            @printf("Ratio: R_FPA/R_SPA = %.6f\n", RF/RS)

            if RF > RS
                println("🎉 REVERSAL FOUND: R_FPA > R_SPA!")
                @printf("    FPA revenue exceeds SPA by %.2f%%\n", (RF/RS - 1) * 100)
            else
                println("Standard result: R_FPA < R_SPA")
                @printf("    SPA revenue exceeds FPA by %.2f%%\n", (RS/RF - 1) * 100)
            end
            println("="^70)
        end

        return (
            ηF = ηF, ηS = ηS,
            gapF = gapF, gapS = gapS,
            seF = seF, seS = seS,
            validF = validF, validS = validS,
            RF = RF, RS = RS,
            ratio = RF/RS,
            reversal = (RF > RS),
            cost_type = string(typeof(em.cost_fn))
        )
    else
        if verbose
            println("⚠ Skipping revenue calculation - invalid equilibria")
            println("="^70)
        end

        return (
            ηF = ηF, ηS = ηS,
            gapF = gapF, gapS = gapS,
            seF = seF, seS = seS,
            validF = validF, validS = validS,
            RF = NaN, RS = NaN,
            ratio = NaN,
            reversal = false,
            cost_type = string(typeof(em.cost_fn))
        )
    end
end

# ============================================================================
# 3. EXTENDED PARAMETER SEARCH
# ============================================================================

"""
Comprehensive search across:
1. Broader parameter ranges
2. Multiple cost function types
3. Finer grids in promising regions
"""
function extended_reversal_search(;
    # EXPANDED parameter ranges
    ρ_range = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 0.98],
    σ_range = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8],

    # Cost function specifications to test
    cost_functions = [
        # Original quadratic-cubic
        QuadraticCubicCost(1e-6, 2e-7),
        QuadraticCubicCost(5e-7, 1e-7),
        QuadraticCubicCost(1e-7, 2e-8),

        # Pure quadratic (more aggressive)
        PureQuadraticCost(1e-6),
        PureQuadraticCost(5e-7),
        PureQuadraticCost(2e-7),

        # Linear-quadratic (less aggressive)
        LinearQuadraticCost(1e-7, 5e-7),
        LinearQuadraticCost(5e-8, 2e-7),

        # Power costs
        PowerCost(1e-6, 1.5),
        PowerCost(1e-6, 2.0),
        PowerCost(1e-6, 2.5),
    ],

    N = 40000,  # Reduced for broader search
    K = 2,
    verbose = true
)

    results = []
    total = length(ρ_range) * length(σ_range) * length(cost_functions)
    current = 0

    if verbose
        println("="^70)
        println("EXTENDED REVERSAL SEARCH")
        println("="^70)
        println("Testing $(total) combinations:")
        println("  - ρ values: $(length(ρ_range))")
        println("  - σ values: $(length(σ_range))")
        println("  - Cost functions: $(length(cost_functions))")
        println()
        println("Estimated time: $(round(total * 3 / 60, digits=1)) minutes")
        println()
    end

    for ρ in ρ_range, σ in σ_range, cost_fn in cost_functions
        current += 1

        if verbose && current % 20 == 1
            @printf("Progress: %d/%d (%.1f%%)\n", current, total, 100*current/total)
        end

        try
            em = make_extended_model(ρ=ρ, σ=σ, cost_fn=cost_fn)
            result = analyze_extended(em; N=N, K=K, verbose=false)

            push!(results, merge(result, (ρ=ρ, σ=σ)))

            if result.reversal && verbose
                @printf("  ✓ REVERSAL: ρ=%.2f, σ=%.2f, %s → ratio=%.4f\n",
                        ρ, σ, result.cost_type, result.ratio)
            end
        catch e
            if verbose
                @printf("  ✗ Error at ρ=%.2f, σ=%.2f: %s\n", ρ, σ, string(e))
            end
        end
    end

    # Summary
    if verbose
        println()
        println("="^70)
        println("EXTENDED SEARCH RESULTS")
        println("="^70)

        valid_results = filter(r -> r.validF && r.validS, results)
        reversals = filter(r -> r.validF && r.validS && r.reversal, results)

        @printf("Total combinations: %d\n", length(results))
        @printf("Valid equilibria: %d (%.1f%%)\n",
                length(valid_results), 100*length(valid_results)/max(1,length(results)))
        @printf("\n🎯 TRUE REVERSALS: %d (%.1f%% of valid)\n",
                length(reversals), 100*length(reversals)/max(1, length(valid_results)))

        if length(reversals) > 0
            println("\n🎉 SUCCESS! REVERSALS FOUND! 🎉")
            println("\nTop 10 reversals by ratio:")
            sort!(reversals, by=r->r.ratio, rev=true)
            for (i, r) in enumerate(reversals[1:min(10, length(reversals))])
                @printf("  %d. ρ=%.2f, σ=%.2f, %s\n", i, r.ρ, r.σ, r.cost_type)
                @printf("      Ratio=%.4f (FPA wins by %.1f%%)\n", r.ratio, (r.ratio-1)*100)
                @printf("      η_F=%.3f, η_S=%.3f (gaps: %.1e, %.1e)\n",
                        r.ηF, r.ηS, r.gapF, r.gapS)
                println()
            end

            # Analyze patterns
            println("PATTERN ANALYSIS:")

            # By correlation
            low_rho = filter(r -> r.ρ < 0.5, reversals)
            @printf("  Low correlation (ρ<0.5): %d reversals (%.1f%%)\n",
                    length(low_rho), 100*length(low_rho)/length(reversals))

            # By variance
            high_sigma = filter(r -> r.σ > 0.5, reversals)
            @printf("  High variance (σ>0.5): %d reversals (%.1f%%)\n",
                    length(high_sigma), 100*length(high_sigma)/length(reversals))

            # By cost function
            println("\n  By cost function type:")
            cost_types = unique([r.cost_type for r in reversals])
            for ct in cost_types
                count = length(filter(r -> r.cost_type == ct, reversals))
                @printf("    %s: %d reversals\n", ct, count)
            end

        else
            println("\n❌ NO REVERSALS FOUND")
            println("\nClosest to reversal (top 5):")
            valid_with_ratio = filter(r -> !isnan(r.ratio), valid_results)
            if length(valid_with_ratio) > 0
                sort!(valid_with_ratio, by=r->abs(r.ratio-1))
                for (i, r) in enumerate(valid_with_ratio[1:min(5, length(valid_with_ratio))])
                    @printf("  %d. ρ=%.2f, σ=%.2f, %s: ratio=%.4f\n",
                            i, r.ρ, r.σ, r.cost_type, r.ratio)
                end
            end
        end
        println("="^70)
    end

    return results
end

"""
Focused search around promising parameters
Once we find regions close to reversal, zoom in
"""
function focused_search(ρ_center, σ_center, cost_fn;
                       ρ_range_width = 0.1,
                       σ_range_width = 0.1,
                       n_points = 5,
                       N = 60000,
                       K = 3)

    println("="^70)
    println("FOCUSED SEARCH")
    println("="^70)
    @printf("Center: ρ=%.2f, σ=%.2f\n", ρ_center, σ_center)
    println("Cost function: $(typeof(cost_fn))")
    println()

    ρ_range = range(max(0.05, ρ_center - ρ_range_width),
                    min(0.99, ρ_center + ρ_range_width),
                    length=n_points)
    σ_range = range(max(0.05, σ_center - σ_range_width),
                    min(0.95, σ_center + σ_range_width),
                    length=n_points)

    results = []

    for ρ in ρ_range, σ in σ_range
        try
            em = make_extended_model(ρ=ρ, σ=σ, cost_fn=cost_fn)
            result = analyze_extended(em; N=N, K=K, verbose=false)
            push!(results, merge(result, (ρ=ρ, σ=σ)))

            if result.reversal
                @printf("✓ REVERSAL: ρ=%.3f, σ=%.3f, ratio=%.4f\n", ρ, σ, result.ratio)
            end
        catch e
            println("Error at ρ=$ρ, σ=$σ: $e")
        end
    end

    # Find best
    reversals = filter(r -> r.validF && r.validS && r.reversal, results)

    if length(reversals) > 0
        best = reversals[argmax([r.ratio for r in reversals])]
        println("\n🎉 Best reversal in focused region:")
        @printf("  ρ=%.4f, σ=%.4f\n", best.ρ, best.σ)
        @printf("  Ratio=%.4f (FPA wins by %.2f%%)\n", best.ratio, (best.ratio-1)*100)
        @printf("  η_F=%.3f, η_S=%.3f\n", best.ηF, best.ηS)
    else
        println("\n❌ No reversals in focused region")
        valid = filter(r -> r.validF && r.validS, results)
        if length(valid) > 0
            closest = valid[argmin([abs(r.ratio - 1) for r in valid])]
            @printf("  Closest: ρ=%.4f, σ=%.4f, ratio=%.4f\n",
                    closest.ρ, closest.σ, closest.ratio)
        end
    end
    println("="^70)

    return results
end

# ============================================================================
# 4. EXECUTION
# ============================================================================

"""
Run full extended search
"""
function run_extended_search()
    println("LAUNCHING EXTENDED REVERSAL SEARCH")
    println("This explores:")
    println("  - Much broader parameter ranges")
    println("  - Multiple cost function types")
    println("  - ~900 combinations total")
    println()

    results = extended_reversal_search(
        ρ_range = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 0.98],
        σ_range = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8],
        N = 40000,
        K = 2,
        verbose = true
    )

    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    println("Starting extended reversal search...")
    println("This maintains theoretical rigor while exploring broader space")
    println()

    results = run_extended_search()

    println("\n✅ Extended search complete!")
end
