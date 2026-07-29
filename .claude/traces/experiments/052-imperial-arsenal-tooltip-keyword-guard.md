# 052 - Imperial Arsenal Tooltip Keyword Guard

Date: 2026-07-27
Slice: H56
Status: ADOPT

## Question

The player reported that Imperial Arsenal appeared to carry the Druid growth keyword in its explanation. Confirm whether the leak came from YAML/codegen text or from UI keyword matching, then fix the layer that caused the misleading in-game tooltip.

## Multi-Review Synthesis

- UX perspective: event/merge history remains the highest visible friction, but the Arsenal tooltip issue is a sharper trust bug because it makes a card look like it belongs to the wrong mechanic family.
- Technical perspective: generated card descriptions already use Steampunk upgrade wording for `sp_arsenal`, so the likely defect is tooltip glossary matching against bare keyword substrings.
- Scope perspective: prefer a targeted correctness fix before broader UI polish, then return to merge/history readability as the next player-facing candidate.

Decision: make H56 a verification-first tooltip keyword slice. Do not change card numbers or generated card data.

## Findings

- `sp_arsenal` generated text did not currently contain Druid tree-growth language.
- `CardTooltip` scanned every glossary keyword by raw substring; a phrase containing generic `성장` could pull in the Druid `[드루이드] 성장` definition.
- The glossary treated bare `성장` as Druid-specific even though multiple non-Druid cards use it for generic permanent stat growth.

## Change

- Reclassified bare `성장` as common stat growth.
- Added explicit Druid `나무 성장` glossary entry for tree-growth events.
- Updated tooltip keyword detection to match longer keywords first and mask matched spans, so `나무 성장` wins over nested bare `성장`.
- Added tooltip regression coverage for Imperial Arsenal, non-Druid bare growth, and explicit tree growth.
- Added allow markers to deliberate live-smoke fixture board/bench setup assignments so the card-spawn funnel guard remains green.

## Verification

- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_card_tooltip.gd -glog=1 -gexit`
  - 3/3 tests, 9 asserts.
- PASS `python3 -m unittest scripts.tests.test_card_desc_codegen scripts.tests.test_keywords_glossary`
  - 9 tests.
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_card_db.gd -glog=1 -gexit`
  - 32/32 tests, 2404 asserts.
- PASS `python3 scripts/lint_card_spawn.py`
- PASS headless live UI smoke report plus summary.
  - Summary verdict PASS.
  - Shop reroll scope still held.
  - Unlock recap still showed 3/12 with overflow availability actionable.
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit`
  - 12/12 tests, 349 asserts.
- PASS `python3 -m unittest discover -s scripts/tests`
  - 96 tests.
- PASS `git diff --check`
- PASS full GUT:
  - 57 scripts, 1246 tests, 8042 asserts.

## Result

Adopted. Imperial Arsenal now displays Steampunk upgrade glossary context without the Druid growth definition. Generic non-Druid growth text remains explainable as common growth, while explicit Druid tree-growth text still receives the Druid glossary entry.

## Next Candidate

H57 should likely return to the player's merge/event-history feedback complaint: decide whether to remove the sticky single merge message entirely or replace it with a compact inspectable history.
