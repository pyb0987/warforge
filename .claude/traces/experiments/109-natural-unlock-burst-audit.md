# 109 - Natural Unlock Burst Audit

Date: 2026-07-31
Status: DONE - watch item refreshed, no progression change

## Purpose

Refresh the replay/meta clarity watch item with current evidence. The user had
previously observed that a single run could unlock more than ten items, and
H111 left unlock burst pacing as acceptable but worth revisiting if manual play
felt overwhelming.

This audit does not change unlock thresholds, actual unlock availability, UI,
or gameplay. It records whether the current observer still sees burst pressure
now that sell counts are trace-observable.

## Source State

- Branch: `main`
- Commit: `2d9a8d43369764356beabf71c6f0717186e62670`
- Dirty state during self-play: clean

## Fresh Self-Play Evidence

Command:

```text
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h112_unlock35 \
  godot --headless --log-file /private/tmp/warforge_h112_unlock35.log \
  --path godot/ -s tools/self_play_observer.gd -- \
  --runs=5 --strategies=all --difficulty=1 \
  --commander=gambler --talisman=flint \
  --seed=20260731112 \
  --out=/private/tmp/warforge_h112_unlock35.json \
  --quiet-progress=true
```

Summary command:

```text
python3 scripts/summarize_self_play_report.py \
  --report=/private/tmp/warforge_h112_unlock35.json \
  --out=/private/tmp/warforge_h112_unlock35_summary.md
```

Validation:

```text
python3 -m json.tool /private/tmp/warforge_h112_unlock35.json
rg -n "SCRIPT ERROR|Compile Error|ERROR: Failed|ObjectDB|Resource still" \
  /private/tmp/warforge_h112_unlock35.log
```

Result:

- PASS JSON parse.
- PASS summary generation.
- PASS log guard: no script/compile/failure/ObjectDB/resource matches.

Key self-play summary:

- 35 D1 runs, 5 per strategy.
- 17/35 clears, 48.6% clear rate.
- Completion readiness status: `watch`.
- R4/R8/R12 reward application remained reliable for eligible runs:
  35/35, 25/25, and 22/22.
- Unlock projection status: `complete`.
- Runs with projected unlocks: 30/35.
- Runs with projected deferred unlocks under the UI cap: 24/35.
- Largest raw single-run projection: 11 unlocks.
- Largest deferred count under the 3-item reveal cap: 8.
- Alert: `possible_unlock_burst`.

Largest projected runs:

```text
#23 adaptive: raw 11, reveal 3, defer 8, clear R15
#33 aggressive: raw 11, reveal 3, defer 8, clear R15
#0 soft_steampunk: raw 10, reveal 3, defer 7, clear R15
```

The strongest burst examples hit several unrelated metrics at once: clear
reward, field units, upgrade count, win streak, card sales, growth events,
star-2 cards, unit-advantage wins, and upgrade-count talismans. This means a
single numeric threshold bump would not address the whole burst shape.

## Advisory Multi-Review

Used advisory multi-review because progression pacing changes affect the
player's reward contract.

Critic results:

- Player progression pacing: `KEEP_UI_ONLY_REVEAL_CAP_NOW`, score 8/10.
  - Burst pressure is real enough to watch.
  - Do not raise actual thresholds from headless projection alone.
  - Do not add a pending unlock queue without playtest evidence that the capped
    recap still feels overwhelming.
- Implementation/testing risk:
  `NO_UNLOCK_QUEUE_NOW_THRESHOLD_TUNE_ONLY_IF_PLAYTEST_CONFIRMS`, score 9/10.
  - Threshold changes are contained but must update `MetaProgress`, observer
    mirror constants, docs, and parity tests together.
  - A queue would contradict the current documented contract that overflow
    unlocks are immediately available in `PROGRESS`.
- Completion roadmap priority:
  `NO_GO_UNLOCK_PACING_CODE_RECORD_H112_AND_PRESERVE_H105`, score 9/10.
  - Unlock pacing is still a watch item, not the current M1 blocker.
  - H105 remains the next meaningful gameplay work once its runtime/test files
    are explicitly approved.

## Decision

ADOPT as a readiness/watch audit only.

Do not change unlock thresholds yet. Do not add a pending unlock queue. Keep the
current UI-only reveal cap: show three recent unlocks, summarize overflow, and
make all earned content immediately available in `PROGRESS`.

Carry forward:

- If manual/live play says the recap still feels overwhelming, use this H112
  evidence to tune thresholds deliberately across `MetaProgress`, observer
  constants, tests, and replay docs.
- Otherwise, H105 remains the next completion-critical gameplay implementation
  once the protected Druid runtime/test files are approved.
