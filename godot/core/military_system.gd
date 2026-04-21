class_name MilitarySystem
extends "res://core/theme_system.gd"
## Military theme system: rank/training + conscription.
## RS cards (barracks, outpost, special_ops, command) train/conscript;
## OE cards (academy, conscript_react, factory) chain off TRAIN/CONSCRIPT events.

# Conscription unit pool (growth chain uses weighted random)
# 등급별 풀 (징병국 R4/R10 conscript_pool_tier 지원):
# - base: 기본 6종 (신병 다수 / 화력 소수 기수 차등)
# - enhanced: (강화) 6종 추가 (weight는 상응 base의 절반, 후반 접근)
# - elite: enhanced + 엘리트 4종 (저격드론/궤도포대/지휘관/워커) 소수 weight
const CONSCRIPT_POOL: Array = [
	{"id": "ml_recruit", "weight": 3},
	{"id": "ml_drone", "weight": 2},
	{"id": "ml_biker", "weight": 2},
	{"id": "ml_infantry", "weight": 1},
	{"id": "ml_shield", "weight": 1},
	{"id": "ml_plasma", "weight": 1},
]

const CONSCRIPT_POOL_ENHANCED: Array = [
	{"id": "ml_recruit", "weight": 3},
	{"id": "ml_drone", "weight": 2},
	{"id": "ml_biker", "weight": 2},
	{"id": "ml_infantry", "weight": 1},
	{"id": "ml_shield", "weight": 1},
	{"id": "ml_plasma", "weight": 1},
	# (강화) 버전 — weight 절반으로 낮게 (후반 접근)
	{"id": "ml_recruit_enhanced", "weight": 1.5},
	{"id": "ml_drone_enhanced", "weight": 1},
	{"id": "ml_biker_enhanced", "weight": 1},
	{"id": "ml_infantry_enhanced", "weight": 0.5},
	{"id": "ml_shield_enhanced", "weight": 0.5},
	{"id": "ml_plasma_enhanced", "weight": 0.5},
]

const CONSCRIPT_POOL_ELITE: Array = [
	{"id": "ml_recruit", "weight": 3},
	{"id": "ml_drone", "weight": 2},
	{"id": "ml_biker", "weight": 2},
	{"id": "ml_infantry", "weight": 1},
	{"id": "ml_shield", "weight": 1},
	{"id": "ml_plasma", "weight": 1},
	{"id": "ml_recruit_enhanced", "weight": 1.5},
	{"id": "ml_drone_enhanced", "weight": 1},
	{"id": "ml_biker_enhanced", "weight": 1},
	{"id": "ml_infantry_enhanced", "weight": 0.5},
	{"id": "ml_shield_enhanced", "weight": 0.5},
	{"id": "ml_plasma_enhanced", "weight": 0.5},
	# 엘리트 유닛 — 매우 낮은 weight (희소)
	{"id": "ml_sniper", "weight": 0.3},
	{"id": "ml_artillery", "weight": 0.2},
	{"id": "ml_commander", "weight": 0.3},
	{"id": "ml_walker", "weight": 0.2},
]

# Base → Enhanced 유닛 ID 매핑 (6쌍, units-military.md 참조).
# enhance_convert_card handler에서 사용.
const ENHANCED_MAP: Dictionary = {
	"ml_recruit":  "ml_recruit_enhanced",
	"ml_infantry": "ml_infantry_enhanced",
	"ml_shield":   "ml_shield_enhanced",
	"ml_drone":    "ml_drone_enhanced",
	"ml_biker":    "ml_biker_enhanced",
	"ml_plasma":   "ml_plasma_enhanced",
}

## Deferred conscription requests — filled by _outpost(), consumed by game_manager.
## Each entry: {card_ref: CardInstance, card_idx: int, count: int}
var pending_conscriptions: Array = []


# --- Chain integration ---


func process_rs_card(card: CardInstance, idx: int, board: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	# 징병국↔전진기지 스왑 (trace 012):
	#   ml_conscript: T1 RS self 징집 생성 (기존 _outpost 로직)
	#   ml_outpost: T2 OE CO 반응 증폭 (아래 process_event_card)
	match card.get_base_id():
		"ml_barracks": return _barracks(card, idx, board)
		"ml_conscript": return _outpost(card, idx, board, rng)
		"ml_assault": return _assault_rs(card, idx, board)
		"ml_special_ops": return _special_ops(card, idx, board)
		"ml_command": return _command(card, idx, board)
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


func _conscript(target: CardInstance, count: int, rng: RandomNumberGenerator,
		pool: Array = CONSCRIPT_POOL, enhanced_count: int = 0) -> int:
	## 유닛 `count`기를 `target` 카드에 징집한다.
	## `enhanced_count > 0`이면 앞 N기는 ENHANCED 전용 풀에서 pick하고 나머지는
	## 기본 `pool`에서 pick한다. enhanced_count >= count 이면 전원 강화.
	## (P1-1 migration, 2026-04-17: 기존 `enhanced: partial/all` 문자열 필드를
	##  수량 기반 정량 필드로 교체. partial=1, all=count로 마이그레이션됨.)
	var added := 0
	var enhanced_remaining: int = clampi(enhanced_count, 0, count)
	for i in count:
		var active_pool: Array = (
			CONSCRIPT_POOL_ENHANCED if enhanced_remaining > 0 else pool)
		var uid := _weighted_pick(rng, active_pool)
		var n := target.add_specific_unit(uid, 1)
		added += n
		if enhanced_remaining > 0:
			enhanced_remaining -= 1
		# 양성가 보너스: 징집 유닛 각각 확률로 1기 추가 (이벤트 미방출)
		if n > 0 and bonus_spawn_chance > 0.0 and bonus_rng != null:
			if bonus_rng.randf() < bonus_spawn_chance:
				added += target.add_specific_unit(uid, 1)
	return added


func _weighted_pick(rng: RandomNumberGenerator, pool: Array = CONSCRIPT_POOL) -> String:
	var total := 0.0
	for entry in pool:
		total += entry["weight"]
	var r := rng.randf() * total
	var cum := 0.0
	for entry in pool:
		cum += entry["weight"]
		if r <= cum:
			return entry["id"]
	return pool[0]["id"]


## 카드의 rank를 기반으로 적합한 conscript pool 반환.
## YAML의 r_conditional에서 conscript_pool_tier 선언을 직접 평가:
## 가장 높은 활성 milestone의 tier 우선 (R10 > R4 > base).
## 징병국 R4: enhanced, R10: elite.
func _pool_for_card(card: CardInstance) -> Array:
	var rank := _rank(card)
	var tier := "base"
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	for eff in effs:
		if eff.get("action", "") != "r_conditional":
			continue
		if eff.get("condition", "") != "rank_gte":
			continue
		if rank < int(eff.get("threshold", 0)):
			continue
		for inner in eff.get("effects", []):
			if inner.get("action", "") == "conscript_pool_tier":
				tier = str(inner.get("tier", "base"))
	match tier:
		"enhanced": return CONSCRIPT_POOL_ENHANCED
		"elite": return CONSCRIPT_POOL_ELITE
		_: return CONSCRIPT_POOL


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
					# r_conditional 내부 conscript는 이 카드 카드 자체의 rank-gated
					# pool이 아닌 기본 pool + enhanced_count 파라미터로 동작.
					# 전달된 pool은 (호출자 카드 자체의) _pool_for_card 결과일 때만
					# 별도 확장 적용되지만, r_conditional dispatch 시점엔 call-site가
					# event reactor(ml_outpost)이므로 기본 pool 사용이 적절.
					_conscript(board[ti] as CardInstance, count, rng,
							CONSCRIPT_POOL, enh_count)
				events.append(_conscript_evt(idx, ti))
		"enhance_convert_card":
			# 이 카드의 비(강화) 유닛 중 fraction 비율을 (강화)로 변환.
			var fraction: float = eff.get("fraction", 0.5)
			_enhance_convert_card(card, fraction)
		"swarm_buff":
			# BS 타이밍에 발동 (돌격편대 R4). 전군 유닛 수 × ATK%.
			_apply_swarm_buff(eff, board)
		"lifesteal":
			# BS 타이밍 (돌격편대 R10). 전군에 라이프스틸 메커닉.
			_apply_lifesteal(eff, board)
		"crit_buff":
			# 특수작전대 ★/R: 이 카드 유닛에 치명타 mechanic.
			# theme_state에 저장 → _materialize_army가 읽어 unit mechanics 주입.
			# 매 실행 시 덮어쓰기: R10 > R4 > base 순서로 호출되면 최종값은 가장 큰 값.
			_apply_crit_buff(eff, card)
		"crit_splash":
			# 특수작전대 R4/R10: 치명타 발동 시 인접 적 스플래시.
			_apply_crit_splash(eff, card)
		"conscript_pool_tier":
			# 징병국 R4/R10: pool 확장은 _pool_for_card가 YAML을 직접 평가하므로
			# 이 dispatch는 no-op. action은 YAML 선언(설계 의도 문서화) 목적.
			pass
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


## lifesteal 적용 (BS 타이밍). 모든 군대 카드 유닛에 "lifesteal" mechanic 추가.
## pct만큼 가한 피해의 HP 회복. combat_engine mechanics_handler에 이미 구현됨.
func _apply_lifesteal(eff: Dictionary, board: Array) -> void:
	var pct: float = eff.get("pct", 0.10)
	if pct <= 0:
		return
	for mi in _military_indices(board):
		var mc: CardInstance = board[mi]
		# 카드 수준 지속 mechanic. 전투 시작 시 유닛에 적용되도록 theme_state에 저장.
		# combat_engine이 battle_start에 theme_state["lifesteal_pct"]를 읽어 unit mechanics에 주입.
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


## 카드의 비(강화) 유닛 중 fraction 비율(floor)을 (강화)로 변환.
## 가장 약한(CP) 유닛부터 변환. ENHANCED_MAP에 매핑된 유닛만 대상.
## 엘리트 유닛(sniper/artillery/commander/walker)은 매핑 없어 변환 불가.
## Returns: 실제 변환된 유닛 수.
func _enhance_convert_card(card: CardInstance, fraction: float) -> int:
	# 비(강화) 유닛 stack 수집 (ENHANCED_MAP에 매핑된 것만)
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

	# 총 비(강화) 유닛 수
	var total_non_enhanced: int = 0
	for c in candidates:
		total_non_enhanced += c["count"]
	if total_non_enhanced == 0:
		return 0

	# 변환 대상 수 (floor). fraction 1.0이면 전원.
	var to_convert: int = int(floor(float(total_non_enhanced) * fraction))
	if fraction >= 1.0:
		to_convert = total_non_enhanced
	if to_convert <= 0:
		return 0

	# CP 오름차순 정렬 (약한 것부터)
	candidates.sort_custom(func(a, b): return a["cp"] < b["cp"])

	# 변환 실행: 원본 stack에서 제거 + enhanced 유닛 추가
	var converted := 0
	for c in candidates:
		if to_convert <= 0:
			break
		var stack_idx: int = c["stack_idx"]
		var s: Dictionary = card.stacks[stack_idx]
		var take: int = mini(s["count"], to_convert)
		if take <= 0:
			continue
		s["count"] -= take
		to_convert -= take
		converted += take
		var enhanced_id: String = ENHANCED_MAP[c["uid"]]
		card.add_specific_unit(enhanced_id, take)

	# 빈 stack 제거
	card.stacks = card.stacks.filter(func(s): return s["count"] > 0)
	if converted > 0:
		card.stats_changed.emit()
	return converted


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
	# Self-conscription deferred for player choice (3-pick-1 UI)
	pending_conscriptions.append({"card_ref": card, "card_idx": idx, "count": count})
	events.append(_conscript_evt(idx, idx))

	# ★2+: adjacent army cards get random units (stays random)
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

		# 징병국 R4/R10 pool 확장: 양쪽 인접 징집도 같은 pool 사용.
		var pool := _pool_for_card(card)
		for ni in adj_list:
			var adj: CardInstance = board[ni]
			if adj.template.get("theme", -1) == Enums.CardTheme.MILITARY:
				_conscript(adj, 1, rng, pool)
				events.append(_conscript_evt(idx, ni))

	# R4/R10 milestone (enhance_convert_card 등; conscript_pool_tier는 _pool_for_card 경로로 처리됨)
	events.append_array(_process_r_conditional(card, idx, board, {}, rng))

	return {"events": events, "gold": 0, "terazin": 0}


func _assault_rs(card: CardInstance, idx: int, board: Array) -> Dictionary:
	# 돌격편대 재설계(trace 012): timing BS → RS, 구조 B.
	# ★ 기본 효과: 매 RS 바이커 N기 생산 (spawn_unit).
	# R4에서 swarm_buff 해금, R10에서 lifesteal 해금 (BS 타이밍, Phase 2 I에서 연결).
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var events: Array = []
	var spawn_eff := _find_eff(effs, "spawn_unit", "self")
	if not spawn_eff.is_empty():
		var uid: String = spawn_eff.get("unit", "")
		var count: int = spawn_eff.get("count", 1)
		if uid != "" and count > 0:
			card.add_specific_unit(uid, count)
			# NOTE: spawn_unit은 CONSCRIPT 이벤트 방출하지 않음 (체인 독립).
			# 이벤트 필요 시 여기 추가.

	# R4/R10 milestone (enhance_convert_card; swarm_buff/lifesteal는 BS 타이밍)
	events.append_array(_process_r_conditional(card, idx, board))

	return {"events": events, "gold": 0, "terazin": 0}


func _special_ops(card: CardInstance, idx: int, board: Array) -> Dictionary:
	# 특수작전대 재설계(trace 012): 훈련 전파 제거, 치명타 중심으로 전환.
	# ★ 기본 효과: 치명타 버프(crit_buff) + 저격 드론 생산 (★2/★3, spawn_unit).
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

	# spawn_unit (★2/★3: 저격 드론)
	var spawn_eff := _find_eff(effs, "spawn_unit", "self")
	if not spawn_eff.is_empty():
		var uid: String = spawn_eff.get("unit", "")
		var count: int = spawn_eff.get("count", 1)
		if uid != "" and count > 0:
			card.add_specific_unit(uid, count)

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


func _conscript_react(card: CardInstance, idx: int, board: Array,
		event: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var target_idx: int = event.get("target_idx", -1)
	if target_idx < 0 or target_idx >= board.size():
		return Enums.empty_result()

	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var con_eff := _find_eff(effs, "conscript", "event_target")
	var add_n: int = con_eff.get("count", 1)
	var enh_n: int = int(con_eff.get("enhanced_count", 0))

	var target: CardInstance = board[target_idx]
	_conscript(target, add_n, rng, CONSCRIPT_POOL, enh_n)
	var events: Array = [_conscript_evt(idx, target_idx)]

	# R4/R10 milestone (enhance_convert_card + 반응 범위 확장 event_target_adj/far_event_military)
	events.append_array(_process_r_conditional(card, idx, board, event, rng))

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


## ml_factory PC 블록: 수집된 카드에 그 카드의 계급 × atk_pct_per_rank 만큼
## ATK 영구 강화. ml_factory 자신 rank 4+ 이면 동일 비율로 HP 도 강화.
## rank 10+ 이면 동일 비율로 AS 도 강화 (공격 속도 = upgrade_as_mult 값 감소).
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

	var coll: Dictionary = card.theme_state.get("trained_this_round", {})
	for key in coll.keys():
		var tgt_idx: int = int(key)
		if tgt_idx < 0 or tgt_idx >= board.size():
			continue
		var target: CardInstance = board[tgt_idx] as CardInstance
		if target == null:
			continue
		# Safety: TR 이벤트 대상은 군대 카드여야 함 (현재 파이프라인은 항상 그러하지만
		# future-proofing: 다른 테마가 TR layer2 를 재사용할 경우 영향 격리).
		if target.template.get("theme", -1) != Enums.CardTheme.MILITARY:
			continue
		var tgt_rank: int = _rank(target)
		if tgt_rank <= 0:
			continue
		var atk_pct: float = float(tgt_rank) * atk_per_rank
		var hp_pct: float = float(tgt_rank) * r4_hp_per_rank if apply_hp else 0.0
		if atk_pct > 0.0 or hp_pct > 0.0:
			target.enhance(null, atk_pct, hp_pct)
		if apply_as:
			# AS 강화 = upgrade_as_mult 값 감소 (낮을수록 빠름).
			# 1 / (1 + rank × pct) 형태로 안전하게 나눈다 (음수 걱정 없음).
			var as_divisor: float = 1.0 + float(tgt_rank) * r10_as_per_rank
			if as_divisor > 0.0:
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


# --- Deferred conscription helpers (3-pick-1 UI) ---


func clear_pending() -> void:
	pending_conscriptions.clear()


## 3택1 UI용 options 반환. 기본 base pool.
## card가 지정되면 해당 카드의 rank 기반 pool 사용 (징병국 R4/R10 반영).
func pick_conscript_options(rng: RandomNumberGenerator, count: int = 3,
		card: CardInstance = null) -> Array[String]:
	var pool: Array = _pool_for_card(card) if card != null else CONSCRIPT_POOL
	var result: Array[String] = []
	for _i in count:
		result.append(_weighted_pick(rng, pool))
	return result


func apply_conscript(card: CardInstance, unit_id: String) -> int:
	var added := card.add_specific_unit(unit_id, 1)
	if added > 0 and bonus_spawn_chance > 0.0 and bonus_rng != null:
		if bonus_rng.randf() < bonus_spawn_chance:
			added += card.add_specific_unit(unit_id, 1)
	return added
