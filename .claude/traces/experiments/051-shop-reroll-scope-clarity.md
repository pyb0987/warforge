# 051 - Shop Reroll Scope Clarity

Date: 2026-07-27
Slice: H55

## Question

The playtest feedback asked whether rerolling the card shop also rerolls the
upgrade shop. Existing build-phase logic already separates the two: player card
shop refresh keeps upgrade offers, while explicit phase refresh may refresh both
shops. The remaining problem was player-facing ambiguity because both surfaces
looked like generic rerolls.

## Decision

Make the existing rule visible and observable instead of changing gameplay:

- `R` is the card-shop reroll and changes card offers only.
- `T` is the upgrade-shop reroll and changes upgrade offers only.
- Round/phase entry may refresh both when it explicitly passes
  `refresh_upgrades=true`.

No multi-review was used for this slice because it was not a high-risk design
decision; the intended behavior was already covered by focused tests and design
notes, and the implementation was a narrow UI/observability clarification.

## Changes

- `godot/scripts/build/build_phase.gd`
  - Card shop label now says `CARD SHOP` and `R:cards`.
  - Upgrade shop label now says `UPGRADES (T:upgrades only)`.
  - Upgrade reroll button now says `UPG REROLL (T)`.
  - Added a short comment documenting that card refresh does not touch upgrade
    offers unless `refresh_upgrades=true`.

- `godot/scenes/build/build_phase.tscn`
  - Updated default scene copy to match the runtime labels.

- `godot/tools/live_ui_probe.gd`
  - Adds a `shop` snapshot with card offer IDs/costs, upgrade offer IDs/costs,
    shop labels, and upgrade reroll button state.

- `godot/tools/live_ui_smoke_report.gd`
  - Adds `events.shop_reroll_scope`.
  - The event performs a card reroll and proves card offers changed while
    upgrade offers stayed fixed.
  - The event then performs an upgrade reroll and proves upgrade offers changed
    while card offers stayed fixed.

- `scripts/summarize_live_ui_report.py`
  - Validates the new reroll-scope event.
  - Summarizes the before/after offer IDs for human review.

- `docs/design/upgrade.md`
  - Records the card-vs-upgrade reroll rule and phase-refresh exception.

- `docs/tools/live-ui-smoke-report.md`
  - Documents the new report event and invariant.

## Evidence

Focused build-phase UX/logic:

```bash
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit
```

Result: PASS, 14/14 tests, 86 asserts.

Headless live UI report:

```bash
godot --headless --log-file /private/tmp/warforge_h55_live_ui_report.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h55_live_ui_report.json --commander=gambler --talisman=flint
python3 scripts/summarize_live_ui_report.py --report=/private/tmp/warforge_h55_live_ui_report.json --out=/private/tmp/warforge_h55_live_ui_report_summary.md
```

Result: PASS. Key summary lines:

- Shop reroll scope held: card reroll changed cards and preserved upgrades yes;
  upgrade reroll changed upgrades and preserved cards yes.
- Shop reroll offers: cards changed from
  `[sp_furnace, ne_earth_echo, sp_assembly, dr_lifebeat, ml_barracks,
  ml_conscript]` to
  `[dr_lifebeat, sp_workshop, sp_workshop, sp_workshop, ne_pawnbroker,
  ne_wild_pulse]`.
- Upgrade offers changed from `[C9, C7]` to `[R8, R6]`.
- Issues: None.

Focused live smoke:

```bash
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
```

Result: PASS, 12/12 tests, 349 asserts.

Python report checks:

```bash
python3 -m unittest scripts.tests.test_summarize_live_ui_report scripts.tests.test_lint_live_ui_screenshots
python3 -m unittest discover -s scripts/tests
python3 -m py_compile scripts/summarize_live_ui_report.py scripts/tests/test_summarize_live_ui_report.py scripts/lint_live_ui_screenshots.py
```

Result: PASS, 33 focused tests; PASS, 96 discovered tests; py_compile PASS.

Full GUT:

```bash
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
```

Result: PASS, 1243/1243 tests, 8033 asserts.

Scan checks:

Commands: stale-copy scan for old shop/reroll labels; conflict-marker and
H55-marker scan across the changed files.

Result: stale-copy scan only matched intended `UPG REROLL (T)` copy; conflict/TODO
scan found no matches.

## Interpretation

This answers the original player concern directly: a normal shop reroll should
not reroll upgrade offers. If a player saw both change at once, it was likely a
round/phase refresh or visual ambiguity rather than the card-shop reroll path.

The live report can now catch a future regression where these two reroll
surfaces accidentally become coupled.

## Next

Recommended H56: continue with small player-facing ambiguity fixes from the
same playtest cluster. The best candidate is likely compact merge-history
treatment: either remove the sticky one-line merge toast after it has served its
purpose or expose a real recent-merge history panel, since the current behavior
can look stale.
