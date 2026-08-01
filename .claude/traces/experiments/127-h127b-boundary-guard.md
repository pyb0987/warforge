# 127 - H127B Boundary Guard

Date: 2026-08-01
Status: DONE - unprotected guard added

## Purpose

H127B is the next completion-critical observability step, but it requires
explicit approval for protected runner files. The multi-review approval packet
requires that the eventual patch stay trace-only:

- allow `godot/sim/headless_runner.gd`.
- allow `godot/tests/test_headless_runner.gd`.
- optionally allow record-only updates.
- reject AI policy, Druid runtime behavior, analyzer masking, observer
  aggregation, card data, generated DB, evaluator, combat, economy, and
  difficulty edits.

This slice turns that boundary into an executable check before the protected
implementation begins.

## Scope

Edited:

- `scripts/check_h127b_emitter_boundary.py`
- `scripts/tests/test_check_h127b_emitter_boundary.py`
- `Plans.md`
- `docs/tools/self-play-observer.md`
- `.claude/traces/experiments/126-h127b-emitter-approval-packet.md`
- `.claude/traces/experiments/127-h127b-boundary-guard.md`

Not edited:

- `godot/sim/headless_runner.gd`
- `godot/tests/test_headless_runner.gd`
- AI policy files
- Druid runtime/card data/generated DB
- evaluator, combat, economy, or difficulty files

## Verification

PASS focused guard tests:

```text
python3 -m unittest scripts.tests.test_check_h127b_emitter_boundary
Ran 7 tests
OK
```

PASS exact H127B files:

```text
python3 scripts/check_h127b_emitter_boundary.py \
  --changed-file godot/sim/headless_runner.gd \
  --changed-file godot/tests/test_headless_runner.gd
```

PASS exact H127B files plus records:

```text
python3 scripts/check_h127b_emitter_boundary.py --allow-records \
  --changed-file godot/sim/headless_runner.gd \
  --changed-file godot/tests/test_headless_runner.gd \
  --changed-file Plans.md \
  --changed-file .claude/traces/experiments/127-h127b-druid-trace-emitter.md
```

EXPECTED FAIL for analyzer/card-data drift:

```text
python3 scripts/check_h127b_emitter_boundary.py \
  --changed-file scripts/analyze_ai_trace.py \
  --changed-file data/cards/druid.yaml
```

Key output:

```text
Result: FAIL
scripts/analyze_ai_trace.py: analyzer masking is out of scope for H127B
data/cards/druid.yaml: card YAML is out of scope for H127B
```

## Decision

Use this guard in the H127B protected implementation verification:

```bash
python3 scripts/check_h127b_emitter_boundary.py --allow-records
```

The guard is not approval to edit protected files. It only makes the approved
boundary executable once approval exists.
