# 121 - H124 Post-H123 Next-Slice Review

Date: 2026-07-31
Status: DONE - diagnostic-first routing

## Purpose

Choose the next Druid strategy-floor move after H123 rejected and rolled back
the Spore forest-depth debuff-only probe.

## Input Evidence

H123 evaluator:

```text
Verdict: WEAK_LOCAL_SIGNAL_DO_NOT_ADOPT
Clears: 9/60 -> 11/60, target >=14
Avg final HP: -4.23 -> -2.67
R9-R11 focus WR: 34.6% -> 42.7%
Active-loss survivors A/E: 0.0/13.8 -> 0.0/14.2
Failed gates: clears_materially_improve, active_loss_enemy_survivors_fall,
active_loss_allied_survivors_move
```

H123 analyzer signals:

- Debuff optics moved and `debuff_too_small` dropped, but run-level and
  survivor-margin gates failed.
- After the debuff lift, damage shortfall dominates the active battle ledger.
- Focus activation still often happens in the lethal window.
- Bench/promotion gaps remain visible but previous broad activation-ish probes
  were flat or rejected.

## Multi-Review

Damage-Conversion Critic:

- Verdict: `YES_BUT_DIAGNOSTIC_FIRST`
- Score: `8/10`
- Key findings:
  - H123 points away from more debuff-only Spore routing and toward outgoing
    damage conversion.
  - Prior H72/H75 rejected Spore or Spore+Wrath base-number buffs, and H73
    rejected isolated Wrath base ATK, so do not simply buff values.
  - H78/H100 activation-ish probes did not move combat margins, so activation is
    secondary unless the damage ledger disproves the offensive shortfall.
- Recommended shape: analyzer-first Druid offensive conversion ledger, then a
  bounded Wrath/World math probe only if contribution evidence supports it.

Activation/Promotion Critic:

- Verdict: diagnostic-first activation/promotion packet is plausible, but not
  as a generic payoff buff.
- Score: `8/10`
- Key findings:
  - H123 shows 15 never-active payoff cases, 28 inactive frames, and 17
    promotion skips.
  - Prior H100/H103/H118 warn against broad AI or duplicate-focus fixes.
  - Any activation packet must prove survival/clear movement, not just activation
    count movement.

Measurement/Scope Critic:

- Verdict: `record_only_analysis_first`
- Score: `9/10`
- Key findings:
  - A new protected packet is premature because the next causal target is not
    yet isolated.
  - A broader all-core refresh is low value now; the M1 failure is already
    localized to soft-Druid.
  - Same-seed evaluator extensions may be useful, but only after the next
    measurable hypothesis is chosen.

## Synthesis

Verdict: `ANALYZER_FIRST_H124`

Do not implement another protected gameplay packet immediately.

Next action should be a no-code H124 analysis slice over H123 and baseline
traces, focused on:

- Druid outgoing damage conversion.
- Wrath/World offensive contribution in active R9-R11 frames.
- Whether active losses are caused by insufficient damage, late activation, or
  payoff absence.
- Survivor-margin movement, not only debuff/focus optics.

Required next artifact:

- A packet proposal only if the analysis isolates one causal bottleneck.
- The proposal must define target metrics, adoption gates, rollback rule, and
  forbidden files.
- The exact Spore forest-depth debuff-only shape must stay rejected unless new
  evidence changes the causal model.

## Verification

PASS H105 changed-file boundary:

```text
Result: PASS
Allow records: True
Checked files: 2

Files:
- .claude/traces/experiments/121-h124-post-h123-next-slice-review.md
- Plans.md
```

PASS whitespace guard:

```text
git diff --check
```

## Decision

ADOPT as H124 routing.

The next aligned work is analysis/tooling, not gameplay editing.
