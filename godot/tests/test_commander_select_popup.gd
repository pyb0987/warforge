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


func test_select_commander_emits_type_and_closes() -> void:
	var emitted: Array = []
	_popup.commander_selected.connect(func(t: int): emitted.append(t))

	_popup.show_choices()
	_popup.select_commander(Enums.CommanderType.GAMBLER)

	assert_eq(emitted, [Enums.CommanderType.GAMBLER],
		"선택한 commander type emit")
	assert_false(_popup.visible, "선택 후 팝업 닫힘")
