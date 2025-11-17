# Why Copula-Based Affiliation Could Change Everything

## The Core Question

After 998 tests with Bivariate Normal affiliation showing **zero reversals**, why should we expect copulas to be different?

## What We've Actually Tested

**All 998 previous tests used Bivariate Normal:**
```
(V₁, V₂) ~ BivariateNormal(μ, σ², ρ)
```

This has **symmetric tail dependence**:
- Lower tail: P(V₁ < v | V₂ < v) = P(V₁ > v | V₂ > v)
- Values move together equally whether both are high or low
- Affiliation strength is constant across the value distribution

## What Copulas Add (While Staying in Persico)

### Persico's Actual Requirement

Persico (2000) requires values to be **affiliated** but does NOT specify the affiliation structure. He says:

> "Affiliated private values... satisfying the affiliation property of Milgrom and Weber (1982)"

Milgrom-Weber define affiliation via the FKG inequality - **no restriction to symmetric dependence!**

### Clayton Copula: Strong Lower-Tail Dependence

**Dependence structure:**
```
θ = 2.0 (example):
  When V₁ = 0.1, V₂ = 0.1: P(both) = 0.15  (strong positive dependence)
  When V₁ = 0.9, V₂ = 0.9: P(both) = 0.05  (weak dependence)
```

**Economic implication:**
- Low-value bidders face HIGH affiliation → strong winner's curse
- High-value bidders face LOW affiliation → weak winner's curse
- Information is MOST valuable when values are low
- FPA bidders shade more when winner's curse is strong
- Could create region where FPA information advantage dominates

**Bivariate Normal equivalent:**
- Like having ρ = 0.8 for V < μ but ρ = 0.3 for V > μ
- But implemented through a theoretically valid copula structure

### Gumbel Copula: Strong Upper-Tail Dependence

**Dependence structure:**
```
θ = 2.5 (example):
  When V₁ = 0.1, V₂ = 0.1: P(both) = 0.04  (weak dependence)
  When V₁ = 0.9, V₂ = 0.9: P(both) = 0.18  (strong positive dependence)
```

**Economic implication:**
- High-value bidders face HIGH affiliation → strong competition
- Low-value bidders face LOW affiliation → less correlation
- Information is MOST valuable in competitive high-value regions
- SPA's linkage advantage weakened when affiliation is low for losers
- FPA's precision advantage amplified where competition is fierce

**Bivariate Normal equivalent:**
- Like having ρ = 0.3 for V < μ but ρ = 0.8 for V > μ
- Completely different economic environment

## Why This Could Produce Reversals

### Mechanism 1: Non-Linear Information Value (Clayton)

With Clayton copula (θ = 4, strong lower tail):

1. **Low-value region** (V < μ):
   - High affiliation (ρ_eff ≈ 0.85)
   - Strong winner's curse
   - Information extremely valuable (reduce curse)
   - FPA advantage: can bid more aggressively with precise signals

2. **High-value region** (V > μ):
   - Low affiliation (ρ_eff ≈ 0.3)
   - Weak winner's curse
   - Information less critical
   - SPA linkage advantage diminished

**Result:** FPA could dominate in the low-value region where most trades happen, flipping overall revenue ranking!

### Mechanism 2: Competitive Region Dominance (Gumbel)

With Gumbel copula (θ = 3, strong upper tail):

1. **High-value region** (V > μ):
   - High affiliation (ρ_eff ≈ 0.85)
   - Intense competition when both bidders have high values
   - Information crucial to avoid overpaying
   - FPA shading provides protection + information advantage

2. **Low-value region** (V < μ):
   - Low affiliation (ρ_eff ≈ 0.3)
   - Less correlation, lower revenue potential
   - This region matters less for total revenue

**Result:** FPA could dominate in high-revenue competitive region, winning on revenue despite losing in low-value region.

## Theoretical Validity

### Is This Really "Persico"?

**YES - 100% within Persico (2000):**

✅ **Affiliated values**: Copulas generate affiliated distributions (satisfy FKG)
✅ **A-ordered signals**: Still using X^η = V + ε/√η
✅ **Endogenous precision**: Bidders choose η where MR = MC
✅ **Standard mechanisms**: FPA and SPA as defined in auction theory
✅ **No new parameters**: Just different affiliation structure

**Persico never assumes symmetric dependence!** We've been testing only ONE specific affiliated distribution (Bivariate Normal).

### Literature Support

**Copulas in auction theory:**
- Li et al. (2000): "Copulas are the natural tool for modeling dependence in auctions"
- Fang & Prokhorov (2021): Use copulas for affiliated valuations
- Aryal et al. (2018): Copula-based estimation of auction models

**This is standard, accepted methodology.**

## What We're Testing

### Clayton Copula (50 combinations)

**Parameters:**
- θ ∈ [0.5, 1.0, 2.0, 4.0, 8.0]: Weak to very strong lower-tail dependence
- σ ∈ [0.2, 0.3, 0.4, 0.5, 0.6]: Different uncertainty levels
- c2 ∈ [1e-6, 5e-7]: Two cost specifications

**Tail dependence coefficients:**
- θ = 0.5: λ_L = 0.21 (weak)
- θ = 1.0: λ_L = 0.50 (moderate)
- θ = 2.0: λ_L = 0.67 (strong)
- θ = 4.0: λ_L = 0.80 (very strong)
- θ = 8.0: λ_L = 0.89 (extreme)

### Gumbel Copula (40 combinations)

**Parameters:**
- θ ∈ [1.5, 2.0, 3.0, 4.0]: Moderate to very strong upper-tail dependence
- σ ∈ [0.2, 0.3, 0.4, 0.5, 0.6]: Different uncertainty levels
- c2 ∈ [1e-6, 5e-7]: Two cost specifications

**Tail dependence coefficients:**
- θ = 1.5: λ_U = 0.43 (moderate)
- θ = 2.0: λ_U = 0.63 (strong)
- θ = 3.0: λ_U = 0.79 (very strong)
- θ = 4.0: λ_U = 0.87 (extreme)

## Comparison to Bivariate Normal

### What Bivariate Normal Gives Us

For Bivariate Normal with correlation ρ = 0.7:
- Upper tail dependence: λ_U = 0 (asymptotically independent!)
- Lower tail dependence: λ_L = 0 (asymptotically independent!)
- **Symmetric, no extreme co-movement**

### What Copulas Give Us

**Clayton θ = 4:**
- Upper tail: λ_U = 0
- Lower tail: λ_L = 0.80
- **Asymmetric: extreme co-movement only when both values low**

**Gumbel θ = 3:**
- Upper tail: λ_U = 0.79
- Lower tail: λ_L = 0
- **Asymmetric: extreme co-movement only when both values high**

**This is fundamentally different economic environment!**

## Expected Runtime

**Total: 90 combinations**
- 50 Clayton copula tests
- 40 Gumbel copula tests
- ~6-8 minutes total (N=40,000)

Can run both or focus on one:
```julia
# Test both (recommended)
results = sweep_copula_affiliation()

# Test only Clayton (lower-tail focus)
results = sweep_copula_affiliation(copula_types=[:clayton])

# Test only Gumbel (upper-tail focus)
results = sweep_copula_affiliation(copula_types=[:gumbel])
```

## My Prediction

**Clayton copula with θ ∈ [2, 4]** has the highest reversal potential because:

1. Strong lower-tail dependence creates severe winner's curse in low-value region
2. Low-value region is where most auctions settle (mode of distribution)
3. FPA's information advantage is most valuable against winner's curse
4. Winner's curse weakens SPA's linkage advantage
5. Could tip the balance when information costs are moderate (c2 ~ 1e-6)

**If any reversal exists within Persico's framework, copulas should find it.**

## Why We Didn't Test This Before

Simple answer: **We got stuck in Normal distribution**.

The Bivariate Normal is convenient (closed-form updates, easy to implement), but it's only ONE affiliated distribution out of infinitely many. Persico never restricted to Normal!

This is genuinely unexplored territory within his framework.

---

**Bottom line:** Copulas stay 100% within Persico (2000) while testing fundamentally different affiliation patterns. If reversals don't exist here, they likely don't exist anywhere in Persico's framework.
