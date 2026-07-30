# Experiment 099 - Source-Bound Self-Play Evidence

Date: 2026-07-30
Status: DONE

## Decision

Add source-state binding to self-play observer evidence before the next Druid
combat-conversion probe.

H100 showed a false-green risk: focused tests and a generic self-play summary
can look healthy while the same-seed trace evidence is flat. Future self-play
screens should carry the source state that generated them, so a surprising or
flat result can be tied back to the exact commit and dirty files.

## Scope

Changed unprotected observability surfaces only:

- `godot/tools/self_play_observer.gd`
- `scripts/summarize_self_play_report.py`
- `scripts/tests/test_summarize_self_play_report.py`
- `docs/tools/self-play-observer.md`

No protected gameplay surfaces, card values, difficulty values, economy values,
or generated card database files were changed.

## Implementation

The self-play observer now adds `metadata.source_state` to generated JSON:

- `available`
- `vcs`
- `root`
- `commit`
- `branch`
- `dirty`
- `status_short`

The Git status is captured relative to the repository root. Local
`.claude/settings.local.json` is filtered out because temporary-HOME observer
runs can otherwise make clean evidence appear dirty due to machine-local config.

The completion summary now renders a `Source State` section:

- current reports show abbreviated commit, branch, clean/dirty status, and
  changed-file count;
- legacy reports without `metadata.source_state` still summarize, but clearly
  say source state was not recorded;
- malformed `metadata.source_state` marks the summary incomplete.

## Verification

Focused Python summary tests:

```text
python3 -m unittest scripts.tests.test_summarize_self_play_report

Ran 5 tests in 0.003s
OK
```

Python compile check:

```text
python3 -m py_compile scripts/summarize_self_play_report.py \
  scripts/tests/test_summarize_self_play_report.py

PASS
```

Focused Godot observer logic tests:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/test_self_play_observer.gd -glog=1 -gexit

9/9 passed
```

Tiny observer smoke:

```text
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h101_source_state_3 \
  godot --headless --log-file /private/tmp/warforge_h101_source_state_3.log \
  --path godot/ -s tools/self_play_observer.gd -- \
  --runs=1 --strategies=adaptive --difficulty=1 \
  --commander=gambler --talisman=flint \
  --seed=2026073003 \
  --out=/private/tmp/warforge_h101_source_state_3.json \
  --quiet-progress=true

PASS: report contains metadata.source_state with commit
a92db5ee4bed2d859a4b05fce1df43b2f26725aa, branch main, dirty true, and
root-relative changed files:
- docs/tools/self-play-observer.md
- godot/tools/self_play_observer.gd
- scripts/summarize_self_play_report.py
- scripts/tests/test_summarize_self_play_report.py

PASS: machine-local .claude/settings.local.json did not appear in status_short.
```

Summary render check:

```text
python3 scripts/summarize_self_play_report.py \
  --report=/private/tmp/warforge_h101_source_state_3.json \
  --out=/private/tmp/warforge_h101_source_state_3_summary.md

PASS: summary renders Source State.
```

Other guards:

```text
python3 scripts/lint_card_spawn.py
git diff --check
```

Both passed.

## Next Slice

H101 does not make the Druid strategy floor green. It makes the next evidence
screen harder to misread.

The next gameplay-completion slice remains Druid R9-R11 combat conversion,
especially Spore pressure/debuff conversion:

- H100 active battle ledger: R9-R11 focus-active WR 34.6%.
- Primary bottleneck: `debuff_too_small` in 30 frames.
- Before touching protected `godot/sim/**`, card values, difficulty, or
  economy tuning, request fresh approval and prepare a narrow adoption gate.
