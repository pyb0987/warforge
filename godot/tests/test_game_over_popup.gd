extends GutTest

const PopupScene = preload("res://scenes/ui/game_over_popup.tscn")

var _popup = null


func before_each() -> void:
	_popup = PopupScene.instantiate()
	add_child_autofree(_popup)


func test_show_result_formats_victory_unlock_recap_with_overflow() -> void:
	_popup.show_result(
		true,
		15,
		7,
		[
			"난이도 2",
			"커맨더: 전략가",
			"커맨더: 단조사",
			"부적: 영혼 항아리",
		],
		{
			"run_stats": {
				"max_field_units": 44,
				"max_attached_upgrades": 3,
				"best_win_streak": 5,
			},
			"boss_rewards": 3,
		})

	var summary: String = _popup.summary_label.text
	assert_true(_popup.visible)
	assert_eq(_popup.title_label.text, "VICTORY!")
	assert_string_contains(summary, "All 15 rounds cleared!")
	assert_string_contains(summary, "Run bests: 44 field units, 3 upgrades, 5-win streak, 3 boss rewards")
	assert_false(summary.contains("Next run:"))
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
	assert_string_contains(_popup.summary_label.text, "Final HP: -2")
	assert_false(_popup.summary_label.text.contains("New unlocks available"))


func test_show_result_formats_defeat_final_battle_context() -> void:
	_popup.show_result(false, 8, -11, [], {
		"final_battle": {
			"ally_survived": 0,
			"enemy_survived": 21,
			"damage": 15,
			"hp_before": 4,
			"hp_after": -11,
		},
		"run_stats": {
			"max_field_units": 38,
			"max_attached_upgrades": 2,
			"best_win_streak": 2,
		},
		"boss_rewards": 1,
	})

	var summary: String = _popup.summary_label.text
	assert_string_contains(summary, "Defeated at round 8")
	assert_string_contains(summary, "Final HP: -11")
	assert_string_contains(summary, "Last fight: 0 allies / 21 enemies survived")
	assert_string_contains(summary, "Damage: 15 HP (4 -> -11)")
	assert_string_contains(summary, "Run bests: 38 field units, 2 upgrades, 2-win streak, 1 boss reward")
	assert_string_contains(summary,
		"Next run: last fight left 21 enemies; add damage or growth before the R8 boss.")


func test_show_result_formats_defeat_next_run_hint_without_battle_context() -> void:
	_popup.show_result(false, 3, -1, [], {
		"run_stats": {
			"max_attached_upgrades": 0,
		},
	})

	var summary: String = _popup.summary_label.text
	assert_string_contains(summary, "Defeated at round 3")
	assert_string_contains(summary,
		"Next run: attach upgrades before the R4 boss.")
