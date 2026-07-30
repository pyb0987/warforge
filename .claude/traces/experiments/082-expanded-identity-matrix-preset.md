# 082 — Expanded Identity Matrix Preset

Date: 2026-07-30

## Goal

Make the expanded special-commander live UI identity matrix reusable as a named
command instead of a long ad hoc list of repeated `--identity` rows.

## Context

H83 and H84 both used the same five-identity expanded matrix to prove special
commander behavior:

- `breeder=breeder:cracked_egg`
- `collector=collector:glass_eye`
- `strategist=strategist:war_drum`
- `smith=smith:rusty_wrench`
- `raider=raider:mercury_drop`

The matrix had become part of the completion workflow, but future runs still
had to reconstruct it by hand. The H84 multi-review observability critic called
this out as the next repeatability risk.

## Change

Updated `scripts/run_live_ui_identity_matrix.py`:

- added named presets `default` and `expanded`;
- added `--preset {default,expanded}` for runs without custom identities;
- recorded the selected preset in matrix metadata;
- included the preset in the Markdown matrix summary;
- kept repeated `--identity` rows as explicit custom replacements.

Updated `docs/tools/live-ui-smoke-report.md` to document:

- the default preset;
- the expanded preset command;
- custom identity replacement behavior.

## Evidence

Fast checks:

```text
python3 -m py_compile scripts/run_live_ui_identity_matrix.py scripts/tests/test_run_live_ui_identity_matrix.py
python3 -m unittest scripts.tests.test_run_live_ui_identity_matrix -q
python3 scripts/run_live_ui_identity_matrix.py --help
```

Result:

```text
10 tests OK.
Help shows --preset {default,expanded}.
```

Default preset:

```text
python3 scripts/run_live_ui_identity_matrix.py --output-dir=/private/tmp/warforge_h86_default_identity_matrix --out=/private/tmp/warforge_h86_default_identity_matrix/matrix.json --summary-out=/private/tmp/warforge_h86_default_identity_matrix/matrix.md --timeout-sec=90
```

Result:

```text
Verdict: PASS
Preset: `default`
Passing identities: 4/4
```

Expanded preset:

```text
python3 scripts/run_live_ui_identity_matrix.py --preset=expanded --output-dir=/private/tmp/warforge_h86_expanded_identity_matrix --out=/private/tmp/warforge_h86_expanded_identity_matrix/matrix.json --summary-out=/private/tmp/warforge_h86_expanded_identity_matrix/matrix.md --timeout-sec=90
```

Result:

```text
Verdict: PASS
Preset: `expanded`
Passing identities: 5/5
```

## Protected Boundary

No `godot/sim/**` files were edited.

## Decision

ADOPT.

The expanded special-commander coverage is now a stable workflow command:

```text
python3 scripts/run_live_ui_identity_matrix.py --preset=expanded
```

## Next

The H79-H86 stack is now a coherent checkpoint candidate. After checkpointing,
the next completion move should either address a real playability gap exposed by
visible-control/live matrix evidence, or return to H78 only if protected
simulator edits are explicitly approved.
