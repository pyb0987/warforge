# Episode 078: Live UI Identity Matrix Runner

Date: 2026-07-29
Owner: Codex
Plan item: H82

## Purpose

Continue progress toward a complete playable game while H78 remains gated by
explicit approval for protected `godot/sim/**` edits. H80 and H81 made locked
identity smoke reports and run progress observable one identity at a time. The
next unprotected completion step was to make those checks repeatable across a
small set of important commander/talisman profiles.

## Decision

Add a thin Python runner around the existing live UI smoke report instead of
duplicating report logic. The live Godot reporter and Markdown summarizer remain
the source of truth for UI/actionability assertions; the matrix only handles
identity selection, per-row isolation, subprocess execution, and aggregate
status.

Default identities:

- `baseline=gambler:flint`
- `coin=gambler:two_faced_coin`
- `golden_die=gambler:golden_die`
- `locked_economy=alchemist:soul_jar`

These cover the default unlocked path, the previously reported Two-Faced Coin
pricing surface, locked Golden Die boss reward breadth, and a locked
commander/talisman economy identity.

## Changes

- Added `scripts/run_live_ui_identity_matrix.py`.
- Added `scripts/tests/test_run_live_ui_identity_matrix.py`.
- Documented the matrix command and custom `--identity` rows in
  `docs/tools/live-ui-smoke-report.md`.
- Recorded H82 in `Plans.md` and `.claude/handoff.md`.

The runner writes one folder per identity containing:

- `report.json`
- `summary.md`
- `godot.log`
- isolated Godot `HOME`

The aggregate output is `matrix.json` plus `matrix.md`.

## Verification

- PASS `python3 -m py_compile scripts/run_live_ui_identity_matrix.py scripts/tests/test_run_live_ui_identity_matrix.py`.
- PASS `python3 -m unittest scripts.tests.test_run_live_ui_identity_matrix -q`
  (6 tests).
- PASS curated live UI identity matrix:
  `python3 scripts/run_live_ui_identity_matrix.py --output-dir=/private/tmp/warforge_h82_live_ui_identity_matrix --out=/private/tmp/warforge_h82_live_ui_identity_matrix/matrix.json --summary-out=/private/tmp/warforge_h82_live_ui_identity_matrix/matrix.md`
  produced:
  - `Verdict: PASS`
  - `Passing identities: 4/4`
  - PASS `baseline`: 도박꾼 + 부싯돌
  - PASS `coin`: 도박꾼 + 양면 동전
  - PASS `golden_die`: 도박꾼 + 황금 주사위
  - PASS `locked_economy`: 연금술사 + 영혼 항아리
- PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report -q`
  (30 tests).
- PASS `git diff --check`.

No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
difficulty values, or Godot runtime files were changed for H82.

## Next

- Unprotected: broaden the matrix with a custom commander/talisman preset if a
  specific identity remains suspicious, or move to the next live completion gap.
- Protected: H78, the Druid path-lag stabilizer AI probe, still requires
  explicit approval before editing `godot/sim/**`.
