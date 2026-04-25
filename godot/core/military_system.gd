class_name MilitarySystem
extends "res://core/theme_system.gd"
## Military theme system: rank/training + conscription.
## RS cards (barracks, outpost, special_ops, command) train/conscript;
## OE cards (academy, conscript_react, factory) chain off TRAIN/CONSCRIPT events.

# Conscription pool (2026-04-21 해석 B 재설계):
#   base pool 에서 **동등 확률** 1종 뽑기 → 해당 항목의 count 만큼 유닛 추가.
#   R4 도달 카드: ENHANCED_MAP 으로 변환 (base → enhanced 동일 slot 교체).
#   R10 도달 카드: 위 + ELITE_UNITS 에서 1기 보너스 추가.
# Data source: data/cards/military.yaml 최상단 conscript_pool + elite_units.
# codegen_card_db.py 가 godot/core/data/conscript_pool_data.gd 로 생성.
const PoolData = preload("res://core/data/conscript_pool_data.gd")

# Base → Enhanced 유닛 ID 매핑 (6쌍, units-military.md 참조).
# _conscript 의 R4 자동 변환 (해석 B) 에서 사용. 2026-04-21 이후로
# enhance_convert_card action 은 폐기됨 (카드 내 기존 유닛 소급 변환 기능).
const ENHANCED_MAP: Dictionary = {
	"ml_recruit":  "ml_recruit_enhanced",
	"ml_infantry": "ml_infantry_enhanced",
	"ml_shield":   "ml_shield_enhanced",
	"ml_drone":    "ml_drone_enhanced",
	"ml_biker":    "ml_biker_enhanced",
	"ml_plasma":   "ml_plasma_enhanced",
}

# pending_conscriptions / clear_pending / pick_conscript_options / apply_conscript
# 제거됨 (2026-04-21): 3택1 UI 가 실전 트리거 되지 않아 dead feature 였음.
# ml_conscript self 징집은 이제 _outpost() 가 자동 랜덤으로 즉시 처리.


# --- Chain integration ---


func process_rs_card(card: CardInstance, idx: int, board: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	# 징병국↔전진기지 스왑 (trace 012):
	#   ml_conscript: T1 RS self 징집 생성 (기존 _outpost 로직)
	#   ml_outpost: T2 OE CO 반응 증폭 (아래 process_event_card)
	match card.get_base_id():
		"ml_barracks": return _barracks(card, idx, board)
		"ml_conscript": return _outpost(card, idx, board, rng)
		"ml_assault": return _assault_rs(card, idx, board, rng)
		"ml_special_ops": return _special_ops(card, idx, board, rng)
		"ml_command": return _command(card, idx, board)
		"ml_alliance": return _alliance_rs(card, idx, board)
	return Enums.empty_result()


func process_event_card(card: CardInstance, idx: int, board: Array,
		event: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	match card.get_base_id():
		"ml_academy": return _academy(card, idx, board, event, rng)
		"ml_outpost": return _conscript_react(card, idx, board, event, rng)
		"ml_factory": return _factory_collect_tr(card, event)
	return Enums.empty_result()


# --- External hooks (combat engine) ---


func apply_battle_start(card: CardInstance, idx: int, board: Array) -> Dictionary:
	match card.get_base_id():
		"ml_tactical": return _tactical_battle(card, idx, board)
		"ml_assault": return _assault_battle(card, idx, board)
		"ml_alliance": return _alliance_bs(card, idx, board)
	return Enums.empty_result()


func apply_post_combat(card: CardInstance, idx: int, board: Array,
		won: bool) -> Dictionary:
	match card.get_base_id():
		"ml_supply": return _supply_post(card, idx, board, won)
		"ml_factory": return _factory_pc(card, board)
	return Enums.empty_result()


## NOTE: apply_persistent(ml_command) 제거 (2026-04-16, trace 012 후속 cleanup).
## 이전에는 이곳에서 theme_state["revive_hp_pct/limit"]을 설정했으나,
## chain_engine.process_persistent는 PERSISTENT timing 카드만 순회함 (ml_command는 RS).
## 결과: 이 경로는 한 번도 실행되지 않았고, revive는 실제로 동작 안 했음.
## 수정: game_manager._materialize_army가 아래 두 helper를 호출해 YAML을 직접 평가.


# --- Command (통합사령부) revive scope resolution ---
#
# Rationale (trace 014): 과거 _materialize_army는 rank 조건으로 scope를
# 하드코딩(`rank >= 10 → 양옆 인접`, `rank >= 4 → self` 등)해, YAML의
# revive_scope_override.target 문자열을 실제로 읽지 않았다. 설계자가 YAML에서
# target을 바꿔도 코드가 따라오지 못하는 drift 위험. 본 helper 2개가 YAML
# target 문자열을 직접 해석한다.


## YAML의 base revive + r_conditional revive_scope_override를 평가해
## 통합사령부의 현재 effective revive config를 반환한다.
## 반환: {"target": String, "hp_pct": float, "limit": int}
##   - target이 빈 문자열이거나 hp_pct/limit이 0 이하면 revive 미동작.
##   - rank_gte 조건이 충족된 r_conditional의 override가 base target을 덮어쓴다.
##   - 여러 milestone이 충족되면 YAML 순서상 마지막 override가 승 (R10 > R4).
func resolve_command_revive(card: CardInstance) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var rank := _rank(card)
	var result := {"target": "", "hp_pct": 0.0, "limit": 0}
	for eff in effs:
		var action: String = eff.get("action", "")
		if action == "revive":
			result["target"] = String(eff.get("target", ""))
			result["hp_pct"] = float(eff.get("hp_pct", 0.0))
			result["limit"] = int(eff.get("limit_per_combat", 0))
		elif action == "r_conditional":
			if eff.get("condition", "") != "rank_gte":
				continue
			if rank < int(eff.get("threshold", 0)):
				continue
			for inner in eff.get("effects", []):
				if inner.get("action", "") == "revive_scope_override":
					var ov_target: String = String(inner.get("target", ""))
					if ov_target != "":
						result["target"] = ov_target
	return result


## YAML target 문자열을 card index 리스트 + enhanced-only 플래그로 해석.
## 반환: {"card_indices": Array[int], "only_enhanced": bool}
## 지원 target:
##   - "self_enhanced": self 카드, (강화) 유닛만
##   - "self_all": self 카드, 모든 유닛
##   - "self_and_adj_all": self + 양옆 인접 카드, 모든 유닛 (인접은 테마 무관)
## 알 수 없는 target은 warning을 띄우고 self_enhanced로 fallback.
func resolve_revive_scope(target_name: String, self_idx: int,
		board_size: int) -> Dictionary:
	var card_indices: Array[int] = []
	var only_enhanced: bool = false
	match target_name:
		"self_enhanced":
			card_indices.append(self_idx)
			only_enhanced = true
		"self_all":
			card_indices.append(self_idx)
		"self_and_adj_all":
			if self_idx - 1 >= 0:
				card_indices.append(self_idx - 1)
			card_indices.append(self_idx)
			if self_idx + 1 < board_size:
				card_indices.append(self_idx + 1)
		_:
			push_warning(
				"[revive_scope] unknown target: %s (fallback: self_enhanced)"
				% target_name)
			card_indices.append(self_idx)
			only_enhanced = true
	return {"card_indices": card_indices, "only_enhanced": only_enhanced}


# --- Rank / Conscription helpers ---


## First-match lookup on theme_effects by (action, target). See predator_system
## for rationale — push_error on duplicate matches guards against silent
## shadowing at _find_eff call sites.
func _find_eff(effs: Array, action: String, target: String = "") -> Dictionary:
	var first := {}
	var matches := 0
	for e in effs:
		if e.get("action") == action:
			if target == "" or e.get("target", "") == target:
				matches += 1
				if matches == 1:
					first = e
	if matches > 1:
		push_error("_find_eff shadowed duplicates: action=%s target=%s matches=%d — use explicit loop" % [action, target, matches])
	return first


func _rank(card: CardInstance) -> int:
	return card.theme_state.get("rank", 0)


func _add_rank(card: CardInstance, n: int) -> void:
	card.theme_state["rank"] = _rank(card) + n


func _train_card(card: CardInstance, idx: int, amount: int) -> Array:
	## Train a card: add rank, return TRAIN events.
	## NOTE: _check_thresholds 호출 제거 (2026-04-16, trace 012 cleanup).
	## rank_threshold 폐기로 해당 함수는 no-op이었음. 완전 제거.
	_add_rank(card, amount)
	return [{
		"layer1": Enums.Layer1.ENHANCED,
		"layer2": Enums.Layer2.TRAIN,
		"source_idx": idx, "target_idx": idx,
	}]


## 군수공장 R4/R10 상점 보너스 누적 계산.
## 반환: {"slot_delta": int, "terazin_discount": int}
## board를 순회하며 모든 ml_factory 카드의 YAML r_conditional에서
## upgrade_shop_bonus 선언을 rank 조건부로 평가.
## Talisman.get_upgrade_shop_slots, upgrade_shop.get_upgrade_cost에서 호출.
static func get_factory_shop_bonus(board: Array) -> Dictionary:
	var slot_delta := 0
	var terazin_discount := 0
	for c in board:
		if c == null:
			continue
		var card: CardInstance = c as CardInstance
		if card == null or card.get_base_id() != "ml_factory":
			continue
		var rank: int = card.theme_state.get("rank", 0)
		var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
		for eff in effs:
			if eff.get("action", "") != "r_conditional":
				continue
			if eff.get("condition", "") != "rank_gte":
				continue
			if rank < int(eff.get("threshold", 0)):
				continue
			for inner in eff.get("effects", []):
				if inner.get("action", "") == "upgrade_shop_bonus":
					slot_delta += int(inner.get("slot_delta", 0))
					terazin_discount += int(inner.get("terazin_discount", 0))
	return {"slot_delta": slot_delta, "terazin_discount": terazin_discount}


## NOTE: _check_thresholds와 get_next_threshold 제거 (2026-04-16, trace 012 cleanup).
## rank_threshold 폐기로 두 함수는 dead code였음.
## 다음 milestone 표시는 card_tooltip이 rank < 4 ? "R4" : rank < 10 ? "R10" : "최대"로
## 직접 계산 (R4/R10 고정 milestone이므로 단순).


## 양성가 보너스 포함 유닛 추가 (이벤트 미방출).
func _add_with_bonus(target: CardInstance, unit_id: String, count: int) -> int:
	var added := target.add_specific_unit(unit_id, count)
	var bonus := CardInstance.roll_bonus_count(added, bonus_spawn_chance, bonus_rng)
	if bonus > 0:
		target.add_specific_unit(unit_id, bonus)
	return added


## 2026-04-21 재설계 (해석 B):
##   tries: 뽑기 반복 횟수 (이전 인터페이스의 count 재해석 — "count=2 라면
##          2 회 뽑기" 의미. 각 뽑기마다 선택된 pool 항목의 count 만큼 유닛 추가).
##   source_card: 이 카드의 rank 기반으로 R4/R10 변환/엘리트 보너스 적용.
##                null 이면 변환 미적용 (ml_outpost 인접 징집 단순 케이스).
##   enhanced_tries: 앞 N 회 뽑기는 rank 무관 강화 변환 **강제** (ml_outpost
##                   enhanced_count 경로). 기본 0.
##   biker_rebirth: ml_biker 가 뽑힐 때마다 "추가 뽑기" 연쇄 (ml_assault 용).
##                  안전장치: MAX_BIKER_REBIRTH_DEPTH 회 초과 시 강제 중단
##                  (P(20연속 biker) = (1/6)^20 ≈ 10^-15, 사실상 도달 불가).
## 반환: 실제로 추가된 총 유닛 수 (cap 반영, 보너스 포함).
const MAX_BIKER_REBIRTH_DEPTH: int = 20

# Transform 모드 (source_card rank 기반, R4/R10 게이트):
# 0: 변환 없음 (rank < 4 또는 source_card null 에 forced_enhance 도 없음)
# 1: 각 유닛 50% 확률 변환 (4 ≤ rank < 10)
# 2: 전체 변환 (rank ≥ 10 또는 enhanced_tries 강제)
enum ConscriptTransform { NONE, PROB_50, ALL }

func _conscript(target: CardInstance, tries: int, rng: RandomNumberGenerator,
		source_card: CardInstance = null, enhanced_tries: int = 0,
		biker_rebirth: bool = false, forced_unit: String = "") -> int:
	var added := 0
	var source_rank: int = _rank(source_card) if source_card != null else 0
	var rank_mode: int = ConscriptTransform.NONE
	if source_rank >= 10:
		rank_mode = ConscriptTransform.ALL
	elif source_rank >= 4:
		rank_mode = ConscriptTransform.PROB_50
	# forced_unit 일 때 elite_bonus 미적용 (R10 효과가 바이커 전원 강화로 이미
	# 반영됨 + ml_assault 정체성상 엘리트 추가 부적합).
	var elite_bonus: bool = source_rank >= 10 and forced_unit == ""
	var forced_enhance: int = clampi(enhanced_tries, 0, tries)

	# forced_unit 경로: pool 뽑기 없이 지정 유닛의 pool entry 를 재사용.
	var forced_entry: Dictionary = _pool_entry_for(forced_unit) if forced_unit != "" else {}

	for i in tries:
		var mode: int = ConscriptTransform.ALL if i < forced_enhance else rank_mode
		if not forced_entry.is_empty():
			# 고정 유닛 경로: biker_rebirth 무관 (항상 같은 유닛이라 재도전 무의미).
			added += _conscript_apply_entry(target, rng, forced_entry, mode)
		else:
			added += _conscript_single_try(target, rng, mode, biker_rebirth)

	# R10: 엘리트 유닛 1 기 보너스 (base 뽑기와 별개).
	if elite_bonus and PoolData.ELITE_UNITS.size() > 0:
		var eidx: int = rng.randi_range(0, PoolData.ELITE_UNITS.size() - 1)
		var elite_id: String = PoolData.ELITE_UNITS[eidx]
		added += target.add_specific_unit(elite_id, 1)

	return added


## Pool base 에서 id 매칭 entry 반환 ({id, count}). 미발견 시 {}.
func _pool_entry_for(unit_id: String) -> Dictionary:
	for entry in PoolData.BASE:
		if entry.get("id", "") == unit_id:
			return entry
	return {}


## _conscript_single_try 의 forced_unit 변형: pool 뽑기 건너뛰고 지정 entry
## 로 변환 적용 + add. biker_rebirth 불지원 (고정 유닛이라 무의미).
func _conscript_apply_entry(target: CardInstance, rng: RandomNumberGenerator,
		entry: Dictionary, transform_mode: int) -> int:
	var uid: String = entry.get("id", "")
	var count: int = int(entry.get("count", 1))
	if uid == "":
		return 0
	var enhanced_id: String = ENHANCED_MAP.get(uid, uid)

	var enhanced_n: int = 0
	match transform_mode:
		ConscriptTransform.ALL:
			enhanced_n = count
		ConscriptTransform.PROB_50:
			for _j in count:
				if rng.randf() < 0.5:
					enhanced_n += 1
		_:
			enhanced_n = 0
	var base_n: int = count - enhanced_n

	var added: int = 0
	if enhanced_n > 0:
		added += target.add_specific_unit(enhanced_id, enhanced_n)
	if base_n > 0:
		added += target.add_specific_unit(uid, base_n)
	# 양성가 보너스.
	if added > 0 and bonus_spawn_chance > 0.0 and bonus_rng != null:
		if bonus_rng.randf() < bonus_spawn_chance:
			added += target.add_specific_unit(uid, 1)
	return added


## 단일 뽑기 1 회 + biker_rebirth 연쇄 처리.
## transform_mode:
##   NONE    → count 기 전부 base uid 로 추가
##   PROB_50 → count 기 각각 50% 확률로 enhanced, 나머지 base
##   ALL     → count 기 전부 enhanced uid 로 추가
## 반환: 이 뽑기 (재뽑기 포함) 로 추가된 총 유닛 수.
func _conscript_single_try(target: CardInstance, rng: RandomNumberGenerator,
		transform_mode: int, biker_rebirth: bool) -> int:
	var added := 0
	var depth := 0
	while true:
		var picked: Dictionary = _uniform_pick(rng)
		var uid: String = picked.get("id", "")
		var count: int = int(picked.get("count", 1))
		if uid == "":
			return added
		var picked_id: String = uid  # biker 판정용 (원본 id)
		var enhanced_id: String = ENHANCED_MAP.get(uid, uid)

		# enhanced_n 결정 (개별 유닛 단위 확률 적용).
		var enhanced_n: int = 0
		match transform_mode:
			ConscriptTransform.ALL:
				enhanced_n = count
			ConscriptTransform.PROB_50:
				for _j in count:
					if rng.randf() < 0.5:
						enhanced_n += 1
			_:
				enhanced_n = 0
		var base_n: int = count - enhanced_n

		var try_added: int = 0
		if enhanced_n > 0:
			try_added += target.add_specific_unit(enhanced_id, enhanced_n)
		if base_n > 0:
			try_added += target.add_specific_unit(uid, base_n)
		added += try_added

		# 양성가 보너스: 징집 1 회당 확률로 1 기 추가 (이벤트 미방출).
		# 원본 base uid 로 추가 (통일).
		if try_added > 0 and bonus_spawn_chance > 0.0 and bonus_rng != null:
			if bonus_rng.randf() < bonus_spawn_chance:
				added += target.add_specific_unit(uid, 1)
		# biker_rebirth: 뽑힌 base 유닛이 ml_biker 면 즉시 추가 뽑기.
		# 안전장치: 최대 MAX_BIKER_REBIRTH_DEPTH 회까지만 연쇄.
		if biker_rebirth and picked_id == "ml_biker" and depth < MAX_BIKER_REBIRTH_DEPTH:
			depth += 1
			continue
		return added
	return added  # unreachable


## Base pool 에서 동등 확률 (uniform) 1 항목 선택.
## 반환: {id: String, count: int}.
func _uniform_pick(rng: RandomNumberGenerator) -> Dictionary:
	if PoolData.BASE.is_empty():
		return {}
	var idx: int = rng.randi_range(0, PoolData.BASE.size() - 1)
	return PoolData.BASE[idx]


func _military_indices(board: Array) -> Array[int]:
	var result: Array[int] = []
	for i in board.size():
		if (board[i] as CardInstance).template.get("theme", -1) == Enums.CardTheme.MILITARY:
			result.append(i)
	return result


func _army_card_count(board: Array) -> int:
	return _military_indices(board).size()


func _conscript_evt(src: int, tgt: int) -> Dictionary:
	return {
		"layer1": Enums.Layer1.UNIT_ADDED,
		"layer2": Enums.Layer2.CONSCRIPT,
		"source_idx": src, "target_idx": tgt,
	}


# ═══════════════════════════════════════════════════════════════════
# R 축 milestone 프레임워크 (trace 012: R4/R10 재설계)
# ═══════════════════════════════════════════════════════════════════

## target 이름을 카드 index 배열로 해석. YAML에서 쓰이는 모든 target 커버.
## - 기본: self, right_adj, left_adj, both_adj, all_military
## - OE 전용: event_target, event_target_adj
## - 차분 확장: far_military (self/인접 제외), far_event_military (event/인접 제외)
func _resolve_targets(target_name: String, self_idx: int, board: Array,
		event: Dictionary = {}) -> Array[int]:
	var result: Array[int] = []
	match target_name:
		"self":
			result.append(self_idx)
		"right_adj":
			var r := self_idx + 1
			if r < board.size() and _is_military(board, r):
				result.append(r)
		"left_adj":
			var l := self_idx - 1
			if l >= 0 and _is_military(board, l):
				result.append(l)
		"both_adj":
			for di in [-1, 1]:
				var ni: int = self_idx + di
				if ni >= 0 and ni < board.size() and _is_military(board, ni):
					result.append(ni)
		"all_military":
			for mi in _military_indices(board):
				result.append(mi)
		"far_military":
			# 군대 카드 중 self와 양옆 인접을 제외한 나머지.
			var excluded: Dictionary = {self_idx: true}
			for di in [-1, 1]:
				excluded[self_idx + di] = true
			for mi in _military_indices(board):
				if not excluded.has(mi):
					result.append(mi)
		"event_target":
			var et: int = event.get("target_idx", -1)
			if et >= 0 and et < board.size():
				result.append(et)
		"event_target_adj":
			var et2: int = event.get("target_idx", -1)
			if et2 >= 0:
				for di in [-1, 1]:
					var ni2: int = et2 + di
					if ni2 >= 0 and ni2 < board.size() and _is_military(board, ni2):
						result.append(ni2)
		"far_event_military":
			# 군대 카드 중 event_target과 그 인접을 제외한 나머지.
			var et3: int = event.get("target_idx", -1)
			var excluded2: Dictionary = {}
			if et3 >= 0:
				excluded2[et3] = true
				excluded2[et3 - 1] = true
				excluded2[et3 + 1] = true
			for mi in _military_indices(board):
				if not excluded2.has(mi):
					result.append(mi)
		_:
			# Unknown target — warning to console. Phase 2+ 에서 추가 target 등록.
			push_warning("[military r_conditional] unknown target: %s" % target_name)
	return result


func _is_military(board: Array, idx: int) -> bool:
	return (board[idx] as CardInstance).template.get("theme", -1) == Enums.CardTheme.MILITARY


## r_conditional 블록을 순회하며 조건(rank_gte) 만족 시 내부 effects 실행.
## 매 실행 시 조건 체크 (conditional과 동일 패턴). one-shot 아님.
##
## 순회 순서: rank_gte 내림차순 (R10 → R4 → R0). ml_academy처럼 같은 tenure 키를
## 공유하는 max_per_round 효과가 있을 때, R10 도달 시 상위 milestone이 먼저
## 실행되어 tenure를 소진하면 하위 milestone이 자연스럽게 skip된다 (대체 의도).
## 누적형(ml_supply, ml_factory 등) r_conditional은 tenure 키 없이 독립적이라
## 순서와 무관하게 모두 실행됨.
func _process_r_conditional(card: CardInstance, idx: int, board: Array,
		event: Dictionary = {}, rng: RandomNumberGenerator = null) -> Array:
	var events: Array = []
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var rank := _rank(card)
	# rank_gte 내림차순으로 정렬된 r_conditional 블록만 추출
	var rc_blocks: Array = []
	for eff in effs:
		if eff.get("action", "") != "r_conditional":
			continue
		if eff.get("condition", "") != "rank_gte":
			continue
		rc_blocks.append(eff)
	rc_blocks.sort_custom(func(a, b):
		return int(a.get("threshold", 0)) > int(b.get("threshold", 0)))
	for eff in rc_blocks:
		var threshold: int = eff.get("threshold", 0)
		if rank < threshold:
			continue
		var inner_effects: Array = eff.get("effects", [])
		for inner in inner_effects:
			events.append_array(_dispatch_r_effect(inner, card, idx, board, event, rng))
	return events


## 개별 r_conditional 내부 effect를 dispatch.
## Phase별로 지원 action을 확장. train/conscript/enhance_convert_card 연결.
## 나머지 action은 Phase 2+에서 추가.
func _dispatch_r_effect(eff: Dictionary, card: CardInstance, idx: int,
		board: Array, event: Dictionary, rng: RandomNumberGenerator) -> Array:
	var events: Array = []
	var action: String = eff.get("action", "")
	var target_name: String = eff.get("target", "")
	var targets := _resolve_targets(target_name, idx, board, event) if target_name != "" else ([] as Array[int])
	match action:
		"train":
			var amount: int = eff.get("amount", 1)
			for ti in targets:
				events.append_array(_train_card(board[ti] as CardInstance, ti, amount))
		"conscript":
			var count: int = eff.get("count", 1)
			var enh_count: int = int(eff.get("enhanced_count", 0))
			for ti in targets:
				if rng != null:
					# r_conditional 내부 conscript: source_card (호출자) 의 rank
					# 는 무시하고 enhanced_tries 파라미터로 앞 N 회 뽑기만 강화
					# 변환 강제. R10 엘리트 보너스 미적용 (source_card=null).
					_conscript(board[ti] as CardInstance, count, rng,
							null, enh_count)
				events.append(_conscript_evt(idx, ti))
		"swarm_buff":
			# BS 타이밍에 발동. 전군 유닛 수 × ATK%.
			# (ml_assault 재설계 후 미사용 — 다른 카드 재활용 예비)
			_apply_swarm_buff(eff, board)
		"shield":
			# 돌격편대 R4 (2026-04-21): 이 카드 유닛 방어막 ★별 %.
			# target: self → 해당 카드의 shield_hp_pct 에 누적.
			var hp_pct: float = eff.get("hp_pct", 0.0)
			var sh_targets := _resolve_targets(eff.get("target", "self"), idx, board, event)
			for ti in sh_targets:
				(board[ti] as CardInstance).shield_hp_pct += hp_pct
		"lifesteal":
			# 돌격편대 R10 (2026-04-21): target: self → 이 카드 lifesteal_pct.
			# 기존 target: all_military 도 호환 유지.
			_apply_lifesteal(eff, board, card)
		"crit_buff":
			# 특수작전대 ★/R: 이 카드 유닛에 치명타 mechanic.
			# theme_state에 저장 → _materialize_army가 읽어 unit mechanics 주입.
			# 매 실행 시 덮어쓰기: R10 > R4 > base 순서로 호출되면 최종값은 가장 큰 값.
			_apply_crit_buff(eff, card)
		"crit_splash":
			# 특수작전대 R4/R10: 치명타 발동 시 인접 적 스플래시.
			_apply_crit_splash(eff, card)
		"revive_scope_override":
			# 통합사령부 R4/R10: revive scope 확장은 game_manager._materialize_army가
			# 통합사령부 카드의 rank를 직접 읽어 scope를 결정하므로 dispatch는 no-op.
			# action은 YAML 선언(설계 의도 문서화) 목적.
			pass
		"upgrade_shop_bonus":
			# 군수공장 R4/R10: 상점 슬롯/할인은 Talisman.get_upgrade_shop_slots와
			# upgrade_shop.get_upgrade_cost가 get_factory_shop_bonus를 직접 호출해
			# rank 기반으로 평가하므로 dispatch는 no-op.
			pass
		"rank_buff_hp":
			# 전술사령부 R4: 모든 군대 카드에 계급당 HP +% buff (BS 타이밍).
			_apply_rank_buff_hp(eff, card, board)
		"enhance_convert_target":
			# 군사학교 R4: 훈련 대상의 비(강화) 유닛 N기를 (강화)로 변환.
			# max_per_round 제한. theme_state["academy_convert_tenure"]로 관리.
			var max_per_round: int = eff.get("max_per_round", 1)
			if max_per_round > 0 and not _check_per_round(card, "academy_convert_tenure"):
				pass  # 이번 라운드 이미 발동
			else:
				var et: int = event.get("target_idx", -1)
				var count_c: int = eff.get("count", 1)
				if et >= 0 and et < board.size():
					_enhance_convert_count(board[et] as CardInstance, count_c)
		"spawn_enhanced_random":
			# 군사학교 R10: 훈련 대상에 랜덤 (강화) 유닛 N기 추가.
			# academy_convert_tenure를 R4와 공유 (slot 공유 → R10이 R4 대체).
			# _process_r_conditional이 rank_gte 내림차순으로 순회하므로 rank=10일 때
			# 이 블록이 먼저 실행되어 tenure 소진 → R4 convert 자동 skip.
			var max_per_round2: int = eff.get("max_per_round", 1)
			if max_per_round2 > 0 and not _check_per_round(card, "academy_convert_tenure"):
				pass  # 이번 라운드 이미 발동
			else:
				var target_name2: String = eff.get("target", "event_target")
				var targets2 := _resolve_targets(target_name2, idx, board, event)
				var spawn_count: int = eff.get("count", 2)
				for ti in targets2:
					_spawn_enhanced_random(board[ti] as CardInstance, spawn_count, rng)
		"buff":
			# 전술사령부 R10: as_bonus / 기타 단일 buff.
			# target=all_military인 경우 theme_state에 저장 → _materialize_army 반영.
			_apply_buff(eff, board)
		_:
			# Phase 2+ 에서 추가 action 등록. 지금은 no-op.
			pass
	return events


## swarm_buff 적용 (BS 타이밍). 필드 전체 군대 유닛 합계 × atk_per_unit% buff.
## 기존 _assault_battle 로직에서 이식.
func _apply_swarm_buff(eff: Dictionary, board: Array) -> void:
	var atk_per_unit: float = eff.get("atk_per_unit", 0.005)
	var ms_bonus_def: Dictionary = eff.get("ms_bonus", {})
	var ms_thresh: int = ms_bonus_def.get("unit_thresh", 15)
	var ms_bonus_val: int = ms_bonus_def.get("bonus", 1)
	# enhanced_count (2026-04-17 iter3 bug fix): YAML 선언(기본 1, ★1~3
	# R4는 2)을 실제 유닛 집계에 반영. (강화) 유닛 1기를 N기로 환산해
	# atk_per_unit 버프와 ms_thresh 판정 양쪽에 동시 적용.
	var enhanced_weight: int = max(1, int(eff.get("enhanced_count", 1)))

	var total_units := 0
	for mi in _military_indices(board):
		var mc: CardInstance = board[mi]
		for s in mc.stacks:
			var ut_tags: PackedStringArray = s["unit_type"].get(
				"tags", PackedStringArray())
			var w: int = enhanced_weight if "enhanced" in ut_tags else 1
			total_units += int(s["count"]) * w

	var atk_pct := float(total_units) * atk_per_unit
	for mi in _military_indices(board):
		var mc2: CardInstance = board[mi]
		mc2.temp_buff(null, atk_pct)
		# ms_bonus는 임계 도달 시에만 세팅, 미달 시 해제 (이전 전투 잔류 방지).
		if total_units >= ms_thresh:
			mc2.theme_state["ms_bonus"] = ms_bonus_val
		else:
			mc2.theme_state.erase("ms_bonus")


## lifesteal 적용 (BS 타이밍). target 카드들의 theme_state["lifesteal_pct"] 에
## pct 세팅. combat_engine 이 전투 시작 시 이를 읽어 유닛에 lifesteal mechanic 주입.
## 2026-04-21: target 파라미터 지원 — "all_military" (기존) / "self" (신규, ml_assault R10).
func _apply_lifesteal(eff: Dictionary, board: Array, source: CardInstance) -> void:
	var pct: float = eff.get("pct", 0.10)
	if pct <= 0:
		return
	var tgt_name: String = eff.get("target", "all_military")
	if tgt_name == "self":
		source.theme_state["lifesteal_pct"] = pct
		return
	# 기본: 전군 적용 (하위 호환)
	for mi in _military_indices(board):
		var mc: CardInstance = board[mi]
		mc.theme_state["lifesteal_pct"] = pct


## crit_buff 적용 (특수작전대 ★/R). 카드의 theme_state에 치명타 수치 저장.
## _materialize_army가 읽어 unit mechanics에 "critical" mechanic 주입.
## target이 "self"이면 이 카드만, "both_adj"이면 양쪽 인접 군대 카드까지.
func _apply_crit_buff(eff: Dictionary, card: CardInstance) -> void:
	var chance: float = eff.get("chance", 0.0)
	var mult: float = eff.get("mult", 2.0)
	if chance <= 0:
		return
	# target이 self면 이 카드만 (현재 YAML은 target=self로만 사용). 확장 시 board/idx 필요.
	# "큰 값 유지" — R10/R4/base 중 chance 큰 쪽이 최종. _process_r_conditional이
	# rank_gte 내림차순으로 순회하게 바뀐 이후 "마지막 값이 승" 전제가 깨져서
	# max() 기반으로 전환 (academy bug fix와 동일 이터레이션).
	var prev_chance: float = card.theme_state.get("crit_chance", 0.0)
	if chance > prev_chance:
		card.theme_state["crit_chance"] = chance
		card.theme_state["crit_mult"] = mult


## crit_splash 적용 (특수작전대 R4/R10). theme_state에 splash_pct 저장.
## _materialize_army가 읽어 crit mechanic과 함께 unit mechanics에 주입.
func _apply_crit_splash(eff: Dictionary, card: CardInstance) -> void:
	var splash_pct: float = eff.get("splash_pct", 0.0)
	if splash_pct <= 0:
		return
	# "큰 값 유지" (_apply_crit_buff와 동일 이유 — 순회 순서 무관화).
	var prev: float = card.theme_state.get("crit_splash_pct", 0.0)
	if splash_pct > prev:
		card.theme_state["crit_splash_pct"] = splash_pct


## rank_buff_hp 적용 (전술사령부 R4). 발동 카드의 계급 × hp_per_rank를
## 모든 군대 카드에 HP 곱연산 buff (임시, 전투 후 소멸).
## temp_mult_buff(1.0, 1.0 + hp_pct) 재사용.
func _apply_rank_buff_hp(eff: Dictionary, src_card: CardInstance, board: Array) -> void:
	var hp_per_rank: float = eff.get("hp_per_rank", 0.0)
	if hp_per_rank <= 0:
		return
	var rank := _rank(src_card)
	if rank <= 0:
		return
	var hp_pct := float(rank) * hp_per_rank
	for mi in _military_indices(board):
		(board[mi] as CardInstance).temp_mult_buff(1.0, 1.0 + hp_pct)


## 라운드당 1회 제한 체크. card.tenure를 사용해 "이번 라운드 발동 여부" 판정.
## 처음 호출이거나 tenure 달라졌으면 true 반환하고 기록 업데이트.
## 동일 tenure면 false (이번 라운드 이미 발동).
## card.reset_round()가 tenure += 1하므로 자연히 다음 라운드에 리셋.
func _check_per_round(card: CardInstance, key: String) -> bool:
	var last_tenure: int = card.theme_state.get(key, -1)
	if last_tenure == card.tenure:
		return false
	card.theme_state[key] = card.tenure
	return true


## count 기반 (강화) 변환. _enhance_convert_card와 유사하지만 비율 대신 고정 개수.
## 가장 약한(CP) 비(강화) 유닛부터 N기 변환.
func _enhance_convert_count(card: CardInstance, count: int) -> int:
	if count <= 0:
		return 0
	var candidates: Array = []
	for i in card.stacks.size():
		var s: Dictionary = card.stacks[i]
		var uid: String = s["unit_type"].get("id", "")
		if not ENHANCED_MAP.has(uid):
			continue
		var ut: Dictionary = s["unit_type"]
		var as_val: float = maxf(ut["attack_speed"], 0.01)
		var cp: float = float(ut["atk"]) / as_val * float(ut["hp"])
		candidates.append({"stack_idx": i, "uid": uid, "count": s["count"], "cp": cp})

	if candidates.is_empty():
		return 0

	candidates.sort_custom(func(a, b): return a["cp"] < b["cp"])
	var to_convert := count
	var converted := 0
	for c in candidates:
		if to_convert <= 0:
			break
		var s: Dictionary = card.stacks[c["stack_idx"]]
		var take: int = mini(s["count"], to_convert)
		if take <= 0:
			continue
		s["count"] -= take
		to_convert -= take
		converted += take
		card.add_specific_unit(ENHANCED_MAP[c["uid"]], take)

	card.stacks = card.stacks.filter(func(s): return s["count"] > 0)
	if converted > 0:
		card.stats_changed.emit()
	return converted


## 랜덤 (강화) 유닛 N기 추가. ENHANCED_MAP의 value에서 무작위 선택.
## 군사학교 R10 등에서 사용.
func _spawn_enhanced_random(card: CardInstance, count: int, rng: RandomNumberGenerator) -> int:
	if count <= 0:
		return 0
	var enhanced_ids: Array = ENHANCED_MAP.values()
	if enhanced_ids.is_empty():
		return 0
	var added := 0
	for _i in count:
		var uid: String = enhanced_ids[rng.randi() % enhanced_ids.size()] if rng != null else enhanced_ids[0]
		added += card.add_specific_unit(uid, 1)
	return added


## buff 적용 (전술사령부 R10 as_bonus, 추후 확장 가능).
## target이 all_military면 모든 군대 카드 theme_state에 buff 값 저장.
## _materialize_army가 attack_speed 계산 시 theme_state["as_bonus"] 반영.
func _apply_buff(eff: Dictionary, board: Array) -> void:
	var target_name: String = eff.get("target", "")
	var as_bonus: float = eff.get("as_bonus", 0.0)
	var atk_pct: float = eff.get("atk_pct", 0.0)
	var targets: Array[int] = []
	if target_name == "all_military":
		targets = _military_indices(board)
	# 다른 target은 Phase 확장에서.
	for ti in targets:
		var tc: CardInstance = board[ti]
		if as_bonus > 0:
			tc.theme_state["as_bonus"] = as_bonus
		if atk_pct > 0:
			tc.temp_buff(null, atk_pct)


## r_conditional 블록에서 grant_gold/grant_terazin 합계를 모아서 반환.
## _process_r_conditional은 events만 반환하므로 자원 지급은 이 경로로 분리.
## 보급부대 _supply_post에서 호출.
func _collect_r_grants(card: CardInstance) -> Dictionary:
	var rank := _rank(card)
	var gold := 0
	var terazin := 0
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	for eff in effs:
		if eff.get("action", "") != "r_conditional":
			continue
		var cond: String = eff.get("condition", "")
		var thresh: int = eff.get("threshold", 0)
		if cond != "rank_gte" or rank < thresh:
			continue
		for inner in eff.get("effects", []):
			match inner.get("action", ""):
				"grant_gold":
					gold += int(inner.get("amount", 0))
				"grant_terazin":
					terazin += int(inner.get("amount", 0))
	return {"gold": gold, "terazin": terazin}


# _enhance_convert_card 함수 제거 (2026-04-21).
# "카드 내 기존 비(강화) 유닛을 강화로 소급 변환" 기능 폐기.
# 신규 징집 유닛의 강화는 conscript rank_upgrade 플래그 + _conscript 내부
# ENHANCED_MAP 변환으로 일원화됨 (해석 B).


# --- RS cards ---


func _barracks(card: CardInstance, idx: int, board: Array) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var self_train_eff := _find_eff(effs, "train", "self")
	var self_train: int = self_train_eff.get("amount", 1)

	var events: Array = []
	events.append_array(_train_card(card, idx, self_train))

	# 기본 훈련: YAML의 right_adj (R0 기본값). R4에서 left_adj가 r_conditional로 추가됨.
	var right_train_eff := _find_eff(effs, "train", "right_adj")
	if not right_train_eff.is_empty():
		var r := idx + 1
		if r < board.size() and _is_military(board, r):
			events.append_array(_train_card(board[r], r, right_train_eff.get("amount", 1)))

	# ★3 high_rank_mult: 계급 N 도달 시 이 카드 유닛 ATK × atk_mult (one-shot).
	# 기본 effects에 있음 (r_conditional 아님). theme_state 플래그로 중복 방지.
	var hr_eff := _find_eff(effs, "high_rank_mult")
	if not hr_eff.is_empty():
		var hr_rank: int = hr_eff.get("rank", 15)
		var mult: float = hr_eff.get("atk_mult", 1.3)
		if _rank(card) >= hr_rank and not card.theme_state.get("high_rank_applied", false):
			card.enhance(null, mult - 1.0, 0.0)  # mult 1.3 → +30% growth
			card.theme_state["high_rank_applied"] = true

	# R4/R10 milestone 효과 (left_adj, far_military, enhance_convert_card 등)
	events.append_array(_process_r_conditional(card, idx, board))

	return {"events": events, "gold": 0, "terazin": 0}


func _outpost(card: CardInstance, idx: int, board: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var self_eff := _find_eff(effs, "conscript", "self")
	var count: int = self_eff.get("count", 2)

	var events: Array = []
	# Self-conscription: 자동 랜덤 (2026-04-21 UI 제거, 해석 B).
	# source_card=card → ml_conscript 자신의 rank 가 R4/R10 변환/엘리트 보너스 적용.
	_conscript(card, count, rng, card)
	events.append(_conscript_evt(idx, idx))

	# ★2+: adjacent army cards 징집 (ml_conscript rank 기준 R4/R10 확장 공유)
	var adj_eff := _find_eff(effs, "conscript", "right_adj")
	var both_adj_eff := _find_eff(effs, "conscript", "both_adj")
	var has_adj := not adj_eff.is_empty() or not both_adj_eff.is_empty()
	if has_adj:
		var both := not both_adj_eff.is_empty()
		var adj_list: Array[int] = []
		if both:
			if idx > 0: adj_list.append(idx - 1)
			if idx + 1 < board.size(): adj_list.append(idx + 1)
		else:
			if idx + 1 < board.size(): adj_list.append(idx + 1)

		for ni in adj_list:
			var adj: CardInstance = board[ni]
			if adj.template.get("theme", -1) == Enums.CardTheme.MILITARY:
				_conscript(adj, 1, rng, card)  # source_card=card: R4/R10 확장 적용
				events.append(_conscript_evt(idx, ni))

	# R4/R10 milestone (enhance_convert_card 등; conscript_pool_tier 는 제거됨 2026-04-21)
	events.append_array(_process_r_conditional(card, idx, board, {}, rng))

	return {"events": events, "gold": 0, "terazin": 0}


func _assault_rs(card: CardInstance, idx: int, board: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	# 돌격편대 재설계 (2026-04-21):
	#   conscript forced_unit: ml_biker — pool 랜덤 대신 고정 바이커 징집.
	#   rank_upgrade: true → R4 50% / R10 100% 확률로 강화 바이커 전환.
	#   biker_rebirth 제거 (고정 유닛이라 재도전 무의미).
	#   R4: shield target self — 이 카드 유닛 방어막 ★별 20/40/90%.
	#   R10: lifesteal target self — 이 카드 라이프스틸 ★별 10/20/30%.
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var events: Array = []
	var con_eff := _find_eff(effs, "conscript", "self")
	if not con_eff.is_empty():
		var tries: int = int(con_eff.get("count", 1))
		var forced: String = con_eff.get("forced_unit", "")
		if tries > 0:
			_conscript(card, tries, rng, card, 0, false, forced)
			events.append(_conscript_evt(idx, idx))

	# R4/R10 milestone: shield (self) / lifesteal (self) 은 _dispatch_r_effect 에서 처리.
	events.append_array(_process_r_conditional(card, idx, board))

	return {"events": events, "gold": 0, "terazin": 0}


func _special_ops(card: CardInstance, idx: int, board: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	# 특수작전대 재설계:
	#   trace 012: 훈련 전파 제거, 치명타 중심 전환.
	#   2026-04-21: ★2/★3 spawn_unit(sniper fixed) → conscript (base pool 뽑기 +
	#               CO 이벤트 방출, ml_outpost 체인 활성화). biker_rebirth 없음
	#               (특작은 정예 컨셉, base pool 랜덤이어도 R4/R10 로 질적 보상).
	# R4/R10: crit_buff 확률 교체 + crit_splash 해금. 매 RS 실행 시 덮어쓰기.
	# 이전 전투의 theme_state 잔류 방지를 위해 매번 초기화 후 재적용.
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var events: Array = []

	# theme_state 초기화 (이전 ★/R 수치 재적용 보장)
	card.theme_state.erase("crit_chance")
	card.theme_state.erase("crit_mult")
	card.theme_state.erase("crit_splash_pct")

	# ★ 기본 crit_buff (R0 수치)
	var crit_eff := _find_eff(effs, "crit_buff", "self")
	if not crit_eff.is_empty():
		_apply_crit_buff(crit_eff, card)

	# conscript (★2: 1 회, ★3: 3 회 뽑기)
	var con_eff := _find_eff(effs, "conscript", "self")
	if not con_eff.is_empty():
		var tries: int = int(con_eff.get("count", 1))
		if tries > 0:
			_conscript(card, tries, rng, card)
			events.append(_conscript_evt(idx, idx))

	# R4/R10 milestone (enhance_convert_card + crit_buff chance 덮어쓰기 + crit_splash)
	events.append_array(_process_r_conditional(card, idx, board))

	return {"events": events, "gold": 0, "terazin": 0}


func _command(card: CardInstance, idx: int, board: Array) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var train_eff := _find_eff(effs, "train", "all_military")
	var amount: int = train_eff.get("amount", 1)

	var events: Array = []
	for mi in _military_indices(board):
		events.append_array(_train_card(board[mi], mi, amount))

	# R4/R10 milestone (enhance_convert_card; revive_scope_override는 Phase 4)
	events.append_array(_process_r_conditional(card, idx, board))

	return {"events": events, "gold": 0, "terazin": 0}


# --- OE cards ---


func _academy(card: CardInstance, idx: int, board: Array,
		event: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var target_idx: int = event.get("target_idx", -1)
	if target_idx < 0 or target_idx >= board.size():
		return Enums.empty_result()

	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var train_eff := _find_eff(effs, "train", "event_target")
	var enhance_eff := _find_eff(effs, "enhance", "event_target")
	var bonus_train: int = train_eff.get("amount", 1)
	var growth: float = enhance_eff.get("atk_pct", 0.0)

	var target: CardInstance = board[target_idx]
	var events: Array = []
	events.append_array(_train_card(target, target_idx, bonus_train))
	if growth > 0:
		target.enhance(null, growth, 0.0)

	# R4/R10 milestone (enhance_convert_card + enhance_convert_target + spawn_enhanced_random)
	events.append_array(_process_r_conditional(card, idx, board, event, rng))

	return {"events": events, "gold": 0, "terazin": 0}


## ml_outpost OE 반응 (2026-04-21 재설계):
##   r_conditional (R4/R10 확장 + enhanced_count 강제 변환) 제거.
##   ★1: event_target 에 징집 1 회 (강화 없음)
##   ★2: self 에 징집 1 회 (rank_upgrade) + event_target 에 징집 1 회
##   ★3: self 에 징집 2 회 + 훈련 1 회, event_target 에 징집 2 회 + 훈련 1 회
##   (require_other: true 로 자기 CO 체인 차단, C6)
func _conscript_react(card: CardInstance, idx: int, board: Array,
		event: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var target_idx: int = event.get("target_idx", -1)
	if target_idx < 0 or target_idx >= board.size():
		return Enums.empty_result()
	var target: CardInstance = board[target_idx]
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var events: Array = []

	# 모든 conscript action 순회 (self + event_target 두 target 가능).
	for eff in effs:
		if eff.get("action", "") != "conscript":
			continue
		var t_name: String = eff.get("target", "")
		var tries: int = int(eff.get("count", 1))
		var rank_up: bool = bool(eff.get("rank_upgrade", false))
		var enh_n: int = int(eff.get("enhanced_count", 0))
		var src = card if rank_up else null
		if t_name == "self":
			_conscript(card, tries, rng, src, enh_n)
			events.append(_conscript_evt(idx, idx))
		elif t_name == "event_target":
			_conscript(target, tries, rng, src, enh_n)
			events.append(_conscript_evt(idx, target_idx))

	# 모든 train action 순회 (★3 self + event_target 훈련).
	for eff in effs:
		if eff.get("action", "") != "train":
			continue
		var t_name: String = eff.get("target", "")
		var amount: int = int(eff.get("amount", 1))
		if t_name == "self":
			events.append_array(_train_card(card, idx, amount))
		elif t_name == "event_target":
			events.append_array(_train_card(target, target_idx, amount))

	return {"events": events, "gold": 0, "terazin": 0}


## ml_factory OE 블록 (2026-04-21 재설계): TR 이벤트 발생 시 target 군대 카드를
## `theme_state["trained_this_round"]` 집합에 기록. 이 집합은 PC 블록에서
## 소비 후 초기화된다. listen l2=TR 변경 배경: CO 소스가 2장뿐이라 활용도가
## 낮았음. rank 기반 보상은 훈련(계급 축적)과 의미상 직결되므로 TR 수집이 정합.
func _factory_collect_tr(card: CardInstance, event: Dictionary) -> Dictionary:
	var target_idx: int = event.get("target_idx", -1)
	if target_idx < 0:
		return Enums.empty_result()
	# Dictionary-as-set (GDScript 관용): key=target_idx, value=true.
	var coll: Dictionary = card.theme_state.get("trained_this_round", {})
	coll[target_idx] = true
	card.theme_state["trained_this_round"] = coll
	return Enums.empty_result()


## ml_factory PC 블록: 수집된 카드에 **ml_factory 자신의 계급** × atk_pct_per_rank 만큼
## ATK 영구 강화. ml_factory 자신 rank 4+ 이면 동일 비율로 HP 도 강화.
## rank 10+ 이면 동일 비율로 AS 도 강화 (공격 속도 = upgrade_as_mult 값 감소).
## 2026-04-23: 이전에는 target_rank 기반이라 multi-trainer 환경에서 compound 폭증.
## factory 자신 rank로 변경 → self-train 속도로만 성장 → 선형 상한.
## 적용 후: 집합 초기화 + 자신 rank +1 (self-train, 이벤트 재방출 없음 —
## 자기 참조 무한 체인 차단).
func _factory_pc(card: CardInstance, board: Array) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var eff := _find_eff(effs, "rank_scaled_enhance")
	if eff.is_empty():
		return Enums.empty_result()
	var atk_per_rank: float = eff.get("atk_pct_per_rank", 0.0)
	var r4_hp_per_rank: float = eff.get("r4_hp_pct_per_rank", 0.0)
	var r10_as_per_rank: float = eff.get("r10_as_pct_per_rank", 0.0)
	var self_rank: int = _rank(card)
	var apply_hp: bool = self_rank >= 4 and r4_hp_per_rank > 0.0
	var apply_as: bool = self_rank >= 10 and r10_as_per_rank > 0.0

	# 스케일 기준: factory 자신의 rank (target rank 아님).
	var atk_pct: float = float(self_rank) * atk_per_rank
	var hp_pct: float = float(self_rank) * r4_hp_per_rank if apply_hp else 0.0
	var as_divisor: float = 1.0 + float(self_rank) * r10_as_per_rank if apply_as else 1.0

	var coll: Dictionary = card.theme_state.get("trained_this_round", {})
	for key in coll.keys():
		var tgt_idx: int = int(key)
		if tgt_idx < 0 or tgt_idx >= board.size():
			continue
		var target: CardInstance = board[tgt_idx] as CardInstance
		if target == null:
			continue
		# Safety: TR 이벤트 대상은 군대 카드여야 함.
		if target.template.get("theme", -1) != Enums.CardTheme.MILITARY:
			continue
		if self_rank <= 0:
			continue  # factory 자신 rank 0이면 적용치 0
		if atk_pct > 0.0 or hp_pct > 0.0:
			target.enhance(null, atk_pct, hp_pct)
		if apply_as and as_divisor > 0.0:
			target.upgrade_as_mult /= as_divisor
			target.stats_changed.emit()
	# 라운드 단위로 초기화 — 다음 라운드의 수집이 누수 없이 시작.
	card.theme_state["trained_this_round"] = {}
	# Self-train: 전투 종료마다 자신 rank +1 (이벤트 방출 없음).
	# 매 라운드 확정 +1 → R4 4R, R10 10R. 다른 카드의 훈련 대상이 되면 더 빠름.
	_add_rank(card, 1)
	return Enums.empty_result()


# --- Battle hooks ---


func _tactical_battle(card: CardInstance, idx: int, board: Array) -> Dictionary:
	# 이전 전투의 as_bonus 잔류 방지 (R10 해제는 불가하지만 안전 차원).
	for mi in _military_indices(board):
		(board[mi] as CardInstance).theme_state.erase("as_bonus")

	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var buff_eff := _find_eff(effs, "rank_buff", "all_military")
	var shield_per_rank: float = buff_eff.get("shield_per_rank", 0.02)
	var atk_per_unit: float = buff_eff.get("atk_per_unit", 0.005)
	# enhanced_shield_bonus (2026-04-17 iter3 bug fix): YAML 선언이 기존에
	# 런타임 미연결. (강화) 유닛이 1기 이상 배치된 군대 카드에 한해 추가
	# 방어막 %를 가산한다 (카드 레벨 shield_hp_pct, binary 적용).
	var enhanced_shield_bonus: float = buff_eff.get("enhanced_shield_bonus", 0.0)

	var rank := _rank(card)
	var total_units := 0
	for mi in _military_indices(board):
		total_units += (board[mi] as CardInstance).get_total_units()

	var shield_pct := rank * shield_per_rank
	var atk_pct := float(total_units) * atk_per_unit

	for mi in _military_indices(board):
		var mc: CardInstance = board[mi]
		mc.shield_hp_pct += shield_pct
		if enhanced_shield_bonus > 0.0:
			var has_enhanced := false
			for s in mc.stacks:
				var ut_tags: PackedStringArray = s["unit_type"].get(
					"tags", PackedStringArray())
				if "enhanced" in ut_tags:
					has_enhanced = true
					break
			if has_enhanced:
				mc.shield_hp_pct += enhanced_shield_bonus
		mc.temp_buff(null, atk_pct)

	# R4/R10 milestone (enhance_convert_card + rank_buff_hp + buff as_bonus)
	_process_r_conditional(card, idx, board)
	return Enums.empty_result()


func _assault_battle(card: CardInstance, idx: int, board: Array) -> Dictionary:
	# 돌격편대 재설계(trace 012): swarm_buff/lifesteal은 R4/R10 조건부 해금.
	# r_conditional 내부에 있으므로 BS 시점에 _process_r_conditional 호출로 처리.
	# (swarm_buff/lifesteal action은 _dispatch_r_effect 내부에서 BS 효과 적용)
	_process_r_conditional(card, idx, board)
	return Enums.empty_result()


func _supply_post(card: CardInstance, idx: int, board: Array, won: bool) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var econ_eff := _find_eff(effs, "economy")
	var base_gold: int = econ_eff.get("gold_base", 1)
	var per_card: float = econ_eff.get("gold_per", 0.5)
	var halve_on_loss: bool = econ_eff.get("halve_on_loss", false)
	var terazin_def: Dictionary = econ_eff.get("terazin", {})

	var army_n := _army_card_count(board)
	var gold := base_gold + int(army_n * per_card)
	if not won and halve_on_loss:
		gold /= 2

	var terazin := 0
	if not terazin_def.is_empty():
		var cond: String = terazin_def.get("condition", "")
		var thresh: int = terazin_def.get("thresh", 0)
		if cond == "rank_gte" and _rank(card) >= thresh:
			terazin = terazin_def.get("amount", 1)

	# R4/R10 grants (grant_gold/grant_terazin)
	# NOTE: YAML 의도상 R10 효과는 R4를 "대체"해야 함. YAML 누적 구조를
	# 보존하기 위해 R10이 최종 총량(R4+R10 합계)이 되도록 맞췄다면 그대로 합산.
	var r_grants := _collect_r_grants(card)
	gold += int(r_grants.get("gold", 0))
	terazin += int(r_grants.get("terazin", 0))

	# R4/R10 기타 효과 (enhance_convert_card)
	_process_r_conditional(card, idx, board)

	return {"events": [], "gold": gold, "terazin": terazin}


# Deferred conscription helpers 제거됨 (2026-04-21):
#   clear_pending / pick_conscript_options / apply_conscript —
#   3택1 UI 폐기. 모든 conscript 는 _conscript() 자동 처리.


# --- ml_alliance (T3) ---
#
# 동맹군: 보드 테마 다양성에 비례해 징집 가속 + BS spawn.
# RS: conscript_counter += theme_count × mult
# BS: theme_count × mult 유닛 spawn 랜덤 아군에 (★2/★3)
# ★3 BS: theme_count ≥ instant_conscript_threshold 시 즉시 징집 유닛 1기 등장


## 보드의 고유 테마 수 카운트 (NEUTRAL 포함).
func _count_board_themes(board: Array) -> int:
	var seen: Dictionary = {}
	for c in board:
		if c == null:
			continue
		var t: int = (c as CardInstance).template.get("theme", -1)
		if t >= 0:
			seen[t] = true
	return seen.size()


func _alliance_rs(card: CardInstance, idx: int, board: Array) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var eff := _find_eff(effs, "theme_count_conscript")
	if eff.is_empty():
		return Enums.empty_result()
	var mult: int = eff.get("mult", 1)
	var theme_count := _count_board_themes(board)
	var add: int = theme_count * mult
	if add <= 0:
		return Enums.empty_result()
	# 직접 ml_recruit 1기 spawn (theme_count × mult 만큼) — conscript_counter 추상화
	# 제거 (소비자 없는 dead write 회피, multi-review C-A 지적).
	var events: Array = []
	for _i in add:
		if card.get_total_units() >= card.get_unit_cap():
			break
		card.add_specific_unit("ml_recruit", 1)
		events.append({
			"layer1": Enums.Layer1.UNIT_ADDED,
			"layer2": Enums.Layer2.CONSCRIPT,
			"source_idx": idx, "target_idx": idx,
		})
	return {"events": events, "gold": 0, "terazin": 0}


## ml_alliance BS — ★2/★3에서 theme_count 비례 spawn.
## ★3는 theme_count ≥ instant_conscript_threshold 시 즉시 징집 유닛 1기 등장.
func _alliance_bs(card: CardInstance, idx: int, board: Array) -> Dictionary:
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var eff := _find_eff(effs, "theme_count_spawn")
	if eff.is_empty():
		return Enums.empty_result()

	var theme_count := _count_board_themes(board)
	var mult: int = eff.get("mult", 1)
	var spawn_total: int = theme_count * mult

	# Spawn 대상 결정 (random_ally — 보드의 살아있는 카드 1장 랜덤)
	var ally_indices: Array[int] = []
	for i in board.size():
		if board[i] != null:
			ally_indices.append(i)

	var events: Array = []
	if spawn_total > 0 and ally_indices.size() > 0:
		# Deterministic round-robin (sim 결정성 보장 — apply_battle_start에 rng
		# 시그니처 없음. randomize() 호출 시 sim non-determinism 발생, multi-
		# review C-B 지적). idx + n 모듈로 ally_indices 크기로 순환 분배.
		for n in spawn_total:
			var pick_idx: int = ally_indices[(idx + n) % ally_indices.size()]
			var target: CardInstance = board[pick_idx]
			if target.get_total_units() < target.get_unit_cap():
				# spawn_random 은 RNG 필요 — comp 첫 유닛 직접 추가로 대체
				var comp: Array = target.template.get("composition", [])
				if comp.size() > 0:
					var unit_id: String = comp[0].get("unit_id", "")
					if unit_id != "":
						target.add_specific_unit(unit_id, 1)
						events.append({
							"layer1": Enums.Layer1.UNIT_ADDED,
							"layer2": Enums.Layer2.CONSCRIPT,
							"source_idx": idx, "target_idx": pick_idx,
						})

	# ★3: instant_conscript_threshold 도달 시 self에 징집 유닛 1기 등장
	var thresh: int = eff.get("instant_conscript_threshold", 0)
	if thresh > 0 and theme_count >= thresh and card.get_total_units() < card.get_unit_cap():
		# 단순화: ml_recruit 1기 직접 추가 (정식 conscript pool 추첨은 Phase 4 deferred)
		card.add_specific_unit("ml_recruit", 1)
		events.append({
			"layer1": Enums.Layer1.UNIT_ADDED,
			"layer2": Enums.Layer2.CONSCRIPT,
			"source_idx": idx, "target_idx": idx,
		})

	return {"events": events, "gold": 0, "terazin": 0}
