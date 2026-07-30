# 091 - Completion Readiness Gates

Date: 2026-07-30

## Goal

Create a concrete completion-readiness contract for the next autonomous work
cycle without claiming the game is complete and without crossing the protected
`godot/sim/**` edit boundary.

## Context

H94 refreshed the current soft-Druid baseline and confirmed that H78 remains the
strongest gameplay-completion candidate. The current result is still not a green
prototype-completion signal:

```text
soft_druid: 9/60 clears.
completion_readiness: needs_attention.
top risk: low_overall_clear_rate.
path-lag audit gate: GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD.
```

The next useful unprotected step was to define what "completion-ready
prototype" means in evidence terms, so future autonomous work can resume with a
clear target.

## Change

Updated `Plans.md` with:

- an M1-M4 milestone ladder;
- M1 completion-ready prototype gates;
- explicit current status for live flow, replay/meta clarity, reward/economy
  integrity, strategy viability, and verification hygiene;
- an acceptance rule that prose is only a routing aid and that M1 completion
  must be based on recomputable artifacts;
- open blockers that keep H78 as pending explicit protected-simulator approval.

Updated `.claude/handoff.md` with the H95 checkpoint and pause/resume guidance.

## Advisory Review

Three advisory critics returned during the slice and supported a narrow
boundary: H95 is useful only as a contract/readiness artifact and pause
checkpoint. The main caution was false-green risk:

```text
Do not convert H94 into "gameplay fixed" or "prototype complete."
Do not treat Plans.md prose as the sole acceptance authority.
Keep H78 TODO / approval-gated.
```

A frame-challenge critic added that the next honest progress slice should not
be another planning artifact. If work resumes on the highest-impact known
blocker, ask for explicit H78 protected-edit approval; if that approval is not
available, choose a bounded unprotected manual/live playability scout.

A product-completion critic flagged that an H95 DONE row must not reference a
missing trace. This file is the durable trace for that row; the final sanity
query below checks that the H95 row, trace, gate text, and H78 blocker language
are all present.

Those cautions were incorporated into the acceptance rule in `Plans.md`, this
trace, and the handoff resume guidance.

## Evidence

Doc sanity query:

```text
rg -n "H95|Working Completion Gates|Acceptance rule|GO_PROTECTED|M1 completion|H78" Plans.md .claude/handoff.md .claude/traces/experiments/091-completion-readiness-gates.md
```

Result: H95, the completion gates, the acceptance rule, and H78 blocker language
are present in the intended files.

Whitespace/conflict guard:

```text
git diff --check
```

Result: exited 0.

Protected simulator boundary:

```text
git status --short -- godot/sim
```

Result: no output.

## Decision

ADOPT as a routing/readiness artifact only.

Warforge is not being marked complete. H78 remains the highest-impact known
M1 blocker, and it still requires explicit approval before editing
`godot/sim/ai_agent.gd`.

## Next

Pause after this checkpoint per user request. When work resumes with the same
goal, start from H95's gates:

1. ask for explicit protected-simulator approval if continuing H78;
2. run the narrow H78 no-focus stabilizer probe if approved;
3. rerun representative D1 self-play readiness across core strategies;
4. select the next slice from the observer's top risks.
