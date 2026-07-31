# 102 - Druid Spore Forest-Depth Approval Packet

Date: 2026-07-31
Status: READY_FOR_APPROVAL - no protected gameplay files edited

## Purpose

Prepare the next protected Druid strategy-floor probe after H104. This packet
does not implement the probe; it defines the smallest protected runtime change
worth asking for.

M1 is still blocked by the D1 Druid strategy floor. Current clean baseline
evidence at commit `23d8fe3`:

- Same-seed soft-Druid: 9/60 clears, avg final HP `-4.23`.
- R9-R11 focus-active ledger: 81 frames, 28 wins / 53 losses, WR `34.6%`.
- Primary ledger bottleneck: `debuff_too_small` 30 frames.
- H104 Spore audit: Spore active 50 frames, 17 wins / 33 losses.
- H104 tree gap: Spore own trees avg `0.2`, active Druid forest depth avg
  `26.6`, Spore-loss current debuff `15.7%`, diagnostic forest-depth estimate
  `21.8%`, low-debuff loss threshold crossings `21/32`.

This is not approval to execute. Fresh user approval is required before editing
the runtime/test files below.

## Multi-Review Synthesis

Three critics reviewed the packet shape:

- Card-design critic: conditional go. This is meaningfully different from H72
  and H75 if Spore bases, own-tree scaling, caps, Wrath, World Tree, AI, and UI
  stay unchanged. Mandatory-card risk is medium and must be tested.
- Measurement critic: sufficient to prepare a packet, not to execute or adopt.
  H104 is directional evidence only; same-seed and disjoint-seed screens remain
  required.
- Implementation critic: conditional go with guardrails. Avoid a YAML/schema
  field for the first probe. Prefer computing the final debuff at
  `collect_enemy_battle_debuffs(board)` time so the probe observes final
  battle-start tree state and avoids left-to-right order artifacts.

## Approval Required

Approve edits only to:

- `godot/core/druid_system.gd`
- `godot/tests/test_druid_system.gd`
- `godot/tests/test_chain_engine.gd`

Do not edit for this runtime-only probe:

- `data/cards/druid.yaml`
- `godot/core/data/card_db.gd`
- `godot/core/data/card_descs.gd`
- `scripts/codegen_card_db.py`
- `scripts/card_desc_gen.py`
- `docs/design/card-codegen-schema.md`
- `godot/sim/**`
- difficulty, economy, UI, unlock, reward, or broad AI policy files

The user previously approved AI files, but this packet does not use that
approval because the best current evidence points at Druid runtime/card
behavior, not AI policy.

## Narrow Hypothesis

Spore currently scales its enemy debuff from its own tree counter only. H104
shows that in failing active fights, Spore often has almost no own trees while
the active Druid board already has meaningful forest depth. A narrow probe
should let Spore read a small amount of non-Spore active Druid tree depth for
enemy debuff only.

Formula:

```text
debuff =
  min(
    base_pct
    + spore_own_trees * existing_tree_scale_pct
    + non_spore_active_druid_trees * 0.0025,
    existing_cap
  )
```

Invariants:

- Spore base values unchanged.
- Existing own-tree scaling unchanged.
- Existing 50% debuff cap unchanged.
- Spore does not generate trees.
- Star 3 Spore self shield remains own-tree-scaled.
- Wrath, World Tree, Lifebeat, Grace, economy, AI, difficulty, and UI unchanged.
- Duplicate Spore debuffs remain non-stacking via strongest-effect-wins.
- Non-Druid cards do not contribute.
- Other Spore copies do not contribute to the added forest-depth component.

Why this differs from rejected probes:

- H72 raised Spore base mitigation and was rejected after only +1 clear and no
  active survivor-margin movement.
- H75 combined the rejected Spore base buff with a Wrath base buff and was
  rejected after weak local movement.
- H78/H100 were protected AI probes and did not move Druid outcomes.
- This packet targets a routing mismatch between Spore's non-generating role
  and existing active Druid forest depth; it does not raise base numbers.

## Exact Runtime Shape

Preferred seam:

- Keep `apply_battle_start(card, idx, board)` and `_spore_cloud_battle(card)`
  responsible for existing battle-start local state and Star 3 self shield.
- Recompute or lift Spore enemy debuffs inside
  `collect_enemy_battle_debuffs(board)`, after all battle-start hooks have run.
- Add a small runtime constant, for example:

```gdscript
const _SPORE_FOREST_DEPTH_DEBUFF_SCALE := 0.0025
```

Expected helper shape:

```gdscript
func _spore_cloud_enemy_debuffs(card: CardInstance, board: Array) -> Dictionary:
	var own_trees := _trees(card)
	var other_trees := _non_spore_active_druid_trees(board)
	...
	var debuff := minf(
		base_pct
		+ own_trees * tree_scale
		+ other_trees * _SPORE_FOREST_DEPTH_DEBUFF_SCALE,
		cap
	)
```

`_non_spore_active_druid_trees(board)` should use the existing Druid-entry
semantics and exclude cards whose base id is `dr_spore_cloud`. Do not broaden
forest-depth semantics to transformed/off-theme cards in this probe.

The collect-time seam avoids a false order dependency where Lifebeat's
battle-start tree add would count only when Lifebeat is processed before Spore.

## Focused Tests

Add or update tests for:

- Existing own-tree Spore baseline still passes.
- Star 1 Spore with 0 own trees and 20 non-Spore active Druid trees reaches
  `0.15 + 20*0.0025 = 0.20` AS debuff.
- Non-Druid cards with tree counters do not increase Spore debuff.
- Other Spore copies do not feed the added forest-depth component.
- Duplicate Spore remains strongest-effect-wins, not stacking.
- The 50% cap still clamps final enemy debuff.
- Star 2 Spore applies the forest-depth lift to both AS and ATK while preserving
  existing own-tree scaling.
- Star 3 Spore shield remains own-tree-based.
- ChainEngine enemy attack interval and ATK scaling reflect the lifted debuff on
  a real enemy array.
- Spore/Lifebeat order test: Spore before Lifebeat and Lifebeat before Spore
  produce the same collected enemy debuff when the collect-time seam is used.

## Verification Commands

Pre-probe, confirm clean/understood baseline:

```bash
git status --short --branch
python3 scripts/codegen_card_db.py --check
python3 scripts/lint_card_spawn.py
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_druid_system.gd -glog=1 -gexit
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_chain_engine.gd -glog=1 -gexit
```

After implementation:

```bash
python3 scripts/codegen_card_db.py --check
python3 scripts/lint_card_spawn.py
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_druid_system.gd -glog=1 -gexit
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_chain_engine.gd -glog=1 -gexit
git diff --check
```

Same-seed gameplay screen:

```bash
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h105_spore_forest60 godot --headless --log-file /private/tmp/warforge_h105_spore_forest60.log --path godot/ -s tools/self_play_observer.gd -- --runs=60 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=flint --seed=2026072901 --out=/private/tmp/warforge_h105_spore_forest60.json --trace-dir=/private/tmp/warforge_h105_spore_forest60_traces --quiet-progress=true
python3 scripts/summarize_self_play_report.py --report /private/tmp/warforge_h105_spore_forest60.json --out /private/tmp/warforge_h105_spore_forest60_summary.md
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h105_spore_forest60_traces --strategy=soft_druid --druid-active-ledger --druid-spore-tree-gap --druid-run-phase --druid-activation-audit --druid-compare-baseline=/private/tmp/warforge_h104_clean_druid60_traces > /private/tmp/warforge_h105_spore_forest60_vs_h104.txt
```

Before keeping any gameplay change:

```bash
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
```

## Adoption Gate

Same-seed candidate may be nominated only if all are true:

- Clears improve materially over H104's 9/60, with target gate `>=14/60`.
- Avg final HP improves by about +1.0 or more, target `>= -3.25`.
- R9-R11 focus-active WR improves by at least +8pp, target `>=42.6%`, with
  preference for `>=45%`.
- H74/H104 comparison is not `REJECT_FLAT_OR_NOISY`.
- Active-loss enemy survivors fall meaningfully from `13.8`, target `<=12.5`.
- Active-loss allied survivors are no longer flat at `0.0`, target `>=0.2`.
- `debuff_too_small` decreases without increasing early-death or
  no-payoff-seen buckets enough to erase the run-level gains.
- Lift concentrates in prior low-own/high-forest Spore losses, not mostly in
  already-winning boards.

Reject immediately if any are true:

- Clears fall or remain 9/60.
- Avg HP fails to improve.
- R9-R11 focus WR is flat/noisy or regresses.
- The only visible improvement is lower `debuff_too_small` while clears,
  survivor margins, or HP remain flat.
- Cap-heavy behavior makes most Spore boards hit 50%, masking tuning quality.
- Mandatory-card risk appears: Druid wins depend on Spore as the sole survival
  gate while other Druid routes remain weak.

If same-seed is nominated, require a disjoint 60-run seed before adoption.
If disjoint confirmation fails, roll back the gameplay files and keep only trace
evidence.

## Rollback Rule

If the same-seed screen fails, revert only the probe-owned edits in:

- `godot/core/druid_system.gd`
- `godot/tests/test_druid_system.gd`
- `godot/tests/test_chain_engine.gd`

Then rerun focused Druid/Chain tests, codegen check, card-spawn guard, and
`git diff --check`. Record the rejection with exact failed gates.

## Boundary

This packet is a prepared request, not implementation approval. Fresh user
approval is required before touching the protected runtime/test files listed
above.
