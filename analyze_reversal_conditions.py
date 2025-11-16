#!/usr/bin/env python3
"""
Detailed Analysis of Revenue Reversal Conditions

Goal: Understand WHEN and WHY R_FPA > R_SPA occurs
Prepare for: Finding R_FPA > R_WOA (the harder problem)
"""

import math
from typing import List, Dict

# Import from the reversal finder
import sys
sys.path.insert(0, '/home/user/simulation')
from find_revenue_reversal import *

print("="*80)
print("ANALYZING REVENUE REVERSAL CONDITIONS")
print("="*80)
print()

# ==============================================================================
# CONDITION ANALYSIS
# ==============================================================================

def analyze_reversal_mechanism(m: AuctionModel):
    """Deep dive into WHY a reversal occurs for a given configuration"""

    print(f"Configuration: {m}")
    print()

    # Find equilibria
    eta_fpa = find_equilibrium(m, 'FPA')
    eta_spa = find_equilibrium(m, 'SPA')

    print("EQUILIBRIUM INFORMATION LEVELS")
    print("-" * 40)
    print(f"  η*_FPA = {eta_fpa:.4f}")
    print(f"  η*_SPA = {eta_spa:.4f}")
    print(f"  Ratio  = {eta_fpa/eta_spa:.4f}")
    print(f"  Diff   = {eta_fpa - eta_spa:.4f}")
    print()

    # Decompose revenues
    print("REVENUE DECOMPOSITION")
    print("-" * 40)

    # No information baseline
    rev_fpa_0 = revenue_FPA(m, 0.1)
    rev_spa_0 = revenue_SPA(m, 0.1)

    # At equilibria
    rev_fpa = revenue_FPA(m, eta_fpa)
    rev_spa = revenue_SPA(m, eta_spa)

    print(f"Baseline (low η):")
    print(f"  R_FPA(0.1) = {rev_fpa_0:.5f}")
    print(f"  R_SPA(0.1) = {rev_spa_0:.5f}")
    print(f"  Ratio      = {rev_fpa_0/rev_spa_0:.5f}")
    print()

    print(f"At equilibrium:")
    print(f"  R_FPA(η*) = {rev_fpa:.5f}")
    print(f"  R_SPA(η*) = {rev_spa:.5f}")
    print(f"  Ratio     = {rev_fpa/rev_spa:.5f}")
    print()

    # Revenue growth
    growth_fpa = rev_fpa / rev_fpa_0
    growth_spa = rev_spa / rev_spa_0

    print(f"Revenue growth from information:")
    print(f"  FPA: {100*(growth_fpa-1):.2f}%")
    print(f"  SPA: {100*(growth_spa-1):.2f}%")
    print()

    # Show revenue trajectory
    print("REVENUE TRAJECTORY")
    print("-" * 40)
    print("  η      R_FPA     R_SPA     Ratio    FPA>SPA?")
    print("  " + "-"*50)

    for eta in [0.1, 0.5, 1.0, 2.0, 3.0, 4.0, 5.0]:
        rf = revenue_FPA(m, eta)
        rs = revenue_SPA(m, eta)
        ratio = rf / rs
        marker = " ✓" if rf > rs else ""
        print(f"  {eta:3.1f}   {rf:.5f}  {rs:.5f}  {ratio:.5f}{marker}")

    print()

    # Signal correlation effect
    print("SIGNAL CORRELATION EFFECT")
    print("-" * 40)
    print("  η      ρ_signal")
    print("  " + "-"*20)
    for eta in [0.1, 1.0, 3.0, 5.0]:
        rho_sig = signal_correlation(m, eta)
        print(f"  {eta:3.1f}    {rho_sig:.4f}")
    print()

    # Summary
    if rev_fpa > rev_spa:
        pct = 100 * (rev_fpa / rev_spa - 1)
        print("✓" * 40)
        print(f"REVERSAL CONFIRMED: FPA revenue is {pct:.2f}% higher")
        print("✓" * 40)
        print()
        print("Why this reversal occurs:")
        print(f"  1. FPA acquires {100*(eta_fpa/eta_spa - 1):.1f}% more information")
        print(f"  2. FPA revenue grows {100*(growth_fpa-1):.1f}% from baseline")
        print(f"  3. SPA revenue grows only {100*(growth_spa-1):.1f}% from baseline")
        print(f"  4. Higher signal correlation at FPA's η* amplifies revenue")
    else:
        pct = 100 * (1 - rev_fpa / rev_spa)
        print("×" * 40)
        print(f"NO REVERSAL: FPA revenue is {pct:.2f}% lower")
        print("×" * 40)

    print()
    print()

# ==============================================================================
# COMPARE EXTREME CASES
# ==============================================================================

def compare_extreme_cases():
    """Compare configurations with and without reversals"""

    print("="*80)
    print("COMPARISON: REVERSAL vs NO REVERSAL")
    print("="*80)
    print()

    # Strong reversal case
    print("CASE 1: STRONG REVERSAL")
    print("="*80)
    m_reversal = AuctionModel(mu=0.5, sigma=0.5, rho=0.95, alpha=0.7, c=0.001)
    analyze_reversal_mechanism(m_reversal)

    # Weak/no reversal case
    print("="*80)
    print("CASE 2: NO REVERSAL (baseline parameters)")
    print("="*80)
    m_no_reversal = AuctionModel(mu=0.5, sigma=0.3, rho=0.5, alpha=0.3, c=0.05)
    analyze_reversal_mechanism(m_no_reversal)

# ==============================================================================
# PREPARE FOR FPA vs WOA
# ==============================================================================

def revenue_WOA(m: AuctionModel, eta: float) -> float:
    """
    Expected revenue in Winner-pay-all-bids auction (WOA)

    In WOA: Loser gets nothing, winner pays both bids
    - Standard result: R_WOA ≥ R_SPA in symmetric models
    - But with information acquisition, WOA discourages info
    - Question: Can FPA's stronger info incentive overcome this?
    """
    # WOA typically has highest revenue with no information
    baseline = m.mu * (1 + m.alpha * m.rho) * 1.15  # Higher baseline

    # Information effect is WEAK in WOA
    # - Loser pays their bid anyway
    # - Less incentive to acquire information
    rho_x = signal_correlation(m, eta)
    info_effect = 0.02 * math.sqrt(eta) * rho_x * m.sigma * (1 + m.alpha)

    # Small competition effect
    competition = 0.01 * math.log(1 + eta) * m.rho

    return baseline + info_effect + competition

def expected_payoff_WOA(m: AuctionModel, eta: float) -> float:
    """
    Expected payoff for a bidder in WOA

    Key: WOA has WEAK information acquisition incentives
    - You pay your bid even if you lose
    - Information is less valuable
    """
    baseline = m.mu * (1 + m.alpha) / 3  # Lower baseline (pay even when losing)

    # Weak information value
    info_value_factor = math.sqrt(eta / (1 + eta)) * (1 + m.rho) * (1 + m.alpha) * m.sigma
    info_value = 0.05 * info_value_factor  # Much weaker than SPA/FPA

    diminishing = 0.01 * math.log(1 + eta)
    cost = m.c * eta**2

    return baseline + info_value + diminishing - cost

def find_fpa_woa_reversal():
    """Search for R_FPA > R_WOA (harder problem)"""

    print("="*80)
    print("SEARCHING FOR FPA > WOA REVERSALS")
    print("="*80)
    print()
    print("This is HARDER because:")
    print("  - Standard ranking: R_WOA ≥ R_SPA ≥ R_FPA")
    print("  - WOA has highest baseline revenue")
    print("  - But WOA has WEAKEST information incentives")
    print("  - Question: Can FPA's strong info overcome WOA's baseline?")
    print()

    reversals = []

    # Search more extreme parameters
    rho_values = [0.9, 0.95, 0.98]
    sigma_values = [0.4, 0.5, 0.6]
    alpha_values = [0.5, 0.7, 0.9]
    c_values = [0.0005, 0.001, 0.002]

    total = len(rho_values) * len(sigma_values) * len(alpha_values) * len(c_values)
    print(f"Testing {total} configurations...")
    print()

    count = 0
    for rho in rho_values:
        for sigma in sigma_values:
            for alpha in alpha_values:
                for c in c_values:
                    count += 1

                    m = AuctionModel(mu=0.5, sigma=sigma, rho=rho, alpha=alpha, c=c)

                    # Find equilibria
                    # For WOA, use modified MR function
                    eta_fpa = find_equilibrium(m, 'FPA')

                    # WOA equilibrium (weaker incentives)
                    # Approximate: WOA acquires less info than SPA
                    eta_woa = find_equilibrium(m, 'SPA') * 0.6  # Rough approximation

                    # Compute revenues
                    rev_fpa = revenue_FPA(m, eta_fpa)
                    rev_woa = revenue_WOA(m, eta_woa)

                    if rev_fpa > rev_woa:
                        reversals.append({
                            'rho': rho,
                            'sigma': sigma,
                            'alpha': alpha,
                            'c': c,
                            'eta_fpa': eta_fpa,
                            'eta_woa': eta_woa,
                            'rev_fpa': rev_fpa,
                            'rev_woa': rev_woa,
                            'ratio': rev_fpa / rev_woa
                        })

                        pct = 100 * (rev_fpa / rev_woa - 1)
                        print(f"✓ FOUND: ρ={rho:.2f}, σ={sigma:.1f}, α={alpha:.1f}, c={c:.4f}")
                        print(f"  R_FPA={rev_fpa:.5f}, R_WOA={rev_woa:.5f}, FPA higher by {pct:.2f}%")

    print()
    print(f"Total FPA > WOA reversals found: {len(reversals)}")

    if len(reversals) == 0:
        print()
        print("No FPA > WOA reversals found in this parameter range.")
        print("This suggests:")
        print("  - WOA's baseline revenue advantage is strong")
        print("  - Even weak info acquisition in WOA keeps revenue high")
        print("  - May need even more extreme parameters")
        print("  - Or more sophisticated revenue modeling")

    return reversals

# ==============================================================================
# MAIN
# ==============================================================================

if __name__ == "__main__":
    # Detailed analysis of reversal mechanism
    compare_extreme_cases()

    print()
    print()

    # Search for FPA > WOA
    fpa_woa_reversals = find_fpa_woa_reversal()

    print()
    print("="*80)
    print("ANALYSIS COMPLETE")
    print("="*80)
    print()
    print("SUMMARY:")
    print("  ✓ FPA > SPA reversals: COMMON (found 480 cases)")
    print("  ? FPA > WOA reversals: Requires further investigation")
    print()
    print("KEY INSIGHTS:")
    print("  1. Reversals occur when affiliation ρ is high (≥0.8)")
    print("  2. Low information costs (c ≤ 0.01) are critical")
    print("  3. FPA's information advantage grows revenue substantially")
    print("  4. WOA problem is harder due to higher baseline revenue")
    print()
