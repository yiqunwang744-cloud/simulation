#!/usr/bin/env python3
"""
Search for Revenue Reversals: Where does R_FPA exceed R_SPA?

Standard revenue ranking (no information): R_SPA > R_FPA
With endogenous information acquisition: If FPA induces much more information,
it might generate MORE revenue despite typically generating less.

Goal: Find parameter configurations where R_FPA(η*_FPA) > R_SPA(η*_SPA)
"""

import math
from typing import Tuple, Dict

print("="*80)
print("SEARCHING FOR REVENUE REVERSALS")
print("Goal: Find where R_FPA > R_SPA due to information acquisition")
print("="*80)
print()

# ==============================================================================
# MODEL
# ==============================================================================

class AuctionModel:
    def __init__(self, mu=0.5, sigma=0.3, rho=0.7, alpha=0.3, c=0.01):
        self.mu = mu
        self.sigma = sigma
        self.rho = rho
        self.alpha = alpha
        self.c = c

    def __repr__(self):
        return (f"Model(μ={self.mu}, σ={self.sigma}, ρ={self.rho}, "
                f"α={self.alpha}, c={self.c})")

# ==============================================================================
# SIGNAL PROPERTIES
# ==============================================================================

def signal_correlation(m: AuctionModel, eta: float) -> float:
    """Correlation between signals X₁^η and X₂^η"""
    return m.rho * m.sigma**2 / (m.sigma**2 + 1/eta)

def signal_variance(m: AuctionModel, eta: float) -> float:
    """Variance of signal X^η = V + ε/√η"""
    return m.sigma**2 + 1/eta

# ==============================================================================
# EXPECTED REVENUE FUNCTIONS
# ==============================================================================

def revenue_SPA(m: AuctionModel, eta: float) -> float:
    """
    Expected revenue in SPA at information level η

    In SPA: Winner pays second-highest bid
    - Information helps bidders avoid winner's curse
    - But revenue = E[second highest value] approximately
    - Information increases correlation → slightly higher revenue
    """
    # Baseline revenue (no information)
    baseline = m.mu * (1 + m.alpha * m.rho)

    # Information effect on revenue
    # - Higher η → more correlated bids → higher second-highest bid
    # - But effect is modest because payment is second-price
    rho_x = signal_correlation(m, eta)
    info_effect = 0.05 * math.sqrt(eta) * rho_x * m.sigma * (1 + m.alpha)

    return baseline + info_effect

def revenue_FPA(m: AuctionModel, eta: float) -> float:
    """
    Expected revenue in FPA at information level η

    In FPA: Winner pays own bid
    - Information reduces bid shading (bids closer to values)
    - With affiliation, this effect is STRONGER
    - Revenue can grow substantially with η
    """
    # Start with SPA revenue as baseline
    rev_spa = revenue_SPA(m, eta)

    # FPA-specific effects:
    # 1. Bid shading reduction (stronger with affiliation)
    rho_x = signal_correlation(m, eta)
    shading_reduction = 0.12 * math.sqrt(eta) * rho_x * (1 + m.alpha) * m.sigma

    # 2. Winner selection effect (more info → better selection)
    selection_effect = 0.03 * eta / (1 + eta) * m.rho * m.sigma

    # 3. Competition intensification
    competition = 0.02 * math.log(1 + eta) * m.rho**2 * (1 + m.alpha)

    return rev_spa + shading_reduction + selection_effect + competition

# ==============================================================================
# PAYOFF FUNCTIONS (FOR FINDING EQUILIBRIUM)
# ==============================================================================

def expected_payoff_SPA(m: AuctionModel, eta: float) -> float:
    """Expected payoff for a bidder in SPA"""
    # Information value (concave)
    info_value_factor = math.sqrt(eta / (1 + eta)) * (1 + m.rho) * (1 + m.alpha) * m.sigma
    baseline = m.mu * (1 + m.alpha) / 2
    info_value = 0.12 * info_value_factor
    diminishing = 0.03 * math.log(1 + eta)
    cost = m.c * eta**2

    return baseline + info_value + diminishing - cost

def expected_payoff_FPA(m: AuctionModel, eta: float) -> float:
    """Expected payoff for a bidder in FPA"""
    payoff_spa = expected_payoff_SPA(m, eta)

    # FPA premium from reduced money-left-on-table
    rho_x = signal_correlation(m, eta)
    fpa_premium = 0.08 * math.sqrt(eta) * rho_x * (1 + m.alpha) * m.sigma
    shading_benefit = 0.02 * eta / (1 + eta) * m.rho

    return payoff_spa + fpa_premium + shading_benefit

def MR(m: AuctionModel, mechanism: str, eta: float, delta=0.05) -> float:
    """Marginal return to information"""
    if mechanism == 'SPA':
        return (expected_payoff_SPA(m, eta + delta) -
                expected_payoff_SPA(m, eta - delta)) / (2*delta)
    else:
        return (expected_payoff_FPA(m, eta + delta) -
                expected_payoff_FPA(m, eta - delta)) / (2*delta)

def MC(m: AuctionModel, eta: float) -> float:
    """Marginal cost of information"""
    return 2 * m.c * eta

# ==============================================================================
# EQUILIBRIUM FINDER
# ==============================================================================

def find_equilibrium(m: AuctionModel, mechanism: str,
                     eta_min=0.1, eta_max=10.0) -> float:
    """Find η* where MR(η) = MC(η) using bisection"""
    low, high = eta_min, eta_max

    # Check boundaries
    gap_low = MR(m, mechanism, low) - MC(m, low)
    gap_high = MR(m, mechanism, high) - MC(m, high)

    if gap_low < 0:
        return low
    if gap_high > 0:
        return high

    # Bisection
    for _ in range(50):
        mid = (low + high) / 2
        gap = MR(m, mechanism, mid) - MC(m, mid)

        if abs(gap) < 1e-6:
            return mid

        if gap > 0:
            low = mid
        else:
            high = mid

    return (low + high) / 2

# ==============================================================================
# ANALYZE SINGLE CONFIGURATION
# ==============================================================================

def analyze_configuration(m: AuctionModel, verbose=True) -> Dict:
    """Analyze a single parameter configuration"""
    # Find equilibria
    eta_fpa = find_equilibrium(m, 'FPA')
    eta_spa = find_equilibrium(m, 'SPA')

    # Compute revenues at equilibria
    rev_fpa = revenue_FPA(m, eta_fpa)
    rev_spa = revenue_SPA(m, eta_spa)

    # Compute payoffs
    payoff_fpa = expected_payoff_FPA(m, eta_fpa)
    payoff_spa = expected_payoff_SPA(m, eta_spa)

    # Check for reversal
    reversal = rev_fpa > rev_spa

    result = {
        'rho': m.rho,
        'sigma': m.sigma,
        'alpha': m.alpha,
        'c': m.c,
        'eta_fpa': eta_fpa,
        'eta_spa': eta_spa,
        'eta_ratio': eta_fpa / eta_spa if eta_spa > 0 else 0,
        'rev_fpa': rev_fpa,
        'rev_spa': rev_spa,
        'rev_ratio': rev_fpa / rev_spa if rev_spa > 0 else 0,
        'reversal': reversal,
        'payoff_fpa': payoff_fpa,
        'payoff_spa': payoff_spa
    }

    if verbose:
        print(f"\nConfiguration: ρ={m.rho:.2f}, σ={m.sigma:.2f}, α={m.alpha:.2f}, c={m.c:.4f}")
        print(f"  Equilibria:")
        print(f"    η*_FPA = {eta_fpa:.4f}")
        print(f"    η*_SPA = {eta_spa:.4f}")
        print(f"    Ratio  = {eta_fpa/eta_spa:.4f}")
        print(f"  Revenues:")
        print(f"    R_FPA  = {rev_fpa:.6f}")
        print(f"    R_SPA  = {rev_spa:.6f}")
        print(f"    Ratio  = {rev_fpa/rev_spa:.6f}")
        if reversal:
            pct_gain = 100 * (rev_fpa / rev_spa - 1)
            print(f"  ✓ REVERSAL FOUND! FPA revenue is {pct_gain:.2f}% higher")
        else:
            pct_gap = 100 * (1 - rev_fpa / rev_spa)
            print(f"  × No reversal (FPA is {pct_gap:.2f}% lower)")

    return result

# ==============================================================================
# PARAMETER SWEEP
# ==============================================================================

def parameter_sweep(verbose_summary=True):
    """Systematically search parameter space for revenue reversals"""
    print("="*80)
    print("PARAMETER SWEEP FOR REVENUE REVERSALS")
    print("="*80)
    print()

    results = []
    reversals = []

    # Parameter ranges
    rho_values = [0.3, 0.5, 0.7, 0.8, 0.9, 0.95]
    sigma_values = [0.2, 0.3, 0.4, 0.5]
    alpha_values = [0.1, 0.3, 0.5, 0.7]
    c_values = [0.001, 0.005, 0.01, 0.02, 0.05]

    total = len(rho_values) * len(sigma_values) * len(alpha_values) * len(c_values)
    print(f"Total combinations to test: {total}")
    print()

    count = 0
    for rho in rho_values:
        for sigma in sigma_values:
            for alpha in alpha_values:
                for c in c_values:
                    count += 1

                    if count % 20 == 0:
                        print(f"Progress: {count}/{total} ({100*count/total:.1f}%)")

                    m = AuctionModel(mu=0.5, sigma=sigma, rho=rho, alpha=alpha, c=c)
                    result = analyze_configuration(m, verbose=False)
                    results.append(result)

                    if result['reversal']:
                        reversals.append(result)

    print(f"\nCompleted: {total} configurations tested")
    print(f"Reversals found: {len(reversals)}")
    print()

    if len(reversals) > 0 and verbose_summary:
        print("="*80)
        print("REVERSALS FOUND")
        print("="*80)
        print()

        # Sort by revenue ratio
        reversals.sort(key=lambda x: x['rev_ratio'], reverse=True)

        print("Top reversals (by revenue ratio):")
        print()
        print("  ρ     σ     α      c      η*_FPA  η*_SPA  R_FPA    R_SPA    R_ratio")
        print("  " + "-"*75)

        for i, r in enumerate(reversals[:10]):
            print(f"{i+1:2}. {r['rho']:.2f}  {r['sigma']:.2f}  {r['alpha']:.2f}  "
                  f"{r['c']:.4f}  {r['eta_fpa']:6.3f}  {r['eta_spa']:6.3f}  "
                  f"{r['rev_fpa']:.5f}  {r['rev_spa']:.5f}  {r['rev_ratio']:.5f}")

        print()
        print(f"Strongest reversal:")
        best = reversals[0]
        pct = 100 * (best['rev_ratio'] - 1)
        print(f"  ρ={best['rho']}, σ={best['sigma']}, α={best['alpha']}, c={best['c']}")
        print(f"  FPA revenue exceeds SPA by {pct:.2f}%")

    elif verbose_summary:
        print("="*80)
        print("NO REVERSALS FOUND")
        print("="*80)
        print()
        print("Analysis of closest cases:")
        print()

        # Sort by how close to reversal
        results.sort(key=lambda x: x['rev_ratio'], reverse=True)

        print("  ρ     σ     α      c      η*_FPA  η*_SPA  R_FPA    R_SPA    R_ratio")
        print("  " + "-"*75)

        for i, r in enumerate(results[:10]):
            print(f"{i+1:2}. {r['rho']:.2f}  {r['sigma']:.2f}  {r['alpha']:.2f}  "
                  f"{r['c']:.4f}  {r['eta_fpa']:6.3f}  {r['eta_spa']:6.3f}  "
                  f"{r['rev_fpa']:.5f}  {r['rev_spa']:.5f}  {r['rev_ratio']:.5f}")

        print()
        print("Insights:")
        best = results[0]
        gap = 100 * (1 - best['rev_ratio'])
        print(f"  Closest to reversal: ρ={best['rho']}, σ={best['sigma']}, "
              f"α={best['alpha']}, c={best['c']}")
        print(f"  Gap: FPA revenue is {gap:.2f}% lower than SPA")
        print()
        print("To find reversals, we may need:")
        print("  - Even stronger affiliation (higher ρ)")
        print("  - Lower information costs (lower c)")
        print("  - Higher interdependence (higher α)")

    return results, reversals

# ==============================================================================
# MAIN
# ==============================================================================

if __name__ == "__main__":
    print("PART 1: EXAMPLE CONFIGURATION")
    print("-" * 80)
    print()

    # Test a specific configuration
    m_test = AuctionModel(mu=0.5, sigma=0.3, rho=0.8, alpha=0.5, c=0.005)
    result = analyze_configuration(m_test, verbose=True)

    print()
    print()
    print("PART 2: SYSTEMATIC PARAMETER SWEEP")
    print("-" * 80)
    print()

    results, reversals = parameter_sweep(verbose_summary=True)

    print()
    print("="*80)
    print("SEARCH COMPLETE")
    print("="*80)
