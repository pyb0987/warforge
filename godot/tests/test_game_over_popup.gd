extends GutTest

const PopupScene = preload("res://scenes/ui/game_over_popup.tscn")

var _popup = null


func before_each() -> void:
	_popup = PopupScene.instantiate()
	add_child_autofree(_popup)


func test_show_result_formats_victory_unlock_recap_with_overflow() -> void:
	_popup.show_result(true, 15, 7, [
		"난이도 2",
		"커맨더: 전략가",
		"커맨더: 단조사",
		"부적: 영혼 항아리",
	])

	var summary: String = _popup.summary_label.text
	assert_true(_popup.visible)
	assert_eq(_popup.title_label.text, "VICTORY!")
	assert_string_contains(summary, "All 15 rounds cleared!")
	assert_string_contains(summary, "New unlocks available")
	assert_string_contains(summary, "- 난이도 2")
	assert_string_contains(summary, "- 커맨더: 전략가")
	assert_string_contains(summary, "- 커맨더: 단조사")
	assert_false(summary.contains("- 부적: 영혼 항아리"))
	assert_string_contains(summary, "+1 more unlocked - all available in PROGRESS")


func test_show_result_omits_unlock_recap_when_empty() -> void:
	_popup.show_result(false, 8, -2)

	assert_true(_popup.visible)
	assert_eq(_popup.title_label.text, "GAME OVER")
	assert_string_contains(_popup.summary_label.text, "Defeated at round 8")
	assert_false(_popup.summary_label.text.contains("New unlocks available"))
