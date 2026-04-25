---
iteration: 19
date: "2026-04-25"
type: subtractive
verdict: adopted
files_changed:
  - godot/sim/genome.gd (DEFAULT_BOSS_SCALING + comment)
  - godot/core/data/enemy_db.gd (use cp_mult, drop atk_mult fallback + dead hp_mult)
  - godot/sim/autoresearch.py (validate + mutate cp_mult only)
  - godot/sim/best_genome.json (rename keys)
  - godot/sim/default_genome.json (rename keys)
refs:
  - "handoff: docs/design/cp-formula-application-handoff.md (evaluator §1.2-1.5x boss difficulty criterion)"
  - "iter 17: cp-formula-applied"
  - "iter 18: cp-formula-followup-cleanup"
---

## Iteration 19: boss_scaling — atk_mult/hp_mult → cp_mult rename

### Problem

`boss_scaling = {atk_mult: 1.3, hp_mult: 1.3}` had a naming/semantics drift:
- Variable names suggested per-unit stat boost (atk × 1.3, hp × 1.3)
- Implementation in `enemy_db.gd:46-47` only used `atk_mult` and applied
  it to `target_cp` (count multiplier, not per-unit boost)
- `hp_mult` was dead code (never read)

User clarified intent: boss difficulty is **CP-level scaling** (more total
enemy CP), not per-unit stat boost. The implementation was correct in spirit
but variable names were misleading.

### Change

Subtractive — rename to match implementation:
- `boss_scaling`: `{atk_mult: 1.3, hp_mult: 1.3}` → `{cp_mult: 1.3}`
- `enemy_db.gd`: read `cp_mult` (was `atk_mult`)
- `autoresearch.py`: validate + mutate `cp_mult` only
- JSON files: rename keys, drop `hp_mult`

No behavior change — same `target_cp *= 1.3` math, cleaner naming.

### Verification

- GUT 903/903 pass
- `autoresearch.validate_genome(best_genome)` returns OK
- `mutate_boss_scaling` produces `cp_mult` ∈ [1.0, 2.0]

### Outcome — adopted

Naming now matches semantics. Future readers won't be misled into thinking
per-unit ATK/HP scaling is in effect.

### Lessons

- When variable names and implementation diverge, the cleanup direction
  depends on user intent. Here: keep impl, rename vars (cheaper than
  rewriting impl + recalibrating).
- `hp_mult` was dead for an unknown duration — silent drift. The Tier 0
  protect-files hook would prevent unauthorized changes, but doesn't catch
  internal naming/semantic mismatch. P5 ladder doesn't help here — needs
  type-checked schema (e.g., explicit named struct) or a unit test on the
  field-name-vs-usage pair.
