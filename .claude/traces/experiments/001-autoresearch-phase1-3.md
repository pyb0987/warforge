---
name: autoresearch-session-001
verdict: partial_success
score_before: 0.4142
score_after: 0.4945
axes_improved: [emotional_arc, tipping_point_quality, activation_utilization]
axes_stuck: [win_rate_band]
date: 2026-04-04
---

# Autoresearch Session 001: Phase 1-3

## Setup
- AI: v5 (per-strategy config, genome signal propagation, continuous pressure)
- Evaluator: v7 (8-axis, immutable)
- Iterations: 30 total (Phase1: 20, Phase2: 10, Phase3: 10)
- ADOPTs: 11/30

## Results
- **0.4142 → 0.4945 (+19.4%)**
- emotional_arc: 0.44 → 0.69 (biggest improvement)
- tipping_point: 0.13 → 0.37
- activation_utilization: 0.87 → 0.97
- win_rate_band: 0.00 → 0.00 (stuck)

## Key Finding: win_rate_band Gradient Dead Zone

**Problem**: win_rate_band = clamp(1 - |overall_wr - 0.70| / 0.10, 0, 1) × (1 - σ_penalty × 0.5).
When overall per-round WR is outside 60-80%, band_score = 0 regardless of distance.
This creates a gradient-free zone where the optimizer has no incentive to move WR toward the target.

**Consequence**: Optimizer maximized other axes (emotional_arc=0.15w, tipping_point=0.17w)
by making enemies harder → more defeats → better "tipping point" and "emotional arc" scores.
But this crashed WRs to 0% for 5/7 strategies.

**CP curve diverged from gameplay**: Best genome has enemies 13-68% harder than default.
This produces good evaluator scores for arc/tipping but terrible actual gameplay.

## Axis-by-axis Genome Sensitivity
| Phase | Axis | ADOPTs | Response |
|-------|------|--------|----------|
| 1 (CP+econ) | emotional_arc | 7/20 | Strong — CP curve directly controls difficulty progression |
| 1 (CP+econ) | tipping_point | 7/20 | Strong — harder enemies create more comeback moments |
| 2 (shop tiers) | activation_util | 4/10 | Moderate — tier weights affect card quality/quantity |
| 3 (enemy comp) | — | 0/10 | None — already saturated from Phase 1 |
| all | win_rate_band | 0/30 | Dead — no gradient below 60% WR |

## Diagnosis: Evaluator Design Issue
The evaluator's win_rate_band cliff at 60% creates a multi-objective conflict:
- emotional_arc and tipping_point reward hard games (more defeats)
- win_rate_band rewards balanced games (60-80% WR)
- When win_rate_band is stuck at 0, the optimizer freely maximizes arc/tipping

## Recommended Fix
Option A: Add gradient to win_rate_band below 60% (evaluator change — currently immutable)
Option B: Two-phase optimization: first constrain CP curve to achieve 60-80% WR, then optimize other axes
Option C: Penalty term for extreme strategy WR imbalance (e.g., any strategy at 0% → score penalty)
