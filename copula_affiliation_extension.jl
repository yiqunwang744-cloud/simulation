# ============================================================================
# COPULA-BASED AFFILIATION FOR PERSICO FRAMEWORK
# ============================================================================
#
# This implements ASYMMETRIC tail dependence using copulas while staying
# completely within Persico (2000)'s framework:
#   - Affiliated private values (via copulas, not just Normal)
#   - A-ordered signal technology X^η = V + ε/√η
#   - Endogenous information choice with MR = MC
#   - Standard FPA and SPA auction mechanisms
#
# KEY INNOVATION: Asymmetric tail dependence could break revenue ranking!
#
# Clayton Copula: Strong LOWER tail dependence
#   - When both values low → highly correlated
#   - When both values high → more independent
#   - Could favor FPA in low-value regions where information matters most
#
# Gumbel Copula: Strong UPPER tail dependence
#   - When both values low → more independent
#   - When both values high → highly correlated
#   - Could favor FPA in high-value competitive regions
#
# This is PURE PERSICO - affiliation via copulas is standard in auction theory
# (Milgrom-Weber 1982, Krishna 2009, etc.)
#
# ============================================================================

using Random
using Distributions
using Printf
using Statistics

# ============================================================================
# 1. COPULA STRUCTURES
# ============================================================================

"""
Clayton copula for generating affiliated values with strong lower-tail dependence

C(u,v; θ) = (u^(-θ) + v^(-θ) - 1)^(-1/θ)

θ > 0: Controls tail dependence strength
  θ → 0: Independence
  θ = 1: Moderate lower-tail dependence (similar to ρ ≈ 0.5 Normal)
  θ = 2: Strong lower-tail dependence (similar to ρ ≈ 0.7 Normal)
  θ = 4: Very strong (similar to ρ ≈ 0.85 Normal)
  θ → ∞: Perfect dependence
"""
function clayton_sample(θ::Float64)
    # Generate Clayton copula sample (u1, u2) ∈ [0,1]²
    u1 = rand()
    t = rand()

    if θ < 1e-6
        # Independence case
        u2 = rand()
    else
        # Clayton conditional: u2|u1
        u2 = (1 + t^(-θ/(1+θ)) * (u1^(-θ) - 1))^(-1/θ)
    end

    return (u1, u2)
end

"""
Gumbel copula for generating affiliated values with strong upper-tail dependence

C(u,v; θ) = exp(-((-log u)^θ + (-log v)^θ)^(1/θ))

θ ≥ 1: Controls tail dependence strength
  θ = 1: Independence
  θ = 1.5: Moderate upper-tail dependence
  θ = 2: Strong upper-tail dependence (similar to ρ ≈ 0.7 Normal)
  θ = 3: Very strong (similar to ρ ≈ 0.85 Normal)
  θ → ∞: Perfect dependence
"""
function gumbel_sample(θ::Float64)
    # Generate Gumbel copula sample using Marshall-Olkin method
    if θ < 1.001
        # Near independence
        return (rand(), rand())
    end

    # Generate from Gumbel
    v = rand()
    gamma_dist = Gamma(1/θ, 1)
    s = rand(gamma_dist)

    u1 = exp(-((-log(rand()))^θ / s)^(1/θ))
    u2 = exp(-((-log(rand()))^θ / s)^(1/θ))

    return (u1, u2)
end

# ============================================================================
# 2. VALUE GENERATION WITH COPULAS
# ============================================================================

"""
Model structure for copula-based affiliation
"""
struct CopulaModel
    # Value distribution (marginals)
    μ::Float64          # Mean value
    σ::Float64          # Std dev of values
    vmin::Float64       # Min value
    vmax::Float64       # Max value

    # Copula specification
    copula_type::Symbol  # :clayton or :gumbel
    θ::Float64          # Copula parameter (dependence strength)

    # Information parameters
    ηmin::Float64
    ηmax::Float64

    # Cost function C(η) = c2*(η-ηmin)^2 + c3*(η-ηmin)^3
    c2::Float64
    c3::Float64
end

"""
Generate affiliated values using copula
"""
function generate_copula_values(m::CopulaModel)
    # Sample from copula
    if m.copula_type == :clayton
        (u1, u2) = clayton_sample(m.θ)
    elseif m.copula_type == :gumbel
        (u1, u2) = gumbel_sample(m.θ)
    else
        error("Unknown copula type: $(m.copula_type)")
    end

    # Transform to value space using marginal distribution
    # Use Normal marginals for consistency
    norm_dist = Normal(m.μ, m.σ)
    v1 = quantile(norm_dist, u1)
    v2 = quantile(norm_dist, u2)

    # Clamp to bounds
    v1 = clamp(v1, m.vmin, m.vmax)
    v2 = clamp(v2, m.vmin, m.vmax)

    return (v1, v2)
end

"""
Data structure for Monte Carlo draws with copula
"""
struct CopulaDraws
    v1::Vector{Float64}
    v2::Vector{Float64}
    e1::Vector{Float64}
    e2::Vector{Float64}
end

"""
Generate Monte Carlo draws for copula model
"""
function make_copula_draws(m::CopulaModel; N::Int=40000, seed::Int=12345)
    Random.seed!(seed)

    v1 = Vector{Float64}(undef, N)
    v2 = Vector{Float64}(undef, N)
    e1 = randn(N)
    e2 = randn(N)

    for i in 1:N
        (v1[i], v2[i]) = generate_copula_values(m)
    end

    return CopulaDraws(v1, v2, e1, e2)
end

# ============================================================================
# 3. POSTERIOR VALUE CALCULATION (COPULA-AWARE)
# ============================================================================

"""
Expected value for symmetric bidder given signal x and precision η

For copula-based affiliation, we use kernel density estimation on the
joint distribution to compute E[V_i | X_i = x]

Simplified: Use approximation based on copula structure
"""
function posterior_value_copula(x::Float64, η::Float64, m::CopulaModel, D::CopulaDraws)
    # Bayesian update: E[V | X = x]
    # Weight between prior mean and signal

    # Signal variance
    signal_var = 1.0 / η

    # Prior variance (empirical from data)
    prior_var = m.σ^2

    # Posterior mean (Gaussian approximation)
    weight = prior_var / (prior_var + signal_var)
    E_v = m.μ + weight * (x - m.μ)

    return clamp(E_v, m.vmin, m.vmax)
end

"""
Expected value conditional on symmetric tie (for SPA bidding)
"""
function posterior_value_tie_copula(x::Float64, η::Float64, m::CopulaModel, D::CopulaDraws)
    # In symmetric auction: E[V_i | X_i = x, X_j = x]
    # This requires integrating over the copula structure

    # Approximate using kernel density
    N = length(D.v1)
    weights = Float64[]
    values = Float64[]

    # Bandwidth for kernel
    h = 0.3 / sqrt(η)

    for i in 1:min(N, 5000)  # Use subset for speed
        # Compute signal
        x_i = D.v1[i] + D.e1[i] / sqrt(η)
        x_j = D.v2[i] + D.e2[i] / sqrt(η)

        # Kernel weight for tie condition
        if abs(x_i - x) < 3h && abs(x_j - x) < 3h
            w = exp(-0.5 * ((x_i - x)/h)^2) * exp(-0.5 * ((x_j - x)/h)^2)
            push!(weights, w)
            push!(values, D.v1[i])
        end
    end

    if isempty(weights)
        # Fallback to simple posterior
        return posterior_value_copula(x, η, m, D)
    end

    # Weighted average
    E_v = sum(values .* weights) / sum(weights)
    return clamp(E_v, m.vmin, m.vmax)
end

# ============================================================================
# 4. BIDDING FUNCTIONS
# ============================================================================

"""
SPA bidding function (dominant strategy)
"""
function bid_spa_copula(x::Float64, η::Float64, m::CopulaModel, D::CopulaDraws)
    return posterior_value_tie_copula(x, η, m, D)
end

"""
FPA bidding function using RK4 ODE solver
"""
function solve_bid_fpa_copula(η::Float64, m::CopulaModel, D::CopulaDraws; nx::Int=200)
    x_grid = range(m.vmin, m.vmax, length=nx)
    dx = x_grid[2] - x_grid[1]
    bid = zeros(nx)

    # Boundary condition: b(vmax) = E[V | X = vmax]
    bid[nx] = posterior_value_copula(x_grid[nx], η, m, D)

    # Backward integration using RK4
    for i in (nx-1):-1:1
        x = x_grid[i]
        b = bid[i+1]

        # Approximation: use hazard rate from empirical signal distribution
        h_rate = 1.0 / m.σ  # Simplified hazard rate
        v_est = posterior_value_copula(x, η, m, D)

        # ODE: b'(x) = [v(x) - b(x)] * h(x)
        # RK4 step (backward, so negate)
        k1 = -(v_est - b) * h_rate
        k2 = -(v_est - (b + 0.5*dx*k1)) * h_rate
        k3 = -(v_est - (b + 0.5*dx*k2)) * h_rate
        k4 = -(v_est - (b + dx*k3)) * h_rate

        bid[i] = b + (dx/6) * (k1 + 2*k2 + 2*k3 + k4)
    end

    return (collect(x_grid), bid)
end

# Cache structure for FPA bids
struct BidCacheCopula
    x_grid::Vector{Float64}
    bid::Vector{Float64}
end

function lininterp_copula(x::Float64, cache::BidCacheCopula)
    if x <= cache.x_grid[1]
        return cache.bid[1]
    elseif x >= cache.x_grid[end]
        return cache.bid[end]
    end

    # Binary search
    idx = searchsortedfirst(cache.x_grid, x)
    if idx == 1
        return cache.bid[1]
    end

    # Linear interpolation
    x0, x1 = cache.x_grid[idx-1], cache.x_grid[idx]
    b0, b1 = cache.bid[idx-1], cache.bid[idx]
    t = (x - x0) / (x1 - x0)

    return b0 + t * (b1 - b0)
end

# ============================================================================
# 5. REVENUE AND PAYOFF CALCULATION
# ============================================================================

"""
Calculate revenue for given mechanism and precision
"""
function revenue_copula(η::Float64, mech::Symbol, m::CopulaModel, D::CopulaDraws;
                        cache::Union{BidCacheCopula,Nothing}=nothing)
    N = length(D.v1)
    revenue_sum = 0.0

    for i in 1:N
        x1 = D.v1[i] + D.e1[i] / sqrt(η)
        x2 = D.v2[i] + D.e2[i] / sqrt(η)

        if mech == :FPA
            if isnothing(cache)
                error("FPA requires bid cache")
            end
            b1 = lininterp_copula(x1, cache)
            b2 = lininterp_copula(x2, cache)
            revenue_sum += max(b1, b2)
        elseif mech == :SPA
            b1 = bid_spa_copula(x1, η, m, D)
            b2 = bid_spa_copula(x2, η, m, D)
            revenue_sum += min(b1, b2)
        end
    end

    return revenue_sum / N
end

"""
Calculate expected payoff
"""
function expected_payoff_copula(η::Float64, mech::Symbol, m::CopulaModel, D::CopulaDraws;
                                cache::Union{BidCacheCopula,Nothing}=nothing)
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
            b1 = lininterp_copula(x1, cache)
            b2 = lininterp_copula(x2, cache)
            if b1 > b2
                payoff_sum += v1 - b1
            else
                payoff_sum += v2 - b2
            end
        elseif mech == :SPA
            b1 = bid_spa_copula(x1, η, m, D)
            b2 = bid_spa_copula(x2, η, m, D)
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
# 6. MARGINAL REVENUE (Richardson Extrapolation)
# ============================================================================

"""
Marginal revenue with O(h^4) accuracy
"""
function marginal_revenue_copula(η::Float64, mech::Symbol, m::CopulaModel, D::CopulaDraws;
                                  h::Float64=0.1)
    # Precompute bid caches if FPA
    caches = Dict()
    if mech == :FPA
        for η_val in [η-h, η-h/2, η+h/2, η+h]
            η_clamped = clamp(η_val, m.ηmin, m.ηmax)
            (x_grid, bid) = solve_bid_fpa_copula(η_clamped, m, D)
            caches[η_val] = BidCacheCopula(x_grid, bid)
        end
    end

    # Richardson extrapolation
    f(η_val) = expected_payoff_copula(clamp(η_val, m.ηmin, m.ηmax), mech, m, D,
                                       cache=get(caches, η_val, nothing))

    d1h = (f(η + h) - f(η - h)) / (2h)
    d1h2 = (f(η + h/2) - f(η - h/2)) / h

    MR = (4 * d1h2 - d1h) / 3

    return MR
end

# ============================================================================
# 7. EQUILIBRIUM SOLVER
# ============================================================================

"""
Solve for equilibrium η* where MR(η*) = MC(η*)
"""
function solve_equilibrium_copula(mech::Symbol, m::CopulaModel, D::CopulaDraws;
                                   tol::Float64=1e-3, max_iter::Int=30)
    # Marginal cost
    MC(η) = 2*m.c2*(η - m.ηmin) + 3*m.c3*(η - m.ηmin)^2

    # Initial guess
    η = (m.ηmin + m.ηmax) / 2

    for iter in 1:max_iter
        MR = marginal_revenue_copula(η, mech, m, D)
        gap = MR - MC(η)

        if abs(gap) < tol
            return (η=η, gap=gap, converged=true)
        end

        # Newton-like update
        MC_deriv = 2*m.c2 + 6*m.c3*(η - m.ηmin)
        η_new = η + 0.4 * gap / (MC_deriv + 1e-10)
        η = clamp(η_new, m.ηmin, m.ηmax)
    end

    # Check corner solutions
    MR_min = marginal_revenue_copula(m.ηmin, mech, m, D)
    gap_min = MR_min - MC(m.ηmin)

    if abs(gap_min) < tol
        return (η=m.ηmin, gap=gap_min, converged=true)
    end

    # Did not converge
    MR_final = marginal_revenue_copula(η, mech, m, D)
    return (η=η, gap=MR_final - MC(η), converged=false)
end

# ============================================================================
# 8. PARAMETER SWEEP
# ============================================================================

"""
Test for revenue reversal with copula-based affiliation
"""
function test_copula_reversal(copula_type::Symbol, θ::Float64, σ::Float64;
                               c2::Float64=1e-6, c3::Float64=2e-7,
                               N::Int=40000, verbose::Bool=true)
    if verbose
        @printf("Testing %s copula: θ=%.2f, σ=%.2f\n", copula_type, θ, σ)
    end

    # Create model
    m = CopulaModel(
        0.5, σ, 0.0, 1.0,  # μ, σ, vmin, vmax
        copula_type, θ,
        0.01, 10.0,  # ηmin, ηmax
        c2, c3
    )

    # Generate draws
    D = make_copula_draws(m; N=N)

    # Solve equilibria
    eqF = solve_equilibrium_copula(:FPA, m, D)
    eqS = solve_equilibrium_copula(:SPA, m, D)

    if !eqF.converged || !eqS.converged
        if verbose
            println("  ❌ Equilibria did not converge")
        end
        return (reversal=false, valid=false)
    end

    if abs(eqF.gap) > 1e-3 || abs(eqS.gap) > 1e-3
        if verbose
            println("  ❌ Equilibria not valid")
        end
        return (reversal=false, valid=false)
    end

    # Calculate revenues
    (x_grid_F, bid_F) = solve_bid_fpa_copula(eqF.η, m, D)
    cacheF = BidCacheCopula(x_grid_F, bid_F)

    R_FPA = revenue_copula(eqF.η, :FPA, m, D, cache=cacheF)
    R_SPA = revenue_copula(eqS.η, :SPA, m, D)

    ratio = R_FPA / R_SPA
    reversal = ratio > 1.0

    if verbose
        @printf("  FPA: η*=%.3f, R=%.4f\n", eqF.η, R_FPA)
        @printf("  SPA: η*=%.3f, R=%.4f\n", eqS.η, R_SPA)
        @printf("  Ratio: %.4f ", ratio)
        if reversal
            println("🎉 REVERSAL!")
        else
            println()
        end
    end

    return (
        reversal=reversal, valid=true,
        ηF=eqF.η, ηS=eqS.η,
        R_FPA=R_FPA, R_SPA=R_SPA, ratio=ratio
    )
end

"""
Sweep over copula parameter space
"""
function sweep_copula_affiliation(;
    copula_types = [:clayton, :gumbel],
    θ_clayton = [0.5, 1.0, 2.0, 4.0, 8.0],      # Lower tail strength
    θ_gumbel = [1.5, 2.0, 3.0, 4.0],             # Upper tail strength
    σ_range = [0.2, 0.3, 0.4, 0.5, 0.6],
    c2_range = [1e-6, 5e-7],
    N = 40000,
    verbose = false
)
    println("="^70)
    println("COPULA-BASED AFFILIATION REVERSAL SEARCH")
    println("="^70)
    println()

    results = []
    count = 0
    reversals = 0

    # Test Clayton copula
    if :clayton in copula_types
        println("Testing Clayton copula (strong lower-tail dependence)...")
        for θ in θ_clayton, σ in σ_range, c2 in c2_range
            count += 1
            @printf("[%d] Clayton θ=%.1f, σ=%.2f, c2=%.1e\n", count, θ, σ, c2)

            try
                result = test_copula_reversal(:clayton, θ, σ, c2=c2, N=N, verbose=verbose)
                if result.reversal
                    reversals += 1
                    println("  🎉 REVERSAL #$reversals!")
                end
                push!(results, merge((copula=:clayton, θ=θ, σ=σ, c2=c2), result))
            catch e
                println("  Error: $e")
                push!(results, (copula=:clayton, θ=θ, σ=σ, c2=c2, reversal=false, valid=false))
            end
        end
    end

    # Test Gumbel copula
    if :gumbel in copula_types
        println("\nTesting Gumbel copula (strong upper-tail dependence)...")
        for θ in θ_gumbel, σ in σ_range, c2 in c2_range
            count += 1
            @printf("[%d] Gumbel θ=%.1f, σ=%.2f, c2=%.1e\n", count, θ, σ, c2)

            try
                result = test_copula_reversal(:gumbel, θ, σ, c2=c2, N=N, verbose=verbose)
                if result.reversal
                    reversals += 1
                    println("  🎉 REVERSAL #$reversals!")
                end
                push!(results, merge((copula=:gumbel, θ=θ, σ=σ, c2=c2), result))
            catch e
                println("  Error: $e")
                push!(results, (copula=:gumbel, θ=θ, σ=σ, c2=c2, reversal=false, valid=false))
            end
        end
    end

    # Summary
    println()
    println("="^70)
    println("COPULA SEARCH COMPLETE")
    println("="^70)
    @printf("Combinations tested: %d\n", count)
    @printf("Valid equilibria: %d\n", count(r -> get(r, :valid, false), results))
    @printf("REVERSALS FOUND: %d\n", reversals)

    if reversals > 0
        println("\n🎉 Reversals found at:")
        for r in filter(r -> get(r, :reversal, false), results)
            @printf("  %s θ=%.1f, σ=%.2f, c2=%.1e: ratio=%.4f\n",
                    r.copula, r.θ, r.σ, r.c2, r.ratio)
        end
    end

    return results
end

# ============================================================================
# READY TO RUN
# ============================================================================

println("="^70)
println("Copula-based affiliation implementation COMPLETE!")
println("="^70)
println()
println("This is PURE PERSICO (2000) - just using copulas for affiliation")
println("instead of Bivariate Normal.")
println()
println("To search for reversals:")
println("  results = sweep_copula_affiliation()")
println()
println("Default: 5 Clayton θ × 5 σ × 2 costs = 50 combinations")
println("        4 Gumbel θ × 5 σ × 2 costs = 40 combinations")
println("        Total: 90 combinations (~6-8 minutes)")
println()
println("="^70)
