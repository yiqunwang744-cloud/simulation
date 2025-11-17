# Common Value Extension - Usage Guide

## Overview

The common value extension adds a component **C** (unknown to bidders) that affects both players equally. This creates a **winner's curse** that could potentially reverse revenue rankings.

## Model Structure

**Utility function:**
```
u_i(V_i, V_j, C) = V_i + α·V_j + β·C
```

where:
- `V_i, V_j`: Private value components (affiliated with correlation ρ)
- `C`: Common value component (unknown to bidders)
- `α`: Interdependence weight (how much opponent's value matters)
- `β`: Common value weight (how much common value matters)

**Information structure:**
- Each bidder observes: `X_i^η = V_i + ε_i/√η` (noisy private signal)
- Each bidder observes: `Y_c^η_c = C + δ/√η_c` (noisy common signal)

**Equilibrium:**
Bidders choose precision levels `(η*, η_c*)` satisfying:
- `MR_private(η*, η_c*) = MC_private(η*)`
- `MR_common(η*, η_c*) = MC_common(η_c*)`

## Why This Might Produce Reversals

### Winner's Curse Mechanism

1. **Common values amplify winner's curse**: The winning bidder likely overestimated C
2. **FPA bidders shade more**: Need to compensate for winner's curse
3. **Information is more valuable in FPA**: Helps reduce winner's curse impact
4. **Could flip revenue ranking** when β is high (common value dominates)

### Theoretical Prediction

Reversals most likely when:
- **High β** (β ≥ 0.5): Common value component dominates private values
- **High σ_c** (σ_c ≥ 0.4): Large uncertainty about common value
- **Moderate α** (α ~ 0.3): Some interdependence but not extreme
- **Moderate ρ** (ρ ~ 0.3-0.5): Private values not too highly correlated

This creates an environment where FPA's information advantage outweighs its bid-shading disadvantage!

## Usage

### Quick Search (Default Parameters)

```julia
include("common_value_extension.jl")

# Search 180 combinations (5×3×3×4×3)
results = search_common_value_reversals()
```

**Default ranges:**
- β (common weight): [0.4, 0.5, 0.6, 0.7, 0.8]
- α (interdependence): [0.2, 0.3, 0.4]
- ρ (private correlation): [0.3, 0.4, 0.5]
- σ_c (common uncertainty): [0.3, 0.4, 0.5, 0.6]
- σ (private uncertainty): [0.3, 0.4, 0.5]

**Runtime:** ~9-12 minutes with N=40000

### Focused Search (High β Region)

```julia
# Focus on high common value weight (most promising)
results = search_common_value_reversals(
    β_range = [0.6, 0.65, 0.7, 0.75, 0.8],
    α_range = [0.25, 0.3, 0.35],
    ρ_range = [0.35, 0.4, 0.45],
    σ_c_range = [0.4, 0.5, 0.6],
    σ_range = [0.3, 0.4],
    N = 60000,  # Higher precision
    verbose = false
)
# Tests 5×3×3×3×2 = 270 combinations (~20 minutes)
```

### Test Specific Parameters

```julia
# High common value weight scenario
m = make_cv_model(
    β = 0.7,      # 70% weight on common value!
    α = 0.3,      # Moderate interdependence
    ρ = 0.4,      # Moderate correlation
    σ_c = 0.5,    # High common value uncertainty
    σ = 0.4       # Moderate private value uncertainty
)

result = analyze_cv_model(m; N=80000, verbose=true)

if result.reversal
    println("REVERSAL FOUND!")
    println("FPA: η*=$(result.ηF), η_c*=$(result.ηF_c)")
    println("SPA: η*=$(result.ηS), η_c*=$(result.ηS_c)")
    println("Ratio: $(result.ratio)")
end
```

### Custom Parameter Sweep

```julia
# Test extreme common value dominance
results = search_common_value_reversals(
    β_range = [0.7, 0.75, 0.8, 0.85, 0.9],  # Very high β!
    α_range = [0.2, 0.3],
    ρ_range = [0.3, 0.4],
    σ_c_range = [0.5, 0.6, 0.7],            # Very high uncertainty
    σ_range = [0.3, 0.4],
    N = 50000
)
```

## Interpreting Results

### Valid Equilibrium

```
✓ Both equilibria valid
  FPA: η*=2.345, η_c*=1.678
  SPA: η*=1.234, η_c*=0.987
```

Both mechanisms found equilibria where MR = MC for both precision choices.

### Reversal Detection

```
R_FPA/R_SPA = 1.0427
🎉 REVERSAL FOUND!
```

FPA revenue is 4.27% higher than SPA - this is what we're looking for!

### No Reversal

```
R_FPA/R_SPA = 0.9654
No reversal
```

SPA still dominates (revenue 3.6% higher).

## Expected Outcomes

### If Reversals Found

This would be a **major theoretical contribution** because:
1. First documented reversal of Krishna-Morgan ranking with endogenous information
2. Identifies precise mechanism: winner's curse + information value
3. Quantifies exact parameter regions where FPA dominates
4. Publication-worthy in top economics journals

### If No Reversals Found

Still valuable as it shows:
1. Krishna-Morgan ranking is **extremely robust**
2. Even winner's curse + common values can't reverse it
3. Suggests fundamental structural advantage of SPA
4. Next step: Try asymmetric costs or reserve prices

## Computational Cost

| Configuration | Combinations | Time (est.) |
|--------------|--------------|-------------|
| Default | 180 | ~10 min |
| Focused high β | 270 | ~20 min |
| Extreme sweep | 500 | ~40 min |

All estimates assume N=40000, single-threaded execution.

## Technical Details

### Joint Equilibrium Solver

Uses alternating optimization:
1. Fix η_c, solve for η* where MR_η = MC_η
2. Fix η, solve for η_c* where MR_η_c = MC_η_c
3. Repeat until both converge (|gap| < 10⁻³)

### Validation Criteria

Both equilibria must satisfy:
- `converged = true` (found within max_iter)
- `|gap_η| < 10⁻³` (MR ≈ MC for private precision)
- `|gap_η_c| < 10⁻³` (MR ≈ MC for common precision)

### Bidding Functions

**FPA:** Approximates solution to 2D bidding ODE with bid-shading factor ~0.7

**SPA:** Dominant strategy b(x,y) = E[u_i | X_i=x, Y_c=y, tie]

## Troubleshooting

### Many Non-Convergent Equilibria?

Some parameter combinations may not have equilibria where both information choices are interior. This is economically meaningful - not all parameter combinations support stable equilibria.

### All Ratios < 1?

Try:
1. Increase β (common value weight)
2. Increase σ_c (common value uncertainty)
3. Reduce ρ (make private values less correlated)

### Slow Execution?

Reduce search space:
- Fewer β values (focus on β ≥ 0.6)
- Fewer grid points (3 per dimension instead of 4-5)
- Lower N (minimum 30000 for reasonable precision)

## Next Steps

### If Reversals Found:
1. Verify with higher precision (N=100000)
2. Sensitivity analysis around reversal region
3. Document mechanism precisely
4. Write up theoretical explanation

### If No Reversals:
1. Try asymmetric information costs (different c for FPA vs SPA)
2. Add reserve prices
3. Test alternative signal technologies
4. Consider 3+ bidders

## Theoretical Foundations

This extension is grounded in:
- **Milgrom-Weber (1982)**: Interdependent values and common components
- **Krishna (2009)**: Auction theory with affiliated signals
- **Persico (2000)**: Endogenous information acquisition framework
- **Wilson (1977)**: Winner's curse in common value auctions

All theoretical requirements are maintained:
- ✓ Signals remain A-ordered
- ✓ Equilibrium condition MR = MC enforced
- ✓ Proper Bayesian updating
- ✓ Symmetric equilibrium framework

---

**This is the most theoretically promising extension for finding revenue reversals!**

Common values create fundamentally different information incentives that could flip the Krishna-Morgan revenue ranking.
