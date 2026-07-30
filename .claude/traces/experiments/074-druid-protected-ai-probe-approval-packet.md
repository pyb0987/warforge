# Experiment 074 - Druid Protected AI Probe Approval Packet

Date: 2026-07-29
Status: READY_FOR_APPROVAL - no protected files edited

## Purpose

Prepare the exact H78 protected simulator AI probe before editing
`godot/sim/**`.

H77 proved that the current Druid `path_lag_hold` behavior is mostly not
skipping affordable focus cards. Instead, it hard-holds while no focus card is
visible, often through the R9-R12 lethal window:

- H75 R8-R12 holds: `265`.
- No focus card visible: `260/265` (`98.1%`).
- Affordable focus visible: `1/265`.
- Garden actionable no-focus loss runs: `18`.
- H77 gate: `GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD`.

## Approval Required

Explicit user approval is required before editing protected simulator AI files:

- `godot/sim/ai_agent.gd`

Focused test edits are expected in:

- `godot/tests/test_ai_agent.gd`

No card YAML, generated card DB, combat/runtime, difficulty, UI, or broad AI
surface should be edited for this probe.

## Narrow Hypothesis

When `soft_druid` is in payoff/capstone path lag and no focus card is visible in
the current shop offers, hard-holding every non-focus purchase can starve the
run of stabilizing board/economy pieces.

Probe behavior:

- Preserve current behavior when a current/next focus card is visible.
- Preserve current behavior when an affordable focus card is visible.
- Preserve priority purchases for current/next focus, missing critical path
  cards, and capstone cards.
- Only when no focus card is visible, allow selected stabilizers instead of
  `path_lag_hold`.

Allowed stabilizer shape:

- Druid body or Druid core card above a conservative score threshold.
- High-value neutral stabilizer above a stricter score threshold.
- No off-theme stabilizer fallback in the first probe unless evidence later
  shows neutral-only is too narrow.

This is intentionally not a Druid card buff and not a broad redesign.

## Exact Code Seam

Current protected function:

```gdscript
func _should_hold_for_path_lag_purchase(state: GameState, card_id: String,
		tmpl: Dictionary, board_ids: Dictionary) -> bool:
```

Current call site:

```gdscript
if _should_hold_for_path_lag_purchase(state, chosen_id, chosen_tmpl, _H.get_board_ids(state)):
```

Proposed probe patch shape:

```gdscript
const _DRUID_NO_FOCUS_BODY_STABILIZER_SCORE := 30.0
const _DRUID_NO_FOCUS_NEUTRAL_STABILIZER_SCORE := 22.0

if _should_hold_for_path_lag_purchase(
		state, chosen_id, chosen_tmpl, _H.get_board_ids(state), evals, best_score):
	...

func _should_hold_for_path_lag_purchase(state: GameState, card_id: String,
		tmpl: Dictionary, board_ids: Dictionary, offer_evals: Array = [],
		best_score: float = 0.0) -> bool:
	...
	if _is_path_lag_purchase_priority(card_id, state, board_ids, focus):
		return false
	if _should_allow_no_focus_stabilizer(
			card_id, tmpl, state, board_ids, focus, offer_evals, best_score):
		return false
	return true
```

Helper logic:

- `_has_visible_path_focus_offer(offer_evals, focus)` returns true if any
  current/next focus card is in offers, even if unaffordable.
- `_should_allow_no_focus_stabilizer(...)` returns true only when:
  - no visible focus offer exists, and
  - candidate is Druid and `best_score >= 30.0`, or
  - candidate is neutral and `best_score >= 22.0`.

The thresholds are intentionally conservative. H77 top held examples include
`dr_grace 55.2`, `dr_deep 44.36`, `dr_lifebeat 39.3`,
`dr_prune 57.1`, `dr_origin 47.86`, `dr_cradle 37.58`, and
`ne_mutant_adapt 27.25`, so the probe targets repeated high-confidence holds
without opening low-value filler.

## Focused Test Changes

Update existing test:

- `test_druid_path_lag_holds_non_priority_purchase`
  - keep asserting low/irrelevant neutral filler is held.
  - change `dr_grace` assertion to allow when no focus offer is visible and
    `best_score` clears the Druid body threshold.

Add tests:

- `test_druid_path_lag_holds_when_focus_offer_visible`
  - pass `offer_evals` containing `dr_spore_cloud`.
  - assert a non-focus stabilizer is still held.
- `test_druid_path_lag_allows_high_value_neutral_when_no_focus_visible`
  - pass no focus offer and high `best_score`.
  - assert hold returns false.
- `test_druid_path_lag_holds_low_value_neutral_when_no_focus_visible`
  - pass no focus offer and low `best_score`.
  - assert hold returns true.

Existing priority test remains:

- `test_druid_path_lag_allows_priority_purchase`

## Verification Commands

Pre-probe:

```bash
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h75_coupled60_traces --strategy=soft_druid --druid-run-phase --druid-path-lag-audit --druid-compare-baseline=/private/tmp/warforge_h71_ledger60_druid_traces
```

Post-patch focused verification:

```bash
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit
git diff --check -- godot/sim/ai_agent.gd godot/tests/test_ai_agent.gd
```

Same-seed probe:

```bash
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h78_stabilizer60 \
godot --headless --log-file /private/tmp/warforge_h78_stabilizer60.log \
--path godot/ -s tools/self_play_observer.gd -- \
--runs=60 \
--strategies=soft_druid \
--difficulty=1 \
--commander=gambler \
--talisman=flint \
--seed=2026072901 \
--out=/private/tmp/warforge_h78_stabilizer60.json \
--trace-dir=/private/tmp/warforge_h78_stabilizer60_traces \
--quiet-progress=true

python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h78_stabilizer60_traces \
  --strategy=soft_druid \
  --druid-active-ledger \
  --druid-run-phase \
  --druid-path-lag-audit \
  --druid-compare-baseline=/private/tmp/warforge_h71_ledger60_druid_traces
```

## Adoption Gate

Adopt only if same-seed H78 clears a strict screen, then confirm on a disjoint
seed before final adoption.

Same-seed nomination requires:

- Clears improve by at least `+2/60`, or average final HP improves by at least
  `+1.0` without clear regression.
- H76 run-phase improves at least one of:
  - `active_too_late` decreases by `>= 3`.
  - Garden `no_payoff_seen` decreases by `>= 3`.
  - loss post-active WR improves by `>= 8pp`.
- H77 audit improves:
  - no-focus `path_lag_hold` count decreases materially, and
  - `affordable_focus_available` does not increase.
- H74 probe screen is not `REJECT_FLAT_OR_NOISY`.
- Active-loss survivor margin does not worsen.

Reject immediately if:

- Clears fall, or average HP falls by `>= 1.0`.
- `affordable_focus_available` increases, meaning the probe harms focus
  priority.
- H77 shows the AI is buying low-value filler rather than stabilizers.
- H74 screen is `REJECT_FLAT_OR_NOISY`.

## Rollback

If the same-seed screen fails, revert only H78-owned edits in:

- `godot/sim/ai_agent.gd`
- `godot/tests/test_ai_agent.gd`

Do not revert H76/H77 analyzer diagnostics or unrelated dirty worktree files.

## Approval Prompt

Please approve editing protected `godot/sim/**` for this narrow H78 AI policy
probe.
