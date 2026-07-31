# 118 - H105 Approval-Boundary Multi-Review

Date: 2026-07-31
Status: DONE - decision review and approval handoff

## Purpose

After H120, review whether the newly approved AI-file scope should be used for
another implementation slice, or whether the next honest M1 move is still H105
approval.

The decision matters because M1 is currently gated by strategy viability, and
H120 shows soft-Druid at 0/10 clears on current clean `main`.

## Decision Frame

Decision:

- Choose the next action toward M1 after H120.

Stakes:

- Avoid false progress from a permitted but low-value AI/UI/economy slice.
- Avoid silently expanding user approval into protected files.
- Keep the route to a completion-ready prototype tied to recomputable evidence.

Constraints:

- Latest user approval covers only:
  - `godot/sim/ai_agent.gd`
  - `godot/tests/test_ai_agent.gd`
- H105 requires fresh explicit approval for:
  - `godot/core/druid_system.gd`
  - `godot/tests/test_druid_system.gd`
  - `godot/tests/test_chain_engine.gd`
- H105 must not touch YAML, generated DB, schema, broad AI policy, difficulty,
  economy, UI, unlock, or reward files.

Input materials:

- `Plans.md` H120 and M1 gates.
- `.claude/traces/experiments/117-current-head-self-play-strategy-floor-refresh.md`
- `.claude/traces/experiments/102-druid-spore-forest-depth-approval-packet.md`
- `scripts/check_h105_spore_forest_boundary.py`
- `scripts/evaluate_h105_spore_forest_probe.py`
- `scripts/run_h105_spore_forest_workflow.py`

## Critics

Completion-Criticality Critic:

- Scope: whether the next action materially advances M1.
- Anti-scope: code style and implementation details.
- Attack surface: false progress from easy AI/UI work.
- Primary failure mode: recommending work that looks useful but does not make
  the actual objective more true.
- Frame challenge: allowed.
- Verdict: `ask_stop_for_protected_H105_approval`
- Score: `10/10`
- Key findings:
  - H120 is record-only evidence, not gameplay progress.
  - M1 strategy viability is not green: soft-Druid is 0/10 in the latest
    70-run D1 scout.
  - H105 Spore forest-depth scaling is repeatedly identified as the next
    completion-critical packet.
  - AI-file approval does not cover the protected H105 runtime/test files.
- Recommended next action: ask for explicit approval to edit the three H105
  protected files, then execute the narrow H105 packet.

Scope-Boundary Critic:

- Scope: permission and changed-file safety.
- Anti-scope: balance or design value.
- Attack surface: silently expanding approval or touching out-of-packet files.
- Primary failure mode: scope creep.
- Frame challenge: allowed.
- Verdict: `Do not edit H105 protected files yet`
- Score: `0.96`
- Key findings:
  - Approval currently covers only AI files.
  - H105 files remain protected without explicit file-named approval.
  - Evidence is not permission.
- Permitted actions:
  - Record-only plan or trace updates.
  - Non-invasive verification.
  - Edits limited to the two explicitly approved AI files.
- Forbidden actions:
  - Editing H105 protected files.
  - Touching YAML, generated files, difficulty, economy, or UI as part of H105
    without separate approval.
  - Claiming blocked before the repeated-blocker threshold is met.

Alternative-Progress Critic:

- Scope: whether any non-protected task can honestly advance completion now.
- Anti-scope: protected H105 implementation.
- Attack surface: missing useful permitted work, or inventing busywork.
- Primary failure mode: overblocking or recommending side work as M1 progress.
- Frame challenge: allowed.
- Verdict: `NO_HIGH_VALUE_NON_PROTECTED_CODE_SLICE`
- Score: `0.88`
- Candidate slices:
  - High value: non-code H105 approval handoff.
  - Low value: optional unlock recap review, but replay/meta is already green
    enough for M1 and this does not address the strategy floor.
- Rejected slices:
  - AI-only Druid tuning in approved files: likely false progress.
  - More self-play/preflight reruns: mostly confidence, not movement.
  - Unlock threshold or queue changes: no manual/live overwhelm evidence.
  - Reward/economy/live-flow expansion: diminishing returns for M1.
  - Difficulty, YAML, card buffs, generated DB, or economy tuning: outside
    scope or conflicts with H105 boundaries.

## Synthesis

Verdict: `ADVISORY PASS - REQUEST_H105_APPROVAL`

All critics converge that the next completion-critical action is not another
AI-only slice. The project can do record-only handoff work without approval, but
no non-protected implementation is a high-value substitute for H105.

False-green risk:

- High if approved AI files are edited and then treated as strategy-floor
  progress while soft-Druid remains 0/10.
- High if passing tests are used to obscure an approval-boundary violation.
- Medium if unlock pacing is changed without manual/live overwhelm evidence.

Invariant checked:

- M1 cannot be called complete until strategy viability is green on recomputable
  self-play/analyzer evidence.
- Protected-file approval must be explicit by file and cannot be inferred from
  adjacent AI-file approval or plan priority.

## Verification

PASS H105 changed-file boundary:

```text
Result: PASS
Allow records: True
Checked files: 2

Files:
- .claude/traces/experiments/118-h105-approval-boundary-multireview.md
- Plans.md
```

PASS whitespace guard:

```text
git diff --check
```

## Decision

Do not edit code in this slice.

Ask for explicit approval to edit:

- `godot/core/druid_system.gd`
- `godot/tests/test_druid_system.gd`
- `godot/tests/test_chain_engine.gd`

If approval is granted, execute H105 exactly as already packeted:

- Implement runtime-only Spore forest-depth enemy-debuff routing.
- Preserve Spore base values, own-tree scaling, 50% cap, Star 3 self-shield
  semantics, YAML, generated DB, AI, difficulty, economy, UI, unlocks, and
  rewards.
- Verify with the H105 workflow runner, evaluator, boundary guard, focused GUT,
  full GUT, and disjoint-seed confirmation before adoption.
