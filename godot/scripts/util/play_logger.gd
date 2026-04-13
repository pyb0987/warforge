class_name PlayLogger
extends RefCounted
## Append-only structured event logger for human play sessions.
##
## Writes one JSON event per line to user://play_logs/session_<ts>.jsonl
## and a paired notes template to user://play_logs/session_<ts>_notes.md
## that the player fills in with decision rationales.
##
## Events:
##   - session_start
##   - round_start (with full state snapshot + shop offered)
##   - shop_refresh (after reroll)
##   - purchase / sell / move / merge
##   - reroll / upgrade_reroll / levelup
##   - build_confirm (final board)
##   - battle_result
##   - boss_reward / boss_reward_selected
##   - settlement (income/terazin/interest)
##   - game_over

const LOG_DIR := "user://play_logs"

var _file: FileAccess = null
var _session_id: String = ""


## Open log file and write session header. Returns abs path of session for reference.
func start_session(seed_val: int) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
	var ts := Time.get_datetime_string_from_system().replace(":", "-")
	_session_id = ts
	var log_path := "%s/session_%s.jsonl" % [LOG_DIR, ts]
	var notes_path := "%s/session_%s_notes.md" % [LOG_DIR, ts]

	_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _file == null:
		push_error("[PlayLogger] Failed to open %s" % log_path)
		return ""

	_write({
		"event": "session_start",
		"session_id": _session_id,
		"seed": seed_val,
		"unix_time": Time.get_unix_time_from_system(),
	})

	_create_notes_template(notes_path)

	var abs := ProjectSettings.globalize_path(log_path)
	print("[PlayLogger] Logging to %s" % abs)
	print("[PlayLogger] Notes template: %s" % ProjectSettings.globalize_path(notes_path))
	return abs


func close_session() -> void:
	if _file != null:
		_file.close()
		_file = null


# ================================================================
# Event API
# ================================================================


func log_round_start(state: GameState, shop_offered: Array) -> void:
	var data := {
		"event": "round_start",
		"round": state.round_num,
		"gold": state.gold,
		"terazin": state.terazin,
		"hp": state.hp,
		"shop_level": state.shop_level,
		"levelup_cost": state.levelup_current_cost,
		"field_slots": state.field_slots,
		"board": _snapshot_zone(state.board),
		"bench": _snapshot_zone(state.bench),
		"shop": _snapshot_shop(shop_offered),
	}
	if state.card_pool != null:
		data["pool_remaining"] = state.card_pool.remaining_per_tier()
	_write(data)


func log_shop_refresh(reason: String, shop_offered: Array, gold_after: int) -> void:
	_write({
		"event": "shop_refresh",
		"reason": reason,
		"gold_after": gold_after,
		"shop": _snapshot_shop(shop_offered),
	})


func log_purchase(card_id: String, slot_idx: int, cost: int, state: GameState) -> void:
	_write({
		"event": "purchase",
		"card_id": card_id,
		"slot_idx": slot_idx,
		"cost": cost,
		"gold_after": state.gold,
	})


func log_sell(zone: String, idx: int, card_id: String, refund: int, state: GameState) -> void:
	_write({
		"event": "sell",
		"zone": zone,
		"idx": idx,
		"card_id": card_id,
		"refund": refund,
		"gold_after": state.gold,
	})


func log_move(from_zone: String, from_idx: int, to_zone: String, to_idx: int) -> void:
	_write({
		"event": "move",
		"from_zone": from_zone,
		"from_idx": from_idx,
		"to_zone": to_zone,
		"to_idx": to_idx,
	})


func log_merge(card_id: String, old_star: int, new_star: int) -> void:
	_write({
		"event": "merge",
		"card_id": card_id,
		"old_star": old_star,
		"new_star": new_star,
	})


func log_reroll(cost: int, free: bool, gold_after: int) -> void:
	_write({
		"event": "reroll",
		"cost": cost,
		"free": free,
		"gold_after": gold_after,
	})


func log_upgrade_reroll(cost: int, terazin_after: int) -> void:
	_write({
		"event": "upgrade_reroll",
		"cost": cost,
		"terazin_after": terazin_after,
	})


## 상점에서 업그레이드 구매(테라진 차감) 이벤트.
## 부착은 별도 upgrade_attach 이벤트로 기록.
func log_upgrade_purchase(upgrade_id: String, slot_idx: int, cost: int, terazin_after: int) -> void:
	_write({
		"event": "upgrade_purchase",
		"upgrade_id": upgrade_id,
		"slot_idx": slot_idx,
		"cost": cost,
		"terazin_after": terazin_after,
	})


## 상점 구매 후 부착 실패/취소로 환불된 경우.
func log_upgrade_refund(upgrade_id: String, cost: int, reason: String, terazin_after: int) -> void:
	_write({
		"event": "upgrade_refund",
		"upgrade_id": upgrade_id,
		"cost": cost,
		"reason": reason,
		"terazin_after": terazin_after,
	})


## 카드에 업그레이드가 실제로 부착된 이벤트.
## source: "shop" | "merge_bonus" | "boss_reward" | "salvage" 등.
func log_upgrade_attach(upgrade_id: String, source: String, target_card_id: String, target_idx: int) -> void:
	_write({
		"event": "upgrade_attach",
		"upgrade_id": upgrade_id,
		"source": source,
		"target_card_id": target_card_id,
		"target_idx": target_idx,
	})


func log_levelup(new_level: int, cost: int, gold_after: int, next_cost: int) -> void:
	_write({
		"event": "levelup",
		"new_level": new_level,
		"cost": cost,
		"gold_after": gold_after,
		"next_cost": next_cost,
	})


func log_build_confirm(state: GameState) -> void:
	var board_snap := _snapshot_zone(state.board)
	var total_cp := 0.0
	for entry in board_snap:
		total_cp += entry.get("cp", 0.0)
	_write({
		"event": "build_confirm",
		"round": state.round_num,
		"board": board_snap,
		"bench": _snapshot_zone(state.bench),
		"gold": state.gold,
		"terazin": state.terazin,
		"total_board_cp": total_cp,
	})


func log_battle_result(round_num: int, won: bool, ally_survived: int, enemy_survived: int, hp_after: int, win_bonus_gold: int = 0) -> void:
	_write({
		"event": "battle_result",
		"round": round_num,
		"won": won,
		"ally_survived": ally_survived,
		"enemy_survived": enemy_survived,
		"hp_after": hp_after,
		"win_bonus_gold": win_bonus_gold,
	})


func log_settlement(round_num: int, base_income: int, interest: int, terazin_gain: int, gold_after: int, terazin_after: int, card_effect_gold: int = 0) -> void:
	_write({
		"event": "settlement",
		"round": round_num,
		"base_income": base_income,
		"interest": interest,
		"terazin_gain": terazin_gain,
		"card_effect_gold": card_effect_gold,
		"gold_after": gold_after,
		"terazin_after": terazin_after,
	})


func log_boss_reward_offered(round_num: int, choices: Array) -> void:
	_write({
		"event": "boss_reward_offered",
		"round": round_num,
		"choices": choices,
	})


func log_boss_reward_selected(reward_id: String) -> void:
	_write({
		"event": "boss_reward_selected",
		"reward_id": reward_id,
	})


func log_boss_reward_applied(round_num: int, reward_id: String, targets: Array) -> void:
	_write({
		"event": "boss_reward_applied",
		"round": round_num,
		"reward_id": reward_id,
		"targets": targets,
	})


func log_game_over(victory: bool, final_round: int, final_hp: int) -> void:
	_write({
		"event": "game_over",
		"victory": victory,
		"final_round": final_round,
		"final_hp": final_hp,
	})


# ================================================================
# Internals
# ================================================================


func _write(d: Dictionary) -> void:
	if _file == null:
		return
	_file.store_line(JSON.stringify(d))
	_file.flush()


func _snapshot_zone(zone: Array) -> Array:
	var out: Array = []
	for i in zone.size():
		var c = zone[i]
		if c == null:
			continue
		var ci: CardInstance = c
		out.append({
			"idx": i,
			"id": ci.get_base_id(),
			"name": ci.get_name(),
			"star": ci.star_level,
			"units": ci.get_total_units(),
			"atk": ci.get_total_atk(),
			"hp": ci.get_total_hp(),
			"cp": ci.get_total_cp(),
			"upgrades": ci.upgrades.duplicate() if ci.upgrades != null else [],
		})
	return out


func _snapshot_shop(shop_offered: Array) -> Array:
	var out: Array = []
	for i in shop_offered.size():
		var id: String = shop_offered[i]
		if id == "":
			continue
		var tmpl := CardDB.get_template(id)
		out.append({
			"slot": i,
			"id": id,
			"name": tmpl.get("name", id),
			"tier": tmpl.get("tier", 0),
			"cost": tmpl.get("cost", 0),
		})
	return out


func _create_notes_template(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[PlayLogger] Failed to create notes template: %s" % path)
		return
	f.store_line("# Play Session Notes — %s" % _session_id)
	f.store_line("")
	f.store_line("> Paired log: `session_%s.jsonl`" % _session_id)
	f.store_line("> 각 라운드에서 **결정의 이유**만 적어주세요. 보드/상점/결과는 jsonl에 자동 기록됩니다.")
	f.store_line("")
	for r in range(1, 16):
		f.store_line("## R%d" % r)
		f.store_line("")
		f.store_line("**의도:** ")
		f.store_line("")
		f.store_line("**핵심 결정:** ")
		f.store_line("")
		f.store_line("**놓친 것 / 헷갈린 것:** ")
		f.store_line("")
		f.store_line("---")
		f.store_line("")
	f.store_line("## 종합 회고")
	f.store_line("")
	f.store_line("- 어느 라운드가 가장 만족스러웠나? ")
	f.store_line("- 어디서 운에 휘둘렸나? ")
	f.store_line("- AI 시뮬과 다르게 행동한 부분은? ")
	f.store_line("")
	f.close()
