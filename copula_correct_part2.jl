# ============================================================================
# CORRECT COPULA IMPLEMENTATION - PART 2
# Bidding Functions, Revenue, Equilibrium
# ============================================================================

# Load Part 1
include("copula_correct_implementation.jl")

# ============================================================================
# 7. BIDDING FUNCTIONS
# ============================================================================

"""
SPA bidding with correct copula conditional expectation
"""
function bid_spa_correct(x::Float64, η::Float64, m::CopulaModelCorrect,
                         D::CopulaDrawsCorrect)
    # Dominant strategy: bid E[V_i | X_i = x, X_j = x]
    return conditional_expectation_tie_correct(x, η, m, D)
end

"""
FPA bidding using ODE with correct hazard rate and conditional expectations
"""
function solve_bid_fpa_correct(η::Float64, m::CopulaModelCorrect,
                               D::CopulaDrawsCorrect; nx::Int=150)
    x_grid = range(m.vmin, m.vmax, length=nx)
    dx = x_grid[2] - x_grid[1]
    bid = zeros(nx)

    # Compute signal distribution for hazard rate
    signals = D.v1 .+ D.e1 ./ sqrt(η)

    # Boundary condition
    bid[nx] = conditional_expectation_correct(x_grid[nx], η, m)

    # Backward integration with correct hazard rate
    for i in (nx-1):-1:1
        x = x_grid[i]
        b = bid[i+1]

        # CORRECT: empirical hazard rate
        h_x = compute_hazard_rate(x, signals)

        # CORRECT: copula conditional expectation
        v_x = conditional_expectation_correct(x, η, m)

        # ODE: b'(x) = [v(x) - b(x)] * h(x)
        # RK4 integration (backward)
        k1 = -(v_x - b) * h_x

        x_mid = x + 0.5*dx
        v_mid = conditional_expectation_correct(x_mid, η, m)
        h_mid = compute_hazard_rate(x_mid, signals)
        k2 = -(v_mid - (b + 0.5*dx*k1)) * h_mid

        k3 = -(v_mid - (b + 0.5*dx*k2)) * h_mid

        x_next = x + dx
        v_next = conditional_expectation_correct(x_next, η, m)
        h_next = compute_hazard_rate(x_next, signals)
        k4 = -(v_next - (b + dx*k3)) * h_next

        bid[i] = b + (dx/6.0) * (k1 + 2.0*k2 + 2.0*k3 + k4)
    end

    return (collect(x_grid), bid)
end

# Bid cache for interpolation
struct BidCacheCorrect
    x_grid::Vector{Float64}
    bid::Vector{Float64}
    itp::Any  # Interpolation object
end

function create_bid_cache(x_grid::Vector{Float64}, bid::Vector{Float64})
    itp = linear_interpolation(x_grid, bid, extrapolation_bc=Line())
    return BidCacheCorrect(x_grid, bid, itp)
end

function eval_bid(x::Float64, cache::BidCacheCorrect)
    return cache.itp(clamp(x, cache.x_grid[1], cache.x_grid[end]))
end

# ============================================================================
# 8. REVENUE CALCULATION
# ============================================================================

"""
Revenue with correct copula implementation
"""
function revenue_correct(η::Float64, mech::Symbol, m::CopulaModelCorrect,
                        D::CopulaDrawsCorrect;
                        cache::Union{BidCacheCorrect,Nothing}=nothing)
    N = length(D.v1)
    revenue_sum = 0.0

    for i in 1:N
        x1 = D.v1[i] + D.e1[i] / sqrt(η)
        x2 = D.v2[i] + D.e2[i] / sqrt(η)

        if mech == :FPA
            if isnothing(cache)
                error("FPA requires bid cache")
            end
            b1 = eval_bid(x1, cache)
            b2 = eval_bid(x2, cache)
            revenue_sum += max(b1, b2)
        elseif mech == :SPA
            b1 = bid_spa_correct(x1, η, m, D)
            b2 = bid_spa_correct(x2, η, m, D)
            revenue_sum += min(b1, b2)
        end
    end

    return revenue_sum / N
end

"""
Expected payoff with correct implementation
"""
function expected_payoff_correct(η::Float64, mech::Symbol,
                                 m::CopulaModelCorrect, D::CopulaDrawsCorrect;
                                 cache::Union{BidCacheCorrect,Nothing}=nothing)
    N = length(D.v1)
    payoff_sum = 0.0

    for i in 1:N
        x1 = D.v1[i] + D.e1[i] / sqrt(η)
        x2 = D.v2[i] + D.e2[i] / sqrt(η)
        v1, v2 = D.v1[i], D.v2[i]

        if mech == :FPA
            if isnothing(cache)
                error("FPA requires bid cache")
            end
            b1 = eval_bid(x1, cache)
            b2 = eval_bid(x2, cache)
            if b1 > b2
                payoff_sum += v1 - b1
            else
                payoff_sum += v2 - b2
            end
        elseif mech == :SPA
            b1 = bid_spa_correct(x1, η, m, D)
            b2 = bid_spa_correct(x2, η, m, D)
            payment = min(b1, b2)
            if x1 > x2
                payoff_sum += v1 - payment
            else
                payoff_sum += v2 - payment
            end
        end
    end

    return payoff_sum / N
end

# ============================================================================
# 9. MARGINAL REVENUE (Richardson Extrapolation)
# ============================================================================

"""
Marginal revenue with correct copula implementation
WARNING: This is computationally expensive - each call solves 4-5 FPA ODEs
"""
function marginal_revenue_correct(η::Float64, mech::Symbol,
                                  m::CopulaModelCorrect, D::CopulaDrawsCorrect;
                                  h::Float64=0.1)
    # Pre-compute bid caches for different η values
    caches = Dict{Float64, Union{BidCacheCorrect,Nothing}}()

    if mech == :FPA
        for η_val in [η-h, η-h/2, η+h/2, η+h]
            η_clamped = clamp(η_val, m.ηmin, m.ηmax)
            println("    Computing FPA bids at η=$(round(η_clamped, digits=3))...")
            (x_grid, bid) = solve_bid_fpa_correct(η_clamped, m, D)
            caches[η_val] = create_bid_cache(x_grid, bid)
        end
    end

    # Payoff function
    function f(η_val::Float64)
        η_clamped = clamp(η_val, m.ηmin, m.ηmax)
        cache = get(caches, η_val, nothing)
        return expected_payoff_correct(η_clamped, mech, m, D, cache=cache)
    end

    # Richardson extrapolation for O(h^4) accuracy
    d1h = (f(η + h) - f(η - h)) / (2.0*h)
    d1h2 = (f(η + h/2) - f(η - h/2)) / h

    MR = (4.0 * d1h2 - d1h) / 3.0

    return MR
end

# ============================================================================
# 10. EQUILIBRIUM SOLVER
# ============================================================================

"""
Solve for equilibrium η* where MR(η*) = MC(η*)
With correct copula implementation
"""
function solve_equilibrium_correct(mech::Symbol, m::CopulaModelCorrect,
                                   D::CopulaDrawsCorrect;
                                   tol::Float64=1e-3, max_iter::Int=25)
    println("  Solving $(mech) equilibrium...")

    # Marginal cost function
    MC(η) = 2.0*m.c2*(η - m.ηmin) + 3.0*m.c3*(η - m.ηmin)^2

    # Initial guess
    η = (m.ηmin + m.ηmax) / 2

    for iter in 1:max_iter
        println("    Iteration $iter: η=$(round(η, digits=3))")

        # Compute marginal revenue (expensive!)
        MR = marginal_revenue_correct(η, mech, m, D)
        gap = MR - MC(η)

        println("      MR=$(round(MR, digits=4)), MC=$(round(MC(η), digits=4)), gap=$(round(gap, digits=4))")

        if abs(gap) < tol
            println("    ✓ Converged!")
            return (η=η, gap=gap, converged=true)
        end

        # Newton-like update
        MC_deriv = 2.0*m.c2 + 6.0*m.c3*(η - m.ηmin)
        step = 0.3 * gap / (MC_deriv + 1e-10)
        η_new = η + step

        # Clamp to bounds
        η = clamp(η_new, m.ηmin, m.ηmax)
    end

    # Check corner solutions
    println("    Did not converge, checking corners...")
    MR_min = marginal_revenue_correct(m.ηmin, mech, m, D)
    gap_min = MR_min - MC(m.ηmin)

    if abs(gap_min) < tol
        println("    ✓ Valid corner solution at η_min")
        return (η=m.ηmin, gap=gap_min, converged=true)
    end

    println("    ❌ No equilibrium found")
    MR_final = marginal_revenue_correct(η, mech, m, D)
    return (η=η, gap=MR_final - MC(η), converged=false)
end

# ============================================================================
# 11. COMPLETE TEST FUNCTION
# ============================================================================

"""
Test for revenue reversal with correct copula implementation
"""
function test_reversal_correct(copula_type::Symbol, θ::Float64, σ::Float64;
                                c2::Float64=1e-6, c3::Float64=2e-7,
                                N::Int=40000, verbose::Bool=true)
    if verbose
        println("="^70)
        @printf("Testing %s copula: θ=%.2f, σ=%.2f\n", copula_type, θ, σ)
        println("="^70)
    end

    # Create model
    m = CopulaModelCorrect(
        0.5, σ, 0.0, 1.0,  # μ, σ, vmin, vmax
        copula_type, θ,
        0.01, 10.0,  # ηmin, ηmax
        c2, c3
    )

    # Generate data
    println("Generating draws...")
    D = generate_copula_draws_correct(m; N=N)

    # Solve equilibria
    eqF = solve_equilibrium_correct(:FPA, m, D)
    eqS = solve_equilibrium_correct(:SPA, m, D)

    # Validate
    validF = eqF.converged && abs(eqF.gap) < 1e-3
    validS = eqS.converged && abs(eqS.gap) < 1e-3

    if !validF || !validS
        println("❌ Equilibria did not converge properly")
        return (reversal=false, valid=false, ηF=NaN, ηS=NaN,
                R_FPA=NaN, R_SPA=NaN, ratio=NaN)
    end

    # Calculate revenues
    println("Computing revenues...")
    (x_grid_F, bid_F) = solve_bid_fpa_correct(eqF.η, m, D)
    cacheF = create_bid_cache(x_grid_F, bid_F)

    R_FPA = revenue_correct(eqF.η, :FPA, m, D, cache=cacheF)
    R_SPA = revenue_correct(eqS.η, :SPA, m, D)

    ratio = R_FPA / R_SPA
    reversal = ratio > 1.0

    println("="^70)
    println("RESULTS:")
    @printf("  FPA: η*=%.3f, R=%.4f\n", eqF.η, R_FPA)
    @printf("  SPA: η*=%.3f, R=%.4f\n", eqS.η, R_SPA)
    @printf("  Ratio: %.4f ", ratio)
    if reversal
        println("🎉🎉🎉 REVERSAL FOUND! 🎉🎉🎉")
    else
        println("(no reversal)")
    end
    println("="^70)

    return (
        reversal=reversal, valid=true,
        ηF=eqF.η, ηS=eqS.η,
        R_FPA=R_FPA, R_SPA=R_SPA, ratio=ratio
    )
end

# ============================================================================
# 12. SEARCH FUNCTION
# ============================================================================

"""
Search across copula parameters with CORRECT implementation
"""
function search_copula_correct(;
    copula_types = [:clayton, :gumbel],
    θ_clayton = [1.0, 2.0, 4.0],
    θ_gumbel = [2.0, 3.0],
    σ_range = [0.3, 0.4, 0.5],
    c2_range = [1e-6],
    N = 40000
)
    println("="^70)
    println("CORRECT COPULA REVERSAL SEARCH")
    println("="^70)
    println("This uses proper copula conditional expectations,")
    println("correct Gumbel sampling, and empirical hazard rates.")
    println("Expect 50-100x slower than flawed implementation.")
    println("="^70)
    println()

    results = []
    reversals = 0

    # Clayton
    if :clayton in copula_types
        for θ in θ_clayton, σ in σ_range, c2 in c2_range
            try
                result = test_reversal_correct(:clayton, θ, σ, c2=c2, N=N)
                if result.reversal
                    reversals += 1
                    println("\n🎉🎉🎉 REVERSAL #$reversals FOUND! 🎉🎉🎉\n")
                end
                push!(results, merge((copula=:clayton, θ=θ, σ=σ, c2=c2), result))
            catch e
                println("Error: $e")
                push!(results, (copula=:clayton, θ=θ, σ=σ, c2=c2,
                               reversal=false, valid=false))
            end
        end
    end

    # Gumbel
    if :gumbel in copula_types
        for θ in θ_gumbel, σ in σ_range, c2 in c2_range
            try
                result = test_reversal_correct(:gumbel, θ, σ, c2=c2, N=N)
                if result.reversal
                    reversals += 1
                    println("\n🎉🎉🎉 REVERSAL #$reversals FOUND! 🎉🎉🎉\n")
                end
                push!(results, merge((copula=:gumbel, θ=θ, σ=σ, c2=c2), result))
            catch e
                println("Error: $e")
                push!(results, (copula=:gumbel, θ=θ, σ=σ, c2=c2,
                               reversal=false, valid=false))
            end
        end
    end

    # Summary
    println("\n" * "="^70)
    println("SEARCH COMPLETE")
    println("="^70)
    @printf("Total reversals found: %d\n", reversals)

    if reversals > 0
        println("\n🎉 Reversals at:")
        for r in filter(r -> get(r, :reversal, false), results)
            @printf("  %s θ=%.1f, σ=%.2f: ratio=%.4f\n",
                    r.copula, r.θ, r.σ, r.ratio)
        end
    end

    return results
end

# ============================================================================
# READY TO USE
# ============================================================================

println()
println("="^70)
println("CORRECT COPULA IMPLEMENTATION COMPLETE!")
println("="^70)
println()
println("To run rigorous copula search:")
println("  results = search_copula_correct()")
println()
println("WARNING: Each test takes 30-60 minutes!")
println("Default: 3 Clayton × 3 σ = 9 tests (~6-9 hours total)")
println("        2 Gumbel × 3 σ = 6 tests (~3-6 hours total)")
println("="^70)
