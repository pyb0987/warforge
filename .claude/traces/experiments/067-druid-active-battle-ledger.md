# Experiment 067 — Druid Active Battle Ledger

Date: 2026-07-29
Status: DONE - analyzer adopted; no gameplay changes

## Question

After H70 rejected the Lifebeat all-Druid shield reach probe, should the next
Druid slice tune card numbers immediately, or first add a sharper combat-margin
ledger for R9-R11 focus-active losses?

## Review Synthesis

Used multi-review because the next step affected the balance workflow.

- Design/balance critic: choose observability first. H67 already showed generic
  AI activation/purchase variants can regress, and H70 showed a narrow
  survivability probe can improve HP slightly while preserving the real failure
  shape.
- Measurement critic: current evidence was insufficient for another card-number
  adoption. Required a Druid active-battle effect ledger with enough R9-R11
  focus-active samples before the next gameplay probe.
- Implementation critic: safest H71 surface is Python-only analyzer/test work in
  `scripts/analyze_ai_trace.py` and `scripts/tests/test_analyze_ai_trace.py`.
  Avoid YAML and GDScript AI changes in this slice.

Decision: add a behavior-neutral analyzer mode.

## Implementation

Added `--druid-active-ledger` to `scripts/analyze_ai_trace.py`.

The ledger scopes to R9-R11 Druid focus-active battle frames and reports:

- focus card combo, path, star/tree state, active Druid/neutral counts, total
  active tree counters, enemy debuff value, ally/enemy survivors, and examples.
- primary loss bottlenecks with exactly one label per loss:
  `debuff_too_small`, `debuff_missing`, `enemy_pressure_spike`,
  `damage_shortfall`, `near_miss_survivability`, `board_mass_shortfall`,
  `tree_depth_shortfall`, or `mixed_margin`.
- aggregation by focus combo, by focus card, and by detected path.
- a next-signal sentence for the dominant bottleneck.

Added unit coverage for R9-R11 inclusion, classification stability, coverage
fields, focus-combo aggregation, and by-card bucket aggregation.

## 30-Run Smoke on Existing Baseline

Command:

```bash
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h70_baseline_druid_30_traces --strategy=soft_druid --druid-active-ledger
```

Result:

- R9-R11 focus-active frames: 40, below the review sample-strength gate.
- Losses: 26, below the gate of 30 focus-active losses.
- Coverage: detail/star/tree 100%.
- Primary bottlenecks: `debuff_too_small` 15, `enemy_pressure_spike` 5,
  `debuff_missing` 4, `damage_shortfall` 1, `board_mass_shortfall` 1.
- Next signal: Spore is present but under-moving enemy pressure.

Because the 30-run sample was undersized for H71 acceptance, a larger baseline
was run without gameplay changes.

## 60-Run Evidence

Command:

```bash
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h71_ledger60 godot --headless --log-file /private/tmp/warforge_h71_ledger60_druid.log --path godot/ -s tools/self_play_observer.gd -- --runs=60 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=flint --seed=2026072901 --out=/private/tmp/warforge_h71_ledger60_druid.json --trace-dir=/private/tmp/warforge_h71_ledger60_druid_traces --quiet-progress=true
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h71_ledger60_druid_traces --strategy=soft_druid --druid-active-ledger
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h71_ledger60_druid_traces --strategy=soft_druid --druid-loss-buckets
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h71_ledger60_druid_traces --strategy=soft_druid --druid-battle-conversion
python3 scripts/summarize_self_play_report.py --report /private/tmp/warforge_h71_ledger60_druid.json --out /private/tmp/warforge_h71_ledger60_druid_summary.md
```

Completion result:

- Clears: 9/60 (15.0%).
- Average final HP: -4.23.
- Average rounds reached: 11.07.
- Loss rounds: R9 x13, R10 x13, R11 x9.
- Boss reward application remained clean for eligible runs:
  R4 58/58, R8 28/28, R12 9/9.

Ledger result:

- R9-R11 focus-active frames: 81.
- Results: 28 wins / 53 losses, 34.6% WR.
- Coverage: detail 100%, star 100%, tree 100%, missing round_end 0.
- Primary bottlenecks:
  - `debuff_too_small`: 30/53 losses.
  - `debuff_missing`: 15/53 losses.
  - `enemy_pressure_spike`: 6/53 losses.
  - `damage_shortfall`: 1/53 losses.
  - `board_mass_shortfall`: 1/53 losses.
- Focus combo highlights:
  - `dr_spore_cloud`: 32 frames, 12 wins / 20 losses, loss enemy survivors 13.1,
    average debuff 15.5%, buckets mostly `debuff_too_small`.
  - `dr_spore_cloud+dr_wrath`: 13 frames, 5 wins / 8 losses, loss enemy survivors
    13.2, buckets all `debuff_too_small`.
  - `dr_wrath`: 21 frames, 6 wins / 15 losses, loss enemy survivors 14.5,
    mostly `debuff_missing` or `enemy_pressure_spike`.
- Path highlights:
  - `druid_garden`: 49 frames, 18 wins / 31 losses, mostly `debuff_too_small`.
  - `druid_world_tree`: 18 frames, 5 wins / 13 losses, worse WR and more pressure
    spikes, but still includes `debuff_too_small`.

Battle conversion cross-check:

- Full focus-active battles across all rounds: 130, with 58 wins / 72 losses,
  44.6% WR.
- Active loss survivors: 0.0 allies / 14.4 enemies.
- Spore-active battles: 71, 46.5% WR, debuff rate 100%.
- Wrath-active battles: 67, 40.3% WR, debuff rate 35.8%.

## Decision

Adopt the analyzer addition. H71 changed observability only and did not alter
gameplay behavior.

H71 also identifies the next gameplay probe more clearly:

- The dominant R9-R11 loss shape is not "Druid lacks any payoff." It is "Spore
  is active, usually at star 1 with about 15-16% debuff, and that debuff does
  not convert the fight."
- Secondary loss shape is Wrath or World/Wrath active without Spore debuff.
- The next card-data probe should therefore target Spore's early battle
  mitigation or Spore/Wrath pairing value, not Lifebeat reach or generic AI
  purchase/activation.

## Verification

- PASS `python3 -m py_compile scripts/analyze_ai_trace.py scripts/tests/test_analyze_ai_trace.py`.
- PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace` (14 tests after the ledger patch).
- PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace scripts.tests.test_summarize_self_play_report -q` (17 tests).
- PASS `git diff --check -- scripts/analyze_ai_trace.py scripts/tests/test_analyze_ai_trace.py`.

## Resume Note

Proceed to H72 as a measured Druid card-data probe. Recommended first candidate:
a narrow Spore Cloud star 1/2 mitigation probe, with the H71 ledger as the
primary same-seed readout and the H70/H71 gates preserved:

- same-seed 30-run clears at least 7/30 or focus-active WR >= 50%.
- active losses improve to allied survivors >= 0.5 or enemy survivors <= 10.0.
- if same-seed passes, confirm on disjoint seed before adoption.
- run cross-lane smoke before keeping any gameplay change.
