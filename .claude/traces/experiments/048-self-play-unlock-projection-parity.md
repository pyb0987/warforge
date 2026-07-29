# 048 - Self-Play Unlock Projection Parity

Date: 2026-07-27
Slice: H52

## Question

H51 showed a possible unlock burst after representative self-play, but the
projection was partial because card-sale metrics were unobservable and several
other metrics were proxies. Before changing live `MetaProgress` unlock rules,
can the self-play workflow make the burst evidence clearer without editing
protected simulator files under `godot/sim/`?

## Multi-Review Synthesis

Three independent critics reviewed the next step:

- Player progression critic: the burst is real enough to act on, but broad
  threshold increases are risky; prefer presentation/reveal pacing before
  hiding earned replay variety.
- Implementation/testability critic: a persisted 3-unlock reveal queue is a
  plausible later fix, but the observer must distinguish raw pressure from
  capped reveal pressure if that path is taken.
- Frame/measurement critic: H51 was not clean enough to tune progression
  directly; first make the projection closer to the real unlock contract and
  rerun evidence.

Decision: do a non-invasive observability/parity slice first. Do not change
live progression rules and do not edit protected `godot/sim/` files.

## Changes

- `godot/tools/self_play_observer.gd`
  - Enables lightweight trace-stat collection by default.
  - Derives `trace_stats.cards_sold` from existing `AITracer` sell events.
  - Keeps `--trace-dir` trace writing compatible with trace-stat derivation.
  - Adds `--trace-stats=false` to preserve the old partial projection mode.

- `godot/tools/self_play_observer_logic.gd`
  - Uses trace-derived `cards_sold` when every result provides it.
  - Marks card-sale metrics observable with `trace_event_count` confidence.
  - Labels growth-event projection as `chain_event_count_proxy`.
  - Adds raw/capped/deferred unlock projection fields per run.
  - Adds a hypothetical 3-unlock reveal pacing model, explicitly noting that
    live `MetaProgress` is not capped.

- `scripts/summarize_self_play_report.py`
  - Summarizes raw unlock pressure separately from reveal/deferred pressure.

- `docs/tools/self-play-observer.md`
  - Documents trace-derived sale counts, `--trace-stats=false`, and the
    hypothetical reveal cap semantics.

## Evidence

Focused observer GUT:

```bash
godot --headless --log-file /private/tmp/warforge_h52_self_play_observer_gut_2.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_self_play_observer.gd -glog=1 -gexit
```

Result: PASS, 8/8 tests, 60 asserts.

Python summary checks:

```bash
python3 -m unittest scripts.tests.test_summarize_self_play_report scripts.tests.test_lint_live_ui_screenshots scripts.tests.test_summarize_live_ui_report
python3 -m py_compile scripts/summarize_self_play_report.py scripts/summarize_live_ui_report.py scripts/lint_live_ui_screenshots.py
```

Result: PASS, 30 tests; py_compile PASS.

Command-line smoke:

```bash
godot --headless --log-file /private/tmp/warforge_h52_selfplay_smoke.log --path godot/ -s tools/self_play_observer.gd -- --runs=1 --strategies=adaptive --difficulty=1 --commander=gambler --talisman=flint --include-results=true --quiet-progress=true --out=/private/tmp/warforge_h52_selfplay_smoke.json
```

Result: PASS. Output included `trace_stats.cards_sold`.

Trace-dir smoke:

```bash
godot --headless --log-file /private/tmp/warforge_h52_selfplay_trace_dir_smoke.log --path godot/ -s tools/self_play_observer.gd -- --runs=1 --strategies=adaptive --difficulty=1 --commander=gambler --talisman=flint --trace-dir=/private/tmp/warforge_h52_trace_dir_smoke --include-results=false --quiet-progress=true --out=/private/tmp/warforge_h52_trace_dir_smoke.json
```

Result: PASS. Trace written:
`/private/tmp/warforge_h52_trace_dir_smoke/adaptive_4241831549.jsonl`
with 68 JSONL events.

No-trace-stats smoke:

```bash
godot --headless --log-file /private/tmp/warforge_h52_selfplay_no_trace_stats.log --path godot/ -s tools/self_play_observer.gd -- --runs=1 --strategies=adaptive --difficulty=1 --commander=gambler --talisman=flint --trace-stats=false --include-results=false --quiet-progress=true --out=/private/tmp/warforge_h52_no_trace_stats.json
```

Result: PASS. Projection returned `status: partial` and flagged card-sale
metrics as unobservable.

Representative 10-run matrix:

```bash
godot --headless --log-file /private/tmp/warforge_h52_selfplay_matrix.log --path godot/ -s tools/self_play_observer.gd -- --runs=2 --strategies=adaptive,soft_steampunk,soft_druid,soft_predator,soft_military --difficulty=1 --commander=gambler --talisman=flint --seed=2026072751 --include-results=true --quiet-progress=true --out=/private/tmp/warforge_h52_selfplay_matrix.json
python3 scripts/summarize_self_play_report.py --report=/private/tmp/warforge_h52_selfplay_matrix.json --out=/private/tmp/warforge_h52_selfplay_matrix_summary.md
```

Result: PASS.

Key summary:

- Overall clear rate: 6/10.
- Boss milestones: R4 reward 10/10, R8 reward 7/10, R12 reward 5/8 reached.
- Projection status: complete observable metrics for this run because trace
  stats were enabled.
- Largest raw single-run unlock projection: 11.
- Runs with projected unlocks: 9/10.
- Runs with projected deferred unlocks under a hypothetical 3-reveal model: 6.
- Largest deferred count under that model: 8.
- Card-sale metrics are now material:
  - `cards_sold_20`: best 69, hit 5/10.
  - `cards_sold_12`: best 69, hit 6/10.

Log/error checks:

```bash
rg -n "SCRIPT ERROR|Compile Error|ERROR:" /private/tmp/warforge_h52_selfplay_matrix.log
rg -n "SCRIPT ERROR|Compile Error|ERROR:" /private/tmp/warforge_h52_selfplay_trace_dir_smoke.log /private/tmp/warforge_h52_selfplay_smoke.log /private/tmp/warforge_h52_selfplay_matrix.log
rg -n "SCRIPT ERROR|Compile Error|ERROR: Failed|ObjectDB|Resource still" /private/tmp/warforge_h52_full_gut.log
```

Result: PASS; no matches.

Whitespace/diff checks:

```bash
rg -n "[ \t]+$" godot/tools/self_play_observer.gd godot/tools/self_play_observer_logic.gd godot/tests/test_self_play_observer.gd scripts/summarize_self_play_report.py scripts/tests/test_summarize_self_play_report.py docs/tools/self-play-observer.md
git diff --check
```

Result: PASS.

Full GUT:

```bash
godot --headless --log-file /private/tmp/warforge_h52_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
```

Result: PASS, 1240/1240 tests, 8009 asserts.

## Interpretation

H52 strengthens the user-reported concern. With card sales counted from trace
events, the same representative matrix moves from H51's largest projected
single-run burst of 9 to H52's largest raw projection of 11. The burst is not
just a display artifact.

Because several non-sale metrics are still proxy or lower-bound measurements,
the next progression-rule change should be narrow and reversible. The best next
candidate is a player-facing reveal budget/pending queue that keeps earned
content available through deliberate pacing, or a UI-only post-run reveal recap
if we want an even smaller step first.

## Next

Recommended H53: implement a narrow post-run/recent-unlock reveal layer, using
the H52 raw/deferred projection fields as the acceptance signal. If changing
actual unlock availability, use another multi-review first because it alters
the meta progression contract.
