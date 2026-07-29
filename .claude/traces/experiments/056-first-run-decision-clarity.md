# 056 - First-Run Decision Clarity

Date: 2026-07-27
Slice: H60
Status: ADOPT

## Question

After H59 proved the commander/talisman choice cards were rendered, improve the actual player-facing first choice moment without adding a new tutorial flow or changing balance.

## Multi-Review Synthesis

- UX critic: pick a small run-start choice-clarity slice; the first five minutes hinge on understanding commander and talisman choices before BUILD.
- Implementation critic: use existing selection and BUILD observer surfaces so the change can be proven without subjective screenshot-only evidence.
- Product/frame critic: stop adding observability-only work here; H60 should change what the player sees while keeping mechanics, unlocks, difficulty, and economy untouched.

Decision: add short context text to the existing selection modals, and carry the selected commander summary into the talisman selection modal so the player sees continuity before BUILD.

## Findings

- The commander/talisman cards already showed names and effect descriptions, but the modal itself did not state what kind of run choice the player was making.
- After selecting a commander, the talisman modal did not remind the player which commander was locked in.
- H59 gave the live UI report enough rendered-text access to validate this as real UI, not reconstructed metadata.

## Change

- `CommanderSelectPopup` now shows a visible role context line: `커맨더 = 런 전체 방향을 바꾸는 큰 규칙`.
- `TalismanSelectPopup` now shows a visible role context line, and when opened after commander selection it includes the selected commander icon/name/effect above the talisman role line.
- `GameManager` passes the selected commander into talisman selection.
- `LiveUiProbe` exports selection modal `context_text` and `context_rect`.
- The live UI smoke report records and validates initial and post-unlock selection context, including selected-commander continuity on the talisman modal.
- The Markdown summary reports the first-run choice context in the "What Codex Saw" section.
- Focused popup, live smoke, and summarizer tests now fail if the context text or visible rect disappears.
- `docs/tools/live-ui-smoke-report.md` documents the selection context contract.

## Verification

- PASS advisory multi-review.
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_commander_select_popup.gd -glog=1 -gexit`
  - 5/5 tests, 21 asserts.
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_talisman_select_popup.gd -glog=1 -gexit`
  - 6/6 tests, 23 asserts.
- PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report`
  - 22 tests.
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit`
  - 12/12 tests, 447 asserts.
- PASS headless live UI smoke report plus summary.
  - Summary includes `Choice context before BUILD`.
  - Talisman context includes the selected commander `도박꾼`.
- PASS `python3 scripts/lint_card_spawn.py`
- PASS `python3 -m unittest discover -s scripts/tests`
  - 103 tests.
- PASS `git diff --check`
- PASS exact merge-marker scan:
  - `rg -n "^(<{7}|>{7}|={7})( |$)" . --glob '!godot/.godot/**' --glob '!*.import'`
- PASS full GUT with Godot allowed to write its normal user-data test profile:
  - 57 scripts, 1255 tests, 8194 asserts.

## Result

Adopted. The first-run decision path now explains commander and talisman roles in-place, and the talisman choice preserves the selected commander context before the run reaches BUILD.

## Next Candidate

The next plausible improvement is a small manual-play readiness pass: inspect first BUILD density now that run identity, selection context, shop reroll scope, merge history, and chain feedback are all visible, then choose one remaining player-facing friction point rather than adding more observability.
