# Comprehensive Julia Implementation with Revenue Calculation and Reversal Search
# Based on rigorous MR=MC equilibrium (NOT heuristics)
#
# ✅ Proper theoretical foundation from Persico (2000)
# ✅ A-ordered signals: X^η = V + ε/√η
# ✅ Affiliated values (bivariate normal)
# ✅ Correct equilibrium finding via MR = MC
# ✅ Revenue calculation
# ✅ Reversal search

using Distributions, QuadGK, LinearAlgebra, Optim, Printf, ForwardDiff, Roots, Random, Statistics

# ============================================
# PART 1: DATA STRUCTURES
# ============================================

"""
Complete auction model with affiliated values and A-ordered signals
"""
struct AuctionModel
    # Value distribution parameters
    μ::Float64      # Mean of values
    σ::Float64      # Standard deviation
    ρ::Float64      # Correlation between V₁ and V₂

    # Signal technology parameters (A-ordered)
    # X^η = V + ε/√η where ε ~ N(0,1)
    η_min::Float64
    η_max::Float64

    # Information cost parameters: C(η) = c₂(η - η_min)² + c₃(η - η_min)³
    c₂::Float64
    c₃::Float64

    # Computational parameters
    tol::Float64    # Numerical tolerance

    function AuctionModel(;μ=0.5, σ=0.4, ρ=0.9, η_min=0.01, η_max=100.0,
                          c₂=1e-6, c₃=2e-7, tol=1e-10)
        @assert 0 < σ "Standard deviation must be positive"
        @assert -1 ≤ ρ ≤ 1 "Correlation must be in [-1,1]"
        @assert 0 < η_min < η_max "Invalid η range"
        @assert c₂ > 0 && c₃ ≥ 0 "Invalid cost parameters"
        new(μ, σ, ρ, η_min, η_max, c₂, c₃, tol)
    end
end

"""
Common Random Numbers for variance reduction
"""
struct CommonRandomNumbers
    v1::Vector{Float64}  # Bidder 1 values
    v2::Vector{Float64}  # Bidder 2 values
    ε1::Vector{Float64}  # Bidder 1 noise
    ε2::Vector{Float64}  # Bidder 2 noise
end

"""
Precomputed FPA bidding function
"""
struct FPABidCache
    grid::Vector{Float64}    # Signal grid points
    bids::Vector{Float64}    # Corresponding bids
end

# ============================================
# PART 2: SIGNAL TECHNOLOGY (A-ORDERED)
# ============================================

"""
Generate common random numbers with antithetic variates
"""
function generate_crn(model::AuctionModel; N::Int=60000, seed::Int=123456)
    rng = MersenneTwister(seed)

    # Covariance matrix for bivariate normal
    Σ = [model.σ^2  model.ρ*model.σ^2;
         model.ρ*model.σ^2  model.σ^2]
    L = cholesky(Σ).L  # Cholesky decomposition

    # Generate values using acceptance-rejection for truncation
    v1 = Float64[]
    v2 = Float64[]
    vmin, vmax = 0.0, 1.0

    while length(v1) < N
        z = randn(rng, 2)
        v = model.μ .+ L * z
        if vmin ≤ v[1] ≤ vmax && vmin ≤ v[2] ≤ vmax
            push!(v1, v[1])
            push!(v2, v[2])
        end
    end

    # Generate noise with antithetic variates
    ε1 = zeros(N)
    ε2 = zeros(N)
    for i in 1:(N÷2)
        e1_pos = randn(rng)
        e2_pos = randn(rng)
        ε1[i] = e1_pos
        ε2[i] = e2_pos
        ε1[i + N÷2] = -e1_pos  # Antithetic
        ε2[i + N÷2] = -e2_pos  # Antithetic
    end

    return CommonRandomNumbers(v1[1:N], v2[1:N], ε1, ε2)
end

"""
Signal given value: X^η = V + ε/√η
"""
function signal_from_value(v::Float64, ε::Float64, η::Float64)
    return v + ε / sqrt(η)
end

"""
Posterior expectation E[V₁|X₁=x₁, X₂=x₂] for symmetric case (x₁=x₂=x)
"""
function posterior_value(x::Float64, η::Float64, model::AuctionModel)
    # For X = V + ε/√η with V ~ N(μ, σ²) and affiliation ρ:
    # E[V|X₁=x, X₂=x] = μ + weight * (x - μ)
    # weight = (1+ρ)σ² / [(1+ρ)σ² + 1/η]

    A = (1 + model.ρ) * model.σ^2
    weight = A / (A + 1/η)

    return model.μ + weight * (x - model.μ)
end

"""
Conditional distribution parameters for f(X₂|X₁=x₁)
"""
function conditional_signal_params(x1::Float64, η::Float64, model::AuctionModel)
    # Var[X|V] = 1/η
    # For affiliated values: X₂|X₁ has conditional mean and variance

    var_X = model.σ^2 + 1/η
    ρ_X = (model.ρ * model.σ^2) / var_X

    μ_cond = model.μ + ρ_X * (x1 - model.μ)
    σ_cond = sqrt(var_X * (1 - ρ_X^2))

    return μ_cond, σ_cond
end

"""
Conditional density f(x₂|x₁)
"""
function f_X2_given_X1(x2::Float64, x1::Float64, η::Float64, model::AuctionModel)
    μ_c, σ_c = conditional_signal_params(x1, η, model)
    return pdf(Normal(μ_c, σ_c), x2)
end

"""
Conditional CDF F(x₂|x₁)
"""
function F_X2_given_X1(x2::Float64, x1::Float64, η::Float64, model::AuctionModel)
    μ_c, σ_c = conditional_signal_params(x1, η, model)
    return cdf(Normal(μ_c, σ_c), x2)
end

"""
Hazard rate h(x) = f(x|x) / [1 - F(x|x)]
"""
function hazard_rate(x::Float64, η::Float64, model::AuctionModel)
    f_xx = f_X2_given_X1(x, x, η, model)
    F_xx = F_X2_given_X1(x, x, η, model)

    if F_xx ≥ 0.9999
        return f_xx / 0.0001  # Avoid division by zero
    else
        return f_xx / (1 - F_xx)
    end
end

# ============================================
# PART 3: BIDDING FUNCTIONS
# ============================================

"""
SPA bidding: b^{SPA}(x) = E[V|X₁=x, X₂=x] (dominant strategy)
"""
function bid_spa(x::Float64, η::Float64, model::AuctionModel)
    return posterior_value(x, η, model)
end

"""
FPA bidding via ODE: b'(x) = [v(x,x) - b(x)] * h(x)
Solved using 4th-order Runge-Kutta
"""
function precompute_bid_fpa(η::Float64, model::AuctionModel; nx::Int=500)
    # Signal grid with buffer for extreme values
    σ_X = sqrt(model.σ^2 + 1/η)
    x_min = max(0.0, model.μ - 6*σ_X)
    x_max = min(1.0, model.μ + 6*σ_X)

    grid = range(x_min, x_max, length=nx)
    bids = zeros(nx)

    # Boundary condition: b(x_min) = 0
    bids[1] = 0.0

    # RK4 integration
    for i in 1:(nx-1)
        x = grid[i]
        b = bids[i]
        dx = grid[i+1] - grid[i]

        # RK4 steps
        v1 = posterior_value(x, η, model)
        h1 = hazard_rate(x, η, model)
        k1 = (v1 - b) * h1

        x2 = x + 0.5*dx
        v2 = posterior_value(x2, η, model)
        h2 = hazard_rate(x2, η, model)
        k2 = (v2 - (b + 0.5*dx*k1)) * h2

        k3 = (v2 - (b + 0.5*dx*k2)) * h2

        x4 = x + dx
        v4 = posterior_value(x4, η, model)
        h4 = hazard_rate(x4, η, model)
        k4 = (v4 - (b + dx*k3)) * h4

        bids[i+1] = b + (dx/6) * (k1 + 2*k2 + 2*k3 + k4)
        bids[i+1] = max(0.0, bids[i+1])  # Ensure non-negative
    end

    return FPABidCache(collect(grid), bids)
end

"""
Interpolate FPA bid from precomputed cache
"""
function bid_fpa_interp(x::Float64, cache::FPABidCache)
    if x ≤ cache.grid[1]
        return cache.bids[1]
    elseif x ≥ cache.grid[end]
        return cache.bids[end]
    else
        # Linear interpolation
        i = searchsortedlast(cache.grid, x)
        if i == 0
            return cache.bids[1]
        elseif i >= length(cache.grid)
            return cache.bids[end]
        end

        x0, x1 = cache.grid[i], cache.grid[i+1]
        b0, b1 = cache.bids[i], cache.bids[i+1]

        t = (x - x0) / (x1 - x0)
        return b0 + t * (b1 - b0)
    end
end

# ============================================
# PART 4: REVENUE CALCULATION
# ============================================

"""
Calculate expected revenue for a given mechanism and η
"""
function expected_revenue(η::Float64, mechanism::Symbol, model::AuctionModel,
                         crn::CommonRandomNumbers; fpa_cache::Union{FPABidCache,Nothing}=nothing)
    N = length(crn.v1)

    # Pre-cache FPA bids if needed
    if mechanism == :FPA && fpa_cache === nothing
        fpa_cache = precompute_bid_fpa(η, model)
    end

    revenues = zeros(N)

    for i in 1:N
        # Generate signals
        x1 = signal_from_value(crn.v1[i], crn.ε1[i], η)
        x2 = signal_from_value(crn.v2[i], crn.ε2[i], η)

        # Calculate bids
        if mechanism == :FPA
            b1 = bid_fpa_interp(x1, fpa_cache)
            b2 = bid_fpa_interp(x2, fpa_cache)
            # Revenue = winning bid
            revenues[i] = max(b1, b2)

        elseif mechanism == :SPA
            b1 = bid_spa(x1, η, model)
            b2 = bid_spa(x2, η, model)
            # Revenue = second highest bid
            revenues[i] = min(b1, b2)

        else
            error("Unknown mechanism: $mechanism")
        end
    end

    return mean(revenues)
end

# ============================================
# PART 5: MARGINAL ANALYSIS (MR and MC)
# ============================================

"""
Information cost C(η) = c₂(η - η_min)² + c₃(η - η_min)³
"""
function info_cost(η::Float64, model::AuctionModel)
    Δη = η - model.η_min
    return model.c₂ * Δη^2 + model.c₃ * Δη^3
end

"""
Marginal cost MC(η) = 2c₂(η - η_min) + 3c₃(η - η_min)²
"""
function marginal_cost(η::Float64, model::AuctionModel)
    Δη = η - model.η_min
    return 2 * model.c₂ * Δη + 3 * model.c₃ * Δη^2
end

"""
Gross expected utility (before cost)
"""
function expected_utility_gross(η::Float64, mechanism::Symbol, model::AuctionModel,
                               crn::CommonRandomNumbers; fpa_cache::Union{FPABidCache,Nothing}=nothing)
    N = length(crn.v1)

    # Pre-cache FPA bids if needed
    if mechanism == :FPA && fpa_cache === nothing
        fpa_cache = precompute_bid_fpa(η, model)
    end

    utilities = zeros(N)

    for i in 1:N
        # Generate signals
        x1 = signal_from_value(crn.v1[i], crn.ε1[i], η)
        x2 = signal_from_value(crn.v2[i], crn.ε2[i], η)

        # Calculate bids
        if mechanism == :FPA
            b1 = bid_fpa_interp(x1, fpa_cache)
            b2 = bid_fpa_interp(x2, fpa_cache)
        elseif mechanism == :SPA
            b1 = bid_spa(x1, η, model)
            b2 = bid_spa(x2, η, model)
        end

        # Bidder 1's utility
        if x1 > x2  # Bidder 1 wins
            utilities[i] = crn.v1[i] - (mechanism == :FPA ? b1 : b2)
        else
            utilities[i] = 0.0
        end
    end

    return mean(utilities)
end

"""
Marginal return MR(η) using Richardson extrapolation (high accuracy)
"""
function marginal_return(η::Float64, mechanism::Symbol, model::AuctionModel,
                        crn::CommonRandomNumbers; h_frac::Float64=0.01)
    h = min(0.1, h_frac * η)

    η_p = min(model.η_max, η + h/2)
    η_m = max(model.η_min + 1e-8, η - h/2)
    η_p2 = min(model.η_max, η + h/4)
    η_m2 = max(model.η_min + 1e-8, η - h/4)

    # Cache FPA bids
    cache_p = mechanism == :FPA ? precompute_bid_fpa(η_p, model) : nothing
    cache_m = mechanism == :FPA ? precompute_bid_fpa(η_m, model) : nothing
    cache_p2 = mechanism == :FPA ? precompute_bid_fpa(η_p2, model) : nothing
    cache_m2 = mechanism == :FPA ? precompute_bid_fpa(η_m2, model) : nothing

    # Compute utilities at 4 points
    u_p = expected_utility_gross(η_p, mechanism, model, crn, fpa_cache=cache_p)
    u_m = expected_utility_gross(η_m, mechanism, model, crn, fpa_cache=cache_m)
    u_p2 = expected_utility_gross(η_p2, mechanism, model, crn, fpa_cache=cache_p2)
    u_m2 = expected_utility_gross(η_m2, mechanism, model, crn, fpa_cache=cache_m2)

    # Richardson extrapolation
    D1 = (u_p - u_m) / (η_p - η_m)
    D2 = (u_p2 - u_m2) / (η_p2 - η_m2)

    return (4*D2 - D1) / 3
end

"""
Marginal return with confidence interval (multiple batches)
"""
function marginal_return_ci(η::Float64, mechanism::Symbol, model::AuctionModel;
                           N::Int=60000, K::Int=4, seed::Int=123456, h_frac::Float64=0.01)
    estimates = zeros(K)

    for k in 1:K
        crn = generate_crn(model, N=N, seed=seed + 911*k)
        estimates[k] = marginal_return(η, mechanism, model, crn, h_frac=h_frac)
    end

    μ = mean(estimates)
    se = std(estimates, corrected=true) / sqrt(K)

    return μ, se
end

# ============================================
# PART 6: EQUILIBRIUM SOLVING (MR = MC)
# ============================================

"""
Sign of (MR - MC) with confidence interval awareness
"""
function sign_ci(μ::Float64, se::Float64)
    if μ - 2*se > 0
        return +1  # Clearly positive
    elseif μ + 2*se < 0
        return -1  # Clearly negative
    else
        return 0   # Uncertain
    end
end

"""
Solve for equilibrium η* where MR(η*) = MC(η*)
Uses corner-aware bisection with confidence intervals
"""
function solve_equilibrium(mechanism::Symbol, model::AuctionModel;
                          N::Int=60000, K::Int=4, seed::Int=123456,
                          tol_abs::Float64=1e-5, tol_se::Float64=5e-6,
                          max_iter::Int=60, h_frac::Float64=0.01)

    a = model.η_min + 1e-4
    b = model.η_max

    # Evaluate at endpoints
    mr_a, se_a = marginal_return_ci(a, mechanism, model, N=N, K=K, seed=seed, h_frac=h_frac)
    mc_a = marginal_cost(a, model)
    gap_a = mr_a - mc_a

    mr_b, se_b = marginal_return_ci(b, mechanism, model, N=N, K=K, seed=seed+1, h_frac=h_frac)
    mc_b = marginal_cost(b, model)
    gap_b = mr_b - mc_b

    sign_a = sign_ci(gap_a, se_a)
    sign_b = sign_ci(gap_b, se_b)

    @printf("  Initial: η∈[%.4f, %.4f], gap(a)=%.2e±%.2e, gap(b)=%.2e±%.2e\n",
            a, b, gap_a, se_a, gap_b, se_b)

    # Check for corner solutions
    if sign_a == +1 && sign_b == +1
        @printf("  → Right corner solution at η=%.4f\n", b)
        return b, gap_b, se_b
    end

    if sign_a == -1 && sign_b == -1
        @printf("  → Left corner solution at η=%.4f\n", a)
        return a, gap_a, se_a
    end

    # Bisection
    for iter in 1:max_iter
        c = (a + b) / 2

        mr_c, se_c = marginal_return_ci(c, mechanism, model, N=N, K=K,
                                       seed=seed+iter+10, h_frac=h_frac)
        mc_c = marginal_cost(c, model)
        gap_c = mr_c - mc_c

        sign_c = sign_ci(gap_c, se_c)

        @printf("  Iter %2d: η=%.4f, gap=%.2e±%.2e, sign=%+d\n",
                iter, c, gap_c, se_c, sign_c)

        # Convergence check
        if abs(gap_c) ≤ tol_abs && se_c ≤ tol_se
            @printf("  ✓ Converged at η*=%.4f\n", c)
            return c, gap_c, se_c
        end

        # Update interval
        if sign_c == 0
            # Uncertain - use point estimate
            sign_c = gap_c ≥ 0 ? +1 : -1
        end

        if sign_a == 0
            sign_a = gap_a ≥ 0 ? +1 : -1
        end

        if sign_a * sign_c < 0
            b = c
            gap_b = gap_c
            se_b = se_c
            sign_b = sign_c
        else
            a = c
            gap_a = gap_c
            se_a = se_c
            sign_a = sign_c
        end

        if b - a < 1e-4
            @printf("  → Interval too small, stopping at η=%.4f\n", c)
            return c, gap_c, se_c
        end
    end

    # Max iterations reached
    c = (a + b) / 2
    @printf("  ⚠ Max iterations reached, returning midpoint η=%.4f\n", c)

    mr_c, se_c = marginal_return_ci(c, mechanism, model, N=N, K=K, seed=seed+1000, h_frac=h_frac)
    mc_c = marginal_cost(c, model)
    gap_c = mr_c - mc_c

    return c, gap_c, se_c
end

# ============================================
# PART 7: MAIN ANALYSIS WITH REVENUE COMPARISON
# ============================================

"""
Complete FPA vs SPA analysis with revenue calculation
"""
function analyze_fpa_vs_spa(model::AuctionModel;
                           N::Int=60000, K::Int=4, seed::Int=123456, verbose::Bool=true)

    if verbose
        println("="^80)
        println("FPA vs SPA: Complete Analysis with Revenue Calculation")
        println("="^80)
        println("Model parameters:")
        @printf("  μ=%.2f, σ=%.2f, ρ=%.3f\n", model.μ, model.σ, model.ρ)
        @printf("  c₂=%.2e, c₃=%.2e\n", model.c₂, model.c₃)
        @printf("  η∈[%.4f, %.2f]\n", model.η_min, model.η_max)
        println()
    end

    # Solve equilibria
    if verbose
        println("Solving FPA equilibrium (MR = MC)...")
    end
    η_fpa, gap_fpa, se_fpa = solve_equilibrium(:FPA, model, N=N, K=K, seed=seed)

    if verbose
        println("\nSolving SPA equilibrium (MR = MC)...")
    end
    η_spa, gap_spa, se_spa = solve_equilibrium(:SPA, model, N=N, K=K, seed=seed+12345)

    # Calculate revenues at equilibrium
    if verbose
        println("\nCalculating revenues at equilibrium...")
    end

    crn_revenue = generate_crn(model, N=N*2, seed=seed+54321)

    fpa_cache = precompute_bid_fpa(η_fpa, model)
    R_fpa = expected_revenue(η_fpa, :FPA, model, crn_revenue, fpa_cache=fpa_cache)
    R_spa = expected_revenue(η_spa, :SPA, model, crn_revenue)

    # Results
    if verbose
        println("\n" * "="^80)
        println("RESULTS")
        println("="^80)
        println("Equilibrium Information Acquisition:")
        @printf("  FPA: η* = %.4f | MR-MC = %+.3e (SE ≈ %.2e)\n", η_fpa, gap_fpa, se_fpa)
        @printf("  SPA: η* = %.4f | MR-MC = %+.3e (SE ≈ %.2e)\n", η_spa, gap_spa, se_spa)
        println()
        println("Information Acquisition Ranking:")
        if η_fpa > η_spa
            @printf("  ✓ η*_FPA (%.4f) > η*_SPA (%.4f) - Theory confirmed!\n", η_fpa, η_spa)
        else
            @printf("  ✗ η*_FPA (%.4f) ≤ η*_SPA (%.4f) - Unexpected!\n", η_fpa, η_spa)
        end
        println()
        println("Seller Revenue:")
        @printf("  R_FPA(η*) = %.6f\n", R_fpa)
        @printf("  R_SPA(η*) = %.6f\n", R_spa)
        @printf("  Ratio: R_FPA/R_SPA = %.6f", R_fpa/R_spa)
        if R_fpa > R_spa
            println(" → FPA generates MORE revenue!")
        else
            println(" → SPA generates MORE revenue")
        end
        println("="^80)
    end

    return (η_fpa=η_fpa, η_spa=η_spa, R_fpa=R_fpa, R_spa=R_spa,
            gap_fpa=gap_fpa, gap_spa=gap_spa, se_fpa=se_fpa, se_spa=se_spa)
end

# ============================================
# PART 8: REVERSAL SEARCH
# ============================================

"""
Search for parameter combinations where R_FPA > R_SPA
"""
function search_revenue_reversals(;
                                  ρ_range=[0.5, 0.7, 0.9, 0.95, 0.98],
                                  c₂_range=[1e-7, 1e-6, 1e-5, 1e-4],
                                  σ_range=[0.2, 0.4, 0.6],
                                  N::Int=30000, K::Int=2,
                                  seed::Int=123456)

    println("="^80)
    println("SYSTEMATIC REVERSAL SEARCH")
    println("="^80)
    println("Searching for parameter combinations where R_FPA > R_SPA")
    println()

    results = []
    total = length(ρ_range) * length(c₂_range) * length(σ_range)
    current = 0

    for ρ in ρ_range, c₂ in c₂_range, σ in σ_range
        current += 1

        c₃ = c₂ / 5  # Maintain ratio

        try
            @printf("[%3d/%3d] Testing ρ=%.2f, c₂=%.1e, σ=%.2f... ", current, total, ρ, c₂, σ)

            model = AuctionModel(μ=0.5, σ=σ, ρ=ρ, c₂=c₂, c₃=c₃)
            result = analyze_fpa_vs_spa(model, N=N, K=K, seed=seed+current, verbose=false)

            ratio = result.R_fpa / result.R_spa
            reversal = result.R_fpa > result.R_spa

            @printf("η_FPA=%.3f, η_SPA=%.3f, R_ratio=%.4f %s\n",
                   result.η_fpa, result.η_spa, ratio, reversal ? "✓ REVERSAL!" : "")

            push!(results, merge((ρ=ρ, c₂=c₂, σ=σ, ratio=ratio, reversal=reversal), result))

        catch e
            println("ERROR: $e")
        end
    end

    # Analyze results
    println("\n" * "="^80)
    println("SEARCH RESULTS")
    println("="^80)

    reversals = filter(r -> r.reversal, results)

    @printf("Found %d reversals out of %d tested combinations\n", length(reversals), length(results))

    if length(reversals) > 0
        println("\nTop 5 reversals (by revenue ratio):")
        sort!(reversals, by=r -> r.ratio, rev=true)

        for (i, r) in enumerate(reversals[1:min(5, length(reversals))])
            println("\n$i. ρ=$(r.ρ), c₂=$(r.c₂), σ=$(r.σ)")
            @printf("   η*: FPA=%.4f, SPA=%.4f\n", r.η_fpa, r.η_spa)
            @printf("   Revenue: FPA=%.6f, SPA=%.6f (ratio=%.4f)\n", r.R_fpa, r.R_spa, r.ratio)
        end
    else
        println("\nNo reversals found in parameter range.")
        println("Closest cases (by ratio to 1.0):")

        sort!(results, by=r -> abs(r.ratio - 1.0))
        for (i, r) in enumerate(results[1:min(3, length(results))])
            @printf("\n%d. ρ=%.2f, c₂=%.1e, σ=%.2f: ratio=%.4f\n",
                   i, r.ρ, r.c₂, r.σ, r.ratio)
        end
    end

    println("="^80)

    return results
end

# ============================================
# PART 9: MAIN EXECUTION
# ============================================

if abspath(PROGRAM_FILE) == @__FILE__
    println("🚀 Comprehensive Julia Implementation")
    println("   With Revenue Calculation and Reversal Search")
    println("   Based on Rigorous MR=MC Equilibrium")
    println()

    # Example 1: Single analysis with default parameters
    println("EXAMPLE 1: Standard Analysis")
    model = AuctionModel(ρ=0.98, c₂=1e-6, c₃=2e-7)
    analyze_fpa_vs_spa(model, N=60000, K=4)

    println("\n" * "="^80)
    println()

    # Example 2: Reversal search
    println("EXAMPLE 2: Systematic Reversal Search")
    search_revenue_reversals(N=30000, K=2)
end
