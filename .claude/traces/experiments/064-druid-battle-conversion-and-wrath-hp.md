# 064 - Druid Battle Conversion and Wrath HP

Date: 2026-07-29
Status: DONE - adopted observability and a Wrath HP implementation fix; Druid floor remains unresolved

## Objective

H67 rejected several Druid AI acquisition and commitment variants. The next question was whether
active Druid payoff battles were failing because the AI did not reach the cards, because payoff
effects were not visible in combat, or because a concrete implementation defect was suppressing
expected combat output.

This slice was intentionally narrow:

- Add trace-level battle-frame observability for Druid focus cards.
- Check whether active payoff battles convert into wins, debuffs, and surviving allies.
- Fix only a concrete defect if the audit found one.
- Do not start another balance probe after this run.

## Battle Conversion Observability

Added `--druid-battle-conversion` to `scripts/analyze_ai_trace.py` with Python test coverage.
The view reports focus-active runs and battles, debuff conversion, active Druid/neutral counts,
tree-counter averages, survivor counts, per-focus-card win rates, and compact loss examples.

Baseline command:

```bash
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h67_druid_base_30_traces --strategy=soft_druid --druid-battle-conversion
```

Baseline result:

- Clears: 4/30, avg final HP -4.20, avg rounds 11.07.
- Focus-active runs: 20/30, with 17 loss runs.
- Focus-active battles: 62 total, 27 won / 35 lost, 43.5% battle win rate.
- Debuff battles: 29; losses after debuff: 19; losses without debuff: 16.
- Losses with enemies surviving: 35.
- Active loss survivors: 0.0 allies, 16.0 enemies.
- Focus card counts: `dr_spore_cloud` 29, `dr_wrath` 42, `dr_world` 19.
- Per-card battle win rates: Spore Cloud 34.5%, Wrath 47.6%, World Tree 63.2%.

Conclusion: Druid does reach active focus cards in many runs, but those battle frames still collapse
with no allied survivors. Spore Cloud in particular applies debuff but does not convert enough fights.

## Defect Found

Card data for `dr_wrath` includes HP scaling:

- star 2 has `hp_pct: 0.6`
- star 3 has `hp_mult: 1.3`

The runtime implementation in `godot/core/druid_system.gd` only applied the attack side. A comment
claimed HP was handled elsewhere, but no combat path applied those values.

Fix:

- Star 2 now applies the additive attack buff plus an HP multiplier of `1.0 + hp_pct`.
- Star 3 now passes both attack and HP multipliers to `temp_mult_buff`.
- Over-cap Wrath still skips both attack and HP buffs.

Focused tests in `godot/tests/test_druid_system.gd` now assert the HP behavior directly.

## Same-Seed Result After Fix

Command:

```bash
HOME=/private/tmp/warforge_godot_home_h68_druid_wrath_hp godot --headless --log-file /private/tmp/warforge_h68_druid_wrath_hp_30.log --path godot/ -s tools/self_play_observer.gd -- --runs=30 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=flint --seed=2026072901 --out=/private/tmp/warforge_h68_druid_wrath_hp_30.json --trace-dir=/private/tmp/warforge_h68_druid_wrath_hp_30_traces --quiet-progress=true
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h68_druid_wrath_hp_30_traces --strategy=soft_druid --druid-battle-conversion
```

Result:

- Clears: 4/30, avg final HP -4.17, avg rounds 11.07.
- Focus-active runs: 20/30, with 17 loss runs.
- Focus-active battles: 62 total, 27 won / 35 lost, 43.5% battle win rate.
- Debuff battles: 29; losses after debuff: 19; losses without debuff: 16.
- Active loss survivors: 0.0 allies, 15.9 enemies.
- Per-card battle win rates remained flat: Spore Cloud 34.5%, Wrath 47.6%, World Tree 63.2%.

Decision: ADOPT the bug fix because the implementation was wrong relative to card data. Do not
claim it repairs the Druid strategy floor.

## Cross-Lane Smoke

Ran a 35-run D1 all-strategy smoke after the fix:

- Overall: 17/35 clears, avg final HP 10.03, avg rounds 12.97.
- Boss reward eligibility/application stayed clean: R4 33/33, R8 25/25, R12 21/21, all 100%.
- `soft_druid`: 0/5 clears, avg rounds 11.20.
- Other strategy splits: adaptive 4/5, aggressive 4/5, economy 1/5, soft_military 2/5,
  soft_predator 5/5, soft_steampunk 1/5.

This smoke did not reveal a broad reward-flow regression. It did confirm that Druid is still the
worst strategy lane in the completion-readiness view.

## Verification

Focused verification:

```bash
HOME=/private/tmp/warforge_godot_home_h68_druid godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_druid_system.gd -glog=1 -gexit
HOME=/private/tmp/warforge_godot_home_h68_game_manager godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_logic.gd -glog=1 -gexit
python3 -m unittest scripts.tests.test_analyze_ai_trace
```

Results:

- PASS `test_druid_system.gd` 50/50.
- PASS `test_game_manager_logic.gd` 36/36.
- PASS `scripts.tests.test_analyze_ai_trace` 13/13.

Broad verification:

```bash
HOME=/private/tmp/warforge_godot_home_h68_full godot --headless --log-file /private/tmp/warforge_h68_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
python3 -m unittest discover -s scripts/tests
python3 scripts/lint_card_spawn.py
```

Results:

- PASS full GUT 1265/1265, 57 scripts, 8552 asserts.
- PASS Python discovery 110/110.
- PASS card spawn lint.
- PASS `git diff --check` on touched H68 files.

## Next Slice

Pause here as requested. When work resumes, the strongest next target is still Druid combat
conversion, but it should focus on actual active battle output rather than more acquisition timing:

- Spore Cloud debuff applies, yet most Spore-active focus battles still lose.
- Wrath HP parity was real but too small to move the strategy floor.
- Druid losses are still "active pieces collapse with no allied survivors", not "payoff never seen".

Good next probes would inspect Druid combat math and board survivability around Spore Cloud, Wrath,
and World Tree active frames before changing any numbers.
