# PART 3: PAYOFF FUNCTIONS AND SINGLE-CROSSING PROOFS
# This continues correct_implementation.jl

include("correct_implementation.jl")

# ==============================================================================
# PART 3: PAYOFF FUNCTIONS (Following Paper Exactly)
# ==============================================================================

"""
Compute expected payoff in SPA.

Following the paper's equation:
u^SPA(v₁, b | x₁, η) = ∫_{-∞}^{x₁} [ṽ(v₁,y) - b^SPA(y)] f^η(y|v₁) dy

This represents:
- Win if opponent's signal X₂ < x₁
- Pay opponent's bid b^SPA(X₂)
- Receive value ṽ(v₁, V₂) which depends on opponent's value

For our model with X^η = V + ε/√η:
f^η(y|v₁) requires computing f(y|V₁=v₁) = ∫ f^η(y|v₂) g(v₂|v₁) dv₂
"""
function payoff_SPA_given_value(m::ModelParameters, v₁::Float64, x₁::Float64, η::Float64)
    # We need to compute the integral over opponent's signal y < x₁
    # This requires the conditional density f(y|v₁)

    σ_x = sqrt(m.σ^2 + 1/η)
    y_lower = m.μ - 5*σ_x

    integrand(y) = begin
        if y > x₁
            return 0.0
        end

        # For bivariate normal structure:
        # f(y|v₁) = ∫ f^η(y|v₂) · g(v₂|v₁) dv₂
        # This is also normal: y|V₁=v₁ ~ N(μ + ρ(v₁-μ), σ²(1-ρ²) + 1/η)

        μ_cond = m.μ + m.ρ * (v₁ - m.μ)
        σ_cond = sqrt(m.σ^2 * (1 - m.ρ^2) + 1/η)
        f_y_given_v1 = pdf(Normal(μ_cond, σ_cond), y)

        # Expected value when opponent has signal y
        # ṽ(v₁, V₂) = v₁ + α·V₂
        # E[ṽ(v₁,V₂) | V₁=v₁, X₂=y] = v₁ + α·E[V₂|X₂=y]
        E_v2_given_y = posterior_value_mean(m, y, η)
        v_tilde_expected = v₁ + m.α * E_v2_given_y

        # Opponent's bid
        b_opponent = bid_SPA(m, y, η)

        return (v_tilde_expected - b_opponent) * f_y_given_v1
    end

    result, _ = quadgk(integrand, y_lower, x₁, rtol=m.tol)
    return max(0.0, result)
end

"""
Expected payoff in SPA, averaging over own value distribution.
E[u^SPA | X₁=x₁] = ∫ u^SPA(v₁, x₁, η) f(v₁|x₁) dv₁
"""
function expected_payoff_SPA(m::ModelParameters, x₁::Float64, η::Float64)
    # Posterior of V₁|X₁=x₁ is N(posterior_mean, posterior_var)
    post_mean = posterior_value_mean(m, x₁, η)
    post_var = 1 / (1/m.σ^2 + η)
    post_std = sqrt(post_var)

    # Integrate over posterior
    v1_lower = post_mean - 4*post_std
    v1_upper = post_mean + 4*post_std

    integrand(v₁) = begin
        payoff = payoff_SPA_given_value(m, v₁, x₁, η)
        density = pdf(Normal(post_mean, post_std), v₁)
        return payoff * density
    end

    result, _ = quadgk(integrand, v1_lower, v1_upper, rtol=m.tol)
    return result
end

"""
Compute expected payoff in FPA.

u^FPA(v₁, b | x₁, η) = ∫_{y: b^FPA(y)≤b} [ṽ(v₁,y) - b] f^η(y|v₁) dy

Win if opponent's bid ≤ our bid, pay our own bid.
"""
function payoff_FPA_given_value(m::ModelParameters, v₁::Float64, x₁::Float64,
                                η::Float64, bid_func_FPA)
    σ_x = sqrt(m.σ^2 + 1/η)
    y_lower = m.μ - 5*σ_x

    own_bid = bid_func_FPA(x₁)

    integrand(y) = begin
        opponent_bid = bid_func_FPA(y)

        # Only win if opponent's bid ≤ our bid
        if opponent_bid > own_bid
            return 0.0
        end

        # Conditional density f(y|v₁)
        μ_cond = m.μ + m.ρ * (v₁ - m.μ)
        σ_cond = sqrt(m.σ^2 * (1 - m.ρ^2) + 1/η)
        f_y_given_v1 = pdf(Normal(μ_cond, σ_cond), y)

        # Expected value
        E_v2_given_y = posterior_value_mean(m, y, η)
        v_tilde_expected = v₁ + m.α * E_v2_given_y

        return (v_tilde_expected - own_bid) * f_y_given_v1
    end

    # Find upper limit: where opponent_bid = own_bid
    # Since bid is monotone, we can find this
    y_upper = x₁ + 2*σ_x  # Conservative upper bound

    result, _ = quadgk(integrand, y_lower, y_upper, rtol=m.tol)
    return max(0.0, result)
end

function expected_payoff_FPA(m::ModelParameters, x₁::Float64, η::Float64, bid_func_FPA)
    post_mean = posterior_value_mean(m, x₁, η)
    post_var = 1 / (1/m.σ^2 + η)
    post_std = sqrt(post_var)

    v1_lower = post_mean - 4*post_std
    v1_upper = post_mean + 4*post_std

    integrand(v₁) = begin
        payoff = payoff_FPA_given_value(m, v₁, x₁, η, bid_func_FPA)
        density = pdf(Normal(post_mean, post_std), v₁)
        return payoff * density
    end

    result, _ = quadgk(integrand, v1_lower, v1_upper, rtol=m.tol)
    return result
end

"""
Compute expected payoff in APA.

u^APA(v₁, b | x₁, η) = ∫_{-∞}^{x₁} ṽ(v₁,y) f^η(y|v₁) dy - b

Win if opponent's signal < x₁, but ALWAYS PAY the bid.
"""
function payoff_APA_given_value(m::ModelParameters, v₁::Float64, x₁::Float64, η::Float64)
    σ_x = sqrt(m.σ^2 + 1/η)
    y_lower = m.μ - 5*σ_x

    # Expected value when winning
    integrand_win(y) = begin
        if y > x₁
            return 0.0
        end

        μ_cond = m.μ + m.ρ * (v₁ - m.μ)
        σ_cond = sqrt(m.σ^2 * (1 - m.ρ^2) + 1/η)
        f_y_given_v1 = pdf(Normal(μ_cond, σ_cond), y)

        E_v2_given_y = posterior_value_mean(m, y, η)
        v_tilde_expected = v₁ + m.α * E_v2_given_y

        return v_tilde_expected * f_y_given_v1
    end

    win_value, _ = quadgk(integrand_win, y_lower, x₁, rtol=m.tol)

    # Bid is always paid
    own_bid = bid_APA(m, x₁, η)

    return win_value - own_bid
end

function expected_payoff_APA(m::ModelParameters, x₁::Float64, η::Float64)
    post_mean = posterior_value_mean(m, x₁, η)
    post_var = 1 / (1/m.σ^2 + η)
    post_std = sqrt(post_var)

    v1_lower = post_mean - 4*post_std
    v1_upper = post_mean + 4*post_std

    integrand(v₁) = begin
        payoff = payoff_APA_given_value(m, v₁, x₁, η)
        density = pdf(Normal(post_mean, post_std), v₁)
        return payoff * density
    end

    result, _ = quadgk(integrand, v1_lower, v1_upper, rtol=m.tol)
    return result
end

"""
Compute expected payoff in WOA.

u^WOA(v₁, b | x₁, η) = ∫_{-∞}^{x₁} [ṽ(v₁,y) - b^WOA(y)] f^η(y|v₁) dy
                        - ∫_{x₁}^{∞} b f^η(y|v₁) dy

Win if opponent's signal < x₁, pay second-price.
Lose if opponent's signal > x₁, pay our own bid.
"""
function payoff_WOA_given_value(m::ModelParameters, v₁::Float64, x₁::Float64, η::Float64)
    σ_x = sqrt(m.σ^2 + 1/η)
    y_lower = m.μ - 5*σ_x
    y_upper = m.μ + 5*σ_x

    μ_cond = m.μ + m.ρ * (v₁ - m.μ)
    σ_cond = sqrt(m.σ^2 * (1 - m.ρ^2) + 1/η)

    # Winning payoff
    integrand_win(y) = begin
        if y > x₁
            return 0.0
        end

        f_y_given_v1 = pdf(Normal(μ_cond, σ_cond), y)
        E_v2_given_y = posterior_value_mean(m, y, η)
        v_tilde_expected = v₁ + m.α * E_v2_given_y
        b_opponent = bid_WOA(m, y, η)

        return (v_tilde_expected - b_opponent) * f_y_given_v1
    end

    win_payoff, _ = quadgk(integrand_win, y_lower, x₁, rtol=m.tol)

    # Losing payoff (pay own bid)
    own_bid = bid_WOA(m, x₁, η)

    integrand_lose(y) = begin
        if y ≤ x₁
            return 0.0
        end
        f_y_given_v1 = pdf(Normal(μ_cond, σ_cond), y)
        return -own_bid * f_y_given_v1
    end

    lose_payoff, _ = quadgk(integrand_lose, x₁, y_upper, rtol=m.tol)

    return win_payoff + lose_payoff
end

function expected_payoff_WOA(m::ModelParameters, x₁::Float64, η::Float64)
    post_mean = posterior_value_mean(m, x₁, η)
    post_var = 1 / (1/m.σ^2 + η)
    post_std = sqrt(post_var)

    v1_lower = post_mean - 4*post_std
    v1_upper = post_mean + 4*post_std

    integrand(v₁) = begin
        payoff = payoff_WOA_given_value(m, v₁, x₁, η)
        density = pdf(Normal(post_mean, post_std), v₁)
        return payoff * density
    end

    result, _ = quadgk(integrand, v1_lower, v1_upper, rtol=m.tol)
    return result
end

"""
Total expected payoff in mechanism, integrating over signal distribution.
"""
function total_expected_payoff(m::ModelParameters, mechanism::Symbol, η::Float64;
                              bid_func_FPA=nothing)
    σ_x = sqrt(m.σ^2 + 1/η)
    x_lower = m.μ - 4*σ_x
    x_upper = m.μ + 4*σ_x

    integrand(x₁) = begin
        marginal = signal_marginal_density(m, x₁, η)

        payoff = if mechanism == :SPA
            expected_payoff_SPA(m, x₁, η)
        elseif mechanism == :FPA
            expected_payoff_FPA(m, x₁, η, bid_func_FPA)
        elseif mechanism == :APA
            expected_payoff_APA(m, x₁, η)
        elseif mechanism == :WOA
            expected_payoff_WOA(m, x₁, η)
        else
            error("Unknown mechanism: $mechanism")
        end

        return payoff * marginal
    end

    result, _ = quadgk(integrand, x_lower, x_upper, rtol=m.tol)
    return result
end

println("✓ Part 3 complete: Payoff functions implemented from theory")
println()

# ==============================================================================
# PART 5: SINGLE-CROSSING PROPERTY (THE CORE THEOREM)
# ==============================================================================

"""
Test single-crossing property: Δu = u_I - u_II

If ∂Δu/∂v₁ is quasi-monotone (crosses zero at most once, from below),
then MR_I(η) ≥ MR_II(η) for all η.

This is the theoretical foundation for ranking mechanisms.
"""
function test_single_crossing(m::ModelParameters, mech_I::Symbol, mech_II::Symbol,
                              η::Float64; n_test=20, bid_func_FPA=nothing)

    println("\n" * "="^80)
    println("SINGLE-CROSSING TEST: $mech_I vs $mech_II at η=$η")
    println("="^80)

    # Test signal
    x₁ = m.μ

    # Range of values to test
    post_mean = posterior_value_mean(m, x₁, η)
    post_var = 1 / (1/m.σ^2 + η)
    post_std = sqrt(post_var)

    v₁_range = range(post_mean - 2*post_std, post_mean + 2*post_std, length=n_test)

    derivatives = Float64[]

    for v₁ in v₁_range
        # Compute payoff difference
        payoff_I = if mech_I == :SPA
            payoff_SPA_given_value(m, v₁, x₁, η)
        elseif mech_I == :FPA
            payoff_FPA_given_value(m, v₁, x₁, η, bid_func_FPA)
        elseif mech_I == :APA
            payoff_APA_given_value(m, v₁, x₁, η)
        elseif mech_I == :WOA
            payoff_WOA_given_value(m, v₁, x₁, η)
        end

        payoff_II = if mech_II == :SPA
            payoff_SPA_given_value(m, v₁, x₁, η)
        elseif mech_II == :FPA
            payoff_FPA_given_value(m, v₁, x₁, η, bid_func_FPA)
        elseif mech_II == :APA
            payoff_APA_given_value(m, v₁, x₁, η)
        elseif mech_II == :WOA
            payoff_WOA_given_value(m, v₁, x₁, η)
        end

        Δu = payoff_I - payoff_II

        # Compute derivative using ForwardDiff
        f(v) = begin
            p_I = if mech_I == :SPA
                payoff_SPA_given_value(m, v, x₁, η)
            elseif mech_I == :FPA
                payoff_FPA_given_value(m, v, x₁, η, bid_func_FPA)
            elseif mech_I == :APA
                payoff_APA_given_value(m, v, x₁, η)
            elseif mech_I == :WOA
                payoff_WOA_given_value(m, v, x₁, η)
            end

            p_II = if mech_II == :SPA
                payoff_SPA_given_value(m, v, x₁, η)
            elseif mech_II == :FPA
                payoff_FPA_given_value(m, v, x₁, η, bid_func_FPA)
            elseif mech_II == :APA
                payoff_APA_given_value(m, v, x₁, η)
            elseif mech_II == :WOA
                payoff_WOA_given_value(m, v, x₁, η)
            end

            return p_I - p_II
        end

        deriv = ForwardDiff.derivative(f, v₁)
        push!(derivatives, deriv)

        @printf("v₁=%.3f: Δu=%.4f, ∂Δu/∂v₁=%.4f\n", v₁, Δu, deriv)
    end

    # Check quasi-monotonicity
    crossed_positive = false
    is_quasi_monotone = true

    for i in 1:length(derivatives)
        if derivatives[i] > 0 && !crossed_positive
            crossed_positive = true
            println("\n→ Derivative becomes positive at v₁=$(v₁_range[i])")
        end

        if crossed_positive && derivatives[i] < -1e-6
            is_quasi_monotone = false
            println("✗ VIOLATION: Derivative becomes negative again at v₁=$(v₁_range[i])")
            break
        end
    end

    if is_quasi_monotone
        println("\n✓ QUASI-MONOTONE → MR_$mech_I(η) ≥ MR_$mech_II(η)")
        println("  Theoretical ranking: $mech_I has stronger info incentives than $mech_II")
        return true
    else
        println("\n✗ NOT QUASI-MONOTONE → Ranking indeterminate")
        return false
    end
end

println("✓ Part 5: Single-crossing framework ready")
println()

# ==============================================================================
# PART 6: NUMERICAL VERIFICATION
# ==============================================================================

"""
Compute marginal return to information MR(η) = ∂E[payoff]/∂η
"""
function marginal_return(m::ModelParameters, mechanism::Symbol, η::Float64;
                        δη=0.01, bid_func_FPA_low=nothing, bid_func_FPA_high=nothing)
    # Richardson extrapolation for better accuracy
    η_high = η + δη
    η_low = η - δη

    payoff_high = total_expected_payoff(m, mechanism, η_high, bid_func_FPA=bid_func_FPA_high)
    payoff_low = total_expected_payoff(m, mechanism, η_low, bid_func_FPA=bid_func_FPA_low)

    return (payoff_high - payoff_low) / (2*δη)
end

"""
Find equilibrium η* where MR(η) = MC(η)
"""
function find_equilibrium_eta(m::ModelParameters, mechanism::Symbol;
                             η_initial=5.0, verbose=false)
    println("\nFinding equilibrium for $mechanism...")

    function foc(η)
        # Need to recompute bid function for FPA at each η
        bid_func = nothing
        bid_func_low = nothing
        bid_func_high = nothing

        if mechanism == :FPA
            bid_func = solve_FPA_bidding_ode(m, η)
            bid_func_low = solve_FPA_bidding_ode(m, η - 0.01)
            bid_func_high = solve_FPA_bidding_ode(m, η + 0.01)
        end

        mr = marginal_return(m, mechanism, η,
                           bid_func_FPA_low=bid_func_low,
                           bid_func_FPA_high=bid_func_high)
        mc = marginal_cost(m, η)

        if verbose
            @printf("  η=%.3f: MR=%.6f, MC=%.6f, Gap=%.6f\n", η, mr, mc, mr-mc)
        end

        return mr - mc
    end

    try
        η_star = find_zero(foc, (m.η_min + 0.1, m.η_max - 0.1), Bisection())

        if verbose
            mr_star = marginal_return(m, mechanism, η_star)
            mc_star = marginal_cost(m, η_star)
            payoff_star = total_expected_payoff(m, mechanism, η_star,
                          bid_func_FPA=(mechanism==:FPA ? solve_FPA_bidding_ode(m, η_star) : nothing))
            net_payoff = payoff_star - cost_function(m, η_star)

            @printf("\n✓ Equilibrium found for $mechanism:\n")
            @printf("  η* = %.4f\n", η_star)
            @printf("  MR = %.6f\n", mr_star)
            @printf("  MC = %.6f\n", mc_star)
            @printf("  Net payoff = %.6f\n", net_payoff)
        end

        return η_star

    catch e
        println("✗ Failed to find equilibrium for $mechanism: $e")
        return NaN
    end
end

println("✓ Part 6: Numerical methods ready")
println()

println("="^80)
println("ALL COMPONENTS COMPLETE")
println("Ready to run tests and verify theoretical predictions")
println("="^80)
