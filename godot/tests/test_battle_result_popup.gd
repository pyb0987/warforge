extends GutTest

const BattleResultPopupScene = preload("res://scenes/ui/battle_result_popup.tscn")


func test_show_result_formats_victory_aftermath_context() -> void:
	var popup = BattleResultPopupScene.instantiate()
	add_child_autofree(popup)

	popup.show_result(true, 2, 0, 3, 0, 1, {
		"round": 4,
		"ally_start": 8,
		"enemy_start": 9,
		"hp_before": 24,
		"hp_after": 24,
		"gold_before": 10,
		"gold_after": 14,
		"next_hint": "choose boss reward before next BUILD",
	})

	assert_true(popup.visible)
	assert_eq(popup.get_result_text(), "VICTORY")
	var detail: String = str(popup.get_detail_text())
	assert_string_contains(detail, "Round 4 cleared")
	assert_string_contains(detail, "Allies: 2/8 survived")
	assert_string_contains(detail, "HP: 24 -> 24 (+0)")
	assert_string_contains(detail, "Gold: 10 -> 14 (+3 win, +1 cards)")
	assert_string_contains(detail, "Next: choose boss reward before next BUILD")
	assert_eq(popup.get_summary_text(), "Next: choose boss reward before next BUILD")


func test_show_result_formats_defeat_damage_context() -> void:
	var popup = BattleResultPopupScene.instantiate()
	add_child_autofree(popup)

	popup.show_result(false, 0, 3, 0, -2, 0, {
		"round": 3,
		"ally_start": 4,
		"enemy_start": 9,
		"hp_before": 30,
		"hp_after": 28,
		"damage": 2,
		"gold_before": 12,
		"gold_after": 12,
		"next_hint": "return to BUILD after income",
	})

	assert_eq(popup.get_result_text(), "DEFEAT")
	var detail: String = str(popup.get_detail_text())
	assert_string_contains(detail, "Round 3 lost")
	assert_string_contains(detail, "Enemies: 3/9 survived; damage 2")
	assert_string_contains(detail, "HP: 30 -> 28 (-2)")
	assert_string_contains(detail, "Gold: 12 -> 12 (+0 win, +0 cards)")
	assert_string_contains(detail, "Next: return to BUILD after income")
