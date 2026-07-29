# Episode 025: Steampunk engine retention/activation probe

## Context

Episode 024 showed that Steampunk engine pieces were not an offer-space problem:
losing `soft_steampunk` runs usually saw, afforded, and bought their selected
path engine targets, but almost never ended with complete engine ownership or
active engine completion.

That made a narrow board-retention/activation probe plausible, especially for
Spread `sp_line`.

## Multi-Review

Three independent critics reviewed the planned behavior before implementation.

- Evidence review: proceed only if the probe measures active-board conversion,
  because engine acquisition already succeeds and sale counts alone do not
  explain the failure.
- Design review: keep the probe selected-path-only; do not protect shared
  support such as `sp_barrier`/`sp_interest`, and do not activate payoffs blindly.
- Implementation review: add the smallest possible hooks in the AI agent:
  protect one copy of selected path machinery from bench cleanup/upgrade sales,
  promote missing selected-path engine cards from bench, and replace only filler
  or anti-branch bodies.

## Probe

Implemented a temporary `soft_steampunk` engine-retention path:

- protect one owned copy of selected engine targets while the active engine is
  incomplete;
- promote missing selected engine cards from bench before generic theme
  conversion;
- prevent generic promotion swaps from removing the last active selected engine
  card.

Focused tests pinned Spread, Focus, sale protection, and shared-support
exclusions.

## Verification

```text
PASS godot --headless --log-file /private/tmp/warforge_h29_ai_agent.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit
  44/44

PASS python3 -m unittest scripts.tests.test_analyze_ai_trace
  12/12
```

Same-seed observer:

```bash
godot --headless --log-file /private/tmp/warforge_h29_engine_retention_140.log \
  --path godot/ -s tools/self_play_observer.gd -- --runs=20 --strategies=all \
  --difficulty=1 --commander=gambler --talisman=two_faced_coin \
  --seed=2026072620 --out=/private/tmp/warforge_h29_engine_retention_140.json \
  --trace-dir=/private/tmp/warforge_h29_engine_retention_140_traces \
  --quiet-progress=true
```

Headline result:

```text
overall wins: 62/140
soft_steampunk: 3/20, avg final HP -0.4
```

Compared with H23-B:

```text
overall wins: 64/140 -> 62/140
soft_steampunk WR: 25.0% -> 15.0%
```

Detailed Steampunk read:

```text
losses: 17/20
Lv4 reached: 40.0%
Lv5 reached: 20.0%
loss path target funnel:
  engine: offered 17, affordable 17, bought 17,
          complete owned 7, complete active 7
  payoff: offered 4, affordable 4, bought 4,
          complete owned 4, complete active 0
```

Post-revert verification:

```text
PASS rg H29 symbol sweep: no remaining references
PASS godot --headless --log-file /private/tmp/warforge_h29_revert_ai_agent.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit
  39/39
PASS python3 -m unittest scripts.tests.test_analyze_ai_trace
  12/12
```

## Decision

Reject and revert the behavior/test patch.

Reason:

- The probe successfully converted engine ownership into active engine
  completion, so the mechanism worked locally.
- The game outcome regressed: `soft_steampunk` dropped from 5/20 to 3/20 and
  overall wins dropped from 64/140 to 62/140.
- The target funnel still did not convert payoffs into active output:
  losing runs bought four payoffs but had zero complete-active payoff targets.
- Lv4 access also slipped from the retained H23-B surface, suggesting the board
  protection/promotion was preserving machinery at the cost of survival and/or
  economy timing.

Carry-over:

- Do not force Steampunk engine bodies onto the active board merely because they
  complete the path.
- Future Steampunk work should target payoff access/output and survival
  together, not engine activation in isolation.
- The retained diagnostic funnel is valuable: it showed the local improvement
  and still explained why the aggregate result was worse.
