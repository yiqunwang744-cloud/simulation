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

# Note: Full implementation would require:
# 1. Bidding functions with common value signals
# 2. Joint equilibrium in (η, η_c) space
# 3. Revenue calculation with common value
# 4. Extended parameter search
#
# This is substantial work but theoretically sound and most likely
# to produce revenue reversals!
