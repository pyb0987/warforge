# 123 - H125 Druid Offense Causal Split

Date: 2026-07-31
Status: DONE - gameplay packet deferred

## Purpose

Decide whether H124's Druid offense-access signal justifies an immediate
AI-side promotion/access packet, or whether one more behavior-neutral causal
split is needed first.

## Multi-Review

Decision under review:

```text
Implement a Druid-only AI promotion rule in R9-R11 that pairs active Spore with
benched Wrath/World, or active Wrath/World with benched Spore, using existing
path-focus replacement/value guards.
```

Critic A, activation-packet scope:

```text
score: 7
verdict: conditional_go_for_packet_design_not_adoption
finding: meaningfully different from H100 only if it is complementary-pair
targeted, not duplicate-current-focus activation.
gate: adoption must be computed from outcomes, not pair counts.
```

Critic B, measurement/adoption gates:

```text
score: 6
verdict: VETO_CURRENT_GATESET_GO_AFTER_STRENGTHENING
finding: H125 must not pass on active Spore+Wrath/World pairing alone.
required: same-seed nomination plus disjoint confirmation, with clear/HP/focus
WR/survivor-margin gates.
```

Critic C, frame challenge:

```text
score: 6
verdict: CONDITIONAL_NO_GO_FOR_GAMEPLAY_PATCH
finding: H124 supports an offense-package question, not yet an activation patch.
missing split: acquisition vs activation vs runtime contribution.
recommendation: add behavior-neutral causal split first.
```

Synthesis:

```text
NO_GO_IMMEDIATE_GAMEPLAY_PATCH
Proceed with H125A causal split only.
```

## Tooling Added

Added `--druid-offense-causal-split` to `scripts/analyze_ai_trace.py`.

The report classifies R9-R11 Druid focus-active losses by:

- Missing target: offense, Spore, or none.
- Access bucket: active pair, owned inactive, bought not owned, offered not
  bought, offered unaffordable, or not seen/unavailable.
- Timing bucket: stable, danger, lethal, or unknown.
- Primary causal bucket: active too late, owned inactive, offered/not seen,
  active pair under-damaging, active pair mixed, or mixed/unknown.

It also adds a baseline comparison for causal-bucket deltas.

## H104 Current-Baseline Read

Command:

```text
python3 scripts/analyze_ai_trace.py \
  /private/tmp/warforge_h104_clean_druid60_traces \
  --strategy=soft_druid \
  --druid-offense-causal-split \
  --druid-offense-ledger \
  --druid-activation-audit
```

Key output:

```text
R9-R11 focus-active: 81 frames, 53 losses
Spore+offense frames/losses: 18 / 13
active-pair under-damage: 2
shortfall no-pair / with-pair: 0 / 1
owned-inactive: 5
offered-not-bought: 1
not-seen/unavailable: 19
active-too-late: 9
primary causal buckets:
  not_seen_or_unavailable 15
  active_pair_mixed 10
  offered_unaffordable 11
  active_too_late 9
  active_pair_under_damaging 2
  owned_inactive 4
next signal: ACQUISITION_PACKET_CANDIDATE
```

Current baseline interpretation:

- An immediate promotion packet is not the cleanest current-state target.
- The largest current causal bucket is missing/unavailable pair pieces, not
  owned-inactive pair pieces.
- Current active-pair failures mostly still look like debuff gaps, not proven
  Wrath/World damage math.

## H123 Rejected-Probe Read vs H104

Command:

```text
python3 scripts/analyze_ai_trace.py \
  /private/tmp/warforge_h123_h105_spore_forest60_traces \
  --strategy=soft_druid \
  --druid-offense-causal-split \
  --druid-offense-ledger \
  --druid-activation-audit \
  --druid-compare-baseline=/private/tmp/warforge_h104_clean_druid60_traces
```

Key output:

```text
H123 causal split:
  Spore+offense frames/losses: 18 / 11
  active-pair under-damage: 7
  shortfall no-pair / with-pair: 9 / 7
  owned-inactive: 3
  offered-not-bought: 1
  not-seen/unavailable: 18
  active-too-late: 10
  next signal: ACQUISITION_PACKET_CANDIDATE

H123 vs H104 comparison:
  pair frames/losses: 18 -> 18 / 13 -> 11
  owned-inactive delta: -2
  not-seen/unavailable delta: -1
  active-pair under-damage delta: +5
  active-too-late delta: +1
  shortfall without pair delta: +9
  shortfall with pair delta: +6
  loss enemy: 13.8 -> 14.2
  next signal: PAIR_RUNTIME_MATH_CANDIDATE
```

Rejected-probe interpretation:

- The H123 Spore debuff repair did not create more active pairing; pair frames
  stayed flat at 18.
- It converted debuff gaps into damage shortfall both without and with active
  pairs.
- Owned-inactive evidence weakened, so H125 should not implement a promotion
  packet from this evidence.
- The next missing evidence is combat contribution: what Wrath/World actually
  contribute when Spore+offense is active and still loses.

## Decision

Do not implement the H125 gameplay promotion packet now.

Next aligned slice:

```text
H126 Druid combat contribution observability
```

The likely next tool should add trace-only battle snapshots that expose active
card star, trees, unit count, total ATK/HP/AS, and focus-pair status before
combat. That would let the analyzer distinguish:

- Pair exists but Wrath/World has too few units.
- Pair exists but Wrath/World buffs are capped/too small.
- Pair exists but Spore/debuff/survival remains the actual problem.
- Pair arrives too late to matter.

Because this probably touches `godot/sim/headless_runner.gd`, it should be
treated as a fresh file-scope approval packet before editing.

## Verification

PASS analyzer tests:

```text
python3 -m unittest scripts.tests.test_analyze_ai_trace
Ran 26 tests
OK
```

PASS syntax:

```text
python3 -m py_compile scripts/analyze_ai_trace.py
```

PASS focused AI baseline before gameplay decision:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit
44/44 passed
```

PASS H105 boundary before H125 edits:

```text
python3 scripts/check_h105_spore_forest_boundary.py --allow-records
Result: PASS
Checked files: 0
```

## Forbidden Follow-Up

- Do not retry H123's exact Spore forest-depth debuff-only shape.
- Do not implement the H100 duplicate-focus activation shape.
- Do not use pair counts, activation counts, same-seed local WR, or prose PASS
  as adoption evidence.
- Do not edit card YAML, generated DB, difficulty, or economy files for this
  line without new evidence and explicit scope.
