# 105 - H105 Spore Forest Boundary Guard

Date: 2026-07-31
Status: DONE - boundary guard only, no gameplay files edited

## Purpose

Add an executable changed-file boundary check for the H105 Druid Spore
forest-depth protected probe. The H105 packet is intentionally runtime-only, so
post-probe verification should fail if an implementation accidentally touches
card YAML, generated card data, schema/codegen, AI simulator policy, or other
surfaces outside the packet.

## Changes

- Added `scripts/check_h105_spore_forest_boundary.py`.
- Added `scripts/tests/test_check_h105_spore_forest_boundary.py`.
- Documented the boundary guard in `docs/tools/self-play-observer.md`.

Usage after an H105 probe:

```bash
python3 scripts/check_h105_spore_forest_boundary.py --allow-records
```

Strict runtime-only check, without records:

```bash
python3 scripts/check_h105_spore_forest_boundary.py
```

## Boundary Rules

Allowed H105 probe files:

- `godot/core/druid_system.gd`
- `godot/tests/test_druid_system.gd`
- `godot/tests/test_chain_engine.gd`

With `--allow-records`, also allow:

- `Plans.md`
- `.claude/traces/experiments/*`

Explicitly rejected:

- `data/cards/druid.yaml`
- `godot/core/data/card_db.gd`
- `godot/core/data/card_descs.gd`
- `scripts/codegen_card_db.py`
- `scripts/card_desc_gen.py`
- `docs/design/card-codegen-schema.md`
- `godot/sim/**`
- any other file not in the H105 allowlist

## Verification

- PASS `python3 -m py_compile scripts/check_h105_spore_forest_boundary.py scripts/tests/test_check_h105_spore_forest_boundary.py`.
- PASS `python3 -m unittest scripts.tests.test_check_h105_spore_forest_boundary -q` (6 tests).
- PASS `python3 -m unittest scripts.tests.test_check_h105_spore_forest_boundary scripts.tests.test_evaluate_h105_spore_forest_probe -q` (9 tests).
- PASS `python3 scripts/check_h105_spore_forest_boundary.py --help`.
- PASS `git diff --check`.

## Boundary

No runtime, card data, generated database, AI, difficulty, economy, or UI files
were edited. H105 still requires fresh approval before implementation.
