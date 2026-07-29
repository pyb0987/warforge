extends GutTest
## Boss reward popup selection contract for live run gates.

const PopupScene = preload("res://scenes/ui/boss_reward_popup.tscn")

var _popup = null


func before_each() -> void:
	_popup = PopupScene.instantiate()
	add_child_autofree(_popup)


func test_select_choice_index_emits_choice_and_cleans_up() -> void:
	var emitted: Array[String] = []
	_popup.reward_selected.connect(func(reward_id: String): emitted.append(reward_id))

	var rewards: Array[String] = ["r4_2", "r4_3"]
	_popup.show_choices(rewards)

	assert_eq(_popup.get_choice_ids(), rewards)
	assert_true(_popup.select_choice_index(1),
		"valid choice index is accepted")
	assert_eq(emitted.size(), 1)
	assert_eq(emitted[0], "r4_3")
	assert_false(_popup.visible, "selection closes popup")
	assert_eq(_popup.get_choice_ids().size(), 0,
		"selection clears stored choice ids")


func test_select_choice_index_rejects_invalid_choice_without_cleanup() -> void:
	var emitted: Array[String] = []
	_popup.reward_selected.connect(func(reward_id: String): emitted.append(reward_id))

	var rewards: Array[String] = ["r4_2"]
	_popup.show_choices(rewards)

	assert_false(_popup.select_choice_index(4),
		"out-of-range choice index is rejected")
	assert_eq(emitted.size(), 0)
	assert_true(_popup.visible, "invalid selection leaves popup open")
	assert_eq(_popup.get_choice_ids(), rewards)


func test_choice_summaries_report_rendered_reward_text() -> void:
	var rewards: Array[String] = ["r4_1", "r4_2"]
	_popup.show_choices(rewards)

	var summaries: Array = _popup.get_choice_summaries()

	assert_eq(summaries.size(), 2)
	var first: Dictionary = summaries[0]
	assert_eq(first.get("id", ""), "r4_1")
	assert_eq(int(first.get("idx", -1)), 0)
	assert_string_contains(str(first.get("name", "")), "긴급 보급")
	assert_string_contains(str(first.get("type", "")), "즉시")
	assert_string_contains(str(first.get("desc", "")), "테라진")
	assert_true(bool(first.get("needs_target", false)))
	assert_string_contains(str(first.get("text", "")), str(first.get("name", "")))
	assert_string_contains(str(first.get("text", "")), str(first.get("desc", "")))
	var rect: Dictionary = first.get("rect", {})
	assert_gt(float(rect.get("w", 0.0)), 0.0)
	assert_gt(float(rect.get("h", 0.0)), 0.0)

	var second: Dictionary = summaries[1]
	assert_eq(second.get("id", ""), "r4_2")
	assert_false(bool(second.get("needs_target", true)))
