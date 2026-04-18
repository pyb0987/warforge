extends RefCounted
## AI Theme Scorer — theme_state 기반 스코어링.
##
## _score_card()와 _card_value()에서 호출되어 테마 축적 상태
## (나무, 랭크, 제조 카운터 등)를 읽고 보너스/페널티를 반환한다.
##
## 신규 ai_params (Tier 1):
##   tree_value_per, rank_value_per, counter_near_bonus,
##   unit_cap_penalty, theme_state_weight

const GenomeScript = preload("res://sim/genome.gd")

# --- 군대 랭크 임계값 (R4/R10 milestone 시스템, trace 012 재설계) ---
# 모든 군대 카드가 R4/R10에서 r_conditional 효과 발동.
# ml_barracks ★3은 추가로 rank 15에서 high_rank_mult (ATK x1.3).
# {card_id: [threshold_ranks]}
const RANK_THRESHOLDS := {
	"ml_barracks": [4, 10, 15],
	"ml_conscript": [4, 10],
	"ml_outpost": [4, 10],
	"ml_academy": [4, 10],
	"ml_supply": [4, 10],
	"ml_tactical": [4, 10],
	"ml_assault": [4, 10],
	"ml_special_ops": [4, 10],
	"ml_factory": [4, 10],
	"ml_command": [4, 10],
}

# --- 스팀펑크 카운터 임계값 ---
const MANUFACTURE_THRESHOLD := 10
const RARE_COUNTER_THRESHOLD := 20
const EPIC_COUNTER_THRESHOLD := 15
const CONSCRIPT_THRESHOLD := {1: 10, 2: 8, 3: 6}  # star → threshold

# --- 드루이드 유닛캡 ---
const DRUID_WORLD_UNIT_CAP := {1: 20, 2: 40, 3: 200}
const DRUID_WRATH_UNIT_CAP := {1: 5, 2: 6, 3: 7}

# --- 드루이드 나무 임계값 (r_conditional 유형 임박 보너스용) ---
# tree_bonus.thresh (dr_deep), terazin_thresh (dr_grace), tree_distribute tiers (dr_wt_root).
# {card_id: {star: [thresholds]}}
const TREE_THRESHOLDS := {
	"dr_deep":    {1: [10], 2: [8], 3: [8]},
	"dr_grace":   {1: [10], 2: [8], 3: [8]},
	"dr_wt_root": {1: [4, 8], 2: [3, 6], 3: [3, 6]},
}

# --- 드루이드 빌드 타입 분류 (payoff↔producer 시너지 감지) ---
# payoff: 나무 축적을 적극 소비/스케일링 (T3+ 및 dr_grace/dr_spore_cloud).
const DRUID_PAYOFF := ["dr_deep", "dr_wt_root", "dr_grace", "dr_spore_cloud", "dr_wrath", "dr_world"]
# producer: 주로 나무 생산(+부가 효과), tree_add 반복 소스.
const DRUID_PRODUCER := ["dr_cradle", "dr_origin", "dr_lifebeat", "dr_earth"]

# --- 군대 트레이닝 카드 (trace 012 재설계 후 train: action 보유 카드) ---
# ml_barracks(기본 훈련), ml_academy(훈련+강화 변환), ml_command(부활+글로벌 훈련)
const MILITARY_TRAINING_CARDS := ["ml_barracks", "ml_academy", "ml_command"]
# 앰프: 훈련된 유닛의 가치를 증폭(rank_buff로 rank 스케일링, enhance_convert로 강화 전환)
const MILITARY_TRAINING_AMPLIFIERS := ["ml_tactical", "ml_academy"]

# --- CHAIN_PAIRS 교차 보너스 (ai_synergy_data.CHAIN_PAIRS 군대 부분 반영) ---
# TR emitter (round start에 TR 이벤트 방출) → ml_academy listener
const MILITARY_TR_EMITTERS := ["ml_barracks", "ml_command"]
const MILITARY_TR_LISTENERS := ["ml_academy"]
# CO emitter (round start에 CO 이벤트 방출) → outpost/factory listener
const MILITARY_CO_EMITTERS := ["ml_conscript"]
const MILITARY_CO_LISTENERS := ["ml_outpost", "ml_factory"]

# --- Enhanced 유닛 활용 카드 (assault: swarm_buff 가중치, tactical: enhanced shield) ---
const MILITARY_ENHANCED_CONSUMERS := ["ml_assault", "ml_tactical"]

# --- 포식종 유닛캡 카드 ---
const PREDATOR_LOW_UNIT_CARDS := ["pr_apex_hunt"]
const PREDATOR_LOW_UNIT_CAP := 5


# ================================================================
# 구매 스코어 보너스 (상점 카드 평가용)
# ================================================================

## 상점 카드의 테마 컨텍스트 보너스. board_cards는 보드+벤치의 CardInstance 배열.
func score_buy_bonus(card_id: String, tmpl: Dictionary, preferred_theme: int,
		board_cards: Array, genome: RefCounted) -> float:
	var theme: int = tmpl.get("theme", Enums.CardTheme.NEUTRAL)
	if theme == Enums.CardTheme.NEUTRAL or theme == 0:
		return 0.0

	var weight: float = _p(genome, "theme_state_weight", 1.0)
	var bonus := 0.0

	match theme:
		Enums.CardTheme.DRUID:
			bonus += _score_buy_druid(card_id, board_cards, genome)
		Enums.CardTheme.MILITARY:
			bonus += _score_buy_military(card_id, board_cards, genome)
		Enums.CardTheme.PREDATOR:
			bonus += _score_buy_predator(card_id, board_cards, genome)
		Enums.CardTheme.STEAMPUNK:
			bonus += _score_buy_steampunk(card_id, board_cards, genome)

	return bonus * weight


# ================================================================
# 보드 카드 가치 보너스 (판매/정리 판단용)
# ================================================================

## 보유 카드의 축적 상태 기반 가치 보너스.
func card_value_bonus(card: CardInstance, board_cards: Array, genome: RefCounted) -> float:
	var theme: int = card.template.get("theme", Enums.CardTheme.NEUTRAL)
	if theme == Enums.CardTheme.NEUTRAL or theme == 0:
		return 0.0

	var weight: float = _p(genome, "theme_state_weight", 1.0)
	var bonus := 0.0

	match theme:
		Enums.CardTheme.DRUID:
			bonus += _value_druid(card, genome)
		Enums.CardTheme.MILITARY:
			bonus += _value_military(card, board_cards, genome)
		Enums.CardTheme.STEAMPUNK:
			bonus += _value_steampunk(card, genome)
		Enums.CardTheme.PREDATOR:
			bonus += _value_predator(card, genome)

	return bonus * weight


# ================================================================
# 드루이드
# ================================================================

func _value_druid(card: CardInstance, genome: RefCounted) -> float:
	var bonus := 0.0
	var trees: int = card.theme_state.get("trees", 0)
	var tree_val: float = _p(genome, "tree_value_per", 2.0)
	var near_bonus: float = _p(genome, "counter_near_bonus", 10.0)

	# 나무 축적 가치
	bonus += trees * tree_val

	# 나무 임계 근접 보너스 (dr_deep tree_bonus, dr_grace terazin_thresh, dr_wt_root tier)
	var cid: String = card.template_id
	if TREE_THRESHOLDS.has(cid):
		var per_star: Dictionary = TREE_THRESHOLDS[cid]
		var thresholds: Array = per_star.get(card.star_level, [])
		for threshold in thresholds:
			if trees >= threshold:
				continue
			var distance: int = threshold - trees
			if distance > 0 and distance <= 2:
				bonus += near_bonus * (1.0 - float(distance - 1) / 2.0)
				break  # 가장 가까운 미달 임계만

	return bonus


func _score_buy_druid(card_id: String, board_cards: Array, genome: RefCounted) -> float:
	var bonus := 0.0
	var cap_penalty: float = _p(genome, "unit_cap_penalty", 15.0)

	# 유닛캡 페널티: dr_world의 unit_cap은 자신(dr_world) stack에만 적용.
	# 타 드루이드 카드의 유닛 수는 무관 — forest_depth만 기여.
	for c in board_cards:
		if c is CardInstance and c.template_id == "dr_world":
			var cap: int = DRUID_WORLD_UNIT_CAP.get(c.star_level, 20)
			var own_units: int = c.get_total_units()
			if own_units > 0:
				var ratio: float = float(own_units) / float(cap)
				if ratio > 0.8:
					bonus -= cap_penalty * (ratio - 0.8) / 0.2
			break

	# payoff 카드 보유 시 producer 구매 보너스 (forest_depth 공급 목적)
	var has_payoff := false
	for c in board_cards:
		if c is CardInstance and c.template_id in DRUID_PAYOFF:
			has_payoff = true
			break

	if has_payoff and card_id in DRUID_PRODUCER:
		bonus += 4.0

	return bonus


# ================================================================
# 군대
# ================================================================

func _value_military(card: CardInstance, board_cards: Array, genome: RefCounted) -> float:
	var bonus := 0.0
	var rank: int = card.theme_state.get("rank", 0)
	var rank_val: float = _p(genome, "rank_value_per", 3.0)
	var near_bonus: float = _p(genome, "counter_near_bonus", 10.0)

	# 랭크 축적 가치
	bonus += rank * rank_val

	# Enhanced 유닛 활용 카드(assault/tactical): 보드의 강화 유닛 수에 비례해 가치↑.
	# 근거: ml_assault swarm_buff enhanced_weight, ml_tactical enhanced shield bonus.
	if card.template_id in MILITARY_ENHANCED_CONSUMERS:
		var enh_total: int = _count_enhanced_units(board_cards)
		# cap 20기 기준 선형 스케일: 20기 = +10 가치. 1기당 +0.5.
		bonus += min(enh_total, 20) * 0.5

	# 임계 근접 보너스
	var cid: String = card.template_id
	if RANK_THRESHOLDS.has(cid):
		var rank_triggers: Dictionary = card.theme_state.get("rank_triggers", {})
		for threshold in RANK_THRESHOLDS[cid]:
			if rank_triggers.has(threshold):
				continue  # 이미 발동됨
			var distance: int = threshold - rank
			if distance > 0 and distance <= 2:
				bonus += near_bonus * (1.0 - float(distance - 1) / 2.0)
				break  # 가장 가까운 미발동 임계값만

	# 징집 카운터 근접
	var conscript_counter: int = card.theme_state.get("conscript_counter", 0)
	if conscript_counter > 0:
		var threshold: int = CONSCRIPT_THRESHOLD.get(card.star_level, 10)
		var remaining: int = threshold - conscript_counter
		if remaining > 0 and remaining <= 2:
			bonus += near_bonus * 0.5

	return bonus


func _score_buy_military(card_id: String, board_cards: Array, genome: RefCounted) -> float:
	var bonus := 0.0

	# 트레이닝 앰프 보유 시 트레이닝 카드 구매 보너스
	var has_amplifier := false
	for c in board_cards:
		if c is CardInstance and c.template_id in MILITARY_TRAINING_AMPLIFIERS:
			has_amplifier = true
			break

	if has_amplifier and card_id in MILITARY_TRAINING_CARDS:
		bonus += 5.0

	# ml_command 보유 시 다른 군대 카드 가치 증가 (전체 트레이닝)
	var has_command := false
	for c in board_cards:
		if c is CardInstance and c.template_id == "ml_command":
			has_command = true
			break

	if has_command and card_id != "ml_command":
		var tmpl := CardDB.get_template(card_id) if CardDB else {}
		var ct: int = tmpl.get("theme", 0) if tmpl else 0
		if ct == Enums.CardTheme.MILITARY:
			bonus += 3.0  # ml_command가 모든 군대 카드를 트레이닝

	# 크로스 체인 보너스 (CHAIN_PAIRS 완성 유도)
	var board_ids: Array[String] = []
	for c in board_cards:
		if c is CardInstance:
			board_ids.append(c.template_id)

	# TR 체인: listener(academy) 보유 시 emitter(barracks/command) 구매 ↑,
	#          emitter 보유 & listener 없음 시 listener 구매 ↑
	var has_tr_listener: bool = _any_in(board_ids, MILITARY_TR_LISTENERS)
	var has_tr_emitter: bool = _any_in(board_ids, MILITARY_TR_EMITTERS)
	if has_tr_listener and card_id in MILITARY_TR_EMITTERS:
		bonus += 4.0
	if has_tr_emitter and not has_tr_listener and card_id in MILITARY_TR_LISTENERS:
		bonus += 4.0

	# CO 체인: listener(outpost/factory) 보유 시 emitter(conscript) 구매 ↑,
	#          emitter 보유 & listener 없음 시 listener 구매 ↑
	var has_co_listener: bool = _any_in(board_ids, MILITARY_CO_LISTENERS)
	var has_co_emitter: bool = _any_in(board_ids, MILITARY_CO_EMITTERS)
	if has_co_listener and card_id in MILITARY_CO_EMITTERS:
		bonus += 4.0
	if has_co_emitter and not has_co_listener and card_id in MILITARY_CO_LISTENERS:
		bonus += 4.0

	return bonus


# ================================================================
# 군대 헬퍼
# ================================================================

func _count_enhanced_units(board_cards: Array) -> int:
	var total := 0
	for c in board_cards:
		if c is CardInstance:
			for s in c.stacks:
				var ut_tags: PackedStringArray = s["unit_type"].get("tags", PackedStringArray())
				if "enhanced" in ut_tags:
					total += s["count"]
	return total


func _any_in(ids: Array[String], targets: Array) -> bool:
	for t in targets:
		if t in ids:
			return true
	return false


# ================================================================
# 스팀펑크
# ================================================================

func _value_steampunk(card: CardInstance, genome: RefCounted) -> float:
	var bonus := 0.0
	var near_bonus: float = _p(genome, "counter_near_bonus", 10.0)

	# 제조 카운터 근접 (sp_charger)
	var mfg_counter: int = card.theme_state.get("manufacture_counter", 0)
	if mfg_counter > 0:
		var remaining: int = MANUFACTURE_THRESHOLD - mfg_counter
		if remaining > 0 and remaining <= 3:
			bonus += near_bonus * (1.0 - float(remaining - 1) / 3.0)

	# 레어 카운터 근접 (★2 sp_charger)
	var rare_counter: int = card.theme_state.get("rare_counter", 0)
	if rare_counter > 0:
		var remaining: int = RARE_COUNTER_THRESHOLD - rare_counter
		if remaining > 0 and remaining <= 4:
			bonus += near_bonus * 0.7

	# 에픽 카운터 근접 (★3 sp_charger)
	var epic_counter: int = card.theme_state.get("epic_counter", 0)
	if epic_counter > 0:
		var remaining: int = EPIC_COUNTER_THRESHOLD - epic_counter
		if remaining > 0 and remaining <= 3:
			bonus += near_bonus * 1.0  # 에픽은 최대 보너스

	return bonus


func _score_buy_steampunk(card_id: String, board_cards: Array, genome: RefCounted) -> float:
	var bonus := 0.0

	# sp_charger 보유 시 MF 이벤트 생산 카드 보너스
	var has_charger := false
	for c in board_cards:
		if c is CardInstance and c.template_id == "sp_charger":
			has_charger = true
			break

	if has_charger and card_id in ["sp_assembly", "sp_furnace", "sp_workshop", "sp_line"]:
		bonus += 4.0  # MF 이벤트 → sp_charger 카운터 가속

	return bonus


# ================================================================
# 포식종
# ================================================================

func _value_predator(card: CardInstance, genome: RefCounted) -> float:
	var bonus := 0.0

	# death_atk_bonus (pr_transcend 축적)
	var death_bonus: float = card.theme_state.get("death_atk_bonus", 0.0)
	if death_bonus > 0.0:
		bonus += death_bonus * 100.0  # 0.03 → +3, 0.05 → +5 정도의 가치

	return bonus


func _score_buy_predator(card_id: String, board_cards: Array, genome: RefCounted) -> float:
	var bonus := 0.0
	var cap_penalty: float = _p(genome, "unit_cap_penalty", 15.0)

	# pr_apex_hunt 보유 시: 유닛 수 체크
	var has_apex := false
	var apex_units := 0
	for c in board_cards:
		if c is CardInstance and c.template_id == "pr_apex_hunt":
			has_apex = true
			apex_units = c.get_total_units()
			break

	# pr_apex_hunt가 유닛 5개 이하 조건이므로, 유닛 추가 카드 구매에 주의
	if has_apex and apex_units >= 4:
		# 이미 근접 — 유닛 폭증 카드 페널티
		if card_id in ["pr_queen", "pr_nest", "pr_transcend"]:
			bonus -= cap_penalty * 0.3  # 가벼운 경고

	# pr_molt/pr_harvest 보유 시 해치 카드 보너스 (META 체인 활성화)
	var has_meta_consumer := false
	for c in board_cards:
		if c is CardInstance and c.template_id in ["pr_molt", "pr_harvest", "pr_carapace"]:
			has_meta_consumer = true
			break

	if has_meta_consumer and card_id in ["pr_nest", "pr_queen", "pr_farm", "pr_transcend"]:
		bonus += 4.0  # 해치 → META 체인 시너지

	return bonus


# ================================================================
# 유틸리티
# ================================================================

func _p(genome: RefCounted, key: String, fallback: float) -> float:
	if genome and genome.has_method("get_ai_param"):
		return genome.get_ai_param(key)
	return GenomeScript.DEFAULT_AI_PARAMS.get(key, fallback)
