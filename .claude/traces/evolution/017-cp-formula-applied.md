---
iteration: 17
date: "2026-04-25"
type: additive
verdict: adopted
files_changed:
  - scripts/analyze_card_cp.py (OLD `n × atk/as × hp` → import preset_generator SSoT)
  - scripts/preset_generator.py (extract `cp_from_stats` helper)
  - godot/sim/preset_generator.gd (mirror cp_from_stats)
  - godot/core/card_instance.gd (5 CP usages → PresetGen.cp_from_stats)
  - godot/tests/test_predator_system.gd (2 tests robust to NEW ranking)
  - godot/sim/best_genome.json (target_cp_per_round recalibrated)
  - godot/sim/baseline.json (regenerated)
refs:
  - "handoff: docs/design/cp-formula-application-handoff.md"
  - "trace 002: experiments/002-cp-formula-theme-system.md (formula derivation)"
  - "commit ee4bc61 — analyze_card_cp.py SSoT"
  - "commit 95203a5 — card_instance.gd SSoT"
---

## Iteration 17: CP Formula SSoT — applied across codebase

### Problem

Phase 2 (commits `40e64ef` + `8e84d25`) confirmed the new CP formula:

```
CP = 19.35 + (atk/as)^0.249 × hp^0.905
```

via 5 independent autoresearch lines (2026-04-24 trace 002). Canonical
location: `preset_generator.{gd,py}::unit_intrinsic_cp`. But 3 separate CP
formulas remained scattered across runtime + analysis code:

1. `scripts/analyze_card_cp.py`: `n × atk/as × hp` (OLD)
2. `godot/core/card_instance.gd::get_total_cp()`: same OLD formula
3. `godot/core/card_instance.gd` 4 gameplay-ranking methods: same OLD
4. `godot/sim/headless_runner.gd::card_cps`: `atk + hp` (heuristic)
5. `godot/sim/ai_board_evaluator.gd::card_board_value`: `atk + hp` (heuristic)

`target_cp_per_round` in `best_genome.json` was calibrated against the OLD
preset CP formula → now mis-scaled vs new formula.

### Change

Additive migration (P-additive first):

**SSoT helper** (preset_generator.gd + .py):
```gdscript
static func cp_from_stats(atk, as, hp, stat_mult=1.0) -> float:
    var dps = atk / max(as, 0.01)
    return (BASE + dps^ALPHA × hp^BETA) × stat_mult²
```

**Migrated** (5 places in card_instance.gd):
- `get_total_cp` (UI/logger display)
- `breed_strongest`, `remove_weakest_unit`, `remove_weakest`, `metamorphosis`
  (gameplay ranking — "strongest"/"weakest" decisions)

**Left unchanged** (intentionally — heuristics, not "the CP"):
- `headless_runner.card_cps` (`atk + hp`) — used by evaluator's Gini and
  total-CP metrics. Scale-invariant for those purposes.
- `ai_board_evaluator.card_board_value` — log-scaled internal AI heuristic.

**Recalibrated**:
- `target_cp_per_round`: ratios 0.53–0.75× of old (NEW formula yields
  smaller absolute CP values). Calibration: best iter 4, max err 7.4pp.
  Final 3-iter moving avg: early 3.5pp ✓, mid 8.0pp (boundary), late 9.2pp ✓.
- `baseline.json`: weighted_score 0.5502 → 0.5456.

### Behavioral side-effect — gameplay ranking

NEW formula ranks high-HP units higher than OLD:

|         | atk | as  | hp  | OLD `(atk/as)×hp` | NEW `BASE + (atk/as)^0.249 × hp^0.905` |
|---------|-----|-----|-----|-------------------|----------------------------------------|
| pr_apex | 8   | 1.0 | 30  | 240               | 55.8                                   |
| pr_guardian | 6 | 1.5 | 45 | 180               | 63.6                                   |

So `pr_apex_hunt`'s `metamorphosis(consume=2)` now consumes 2× pr_apex
(weakest under NEW) and adds 1× pr_guardian (strongest), producing a
different post-meta composition. Two `test_predator_system` tests asserted
`get_total_atk() > before` — fragile under composition shift. Updated to
verify the buff side-effect directly via `stack["temp_atk"] > 0`.

### Verification

- GUT: 903/903 pass.
- Calibration: per-round WR within target_wr_curve tolerances
  (early ✓, mid boundary, late ✓).
- Boss balance (210 runs, 30/strategy):
  - R4: 96.2% (target 94.6%) ✓
  - R8: 92.1% (target 88.9%) ✓
  - R12: 78.2% (target 84.1%) — within noise (n=179, SE~3pp)
  - R15: 71.4% (target 65.4%) — within noise (n=119, SE~4pp)

### Outcome — adopted

CP SSoT achieved across 3 layers (Python analysis, Godot runtime, target
calibration). Remaining heuristics (`card_cps`, `ai_board_evaluator`) are
intentionally separate concerns and documented as such here.

### Lessons

- "Single source of truth" is a behavioral claim, not just a code claim:
  changing the formula necessarily changed gameplay (ranking) and tests.
  Tests that asserted total_atk > before were implicitly OLD-formula-bound.
  Robust replacement: assert the **side-effect** (buff applied), not the
  derived state (total_atk delta).
- `batch_runner.gd` writes JSON only to stdout (mixed with engine messages).
  Need regex-extract pattern (same as `calibrate_target_cp.py:run_batch`)
  to write `baseline.json` cleanly.
- Migration scope decisions are best made before, not during. Initial plan
  (UI-only) shifted to all-5-places after user confirmation; testing then
  surfaced 2 fragile assertions. Future: enumerate behavioral implications
  upfront.
