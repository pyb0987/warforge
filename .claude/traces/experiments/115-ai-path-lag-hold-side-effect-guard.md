# 115 - AI Path-Lag Hold Side-Effect Guard

Date: 2026-07-31
Status: DONE - approved AI-only maintenance; not H105 strategy-floor progress

## Purpose

Resume after H117 using the user's latest approval for:

- `godot/sim/ai_agent.gd`
- `godot/tests/test_ai_agent.gd`

H105 remains the completion-critical M1 blocker and still requires separate
approval for the protected Druid runtime/test files. This slice is an approved
AI correctness and observability cleanup only.

## Advisory Multi-Review

Decision under review: whether to proceed with an AI-agent-only slice or stop
for H105 approval.

Critics:

- Completion-Criticality Critic: verdict `A_APPROVAL_ONLY_BLOCKED_ON_H105`.
- Scope-Boundary and False-Progress Critic: verdict
  `STOP_AND_ASK_FOR_H105_APPROVAL_FOR_NEXT_COMPLETION_CRITICAL_WORK`;
  AI-only work is allowed only as non-M1 maintenance.
- AI-Agent Opportunity Critic: verdict `ADVISORY_PASS_SMALL_PATCH`, identifying
  a concrete side-effect bug in `_try_buy_best`.

Synthesis:

- H105 remains the next completion-critical implementation.
- Since the user explicitly approved the AI files and a concrete AI bug was
  found, proceed with one narrow AI-only maintenance slice.
- The trace and plan must not call this strategy-floor progress.

## Bug

Before this slice, `_try_buy_best` could:

1. choose an attractive shop card;
2. notice the bench was full;
3. sell the weakest bench card to make space;
4. only then apply Druid `path_lag_hold`;
5. return `false` without buying the held card.

That made a no-purchase hold decision side-effectful. It could also make the AI
trace misleading: a `buy_skip:path_lag_hold` decision might hide an earlier
`weakest_for_upgrade` sale.

## Change

Move the Druid path-lag hold check before bench-space sale in `_try_buy_best`.

Invariant after the change:

- If the chosen purchase is held for Druid path-lag discipline, the AI does not
  sell bench material, spend gold, or consume the shop offer.
- Bench-space sales still happen for non-held attractive purchases.

## Source State

- Branch: `main`
- HEAD before implementation: `833cdc6 Cover neutral targeted sell transfers`

## Files Changed

- `godot/sim/ai_agent.gd`
- `godot/tests/test_ai_agent.gd`
- `Plans.md`
- `.claude/traces/experiments/115-ai-path-lag-hold-side-effect-guard.md`

## Verification

PASS focused AI agent:

```text
test_ai_agent.gd
44/44 tests
107 assertions
```

PASS full GUT:

```text
57 scripts
1292/1292 tests
9474 assertions
```

PASS card spawn guard:

```text
python3 scripts/lint_card_spawn.py
```

PASS whitespace guard:

```text
git diff --check
```

PASS traced self-play smoke:

```text
godot --headless --log-file /private/tmp/warforge_h118_selfplay_smoke.log \
  --path godot/ -s tools/self_play_observer.gd -- \
  --runs=1 --strategies=soft_druid --difficulty=1 \
  --commander=gambler --talisman=flint --include-results=true \
  --quiet-progress=true \
  --out=/private/tmp/warforge_h118_selfplay_smoke.json \
  --trace-dir=/private/tmp/warforge_h118_selfplay_smoke_traces
```

PASS self-play hard-error log guard:

```text
rg -n "SCRIPT ERROR|Parse Error|ERROR:" \
  /private/tmp/warforge_h118_selfplay_smoke.log
```

No matches.

PASS protected H105 file check:

```text
git diff --name-only -- \
  godot/core/druid_system.gd \
  godot/tests/test_druid_system.gd \
  godot/tests/test_chain_engine.gd
```

No protected H105 files were changed.

## Boundary

This slice did not edit:

- `godot/core/druid_system.gd`
- `godot/tests/test_druid_system.gd`
- `godot/tests/test_chain_engine.gd`
- card YAML
- generated card DB files
- difficulty/economy values
- live UI files

## Decision

ADOPT as H118 AI-only maintenance.

Do not count this as M1 strategy-floor progress. The next completion-critical
implementation remains H105 after explicit protected-file approval.
