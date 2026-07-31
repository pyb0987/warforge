# 119 - H105 Implementation Seam Map

Date: 2026-07-31
Status: DONE - no-edit implementation handoff

## Purpose

Prepare the H105 Spore forest-depth implementation at line-level detail without
editing protected files. The latest user approval still covers only AI files, so
this trace is a record-only handoff for the next approved run.

## Source State

- Branch: `main`
- HEAD before mapping: `9dff293 Record H105 approval boundary review`
- Worktree before mapping: clean

## Current Runtime Anchors

`godot/core/druid_system.gd`:

- `apply_battle_start(card, idx, board)` routes `dr_spore_cloud` to
  `_spore_cloud_battle(card)` at lines 35-42.
- `collect_enemy_battle_debuffs(board)` currently reads stored
  `enemy_atk_debuff` and `enemy_as_debuff` from each active card and applies
  strongest-effect-wins at lines 48-60.
- `_trees(card)` and `_add_trees(card, n)` are the existing tree helpers at
  lines 188-193.
- `_druid_entries(board)` already defines active Druid board membership at
  lines 196-203.
- `_spore_cloud_battle(card)` currently computes local stored debuffs as
  `base_pct + own_trees * tree_scale` and writes them into `theme_state` at
  lines 512-527.

`godot/core/chain_engine.gd`:

- `process_battle_start(board)` runs battle-start effects in board order at
  lines 367-404.
- `apply_enemy_battle_debuffs(board, enemy_units)` calls
  `dr_sys.collect_enemy_battle_debuffs(board)` after battle-start effects and
  clamps/applies the returned ATK/AS debuffs at lines 408-430.

## Intended Protected Runtime Shape

Do not move the base Spore write path out of `_spore_cloud_battle`. Leave stored
`card.theme_state["enemy_*_debuff"]` values as the local, own-tree-only values
so existing direct Spore tests continue to protect YAML/codegen numbers.

Add the forest-depth lift at collection time:

- Add a small constant in `DruidSystem`:

```gdscript
const _SPORE_FOREST_DEPTH_DEBUFF_SCALE := 0.0025
```

- Add helper using existing active-Druid semantics:

```gdscript
func _non_spore_active_druid_trees(board: Array) -> int:
	var total := 0
	for entry in _druid_entries(board):
		var card := entry["card"] as CardInstance
		if card.get_base_id() == "dr_spore_cloud":
			continue
		total += _trees(card)
	return total
```

- Add helper to recompute collected Spore debuffs from card data:

```gdscript
func _spore_cloud_collected_debuffs(card: CardInstance, other_trees: int) -> Dictionary:
	var result := {"atk_pct": 0.0, "as_pct": 0.0}
	var effs := CardDB.get_theme_effects("dr_spore_cloud", card.star_level)
	var trees := _trees(card)
	for eff in effs:
		if eff.get("action") != "debuff_store":
			continue
		var base_pct: float = eff.get("base_pct", 0.15)
		var tree_scale: float = eff.get("tree_scale_pct", 0.015)
		var cap: float = eff.get("cap", 0.5)
		var debuff := minf(
			base_pct
			+ trees * tree_scale
			+ other_trees * _SPORE_FOREST_DEPTH_DEBUFF_SCALE,
			cap
		)
		match String(eff.get("stat", "as")):
			"as":
				result["as_pct"] = maxf(result["as_pct"], debuff)
			"atk":
				result["atk_pct"] = maxf(result["atk_pct"], debuff)
	return result
```

- Update `collect_enemy_battle_debuffs(board)`:
  - Compute `other_druid_trees` once before the loop.
  - For Spore cards, use `_spore_cloud_collected_debuffs(c, other_druid_trees)`
    and strongest-effect-wins against any stored debuff.
  - For non-Spore cards, keep the existing stored-debuff path.
  - Preserve the final `minf(..., 0.5)` cap.

Important invariant: `other_druid_trees` excludes all Spore copies and includes
only active Druid cards as defined by `_druid_entries(board)`.

## Intended Focused Tests

`godot/tests/test_druid_system.gd`:

- Keep existing direct Spore tests unchanged or add an assertion that stored
  `theme_state` debuffs remain own-tree-only.
- Add Star 1 collection test:
  - Spore has 0 own trees.
  - A non-Spore Druid card has 20 trees.
  - `collect_enemy_battle_debuffs(board)["as_pct"]` is `0.20`.
- Add non-Druid exclusion test:
  - A non-Druid card with tree counters must not lift Spore debuff.
- Add other-Spore exclusion test:
  - A second Spore copy with trees must not feed the forest-depth component.
- Add strongest-effect-wins test:
  - Multiple Spore copies should still yield the strongest single collected
    debuff, not stacked debuffs.
- Add cap test:
  - Large non-Spore active Druid tree depth still clamps at 50%.
- Add Star 2 test:
  - Forest-depth lift applies to both AS and ATK while preserving existing
    own-tree scaling.
- Add Star 3 shield test:
  - Star 3 self shield remains own-tree-based and does not include forest-depth
    trees.

`godot/tests/test_chain_engine.gd`:

- Add enemy application test with Spore plus non-Spore Druid tree depth:
  - Enemy attack interval reflects lifted AS debuff.
  - Star 2 enemy ATK reflects lifted ATK debuff.
- Add Spore/Lifebeat order test:
  - Spore before Lifebeat and Lifebeat before Spore produce the same collected
    enemy debuff after `process_battle_start(board)`.
  - This validates the collect-time seam and avoids board-order artifacts.

## Files To Edit After Approval

Only after explicit approval:

- `godot/core/druid_system.gd`
- `godot/tests/test_druid_system.gd`
- `godot/tests/test_chain_engine.gd`

Continue to avoid:

- `data/cards/druid.yaml`
- `godot/core/data/card_db.gd`
- `godot/core/data/card_descs.gd`
- `scripts/codegen_card_db.py`
- `scripts/card_desc_gen.py`
- `docs/design/card-codegen-schema.md`
- `godot/sim/**`
- difficulty, economy, UI, unlock, reward, and broad AI policy files

## Verification After Approval

Use the existing H105 workflow:

```text
python3 scripts/run_h105_spore_forest_workflow.py --execute --prefix warforge_h105_spore_forest60
```

If the same-seed evaluator nominates the candidate rather than rejecting it,
run full GUT and a disjoint-seed confirmation before adopting the gameplay
change.

## Record-Only Verification

PASS H105 changed-file boundary:

```text
Result: PASS
Allow records: True
Checked files: 2

Files:
- .claude/traces/experiments/119-h105-implementation-seam-map.md
- Plans.md
```

PASS whitespace guard:

```text
git diff --check
```

## Decision

ADOPT as an implementation-seam handoff.

No protected files were edited. The next completion-critical action still
requires explicit H105 approval naming the three protected files.
