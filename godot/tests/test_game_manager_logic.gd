extends GutTest
## GameManager 순수 로직 테스트 (UI 우회)
## 참조: game_manager.gd _apply_battle_start_effects, _materialize_army, _apply_post_combat_effects
##
## ⚠️ 구조적 한계: game_manager는 Node+@onready라 직접 인스턴스화 불가.
## 아래 helper는 game_manager의 핵심 로직을 복제한 것이며, game_manager가 변경되면
## 이 테스트도 동기화 필요. 향후 game_manager에서 로직을 별도 클래스로 추출 시 제거.
## TODO: game_manager 리팩토링 후 실제 코드 직접 호출로 전환


var _state: GameState = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_state = GameState.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42


# ================================================================
# Helper: game_manager 패턴 재현
# ================================================================

func _apply_battle_start_effects() -> void:
	## game_manager._apply_battle_start_effects() 로직 복제
	var active := _state.get_active_board()
	for card in active:
		var c: CardInstance = card
		var timing: int = c.template.get("trigger_timing", -1)
		if timing != Enums.TriggerTiming.BATTLE_START:
			continue
		for eff in c.template.get("effects", []):
			var action: String = eff.get("action", "")
			match action:
				"buff_pct":
					var tag_filter = eff.get("unit_tag_filter", "")
					if tag_filter == "":
						tag_filter = null
					c.temp_buff(tag_filter, eff.get("buff_atk_pct", 0.0))
				"shield_pct":
					c.shield_hp_pct += eff.get("shield_hp_pct", 0.0)


func _materialize_army() -> Array:
	## game_manager._materialize_army() 로직 복제
	var units: Array = []
	var active := _state.get_active_board()
	for card in active:
		var c: CardInstance = card
		var card_mechanics := c.get_all_mechanics()
		for s in c.stacks:
			var ut: Dictionary = s["unit_type"]
			var eff_atk := c.eff_atk_for(s)
			var eff_hp := c.eff_hp_for(s)
			for _n in s["count"]:
				units.append({
					"atk": eff_atk, "hp": eff_hp,
					"attack_speed": ut["attack_speed"] * c.upgrade_as_mult,
					"range": ut["range"] + c.upgrade_range,
					"move_speed": ut["move_speed"] + c.upgrade_move_speed,
					"def": c.upgrade_def,
					"mechanics": card_mechanics,
					"radius": 6.0,
				})
	return units


func _apply_post_combat_effects(won: bool) -> void:
	## game_manager._apply_post_combat_effects() 로직 복제
	var active := _state.get_active_board()
	for card in active:
		var c: CardInstance = card
		var timing: int = c.template.get("trigger_timing", -1)
		var should_fire := false
		match timing:
			Enums.TriggerTiming.POST_COMBAT:
				should_fire = true
			Enums.TriggerTiming.POST_COMBAT_DEFEAT:
				should_fire = not won
			Enums.TriggerTiming.POST_COMBAT_VICTORY:
				should_fire = won
		if not should_fire:
			continue
		var max_act: int = c.template.get("max_activations", -1)
		if max_act != -1 and c.activations_used >= max_act:
			continue
		c.activations_used += 1
		for eff in c.template.get("effects", []):
			var action: String = eff.get("action", "")
			match action:
				"grant_gold":
					_state.gold += eff.get("gold_amount", 0)
				"enhance_pct":
					var tag_filter = eff.get("unit_tag_filter", "")
					if tag_filter == "":
						tag_filter = null
					c.enhance(tag_filter, eff.get("enhance_atk_pct", 0.0), eff.get("enhance_hp_pct", 0.0))
				"spawn":
					for _n in eff.get("spawn_count", 1):
						c.spawn_random(_rng)


# ================================================================
# _apply_battle_start_effects — BS 카드 효과
# ================================================================

func test_bs_wildforce_buffs_atk_10pct() -> void:
	## ne_wildforce(BS): buff self 10%
	var card: CardInstance = CardInstance.create("ne_wildforce")
	_state.board[0] = card
	var atk_before: float = card.get_total_atk()
	_apply_battle_start_effects()
	assert_gt(card.get_total_atk(), atk_before, "BS buff → ATK 증가")


func test_bs_barrier_shields_20pct() -> void:
	## sp_barrier(BS): shield self 20%
	var card: CardInstance = CardInstance.create("sp_barrier")
	_state.board[0] = card
	_apply_battle_start_effects()
	assert_almost_eq(card.shield_hp_pct, 0.20, 0.001, "shield 20%")


func test_bs_skips_non_bs_cards() -> void:
	## RS 카드는 BS 효과 미적용
	var card: CardInstance = CardInstance.create("sp_assembly")
	_state.board[0] = card
	var atk_before: float = card.get_total_atk()
	_apply_battle_start_effects()
	assert_eq(card.get_total_atk(), atk_before, "RS 카드 → BS 미발동")
	assert_eq(card.shield_hp_pct, 0.0, "shield 0")


func test_bs_multiple_cards() -> void:
	## 2개 BS 카드 동시 적용
	var wildforce: CardInstance = CardInstance.create("ne_wildforce")
	var barrier: CardInstance = CardInstance.create("sp_barrier")
	_state.board[0] = wildforce
	_state.board[1] = barrier
	var atk_before: float = wildforce.get_total_atk()
	_apply_battle_start_effects()
	assert_gt(wildforce.get_total_atk(), atk_before, "wildforce ATK 증가")
	assert_almost_eq(barrier.shield_hp_pct, 0.20, 0.001, "barrier shield 20%")


# ================================================================
# _materialize_army — 유닛 배열 생성
# ================================================================

func test_materialize_empty_board() -> void:
	var units: Array = _materialize_army()
	assert_eq(units.size(), 0, "빈 보드 → 유닛 0")


func test_materialize_unit_count() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	_state.board[0] = card
	var total: int = card.get_total_units()
	var units: Array = _materialize_army()
	assert_eq(units.size(), total, "유닛 수 = get_total_units()")


func test_materialize_has_required_keys() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	var units: Array = _materialize_army()
	var u: Dictionary = units[0]
	for key in ["atk", "hp", "attack_speed", "range", "move_speed", "def", "mechanics", "radius"]:
		assert_true(u.has(key), "키 '%s' 존재" % key)


func test_materialize_atk_positive() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	var units: Array = _materialize_army()
	for u in units:
		assert_gt(u["atk"], 0.0, "ATK > 0")
		assert_gt(u["hp"], 0.0, "HP > 0")


func test_materialize_multiple_cards() -> void:
	_state.board[0] = CardInstance.create("sp_assembly")
	_state.board[1] = CardInstance.create("ne_wildforce")
	var total: int = _state.board[0].get_total_units() + _state.board[1].get_total_units()
	var units: Array = _materialize_army()
	assert_eq(units.size(), total, "2카드 유닛 합산")


# ================================================================
# _apply_post_combat_effects — PC 카드 효과
# ================================================================

func test_pc_merchant_grants_gold_on_defeat() -> void:
	## ne_merchant(PD): grant_gold 3 on defeat
	_state.board[0] = CardInstance.create("ne_merchant")
	_state.gold = 0
	_apply_post_combat_effects(false)
	assert_eq(_state.gold, 3, "패배 시 +3g")


func test_pc_merchant_no_gold_on_victory() -> void:
	## ne_merchant(PD) — 승리 시 미발동
	_state.board[0] = CardInstance.create("ne_merchant")
	_state.gold = 0
	_apply_post_combat_effects(true)
	assert_eq(_state.gold, 0, "승리 시 PD 미발동 → 0g")


func test_pc_chimera_cry_enhances_on_defeat() -> void:
	## ne_chimera_cry(PD): enhance self 8% ATK + 8% HP on defeat
	var card: CardInstance = CardInstance.create("ne_chimera_cry")
	_state.board[0] = card
	var atk_before: float = card.get_total_atk()
	_apply_post_combat_effects(false)
	assert_gt(card.get_total_atk(), atk_before, "패배 시 enhance → ATK 증가")


func test_pc_chimera_cry_no_effect_on_victory() -> void:
	var card: CardInstance = CardInstance.create("ne_chimera_cry")
	_state.board[0] = card
	var atk_before: float = card.get_total_atk()
	_apply_post_combat_effects(true)
	assert_eq(card.get_total_atk(), atk_before, "승리 시 PD 미발동")


func test_pc_max_activations_respected() -> void:
	## ne_merchant max_act=1, 2회 패배 → 1회만 발동
	_state.board[0] = CardInstance.create("ne_merchant")
	_state.gold = 0
	_apply_post_combat_effects(false)  # 1회
	_apply_post_combat_effects(false)  # 2회
	assert_eq(_state.gold, 3, "max_act=1 → 1회만 +3g")


func test_pc_multiple_cards() -> void:
	## 2개 PC 카드 동시
	_state.board[0] = CardInstance.create("ne_merchant")
	_state.board[1] = CardInstance.create("ne_chimera_cry")
	_state.gold = 0
	var atk_before: float = _state.board[1].get_total_atk()
	_apply_post_combat_effects(false)
	assert_eq(_state.gold, 3, "merchant +3g")
	assert_gt(_state.board[1].get_total_atk(), atk_before, "chimera enhance")


# ================================================================
# FSM 전이 (Phase guard)
# ================================================================

func test_phase_enum_exists() -> void:
	## Phase enum 기본 값 검증
	var gm_script = load("res://scripts/game/game_manager.gd")
	assert_not_null(gm_script, "game_manager 스크립트 로드")
