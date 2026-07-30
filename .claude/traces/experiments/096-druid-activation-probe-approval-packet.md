# Experiment 096 - Druid Activation Probe Approval Packet

Date: 2026-07-30
Status: READY - awaits fresh protected-edit approval

## Request

Approve a narrow protected probe that edits only:

- `godot/sim/ai_agent.gd`
- `godot/tests/test_ai_agent.gd`

Do not edit card YAML, generated card DB, combat/runtime systems, difficulty
values, economy values, progression thresholds, or other `godot/sim/**` files.

## Why This Probe

H98 found that the H94 same-seed soft-Druid baseline has a real R8-R12
activation tail:

- 42/60 runs bought a Druid payoff.
- 63 payoff copies were bought.
- 46 copies became active after buy.
- 17 copies never became active after buy.
- 29 inactive payoff frames occurred across 20 runs.
- 23 inactive frames were bench gaps.
- 19 inactive frames had no same-round promotion decision.
- Promotion skips were mostly `protect_path_focus` and
  `path_focus_value_gap`.
- `druid_world_tree` carried the largest gap: 20 inactive frames, 16 bench gaps,
  and 16 promotion skips.

H78 did not solve this:

- H78 reduced path-lag holds but kept inactive frames flat at 29.
- H78 clears fell from 9/60 to 8/60.
- H74 verdict remained `REJECT_FLAT_OR_NOISY`.

## Hypothesis

Soft-Druid sometimes keeps a missing payoff on the bench because
`_find_path_focus_replacement()` skips all current focus cards before checking
whether the active board has duplicate copies.

This conflicts with the later protection rule: `_should_skip_path_focus_swap()`
already allows replacing a duplicate active focus card, but the replacement
finder may never choose that duplicate as an outgoing candidate.

Allowing duplicate current-focus copies to be replacement candidates should
reduce Druid payoff bench gaps without broadly weakening path-focus protection.

## Proposed Patch Shape

In `godot/sim/ai_agent.gd`:

1. Add a small helper, for example:

```gdscript
func _is_replaceable_path_focus_duplicate(
        state: GameState, card_id: String, current_cards: Array) -> bool:
    return card_id in current_cards and _active_card_count(state, card_id) > 1
```

2. Update `_find_path_focus_replacement()`:

Current behavior:

```gdscript
if card.get_base_id() in current_cards:
    continue
if _H.count_star1_copies(state, card.get_base_id()) >= 2:
    continue
```

Probe behavior:

```gdscript
var card_id := card.get_base_id()
if card_id in current_cards and not _is_replaceable_path_focus_duplicate(
        state, card_id, current_cards):
    continue
if not (card_id in current_cards) and _H.count_star1_copies(state, card_id) >= 2:
    continue
```

This keeps single active focus cards protected, but lets a duplicate active
focus copy make room for a different missing current payoff.

3. Optionally add trace-only `promote_skip` reasons when
`_promote_path_focus_bench()` returns after finding a bench current card but no
replacement candidate. This is helpful but secondary; the behavior probe above
is the core test.

## Focused Tests

Add focused tests in `godot/tests/test_ai_agent.gd`:

1. Duplicate focus replacement:
   - Setup soft-Druid at R9/R10 with `dr_spore_cloud` duplicated on the active
     board and `dr_wrath` on the bench.
   - Call `_promote_path_focus_bench()`.
   - Assert `dr_wrath` becomes active, one `dr_spore_cloud` remains active, and
     the bench copy leaves the bench.

2. Single focus protection:
   - Setup soft-Druid with only one active `dr_spore_cloud`, no active
     `dr_wrath`, and `dr_wrath` on the bench.
   - If no non-focus replacement exists, assert the single active
     `dr_spore_cloud` is not replaced.

3. Non-Druid isolation:
   - Existing non-Druid promotion behavior stays unchanged.

4. Optional trace test:
   - With tracer enabled, a duplicate-focus replacement emits `promote` with
     reason `path_focus_activation`.

## Same-Seed Evaluation

After focused tests pass, run the same H94 seed:

```bash
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h99_activation60 \
  godot --headless --log-file /private/tmp/warforge_h99_activation60.log \
  --path godot/ -s tools/self_play_observer.gd -- \
  --runs=60 --strategies=soft_druid --difficulty=1 \
  --commander=gambler --talisman=flint \
  --seed=2026072901 \
  --out=/private/tmp/warforge_h99_activation60.json \
  --trace-dir=/private/tmp/warforge_h99_activation60_traces \
  --quiet-progress=true
```

Then run:

```bash
python3 scripts/summarize_self_play_report.py \
  --report=/private/tmp/warforge_h99_activation60.json \
  --out=/private/tmp/warforge_h99_activation60_summary.md

python3 scripts/analyze_ai_trace.py \
  /private/tmp/warforge_h99_activation60_traces \
  --strategy=soft_druid \
  --druid-active-ledger \
  --druid-run-phase \
  --druid-activation-audit \
  --druid-path-lag-audit \
  --druid-compare-baseline=/private/tmp/warforge_h94_druid60_traces \
  > /private/tmp/warforge_h99_activation60_vs_h94.txt
```

## Adoption Gate

Same-seed candidate may be nominated only if all are true:

- Clears do not fall below H94's 9/60.
- Avg final HP does not fall by 0.5 or more.
- H74 Druid probe screen is not `REJECT_FLAT_OR_NOISY`.
- H98 activation audit improves at least one direct activation signal:
  - inactive frames decrease by at least 6, or
  - bench gaps decrease by at least 5, or
  - never-active-after-buy copies decrease by at least 4.
- Run-phase does not increase `active_too_late` or `bought_not_active`.
- Active-loss survivor margin does not worsen.
- Final board theme ratio does not drop below baseline.

Same-seed candidate must be rejected if any are true:

- Clears fall.
- Avg final HP falls by 0.5 or more.
- H74 screen is `REJECT_FLAT_OR_NOISY`.
- Activation gaps improve locally but active combat/survival worsens.
- Promotion starts replacing single active focus cards or Druid identity
  foundation cards in focused tests.

If same-seed is nominated, confirm on a disjoint 60-run seed before adoption.

## Rollback Rule

If the same-seed screen fails, revert only the H99-owned edits in:

- `godot/sim/ai_agent.gd`
- `godot/tests/test_ai_agent.gd`

Then rerun focused AI tests and keep only the trace/plan evidence.

## Boundary

This packet is not approval by itself. It is a prepared request for the next
protected edit. Fresh user approval is required before making the proposed
changes.
