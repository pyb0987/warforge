# 085 — Post-Defeat Next-Run Orientation

Date: 2026-07-30

## Goal

Make a real defeat screen tell the player one useful thing to try next, using
the terminal evidence already gathered by H87.

## Context

H85 proved a fresh-profile visible-control playthrough can reach a real terminal
overlay through normal UI controls and real battles. The current natural run
still loses at R8. H87 made that terminal overlay show final HP, final-fight
survivors, damage, and run bests, but it still stopped short of answering the
player's likely next question: what should I try differently?

H88 refreshed broad verification and made the stack checkpoint-ready. That green
status is permission to proceed, not proof of product completion.

## Multi-Review

Decision: choose the next completion-oriented slice after H88.

Critics:

- Player-completion critic, score 9: choose player-facing work from the current
  visible-control R8 defeat evidence. If no sharper blocker appears, add
  post-defeat next-run orientation.
- Scope/protected-boundary critic, score 8: choose a narrow unprotected defeat
  orientation slice now; keep H78 deferred until explicit protected simulator
  approval.
- Verification/observability critic, score 8: current evidence is sufficient to
  support player-facing UI work, but not to claim whole-game balance or H78
  completion.
- Review-quality meta-critic, score 6: revise the decision frame before acting.
  Do not choose work because tests are green; require a blocker tied to current
  play evidence.

Revised frame:

The current blocker is that the freshest natural visible-control play evidence
ends in an R8 defeat. After H87 the player can see what happened, but not what to
try next. H89 should reduce that specific player-learning gap without touching
balance, card data, difficulty, economy, combat logic, or protected
`godot/sim/**` files.

## Change

`GameOverPopup` now adds one defeat-only line after run bests:

```text
Next run: ...
```

When final-battle survivor context exists, the hint names the enemy survivor
pressure and the next pressure milestone:

```text
Next run: last fight left 19 enemies; add damage or growth before the R8 boss.
```

When no final-battle context exists, the hint falls back to upgrade/milestone
context:

```text
Next run: attach upgrades before the R4 boss.
```

Victory screens intentionally omit the next-run hint.

## Evidence

Focused popup test:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_over_popup.gd -glog=1 -gexit
```

Result:

```text
4/4 passed.
24 asserts.
```

Focused live smoke:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
```

Result:

```text
14/14 passed.
957 asserts.
```

The visible-control playthrough still naturally reached a defeat at R8, and the
test now asserts the terminal overlay contains a `Next run:` cue on defeat.

Headless live UI report:

```text
/usr/bin/env HOME=/private/tmp/warforge_h89_report_home godot --headless --log-file /private/tmp/warforge_h89_live_ui_report.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h89_live_ui_report.json --commander=gambler --talisman=flint --unlock-selected=true
python3 scripts/summarize_live_ui_report.py --report /private/tmp/warforge_h89_live_ui_report.json --out /private/tmp/warforge_h89_live_ui_report_summary.md
```

Result:

```text
Verdict: PASS
Report OK: yes
```

Python summary/matrix tests:

```text
python3 -m unittest scripts.tests.test_summarize_live_ui_report scripts.tests.test_run_live_ui_identity_matrix -q
```

Result:

```text
Ran 45 tests in 0.047s
OK
```

Card-spawn guard:

```text
python3 scripts/lint_card_spawn.py
```

Result: exited 0 with no output.

Full GUT:

```text
/usr/bin/env HOME=/private/tmp/warforge_h89_fullgut_home godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
```

Result:

```text
Scripts              57
Tests              1278
Passing Tests      1278
Asserts            8904
---- All tests passed! ----
```

Whitespace/conflict guard:

```text
git diff --check
```

Result: exited 0.

Protected simulator boundary:

```text
git status --short -- godot/sim
```

Result: no output.

## Log Notes

Full GUT printed the same macOS certificate probe line at startup and expected
negative-path diagnostics from invalid card and revive-scope tests. The
command-line live UI report still printed the known ObjectDB/resource warning
after writing a passing report.

## Decision

ADOPT.

The terminal defeat screen now gives the player a concise, evidence-based next
run cue. This moves the current visible-control defeat from "what happened" to
"what to try next" without changing game balance.

## Protected Boundary

No `godot/sim/**` files were edited. H78 remains gated on explicit protected
simulator approval.

## Next

Checkpoint the current H79-H89 stack soon. After that, choose between deeper
natural-run coverage for more identities and the protected H78 Druid probe if
the user explicitly approves simulator edits.
