extends ColorRect
## First screen for profile summary and beginning a new run.

signal start_requested
signal difficulty_changed(difficulty: int)

@onready var stats_label: Label = $VBox/StatsLabel
@onready var unlocks_label: Label = $VBox/UnlocksLabel
@onready var recent_unlocks_label: Label = $VBox/RecentUnlocksLabel
@onready var goals_label: Label = $VBox/GoalsLabel
@onready var guide_label: Label = $VBox/GuideLabel
@onready var progress_details_button: Button = $VBox/ProgressDetailsButton
@onready var progress_details_scroll: ScrollContainer = $VBox/ProgressDetailsScroll
@onready var progress_details_label: Label = \
	$VBox/ProgressDetailsScroll/ProgressDetailsLabel
@onready var difficulty_down_button: Button = $VBox/DifficultyRow/DifficultyDownButton
@onready var difficulty_label: Label = $VBox/DifficultyRow/DifficultyLabel
@onready var difficulty_up_button: Button = $VBox/DifficultyRow/DifficultyUpButton
@onready var start_button: Button = $VBox/StartButton

var _progress = null
var _details_visible := false


func _ready() -> void:
	visible = false
	difficulty_down_button.pressed.connect(_change_difficulty.bind(-1))
	difficulty_up_button.pressed.connect(_change_difficulty.bind(1))
	progress_details_button.pressed.connect(_toggle_progress_details)
	start_button.pressed.connect(func(): start_requested.emit())
	_update_progress_details()


func show_progress(progress) -> void:
	_progress = progress
	_refresh()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func hide_screen() -> void:
	visible = false


func _refresh() -> void:
	if _progress == null:
		return
	stats_label.text = "Runs %d  Wins %d  Best R%d" % [
		_progress.runs_started,
		_progress.wins,
		_progress.best_round,
	]
	difficulty_label.text = "Difficulty %d / %d" % [
		_progress.selected_difficulty,
		_progress.max_difficulty_unlocked,
	]
	difficulty_down_button.disabled = _progress.selected_difficulty <= 1
	difficulty_up_button.disabled = \
		_progress.selected_difficulty >= _progress.max_difficulty_unlocked
	unlocks_label.text = "Commanders: %s\nTalismans: %s" % [
		_names_for_commanders(_progress.get_unlocked_commanders()),
		_names_for_talismans(_progress.get_unlocked_talismans()),
	]
	recent_unlocks_label.text = _progress.get_last_unlock_text()
	recent_unlocks_label.visible = recent_unlocks_label.text != ""
	goals_label.text = _progress.get_next_goal_text()
	guide_label.text = _progress.get_tutorial_text()
	guide_label.visible = _progress.should_show_tutorial()
	progress_details_label.text = _progress.get_full_progress_text()
	_update_progress_details()


func _change_difficulty(delta: int) -> void:
	if _progress == null:
		return
	var before: int = _progress.selected_difficulty
	_progress.set_selected_difficulty(before + delta)
	_refresh()
	if _progress.selected_difficulty != before:
		difficulty_changed.emit(_progress.selected_difficulty)


func _toggle_progress_details() -> void:
	_details_visible = not _details_visible
	_update_progress_details()


func _update_progress_details() -> void:
	if progress_details_scroll:
		progress_details_scroll.visible = _details_visible
	if progress_details_button:
		progress_details_button.text = "HIDE PROGRESS" if _details_visible else "PROGRESS"


func _names_for_commanders(types: Array[int]) -> String:
	var names: Array[String] = []
	for commander_type in types:
		var data := Commander.get_data(commander_type)
		names.append(data.get("name", str(commander_type)))
	return ", ".join(names)


func _names_for_talismans(types: Array[int]) -> String:
	var names: Array[String] = []
	for talisman_type in types:
		var data := Talisman.get_data(talisman_type)
		names.append(data.get("name", str(talisman_type)))
	return ", ".join(names)
