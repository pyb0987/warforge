extends GutTest
## Run start screen contract for G-4.

const ScreenScene = preload("res://scenes/ui/run_start_screen.tscn")
const MainScene = preload("res://scenes/main.tscn")
const MetaProgressScript = preload("res://core/meta_progress.gd")

var _screen = null


func before_each() -> void:
	_screen = ScreenScene.instantiate()
	add_child_autofree(_screen)


func test_show_progress_displays_profile_summary() -> void:
	var progress = MetaProgressScript.new()
	progress.runs_started = 4
	progress.wins = 2
	progress.best_round = 13
	progress.max_difficulty_unlocked = 2
	progress.selected_difficulty = 2

	_screen.show_progress(progress)

	assert_true(_screen.visible)
	assert_string_contains(_screen.get_node("VBox/StatsLabel").text, "Runs 4")
	assert_string_contains(_screen.get_node("VBox/StatsLabel").text, "Wins 2")
	assert_string_contains(_screen.get_node("VBox/StatsLabel").text, "Best R13")
	assert_string_contains(_screen.get_node("VBox/DifficultyRow/DifficultyLabel").text, "2 / 2")
	assert_string_contains(_screen.get_node("VBox/UnlocksLabel").text, "도박꾼")
	assert_string_contains(_screen.get_node("VBox/UnlocksLabel").text, "부싯돌")
	assert_string_contains(_screen.get_node("VBox/GoalsLabel").text, "다음 목표")
	assert_string_contains(_screen.get_node("VBox/GoalsLabel").text, "전략가")
	assert_true(_screen.get_node("VBox/GuideLabel").visible)
	assert_string_contains(_screen.get_node("VBox/GuideLabel").text, "첫 런 가이드")
	assert_false(_screen.get_node("VBox/ProgressDetailsScroll").visible)


func test_progress_screen_shows_recent_unlocks_and_hides_seen_tutorial() -> void:
	var progress = MetaProgressScript.new()
	progress.mark_tutorial_seen()
	progress.last_unlocks.append("커맨더: 단조사")
	progress.last_unlocks.append("부적: 영혼 항아리")

	_screen.show_progress(progress)

	assert_false(_screen.get_node("VBox/GuideLabel").visible)
	assert_true(_screen.get_node("VBox/RecentUnlocksLabel").visible)
	assert_string_contains(_screen.get_node("VBox/RecentUnlocksLabel").text, "단조사")
	assert_string_contains(_screen.get_node("VBox/RecentUnlocksLabel").text, "영혼 항아리")


func test_progress_details_toggle_shows_unlock_statuses() -> void:
	var progress = MetaProgressScript.new()
	progress.completed_achievements.append(MetaProgressScript.ACH_GROWTH_50)
	progress.unlocked_talismans.append(Enums.TalismanType.MERCURY_DROP)

	_screen.show_progress(progress)
	_screen.get_node("VBox/ProgressDetailsButton").pressed.emit()

	assert_true(_screen.get_node("VBox/ProgressDetailsScroll").visible)
	var details: String = _screen.get_node(
		"VBox/ProgressDetailsScroll/ProgressDetailsLabel").text
	assert_string_contains(details, "진행 상세")
	assert_string_contains(details, "커맨더 2/7")
	assert_string_contains(details, "단조사: 잠김")
	assert_string_contains(details, "수은 방울: 해금")
	assert_string_contains(details, "완료 업적")
	assert_string_contains(details, "성장 효과 50회")

	_screen.get_node("VBox/ProgressDetailsButton").pressed.emit()
	assert_false(_screen.get_node("VBox/ProgressDetailsScroll").visible)


func test_start_button_emits_start_requested() -> void:
	var emitted := [0]
	_screen.start_requested.connect(func(): emitted[0] += 1)
	_screen.show_progress(MetaProgressScript.new())
	_screen.get_node("VBox/StartButton").pressed.emit()
	assert_eq(emitted[0], 1)


func test_difficulty_buttons_update_selected_difficulty() -> void:
	var progress = MetaProgressScript.new()
	progress.max_difficulty_unlocked = 3
	progress.selected_difficulty = 2
	var emitted: Array[int] = []
	_screen.difficulty_changed.connect(func(difficulty: int): emitted.append(difficulty))

	_screen.show_progress(progress)
	_screen.get_node("VBox/DifficultyRow/DifficultyUpButton").pressed.emit()
	assert_eq(progress.selected_difficulty, 3, "위 버튼으로 D3 선택")
	assert_true(_screen.get_node("VBox/DifficultyRow/DifficultyUpButton").disabled,
		"최대 난이도에서 위 버튼 비활성")
	assert_eq(emitted, [3], "변경 신호 emit")

	_screen.get_node("VBox/DifficultyRow/DifficultyDownButton").pressed.emit()
	assert_eq(progress.selected_difficulty, 2, "아래 버튼으로 D2 선택")
	assert_eq(emitted, [3, 2], "두 번째 변경 신호 emit")


func test_main_scene_includes_run_start_screen() -> void:
	var main = MainScene.instantiate()
	assert_not_null(main.get_node_or_null("UILayer/RunStartScreen"),
		"Main scene에 RunStartScreen 배치")
	main.free()
