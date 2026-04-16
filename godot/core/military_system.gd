class_name MilitarySystem
extends "res://core/theme_system.gd"
## Military theme system: rank/training + conscription.
## RS cards (barracks, outpost, special_ops, command) train/conscript;
## OE cards (academy, conscript_react, factory) chain off TRAIN/CONSCRIPT events.

# Conscription unit pool (growth chain uses weighted random)
const CONSCRIPT_POOL: Array = [
	{"id": "ml_recruit", "weight": 3},
	{"id": "ml_drone", "weight": 2},
	{"id": "ml_biker", "weight": 2},
	{"id": "ml_infantry", "weight": 1},
	{"id": "ml_shield", "weight": 1},
	{"id": "ml_plasma", "weight": 1},
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
		"ml_academy": return _academy(card, idx, board, event)
		"ml_outpost": return _conscript_react(card, idx, board, event, rng)
		"ml_factory": return _factory(card, idx, board)
	return Enums.empty_result()


# --- External hooks (combat engine) ---


func apply_battle_start(card: CardInstance, idx: int, board: Array) -> Dictionary:
	match card.get_base_id():
		"ml_tactical": return _tactical_battle(card, idx, board)
		"ml_assault": return _assault_battle(card, idx, board)
	return Enums.empty_result()


func apply_post_combat(card: CardInstance, idx: int, board: Array,
		won: bool) -> Dictionary:
	if card.get_base_id() == "ml_supply":
		return _supply_post(card, idx, board, won)
	return Enums.empty_result()


## Persistent combat: ml_command revive stored for combat engine.
func apply_persistent(card: CardInstance) -> void:
	if card.get_base_id() != "ml_command":
		return
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var revive_eff := _find_eff(effs, "revive")
	card.theme_state["revive_hp_pct"] = revive_eff.get("hp_pct", 0.50)
	card.theme_state["revive_limit"] = revive_eff.get("limit_per_combat", 1)


# --- Rank / Conscription helpers ---


func _find_eff(effs: Array, action: String, target: String = "") -> Dictionary:
	for e in effs:
		if e.get("action") == action:
			if target == "" or e.get("target", "") == target:
				return e
	return {}


func _rank(card: CardInstance) -> int:
	return card.theme_state.get("rank", 0)


func _add_rank(card: CardInstance, n: int) -> void:
	card.theme_state["rank"] = _rank(card) + n


func _train_card(card: CardInstance, idx: int, amount: int) -> Array:
	## Train a card: add rank, check thresholds, return TRAIN events.
	var old_rank := _rank(card)
	_add_rank(card, amount)
	_check_thresholds(card, old_rank, _rank(card))
	return [{
		"layer1": Enums.Layer1.ENHANCED,
		"layer2": Enums.Layer2.TRAIN,
		"source_idx": idx, "target_idx": idx,
	}]


## @deprecated: rank_threshold 액션이 R4/R10 milestone 재설계(2026-04-16, trace 012)로
## YAML에서 제거됨. 현재는 no-op. Step 3 구현 스프린트에서
## R4/R10 공통 처리(enhance_convert_card) 및 카드별 r_conditional 로직으로 대체 예정.
func _check_thresholds(card: CardInstance, old: int, new_rank: int) -> void:
	var triggered: Dictionary = card.theme_state.get("rank_triggers", {})
	var base := card.get_base_id()
	var effs := CardDB.get_theme_effects(base, card.star_level)
	var thresh_eff := _find_eff(effs, "rank_threshold")
	if thresh_eff.is_empty():
		card.theme_state["rank_triggers"] = triggered
		return

	var tiers: Array = thresh_eff.get("tiers", [])
	for tier in tiers:
		var rank_val: int = tier.get("rank", -1)
		if rank_val < 0:
			continue
		if old < rank_val and new_rank >= rank_val and not triggered.get(rank_val, false):
			triggered[rank_val] = true
			var unit_id: String = tier.get("unit", "")
			var count: int = tier.get("count", 1)
			for _i in count:
				_add_with_bonus(card, unit_id, 1)

	card.theme_state["rank_triggers"] = triggered


## Return the next unfired rank threshold for a military card, or -1 if none.
## @deprecated: R4/R10 milestone 재설계(2026-04-16, trace 012)로 YAML에서
## rank_threshold 제거됨 → 항상 -1 반환. UI(card_tooltip)에서 자연스럽게 표시 숨김.
## Step 3에서 R4/R10 milestone 표시 방식으로 대체 예정.
static func get_next_threshold(card: CardInstance) -> int:
	var base := card.get_base_id()
	var rank: int = card.theme_state.get("rank", 0)
	var triggered: Dictionary = card.theme_state.get("rank_triggers", {})
	var effs := CardDB.get_theme_effects(base, card.star_level)
	var thresh_eff: Dictionary = {}
	for e in effs:
		if e.get("action") == "rank_threshold":
			thresh_eff = e
			break
	if thresh_eff.is_empty():
		return -1
	var tiers: Array = thresh_eff.get("tiers", [])
	for tier in tiers:
		var t: int = tier.get("rank", -1)
		if t >= 0 and not triggered.get(t, false):
			return t
	return -1


## 양성가 보너스 포함 유닛 추가 (이벤트 미방출).
func _add_with_bonus(target: CardInstance, unit_id: String, count: int) -> int:
	var added := target.add_specific_unit(unit_id, count)
	var bonus := CardInstance.roll_bonus_count(added, bonus_spawn_chance, bonus_rng)
	if bonus > 0:
		target.add_specific_unit(unit_id, bonus)
	return added


func _conscript(target: CardInstance, count: int, rng: RandomNumberGenerator) -> int:
	var added := 0
	for _i in count:
		var uid := _weighted_pick(rng)
		var n := target.add_specific_unit(uid, 1)
		added += n
		# 양성가 보너스: 징집 유닛 각각 확률로 1기 추가 (이벤트 미방출)
		if n > 0 and bonus_spawn_chance > 0.0 and bonus_rng != null:
			if bonus_rng.randf() < bonus_spawn_chance:
				added += target.add_specific_unit(uid, 1)
	return added


func _weighted_pick(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for entry in CONSCRIPT_POOL:
		total += entry["weight"]
	var r := rng.randf() * total
	var cum := 0.0
	for entry in CONSCRIPT_POOL:
		cum += entry["weight"]
		if r <= cum:
			return entry["id"]
	return CONSCRIPT_POOL[0]["id"]


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
func _process_r_conditional(card: CardInstance, idx: int, board: Array,
		event: Dictionary = {}, rng: RandomNumberGenerator = null) -> Array:
	var events: Array = []
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var rank := _rank(card)
	for eff in effs:
		if eff.get("action", "") != "r_conditional":
			continue
		var condition: String = eff.get("condition", "")
		var threshold: int = eff.get("threshold", 0)
		var passed := false
		match condition:
			"rank_gte":
				passed = rank >= threshold
			_:
				passed = false
		if not passed:
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
			for ti in targets:
				if rng != null:
					_conscript(board[ti] as CardInstance, count, rng)
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
		"rank_buff_hp":
			# 전술사령부 R4: 모든 군대 카드에 계급당 HP +% buff (BS 타이밍).
			_apply_rank_buff_hp(eff, card, board)
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

	var total_units := 0
	for mi in _military_indices(board):
		total_units += (board[mi] as CardInstance).get_total_units()

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
	# 매 실행 시 덮어쓰기: R10 우선, R4 차선, base 최후.
	# 순서 보장: dispatch가 YAML 선언 순서대로 호출 → 마지막 값이 최종.
	card.theme_state["crit_chance"] = chance
	card.theme_state["crit_mult"] = mult


## crit_splash 적용 (특수작전대 R4/R10). theme_state에 splash_pct 저장.
## _materialize_army가 읽어 crit mechanic과 함께 unit mechanics에 주입.
func _apply_crit_splash(eff: Dictionary, card: CardInstance) -> void:
	var splash_pct: float = eff.get("splash_pct", 0.0)
	if splash_pct <= 0:
		return
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

		for ni in adj_list:
			var adj: CardInstance = board[ni]
			if adj.template.get("theme", -1) == Enums.CardTheme.MILITARY:
				_conscript(adj, 1, rng)
				events.append(_conscript_evt(idx, ni))

	# R4/R10 milestone (enhance_convert_card, conscript_pool_tier, far_event_military 등)
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
		event: Dictionary) -> Dictionary:
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

	# R4/R10 milestone (enhance_convert_card; enhance_convert_target/spawn_enhanced_random는 Phase 3)
	events.append_array(_process_r_conditional(card, idx, board, event))

	return {"events": events, "gold": 0, "terazin": 0}


func _conscript_react(card: CardInstance, idx: int, board: Array,
		event: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var target_idx: int = event.get("target_idx", -1)
	if target_idx < 0 or target_idx >= board.size():
		return Enums.empty_result()

	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var con_eff := _find_eff(effs, "conscript", "event_target")
	var add_n: int = con_eff.get("count", 1)

	var target: CardInstance = board[target_idx]
	_conscript(target, add_n, rng)
	var events: Array = [_conscript_evt(idx, target_idx)]

	# R4/R10 milestone (enhance_convert_card + 반응 범위 확장 event_target_adj/far_event_military)
	events.append_array(_process_r_conditional(card, idx, board, event, rng))

	return {"events": events, "gold": 0, "terazin": 0}


func _factory(card: CardInstance, idx: int, board: Array) -> Dictionary:
	# 재설계(trace 012): rewards 구조 변경.
	# 구 버전: {terazin: N, enhance_atk_pct: N} — 이 카드만 enhance.
	# 신 버전: {global_military_atk_pct: N, global_military_range_bonus: N}
	#          — 모든 군대 카드에 영구 ATK/Range 증가.
	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var prod_eff := _find_eff(effs, "counter_produce")
	var threshold: int = prod_eff.get("threshold", 10)
	var rewards: Dictionary = prod_eff.get("rewards", {})

	var counter: int = card.theme_state.get("conscript_counter", 0)
	counter += 1

	if counter >= threshold:
		counter -= threshold
		# 모든 군대 카드에 ATK 영구 증강 (card.enhance → growth_atk_pct 누적)
		var global_atk: float = rewards.get("global_military_atk_pct", 0.0)
		if global_atk > 0.0:
			for mi in _military_indices(board):
				(board[mi] as CardInstance).enhance(null, global_atk, 0.0)
		# Range +N 영구 (★3 전용). card.upgrade_range는 업그레이드 시스템이
		# 쓰는 필드이므로, 별도 theme_state["range_bonus"]에 누적해 _materialize_army에서 반영.
		var range_bonus: int = int(rewards.get("global_military_range_bonus", 0))
		if range_bonus > 0:
			for mi in _military_indices(board):
				var mc: CardInstance = board[mi]
				mc.theme_state["range_bonus"] = mc.theme_state.get("range_bonus", 0) + range_bonus

	card.theme_state["conscript_counter"] = counter

	# R4/R10 milestone (enhance_convert_card; upgrade_shop_bonus는 Phase 4)
	var r_events := _process_r_conditional(card, idx, board)
	return {"events": r_events, "gold": 0, "terazin": 0}


# --- Battle hooks ---


func _tactical_battle(card: CardInstance, idx: int, board: Array) -> Dictionary:
	# 이전 전투의 as_bonus 잔류 방지 (R10 해제는 불가하지만 안전 차원).
	for mi in _military_indices(board):
		(board[mi] as CardInstance).theme_state.erase("as_bonus")

	var effs := CardDB.get_theme_effects(card.get_base_id(), card.star_level)
	var buff_eff := _find_eff(effs, "rank_buff", "all_military")
	var shield_per_rank: float = buff_eff.get("shield_per_rank", 0.02)
	var atk_per_unit: float = buff_eff.get("atk_per_unit", 0.005)

	var rank := _rank(card)
	var total_units := 0
	for mi in _military_indices(board):
		total_units += (board[mi] as CardInstance).get_total_units()

	var shield_pct := rank * shield_per_rank
	var atk_pct := float(total_units) * atk_per_unit

	for mi in _military_indices(board):
		var mc: CardInstance = board[mi]
		mc.shield_hp_pct += shield_pct
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


func pick_conscript_options(rng: RandomNumberGenerator, count: int = 3) -> Array[String]:
	var result: Array[String] = []
	for _i in count:
		result.append(_weighted_pick(rng))
	return result


func apply_conscript(card: CardInstance, unit_id: String) -> int:
	var added := card.add_specific_unit(unit_id, 1)
	if added > 0 and bonus_spawn_chance > 0.0 and bonus_rng != null:
		if bonus_rng.randf() < bonus_spawn_chance:
			added += card.add_specific_unit(unit_id, 1)
	return added
