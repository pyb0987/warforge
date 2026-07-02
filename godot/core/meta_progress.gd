class_name MetaProgress
extends RefCounted
## Minimal persistent profile for run-start unlocks and summary stats.

const SAVE_PATH := "user://meta_progress.cfg"
const MAX_DIFFICULTY := 8
const ACH_FIELD_50_UNITS := "field_50_units"
const ACH_UPGRADES_10 := "upgrades_10"
const ACH_UNIQUE_7 := "unique_7"
const ACH_WIN_STREAK_5 := "win_streak_5"
const ACH_CARDS_SOLD_10 := "cards_sold_10"
const ACH_GROWTH_50 := "growth_50"
const ACH_STAR2_3 := "star2_3"
const ACH_UNIT_ADVANTAGE_WIN := "unit_advantage_win"
const ACH_UPGRADES_8 := "upgrades_8"
const ACH_CARDS_SOLD_5 := "cards_sold_5"

var unlocked_commanders: Array[int] = []
var unlocked_talismans: Array[int] = []
var completed_achievements: Array[String] = []
var last_unlocks: Array[String] = []
var max_difficulty_unlocked: int = 1
var selected_difficulty: int = 1
var runs_started: int = 0
var runs_finished: int = 0
var wins: int = 0
var best_round: int = 0
var last_result: String = ""
var tutorial_seen: bool = false


func _init() -> void:
	reset_to_defaults()


static func default_unlocked_commanders() -> Array[int]:
	return [
		Enums.CommanderType.GAMBLER,
		Enums.CommanderType.BREEDER,
	]


static func default_unlocked_talismans() -> Array[int]:
	return [
		Enums.TalismanType.FLINT,
		Enums.TalismanType.TWO_FACED_COIN,
		Enums.TalismanType.CRACKED_SKULL,
	]


func load_or_create(path: String = SAVE_PATH) -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		save(path)
		return
	_read_config(cfg)
	_sanitize()


func reset_to_defaults() -> void:
	unlocked_commanders = default_unlocked_commanders()
	unlocked_talismans = default_unlocked_talismans()
	completed_achievements = []
	last_unlocks = []
	max_difficulty_unlocked = 1
	selected_difficulty = 1
	runs_started = 0
	runs_finished = 0
	wins = 0
	best_round = 0
	last_result = ""
	tutorial_seen = false


func save(path: String = SAVE_PATH) -> Error:
	_sanitize()
	var cfg := ConfigFile.new()
	cfg.set_value("unlocks", "commanders", unlocked_commanders)
	cfg.set_value("unlocks", "talismans", unlocked_talismans)
	cfg.set_value("unlocks", "max_difficulty", max_difficulty_unlocked)
	cfg.set_value("unlocks", "completed_achievements", completed_achievements)
	cfg.set_value("unlocks", "last_unlocks", last_unlocks)
	cfg.set_value("run", "selected_difficulty", selected_difficulty)
	cfg.set_value("run", "tutorial_seen", tutorial_seen)
	cfg.set_value("stats", "runs_started", runs_started)
	cfg.set_value("stats", "runs_finished", runs_finished)
	cfg.set_value("stats", "wins", wins)
	cfg.set_value("stats", "best_round", best_round)
	cfg.set_value("stats", "last_result", last_result)
	return cfg.save(path)


func get_unlocked_commanders() -> Array[int]:
	return unlocked_commanders.duplicate()


func get_unlocked_talismans() -> Array[int]:
	return unlocked_talismans.duplicate()


func get_completed_achievements() -> Array[String]:
	return completed_achievements.duplicate()


func get_commander_unlock_statuses() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		{"type": Enums.CommanderType.GAMBLER, "goal": "초기 해금"},
		{"type": Enums.CommanderType.BREEDER, "goal": "초기 해금"},
		{"type": Enums.CommanderType.SMITH, "goal": "업그레이드 10개 장착"},
		{"type": Enums.CommanderType.STRATEGIST, "goal": "필드 유닛 50기 보유"},
		{"type": Enums.CommanderType.COLLECTOR, "goal": "서로 다른 카드 7종 필드"},
		{"type": Enums.CommanderType.RAIDER, "goal": "한 런 5연승"},
		{"type": Enums.CommanderType.ALCHEMIST, "goal": "한 런 카드 10장 판매"},
	]
	for row in rows:
		var commander_type: int = int(row["type"])
		var data := Commander.get_data(commander_type)
		row["name"] = data.get("name", str(commander_type))
		row["unlocked"] = is_commander_unlocked(commander_type)
	return rows


func get_talisman_unlock_statuses() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		{"type": Enums.TalismanType.FLINT, "goal": "초기 해금"},
		{"type": Enums.TalismanType.TWO_FACED_COIN, "goal": "초기 해금"},
		{"type": Enums.TalismanType.CRACKED_SKULL, "goal": "초기 해금"},
		{"type": Enums.TalismanType.BURST_SACK, "goal": "업그레이드 8개 장착"},
		{"type": Enums.TalismanType.WAR_DRUM,
			"goal": "수적 우위 전투 승리 또는 난이도 7 클리어"},
		{"type": Enums.TalismanType.MERCURY_DROP, "goal": "성장 효과 50회"},
		{"type": Enums.TalismanType.GLASS_EYE, "goal": "난이도 2 클리어"},
		{"type": Enums.TalismanType.GOLDEN_DIE, "goal": "난이도 5 클리어"},
		{"type": Enums.TalismanType.CRACKED_EGG, "goal": "★2+ 카드 3장 보유"},
		{"type": Enums.TalismanType.RUSTY_WRENCH, "goal": "업그레이드 8개 장착"},
		{"type": Enums.TalismanType.SOUL_JAR, "goal": "한 런 카드 5장 판매"},
		{"type": Enums.TalismanType.COPPER_WIRE, "goal": "난이도 3 클리어"},
	]
	for row in rows:
		var talisman_type: int = int(row["type"])
		var data := Talisman.get_data(talisman_type)
		row["name"] = data.get("name", str(talisman_type))
		row["unlocked"] = is_talisman_unlocked(talisman_type)
	return rows


func get_achievement_statuses() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		{"id": ACH_FIELD_50_UNITS, "name": "필드 유닛 50기 보유"},
		{"id": ACH_UPGRADES_10, "name": "업그레이드 10개 장착"},
		{"id": ACH_UNIQUE_7, "name": "서로 다른 카드 7종 필드"},
		{"id": ACH_WIN_STREAK_5, "name": "한 런 5연승"},
		{"id": ACH_CARDS_SOLD_10, "name": "한 런 카드 10장 판매"},
		{"id": ACH_GROWTH_50, "name": "성장 효과 50회"},
		{"id": ACH_STAR2_3, "name": "★2+ 카드 3장 보유"},
		{"id": ACH_UNIT_ADVANTAGE_WIN, "name": "수적 우위 전투 승리"},
		{"id": ACH_UPGRADES_8, "name": "업그레이드 8개 장착"},
		{"id": ACH_CARDS_SOLD_5, "name": "한 런 카드 5장 판매"},
	]
	for row in rows:
		row["completed"] = completed_achievements.has(str(row["id"]))
	return rows


func get_full_progress_text() -> String:
	var commander_rows := get_commander_unlock_statuses()
	var talisman_rows := get_talisman_unlock_statuses()
	var achievement_rows := get_achievement_statuses()
	var lines: PackedStringArray = []
	lines.append("진행 상세")
	lines.append("난이도 %d/%d 해금" % [max_difficulty_unlocked, MAX_DIFFICULTY])
	lines.append("")
	lines.append("커맨더 %d/%d" % [_count_unlocked_rows(commander_rows),
		commander_rows.size()])
	_append_unlock_lines(lines, commander_rows)
	lines.append("")
	lines.append("부적 %d/%d" % [_count_unlocked_rows(talisman_rows),
		talisman_rows.size()])
	_append_unlock_lines(lines, talisman_rows)
	lines.append("")
	lines.append("완료 업적")
	_append_achievement_lines(lines, achievement_rows, true)
	lines.append("")
	lines.append("잠긴 목표")
	_append_achievement_lines(lines, achievement_rows, false)
	return "\n".join(lines)


func is_commander_unlocked(commander_type: int) -> bool:
	return unlocked_commanders.has(commander_type)


func is_talisman_unlocked(talisman_type: int) -> bool:
	return unlocked_talismans.has(talisman_type)


func set_selected_difficulty(value: int) -> void:
	selected_difficulty = clampi(value, 1, max_difficulty_unlocked)


func record_run_started() -> void:
	runs_started += 1
	set_selected_difficulty(selected_difficulty)


func mark_tutorial_seen() -> void:
	tutorial_seen = true


func should_show_tutorial() -> bool:
	return not tutorial_seen


func get_tutorial_text() -> String:
	return "첫 런 가이드\n상점에서 카드를 사고 보드에 배치하세요.\nBUILD 확인 후 성장 체인과 전투가 진행됩니다.\n같은 카드 3장은 자동으로 더 높은 별 등급이 됩니다."


func get_next_goal_text(limit: int = 5) -> String:
	var goals: Array[String] = []
	_add_next_goal(goals, Enums.CommanderType.STRATEGIST,
		"전략가: 필드 유닛 50기 보유")
	_add_next_goal(goals, Enums.CommanderType.SMITH,
		"단조사: 업그레이드 10개 장착")
	_add_next_goal(goals, Enums.CommanderType.COLLECTOR,
		"수집가: 서로 다른 카드 7종 필드")
	_add_next_goal(goals, Enums.CommanderType.RAIDER,
		"약탈자: 한 런 5연승")
	_add_next_goal(goals, Enums.CommanderType.ALCHEMIST,
		"연금술사: 한 런 카드 10장 판매")
	if not is_talisman_unlocked(Enums.TalismanType.MERCURY_DROP):
		goals.append("수은 방울: 성장 효과 50회")
	if not is_talisman_unlocked(Enums.TalismanType.CRACKED_EGG):
		goals.append("깨진 알: ★2+ 카드 3장 보유")
	if not is_talisman_unlocked(Enums.TalismanType.RUSTY_WRENCH):
		goals.append("녹슨 렌치/터진 자루: 업그레이드 8개 장착")
	if not is_talisman_unlocked(Enums.TalismanType.SOUL_JAR):
		goals.append("영혼 항아리: 한 런 카드 5장 판매")
	if goals.is_empty():
		return "다음 목표\n기본 업적 해금을 모두 완료했습니다."
	var shown: Array[String] = []
	for i in mini(limit, goals.size()):
		shown.append("- %s" % goals[i])
	return "다음 목표\n%s" % "\n".join(shown)


func get_last_unlock_text() -> String:
	if last_unlocks.is_empty():
		return ""
	return "최근 해금\n%s" % "\n".join(last_unlocks)


func record_run_finished(victory: bool, final_round: int, run_stats: Dictionary = {}) -> Array[String]:
	runs_finished += 1
	best_round = maxi(best_round, final_round)
	var unlocks: Array[String] = []
	_apply_achievement_unlocks(run_stats, unlocks)
	if victory:
		wins += 1
		last_result = "victory"
		_unlock_next_difficulty(unlocks)
		_unlock_difficulty_talisman(selected_difficulty, unlocks)
	else:
		last_result = "defeat"
	last_unlocks = unlocks
	_sanitize()
	return unlocks


func _read_config(cfg: ConfigFile) -> void:
	unlocked_commanders = _to_int_array(
		cfg.get_value("unlocks", "commanders", default_unlocked_commanders()))
	unlocked_talismans = _to_int_array(
		cfg.get_value("unlocks", "talismans", default_unlocked_talismans()))
	max_difficulty_unlocked = int(cfg.get_value("unlocks", "max_difficulty", 1))
	completed_achievements = _to_string_array(
		cfg.get_value("unlocks", "completed_achievements", []))
	last_unlocks = _to_string_array(cfg.get_value("unlocks", "last_unlocks", []))
	selected_difficulty = int(cfg.get_value("run", "selected_difficulty", 1))
	tutorial_seen = bool(cfg.get_value("run", "tutorial_seen", false))
	runs_started = int(cfg.get_value("stats", "runs_started", 0))
	runs_finished = int(cfg.get_value("stats", "runs_finished", 0))
	wins = int(cfg.get_value("stats", "wins", 0))
	best_round = int(cfg.get_value("stats", "best_round", 0))
	last_result = str(cfg.get_value("stats", "last_result", ""))


func _sanitize() -> void:
	unlocked_commanders = _sanitize_commanders(unlocked_commanders)
	unlocked_talismans = _sanitize_talismans(unlocked_talismans)
	if unlocked_commanders.is_empty():
		unlocked_commanders = default_unlocked_commanders()
	if unlocked_talismans.is_empty():
		unlocked_talismans = default_unlocked_talismans()
	completed_achievements = _sanitize_string_set(completed_achievements)
	last_unlocks = _sanitize_string_set(last_unlocks)
	max_difficulty_unlocked = clampi(max_difficulty_unlocked, 1, MAX_DIFFICULTY)
	selected_difficulty = clampi(selected_difficulty, 1, max_difficulty_unlocked)
	runs_started = maxi(0, runs_started)
	runs_finished = maxi(0, runs_finished)
	wins = clampi(wins, 0, runs_finished)
	best_round = clampi(best_round, 0, Enums.MAX_ROUNDS)


func _add_next_goal(goals: Array[String], commander_type: int, text: String) -> void:
	if not is_commander_unlocked(commander_type):
		goals.append(text)


func _apply_achievement_unlocks(run_stats: Dictionary, unlocks: Array[String]) -> void:
	if int(run_stats.get("max_field_units", 0)) >= 50:
		_complete_achievement(ACH_FIELD_50_UNITS)
		_unlock_commander(Enums.CommanderType.STRATEGIST, unlocks)
	if int(run_stats.get("max_attached_upgrades", 0)) >= 10:
		_complete_achievement(ACH_UPGRADES_10)
		_unlock_commander(Enums.CommanderType.SMITH, unlocks)
	if int(run_stats.get("max_unique_field_cards", 0)) >= 7:
		_complete_achievement(ACH_UNIQUE_7)
		_unlock_commander(Enums.CommanderType.COLLECTOR, unlocks)
	if int(run_stats.get("best_win_streak", 0)) >= 5:
		_complete_achievement(ACH_WIN_STREAK_5)
		_unlock_commander(Enums.CommanderType.RAIDER, unlocks)
	if int(run_stats.get("cards_sold", 0)) >= 10:
		_complete_achievement(ACH_CARDS_SOLD_10)
		_unlock_commander(Enums.CommanderType.ALCHEMIST, unlocks)

	if int(run_stats.get("growth_events", 0)) >= 50:
		_complete_achievement(ACH_GROWTH_50)
		_unlock_talisman(Enums.TalismanType.MERCURY_DROP, unlocks)
	if int(run_stats.get("max_star2_cards", 0)) >= 3:
		_complete_achievement(ACH_STAR2_3)
		_unlock_talisman(Enums.TalismanType.CRACKED_EGG, unlocks)
	if bool(run_stats.get("unit_advantage_win", false)):
		_complete_achievement(ACH_UNIT_ADVANTAGE_WIN)
		_unlock_talisman(Enums.TalismanType.WAR_DRUM, unlocks)
	if int(run_stats.get("max_attached_upgrades", 0)) >= 8:
		_complete_achievement(ACH_UPGRADES_8)
		_unlock_talisman(Enums.TalismanType.RUSTY_WRENCH, unlocks)
		_unlock_talisman(Enums.TalismanType.BURST_SACK, unlocks)
	if int(run_stats.get("cards_sold", 0)) >= 5:
		_complete_achievement(ACH_CARDS_SOLD_5)
		_unlock_talisman(Enums.TalismanType.SOUL_JAR, unlocks)


func _complete_achievement(achievement_id: String) -> void:
	if not completed_achievements.has(achievement_id):
		completed_achievements.append(achievement_id)


func _unlock_commander(commander_type: int, unlocks: Array[String]) -> void:
	if is_commander_unlocked(commander_type):
		return
	unlocked_commanders.append(commander_type)
	var data := Commander.get_data(commander_type)
	_append_unlock(unlocks, "커맨더: %s" % data.get("name", str(commander_type)))


func _unlock_talisman(talisman_type: int, unlocks: Array[String]) -> void:
	if is_talisman_unlocked(talisman_type):
		return
	unlocked_talismans.append(talisman_type)
	var data := Talisman.get_data(talisman_type)
	_append_unlock(unlocks, "부적: %s" % data.get("name", str(talisman_type)))


func _unlock_next_difficulty(unlocks: Array[String]) -> void:
	var next_difficulty := mini(MAX_DIFFICULTY, selected_difficulty + 1)
	if next_difficulty > max_difficulty_unlocked:
		max_difficulty_unlocked = next_difficulty
		_append_unlock(unlocks, "난이도 %d" % next_difficulty)


func _unlock_difficulty_talisman(cleared_difficulty: int, unlocks: Array[String]) -> void:
	match cleared_difficulty:
		2:
			_unlock_talisman(Enums.TalismanType.GLASS_EYE, unlocks)
		3:
			_unlock_talisman(Enums.TalismanType.COPPER_WIRE, unlocks)
		5:
			_unlock_talisman(Enums.TalismanType.GOLDEN_DIE, unlocks)
		7:
			_unlock_talisman(Enums.TalismanType.WAR_DRUM, unlocks)


func _append_unlock(unlocks: Array[String], text: String) -> void:
	if not unlocks.has(text):
		unlocks.append(text)


func _count_unlocked_rows(rows: Array[Dictionary]) -> int:
	var total := 0
	for row in rows:
		if bool(row.get("unlocked", false)):
			total += 1
	return total


func _append_unlock_lines(lines: PackedStringArray,
		rows: Array[Dictionary]) -> void:
	for row in rows:
		var state := "해금" if bool(row.get("unlocked", false)) else "잠김"
		var goal := str(row.get("goal", ""))
		lines.append("- %s: %s (%s)" % [row.get("name", "???"), state, goal])


func _append_achievement_lines(lines: PackedStringArray,
		rows: Array[Dictionary], completed: bool) -> void:
	var added := false
	for row in rows:
		if bool(row.get("completed", false)) != completed:
			continue
		lines.append("- %s" % row.get("name", "???"))
		added = true
	if not added:
		lines.append("- 없음")


func _sanitize_commanders(values: Array[int]) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		if value <= Enums.CommanderType.NONE or value >= Enums.CommanderType.size():
			continue
		if not result.has(value):
			result.append(value)
	return result


func _sanitize_talismans(values: Array[int]) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		if value <= Enums.TalismanType.NONE or value >= Enums.TalismanType.size():
			continue
		if not result.has(value):
			result.append(value)
	return result


func _to_int_array(values) -> Array[int]:
	var result: Array[int] = []
	if values is Array:
		for value in values:
			result.append(int(value))
	return result


func _to_string_array(values) -> Array[String]:
	var result: Array[String] = []
	if values is Array:
		for value in values:
			result.append(str(value))
	return result


func _sanitize_string_set(values: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		if value == "":
			continue
		if not result.has(value):
			result.append(value)
	return result
