# Experiment 095 - Druid Activation/Promotion Audit

Date: 2026-07-30
Status: DONE - behavior-neutral analyzer adopted; no gameplay values changed

## Question

After H78 rejected the no-focus stabilizer-buy AI probe, should the next Druid
strategy-floor repair target activation/promotion, Spore combat conversion, or
another acquisition/economy policy?

## Multi-Review

Used advisory multi-review because H98 chooses the next M1 blocker direction.

| Critic | Score | Verdict | Key Finding |
|--------|-------|---------|-------------|
| Product/strategy | 8/10 | Select activation diagnostic | Do not accept M1 and do not tune Spore immediately; use a behavior-neutral activation/promotion diagnostic first. |
| Trace evidence | 8/10 | FEASIBLE | Existing `buy`, `round_end`, `promote`, and `promote_skip` traces are enough for aggregate attribution, but not per-instance causality. |
| Scope boundary | 8/10 | SAFE | Python analyzer/tests/docs are allowed; fresh approval remains required before protected simulator edits or gameplay tuning. |

## Implementation

Added `--druid-activation-audit` to `scripts/analyze_ai_trace.py`.

The audit reports, from existing trace JSONL only:

- payoff buy runs and bought payoff copies;
- active-after-buy and never-active-after-buy counts;
- inactive R8-R12 frames by bench/board/absent status, card, round, path, and
  run-phase conversion bucket;
- promotion attempts and promotion skips by reason/card/blocking card;
- inactive examples linked to next battle survivors and final outcome;
- explicit trace limitations for aggregate card-ID attribution.

It also supports `--druid-compare-baseline`, producing activation/promotion
deltas alongside the existing Druid probe comparison.

Docs updated: `docs/tools/self-play-observer.md`.

## Real-Trace Evidence

Commands:

```bash
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h94_druid60_traces \
  --strategy=soft_druid \
  --druid-activation-audit \
  > /private/tmp/warforge_h98_h94_activation_audit.txt

python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h78_stabilizer60_traces \
  --strategy=soft_druid \
  --druid-activation-audit \
  --druid-compare-baseline=/private/tmp/warforge_h94_druid60_traces \
  > /private/tmp/warforge_h98_h78_vs_h94_activation_audit.txt

python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h97_selfplay70_traces \
  --strategy=soft_druid \
  --druid-activation-audit \
  > /private/tmp/warforge_h98_h97_activation_audit.txt
```

H94 baseline activation audit:

- Payoff buy runs: 42/60.
- Bought copies: 63.
- Active after buy: 46.
- Never active after buy: 17.
- Inactive frames: 29 from 20 runs.
- Bench gaps: 23.
- Board gaps: 0.
- No-attempt bench gaps: 19.
- Promotion skips: 19 (`protect_path_focus` 15, `path_focus_value_gap` 4).
- Path split:
  - `druid_world_tree`: 20 inactive frames, 16 bench gaps, 16 promotion skips.
  - `druid_garden`: 9 inactive frames, 7 bench gaps, 2 promotion skips.
- Next signal: bench/promotion gaps are common enough to justify a protected
  activation/promotion policy probe with fresh approval.

H78 rejected candidate vs H94:

- Payoff buy runs fell 42/60 -> 36/60.
- Total inactive frames stayed 29 -> 29.
- Gap runs increased 20 -> 22.
- Bench gaps fell 23 -> 18, but absent/unobserved gaps rose 6 -> 11.
- Promotion skips rose 19 -> 25, mostly `protect_path_focus`.
- Activation comparison next signal: no decisive activation delta; H78 remains
  rejected and should not be used as a new baseline.

H97 natural 10-run Druid sample:

- Payoff buy runs: 9/10.
- Inactive frames: 7 from 2 runs.
- Bench gaps: 6.
- Promotion skips: 9.
- Next signal: activation evidence is mixed in this small sample; use the larger
  H94/H78 same-seed evidence for the next protected-probe decision.

## Interpretation

H98 shifts the next Druid question away from shop purchase loosening:

- H78 reduced path-lag holds but did not reduce total inactive payoff frames or
  improve clears.
- H94 shows many bought payoff copies activate quickly, but a meaningful tail
  remains stuck on the bench during the R8-R12 lethal window.
- The largest activation/promotion gap is `druid_world_tree`, where current
  focus protection and missing-payoff activation appear to conflict.

Read-only code inspection of `godot/sim/ai_agent.gd` found one plausible
protected probe: `_find_path_focus_replacement()` skips all current focus cards
before considering duplicate active copies. This can block replacing a duplicate
current payoff with a different missing current payoff, even though
`_should_skip_path_focus_swap()` already treats duplicate active copies as not
protected.

## Verification

- PASS `python3 -m py_compile scripts/analyze_ai_trace.py scripts/tests/test_analyze_ai_trace.py`.
- PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace -q` (21 tests).
- PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace scripts.tests.test_summarize_self_play_report -q` (24 tests).
- PASS real-trace H94 activation audit.
- PASS real-trace H78-vs-H94 activation comparison.
- PASS real-trace H97 activation audit.
- PASS `git diff --check -- scripts/analyze_ai_trace.py scripts/tests/test_analyze_ai_trace.py docs/tools/self-play-observer.md`.
- PASS protected/tuning boundary check produced no output for `godot/sim/**`,
  `godot/tests/test_ai_agent.gd`, card YAML, generated card DB, and difficulty
  config.

## Decision

Adopt the behavior-neutral analyzer. H98 does not complete M1 and does not adopt
any gameplay behavior.

## Next

Use the H99 approval packet before any protected simulator edit. The next
candidate should test duplicate-current focus replacement for missing Druid
payoffs, with strict outcome gates and rollback if same-seed clears or health
regress.
