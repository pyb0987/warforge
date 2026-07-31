# 110 - AI Unique-Effect Duplicate Awareness

Date: 2026-07-31
Status: DONE - approved AI-only maintenance slice

## Purpose

Use the user's explicit approval for `godot/sim/ai_agent.gd` and
`godot/tests/test_ai_agent.gd` for a contained AI-agent correctness improvement.

The selected slice addresses a known design note from
`docs/design/unique-effect-plan.md`: once card templates opt into
`unique_effect: true`, the headless AI should not value redundant same-card
effect copies as if every duplicate effect would fire independently.

This is deliberately scoped as AI observability/play-quality maintenance. It is
not a Druid H105 runtime packet and does not attempt to move the Druid strategy
viability floor.

## Source State

- Branch: `main`
- Base commit: `b36c588bdcb12c8f4745722e5501f98e2d6d0fe7`
- Approved gameplay files:
  - `godot/sim/ai_agent.gd`
  - `godot/tests/test_ai_agent.gd`

## Change

- Added an AI scoring penalty for incoming card templates with
  `unique_effect: true` when the player already owns the same base card.
- Kept merge completion viable:
  - First copy: no penalty.
  - Second/redundant copy: stronger duplicate penalty.
  - Third star-1 copy that completes a merge: smaller penalty, preserving most
    of the existing imminent-merge bonus.
- Added focused tests for all three cases.
- Did not add or change any `unique_effect` card data flags. Current card pool
  behavior is therefore unchanged unless future card data opts into the flag.

## Verification

Focused AI test:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit
```

Result:

- PASS `test_ai_agent.gd`
- 43/43 tests
- 99 assertions

Whitespace guard:

```text
git diff --check
```

Result:

- PASS

Full Godot suite:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/ -glog=1 -gexit
```

Result:

- PASS
- 57 scripts
- 1286/1286 tests
- 9279 assertions

## Boundary

Touched gameplay files were limited to the two files approved by the user:

- `godot/sim/ai_agent.gd`
- `godot/tests/test_ai_agent.gd`

Record-only files:

- `Plans.md`
- `.claude/traces/experiments/110-ai-unique-effect-duplicate-awareness.md`

Not touched:

- Card YAML data
- Generated `godot/core/data/card_db.gd`
- Difficulty or economy files
- Protected H105 Druid runtime/test files:
  - `godot/core/druid_system.gd`
  - `godot/tests/test_druid_system.gd`
  - `godot/tests/test_chain_engine.gd`

## Decision

ADOPT.

This is a low-risk AI scoring correctness improvement with direct regression
coverage and full-suite verification. It makes future unique-effect cards less
likely to distort self-play observations through redundant duplicate buying,
while still allowing the AI to value a third copy when it creates a merge.

Carry forward: H105 remains the next completion-critical gameplay candidate,
but still requires explicit approval for its protected Druid runtime/test file
set before implementation.
