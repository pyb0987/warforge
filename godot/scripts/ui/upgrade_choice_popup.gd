extends ColorRect
## Modal popup: shows N upgrade choices, player picks 1.
## Used for ★2 merge (rare) and ★3 merge (epic) bonus selection.

signal upgrade_chosen(upgrade_id: String)

var _choice_ids: Array[String] = []
var _choice_visuals: Array = []
var _rng: RandomNumberGenerator

@onready var title_label: Label = $VBox/TitleLabel
@onready var choice_container: HBoxContainer = $VBox/ChoiceContainer

var _rarity_titles := {
	Enums.UpgradeRarity.RARE: "레어 업그레이드 선택 (★2 보너스)",
	Enums.UpgradeRarity.EPIC: "에픽 업그레이드 선택 (★3 보너스)",
}


func setup(rng: RandomNumberGenerator) -> void:
	_rng = rng
	visible = false


func show_choices(rarity: int, count: int = 3) -> void:
	_cleanup()

	title_label.text = _rarity_titles.get(rarity, "업그레이드 선택")

	# Pick distinct random upgrades
	var pool := UpgradeDB.get_ids_by_rarity(rarity)
	pool.shuffle()
	var pick_count := mini(count, pool.size())

	for i in pick_count:
		var uid: String = pool[i]
		_choice_ids.append(uid)
		var vis: Panel = preload("res://scenes/build/upgrade_visual.tscn").instantiate()
		vis.custom_minimum_size = Vector2(160, 180)
		choice_container.add_child(vis)
		vis.call("setup_upgrade", uid, false)  # no cost for free bonus
		vis.gui_input.connect(_on_choice_input.bind(i))
		_choice_visuals.append(vis)

	visible = true
	# Block input below this popup
	mouse_filter = Control.MOUSE_FILTER_STOP


func _on_choice_input(event: InputEvent, idx: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if idx < 0 or idx >= _choice_ids.size():
		return

	var chosen_id: String = _choice_ids[idx]
	upgrade_chosen.emit(chosen_id)
	_cleanup()
	visible = false


func _cleanup() -> void:
	for v in _choice_visuals:
		v.queue_free()
	_choice_visuals.clear()
	_choice_ids.clear()
