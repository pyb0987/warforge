# 049 - Post-Run Unlock Reveal Recap

Date: 2026-07-27
Slice: H53

## Question

H52 showed that a representative run can pressure more than the user-visible
unlock recap budget: largest raw projected single-run unlock count was 11, with
6/10 runs deferring at least one item under a 3-item reveal model. Should H53
delay actual unlock availability, or only make the reveal/presentation layer
more readable while keeping the earned-content contract unchanged?

## Multi-Review Synthesis

Three independent critics reviewed the progression contract:

- Player progression critic: do not delay actual availability yet. Show three
  featured unlocks, summarize overflow, and keep everything available in the
  Progress screen.
- Frame/design critic: H52 evidence is still projection/proxy evidence for some
  metrics, so avoid a persisted pending queue until actual-player progression
  data justifies the contract change.
- Implementation/test critic: a real pending queue is implementable later, but
  if H53 is presentation-only, the copy and tests must explicitly state that
  overflow does not block use.

Decision: adopt a UI-only reveal recap. Do not change live unlock availability.

## Changes

- `godot/core/meta_progress.gd`
  - Adds `UNLOCK_RECAP_LIMIT = 3`.
  - Adds `format_unlock_recap_text(...)` shared by the progress screen and
    game-over popup.
  - Keeps `last_unlocks` as the full recent unlock list while formatting only
    the first three plus an overflow line.

- `godot/scripts/ui/game_over_popup.gd`
  - `show_result(...)` accepts an optional unlock list.
  - Victory/defeat summaries now include a `New unlocks available` section when
    the run earned unlocks.

- `godot/scripts/game/game_manager.gd`
  - `_record_run_finished(...)` returns the unlock list from `MetaProgress`.
  - Fatal and victory run-end paths pass those unlocks to the result popup.
  - Fixed a regression caught by live smoke: run recording and game-over popup
    display must not depend on `_logger` being present.

- `godot/scenes/ui/game_over_popup.tscn`
  - Gives the result summary enough width/height and wrapping for the unlock
    recap.

- `godot/tools/self_play_observer_logic.gd`
  - Renames the pacing model from hypothetical to `ui_reveal`.
  - Documents that the cap matches UI presentation and not live availability.

- `scripts/summarize_self_play_report.py`
  - Summaries now report `Reveal pacing model: ui_reveal, cap 3/run`.

- `docs/design/replay.md` and `docs/tools/self-play-observer.md`
  - Clarify that overflow is presentation-only and earned commanders, talismans,
    and difficulties are immediately usable.

## Evidence

Focused game-over popup GUT:

```bash
godot --headless --log-file /private/tmp/warforge_h53_game_over_popup_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_over_popup.gd -glog=1 -gexit
```

Result: PASS, 2/2 tests, 13 asserts.

Focused run-start/progress GUT:

```bash
godot --headless --log-file /private/tmp/warforge_h53_run_start_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_run_start_screen.gd -glog=1 -gexit
```

Result: PASS, 6/6 tests, 34 asserts.

Focused live game manager smoke:

```bash
godot --headless --log-file /private/tmp/warforge_h53_live_smoke_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
```

Result: PASS, 12/12 tests, 347 asserts. This covers the no-logger fatal path
and final victory path saving progression and showing the result popup.

Focused observer GUT:

```bash
godot --headless --log-file /private/tmp/warforge_h53_self_play_observer_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_self_play_observer.gd -glog=1 -gexit
```

Result: PASS, 8/8 tests, 60 asserts.

Python summary checks:

```bash
python3 -m unittest scripts.tests.test_summarize_self_play_report scripts.tests.test_lint_live_ui_screenshots scripts.tests.test_summarize_live_ui_report
python3 -m py_compile scripts/summarize_self_play_report.py scripts/summarize_live_ui_report.py scripts/lint_live_ui_screenshots.py
```

Result: PASS, 30 tests; py_compile PASS.

Command-line self-play smoke:

```bash
godot --headless --log-file /private/tmp/warforge_h53_selfplay_smoke.log --path godot/ -s tools/self_play_observer.gd -- --runs=1 --strategies=adaptive --difficulty=1 --commander=gambler --talisman=flint --seed=2026072753 --out=/private/tmp/warforge_h53_selfplay_smoke.json --quiet-progress=true
python3 scripts/summarize_self_play_report.py --report=/private/tmp/warforge_h53_selfplay_smoke.json --out=/private/tmp/warforge_h53_selfplay_smoke_summary.md
```

Result: PASS. Summary reported:

- Projection status: complete.
- Reveal pacing model: `ui_reveal`, cap 3/run.
- Largest raw single-run projection: 5.
- Deferred in 1/1 runs, largest deferred count 2.

Log/error checks:

```bash
rg -n "SCRIPT ERROR|Compile Error|ERROR: Failed|ObjectDB|Resource still" /private/tmp/warforge_h53_full_gut.log /private/tmp/warforge_h53_selfplay_smoke.log /private/tmp/warforge_h53_game_over_popup_gut.log /private/tmp/warforge_h53_run_start_gut.log /private/tmp/warforge_h53_live_smoke_gut.log /private/tmp/warforge_h53_self_play_observer_gut.log
```

Result: PASS; no matches.

Whitespace/diff checks:

```bash
rg -n "[ \t]+$" godot/core/meta_progress.gd godot/scripts/ui/game_over_popup.gd godot/scripts/game/game_manager.gd godot/scenes/ui/game_over_popup.tscn godot/tests/test_game_over_popup.gd godot/tests/test_run_start_screen.gd godot/tests/test_game_manager_live_smoke.gd godot/tests/test_self_play_observer.gd godot/tools/self_play_observer_logic.gd scripts/summarize_self_play_report.py scripts/tests/test_summarize_self_play_report.py docs/design/replay.md docs/tools/self-play-observer.md
git diff --check
```

Result: PASS.

Full GUT:

```bash
godot --headless --log-file /private/tmp/warforge_h53_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
```

Result: PASS, 1242/1242 tests, 8027 asserts.

## Interpretation

H53 resolves the immediate user-facing problem without reducing actual earned
content. A first run can still unlock many items, but the run-end popup and the
next-run progress screen now show a readable top-three recap plus an explicit
overflow message: `+N more unlocked - all available in PROGRESS`.

The contract is intentionally conservative:

- Availability remains immediate.
- The observer and summary tools now describe the reveal model as actual UI
  behavior rather than a hypothetical queue.
- A future real pending queue remains possible, but it should require fresh
  actual-progression evidence and another multi-review because it would change
  the player's reward contract.

## Next

Recommended H54: improve the next self-play/playtest workflow so it can capture
the real run-end unlock recap and progress-screen availability state, not only
headless projection fields. This would turn the H53 UI contract into observable
evidence and make later unlock pacing changes safer.
