# 065 - Druid Combat Data Parity

Date: 2026-07-29
Status: DONE - adopted correctness fixes; Druid strategy floor remains unresolved

## Objective

H68 showed that Druid focus cards are active often enough to evaluate, but many active battle
frames still collapse with no allied survivors. Before testing another balance probe, H69 checked
whether Druid YAML/card descriptions still contained combat promises that runtime code silently
ignored.

Multi-review guidance converged on two constraints:

- Fix concrete data/runtime mismatches before touching balance.
- Use self-play as outcome evidence only after unit and integration coverage prove the mechanics.

## Defects Fixed

### Spore Cloud star 3 self shield

`dr_spore_cloud` star 3 data includes `tree_shield`, but `_spore_cloud_battle()` only processed
`debuff_store`.

Fix:

- `godot/core/druid_system.gd` now applies the Spore Cloud self shield from YAML:
  `base_pct + trees * tree_scale_pct`.
- `godot/tests/test_druid_system.gd` now checks star 3 AS debuff, ATK debuff, and self shield
  together.

### Wrath star 3 kill recovery

`dr_wrath` star 3 data/description advertised kill HP recovery, but no combat mechanic existed.
The boolean YAML value was also ambiguous for player-facing text.

Fix:

- `data/cards/druid.yaml` now specifies `kill_hp_recover: 0.15`.
- `godot/core/druid_system.gd` stores `kill_hp_recover_pct` only while Wrath's persistent unit-cap
  condition is active.
- `godot/scripts/game/game_manager.gd` and `godot/sim/headless_runner.gd` materialize that state
  as a `kill_hp_recover` combat mechanic.
- `godot/combat/mechanics_handler.gd` heals the attacker by `max_hp * heal_hp_pct` after a kill,
  capped at max HP.
- `godot/tests/test_combat_basics.gd`, `godot/tests/test_druid_system.gd`, and
  `godot/tests/test_game_manager_logic.gd` cover the path.

### Grace star 3 free reroll

While adding a Druid action coverage guard, `dr_grace` star 3 exposed another parity gap:
YAML contains `free_reroll`, but `_grace_post()` only returned gold/terazin.

Fix:

- `DruidSystem.apply_post_combat()` returns `free_rerolls`.
- `ChainEngine.process_post_combat()` aggregates the value and calls the existing
  `pending_free_reroll_callback`.
- `godot/tests/test_druid_system.gd` and `godot/tests/test_chain_engine.gd` cover the card-level
  and chain-level signal.

## Guard Added

`test_druid_theme_system_handles_all_current_yaml_actions` walks all Druid CardDB effect blocks for
stars 1-3 and asserts every current action name has an explicit Druid runtime coverage bucket. This
is intentionally a Druid-local guard so future YAML additions do not become silent no-ops.

## Same-Seed Druid Evidence

Command:

```bash
HOME=/private/tmp/warforge_godot_home_h69_druid_parity godot --headless --log-file /private/tmp/warforge_h69_druid_parity_30.log --path godot/ -s tools/self_play_observer.gd -- --runs=30 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=flint --seed=2026072901 --out=/private/tmp/warforge_h69_druid_parity_30.json --trace-dir=/private/tmp/warforge_h69_druid_parity_30_traces --quiet-progress=true
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h69_druid_parity_30_traces --strategy=soft_druid --druid-battle-conversion
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h69_druid_parity_30_traces --strategy=soft_druid --druid-loss-buckets
```

Result:

- Clears: 4/30, avg final HP -4.17, avg rounds 11.07.
- Focus-active battles: 62 total, 27 won / 35 lost, 43.5% battle win rate.
- Active loss survivors: 0.0 allies, 15.9 enemies.
- Enemy debuffs seen in 40.0% of runs, with ATK avg max 1.3% and AS avg max 7.3%.
- Loss buckets: `path_lag_hold_pressure` 16, `combat_conversion_failure` 10,
  `payoff_acquisition_lag` 8, `payoff_no_debuff_conversion` 7.

Decision: ADOPT the parity fixes because runtime behavior was wrong relative to card data and
descriptions. Do not claim this repairs the Druid strategy floor; same-seed outcome evidence remains
flat versus H68.

## Cross-Lane Smoke

Command:

```bash
HOME=/private/tmp/warforge_godot_home_h69_all35 godot --headless --log-file /private/tmp/warforge_h69_all35.log --path godot/ -s tools/self_play_observer.gd -- --runs=5 --strategies=soft_steampunk,soft_druid,soft_predator,soft_military,adaptive,economy,aggressive --difficulty=1 --commander=gambler --talisman=flint --seed=2026072901 --out=/private/tmp/warforge_h69_all35.json --trace-dir=/private/tmp/warforge_h69_all35_traces --quiet-progress=true
python3 scripts/summarize_self_play_report.py --report /private/tmp/warforge_h69_all35.json --out /private/tmp/warforge_h69_all35_summary.md
```

Result:

- Overall: 17/35 clears, avg rounds 12.97, avg final HP 10.03.
- Strategy split: adaptive 4/5, aggressive 4/5, economy 1/5, soft_druid 0/5,
  soft_military 2/5, soft_predator 5/5, soft_steampunk 1/5.
- Boss reward flow stayed clean: R4 33/33, R8 25/25, R12 21/21 reward/eligible.

The smoke did not show a broad shared-combat regression, but it again identifies Druid as the weak
strategy floor.

## Verification

Focused verification:

```bash
python3 scripts/codegen_card_db.py --check
python3 scripts/lint_card_spawn.py
python3 -m unittest scripts.tests.test_lint_card_spawn scripts.tests.test_summarize_self_play_report scripts.tests.test_lint_live_ui_screenshots scripts.tests.test_analyze_ai_trace scripts.tests.test_card_desc_codegen
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_druid_system.gd -glog=1 -gexit
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_chain_engine.gd -glog=1 -gexit
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_combat_basics.gd -glog=1 -gexit
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_combat_advanced.gd -glog=1 -gexit
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_logic.gd -glog=1 -gexit
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_headless_runner.gd -glog=1 -gexit
```

Results:

- PASS codegen check: generated card DB/descriptions/conscript pool match YAML.
- PASS card spawn lint.
- PASS Python focused suite: 47/47.
- PASS `test_druid_system.gd` 53/53.
- PASS `test_chain_engine.gd` 21/21.
- PASS `test_combat_basics.gd` 17/17.
- PASS `test_combat_advanced.gd` 15/15.
- PASS `test_game_manager_logic.gd` 37/37.
- PASS `test_headless_runner.gd` 15/15.

Broad verification:

```bash
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
git diff --check
```

Results:

- PASS full GUT 1272/1272, 57 scripts, 8662 asserts.
- PASS `git diff --check`.
- PASS exact conflict-marker scan on touched H69 files.

## Next Slice

Continue Druid completion work, but treat H69 as correctness closure, not balance success. The next
most plausible gameplay slice is a measured Druid combat-conversion probe focused on R9-R11 active
losses:

- Target active battle output, not acquisition timing.
- Keep the same-seed 30-run Druid gate and cross-lane smoke.
- Prefer Spore Cloud/Wrath/World Tree battle math over global Druid common bonus or difficulty
  changes.
