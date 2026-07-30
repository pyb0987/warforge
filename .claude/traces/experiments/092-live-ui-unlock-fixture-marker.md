# 092 - Live UI Unlock Fixture Marker

Date: 2026-07-30

## Goal

Resume from H95 with one bounded unprotected playability scout, then fix any
concrete M1-facing confusion it exposes without touching protected simulator
files.

## Scout

Ran the curated live UI identity matrices before editing:

```text
python3 scripts/run_live_ui_identity_matrix.py --preset=default --output-dir=/private/tmp/warforge_h96_live_matrix_default
python3 scripts/run_live_ui_identity_matrix.py --preset=expanded --output-dir=/private/tmp/warforge_h96_live_matrix_expanded
```

Result:

```text
default: PASS 4/4.
expanded: PASS 5/5.
```

The summaries confirmed that the current live UI answers the previous
player-facing feedback areas:

- commander/talisman identity is visible;
- Two-Faced Coin exposes discount and surcharge slots;
- card reroll and upgrade reroll remain separate;
- merge reward history is visible and the scripted merge economy did not create
  money.

The only suspicious-looking read was unlock overflow: each matrix row reported
10-12 raw unlocks with only 3 shown. Code inspection found this is not natural
progression evidence. The live report intentionally injects
`_overflow_unlock_run_stats()` to stress-test the capped recap and prove that
overflowed unlocks are still available in `PROGRESS`.

## Change

Marked that fixture explicitly:

- `godot/tools/live_ui_smoke_report.gd` now emits
  `events.unlock_recap.run_stats_source: "synthetic_overflow_fixture"` plus the
  scripted stats note and stats payload.
- `scripts/summarize_live_ui_report.py` validates that source marker and prints
  it in the human-readable "What Codex Saw" line.
- `scripts/tests/test_summarize_live_ui_report.py` covers both the rendered
  marker and the missing-marker failure case.
- `docs/tools/live-ui-smoke-report.md` warns that the unlock-overflow segment is
  a scripted fixture, not natural meta-progression pacing evidence.

## Evidence

Python summary/matrix tests:

```text
python3 -m unittest scripts.tests.test_run_live_ui_identity_matrix scripts.tests.test_summarize_live_ui_report
```

Result:

```text
46 tests OK.
```

Fresh live report:

```text
godot --headless --log-file /private/tmp/warforge_h96_marker_live.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h96_marker_live.json --commander=gambler --talisman=flint --unlock-selected=true --reset-meta=true --meta-path=user://warforge_h96_marker_live.cfg
```

Result:

```text
report ok: true.
run_stats_source: synthetic_overflow_fixture.
shown/raw/overflow unlocks: 3/12/+9.
```

Fresh summary:

```text
python3 scripts/summarize_live_ui_report.py --report=/private/tmp/warforge_h96_marker_live.json --out=/private/tmp/warforge_h96_marker_live_summary.md
```

Key line:

```text
Run-end unlock recap used synthetic_overflow_fixture stats; showed 3/12 unlocks and overflowed 9.
```

Fresh matrices after the marker change:

```text
python3 scripts/run_live_ui_identity_matrix.py --preset=default --output-dir=/private/tmp/warforge_h96_marker_matrix_default
python3 scripts/run_live_ui_identity_matrix.py --preset=expanded --output-dir=/private/tmp/warforge_h96_marker_matrix_expanded
```

Result:

```text
default: PASS 4/4.
expanded: PASS 5/5.
```

Focused live smoke:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
```

Result:

```text
18/18 passed.
1324 asserts.
```

Full GUT:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
```

Result:

```text
57 scripts.
1282/1282 passed.
9274 asserts.
```

Additional guards:

```text
python3 scripts/lint_card_spawn.py
git diff --check
git status --short -- godot/sim
```

Result:

```text
PASS card-spawn guard.
PASS whitespace/conflict guard.
PASS protected simulator boundary: no output.
```

## Decision

ADOPT.

This does not change progression thresholds. It prevents future autonomous
scouts from drawing the wrong pacing conclusion from a deliberately synthetic
unlock-overflow fixture.

## Next

H78 remains the direct M1 strategy-viability blocker and still requires explicit
approval before editing `godot/sim/ai_agent.gd`. If approval is not available,
the next unprotected work should use natural run/self-play artifacts rather than
the live report overflow fixture when evaluating unlock pacing.
