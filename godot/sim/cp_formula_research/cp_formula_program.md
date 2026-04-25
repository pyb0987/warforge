# Autoresearch Program — CP Formula Tuning

> This is a **separate autoresearch episode** from `godot/sim/program.md`
> (which targets strategy diversity). This episode explores CP formula
> constants in `preset_generator.gd` to maximize preset parity.

## Identity

You are an autonomous researcher exploring the 4 CP formula constants.
Operate autonomously. Stop at 100 experiments or axis exhaustion.

## Objective

Maximize `score` from `parity_evaluator.py`.

**Score**: Gaussian-weighted mean of 36 off-diagonal cells in preset parity matrix.
- wr=50% → 1.0, wr=30%/70% → 0.61, wr=10%/90% → 0.14
- + 0.05 × (in_band_count / 36) tie-breaker

Current baseline is read from `best_score.txt` (SSOT, written by evaluator).

## What You Can Modify (Mutable Genome)

Only the 4 constants in `godot/sim/preset_generator.gd`:

```
const K_RANGE        // bounds [5.0, 50.0]
const MS_REF         // bounds [1.0, 4.0]
const K_DENSITY      // bounds [0.0, 0.3]
const K_LANCHESTER   // bounds [0.0, 1.0]
```

You must also mirror the same change in `scripts/preset_generator.py`
(the canonical "keep in sync" Python mirror).

## What You CANNOT Modify (Immutable)

- `godot/sim/cp_formula_research/parity_evaluator.py` — Tier 0 fixed evaluator
- `godot/sim/cp_formula_research/baseline_parity.json` — reference snapshot
- `godot/sim/cp_formula_research/best_score.txt` — machine-managed by evaluator
- `godot/sim/preset_parity_runner.gd` — evaluator dependency
- `godot/sim/genome.gd`, `godot/core/data/enemy_db.gd` — out-of-scope
- `PRESET_RECIPES` (role weights in preset_generator.gd) — out-of-scope (handoff §7.5)

## Experiment Loop

1. Read `experiments.jsonl` → resume from n+1
2. Formulate a 1-line hypothesis (must not duplicate Rejection History)
3. Edit the 4 constants in both preset_generator.gd AND preset_generator.py
4. `git commit -m "experiment: <hypothesis>"`
5. Run `python3 godot/sim/cp_formula_research/parity_evaluator.py`
6. Parse JSON verdict
7. `ADOPT` → keep + append to experiments.jsonl
   `REJECT_THRESHOLD` / `REJECT_GUARD` → `git reset --hard HEAD~1` + append
8. Repeat

## Adoption Criteria

- `metric >= baseline + 0.005` (from evaluator)
- Guard: no tier has ≥10/12 extreme cells (prevents catastrophic regressions)
- Guards reject via `verdict: REJECT_GUARD`

## Termination

- `n >= 100` experiments
- `consecutive_rejects >= 20` → blocked, escalate + handoff
- Score plateau (5 consecutive ADOPTs with <0.01 gain) → axis exhaustion, handoff

## Structural Constraints (NEVER violate)

- Bounds above are hard limits (evaluator does not enforce; agent must)
- `K_DENSITY=0 AND K_LANCHESTER=0` is the "no-bonus" degenerate case — allowed but expected to be baseline-tier
- Never modify `PRESET_RECIPES` — scope creep into Option A territory
- Never modify evaluator or parity_runner

## Hypotheses to Explore (Unexplored Hints)

Based on 3 manual iterations (see traces/failures/ and handoff discussion):

- **Lanchester dial-down**: K_LANCHESTER in [0.10, 0.30] — iter3 K=0.5 was too aggressive (sniper over-reduced)
- **Density + mild Lanchester hybrid**: K_DENSITY ≈ 0.08-0.12 combined with K_LANCHESTER ≈ 0.15-0.25
- **Range value re-tuning**: K_RANGE in [10, 25] — lower = more sniper intrinsic CP → fewer snipers in preset
- **MS normalization**: MS_REF in [1.0, 3.0] — higher MS_REF penalizes slow units more (heavy↑ units)

Expected hard ceiling: heavy preset vs everyone likely stays 0-10% due to ms=1 mobility
limitation (formula-independent). Aim for ~20/36 in-band as feasible upper bound.

## Rejection History — EXHAUSTED AXES (DO NOT REVISIT)

(Initial — grows over time)

- `K_LANCHESTER=0.5, K_DENSITY=0.0` (iter3) — sniper over-reduced, tier1/2 all 0-100% extreme (score_raw ≈ 0.15)
- `K_DENSITY=0.15, K_LANCHESTER=0.0` (iter1) — tier1 partial success only, tier2/3 extreme (score_raw ≈ 0.20)
- `K_DENSITY=0.08, K_LANCHESTER=0.0` (iter2) — tier2/3 partial success only, tier1 extreme (score_raw ≈ 0.22)

## Session Handoff Protocol

On termination, update `.claude/handoff.md`:
- Status: in_progress | blocked | paused | completed
- Last completed experiment n and verdict
- Current best constants and score (baseline: see best_score.txt)
- Remaining axes / suggested next hypothesis

## Logging Format (experiments.jsonl)

```json
{"ts": "2026-04-24T11:00:00", "n": 1, "hypothesis": "lanchester 0.2 + density 0.1",
 "constants": {"K_RANGE": 20.0, "MS_REF": 2.0, "K_DENSITY": 0.1, "K_LANCHESTER": 0.2},
 "metric": 0.48, "score_raw": 0.45, "improvement": 0.03,
 "in_band_count": 18, "extreme_count": 12, "verdict": "ADOPT",
 "guards": {"constants_parsed": "PASS", "parity_run": "PASS", "no_catastrophic_tier": "PASS"},
 "sha": "abc1234", "reverted": false}
```
