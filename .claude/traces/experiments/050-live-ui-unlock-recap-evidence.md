# 050 - Live UI Unlock Recap Evidence

Date: 2026-07-27
Slice: H54

## Question

H53 added a UI-only post-run unlock reveal recap: show up to three recent
unlocks and summarize overflow while keeping all earned content immediately
available. Focused tests covered popup/progress formatting, and self-play
summaries described the `ui_reveal` model. But do we have a repeatable live UI
playtest artifact that proves the real run-end popup and the fresh next-run
availability screen match that contract?

## Multi-Review Synthesis

Three independent critics reviewed H54:

- Player/UX evidence critic: proceed with a narrow workflow extension. It should
  record what the player sees at run end and next run-start, not just saved
  state.
- Implementation-boundary critic: keep it semantic JSON-first; screenshots stay
  optional. Add fields to the existing probe/report path instead of creating a
  second harness.
- Frame/false-green critic: require an isolated reset profile, real
  `GameManager` terminal path, more than three live unlocks, fresh saved-profile
  reload, visible PROGRESS details, and visible choice modals for overflow
  rewards.

Decision: implement H54 as evidence closure for H53, not a progression feature
or pending queue.

## Changes

- `godot/tools/live_ui_probe.gd`
  - Exposes player-visible `game_over` title/summary text.
  - Exposes player-visible run-start text: stats, difficulty, recent unlocks,
    unlocked lists, goals, details visibility/text, and start/progress controls.

- `godot/tools/live_ui_smoke_report.gd`
  - Requires `reset-meta=true` for this smoke to prevent stale-profile false
    greens.
  - Adds a deterministic terminal victory through the real `_on_battle_finished`
    path with high live run stats.
  - Captures `unlock_game_over_open` with 12 earned unlocks, 3 shown unlocks,
    and 9 overflowed unlocks.
  - Instantiates a fresh `main.tscn` from the same saved meta profile.
  - Captures next-run recent unlocks and visible PROGRESS details.
  - Selects overflow commander Alchemist and overflow talisman Soul Jar through
    the visible commander/talisman modals and reaches a clean next BUILD.

- `scripts/summarize_live_ui_report.py`
  - Fails incomplete reports that omit the run-end unlock recap, overflow copy,
    next-run progress details, or overflow availability choices.
  - Adds human-readable playtest lines for run-end recap counts and overflow
    availability.

- `scripts/lint_live_ui_screenshots.py`
  - Extends the ordered screenshot/step label contract to include the new
    terminal/progress frames. Screenshots remain optional.

- `docs/tools/live-ui-smoke-report.md`
  - Documents terminal unlock recap coverage, fresh-profile availability
    coverage, new JSON event fields, and the reset-meta requirement.

## Evidence

H54 advisory multi-review:

- UX critic verdict: `YES_WITH_NARROW_SCOPE`, score 9.
- Implementation-boundary critic verdict: `approve_with_constraints`, score 8.
- Frame/false-green critic verdict: proceed as evidence closure, score 8.

Headless live UI report:

```bash
godot --headless --log-file /private/tmp/warforge_h54_live_ui_report.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h54_live_ui_report.json --commander=gambler --talisman=flint
python3 scripts/summarize_live_ui_report.py --report=/private/tmp/warforge_h54_live_ui_report.json --out=/private/tmp/warforge_h54_live_ui_report_summary.md
```

Result: PASS. Key summary lines:

- Run-end unlock recap showed 3/12 unlocks and overflowed 9.
- Next run-start recent unlocks matched the recap.
- Overflow availability was actionable: commander 7 and talisman 11 reached
  BUILD modal-free.
- Issues: None.

Focused live smoke:

```bash
godot --headless --log-file /private/tmp/warforge_h54_live_smoke_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
```

Result: PASS, 12/12 tests, 349 asserts.

Python report checks:

```bash
python3 -m unittest scripts.tests.test_summarize_live_ui_report scripts.tests.test_lint_live_ui_screenshots
python3 -m py_compile scripts/summarize_live_ui_report.py scripts/lint_live_ui_screenshots.py
```

Result: PASS, 30 tests; py_compile PASS.

Log/error checks:

```bash
rg -n "SCRIPT ERROR|Compile Error|ERROR: Failed|ObjectDB|Resource still" /private/tmp/warforge_h54_full_gut.log /private/tmp/warforge_h54_live_ui_report.log /private/tmp/warforge_h54_live_smoke_gut.log
```

Result: PASS; no matches.

Whitespace/diff checks:

```bash
rg -n "[ \t]+$" godot/tools/live_ui_probe.gd godot/tools/live_ui_smoke_report.gd godot/tests/test_game_manager_live_smoke.gd scripts/lint_live_ui_screenshots.py scripts/summarize_live_ui_report.py scripts/tests/test_summarize_live_ui_report.py docs/tools/live-ui-smoke-report.md Plans.md .claude/traces/experiments/049-post-run-unlock-reveal-recap.md
git diff --check
```

Result: PASS.

Full GUT:

```bash
godot --headless --log-file /private/tmp/warforge_h54_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
```

Result: PASS, 1242/1242 tests, 8029 asserts.

## Interpretation

H54 closes the main H53 evidence gap. The live UI smoke report no longer only
proves early run reward/actionability surfaces; it now also proves the terminal
unlock recap and the next-run availability contract from a freshly loaded
profile.

This matters because the original user concern was player-facing: unlocks felt
too numerous and unclear. H53 made the UI contract readable; H54 makes that
contract observable through a repeatable artifact.

## Next

Recommended H55: choose the next completion-oriented player-facing gap from
actual playtest evidence. Good candidates are a small run-start/progress copy
polish pass now that unlocks are observable, or another live report extension
that captures the shop/upgrade reroll split if player feedback suggests that
surface is still ambiguous.
