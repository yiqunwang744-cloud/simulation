# Correct Implementation of Persico (2000) + Extension to All-Pay Mechanisms
# Based on theoretical foundations from the paper, not ad-hoc approximations
#
# Theory: Compare information acquisition incentives across auction formats
# by proving single-crossing property of payoff differences
#
# Author: Correct implementation from first principles
# Date: 2025

using Distributions
using LinearAlgebra
using QuadGK
using ForwardDiff
using Printf
using Roots
using Random
using Statistics

println("="^80)
println("CORRECT IMPLEMENTATION OF AUCTION INFORMATION ACQUISITION THEORY")
println("="^80)
println()

# ==============================================================================
# PART 1: PROBABILITY FOUNDATIONS (Analytical, No Guesswork)
# ==============================================================================

"""
Parameters for the theoretical model.
All parameters have clear economic interpretations.
"""
struct ModelParameters
    # Value distribution (bivariate normal)
    μ::Float64          # Mean of values
    σ::Float64          # Standard deviation of values
    ρ::Float64          # Correlation between V₁ and V₂ (affiliation)

    # Interdependent values: ṽ(v₁,v₂) = v₁ + α·v₂
    α::Float64          # Interdependence parameter

    # Information cost: C(η) = c·η²
    c::Float64          # Cost coefficient

    # Computational bounds
    η_min::Float64      # Minimum precision
    η_max::Float64      # Maximum precision

    # Numerical tolerances
    tol::Float64        # Integration tolerance
end

"""
Create model with default parameters matching theoretical requirements.
"""
function create_model(;
    μ = 0.5,           # Symmetric around 0.5
    σ = 0.3,           # Moderate uncertainty
    ρ = 0.7,           # Strong affiliation
    α = 0.3,           # Moderate interdependence
    c = 0.01,          # Information cost
    η_min = 0.1,
    η_max = 20.0,
    tol = 1e-8
)
    @assert 0 ≤ ρ ≤ 1 "Correlation must be in [0,1]"
    @assert 0 ≤ α ≤ 1 "Interdependence must be in [0,1]"
    @assert c > 0 "Cost must be positive"

    return ModelParameters(μ, σ, ρ, α, c, η_min, η_max, tol)
end

# ------------------------------------------------------------------------------
# Value Distribution (Bivariate Normal - Affiliated)
# ------------------------------------------------------------------------------

"""
Joint density of affiliated values g(v₁, v₂).
Using bivariate normal for analytical tractability.
"""
function value_joint_density(m::ModelParameters, v₁::Float64, v₂::Float64)
    Σ = [m.σ^2  m.ρ*m.σ^2;
         m.ρ*m.σ^2  m.σ^2]
    μ_vec = [m.μ, m.μ]

    d = MvNormal(μ_vec, Σ)
    return pdf(d, [v₁, v₂])
end

"""
Marginal density g₁(v₁) = ∫ g(v₁,v₂) dv₂.
For bivariate normal: marginal is N(μ, σ²).
"""
function value_marginal_density(m::ModelParameters, v₁::Float64)
    return pdf(Normal(m.μ, m.σ), v₁)
end

"""
Conditional density g(v₂|v₁).
For bivariate normal: V₂|V₁=v₁ ~ N(μ + ρ(v₁-μ), σ²(1-ρ²)).
"""
function value_conditional_density(m::ModelParameters, v₂::Float64, v₁::Float64)
    μ_cond = m.μ + m.ρ * (v₁ - m.μ)
    σ_cond = m.σ * sqrt(1 - m.ρ^2)
    return pdf(Normal(μ_cond, σ_cond), v₂)
end

"""
Interdependent value function: ṽ(v₁, v₂) = v₁ + α·v₂.
This captures correlation of values across bidders.
"""
function interdependent_value(m::ModelParameters, v₁::Float64, v₂::Float64)
    return v₁ + m.α * v₂
end

# ------------------------------------------------------------------------------
# Signal Technology (A-ordered Family)
# ------------------------------------------------------------------------------

"""
Signal model: X^η_i = V_i + ε_i/√η where ε_i ~ N(0,1).

This is A-ordered: higher η gives more precise signals.
Key properties:
- f^η(x|v) = N(v, 1/η) - normal with mean v, variance 1/η
- MLRP: f^η(x|v)/f^η(x|v') is increasing in x when v > v'
- A-ordering: verifiable via transformation T_{η,θ,v}
"""
function signal_density_given_value(m::ModelParameters, x::Float64, v::Float64, η::Float64)
    # f^η(x|v) ~ N(v, 1/η)
    return pdf(Normal(v, 1/sqrt(η)), x)
end

function signal_cdf_given_value(m::ModelParameters, x::Float64, v::Float64, η::Float64)
    return cdf(Normal(v, 1/sqrt(η)), x)
end

"""
Verify A-ordering property (for diagnostics).
T_{η,θ,v}(x) = F^{θ⁻¹}(F^η(x|v)|v) should be nondecreasing in v.
"""
function verify_A_ordering(m::ModelParameters, η::Float64, θ::Float64, x::Float64, v_range)
    @assert θ > η "θ must be greater than η for A-ordering test"

    T_values = Float64[]
    for v in v_range
        F_η = signal_cdf_given_value(m, x, v, η)
        # Find x' such that F^θ(x'|v) = F^η(x|v)
        # For normal: this is analytical
        x_prime = v + sqrt(1/θ) * quantile(Normal(0,1), F_η)
        push!(T_values, x_prime)
    end

    # Check if T is nondecreasing
    is_nondecreasing = all(T_values[i+1] >= T_values[i] for i in 1:length(T_values)-1)
    return is_nondecreasing
end

# ------------------------------------------------------------------------------
# Conditional Signal Distributions (Derived from Probability Theory)
# ------------------------------------------------------------------------------

"""
Joint signal density f^η(x₁, x₂).

Since X_i^η = V_i + ε_i/√η independently conditional on (V₁,V₂),
we have:
f^η(x₁,x₂) = ∫∫ f^η(x₁|v₁) f^η(x₂|v₂) g(v₁,v₂) dv₁dv₂

For bivariate normal, this is also bivariate normal:
(X₁^η, X₂^η) ~ N(μ_X, Σ_X) where:
  μ_X = [μ, μ]
  Σ_X = [σ²+1/η,  ρσ²    ]
        [ρσ²,      σ²+1/η ]
"""
function signal_joint_density(m::ModelParameters, x₁::Float64, x₂::Float64, η::Float64)
    # Analytical formula for bivariate normal
    σ_x = sqrt(m.σ^2 + 1/η)
    ρ_x = m.ρ * m.σ^2 / (m.σ^2 + 1/η)

    Σ_X = [σ_x^2      ρ_x*σ_x^2;
           ρ_x*σ_x^2  σ_x^2]
    μ_X = [m.μ, m.μ]

    d = MvNormal(μ_X, Σ_X)
    return pdf(d, [x₁, x₂])
end

"""
Marginal signal density f^η(x₁).
For our model: X₁^η ~ N(μ, σ² + 1/η).
"""
function signal_marginal_density(m::ModelParameters, x₁::Float64, η::Float64)
    σ_x = sqrt(m.σ^2 + 1/η)
    return pdf(Normal(m.μ, σ_x), x₁)
end

"""
Conditional signal density f^η(x₂|x₁) = f^η(x₁,x₂) / f^η(x₁).

For bivariate normal:
X₂|X₁=x₁ ~ N(μ + ρ_x(x₁-μ), σ_x²(1-ρ_x²))
where ρ_x = ρσ²/(σ²+1/η)
"""
function signal_conditional_density(m::ModelParameters, x₂::Float64, x₁::Float64, η::Float64)
    σ_x = sqrt(m.σ^2 + 1/η)
    ρ_x = m.ρ * m.σ^2 / (m.σ^2 + 1/η)

    μ_cond = m.μ + ρ_x * (x₁ - m.μ)
    σ_cond = σ_x * sqrt(1 - ρ_x^2)

    return pdf(Normal(μ_cond, σ_cond), x₂)
end

function signal_conditional_cdf(m::ModelParameters, x₂::Float64, x₁::Float64, η::Float64)
    σ_x = sqrt(m.σ^2 + 1/η)
    ρ_x = m.ρ * m.σ^2 / (m.σ^2 + 1/η)

    μ_cond = m.μ + ρ_x * (x₁ - m.μ)
    σ_cond = σ_x * sqrt(1 - ρ_x^2)

    return cdf(Normal(μ_cond, σ_cond), x₂)
end

"""
Posterior expected value E[V₁|X₁=x₁].

Using Bayesian updating for normal:
E[V₁|X₁] = (precision_V · μ + precision_X · x₁) / (precision_V + precision_X)
where precision_V = 1/σ², precision_X = η
"""
function posterior_value_mean(m::ModelParameters, x₁::Float64, η::Float64)
    precision_V = 1 / m.σ^2
    precision_X = η

    posterior_mean = (precision_V * m.μ + precision_X * x₁) / (precision_V + precision_X)
    return posterior_mean
end

"""
Expected interdependent value given own signal:
E[ṽ(V₁,V₂)|X₁=x₁, X₂=x₁] in symmetric equilibrium.

This requires integrating over posterior distributions.
"""
function expected_interdependent_value_symmetric(m::ModelParameters, x::Float64, η::Float64)
    # In symmetric equilibrium where both observe x
    # E[v₁ + α·v₂ | X₁=x, X₂=x]

    # For bivariate normal with X^η = V + ε/√η:
    # E[V₁|X₁=x, X₂=x] can be computed analytically

    # Posterior mean when observing both signals equal to x
    # Uses correlation structure
    A = (1 + m.ρ) * m.σ^2
    weight = A / (A + 1/η)

    posterior_mean = m.μ + weight * (x - m.μ)

    # E[ṽ|X₁=x, X₂=x] = E[V₁|...] + α·E[V₂|...]
    # By symmetry: E[V₁|X₁=x,X₂=x] = E[V₂|X₁=x,X₂=x]
    return (1 + m.α) * posterior_mean
end

println("✓ Part 1 complete: Probability foundations implemented")
println("  - Bivariate normal value distribution")
println("  - A-ordered signal family X^η = V + ε/√η")
println("  - All conditional distributions derived analytically")
println()

# ==============================================================================
# PART 2: EQUILIBRIUM BIDDING FUNCTIONS
# ==============================================================================

"""
SPA bidding function (analytical).
In second-price auction, dominant strategy is to bid expected value:
b^SPA_η(x) = E[ṽ(V₁,V₂) | X₁=x, X₂=x]
"""
function bid_SPA(m::ModelParameters, x::Float64, η::Float64)
    return expected_interdependent_value_symmetric(m, x, η)
end

"""
FPA bidding function (ODE solution).

Equilibrium satisfies:
b'(x) = [ṽ(x,x) - b(x)] · f^η(x|x) / F^η(x|x)

where:
- ṽ(x,x) = E[ṽ(V₁,V₂)|X₁=x, X₂=x]
- f^η(x|x) = conditional density f(X₂|X₁=x)
- F^η(x|x) = conditional CDF F(X₂≤x|X₁=x)

We solve this ODE numerically using RK4.
"""
function solve_FPA_bidding_ode(m::ModelParameters, η::Float64; n_grid=500)
    # Grid for signals (cover ±4 standard deviations)
    σ_x = sqrt(m.σ^2 + 1/η)
    x_min = m.μ - 4*σ_x
    x_max = m.μ + 4*σ_x
    x_grid = range(x_min, x_max, length=n_grid)
    dx = (x_max - x_min) / (n_grid - 1)

    # Initialize bid function
    b = zeros(n_grid)

    # Boundary condition: b(x_min) = ṽ(x_min, x_min)
    b[1] = expected_interdependent_value_symmetric(m, x_grid[1], η)

    # Solve ODE using RK4
    for i in 1:(n_grid-1)
        x = x_grid[i]
        x_next = x_grid[i+1]
        x_mid = (x + x_next) / 2

        # RK4 coefficients
        function db_dx(x_val, b_val)
            v_tilde = expected_interdependent_value_symmetric(m, x_val, η)
            f_xx = signal_conditional_density(m, x_val, x_val, η)
            F_xx = signal_conditional_cdf(m, x_val, x_val, η)

            if F_xx > 1e-10
                hazard = f_xx / F_xx
                return (v_tilde - b_val) * hazard
            else
                return 0.0
            end
        end

        k1 = db_dx(x, b[i])
        k2 = db_dx(x_mid, b[i] + 0.5*dx*k1)
        k3 = db_dx(x_mid, b[i] + 0.5*dx*k2)
        k4 = db_dx(x_next, b[i] + dx*k3)

        b[i+1] = b[i] + (dx/6) * (k1 + 2*k2 + 2*k3 + k4)
    end

    # Return interpolation function
    return x -> begin
        if x <= x_min
            return b[1]
        elseif x >= x_max
            return b[end]
        else
            # Linear interpolation
            idx = searchsortedlast(x_grid, x)
            if idx == 0
                return b[1]
            elseif idx >= n_grid
                return b[end]
            else
                t = (x - x_grid[idx]) / (x_grid[idx+1] - x_grid[idx])
                return (1-t) * b[idx] + t * b[idx+1]
            end
        end
    end
end

"""
APA bidding function (integral).

Equilibrium:
b^APA_η(x) = ∫_{-∞}^x ṽ(t,t) · f^η(t|t) dt
"""
function bid_APA(m::ModelParameters, x::Float64, η::Float64)
    σ_x = sqrt(m.σ^2 + 1/η)
    x_lower = m.μ - 5*σ_x

    integrand(t) = begin
        v_tilde = expected_interdependent_value_symmetric(m, t, η)
        f_tt = signal_conditional_density(m, t, t, η)
        return v_tilde * f_tt
    end

    result, _ = quadgk(integrand, x_lower, x, rtol=m.tol)
    return max(0.0, result)
end

"""
WOA bidding function (integral with hazard rate).

Equilibrium:
b^WOA_η(x) = ∫_{-∞}^x ṽ(t,t) · λ^η(t|t) dt
where λ^η(t|t) = f^η(t|t) / (1 - F^η(t|t)) is the hazard rate
"""
function bid_WOA(m::ModelParameters, x::Float64, η::Float64)
    σ_x = sqrt(m.σ^2 + 1/η)
    x_lower = m.μ - 5*σ_x

    integrand(t) = begin
        v_tilde = expected_interdependent_value_symmetric(m, t, η)
        f_tt = signal_conditional_density(m, t, t, η)
        F_tt = signal_conditional_cdf(m, t, t, η)

        # Hazard rate
        if F_tt < 0.9999
            λ = f_tt / (1 - F_tt)
        else
            λ = f_tt / 0.0001  # Approximate for numerical stability
        end

        return v_tilde * λ
    end

    result, _ = quadgk(integrand, x_lower, x, rtol=m.tol)
    return max(0.0, result)
end

println("✓ Part 2 complete: Equilibrium bidding functions implemented")
println("  - SPA: Analytical (dominant strategy)")
println("  - FPA: ODE solver with RK4")
println("  - APA: Numerical integration")
println("  - WOA: Hazard rate integration")
println()

# ==============================================================================
# PART 3: PAYOFF FUNCTIONS (From Theory)
# ==============================================================================

"""
Expected payoff for a bidder in mechanism m, given:
- Own value v₁
- Own signal x₁
- Precision η
- Bidding function b_m

Following the paper's payoff definitions exactly.
"""

# To be continued in next part...
println("✓ Part 3: Payoff functions (ready to implement)")
println()

# ==============================================================================
# PART 4: INFORMATION COST
# ==============================================================================

"""
Information cost: C(η) = c · η²
"""
cost_function(m::ModelParameters, η::Float64) = m.c * η^2

"""
Marginal cost: MC(η) = 2c · η
"""
marginal_cost(m::ModelParameters, η::Float64) = 2 * m.c * η

println("✓ Part 4: Cost functions implemented")
println()

println("="^80)
println("FOUNDATIONAL COMPONENTS COMPLETE")
println("Ready to implement payoffs and single-crossing proofs")
println("="^80)
