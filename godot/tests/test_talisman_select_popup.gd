extends GutTest
## Talisman selection popup contract for run start.

const PopupScene = preload("res://scenes/ui/talisman_select_popup.tscn")
const MainScene = preload("res://scenes/main.tscn")

var _popup = null


func before_each() -> void:
	_popup = PopupScene.instantiate()
	add_child_autofree(_popup)


func test_show_choices_lists_all_playable_talismans() -> void:
	_popup.show_choices()

	var types: Array = _popup.get_selectable_types()
	assert_eq(types.size(), Enums.TalismanType.size() - 1,
		"NONE 제외 12종 부적 선택지")
	assert_false(Enums.TalismanType.NONE in types, "NONE은 선택지에 없음")
	assert_eq(_popup.get_node("VBox/ChoiceGrid").get_child_count(), 12,
		"선택 카드 12개 생성")


func test_show_choices_can_filter_unlocked_talismans() -> void:
	_popup.show_choices([
		Enums.TalismanType.FLINT,
		Enums.TalismanType.TWO_FACED_COIN,
		Enums.TalismanType.CRACKED_SKULL,
	])
	assert_eq(_popup.get_node("VBox/ChoiceGrid").get_child_count(), 3,
		"해금된 부적만 표시")


func test_select_talisman_emits_type_and_closes() -> void:
	var emitted: Array = []
	_popup.talisman_selected.connect(func(t: int): emitted.append(t))

	_popup.show_choices()
	_popup.select_talisman(Enums.TalismanType.FLINT)

	assert_eq(emitted, [Enums.TalismanType.FLINT],
		"선택한 talisman type emit")
	assert_false(_popup.visible, "선택 후 팝업 닫힘")


func test_main_scene_includes_talisman_popup() -> void:
	var main = MainScene.instantiate()
	assert_not_null(main.get_node_or_null("UILayer/TalismanSelectPopup"),
		"Main scene에 TalismanSelectPopup 배치")
	main.free()
