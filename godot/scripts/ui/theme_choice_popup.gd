extends ColorRect
## Modal popup: ne_masquerade SELL flow 의 테마 선택.
## 5 테마 (NEUTRAL/STEAMPUNK/DRUID/PREDATOR/MILITARY) 중 offer_count 만큼
## 무작위 추출하여 버튼으로 노출. 사용자가 1개를 선택하면 theme_chosen emit.
## ESC / 바깥 클릭 무시 — game_manager 의 atomic transform 흐름을 안전하게 닫기 위해.

signal theme_chosen(theme_int: int)

@onready var title_label: Label = $VBox/TitleLabel
@onready var choice_container: HBoxContainer = $VBox/ChoiceContainer

var _rng: RandomNumberGenerator
var _emitted: bool = false

const _THEME_NAMES := {
	Enums.CardTheme.NEUTRAL: "중립",
	Enums.CardTheme.STEAMPUNK: "스팀펑크",
	Enums.CardTheme.DRUID: "드루이드",
	Enums.CardTheme.PREDATOR: "포식종",
	Enums.CardTheme.MILITARY: "군대",
}


func setup(rng: RandomNumberGenerator) -> void:
	_rng = rng
	visible = false


## offer_count: 노출할 테마 수 (1~5).
## current_theme: 대상 카드의 현재 theme. allow_self=false 면 풀에서 제외.
## allow_self: 대상 자기 테마 포함 가능 여부 (yaml transform_theme.allow_self).
func show_choices(offer_count: int, current_theme: int, allow_self: bool) -> void:
	_cleanup()
	_emitted = false
	title_label.text = "변환할 테마 선택"

	var pool: Array[int] = [
		Enums.CardTheme.NEUTRAL,
		Enums.CardTheme.STEAMPUNK,
		Enums.CardTheme.DRUID,
		Enums.CardTheme.PREDATOR,
		Enums.CardTheme.MILITARY,
	]
	if not allow_self:
		pool.erase(current_theme)
	pool.shuffle()
	var pick_count: int = mini(offer_count, pool.size())

	for i in pick_count:
		var theme_int: int = pool[i]
		var btn := Button.new()
		btn.text = _THEME_NAMES.get(theme_int, "?")
		btn.custom_minimum_size = Vector2(140, 80)
		btn.pressed.connect(_on_choice_pressed.bind(theme_int))
		choice_container.add_child(btn)

	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func _on_choice_pressed(theme_int: int) -> void:
	if _emitted:
		return
	_emitted = true
	theme_chosen.emit(theme_int)
	_cleanup()
	visible = false


func _cleanup() -> void:
	for c in choice_container.get_children():
		c.queue_free()
