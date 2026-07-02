extends GutTest
## MetaProgress save/default contract for run-start unlocks.

const MetaProgressScript = preload("res://core/meta_progress.gd")
const TEST_PATH := "user://meta_progress_test.cfg"


func test_defaults_match_initial_unlock_design() -> void:
	var progress = MetaProgressScript.new()
	assert_eq(progress.get_unlocked_commanders(), [
		Enums.CommanderType.GAMBLER,
		Enums.CommanderType.BREEDER,
	])
	assert_eq(progress.get_unlocked_talismans(), [
		Enums.TalismanType.FLINT,
		Enums.TalismanType.TWO_FACED_COIN,
		Enums.TalismanType.CRACKED_SKULL,
	])
	assert_eq(progress.max_difficulty_unlocked, 1)
	assert_eq(progress.selected_difficulty, 1)
	assert_true(progress.should_show_tutorial())
	assert_eq(progress.get_completed_achievements(), [])


func test_full_progress_text_lists_locked_and_completed_goals() -> void:
	var progress = MetaProgressScript.new()

	var initial_text: String = progress.get_full_progress_text()
	assert_string_contains(initial_text, "커맨더 2/7")
	assert_string_contains(initial_text, "도박꾼: 해금")
	assert_string_contains(initial_text, "단조사: 잠김")
	assert_string_contains(initial_text, "부적 3/12")
	assert_string_contains(initial_text, "부싯돌: 해금")
	assert_string_contains(initial_text, "터진 자루: 잠김")
	assert_string_contains(initial_text, "완료 업적\n- 없음")
	assert_string_contains(initial_text, "잠긴 목표")
	assert_string_contains(initial_text, "업그레이드 10개 장착")

	progress.record_run_finished(false, 9, {
		"max_attached_upgrades": 10,
		"cards_sold": 5,
	})
	var unlocked_text: String = progress.get_full_progress_text()
	assert_string_contains(unlocked_text, "단조사: 해금")
	assert_string_contains(unlocked_text, "녹슨 렌치: 해금")
	assert_string_contains(unlocked_text, "터진 자루: 해금")
	assert_string_contains(unlocked_text, "영혼 항아리: 해금")
	assert_string_contains(unlocked_text, "완료 업적")
	assert_string_contains(unlocked_text, "한 런 카드 5장 판매")


func test_save_load_round_trip() -> void:
	var progress = MetaProgressScript.new()
	progress.unlocked_commanders.append(Enums.CommanderType.SMITH)
	progress.unlocked_talismans.append(Enums.TalismanType.RUSTY_WRENCH)
	progress.runs_started = 3
	progress.runs_finished = 2
	progress.wins = 1
	progress.best_round = 12
	progress.max_difficulty_unlocked = 2
	progress.selected_difficulty = 2
	progress.mark_tutorial_seen()
	progress.completed_achievements.append(MetaProgressScript.ACH_UPGRADES_10)
	progress.last_unlocks.append("커맨더: 단조사")
	assert_eq(progress.save(TEST_PATH), OK)

	var loaded = MetaProgressScript.new()
	loaded.load_or_create(TEST_PATH)
	assert_true(loaded.is_commander_unlocked(Enums.CommanderType.SMITH))
	assert_true(loaded.is_talisman_unlocked(Enums.TalismanType.RUSTY_WRENCH))
	assert_eq(loaded.runs_started, 3)
	assert_eq(loaded.runs_finished, 2)
	assert_eq(loaded.wins, 1)
	assert_eq(loaded.best_round, 12)
	assert_eq(loaded.max_difficulty_unlocked, 2)
	assert_eq(loaded.selected_difficulty, 2)
	assert_false(loaded.should_show_tutorial())
	assert_true(loaded.get_completed_achievements().has(MetaProgressScript.ACH_UPGRADES_10))
	assert_eq(loaded.last_unlocks, ["커맨더: 단조사"])


func test_record_run_started_and_finished() -> void:
	var progress = MetaProgressScript.new()
	progress.record_run_started()
	progress.record_run_finished(false, 7)
	assert_eq(progress.runs_started, 1)
	assert_eq(progress.runs_finished, 1)
	assert_eq(progress.wins, 0)
	assert_eq(progress.best_round, 7)
	assert_eq(progress.last_result, "defeat")
	assert_eq(progress.max_difficulty_unlocked, 1)

	progress.record_run_started()
	progress.record_run_finished(true, Enums.MAX_ROUNDS)
	assert_eq(progress.runs_started, 2)
	assert_eq(progress.runs_finished, 2)
	assert_eq(progress.wins, 1)
	assert_eq(progress.best_round, Enums.MAX_ROUNDS)
	assert_eq(progress.last_result, "victory")
	assert_eq(progress.max_difficulty_unlocked, 2)


func test_achievement_stats_unlock_commanders_and_talismans() -> void:
	var progress = MetaProgressScript.new()
	var unlocks: Array[String] = progress.record_run_finished(false, 9, {
		"max_field_units": 50,
		"max_attached_upgrades": 10,
		"max_unique_field_cards": 7,
		"best_win_streak": 5,
		"cards_sold": 10,
		"growth_events": 50,
		"max_star2_cards": 3,
		"unit_advantage_win": true,
	})

	assert_true(progress.is_commander_unlocked(Enums.CommanderType.STRATEGIST))
	assert_true(progress.is_commander_unlocked(Enums.CommanderType.SMITH))
	assert_true(progress.is_commander_unlocked(Enums.CommanderType.COLLECTOR))
	assert_true(progress.is_commander_unlocked(Enums.CommanderType.RAIDER))
	assert_true(progress.is_commander_unlocked(Enums.CommanderType.ALCHEMIST))
	assert_true(progress.is_talisman_unlocked(Enums.TalismanType.MERCURY_DROP))
	assert_true(progress.is_talisman_unlocked(Enums.TalismanType.CRACKED_EGG))
	assert_true(progress.is_talisman_unlocked(Enums.TalismanType.WAR_DRUM))
	assert_true(progress.is_talisman_unlocked(Enums.TalismanType.RUSTY_WRENCH))
	assert_true(progress.is_talisman_unlocked(Enums.TalismanType.BURST_SACK))
	assert_true(progress.is_talisman_unlocked(Enums.TalismanType.SOUL_JAR))
	assert_true(progress.get_completed_achievements().has(MetaProgressScript.ACH_FIELD_50_UNITS))
	assert_false(unlocks.has("난이도 2"), "패배 업적은 난이도를 열지 않음")

	var repeat_unlocks: Array[String] = progress.record_run_finished(false, 10, {
		"max_attached_upgrades": 10,
		"cards_sold": 10,
	})
	assert_eq(repeat_unlocks, [], "이미 열린 업적 보상은 중복 표시하지 않음")


func test_victory_unlocks_next_difficulty_and_clear_talisman() -> void:
	var progress = MetaProgressScript.new()
	progress.max_difficulty_unlocked = 2
	progress.selected_difficulty = 2

	var unlocks: Array[String] = progress.record_run_finished(true, Enums.MAX_ROUNDS)

	assert_eq(progress.max_difficulty_unlocked, 3)
	assert_true(progress.is_talisman_unlocked(Enums.TalismanType.GLASS_EYE))
	assert_true(unlocks.has("난이도 3"))
	assert_true(progress.last_unlocks.has("난이도 3"))
