# Experiment 070 — Druid Probe Comparison Ledger

Date: 2026-07-29
Status: DONE - behavior-neutral analyzer/tooling adopted

## Question

After H72 and H73 rejected isolated Druid Spore/Wrath number probes, can H74
make future Druid balance decisions more attributable without editing protected
sim instrumentation or changing gameplay values?

## Review Synthesis

Used multi-review because this was a balance/measurement decision.

- Design critic: ledger first. A coupled Spore+Wrath probe is plausible, but
  H72/H73 do not yet identify which contribution is missing strongly enough.
- Measurement critic: ledger first. Same-seed +1 clear or local focus-window
  movement is a false-green risk; adoption must compare against H71 and require
  disjoint-seed confirmation.
- Implementation critic: warned that a true pre-combat per-card contribution
  ledger would likely require protected `godot/sim/**` instrumentation. It
  preferred a YAML-only coupled probe if the alternative required protected
  edits.

Decision: implement a derived comparison ledger in Python only. This avoids
protected sim edits while still giving H75 stricter gates.

## Adopted Change

Updated `scripts/analyze_ai_trace.py`:

- Added `avg_final_hp` and `wins` to `summarize_strategy()` output.
- Added `--druid-compare-baseline=<trace_dir>`.
- Added `summarize_druid_probe_comparison()` and printer output that compares:
  - clears and clear-rate delta.
  - average final HP and rounds delta.
  - R9-R11 focus-active frame count and win-rate delta.
  - active-loss ally/enemy survivor margins.
  - Druid bottleneck deltas.
  - focus-combo deltas for Spore-only, Wrath-only, Spore+Wrath, World, and
    mixed focus boards.
  - conservative screen verdict:
    `PASS_SCREEN_CONFIRM_ON_DISJOINT_SEED`, `WEAK_LOCAL_SIGNAL_DO_NOT_ADOPT`,
    or `REJECT_FLAT_OR_NOISY`.

Updated `scripts/tests/test_analyze_ai_trace.py` with comparison coverage, and
documented the command in `docs/tools/self-play-observer.md`.

No card values, gameplay rules, AI scoring, generated card DB, or protected
`godot/sim/**` files were changed.

## Evidence Against H71 Baseline

Baseline: H71 accepted 60-run D1 `soft_druid`, Gambler+Flint,
seed `2026072901`.

H72 isolated Spore candidate compared with H71:

- Clears: `9/60 -> 10/60` (`+1`).
- Avg HP: `-4.23 -> -3.65` (`+0.58`).
- R9-R11 focus WR: `34.6% -> 39.8%` (`+5.2pp`).
- Active-loss survivors: ally `0.0 -> 0.0`, enemy `13.8 -> 13.6`.
- Debuff gap delta: `-29`.
- Screen verdict: `WEAK_LOCAL_SIGNAL_DO_NOT_ADOPT`.

H73 isolated Wrath candidate compared with H71:

- Clears: `9/60 -> 9/60` (`+0`).
- Avg HP: `-4.23 -> -3.80` (`+0.43`).
- R9-R11 focus WR: `34.6% -> 37.0%` (`+2.5pp`).
- Active-loss survivors: ally `0.0 -> 0.0`, enemy `13.8 -> 14.1`.
- Debuff gap delta: `-1`.
- Screen verdict: `REJECT_FLAT_OR_NOISY`.

Interpretation: the new comparison confirms the previous decisions. Spore-only
has a local signal but still fails survivor and run-level gates. Wrath-only is
flat/noisy. A later coupled probe must move terminal and survivor metrics
together.

## Verification

- PASS `python3 -m py_compile scripts/analyze_ai_trace.py scripts/tests/test_analyze_ai_trace.py`.
- PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace -q` (15 tests).
- PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace scripts.tests.test_summarize_self_play_report -q` (18 tests).
- PASS H72 comparison command:
  `python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h72_spore60_traces --strategy=soft_druid --druid-active-ledger --druid-compare-baseline=/private/tmp/warforge_h71_ledger60_druid_traces`.
- PASS H73 comparison command:
  `python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h73_wrath60_traces --strategy=soft_druid --druid-compare-baseline=/private/tmp/warforge_h71_ledger60_druid_traces`.
- PASS `git diff --check -- scripts/analyze_ai_trace.py scripts/tests/test_analyze_ai_trace.py`.

## Resume Note

Recommended H75: if continuing Druid, run one explicitly coupled
Spore+Wrath YAML-only probe using H71 as the baseline and this new comparison
report as the screen gate. Do not adopt on label movement alone; require clears,
avg HP, focus-active WR, and active-loss survivor margins to move together, then
confirm on a disjoint seed.
