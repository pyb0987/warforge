# 083 — Terminal Result Clarity

Date: 2026-07-30

## Goal

Make the terminal overlay explain the end of a run well enough that a player can
see what happened, instead of only seeing the final round number.

## Context

H85 proved a fresh-profile visible-control playthrough can reach a real terminal
overlay, but the natural run ended in defeat at R8. The overlay only said
`Defeated at round 8`, which was too thin for a completion-oriented playtest:
the player could not see the final-fight survivor pressure, HP movement, or run
bests from the end screen itself.

## Change

Updated `GameOverPopup.show_result()` to accept optional terminal context and
render:

- final HP on defeat;
- final-fight ally/enemy survivors;
- final damage and HP transition;
- run-best stats: max field units, attached upgrades, best win streak, and boss
  reward count.

Updated `GameManager` terminal paths to pass final battle context and `_run_stats`
into the game-over/victory popup.

Updated tests:

- `test_game_over_popup.gd` now covers victory run-bests, defeat final HP, and
  final-fight context formatting.
- `test_game_manager_live_smoke.gd` now checks the real fatal battle path and
  visible-control terminal overlay for the richer result summary.

## Evidence

Focused popup test:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_over_popup.gd -glog=1 -gexit
```

Result:

```text
3/3 passed.
20 asserts.
```

Focused live smoke:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
```

Result:

```text
14/14 passed.
955 asserts.
```

Observed visible-control path still reached a natural R8 defeat and the terminal
summary included final HP, final fight, damage, and run bests.

Headless live UI report:

```text
/usr/bin/env HOME=/private/tmp/warforge_h87_report_home godot --headless --log-file /private/tmp/warforge_h87_live_ui_report.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h87_live_ui_report.json --commander=gambler --talisman=flint --unlock-selected=true
python3 scripts/summarize_live_ui_report.py --report /private/tmp/warforge_h87_live_ui_report.json --out /private/tmp/warforge_h87_live_ui_report_summary.md
```

Result:

```text
Verdict: PASS
Report OK: yes
Run-end text includes: Run bests: 120 field units, 16 upgrades, 8-win streak, 1 boss reward
```

The Godot process still printed the known post-completion ObjectDB/resource
warnings after writing a passing report.

## Protected Boundary

No `godot/sim/**` files were edited.

## Decision

ADOPT.

The end screen now carries enough run-result evidence for the player and future
live smokes to reason about why the run ended.

## Next

Checkpoint H79-H87 soon. A useful next slice is to use the terminal summary and
visible-control evidence to choose a player-facing next-run orientation, or to
fix the first concrete late-run blocker found by play.
