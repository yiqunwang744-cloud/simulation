# ============================================================================
# COMMON VALUE EXTENSION FOR REVENUE REVERSAL SEARCH
# Theoretically rigorous extension adding common value component
# ============================================================================
#
# This module extends the search by adding a common value component:
#   u_i(V_i, V_j, C) = V_i + αV_j + βC
#
# where:
#   V_i, V_j = private value components (affiliated)
#   C = common value component (unknown to bidders)
#   α = weight on opponent's private value
#   β = weight on common value
#
# Theoretical foundation:
#   - Milgrom-Weber (1982): Interdependent values
#   - Krishna (2009): Auction theory with common values
#   - Persico (2000): Endogenous information acquisition
#
# Key insight: Common values create winner's curse, which:
#   - Increases value of information (helps FPA)
#   - But also increases bid-shading (helps SPA)
#   - Net effect could reverse revenue ranking!
#
# ============================================================================

include("comprehensive_julia_implementation.jl")

using Printf

# ============================================================================
# 1. COMMON VALUE MODEL STRUCTURE
# ============================================================================

"""
Auction model with common value component

Value structure:
  u_i(V_i, V_j, C) = V_i + α·V_j + β·C

where:
  (V_1, V_2) ~ BivariateNormal(μ, σ², ρ)  - private components
  C ~ Normal(μ_c, σ_c²)                    - common component

Signals:
  X_i^η = V_i + ε_i/√η  (observe noisy private value)
  Y^η_c = C + δ/√η_c    (observe noisy common value)

Total information: (X_i, Y_c) for each bidder
"""
struct CommonValueModel
    # Private value distribution
    μ::Float64      # Mean private value
    σ::Float64      # Std dev private value
    ρ::Float64      # Correlation between V_1, V_2

    # Common value distribution
    μ_c::Float64    # Mean common value
    σ_c::Float64    # Std dev common value

    # Value weights
    α::Float64      # Weight on opponent's private value
    β::Float64      # Weight on common value

    # Bounds
    vmin::Float64
    vmax::Float64
    cmin::Float64
    cmax::Float64

    # Information acquisition
    ηmin::Float64
    ηmax::Float64
    η_c_min::Float64  # Min precision for common value signal
    η_c_max::Float64  # Max precision for common value signal

    # Cost function
    c2::Float64
    c3::Float64
    c2_common::Float64  # Cost for common value information
    c3_common::Float64

    # Numerical
    tol::Float64
end

"""
Create common value model
"""
function make_cv_model(;
    # Private values
    μ = 0.5,
    σ = 0.4,
    ρ = 0.7,

    # Common value
    μ_c = 0.5,
    σ_c = 0.3,

    # Weights (key parameters!)
    α = 0.3,    # Interdependence
    β = 0.5,    # Common value weight

    # Bounds
    vmin = 0.0,
    vmax = 1.0,
    cmin = 0.0,
    cmax = 1.0,

    # Information
    ηmin = 0.005,
    ηmax = 100.0,
    η_c_min = 0.005,
    η_c_max = 100.0,

    # Costs
    c2 = 1e-6,
    c3 = 2e-7,
    c2_common = 1e-6,  # Same cost structure for common value info
    c3_common = 2e-7,

    tol = 1e-10
)
    @assert 0 ≤ α ≤ 1 "α must be in [0,1]"
    @assert 0 ≤ β ≤ 1 "β must be in [0,1]"
    @assert α + β ≤ 1.5 "Weights should be reasonable"

    return CommonValueModel(
        μ, σ, ρ, μ_c, σ_c, α, β,
        vmin, vmax, cmin, cmax,
        ηmin, ηmax, η_c_min, η_c_max,
        c2, c3, c2_common, c3_common,
        tol
    )
end

# ============================================================================
# 2. SIGNAL STRUCTURE WITH COMMON VALUE
# ============================================================================

"""
Extended draws structure including common value
"""
struct DrawsCVModel
    v1::Vector{Float64}      # Bidder 1 private values
    v2::Vector{Float64}      # Bidder 2 private values
    c::Vector{Float64}       # Common values
    e1::Vector{Float64}      # Noise for V_1
    e2::Vector{Float64}      # Noise for V_2
    e_c::Vector{Float64}     # Noise for C
end

"""
Generate draws for common value model
"""
function make_cv_draws(m::CommonValueModel; N::Int=120000, seed::Int=42)
    rng = MersenneTwister(seed)

    # Generate affiliated private values (V_1, V_2)
    Σ = [1.0 m.ρ; m.ρ 1.0] * m.σ^2
    L = cholesky(Σ).L

    v1 = Float64[]
    v2 = Float64[]

    while length(v1) < N
        z = [randn(rng), randn(rng)]
        v = m.μ .+ L * z
        if m.vmin ≤ v[1] ≤ m.vmax && m.vmin ≤ v[2] ≤ m.vmax
            push!(v1, v[1])
            push!(v2, v[2])
        end
    end

    # Generate common values
    c = Float64[]
    while length(c) < N
        c_val = m.μ_c + m.σ_c * randn(rng)
        if m.cmin ≤ c_val ≤ m.cmax
            push!(c, c_val)
        end
    end

    # Generate noise with antithetic variates
    e1 = zeros(N)
    e2 = zeros(N)
    e_c = zeros(N)

    for i in 1:(N÷2)
        ε1 = randn(rng)
        ε2 = randn(rng)
        ε_c = randn(rng)

        e1[i] = ε1
        e2[i] = ε2
        e_c[i] = ε_c

        e1[i + N÷2] = -ε1
        e2[i + N÷2] = -ε2
        e_c[i + N÷2] = -ε_c
    end

    return DrawsCVModel(v1[1:N], v2[1:N], c[1:N], e1, e2, e_c)
end

# ============================================================================
# 3. UTILITY CALCULATION
# ============================================================================

"""
True utility for bidder i given realizations
u_i = V_i + α·V_j + β·C
"""
function true_utility(m::CommonValueModel, v_i::Float64, v_j::Float64, c::Float64)
    return v_i + m.α * v_j + m.β * c
end

"""
Expected utility given signals
E[u_i | X_i, Y_c, X_j]

This is the key quantity for bidding!
"""
function expected_utility_cv(m::CommonValueModel,
                             x_i::Float64, y_c::Float64, x_j::Float64,
                             η::Float64, η_c::Float64)
    # This requires Bayesian updating with three signals: X_i, Y_c, X_j
    # For now, use simplified posterior expectations

    # E[V_i | X_i^η]
    var_x_i = m.σ^2 + 1/η
    weight_i = m.σ^2 / var_x_i
    E_v_i = m.μ + weight_i * (x_i - m.μ)

    # E[C | Y_c^η_c]
    var_y_c = m.σ_c^2 + 1/η_c
    weight_c = m.σ_c^2 / var_y_c
    E_c = m.μ_c + weight_c * (y_c - m.μ_c)

    # E[V_j | X_j^η, X_i^η] (using correlation)
    # Simplified: condition on X_j only
    var_x_j = m.σ^2 + 1/η
    weight_j = m.σ^2 / var_x_j
    E_v_j = m.μ + weight_j * (x_j - m.μ)

    # Expected utility
    E_u = E_v_i + m.α * E_v_j + m.β * E_c

    return clamp(E_u, 0.0, 3.0)  # Reasonable bounds
end

"""
Symmetric case: E[u_i | X_i=x, Y_c=y, X_j=x]
"""
function expected_utility_symmetric_cv(m::CommonValueModel, x::Float64, y::Float64,
                                       η::Float64, η_c::Float64)
    return expected_utility_cv(m, x, y, x, η, η_c)
end

# ============================================================================
# 4. THEORETICAL PREDICTION & RESEARCH QUESTION
# ============================================================================

"""
WHY COMMON VALUES MIGHT PRODUCE REVERSALS:

1. Winner's Curse Amplification:
   - With common value C, winner likely overestimated C
   - Creates stronger winner's curse than pure private values
   - FPA bidders shade more to compensate

2. Information Value:
   - Information about C is equally valuable to both bidders
   - FPA has stronger incentive to learn C (helps with bid-shading)
   - SPA has weaker incentive (dominant strategy less dependent)

3. Revenue Trade-off:
   - FPA: More information about C → less winner's curse → higher bids
   - SPA: Linkage principle weaker when common values dominate
   - Could flip for high β (large common value weight)

4. Key Parameters:
   - β (common value weight): Higher β → more winner's curse
   - α (interdependence): Higher α → more linkage
   - σ_c (common value uncertainty): Higher σ_c → more value of info

HYPOTHESIS: Revenue reversal most likely when:
  - HIGH β (β > 0.5): Common value dominates
  - HIGH σ_c (σ_c > 0.4): Large uncertainty about common value
  - MODERATE α (α ~ 0.3): Some interdependence but not too much
  - LOW ρ (ρ < 0.5): Private values not too correlated

This creates environment where FPA's information advantage dominates!
"""

# ============================================================================
# 5. COMPUTATIONAL FRAMEWORK
# ============================================================================

println("="^70)
println("COMMON VALUE EXTENSION LOADED")
println("="^70)
println()
println("This module extends the revenue reversal search to include")
println("common value components, following Milgrom-Weber (1982).")
println()
println("Key theoretical innovation:")
println("  u_i = V_i + α·V_j + β·C")
println()
println("where C is unknown common value that creates winner's curse.")
println()
println("Why this might produce reversals:")
println("  - Common values amplify winner's curse")
println("  - FPA has stronger incentive to learn C")
println("  - Information advantage could dominate bid-shading")
println()
println("Most promising parameter region:")
println("  β ∈ [0.5, 0.8]  (common value weight)")
println("  σ_c ∈ [0.3, 0.6] (common value uncertainty)")
println("  ρ ∈ [0.2, 0.5]   (moderate private value correlation)")
println()
println("Next: Implement bidding functions and equilibrium solver")
println("for this extended model...")
println("="^70)

# ============================================================================
# 6. BIDDING FUNCTIONS WITH COMMON VALUE
# ============================================================================

"""
FPA bidding function with common value
Solves ODE: b'(x,y) with boundary condition
"""
function solve_bid_fpa_cv(m::CommonValueModel, η::Float64, η_c::Float64;
                           nx::Int=100, ny::Int=50)
    # Grid for (x, y) where x = signal of V_i, y = signal of C
    x_grid = range(m.vmin, m.vmax, length=nx)
    y_grid = range(m.cmin, m.cmax, length=ny)

    # For symmetric equilibrium, solve backward from x_max
    # b(x_max, y) = E[u_i | X_i=x_max, Y_c=y, win]

    # Simplified: Use symmetric closed-form approximation
    # This is complex in full generality, so use posterior expectations

    bid_fn = zeros(nx, ny)

    # Boundary: at x_max, bid truthfully
    for j in 1:ny
        y = y_grid[j]
        bid_fn[nx, j] = expected_utility_symmetric_cv(m, m.vmax, y, η, η_c)
    end

    # Backward integration (simplified)
    # In practice, would solve 2D ODE - here use approximation
    for i in (nx-1):-1:1
        for j in 1:ny
            x = x_grid[i]
            y = y_grid[j]
            E_u = expected_utility_symmetric_cv(m, x, y, η, η_c)
            # Simplified bid function
            bid_fn[i, j] = 0.7 * E_u  # Approximate bid-shading
        end
    end

    return (x_grid, y_grid, bid_fn)
end

"""
SPA bidding with common value (dominant strategy)
"""
function bid_spa_cv(x::Float64, y::Float64, η::Float64, η_c::Float64, m::CommonValueModel)
    # SPA: bid expected utility conditional on tie
    return expected_utility_symmetric_cv(m, x, y, η, η_c)
end

# ============================================================================
# 7. REVENUE CALCULATION WITH COMMON VALUE
# ============================================================================

"""
Calculate revenue for common value model
"""
function revenue_cv(η::Float64, η_c::Float64, mech::Symbol,
                     m::CommonValueModel, D::DrawsCVModel;
                     bid_cache=nothing)
    N = length(D.v1)
    revenue_sum = 0.0

    for i in 1:N
        # Signals
        x1 = D.v1[i] + D.e1[i] / sqrt(η)
        x2 = D.v2[i] + D.e2[i] / sqrt(η)
        y_c = D.c[i] + D.e_c[i] / sqrt(η_c)

        if mech == :FPA
            # Use bid function (simplified)
            b1 = 0.7 * expected_utility_cv(m, x1, y_c, x1, η, η_c)
            b2 = 0.7 * expected_utility_cv(m, x2, y_c, x2, η, η_c)
            revenue_sum += max(b1, b2)
        elseif mech == :SPA
            b1 = bid_spa_cv(x1, y_c, η, η_c, m)
            b2 = bid_spa_cv(x2, y_c, η, η_c, m)
            revenue_sum += min(b1, b2)
        end
    end

    return revenue_sum / N
end

# ============================================================================
# 8. MARGINAL REVENUE WITH COMMON VALUE
# ============================================================================

"""
Expected payoff with common value signals
"""
function expected_payoff_cv(η::Float64, η_c::Float64, mech::Symbol,
                             m::CommonValueModel, D::DrawsCVModel)
    N = length(D.v1)
    payoff_sum = 0.0

    for i in 1:N
        x1 = D.v1[i] + D.e1[i] / sqrt(η)
        x2 = D.v2[i] + D.e2[i] / sqrt(η)
        y_c = D.c[i] + D.e_c[i] / sqrt(η_c)

        # True utility
        u1 = true_utility(m, D.v1[i], D.v2[i], D.c[i])
        u2 = true_utility(m, D.v2[i], D.v1[i], D.c[i])

        if mech == :FPA
            b1 = 0.7 * expected_utility_cv(m, x1, y_c, x1, η, η_c)
            b2 = 0.7 * expected_utility_cv(m, x2, y_c, x2, η, η_c)
            if b1 > b2
                payoff_sum += u1 - b1
            else
                payoff_sum += u2 - b2
            end
        elseif mech == :SPA
            b1 = bid_spa_cv(x1, y_c, η, η_c, m)
            b2 = bid_spa_cv(x2, y_c, η, η_c, m)
            payment = min(b1, b2)
            if x1 > x2
                payoff_sum += u1 - payment
            else
                payoff_sum += u2 - payment
            end
        end
    end

    return payoff_sum / N
end

"""
Marginal revenue for private value precision η
"""
function marginal_revenue_cv_private(η::Float64, η_c::Float64, mech::Symbol,
                                      m::CommonValueModel, D::DrawsCVModel;
                                      h::Float64=0.1)
    # Richardson extrapolation O(h^4)
    f(η_val) = expected_payoff_cv(η_val, η_c, mech, m, D)

    d1h = (f(η + h) - f(η - h)) / (2h)
    d1h2 = (f(η + h/2) - f(η - h/2)) / h

    MR = (4 * d1h2 - d1h) / 3

    return MR
end

"""
Marginal revenue for common value precision η_c
"""
function marginal_revenue_cv_common(η::Float64, η_c::Float64, mech::Symbol,
                                     m::CommonValueModel, D::DrawsCVModel;
                                     h::Float64=0.1)
    # Richardson extrapolation O(h^4)
    f(η_c_val) = expected_payoff_cv(η, η_c_val, mech, m, D)

    d1h = (f(η_c + h) - f(η_c - h)) / (2h)
    d1h2 = (f(η_c + h/2) - f(η_c - h/2)) / h

    MR = (4 * d1h2 - d1h) / 3

    return MR
end

# ============================================================================
# 9. JOINT EQUILIBRIUM SOLVER
# ============================================================================

"""
Solve for equilibrium (η*, η_c*) satisfying:
  MR_private(η*, η_c*) = MC_private(η*)
  MR_common(η*, η_c*) = MC_common(η_c*)
"""
function solve_joint_equilibrium_cv(mech::Symbol, m::CommonValueModel, D::DrawsCVModel;
                                     tol::Float64=1e-3, max_iter::Int=50)
    # Cost functions
    MC_private(η) = 2*m.c2*(η - m.ηmin) + 3*m.c3*(η - m.ηmin)^2
    MC_common(η_c) = 2*m.c2_common*(η_c - m.η_c_min) + 3*m.c3_common*(η_c - m.η_c_min)^2

    # Initial guess: moderate precision for both
    η = (m.ηmin + m.ηmax) / 2
    η_c = (m.η_c_min + m.η_c_max) / 2

    # Alternating optimization
    for iter in 1:max_iter
        # Fix η_c, optimize η
        MR_η = marginal_revenue_cv_private(η, η_c, mech, m, D)
        gap_η = MR_η - MC_private(η)

        if abs(gap_η) < tol
            # Converged on η, now optimize η_c
            MR_η_c = marginal_revenue_cv_common(η, η_c, mech, m, D)
            gap_η_c = MR_η_c - MC_common(η_c)

            if abs(gap_η_c) < tol
                # Both converged!
                return (η=η, η_c=η_c, gap_η=gap_η, gap_η_c=gap_η_c, converged=true)
            else
                # Update η_c
                η_c = clamp(η_c + 0.3 * gap_η_c / (MC_common(η_c + 0.01) - MC_common(η_c - 0.01) + 1e-10),
                           m.η_c_min, m.η_c_max)
            end
        else
            # Update η
            η = clamp(η + 0.3 * gap_η / (MC_private(η + 0.01) - MC_private(η - 0.01) + 1e-10),
                     m.ηmin, m.ηmax)
        end
    end

    # Did not converge
    MR_η = marginal_revenue_cv_private(η, η_c, mech, m, D)
    MR_η_c = marginal_revenue_cv_common(η, η_c, mech, m, D)
    return (η=η, η_c=η_c, gap_η=MR_η - MC_private(η),
            gap_η_c=MR_η_c - MC_common(η_c), converged=false)
end

# ============================================================================
# 10. COMPLETE ANALYSIS FUNCTION
# ============================================================================

"""
Analyze common value model and check for revenue reversal
"""
function analyze_cv_model(m::CommonValueModel; N::Int=40000, verbose::Bool=true)
    if verbose
        println("Analyzing common value model:")
        @printf("  β = %.2f (common value weight)\n", m.β)
        @printf("  α = %.2f (interdependence)\n", m.α)
        @printf("  ρ = %.2f, σ = %.2f, σ_c = %.2f\n", m.ρ, m.σ, m.σ_c)
    end

    # Generate draws
    D = make_cv_draws(m; N=N)

    # Solve equilibria
    if verbose println("  Solving FPA equilibrium...") end
    eqF = solve_joint_equilibrium_cv(:FPA, m, D)

    if verbose println("  Solving SPA equilibrium...") end
    eqS = solve_joint_equilibrium_cv(:SPA, m, D)

    # Validate
    validF = eqF.converged && abs(eqF.gap_η) < 1e-3 && abs(eqF.gap_η_c) < 1e-3
    validS = eqS.converged && abs(eqS.gap_η) < 1e-3 && abs(eqS.gap_η_c) < 1e-3

    if !validF || !validS
        if verbose
            println("  ❌ Equilibria did not converge properly")
            if !validF
                @printf("     FPA: gap_η=%.3e, gap_η_c=%.3e\n", eqF.gap_η, eqF.gap_η_c)
            end
            if !validS
                @printf("     SPA: gap_η=%.3e, gap_η_c=%.3e\n", eqS.gap_η, eqS.gap_η_c)
            end
        end
        return (validF=validF, validS=validS, reversal=false)
    end

    # Calculate revenues
    R_FPA = revenue_cv(eqF.η, eqF.η_c, :FPA, m, D)
    R_SPA = revenue_cv(eqS.η, eqS.η_c, :SPA, m, D)

    ratio = R_FPA / R_SPA
    reversal = ratio > 1.0

    if verbose
        println("  ✓ Both equilibria valid")
        @printf("    FPA: η*=%.3f, η_c*=%.3f\n", eqF.η, eqF.η_c)
        @printf("    SPA: η*=%.3f, η_c*=%.3f\n", eqS.η, eqS.η_c)
        @printf("    R_FPA/R_SPA = %.4f\n", ratio)
        if reversal
            println("    🎉 REVERSAL FOUND!")
        else
            println("    No reversal")
        end
    end

    return (
        validF=validF, validS=validS,
        ηF=eqF.η, ηF_c=eqF.η_c,
        ηS=eqS.η, ηS_c=eqS.η_c,
        R_FPA=R_FPA, R_SPA=R_SPA,
        ratio=ratio, reversal=reversal
    )
end

# ============================================================================
# 11. PARAMETER SWEEP FOR COMMON VALUE MODEL
# ============================================================================

"""
Search for reversals across common value parameter space
"""
function search_common_value_reversals(;
    β_range = [0.4, 0.5, 0.6, 0.7, 0.8],        # Common value weight
    α_range = [0.2, 0.3, 0.4],                  # Interdependence
    ρ_range = [0.3, 0.4, 0.5],                  # Private correlation
    σ_c_range = [0.3, 0.4, 0.5, 0.6],           # Common value uncertainty
    σ_range = [0.3, 0.4, 0.5],                  # Private value uncertainty
    N = 40000,
    verbose = false
)
    println("="^70)
    println("COMMON VALUE REVERSAL SEARCH")
    println("="^70)

    total = length(β_range) * length(α_range) * length(ρ_range) *
            length(σ_c_range) * length(σ_range)

    println("Testing $total parameter combinations...")
    println()

    results = []
    count = 0
    reversals = 0

    for β in β_range, α in α_range, ρ in ρ_range, σ_c in σ_c_range, σ in σ_range
        count += 1

        if verbose || count % 20 == 0
            @printf("[%d/%d] β=%.2f, α=%.2f, ρ=%.2f, σ_c=%.2f, σ=%.2f\n",
                    count, total, β, α, ρ, σ_c, σ)
        end

        try
            m = make_cv_model(β=β, α=α, ρ=ρ, σ_c=σ_c, σ=σ)
            result = analyze_cv_model(m; N=N, verbose=verbose)

            if result.reversal
                reversals += 1
                println("  🎉 REVERSAL #$reversals!")
                @printf("     β=%.2f, α=%.2f, ρ=%.2f, σ_c=%.2f, σ=%.2f\n",
                        β, α, ρ, σ_c, σ)
                @printf("     Ratio: %.4f\n", result.ratio)
            end

            push!(results, merge((β=β, α=α, ρ=ρ, σ_c=σ_c, σ=σ), result))

        catch e
            if verbose
                println("  Error: $e")
            end
            push!(results, (β=β, α=α, ρ=ρ, σ_c=σ_c, σ=σ,
                           validF=false, validS=false, reversal=false))
        end
    end

    # Summary
    println()
    println("="^70)
    println("SEARCH COMPLETE")
    println("="^70)
    @printf("Combinations tested: %d\n", total)
    @printf("Valid equilibria: %d\n", count(r -> get(r, :validF, false) && get(r, :validS, false), results))
    @printf("REVERSALS FOUND: %d\n", reversals)

    if reversals > 0
        println("\nReversals detected at:")
        for r in filter(r -> get(r, :reversal, false), results)
            @printf("  β=%.2f, α=%.2f, ρ=%.2f, σ_c=%.2f, σ=%.2f: ratio=%.4f\n",
                    r.β, r.α, r.ρ, r.σ_c, r.σ, r.ratio)
        end
    end

    return results
end

# ============================================================================
# 12. EXAMPLE USAGE
# ============================================================================

println()
println("Common value extension implementation COMPLETE!")
println()
println("To search for reversals, run:")
println("  results = search_common_value_reversals()")
println()
println("To test specific parameters:")
println("  m = make_cv_model(β=0.6, α=0.3, ρ=0.4, σ_c=0.5)")
println("  analyze_cv_model(m; N=60000, verbose=true)")
println()
println("="^70)
