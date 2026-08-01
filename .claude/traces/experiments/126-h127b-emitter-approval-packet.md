# 126 - H127B Druid Snapshot Emitter Approval Packet

Date: 2026-08-01
Status: READY - HOLD for explicit protected-file approval

## Purpose

H126 added a read-only Godot Druid combat snapshot contract.
H127A added the analyzer consumer and proved current self-play traces fail
honestly with:

```text
snapshot coverage: 0/129
missing focus snapshots: 81
invalid snapshots: 0
next signal: SNAPSHOT_EMISSION_REQUIRED
```

Post-packet analyzer hardening also rejects wrong scalar types: non-string IDs,
non-finite numbers, booleans in numeric fields, non-integer counters, and
stringified numeric combat fields no longer count as valid H126 evidence.

H127B is the next wiring step: emit real H126 snapshots from headless battle
trace events so Druid Spore + Wrath/World losses can be attributed from
self-play evidence before any further gameplay packet.

## Current Boundary

No protected files were edited while preparing this packet.

Current explicit approval does not include:

- `godot/sim/headless_runner.gd`
- `godot/tests/test_headless_runner.gd`

Therefore H127B must stay on hold until the user explicitly approves those two
files.

## Requested Approval

Approve editing exactly:

- `godot/sim/headless_runner.gd`
- `godot/tests/test_headless_runner.gd`

Record-only follow-up may update:

- `Plans.md`
- `docs/tools/self-play-observer.md`
- `.claude/traces/experiments/126-h127b-emitter-approval-packet.md`

Do not edit for minimal H127B:

- `godot/sim/ai_agent.gd`
- `godot/tests/test_ai_agent.gd`
- `godot/core/druid_system.gd`
- `godot/tests/test_druid_system.gd`
- `godot/tests/test_chain_engine.gd`
- `godot/tools/self_play_observer.gd`
- `scripts/analyze_ai_trace.py`
- card YAML
- generated card DB
- evaluator, combat engine, economy, or difficulty files

## Intended Implementation

In `godot/sim/headless_runner.gd`, capture the snapshot only for trace-enabled
runs, and only as battle-event payload data.

Seam:

- after `chain_engine.process_persistent(active_board)`
- after `chain_engine.process_battle_start(active_board)`
- after boss reward, commander, and talisman combat temp buffs
- after `chain_engine.apply_enemy_battle_debuffs(active_board, enemy_data)`
- before `clear_temp_buffs()` and `shield_hp_pct = 0.0`

Implementation shape:

```text
var druid_combat_snapshot := {}
if _tracer != null and _tracer.enabled:
    druid_combat_snapshot = DruidSystem.new().build_combat_snapshot(active_board)
```

Then attach the captured dictionary to the later `battle` trace event as:

```text
"druid_combat_snapshot": druid_combat_snapshot
```

when the snapshot has at least one Druid card. The emission must not change
gameplay values, RNG flow, combat setup/tick loop, evaluator `round_data`,
settlement, AI decisions, card data, economy, or difficulty behavior.

## Required Test Shape

Add a focused `test_headless_runner.gd` tracer test that proves more than field
presence:

- battle trace event uses canonical key `druid_combat_snapshot`.
- snapshot is H126-shaped with top-level `forest_depth`, `druid_count`,
  `druid_units`, totals, `enemy_debuffs`, and `cards`.
- Spore aggregate debuffs appear in both `snapshot.enemy_debuffs` and the Spore
  card row.
- Wrath/World offensive rows include nonzero units, ATK/HP/DPS, stacks, and
  `final_attack_interval`.
- timing guard proves the snapshot was captured before `clear_temp_buffs()` and
  shield cleanup.
- tracer-on vs tracer-off same-seed core result metrics remain unchanged.

If a direct full-run fixture is too brittle, add a tiny runner-local trace helper
and test it with a controlled Druid board while still using `AITracer` as the
emission sink. The helper must be called by the real run path.

## Verification After Approval

Minimum commands:

```bash
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/test_headless_runner.gd -glog=1 -gexit

godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/test_druid_system.gd -glog=1 -gexit

python3 -m unittest scripts.tests.test_analyze_ai_trace

python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h127b_traces \
  --strategy=soft_druid \
  --druid-contribution-ledger

git diff --check
```

Expected trace result after fresh H127B self-play traces:

- nonzero valid snapshot coverage.
- zero invalid focus snapshots.
- `--druid-contribution-ledger` no longer reports
  `SNAPSHOT_EMISSION_REQUIRED` for Druid focus battles.

Full GUT is recommended before calling the slice complete because the edit is
inside the headless simulator path.

Boundary guard:

```bash
python3 scripts/check_h127b_emitter_boundary.py --allow-records
```

This guard was added after packet creation and must pass before H127B is closed.

## Multi-Review Summary

Critic A - Completion Routing:

- Score 9.
- Verdict: PASS_WITH_CONDITIONS.
- Finding: H127B remains the next honest M1 step. Easier unprotected work would
  not move the strategy viability floor because H127A proved contribution
  evidence is missing from current traces.

Critic B - Protected Boundary:

- Score 8.
- Verdict: CONDITIONAL PASS, HOLD until explicit approval names the two runner
  files.
- Finding: minimal implementation surface is exactly the emitter and focused
  runner test. Capture before cleanup; do not edit AI, runtime gameplay, card
  data, evaluator, economy, or difficulty files.

Critic C - Evidence/Test Adequacy:

- Score 4 for the initial loose proof shape.
- Verdict: insufficient as stated until H127B has a Godot emitter test observing
  a real `AITracer` battle event with a pre-cleanup H126 snapshot.
- Packet updated to include semantic snapshot assertions, timing guard, and
  tracer-on/off side-effect guard.

## Decision

Request approval for the two H127B files above.

Do not continue to balance tuning, AI promotion, Spore scaling, raw offense
buffs, analyzer masking, or easier unrelated polish until either:

- H127B is approved and implemented, or
- the user explicitly chooses a different completion track.
