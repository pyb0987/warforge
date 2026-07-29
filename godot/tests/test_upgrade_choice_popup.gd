extends GutTest
## Upgrade choice popup selection contract for merge and reward gates.

const PopupScene = preload("res://scenes/ui/upgrade_choice_popup.tscn")

var _popup = null


func before_each() -> void:
	_popup = PopupScene.instantiate()
	add_child_autofree(_popup)


func test_select_choice_index_emits_choice_and_cleans_up() -> void:
	var emitted: Array[String] = []
	_popup.upgrade_chosen.connect(func(upgrade_id: String): emitted.append(upgrade_id))

	_popup.show_choices(Enums.UpgradeRarity.RARE, 2)
	var choices: Array[String] = _popup.get_choice_ids()

	assert_eq(choices.size(), 2)
	assert_true(_popup.select_choice_index(1),
		"valid choice index is accepted")
	assert_eq(emitted.size(), 1)
	assert_eq(emitted[0], choices[1])
	assert_false(_popup.visible, "selection closes popup")
	assert_eq(_popup.get_choice_ids().size(), 0,
		"selection clears stored choice ids")


func test_select_choice_index_rejects_invalid_choice_without_cleanup() -> void:
	var emitted: Array[String] = []
	_popup.upgrade_chosen.connect(func(upgrade_id: String): emitted.append(upgrade_id))

	_popup.show_choices(Enums.UpgradeRarity.RARE, 1)
	var choices: Array[String] = _popup.get_choice_ids()

	assert_false(_popup.select_choice_index(4),
		"out-of-range choice index is rejected")
	assert_eq(emitted.size(), 0)
	assert_true(_popup.visible, "invalid selection leaves popup open")
	assert_eq(_popup.get_choice_ids(), choices)
