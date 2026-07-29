# 057 - First-BUILD Readiness Cue

Date: 2026-07-29
Slice: H61
Status: ADOPT

## Question

After H60 clarified commander/talisman selection, improve the first BUILD
decision moment without changing combat, economy, difficulty, or card values.

## Multi-Review Synthesis

- UX critic: first-time confusion now shifts from "what is a commander/talisman"
  to "what should I do before pressing BUILD COMPLETE?"
- Implementation critic: keep the slice on the existing BuildPhase surface and
  prove it through rendered live UI evidence, not a report-only field.
- Product critic: stop extending observability alone; the next step should be a
  small player-visible cue on the real BUILD handoff.

Decision: add a compact BUILD readiness cue that summarizes current field
participation, bench waiting cards, and the next useful action before combat.

## Change

- `BuildPhase` now has a `BUILD READINESS` panel on idle BUILD screens.
- The readiness text is computed from live state:
  - `FIELD: N장 체인/전투 참가`
  - `BENCH: 비어 있음` or `N장 대기(전투 불참)`
  - `Next: SHOP에서 카드를 구매`, `BENCH 카드를 FIELD로 드래그`,
    `업그레이드하거나 BUILD COMPLETE`, or
    `BUILD COMPLETE로 체인/전투 시작`
- The cue hides under target-selection or merge-reward modal ownership.
- Last-chain history owns the same lower side lane after combat, so the
  readiness cue does not compete with richer recap feedback.
- `LiveUiProbe` exports `build_readiness` text/visibility/rect and the
  `build_readiness_panel` layout rect.
- The command-line live UI report records and validates readiness on both the
  initial BUILD entry and the post-unlock BUILD entry.
- The playtest summary validates the rendered cue against the report step and
  fails if the cue is missing, hidden, missing FIELD/BENCH/Next text, or overlaps
  the confirm button or field card area.
- `docs/tools/live-ui-smoke-report.md` documents the readiness contract.

## Verification

- PASS advisory multi-review.
- PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report`
  - 23 tests.
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_tutorial.gd -glog=1 -gexit`
  - 15/15 tests, 58 asserts.
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit`
  - 12/12 tests, 543 asserts.
- PASS headless live UI smoke report plus summary:
  - report: `/private/tmp/warforge_live_ui_smoke_h61.json`
  - summary: `/private/tmp/warforge_live_ui_smoke_h61_summary.md`
  - summary includes `BUILD readiness cue: FIELD: 0장 체인/전투 참가 | BENCH: 비어 있음 | Next: SHOP에서 카드를 구매`.
- PASS `python3 scripts/lint_card_spawn.py`
- PASS `python3 -m unittest discover -s scripts/tests`
  - 104 tests.
- PASS full GUT:
  - 57 scripts, 1258 tests, 8304 asserts.

## Result

Adopted. The first BUILD screen now answers the immediate readiness question
without blocking play or changing balance.

## Pause Note

The user asked to finish only this current run and then pause. Do not start H62
from this trace automatically; resume later from the same overall game-completion
goal when the user asks.
