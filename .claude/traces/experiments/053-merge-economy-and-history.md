# 053 - Merge Economy and History

Date: 2026-07-27
Slice: H57
Status: ADOPT

## Question

After H56, choose the next player-facing hardening slice from the playtest complaints. The candidate merge issue had two parts: a possible ★1→★2 money increase and a merge message that could feel sticky while only preserving the last merge.

## Multi-Review Synthesis

- UX critic: replace the sticky single merge message with a compact visible history. Removing feedback entirely would make merges harder to audit.
- Implementation critic: prefer bounded history over timer-cleared transient state because it is deterministic and easy to expose in live reports.
- Frame critic: verify merge economy before pure UI polish because a real gold defect would undermine player trust more than text placement.

Decision: make H57 a narrow merge economy plus merge-feedback slice. Do not change card values, difficulty, or broad build layout.

## Findings

- The money increase was plausible under the old Gambler rule: buying a third T1 card for 2g could immediately trigger a ★1→★2 merge refund of 3g.
- Design docs already framed Gambler as a `★3 올인` commander in `replay.md`; `commanders.md` and code were broader than that.
- The merge feedback UI held only `_last_merge_summary` and cleared it by timer, so after multiple merges the older events were not inspectable.

## Change

- Gambler merge refund now applies only to ★2→★3 merges.
- The ★3 refund is computed from the original ★1 investment represented by the three ★2 cards.
- Build HUD copy and design docs now say `★3 합성 환급`.
- The transient `MergeSummaryLabel` was replaced by a bounded `RECENT MERGES` panel.
- Merge history is cleared at run setup, stores newest entries first, hides under active decision modals, and suppresses settlement/tutorial copy in the same right-side lane.
- `LiveUiProbe` and live UI smoke reports now expose merge history and deterministic merge gold math.
- The Markdown playtest summarizer now rejects reports missing merge-history evidence or showing a ★1→★2 Gambler refund.

## Verification

- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_commander.gd -glog=1 -gexit`
  - 37/37 tests, 121 asserts.
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_merge_bonus.gd -glog=1 -gexit`
  - 10/10 tests, 38 asserts.
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit`
  - 14/14 tests, 86 asserts.
- PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report`
  - 17 tests.
- PASS headless live UI smoke report plus summary.
  - Summary verdict PASS.
  - Merge reward line: history visible yes, gold 10 -> 8 after -2g purchase, +0g merge refund.
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit`
  - 12/12 tests, 349 asserts.
- PASS `python3 scripts/lint_card_spawn.py`
- PASS `python3 -m unittest discover -s scripts/tests`
  - 98 tests.
- PASS `git diff --check`
- PASS full GUT:
  - 57 scripts, 1250 tests, 8057 asserts.

## Result

Adopted. The reported ★1→★2 money increase should no longer occur for Gambler, while the intended ★3 all-in refund remains. Merge feedback is no longer a stale last-only transient message; it is a bounded recent history that live self-play can inspect.

## Next Candidate

H58 should likely return to live in-game clarity for selected commander/talisman effects: the HUD now names them, but the next improvement could make per-effect status and recent talisman triggers more visible without growing into a full combat log.
