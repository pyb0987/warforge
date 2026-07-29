# 055 - Selection Choice Render Observability

Date: 2026-07-27
Slice: H59
Status: ADOPT

## Question

After H58 made the active commander/talisman visible during BUILD, make sure the player and live-observer tooling can prove those identities were visible at the moment of selection, before the run enters BUILD.

## Multi-Review Synthesis

- UX critic: this should be an observability/onboarding-confidence slice, not a broad tutorial rewrite.
- Implementation critic: read from the actual rendered popup labels rather than trusting commander/talisman database metadata.
- Frame critic: validate the decision path end-to-end: visible choice cards, selected option summaries, then matching BUILD identity text.

Decision: expose rendered selection-card summaries from the commander and talisman popups, then make the live UI report fail if initial or post-unlock choices are not visible and inspectable before selection.

## Findings

- Commander and talisman popups already rendered useful names/descriptions, but the observer could only see choice IDs.
- The earlier identity HUD check proved the final BUILD state, but not that the player had a readable choice moment.
- Post-unlock selection needed the same evidence because the live report intentionally proves that newly unlocked overflow choices can be selected on a fresh next run.

## Change

- `CommanderSelectPopup` and `TalismanSelectPopup` now expose `get_choice_summaries()` from actual child labels:
  - `id`
  - `idx`
  - `name`
  - `desc`
  - joined visible `text`
  - panel `rect`
- Selection card label nodes now have stable names for observer access.
- `LiveUiProbe` snapshots now include `commander_select.choice_summaries` and `talisman_select.choice_summaries` while those modals are visible.
- The live UI smoke report records `events.run_selection` for initial commander/talisman selection, including selected summaries.
- The post-unlock availability event now carries rendered Alchemist and Soul Jar selection-card summaries, plus final BUILD identity text after selecting them.
- The live UI report fails if selection summaries are blank, missing, have zero rects, or do not match the final BUILD identity.
- The Markdown summarizer validates the same selection evidence and reports what was rendered before BUILD.
- `docs/tools/live-ui-smoke-report.md` documents the new selection-card evidence contract.

## Verification

- PASS advisory multi-review.
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_commander_select_popup.gd -glog=1 -gexit`
  - 4/4 tests, 16 asserts.
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_talisman_select_popup.gd -glog=1 -gexit`
  - 5/5 tests, 17 asserts.
- PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report`
  - 21 tests.
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit`
  - 12/12 tests, 363 asserts.
- PASS headless live UI smoke report plus summary.
  - Initial rendered selection cards included `도박꾼` and `부싯돌`.
  - Post-unlock rendered selection cards included `연금술사` and `영혼 항아리`.
- PASS `python3 scripts/lint_card_spawn.py`
- PASS `python3 -m unittest discover -s scripts/tests`
  - 102 tests.
- PASS `git diff --check`
- PASS exact merge-marker scan:
  - `rg -n "^(<{7}|>{7}|={7})( |$)" . --glob '!godot/.godot/**' --glob '!*.import'`
- PASS full GUT with Godot allowed to write its normal user-data test profile:
  - 57 scripts, 1253 tests, 8099 asserts.

## Result

Adopted. The run-start decision path is now observable from rendered UI, and the smoke report proves that selected commander/talisman cards were legible before the final BUILD HUD identity appears.

## Next Candidate

The next plausible improvement is to use the new visibility evidence to tighten first-run onboarding copy and progress unlock presentation without changing balance or difficulty.
