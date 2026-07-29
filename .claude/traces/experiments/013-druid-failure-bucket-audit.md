# Episode 013: Druid failure bucket audit

date: 2026-07-26
verdict: in-progress

## Question

After Druid AI changes improved active payoff/path observability but left
`soft_druid` weak, decide the next autonomous development step without jumping
straight to card or difficulty tuning.

Recent evidence:

```text
full GUT: PASS 52 scripts, 1205 tests, 7536 asserts

observer smoke:
command:
godot --headless --log-file /private/tmp/warforge_druid_path_lag_hold_soft10.log --path godot/ -s tools/self_play_observer.gd -- --runs=10 --strategies=soft_druid,soft_predator,soft_steampunk --difficulty=1 --commander=gambler --talisman=two_faced_coin --seed=2026072604 --out=/private/tmp/warforge_druid_path_lag_hold_soft10.json --trace-dir=/private/tmp/warforge_druid_path_lag_hold_soft10_traces --quiet-progress=true

soft_druid:    1/10 wins, avg final HP -4.3, avg rerolls 10.6
soft_predator: 6/10 wins, avg final HP 12.5
soft_steampunk: 2/10 wins, avg final HP -0.7

Druid active current-phase progress:
- garden: 30%
- world_tree: 40%
- enemy debuffs seen: 50%
- path_lag_hold skips: 71
```

## Multi-Review Synthesis

Verdict: advisory pass for diagnosis first.

- Gameplay critic: Druid is touching its mechanics but not converting them into
  survivability reliably. Audit losses before buffing values.
- AI/observability critic: 10 runs are not enough for balance conclusions.
  `path_lag_hold` volume and reroll count suggest AI decision flow or trace
  classification still needs investigation.
- Workflow critic: add H17 and this trace before code. Keep one functional
  change per iteration and close with full GUT.

Frame correction: this is not a Druid balance slice yet. It is a failure-bucket
audit that may produce one narrow AI, rules, or card-value patch if the traces
show a recurring confirmed cause.

## Scope

Allowed:

- Run `godot/tools/self_play_observer.gd` with fixed seeds and trace output.
- Extend `scripts/analyze_ai_trace.py` or add a small analysis helper if the
  current analyzer cannot bucket Druid losses clearly.
- Edit Layer 2 AI behavior only if a recurring valuation/path defect is
  confirmed.
- Edit card YAML only after a second review confirms the evidence is balance,
  not AI or instrumentation.

Forbidden for this slice:

- No difficulty tuning.
- No edits to generated `godot/core/data/card_db.gd`.
- No edits to protected Tier 0 evaluator files:
  `godot/sim/autoresearch.py`, `godot/sim/baseline.json`,
  `godot/sim/batch_runner.gd`, or `godot/sim/program.md`.
- No broad reroll/economy changes without a trace-backed defect and a
  multi-review checkpoint.

## Failure Buckets To Measure

- Tier access lag: Druid dies before reaching the shop tier needed for current
  phase cards.
- Path acquisition lag: needed current-phase cards never appear or are skipped.
- Board activation lag: owned payoff/current-phase cards stay benched or are
  swapped out.
- Economy starvation: `path_lag_hold`, rerolling, or no-space behavior blocks
  useful purchases.
- Combat conversion failure: active Druid payoff/debuff cards fire but battle
  damage remains too high.

## Adoption Gate

A code patch may be adopted only if:

- The audit explains most Druid losses with one recurring cause family, or a
  single high-confidence defect appears in raw traces.
- A focused GUT test pins the changed behavior.
- A same-seed observer rerun moves the targeted trace metric in the intended
  direction without an obvious Predator/Steampunk regression.
- Full GUT passes before H17 is marked DONE.

If the audit does not isolate a recurring cause, do not patch. Record the
diagnosis gap and expand observability instead.

## H17 Audit Results

Added durable observability:

- `AIAgent._try_levelup` now emits `levelup` trace events with round, from/to
  shop level, paid cost, gold before/after, and next level cost.
- `scripts/analyze_ai_trace.py --druid-loss-buckets` reports Druid-specific
  loss categories and the payoff offer/afford/buy funnel.
- Analyzer summary now reports level timing from exact `levelup` events when
  present, while remaining compatible with older `round_start.shop_level`
  traces.

Focused verification:

```text
PASS python3 -m unittest scripts.tests.test_analyze_ai_trace
PASS godot --headless --log-file /private/tmp/warforge_h17_test_ai_agent_after_rejects.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit
PASS python3 -m unittest scripts.tests.test_lint_card_spawn scripts.tests.test_analyze_ai_trace
PASS python3 scripts/lint_card_spawn.py
PASS git diff --check
PASS godot --headless --log-file /private/tmp/warforge_h17_test_self_play_observer.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_self_play_observer.gd -glog=1 -gexit
PASS godot --headless --log-file /private/tmp/warforge_h17_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit

full GUT: 52 scripts, 1206 tests, 7545 asserts
```

Corrected same-seed Druid observer:

```text
command:
godot --headless --log-file /private/tmp/warforge_h17_druid_leveltrace_30.log --path godot/ -s tools/self_play_observer.gd -- --runs=30 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=two_faced_coin --seed=2026072617 --out=/private/tmp/warforge_h17_druid_leveltrace_30.json --trace-dir=/private/tmp/warforge_h17_druid_leveltrace_30_traces --quiet-progress=true

result:
soft_druid: 3/30 wins, avg final HP -2.83, avg rounds 10.23
level timing: Lv4 reached 90.0% (avg R7.7), Lv5 reached 63.3% (avg R9.6)
enemy debuffs seen: 26.7%
```

Bucket output:

```text
losses: 27/30
payoff_acquisition_lag: 16
path_lag_hold_pressure: 14
combat_conversion_failure: 7
low_druid_board_ratio: 7
tier_access_lag: 5
payoff_no_debuff_conversion: 4
owned_not_active_gap: 1

loss payoff funnel:
offered 17, affordable 12, bought 11, skipped affordable 2 runs / 3 events
```

Interpretation:

- Earlier traces overstated tier-access lag because level-up was only visible
  on the next `round_start`; exact `levelup` events show Druid usually reaches
  Lv4 during R7-R8.
- The dominant remaining failure is not a simple level schedule bug. Druid
  often reaches tier access but does not acquire or convert Spore/Wrath before
  lethal R8-R10 pressure.
- Affordable payoff skips are rare, so purchase scoring is not the first
  suspect.

## Rejected Behavior Experiments

### Variant A: two-level tier catch-up

Patch: force `soft_druid` scheduled tier access when it is at least two shop
levels behind target even if current phase lag is below 0.5.

Result:

```text
baseline: 3/30 wins, avg final HP -2.83
variant:  3/30 wins, avg final HP -2.73
payoff_acquisition_lag: 16 -> 17
enemy debuffs seen: 26.7% -> 23.3%
```

Verdict: REJECT. It did not improve clear rate or the target bucket.

### Variant B: R7-R8 payoff-prep reroll push

Patch: when `soft_druid` has 2/3 engine progress and no payoff in R7-R8, add a
small reroll push and relax gold reserve.

Result:

```text
baseline: 3/30 wins, avg final HP -2.83
variant:  3/30 wins, avg final HP -2.77
payoff_acquisition_lag: 16 -> 16
path_lag_hold_pressure: 14 -> 15
no_space skips: 40 -> 52
```

Verdict: REJECT. It improved some path-progress diagnostics but did not improve
the dominant failure bucket or outcome.

## Next Allowed Action

Use `card-designer` plus multi-review before editing Druid card YAML. The best
candidate is now a narrow Druid midgame payoff/access balance review, not more
generic AI level-up or reroll tuning. Focus questions:

- Should `dr_spore_cloud`/`dr_wrath` become easier to acquire or convert at
  R7-R10?
- Is Druid's intended Garden branch supposed to stabilize without `dr_world`,
  and does current combat evidence contradict that?
- If balance changes are justified, make one YAML/codegen change at a time and
  rerun the H17 observer/analyzer gate.
