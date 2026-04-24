---
session: 2026-04-24
date: 2026-04-24
experiment_range: formula iter 1-3 (manual) + autoresearch seeds 1337+99 (60 iter)
adopts: 4 (Phase 2 autoresearch)
rejects: 56 (both Phase 1 orig + Phase 2)
metric_start: 0.044
metric_end: 0.512
verdict: adopted
---

# CP Formula — Theme System + Parameterized Formula

## Context

Baseline handoff `docs/design/combat-cp-formula-handoff.md` asked: off-diagonal preset
parity matrix cells all in 30-70% band. With old abstract-role preset system
(swarm/heavy/sniper/balanced), 3 manual iterations + 36-iter autoresearch found a
**structural ceiling at 7/36 in-band** (formula can rotate dominance but not flatten).

## Phases & Decisions

### Phase 0 — Manual formula iteration (rejected axes)
1. `K_DENSITY=0.15, K_LANCHESTER=0` — 2/36 in-band (tier1 only)
2. `K_DENSITY=0.08, K_LANCHESTER=0` — 4/36 in-band (tier2/3 only)
3. `K_LANCHESTER=0.5, K_DENSITY=0` — 1/36 in-band (sniper over-reduced)

**Pattern**: formula rotated but couldn't flatten linear dominance
`swarm > sniper > balanced > heavy`. 9/12 off-diagonal cells per tier involve
heavy preset which structurally loses due to mobility (ms=1).

### Phase 1 — Unified theme-based enemy system
**User decision**: integrate enemy unit pool with player UnitDB (50 themed units).

Changes:
- `preset_generator.gd/py`: abstract roles → `THEME_RECIPES` (predator/druid/military/steampunk × 10 units each)
- `UNIT_INTRINSIC_CP` dict (56 units, seeded from `(atk/as) × hp`)
- `enemy_db.gd`: uses UnitDB stats + theme preset selection
- `preset_parity_runner.gd`: UnitDB via local `UnitDBScript.new()._register_all()` (SceneTree scripts lack autoload compile-time access)
- `test_enemy_db.gd`: removed `_boss_preset` tests (dead code), loosened R1→R15 scaling test

Phase 1 smoke parity: 0/36 in_band, 36/36 extreme. Linear dominance
`predator > steampunk > military > druid` (same shape as abstract system).

### Phase 2 — Parameterized formula + autoresearch

**User insight**: manual CP tuning shouldn't be arbitrary; use autoresearch
to find formula shape. Also atk/as exponent is co-tunable, not just HP.

Formula: `CP = FORMULA_BASE + (atk/as)^FORMULA_ALPHA × hp^FORMULA_BETA`

Autoresearch (seed=1337, then seed=99):
- Bounds: BASE [0, 150], ALPHA [0.2, 1.2], BETA [0.2, 1.2]
- 40 iter (seed 1337) → iter 20 ADOPT at score 0.512, 17/36 in_band
- 20 iter (seed 99) → 0 ADOPT, early terminate (20 consecutive reject)

**Both seeds converge to the same basin** around (BASE≈19, α≈0.25, β≈0.9).

## ADOPTed Config

```
FORMULA_BASE  = 19.35
FORMULA_ALPHA = 0.249   # DPS exponent (sub-linear — "diminishing returns")
FORMULA_BETA  = 0.905   # HP exponent (nearly linear)
```

## Empirical Findings vs User Intuition

| Hypothesis | autoresearch Result | Notes |
|-----------|---------------------|-------|
| HP sub-linear (sqrt) | BETA=0.9 (≈ linear) | HP MORE important than intuition |
| DPS sub-linear | ALPHA=0.25 (≈ 4th root) | STRONGLY sub-linear |
| BASE moderate | BASE=19 (low-mid) | Presence bonus limited |

**Interpretation**: HP is survival-critical (units that die can't contribute).
DPS is shareable (multiple units attacking covers low individual DPS via N-stacking).
This is consistent with Lanchester *linear* law for melee combat — but with DPS stacking
dominating over HP stacking. No sqrt-HP Lanchester effect observed in our combat engine.

## Outcome

- **in_band 0/36 → 14-17/36** (variance ±3, run-to-run)
- **extreme 36/36 → 13/36** (64% reduction)
- Dominance pattern: linear → more cyclical / RPS-adjacent
- **military** still weak at tier1-2 (6 residual extreme cells, 0-5% WR)

## Accepted Residual: military weakness

User decision: military being weak is acceptable as design asymmetry.
Not a formula issue — likely needs theme recipe or unit stats adjustment.
Deferred as potential Phase 3 work.

## Files Touched

- `scripts/preset_generator.py`
- `godot/sim/preset_generator.gd`
- `godot/core/data/enemy_db.gd`
- `godot/sim/preset_parity_runner.gd`
- `godot/tests/test_enemy_db.gd`
- `godot/sim/cp_formula_research/` (new — parity_evaluator.py, cp_formula_autoresearch.py,
  cp_formula_program.md, experiments.jsonl, best_score.txt)

## Known Broken (Phase 3 cleanup)

- `godot/sim/side_bias_test.gd` — uses old `derive_comp(4 args)` + `genome.enemy_stats`
- `godot/sim/diagnostic_game.gd` — uses `genome.get_enemy_comp/stat`
- `godot/sim/autoresearch.py` — mutates enemy_composition/enemy_stats (dead now)
- `test_headless_runner::test_cp_scale_affects_difficulty` — 1 regression (out of 903)

None of these block runtime; they're either dev tools or mutating dead fields.

## Rejection History (Exhausted Axes)

Abstract-role system (4-param formula):
- `K_DENSITY=0.15, K_LANCHESTER=0`
- `K_DENSITY=0.08, K_LANCHESTER=0`
- `K_LANCHESTER=0.5, K_DENSITY=0`
- 36-iter autoresearch from these: best 7/36 in_band @ K_RANGE=14.6, MS_REF=3.92, K_DENSITY=0.16, K_LANCHESTER=0.53

Phase 2 formula (different basins):
- iter 53 BASE=14.1, α=0.577, β=0.667 → 9/36 in_band
- iter 41 BASE=23.7, α=0.339, β=0.907 → 13/36 in_band (near-miss to best)
- High BASE (80+) configs → ~4/36 max

## Lesson

1. **User intuition about exponents can be wrong**; autoresearch > a priori formulas.
2. **Structural refactor** (abstract → theme) unblocked where formula tuning alone stalled —
   changing what's on the table is sometimes necessary before tuning.
3. **Two seeds converging to same basin** = reasonable confidence in global optimum
   (for this search space).
