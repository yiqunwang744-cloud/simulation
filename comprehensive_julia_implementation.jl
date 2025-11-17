# ============================================================================
# COMPREHENSIVE REVENUE REVERSAL SEARCH FOR AUCTION THEORY RESEARCH
# Based on Persico (2000) - Theoretically Rigorous Implementation
# ============================================================================
#
# This implementation combines:
# 1. A-ordered signal technology: X^η = V + ε/√η
# 2. Affiliated values via Bivariate Normal
# 3. Proper bidding functions (FPA ODE, SPA exact)
# 4. MR = MC equilibrium with Richardson extrapolation
# 5. Revenue calculation at equilibrium
# 6. Systematic parameter search for reversals
#
# NO magic coefficients - everything derived from theory
# ============================================================================

using Distributions, LinearAlgebra, QuadGK, Random, Statistics, Printf, Optim

# ============================================================================
# 1. MODEL STRUCTURE AND PARAMETERS
# ============================================================================

"""
Model parameters for auction with endogenous information acquisition
"""
struct AuctionModel
    # Value distribution parameters (Bivariate Normal)
    μ::Float64      # Mean of values
    σ::Float64      # Standard deviation of values
    ρ::Float64      # Correlation between V₁ and V₂

    # Value bounds
    vmin::Float64   # Lower bound
    vmax::Float64   # Upper bound

    # Information acquisition parameters
    ηmin::Float64   # Minimum precision
    ηmax::Float64   # Maximum precision

    # Cost function: C(η) = c₂(η - ηmin)² + c₃(η - ηmin)³
    c2::Float64     # Quadratic cost coefficient
    c3::Float64     # Cubic cost coefficient

    # Numerical tolerance
    tol::Float64    # Convergence tolerance
end

"""
Constructor with default parameters
"""
function make_model(;
    μ = 0.5,
    σ = 0.4,
    ρ = 0.98,
    vmin = 0.0,
    vmax = 1.0,
    ηmin = 0.005,
    ηmax = 100.0,
    c2 = 1e-6,
    c3 = 2e-7,
    tol = 1e-10
)
    return AuctionModel(μ, σ, ρ, vmin, vmax, ηmin, ηmax, c2, c3, tol)
end

"""
Common Random Numbers structure for variance reduction
"""
struct DrawsCRN
    v1::Vector{Float64}   # Bidder 1 values
    v2::Vector{Float64}   # Bidder 2 values
    e1::Vector{Float64}   # Bidder 1 noise (with antithetic variates)
    e2::Vector{Float64}   # Bidder 2 noise (with antithetic variates)
end

"""
Precomputed FPA bidding function
"""
struct BidsCache
    grid::Vector{Float64}     # Signal grid
    bFPA::Vector{Float64}     # FPA bids on grid
end

# ============================================================================
# 2. SIGNAL TECHNOLOGY (A-ORDERED)
# ============================================================================

"""
A-ordered signal family: X^η_i = V_i + ε_i/√η
where ε_i ~ N(0,1) independent

Key properties:
- Higher η → more precise signals (lower variance 1/η)
- Satisfies Monotone Likelihood Ratio Property (MLRP)
- Affiliation preserved
"""

"""
Conditional distribution parameters for X₂|X₁=x₁
Returns (μ_cond, σ_cond) for the conditional signal distribution
"""
function cond_params(x::Float64, η::Float64, m::AuctionModel)
    varX = m.σ^2 + 1/η                    # Signal variance
    ρx = (m.ρ * m.σ^2) / varX            # Conditional correlation
    μy = m.μ + ρx * (x - m.μ)            # Conditional mean
    σy = sqrt(varX * (1 - ρx^2))         # Conditional std dev
    return μy, σy
end

"""
Conditional signal density f(x₂|x₁) at symmetric equilibrium
"""
function f_X2_given_X1(x2::Float64, x1::Float64, η::Float64, m::AuctionModel)
    μy, σy = cond_params(x1, η, m)
    return pdf(Normal(μy, σy), x2)
end

"""
Conditional signal CDF F(x₂|x₁) at symmetric equilibrium
"""
function F_X2_given_X1(x2::Float64, x1::Float64, η::Float64, m::AuctionModel)
    μy, σy = cond_params(x1, η, m)
    return cdf(Normal(μy, σy), x2)
end

"""
Posterior expectation v(x,x) = E[V₁|X₁=x, X₂=x]
Used for SPA bidding (truth-telling)
"""
function v_symmetric(x::Float64, η::Float64, m::AuctionModel)
    A = (1 + m.ρ) * m.σ^2
    weight = A / (A + 1/η)
    return clamp(m.μ + weight * (x - m.μ), m.vmin, m.vmax)
end

# ============================================================================
# 3. RANDOM NUMBER GENERATION WITH VARIANCE REDUCTION
# ============================================================================

"""
Generate Common Random Numbers with antithetic variates
This ensures:
1. Same random shocks used across different η values
2. Variance reduction via antithetic variates
"""
function make_draws(m::AuctionModel; N::Int=120000, seed::Int=42, antithetic::Bool=true)
    rng = MersenneTwister(seed)

    # Generate correlated bivariate normal values
    # Using Cholesky decomposition: [V₁, V₂]' = μ + L*[Z₁, Z₂]'
    Σ = [1.0 m.ρ; m.ρ 1.0] * m.σ^2
    L = cholesky(Σ).L

    v1 = Float64[]
    v2 = Float64[]

    # Accept-reject for truncated bivariate normal
    while length(v1) < N
        z = [randn(rng), randn(rng)]
        v = m.μ .+ L * z
        if m.vmin ≤ v[1] ≤ m.vmax && m.vmin ≤ v[2] ≤ m.vmax
            push!(v1, v[1])
            push!(v2, v[2])
        end
    end

    # Generate noise with antithetic variates
    e1 = zeros(N)
    e2 = zeros(N)

    if antithetic
        for i in 1:(N÷2)
            ε1 = randn(rng)
            ε2 = randn(rng)
            e1[i] = ε1
            e2[i] = ε2
            e1[i + N÷2] = -ε1  # Antithetic pair
            e2[i + N÷2] = -ε2
        end
    else
        e1 = randn(rng, N)
        e2 = randn(rng, N)
    end

    return DrawsCRN(v1[1:N], v2[1:N], e1, e2)
end

# ============================================================================
# 4. BIDDING FUNCTIONS
# ============================================================================

"""
FPA bidding function via ODE solution
Solves: b'(x) = [v(x,x) - b(x)] × h(x)
where h(x) = f(x|x) / F(x|x) is the hazard rate

Uses 4th-order Runge-Kutta method
"""
function precompute_bids_FPA(η::Float64, m::AuctionModel; nx::Int=600)
    # Extended grid to cover signal range
    smin = m.vmin - 6/sqrt(η)
    smax = m.vmax + 6/sqrt(η)
    grid = range(smin, smax, length=nx)
    bFPA = zeros(nx)

    # Boundary condition: b(smin) = 0
    bFPA[1] = 0.0

    # RK4 integration
    for i in 1:(nx-1)
        x = grid[i]
        dx = grid[i+1] - grid[i]

        # Compute RK4 stages
        v1 = v_symmetric(x, η, m)
        f1 = f_X2_given_X1(x, x, η, m)
        F1 = F_X2_given_X1(x, x, η, m)
        h1 = F1 > m.tol ? f1 / F1 : 0.0
        k1 = (v1 - bFPA[i]) * h1

        xmid = x + 0.5*dx
        v2 = v_symmetric(xmid, η, m)
        f2 = f_X2_given_X1(xmid, xmid, η, m)
        F2 = F_X2_given_X1(xmid, xmid, η, m)
        h2 = F2 > m.tol ? f2 / F2 : 0.0
        k2 = (v2 - (bFPA[i] + 0.5*dx*k1)) * h2

        k3 = (v2 - (bFPA[i] + 0.5*dx*k2)) * h2

        xend = grid[i+1]
        v4 = v_symmetric(xend, η, m)
        f4 = f_X2_given_X1(xend, xend, η, m)
        F4 = F_X2_given_X1(xend, xend, η, m)
        h4 = F4 > m.tol ? f4 / F4 : 0.0
        k4 = (v4 - (bFPA[i] + dx*k3)) * h4

        bFPA[i+1] = bFPA[i] + (dx/6) * (k1 + 2*k2 + 2*k3 + k4)
    end

    return BidsCache(collect(grid), bFPA)
end

"""
Linear interpolation for FPA bids
"""
function lininterp(x::Float64, cache::BidsCache)
    if x ≤ cache.grid[1]
        return cache.bFPA[1]
    elseif x ≥ cache.grid[end]
        return cache.bFPA[end]
    else
        i = searchsortedlast(cache.grid, x)
        if i == 0
            return cache.bFPA[1]
        elseif i >= length(cache.grid)
            return cache.bFPA[end]
        else
            α = (x - cache.grid[i]) / (cache.grid[i+1] - cache.grid[i])
            return (1 - α) * cache.bFPA[i] + α * cache.bFPA[i+1]
        end
    end
end

"""
SPA bidding function (exact, no ODE needed)
In SPA, dominant strategy is to bid expected value
"""
function bid_spa(x::Float64, η::Float64, m::AuctionModel)
    return v_symmetric(x, η, m)
end

# ============================================================================
# 5. EXPECTED PAYOFF CALCULATION
# ============================================================================

"""
Calculate gross expected payoff (before information cost)
Uses Monte Carlo integration with CRN
"""
function EU_gross(η::Float64, mech::Symbol, m::AuctionModel, D::DrawsCRN;
                  cacheFPA::Union{BidsCache,Nothing}=nothing)
    N = length(D.v1)
    payoff_sum = 0.0

    for i in 1:N
        # Generate signals X^η = V + ε/√η
        x1 = D.v1[i] + D.e1[i] / sqrt(η)
        x2 = D.v2[i] + D.e2[i] / sqrt(η)

        # Bidder 1's value (affiliated with V₂)
        u1 = D.v1[i]

        if mech == :FPA
            # FPA: pay own bid if win
            b1 = lininterp(x1, cacheFPA)
            b2 = lininterp(x2, cacheFPA)

            if b1 ≥ b2
                payoff_sum += u1 - b1
            end

        elseif mech == :SPA
            # SPA: pay second-highest bid if win
            b1 = bid_spa(x1, η, m)
            b2 = bid_spa(x2, η, m)

            if b1 ≥ b2
                payoff_sum += u1 - b2
            end
        end
    end

    return payoff_sum / N
end

# ============================================================================
# 6. COST FUNCTION
# ============================================================================

"""
Information cost: C(η) = c₂(η - ηmin)² + c₃(η - ηmin)³
"""
function cost(η::Float64, m::AuctionModel)
    Δη = η - m.ηmin
    return m.c2 * Δη^2 + m.c3 * Δη^3
end

"""
Marginal cost: MC(η) = 2c₂(η - ηmin) + 3c₃(η - ηmin)²
"""
function MC(η::Float64, m::AuctionModel)
    Δη = η - m.ηmin
    return 2 * m.c2 * Δη + 3 * m.c3 * Δη^2
end

# ============================================================================
# 7. MARGINAL REVENUE (RICHARDSON EXTRAPOLATION)
# ============================================================================

"""
Calculate marginal revenue MR(η) = ∂E[Payoff]/∂η
using Richardson extrapolation for O(h⁴) accuracy

Uses 4-point stencil:
- Compute centered differences at step sizes h and h/2
- Extrapolate to eliminate O(h²) error term
"""
function MR_one(η::Float64, mech::Symbol, m::AuctionModel, D::DrawsCRN; h_frac::Float64=0.01)
    # Step size (adaptive based on η)
    h = min(0.1, h_frac * η)

    # Ensure we stay within bounds
    ηp = min(m.ηmax, η + h/2)
    ηm = max(m.ηmin + 1e-8, η - h/2)
    ηp2 = min(m.ηmax, η + h/4)
    ηm2 = max(m.ηmin + 1e-8, η - h/4)

    # Precompute FPA bids if needed
    if mech == :FPA
        cache_p = precompute_bids_FPA(ηp, m)
        cache_m = precompute_bids_FPA(ηm, m)
        cache_p2 = precompute_bids_FPA(ηp2, m)
        cache_m2 = precompute_bids_FPA(ηm2, m)

        up = EU_gross(ηp, mech, m, D; cacheFPA=cache_p)
        um = EU_gross(ηm, mech, m, D; cacheFPA=cache_m)
        up2 = EU_gross(ηp2, mech, m, D; cacheFPA=cache_p2)
        um2 = EU_gross(ηm2, mech, m, D; cacheFPA=cache_m2)
    else
        up = EU_gross(ηp, mech, m, D)
        um = EU_gross(ηm, mech, m, D)
        up2 = EU_gross(ηp2, mech, m, D)
        um2 = EU_gross(ηm2, mech, m, D)
    end

    # Richardson extrapolation
    D1 = (up - um) / (ηp - ηm)      # O(h²) approximation
    D2 = (up2 - um2) / (ηp2 - ηm2)  # O(h²) approximation at h/2

    return (4*D2 - D1) / 3           # O(h⁴) approximation
end

"""
Calculate MR with confidence interval using multiple independent batches
"""
function MR_with_CI(η::Float64, mech::Symbol, m::AuctionModel;
                    K::Int=4, N::Int=60000, seed::Int=42, h_frac::Float64=0.01)
    estimates = zeros(K)

    for k in 1:K
        Dk = make_draws(m; N=N, seed=seed + 911*k, antithetic=true)
        estimates[k] = MR_one(η, mech, m, Dk; h_frac=h_frac)
    end

    μ = mean(estimates)
    se = std(estimates, corrected=true) / sqrt(K)

    return μ, se
end

# ============================================================================
# 8. EQUILIBRIUM SOLVER (CORNER-AWARE BISECTION)
# ============================================================================

"""
Sign of F with confidence interval consideration
Returns: +1 if clearly positive, -1 if clearly negative, 0 if uncertain
"""
function sign_CI(μF::Float64, seF::Float64)
    if μF - 2*seF > 0
        return +1
    elseif μF + 2*seF < 0
        return -1
    else
        return 0
    end
end

"""
Solve for η* such that MR(η*) = MC(η*)
Uses corner-aware bisection with confidence intervals
"""
function solve_eta_star_CI(mech::Symbol, m::AuctionModel;
                           N::Int=120000, K::Int=4, seed::Int=42,
                           h_frac::Float64=0.01,
                           tol_abs::Float64=1e-5, tol_se::Float64=5e-6,
                           max_iter::Int=60)

    a = m.ηmin + 1e-4
    b = m.ηmax

    # Evaluate at boundaries
    μFa, seFa = MR_with_CI(a, mech, m; K=K, N=N, seed=seed, h_frac=h_frac)
    μFa -= MC(a, m)

    μFb, seFb = MR_with_CI(b, mech, m; K=K, N=N, seed=seed+1, h_frac=h_frac)
    μFb -= MC(b, m)

    sL = sign_CI(μFa, seFa)
    sR = sign_CI(μFb, seFb)

    # CRITICAL FIX: Do NOT return corner solutions that don't satisfy MR = MC!
    # Corner solutions need to be validated just like interior solutions.
    # If both boundaries have same sign, solution is likely at boundary,
    # but we still need to verify MR ≈ MC before accepting it.

    # If both positive: optimal might be at η_max (right corner)
    if sL == +1 && sR == +1
        # Check if right corner actually satisfies equilibrium
        if abs(μFb) ≤ tol_abs && seFb ≤ tol_se
            return b, μFb, seFb  # Valid right corner equilibrium
        else
            # Right corner doesn't satisfy MR=MC, no equilibrium exists
            return NaN, μFb, seFb  # Return NaN to signal failure
        end
    end

    # If both negative: optimal might be at η_min (left corner)
    if sL == -1 && sR == -1
        # Check if left corner actually satisfies equilibrium
        if abs(μFa) ≤ tol_abs && seFa ≤ tol_se
            return a, μFa, seFa  # Valid left corner equilibrium
        else
            # Left corner doesn't satisfy MR=MC, no equilibrium exists
            return NaN, μFa, seFa  # Return NaN to signal failure
        end
    end

    # Bisection iterations
    for iter in 1:max_iter
        c = (a + b) / 2
        μFc, seFc = MR_with_CI(c, mech, m; K=K, N=N, seed=seed+iter+10, h_frac=h_frac)
        μFc -= MC(c, m)
        sc = sign_CI(μFc, seFc)

        # Check convergence
        if abs(μFc) ≤ tol_abs && seFc ≤ tol_se
            return c, μFc, seFc
        end

        # Update interval
        sLa = (sL == 0) ? (μFa ≥ 0 ? +1 : -1) : sL
        scm = (sc == 0) ? (μFc ≥ 0 ? +1 : -1) : sc

        if sLa * scm < 0
            # Root in [a, c]
            b = c
            μFb = μFc
            seFb = seFc
            sR = sc
        else
            # Root in [c, b]
            a = c
            μFa = μFc
            seFa = seFc
            sL = sc
        end

        if b - a < 1e-6
            return c, μFc, seFc
        end
    end

    # Max iterations reached - return midpoint
    c = (a + b) / 2
    μFc, seFc = MR_with_CI(c, mech, m; K=K, N=N, seed=seed+max_iter+100, h_frac=h_frac)
    μFc -= MC(c, m)

    return c, μFc, seFc
end

# ============================================================================
# 9. REVENUE CALCULATION AT EQUILIBRIUM
# ============================================================================

"""
Calculate seller revenue at equilibrium information level η*
- FPA: R = E[max{b₁(X₁), b₂(X₂)}]
- SPA: R = E[min{b₁(X₁), b₂(X₂)}] when winner pays second price
"""
function revenue(η::Float64, mech::Symbol, m::AuctionModel, D::DrawsCRN;
                 cacheFPA::Union{BidsCache,Nothing}=nothing)
    N = length(D.v1)
    revenue_sum = 0.0

    for i in 1:N
        # Generate signals
        x1 = D.v1[i] + D.e1[i] / sqrt(η)
        x2 = D.v2[i] + D.e2[i] / sqrt(η)

        if mech == :FPA
            # FPA: seller gets highest bid
            b1 = lininterp(x1, cacheFPA)
            b2 = lininterp(x2, cacheFPA)
            revenue_sum += max(b1, b2)

        elseif mech == :SPA
            # SPA: seller gets second-highest bid
            b1 = bid_spa(x1, η, m)
            b2 = bid_spa(x2, η, m)
            revenue_sum += min(b1, b2)
        end
    end

    return revenue_sum / N
end

"""
Calculate revenue with confidence interval
"""
function revenue_with_CI(η::Float64, mech::Symbol, m::AuctionModel;
                        K::Int=4, N::Int=60000, seed::Int=42)
    estimates = zeros(K)

    for k in 1:K
        Dk = make_draws(m; N=N, seed=seed + 911*k, antithetic=true)

        if mech == :FPA
            cache = precompute_bids_FPA(η, m)
            estimates[k] = revenue(η, mech, m, Dk; cacheFPA=cache)
        else
            estimates[k] = revenue(η, mech, m, Dk)
        end
    end

    μ = mean(estimates)
    se = std(estimates, corrected=true) / sqrt(K)

    return μ, se
end

# ============================================================================
# 10. EQUILIBRIUM VALIDATION
# ============================================================================

"""
Check if an equilibrium is valid (not NaN and satisfies MR ≈ MC)
"""
function is_valid_equilibrium(η::Float64, gap::Float64, se::Float64;
                              tol_gap::Float64=1e-3, tol_se::Float64=1e-3)
    # Check for NaN (failed solve)
    if isnan(η)
        return false
    end

    # Check if MR-MC gap is small enough
    if abs(gap) > tol_gap
        return false
    end

    # Check if standard error is reasonable
    if se > tol_se
        return false
    end

    return true
end

# ============================================================================
# 11. COMPREHENSIVE ANALYSIS
# ============================================================================

"""
Analyze FPA vs SPA for given parameters
Returns equilibria and revenues
CRITICAL: Only reports reversals if BOTH equilibria are valid!
"""
function analyze_FPA_vs_SPA(m::AuctionModel;
                            N::Int=120000, K::Int=4, verbose::Bool=true)

    if verbose
        println("="^70)
        println("AUCTION ANALYSIS WITH ENDOGENOUS INFORMATION ACQUISITION")
        println("="^70)
        println("Parameters:")
        @printf("  Value distribution: N(%.2f, %.2f²) with correlation ρ=%.3f\n", m.μ, m.σ, m.ρ)
        @printf("  Cost function: C(η) = %.2e(η-%.3f)² + %.2e(η-%.3f)³\n",
                m.c2, m.ηmin, m.c3, m.ηmin)
        println()
    end

    # Solve for equilibria
    if verbose
        println("Solving for equilibrium information acquisition...")
    end

    ηF, gapF, seF = solve_eta_star_CI(:FPA, m; N=N, K=K)
    ηS, gapS, seS = solve_eta_star_CI(:SPA, m; N=N, K=K, seed=12345)

    # CRITICAL: Validate equilibria before proceeding
    validF = is_valid_equilibrium(ηF, gapF, seF)
    validS = is_valid_equilibrium(ηS, gapS, seS)

    if verbose
        println("-"^70)
        println("EQUILIBRIUM RESULTS (MR = MC):")

        if isnan(ηF)
            println("FPA: ❌ FAILED - No equilibrium found")
        else
            @printf("FPA: η* = %.5f | MR-MC = %+.3e (SE ≈ %.2e)", ηF, gapF, seF)
            if validF
                println(" ✓")
            else
                println(" ❌ INVALID (|MR-MC| too large)")
            end
        end

        if isnan(ηS)
            println("SPA: ❌ FAILED - No equilibrium found")
        else
            @printf("SPA: η* = %.5f | MR-MC = %+.3e (SE ≈ %.2e)", ηS, gapS, seS)
            if validS
                println(" ✓")
            else
                println(" ❌ INVALID (|MR-MC| too large)")
            end
        end

        if validF && validS
            if ηF > ηS
                println("\n✓ Theoretical ranking confirmed: η*_FPA > η*_SPA")
            else
                println("\n⚠ Unexpected ranking: η*_FPA ≤ η*_SPA")
            end
        else
            println("\n⚠ Cannot verify ranking - invalid equilibria")
        end
        println()
    end

    # Only calculate revenues if BOTH equilibria are valid
    if validF && validS
        if verbose
            println("Calculating seller revenues at equilibrium...")
        end

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
            reversal = (RF > RS)
        )
    else
        # Return result with invalid flag
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
            reversal = false
        )
    end
end

# ============================================================================
# 11. SYSTEMATIC PARAMETER SEARCH FOR REVERSALS
# ============================================================================

"""
Search for parameter combinations where R_FPA > R_SPA
"""
function search_revenue_reversals(;
    ρ_range = [0.5, 0.7, 0.8, 0.9, 0.95, 0.98],
    σ_range = [0.2, 0.3, 0.4, 0.5, 0.6],
    c2_range = [1e-7, 5e-7, 1e-6, 5e-6, 1e-5, 5e-5, 1e-4],
    N = 60000,
    K = 3,
    verbose = true
)

    results = []
    total = length(ρ_range) * length(σ_range) * length(c2_range)
    current = 0

    if verbose
        println("="^70)
        println("SYSTEMATIC SEARCH FOR REVENUE REVERSALS")
        println("="^70)
        println("Testing $(total) parameter combinations...")
        println()
    end

    for ρ in ρ_range, σ in σ_range, c2 in c2_range
        current += 1
        c3 = c2 / 5  # Keep ratio consistent

        if verbose && current % 10 == 1
            @printf("Progress: %d/%d (%.1f%%)\n", current, total, 100*current/total)
        end

        try
            m = make_model(ρ=ρ, σ=σ, c2=c2, c3=c3)
            result = analyze_FPA_vs_SPA(m; N=N, K=K, verbose=false)

            push!(results, merge(result, (ρ=ρ, σ=σ, c2=c2)))

            if result.reversal && verbose
                @printf("  ✓ REVERSAL: ρ=%.2f, σ=%.2f, c₂=%.1e → R_FPA/R_SPA=%.4f\n",
                        ρ, σ, c2, result.ratio)
            end
        catch e
            if verbose
                @printf("  ✗ Error at ρ=%.2f, σ=%.2f, c₂=%.1e: %s\n", ρ, σ, c2, string(e))
            end
        end
    end

    # Summary
    if verbose
        println()
        println("="^70)
        println("SEARCH RESULTS SUMMARY:")

        # CRITICAL: Only count results where BOTH equilibria are valid!
        valid_results = filter(r -> r.validF && r.validS, results)
        reversals = filter(r -> r.validF && r.validS && r.reversal, results)
        invalid_fpa = filter(r -> !r.validF, results)
        invalid_spa = filter(r -> !r.validS, results)

        @printf("Total combinations tested: %d\n", length(results))
        @printf("Valid equilibria (both FPA & SPA): %d (%.1f%%)\n",
                length(valid_results), 100*length(valid_results)/max(1,length(results)))
        @printf("  Invalid FPA equilibria: %d\n", length(invalid_fpa))
        @printf("  Invalid SPA equilibria: %d\n", length(invalid_spa))
        @printf("\nTrue reversals (valid equilibria only): %d (%.1f%%)\n",
                length(reversals), 100*length(reversals)/max(1, length(valid_results)))

        if length(reversals) > 0
            println("\n🎉 REVERSALS FOUND! 🎉")
            println("\nTop reversals by ratio (all with valid equilibria):")
            sort!(reversals, by=r->r.ratio, rev=true)
            for (i, r) in enumerate(reversals[1:min(5, length(reversals))])
                @printf("  %d. ρ=%.2f, σ=%.2f, c₂=%.1e: ratio=%.4f\n", i, r.ρ, r.σ, r.c2, r.ratio)
                @printf("      η_F=%.3f (gap=%.1e), η_S=%.3f (gap=%.1e)\n",
                        r.ηF, r.gapF, r.ηS, r.gapS)
            end
        else
            println("\n❌ NO TRUE REVERSALS FOUND")
            println("\nStandard result holds: R_SPA > R_FPA for all valid equilibria")

            if length(valid_results) > 0
                println("\nClosest to reversal (valid equilibria only):")
                valid_with_ratio = filter(r -> !isnan(r.ratio), valid_results)
                if length(valid_with_ratio) > 0
                    sort!(valid_with_ratio, by=r->abs(r.ratio-1))
                    for (i, r) in enumerate(valid_with_ratio[1:min(3, length(valid_with_ratio))])
                        @printf("  %d. ρ=%.2f, σ=%.2f, c₂=%.1e: ratio=%.4f (SPA wins by %.1f%%)\n",
                                i, r.ρ, r.σ, r.c2, r.ratio, (1/r.ratio - 1)*100)
                    end
                end
            end
        end
        println("="^70)
    end

    return results
end

# ============================================================================
# 12. EXAMPLE USAGE
# ============================================================================

"""
Run default analysis
"""
function run_default_analysis()
    println("Running default analysis with theoretically sound parameters...\n")

    # Default parameters from Persico (2000) framework
    m = make_model(
        μ = 0.5,
        σ = 0.4,
        ρ = 0.98,   # Strong affiliation
        c2 = 1e-6,
        c3 = 2e-7
    )

    result = analyze_FPA_vs_SPA(m; N=120000, K=4, verbose=true)

    return result
end

"""
Run systematic search
"""
function run_systematic_search()
    println("Running systematic parameter search...\n")

    results = search_revenue_reversals(
        ρ_range = [0.5, 0.7, 0.8, 0.9, 0.95, 0.98],
        σ_range = [0.3, 0.4, 0.5],
        c2_range = [5e-7, 1e-6, 5e-6, 1e-5],
        N = 60000,
        K = 3,
        verbose = true
    )

    return results
end

# ============================================================================
# MAIN EXECUTION
# ============================================================================

if abspath(PROGRAM_FILE) == @__FILE__
    println("COMPREHENSIVE AUCTION THEORY IMPLEMENTATION")
    println("Based on Persico (2000) - NO magic coefficients")
    println()

    # Run default analysis
    println("="^70)
    println("PART 1: DEFAULT ANALYSIS")
    println("="^70)
    default_result = run_default_analysis()

    println("\n\n")

    # Run systematic search
    println("="^70)
    println("PART 2: SYSTEMATIC PARAMETER SEARCH")
    println("="^70)
    search_results = run_systematic_search()

    println("\n✅ Analysis complete!")
end
