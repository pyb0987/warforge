# 122 - H124 Druid Offense Conversion Analysis

Date: 2026-07-31
Status: DONE - analyzer-first routing completed

## Purpose

Turn the H123 rejected Spore forest-depth probe into a sharper causal routing
decision before preparing another protected gameplay packet.

H123 proved that debuff-only Spore forest-depth routing moved local optics, but
missed the adoption gates: clears were too low, allied survivors stayed flat,
and enemy survivor margin worsened.

## Scope

Behavior-neutral tooling and records only:

- `scripts/analyze_ai_trace.py`
- `scripts/tests/test_analyze_ai_trace.py`
- `.claude/traces/experiments/122-h124-druid-offense-conversion-analysis.md`
- `Plans.md`

The user explicitly approved Druid runtime and focused test files, but this
slice did not edit protected gameplay/runtime files.

## Tooling Added

Added `--druid-offense-ledger` to `scripts/analyze_ai_trace.py`.

The ledger separates R9-R11 Druid focus-active frames by:

- Wrath/World offense presence.
- Spore plus offense pairing.
- Damage-shortfall losses with and without Wrath/World online.
- Debuff-gap losses.
- Ally/enemy survivor margins.

Trace caveat: current battle traces expose survivors and aggregate card-id
states, not per-unit attack contribution.

## H123 vs H104 Result

Command:

```text
python3 scripts/analyze_ai_trace.py \
  /private/tmp/warforge_h123_h105_spore_forest60_traces \
  --strategy=soft_druid \
  --druid-offense-ledger \
  --druid-compare-baseline=/private/tmp/warforge_h104_clean_druid60_traces
```

Key output:

```text
R9-R11 focus frames: 81 -> 82
WR: 34.6% -> 42.7%
Damage shortfall: 1 -> 16
Damage shortfall share: 1.9% -> 34.0%
Shortfall with offense: 1 -> 7
Shortfall without offense: 0 -> 9
Debuff gaps: 45 -> 14
Loss enemy survivors: 13.8 -> 14.2
```

Candidate ledger:

```text
offense frames 49
offense losses 31
no-offense losses 16
Spore+offense frames 18
damage shortfall 16/47 losses
with offense 7
without offense 9
avg shortfall enemy survived 14.7
```

Offense combo split in H123:

```text
none: frames 33, wins 17, losses 16, shortfall 9
dr_wrath: frames 34, wins 12, losses 22, shortfall 6
dr_world: frames 12, wins 5, losses 7, shortfall 1
dr_world+dr_wrath: frames 3, wins 1, losses 2, shortfall 0
```

Analyzer signal:

```text
DEBUFF_REPAIR_EXPOSED_OFFENSE_ACCESS: the rejected probe reduced debuff gaps
but converted many losses into damage shortfall; route next work through
offense access/activation evidence.
```

## Interpretation

H123 did not prove Wrath/World raw battle math is the primary next patch. It
proved the debuff-only repair exposed an offense gap, but most newly visible
damage-shortfall losses still lack Wrath/World in the active focus set.

That changes the next hypothesis from:

```text
Buff Spore/debuff or raw Wrath/World values.
```

to:

```text
Make Druid's late payoff package convert into active Spore+Wrath/World combat
presence earlier and measure whether clear-rate and survivor margins move.
```

Any next gameplay packet should therefore be access/activation-shaped and
bounded. It should not retry H123's exact Spore forest-depth debuff-only shape.

## Next Packet Requirements

Before protected implementation:

- Define whether the packet touches AI purchase/promotion, Druid runtime logic,
  or both.
- Keep card YAML/generated DB/difficulty/economy files out of scope unless a
  new approval explicitly broadens scope.
- Gate adoption on same-seed clear movement, avg HP, R9-R11 focus WR, and
  active-loss survivor margin.
- Reject if it only increases active/offense counts without clear-rate or
  survivor-margin movement.

## Verification

PASS Python analyzer tests:

```text
python3 -m unittest scripts.tests.test_analyze_ai_trace
Ran 24 tests
OK
```

PASS syntax check:

```text
python3 -m py_compile scripts/analyze_ai_trace.py
```

## Decision

ADOPT diagnostic tooling and record.

Next slice should prepare a narrow Druid offense access/activation packet with
explicit gates, then use multi-review before protected gameplay edits.
