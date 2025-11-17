# ============================================================================
# QUICK TEST: High Interdependence (α ≥ 0.5)
# Easiest modification - just change one parameter!
# ============================================================================
#
# Current model: u_i = V_i + αV_j with α ~ 0.3 (implicit in posterior)
# Test: What if α ∈ [0.5, 0.6, 0.7, 0.8, 0.9]?
#
# Theory: When opponent's value matters more (high α):
#   - Learning about V_j becomes more important
#   - FPA might benefit more from its information advantage
#   - SPA's linkage principle weakens (V_i matters less)
#
# This requires modifying v_symmetric() to use higher interdependence
# ============================================================================

include("comprehensive_julia_implementation.jl")

using Printf

# ============================================================================
# MODIFIED POSTERIOR WITH INTERDEPENDENCE
# ============================================================================

"""
Modified posterior expectation with explicit interdependence parameter α

Original: E[V_i|X_i=x, X_j=x]
Modified: E[u_i|X_i=x, X_j=x] where u_i = V_i + α·V_j

For symmetric case X_i = X_j = x:
E[u_i|X_i=x, X_j=x] = E[V_i|X_i=x, X_j=x] + α·E[V_j|X_i=x, X_j=x]
                     = (1+α)·E[V|X=x, X=x]  (by symmetry)
"""
function v_symmetric_interdep(x::Float64, η::Float64, m::AuctionModel, α::Float64)
    # Base posterior (same as before)
    A = (1 + m.ρ) * m.σ^2
    weight = A / (A + 1/η)
    E_v = m.μ + weight * (x - m.μ)

    # With interdependence: u_i = V_i + α·V_j
    # In symmetric case: E[u_i|x,x] = (1+α)·E[V|x,x]
    E_u = (1 + α) * E_v

    return clamp(E_u, m.vmin, 2.0)  # Allow values up to 2.0 for high α
end

"""
Bidding function for SPA with interdependence
"""
function bid_spa_interdep(x::Float64, η::Float64, m::AuctionModel, α::Float64)
    return v_symmetric_interdep(x, η, m, α)
end

"""
FPA bidding with interdependence
Uses same ODE but with modified value function
"""
function precompute_bids_FPA_interdep(η::Float64, m::AuctionModel, α::Float64; nx::Int=600)
    smin = m.vmin - 6/sqrt(η)
    smax = m.vmax + 6/sqrt(η)
    grid = range(smin, smax, length=nx)
    bFPA = zeros(nx)

    bFPA[1] = 0.0

    for i in 1:(nx-1)
        x = grid[i]
        dx = grid[i+1] - grid[i]

        # Use interdependent value
        v1 = v_symmetric_interdep(x, η, m, α)
        f1 = f_X2_given_X1(x, x, η, m)
        F1 = F_X2_given_X1(x, x, η, m)
        h1 = F1 > m.tol ? f1 / F1 : 0.0
        k1 = (v1 - bFPA[i]) * h1

        xmid = x + 0.5*dx
        v2 = v_symmetric_interdep(xmid, η, m, α)
        f2 = f_X2_given_X1(xmid, xmid, η, m)
        F2 = F_X2_given_X1(xmid, xmid, η, m)
        h2 = F2 > m.tol ? f2 / F2 : 0.0
        k2 = (v2 - (bFPA[i] + 0.5*dx*k1)) * h2

        k3 = (v2 - (bFPA[i] + 0.5*dx*k2)) * h2

        xend = grid[i+1]
        v4 = v_symmetric_interdep(xend, η, m, α)
        f4 = f_X2_given_X1(xend, xend, η, m)
        F4 = F_X2_given_X1(xend, xend, η, m)
        h4 = F4 > m.tol ? f4 / F4 : 0.0
        k4 = (v4 - (bFPA[i] + dx*k3)) * h4

        bFPA[i+1] = bFPA[i] + (dx/6) * (k1 + 2*k2 + 2*k3 + k4)
    end

    return BidsCache(collect(grid), bFPA)
end

"""
Expected payoff with interdependence
Note: Payoff still based on TRUE value, not interdependent utility!
Winner gets u_i = V_i + α·V_j
"""
function EU_gross_interdep(η::Float64, mech::Symbol, m::AuctionModel, D::DrawsCRN, α::Float64;
                           cacheFPA::Union{BidsCache,Nothing}=nothing)
    N = length(D.v1)
    payoff_sum = 0.0

    for i in 1:N
        x1 = D.v1[i] + D.e1[i] / sqrt(η)
        x2 = D.v2[i] + D.e2[i] / sqrt(η)

        # True interdependent utility
        u1 = D.v1[i] + α * D.v2[i]

        if mech == :FPA
            b1 = lininterp(x1, cacheFPA)
            b2 = lininterp(x2, cacheFPA)

            if b1 ≥ b2
                payoff_sum += u1 - b1
            end

        elseif mech == :SPA
            b1 = bid_spa_interdep(x1, η, m, α)
            b2 = bid_spa_interdep(x2, η, m, α)

            if b1 ≥ b2
                payoff_sum += u1 - b2
            end
        end
    end

    return payoff_sum / N
end

"""
Revenue with interdependence
"""
function revenue_interdep(η::Float64, mech::Symbol, m::AuctionModel, D::DrawsCRN, α::Float64;
                          cacheFPA::Union{BidsCache,Nothing}=nothing)
    N = length(D.v1)
    revenue_sum = 0.0

    for i in 1:N
        x1 = D.v1[i] + D.e1[i] / sqrt(η)
        x2 = D.v2[i] + D.e2[i] / sqrt(η)

        if mech == :FPA
            b1 = lininterp(x1, cacheFPA)
            b2 = lininterp(x2, cacheFPA)
            revenue_sum += max(b1, b2)

        elseif mech == :SPA
            b1 = bid_spa_interdep(x1, η, m, α)
            b2 = bid_spa_interdep(x2, η, m, α)
            revenue_sum += min(b1, b2)
        end
    end

    return revenue_sum / N
end

"""
Marginal revenue with interdependence
"""
function MR_one_interdep(η::Float64, mech::Symbol, m::AuctionModel, D::DrawsCRN, α::Float64;
                         h_frac::Float64=0.01)
    h = min(0.1, h_frac * η)

    ηp = min(m.ηmax, η + h/2)
    ηm = max(m.ηmin + 1e-8, η - h/2)
    ηp2 = min(m.ηmax, η + h/4)
    ηm2 = max(m.ηmin + 1e-8, η - h/4)

    if mech == :FPA
        cache_p = precompute_bids_FPA_interdep(ηp, m, α)
        cache_m = precompute_bids_FPA_interdep(ηm, m, α)
        cache_p2 = precompute_bids_FPA_interdep(ηp2, m, α)
        cache_m2 = precompute_bids_FPA_interdep(ηm2, m, α)

        up = EU_gross_interdep(ηp, mech, m, D, α; cacheFPA=cache_p)
        um = EU_gross_interdep(ηm, mech, m, D, α; cacheFPA=cache_m)
        up2 = EU_gross_interdep(ηp2, mech, m, D, α; cacheFPA=cache_p2)
        um2 = EU_gross_interdep(ηm2, mech, m, D, α; cacheFPA=cache_m2)
    else
        up = EU_gross_interdep(ηp, mech, m, D, α)
        um = EU_gross_interdep(ηm, mech, m, D, α)
        up2 = EU_gross_interdep(ηp2, mech, m, D, α)
        um2 = EU_gross_interdep(ηm2, mech, m, D, α)
    end

    D1 = (up - um) / (ηp - ηm)
    D2 = (up2 - um2) / (ηp2 - ηm2)

    return (4*D2 - D1) / 3
end

function MR_with_CI_interdep(η::Float64, mech::Symbol, m::AuctionModel, α::Float64;
                              K::Int=4, N::Int=60000, seed::Int=42, h_frac::Float64=0.01)
    estimates = zeros(K)

    for k in 1:K
        Dk = make_draws(m; N=N, seed=seed + 911*k, antithetic=true)
        estimates[k] = MR_one_interdep(η, mech, m, Dk, α; h_frac=h_frac)
    end

    μ = mean(estimates)
    se = std(estimates, corrected=true) / sqrt(K)

    return μ, se
end

"""
Solve equilibrium with interdependence
"""
function solve_eta_star_interdep(mech::Symbol, m::AuctionModel, α::Float64;
                                  N::Int=80000, K::Int=3, seed::Int=42)

    a = m.ηmin + 1e-4
    b = m.ηmax

    μFa, seFa = MR_with_CI_interdep(a, mech, m, α; K=K, N=N, seed=seed)
    μFa -= MC(a, m)

    μFb, seFb = MR_with_CI_interdep(b, mech, m, α; K=K, N=N, seed=seed+1)
    μFb -= MC(b, m)

    sL = sign_CI(μFa, seFa)
    sR = sign_CI(μFb, seFb)

    # Validate corners
    if sL == +1 && sR == +1
        if abs(μFb) ≤ 1e-3 && seFb ≤ 1e-3
            return b, μFb, seFb
        else
            return NaN, μFb, seFb
        end
    end

    if sL == -1 && sR == -1
        if abs(μFa) ≤ 1e-3 && seFa ≤ 1e-3
            return a, μFa, seFa
        else
            return NaN, μFa, seFa
        end
    end

    # Bisection
    for iter in 1:40
        c = (a + b) / 2
        μFc, seFc = MR_with_CI_interdep(c, mech, m, α; K=K, N=N, seed=seed+iter+10)
        μFc -= MC(c, m)
        sc = sign_CI(μFc, seFc)

        if abs(μFc) ≤ 1e-3 && seFc ≤ 1e-3
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

    c = (a + b) / 2
    μFc, seFc = MR_with_CI_interdep(c, mech, m, α; K=K, N=N, seed=seed+100)
    μFc -= MC(c, m)

    return c, μFc, seFc
end

"""
Test single α value
"""
function test_interdependence(ρ, σ, α; N=80000, K=3, verbose=true)
    if verbose
        println("="^70)
        println("TESTING HIGH INTERDEPENDENCE")
        println("="^70)
        @printf("Parameters: ρ=%.2f, σ=%.2f, α=%.2f\n", ρ, σ, α)
        println()
    end

    m = make_model(ρ=ρ, σ=σ, c2=1e-6, c3=2e-7)

    if verbose
        println("Solving equilibria...")
    end

    ηF, gapF, seF = solve_eta_star_interdep(:FPA, m, α; N=N, K=K)
    ηS, gapS, seS = solve_eta_star_interdep(:SPA, m, α; N=N, K=K, seed=12345)

    validF = is_valid_equilibrium(ηF, gapF, seF)
    validS = is_valid_equilibrium(ηS, gapS, seS)

    if verbose
        println("-"^70)
        @printf("FPA: η*=%.3f, gap=%+.2e, valid=%s\n", ηF, gapF, validF)
        @printf("SPA: η*=%.3f, gap=%+.2e, valid=%s\n", ηS, gapS, validS)
        println()
    end

    if validF && validS
        D = make_draws(m; N=N, seed=54321)
        cacheF = precompute_bids_FPA_interdep(ηF, m, α)

        RF = revenue_interdep(ηF, :FPA, m, D, α; cacheFPA=cacheF)
        RS = revenue_interdep(ηS, :SPA, m, D, α)

        if verbose
            println("-"^70)
            println("REVENUE:")
            @printf("R_FPA = %.6f\n", RF)
            @printf("R_SPA = %.6f\n", RS)
            @printf("Ratio = %.6f\n", RF/RS)

            if RF > RS
                println("🎉 REVERSAL! FPA wins by $(@sprintf(\"%.2f%%\", (RF/RS-1)*100))")
            else
                println("Standard: SPA wins by $(@sprintf(\"%.2f%%\", (RS/RF-1)*100))")
            end
            println("="^70)
        end

        return (α=α, ρ=ρ, σ=σ, ηF=ηF, ηS=ηS, RF=RF, RS=RS, ratio=RF/RS,
                reversal=(RF>RS), validF=validF, validS=validS)
    else
        if verbose
            println("⚠️  Invalid equilibria - cannot compare revenues")
            println("="^70)
        end
        return (α=α, ρ=ρ, σ=σ, ηF=ηF, ηS=ηS, RF=NaN, RS=NaN, ratio=NaN,
                reversal=false, validF=validF, validS=validS)
    end
end

"""
Sweep across α values
"""
function sweep_interdependence(;
    α_range = [0.5, 0.6, 0.7, 0.8, 0.9],
    ρ_range = [0.5, 0.7, 0.9],
    σ_range = [0.3, 0.4, 0.5],
    N = 60000,
    K = 3
)
    println("="^70)
    println("INTERDEPENDENCE PARAMETER SWEEP")
    println("="^70)
    println("Testing $(length(α_range) * length(ρ_range) * length(σ_range)) combinations")
    println()

    results = []
    count = 0
    total = length(α_range) * length(ρ_range) * length(σ_range)

    for α in α_range, ρ in ρ_range, σ in σ_range
        count += 1
        @printf("[%d/%d] Testing α=%.1f, ρ=%.1f, σ=%.1f...\n", count, total, α, ρ, σ)

        result = test_interdependence(ρ, σ, α; N=N, K=K, verbose=false)
        push!(results, result)

        if result.reversal
            @printf("  ✓ REVERSAL FOUND! Ratio=%.4f\n", result.ratio)
        elseif result.validF && result.validS
            @printf("  Standard (ratio=%.4f)\n", result.ratio)
        else
            println("  Invalid equilibria")
        end
    end

    # Summary
    println()
    println("="^70)
    println("SWEEP RESULTS:")

    valid = filter(r -> r.validF && r.validS, results)
    reversals = filter(r -> r.reversal, valid)

    @printf("Valid: %d/%d\n", length(valid), length(results))
    @printf("Reversals: %d/%d\n", length(reversals), length(valid))

    if length(reversals) > 0
        println("\n🎉 REVERSALS FOUND:")
        sort!(reversals, by=r->r.ratio, rev=true)
        for r in reversals
            @printf("  α=%.1f, ρ=%.1f, σ=%.1f: ratio=%.4f\n", r.α, r.ρ, r.σ, r.ratio)
        end
    else
        println("\n❌ NO REVERSALS")
        if length(valid) > 0
            println("\nClosest:")
            sort!(valid, by=r->abs(r.ratio-1))
            for r in valid[1:min(3,length(valid))]
                @printf("  α=%.1f, ρ=%.1f, σ=%.1f: ratio=%.4f\n", r.α, r.ρ, r.σ, r.ratio)
            end
        end
    end
    println("="^70)

    return results
end

# Run sweep if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    println("Starting high interdependence test...")
    println("This is the EASIEST extension - just changing α parameter!")
    println()

    results = sweep_interdependence()

    println("\n✅ Interdependence sweep complete!")
end
