# Experiment 072 - Druid Run-Phase Survival Diagnostic

Date: 2026-07-29
Status: DONE - behavior-neutral analyzer adopted; no gameplay values changed

## Question

After H72, H73, and H75 rejected Spore/Wrath base-number probes, what evidence
is missing before choosing the next Druid completion move?

Specifically: are Druid payoff pieces absent, bought but inactive, active too
late, active without immediate combat swing, or active with a local swing that
still fails to stabilize the run?

## Review Synthesis

Used multi-review before implementation because this was a strategic pivot after
three rejected balance probes.

- Design critic: stop local Spore/Wrath value tuning. Treat "payoff active" as
  incomplete evidence unless the run reaches a usable payoff before lethal
  pressure.
- Measurement critic: bind payoff timing to HP-at-activation and immediate
  post-activation battle results. Avoid crediting ownership or active-board
  presence as conversion by itself.
- Implementation critic: keep the slice behavior-neutral and confined to the
  analyzer, analyzer tests, docs, Plans, and trace notes. Do not touch
  `godot/sim/**`, card YAML, generated card DB, combat/runtime, or AI scoring.

## Implemented Diagnostic

Added `--druid-run-phase` to `scripts/analyze_ai_trace.py`.

The report now derives, from existing trace JSONL only:

- First payoff offer, affordable, buy, payoff-active, focus-active, and
  both-payoff-active timing.
- HP at first payoff buy and first focus activation.
- Immediate pre/post activation battle outcomes.
- Exclusive conversion buckets:
  - `no_payoff_seen`
  - `offered_not_bought`
  - `bought_not_active`
  - `active_too_late`
  - `active_no_combat_swing`
  - `active_no_survival_swing`
  - `converted`
- R8-R12 survival curve: reached runs, battle WR, HP, focus/both-active rates,
  owned-but-inactive payoff rate, survivor margins, and path-lag skip counts.
- False-green examples where payoff/focus is active but the run dies before
  stabilizing.
- Baseline comparison output when combined with `--druid-compare-baseline`.

The comparison signal is intentionally subordinate to the older H74 probe
screen: a phase improvement is only a nomination and still needs the stricter
probe screen plus a disjoint seed before any adoption.

## Real-Trace Validation

Command:

```bash
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h75_coupled60_traces --strategy=soft_druid --druid-run-phase --druid-compare-baseline=/private/tmp/warforge_h71_ledger60_druid_traces
```

H75 run-phase read:

- Results: `10` wins / `50` losses.
- Conversion buckets:
  - `active_too_late`: `15`
  - `no_payoff_seen`: `10`
  - `converted`: `10`
  - `active_no_survival_swing`: `8`
  - `offered_not_bought`: `8`
  - `active_no_combat_swing`: `6`
  - `bought_not_active`: `3`
- Next signal: focus activation commonly happens in the lethal window; inspect
  timing, HP-at-activation, and economy pressure before more payoff tuning.
- All runs: offer/buy/active `83.3% / 70.0% / 66.7%`, both-active `13.3%`,
  average first buy `R9.4`, focus `R9.5`, HP at focus `21.4`,
  post-active WR `42.5%`.
- Losses: offer/buy/active `80.0% / 64.0% / 62.0%`, both-active `10.0%`,
  average focus `R9.5`, HP at focus `20.1`, post-active WR `25.8%`,
  dead within one round after activation `17/31`.
- Path split:
  - `druid_garden`: `3/30` wins, `active_too_late` `10`,
    `active_no_combat_swing` `5`, `no_payoff_seen` `7`.
  - `druid_world_tree`: `7/28` wins, `active_no_survival_swing` `7`,
    `active_too_late` `5`.
- R9-R12 path-lag holds: `132`, `76`, `37`, `20`.
- R10 loss survivor margin: ally `0.0`, enemy `14.8`.

H75 vs H71 run-phase comparison:

- Clears: `9/60 -> 10/60` (`+1`).
- Average HP: `-4.23 -> -3.45` (`+0.78`).
- Loss focus timing: `R9.4 -> R9.5`.
- Loss HP at focus: `20.2 -> 20.1`.
- Loss post-active WR: `18.8% -> 25.8%` (`+7.1pp`).
- Bucket deltas:
  - `converted`: `+1`
  - `active_too_late`: `-1`
  - `active_no_combat_swing`: `-2`
  - `active_no_survival_swing`: `+2`
  - `no_payoff_seen`: `0`
  - `offered_not_bought`: `0`
  - `bought_not_active`: `0`
- H74 screen verdict remains `WEAK_LOCAL_SIGNAL_DO_NOT_ADOPT`, so this is not
  adoption evidence for the rejected H75 card values.

## Verification

- PASS `python3 -m py_compile scripts/analyze_ai_trace.py scripts/tests/test_analyze_ai_trace.py`.
- PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace -q` (17 tests).
- PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace scripts.tests.test_summarize_self_play_report -q` (20 tests).
- PASS real-trace analyzer command against H75 candidate and H71 baseline.
- PASS `git diff --check -- scripts/analyze_ai_trace.py scripts/tests/test_analyze_ai_trace.py docs/tools/self-play-observer.md`.

## Decision

Adopt the analyzer-only H76 diagnostic.

Do not adopt or re-test H75 gameplay values from this evidence. H76 explains
why the local Spore/Wrath movement is not enough: many losses are still late,
partial, or non-stabilizing conversions, and the strict H74 screen still rejects
the candidate.

## Resume Note

Recommended H77: stay away from raw Spore/Wrath base values. Target the largest
diagnostic categories:

- Druid Garden timing/economy/path-lag pressure, especially R9-R10 activation
  at low HP and high `path_lag_hold` counts.
- Board activation/promotion only if a direct trace read shows bought payoff
  pieces remaining inactive.
- Combat conversion only after separating late activation deaths from genuinely
  on-time active failures.

Use `--druid-run-phase --druid-compare-baseline=<baseline>` as the first check
for any future Druid probe, alongside the H74 probe-comparison screen.
