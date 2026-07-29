# 054 - Run Identity Status Clarity

Date: 2026-07-27
Slice: H58
Status: ADOPT

## Question

After H57 fixed merge economy/history, address the remaining playtest clarity issue: the player should be able to tell which commander and talisman are active and whether their relevant effects are currently doing anything.

## Multi-Review Synthesis

- UX critic: avoid another right-side panel because that lane already carries tutorial, settlement, chain, and merge history. Make the existing identity HUD more legible instead.
- Implementation critic: strengthen the top HUD plus `LiveUiProbe` observability before introducing a new panel.
- Frame critic: require evidence from a real live flow, especially a talisman state transition, rather than only checking metadata.

Decision: keep H58 narrow. Improve the existing HUD identity label, expose its rendered text/rect to the observer, and make the live smoke report fail if commander/talisman status clarity disappears.

## Findings

- The HUD already had an `IdentityLabel`, but it compressed effects into `C:` and `T:` shorthand.
- Two-Faced Coin slot visibility was already partially covered in live smoke, but only through direct HUD text and shop visuals.
- The first smoke acceptance attempt caught an important lifecycle detail: Flint shows `사용됨` during the CHAIN pause, then resets to `준비` in the next BUILD round. The final contract records all three moments.

## Change

- `BuildPhase` identity text now renders as two plain player-facing lines:
  - `커맨더: <icon> <name> - <effect/status>`
  - `부적: <icon> <name> - <effect/status>`
- Removed `C:`/`T:` shorthand from the identity effect line.
- Added `get_identity_text()` for tests and live probes.
- Flint status copy now says `첫 성장 효과 ×2 준비/사용됨`.
- The identity label has a stable minimum size in the BUILD HUD scene.
- `LiveUiProbe` now exports `identity.text`, `identity.visible`, `identity.rect`, and `layout_rects.identity_label`.
- The live UI smoke report records `events.run_identity` for:
  - first BUILD entry: Flint ready;
  - CHAIN pause: Flint used;
  - next BUILD: Flint ready again.
- The Markdown live UI summarizer validates the rendered identity event and reports what Codex saw.
- Focused and live tests now assert commander/talisman names, Two-Faced Coin discount/markup slot text, Flint ready/used status, visible identity rects, and absence of `C:`/`T:` shorthand.
- `docs/tools/live-ui-smoke-report.md` documents the new identity observability contract.

## Verification

- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit`
  - 15/15 tests, 94 asserts.
- PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report`
  - 19 tests.
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit`
  - 12/12 tests, 363 asserts.
- PASS headless live UI smoke report plus summary.
  - Summary verdict PASS.
  - Identity line showed Flint `준비` at BUILD entry, `사용됨` during CHAIN, and `준비` again in next BUILD.
- PASS `python3 scripts/lint_card_spawn.py`
- PASS `python3 -m unittest discover -s scripts/tests`
  - 100 tests.
- PASS `git diff --check`
- PASS exact merge-marker scan:
  - `rg -n "^(<{7}|>{7}|={7})( |$)" . --glob '!godot/.godot/**' --glob '!*.import'`
- PASS full GUT:
  - 57 scripts, 1251 tests, 8079 asserts.

## Result

Adopted. The active commander and talisman are now visible as normal player-facing HUD text, active effect state is observable, and the self-play/reporting loop will catch regressions in rendered identity clarity.

## Next Candidate

The next plausible improvement is a broader command/talisman onboarding pass: make selection cards and first-run tutorial moments explain why a commander/talisman matters before the player reaches the BUILD HUD, without changing balance.
