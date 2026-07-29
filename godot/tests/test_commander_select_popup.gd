extends GutTest
## Commander selection popup contract for run start.

const PopupScene = preload("res://scenes/ui/commander_select_popup.tscn")

var _popup = null


func before_each() -> void:
	_popup = PopupScene.instantiate()
	add_child_autofree(_popup)


func test_show_choices_lists_all_playable_commanders() -> void:
	_popup.show_choices()

	var types: Array = _popup.get_selectable_types()
	assert_eq(types.size(), Enums.CommanderType.size() - 1,
		"NONE 제외 7종 커맨더 선택지")
	assert_false(Enums.CommanderType.NONE in types, "NONE은 선택지에 없음")
	assert_eq(_popup.get_node("VBox/ChoiceGrid").get_child_count(), 7,
		"선택 카드 7개 생성")


func test_show_choices_can_filter_unlocked_commanders() -> void:
	_popup.show_choices([Enums.CommanderType.GAMBLER, Enums.CommanderType.BREEDER])
	assert_eq(_popup.get_node("VBox/ChoiceGrid").get_child_count(), 2,
		"해금된 커맨더만 표시")


func test_context_text_explains_commander_role() -> void:
	_popup.show_choices([Enums.CommanderType.GAMBLER, Enums.CommanderType.BREEDER])

	assert_string_contains(_popup.get_context_text(), "커맨더")
	assert_string_contains(_popup.get_context_text(), "런 전체")
	var rect: Dictionary = _popup.get_context_rect()
	assert_gt(float(rect.get("w", 0.0)), 0.0)
	assert_gt(float(rect.get("h", 0.0)), 0.0)
	assert_true(bool(rect.get("visible", false)))


func test_choice_summaries_report_rendered_commander_cards() -> void:
	_popup.show_choices([Enums.CommanderType.GAMBLER, Enums.CommanderType.BREEDER])

	var summaries: Array = _popup.get_choice_summaries()
	assert_eq(summaries.size(), 2)
	assert_eq(summaries[0]["id"], str(Enums.CommanderType.GAMBLER))
	assert_eq(summaries[0]["idx"], 0)
	assert_string_contains(str(summaries[0]["name"]), "도박꾼")
	assert_string_contains(str(summaries[0]["desc"]), "리롤")
	assert_string_contains(str(summaries[0]["text"]), "도박꾼")
	assert_string_contains(str(summaries[0]["text"]), "리롤")
	var rect: Dictionary = summaries[0].get("rect", {})
	assert_gt(float(rect.get("w", 0.0)), 0.0)
	assert_gt(float(rect.get("h", 0.0)), 0.0)
	assert_true(bool(rect.get("visible", false)))


func test_select_commander_emits_type_and_closes() -> void:
	var emitted: Array = []
	_popup.commander_selected.connect(func(t: int): emitted.append(t))

	_popup.show_choices()
	_popup.select_commander(Enums.CommanderType.GAMBLER)

	assert_eq(emitted, [Enums.CommanderType.GAMBLER],
		"선택한 commander type emit")
	assert_false(_popup.visible, "선택 후 팝업 닫힘")
