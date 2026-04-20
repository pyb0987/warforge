extends Node
## 보스 보상 27종 데이터 + 풀 조회. Autoloaded as "BossRewardDB".
## 참조: docs/design/boss-rewards.md (확정)
##
## 패턴: CardDB/UpgradeDB와 동일 — static 데이터 + 조회 함수.

var _data := {}
var _pools := {}  # boss_tier → Array[String]


func _init() -> void:
	_register_r4()
	_register_r8()
	_register_r12()


# ================================================================
# 조회
# ================================================================

func get_data(id: String) -> Dictionary:
	return _data.get(id, {})


func get_all_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_data.keys())
	return ids


func get_pool(boss_tier: int) -> Array[String]:
	return _pools.get(boss_tier, [] as Array[String])


## count개 보상을 중복 없이 랜덤 선택.
func roll_choices(boss_tier: int, count: int,
		rng: RandomNumberGenerator) -> Array[String]:
	var pool := get_pool(boss_tier)
	if pool.is_empty():
		return [] as Array[String]
	var actual := mini(count, pool.size())
	var shuffled := pool.duplicate()
	# Fisher–Yates shuffle
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: String = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	var result: Array[String] = []
	for i in actual:
		result.append(shuffled[i])
	return result


# ================================================================
# 등록 헬퍼
# ================================================================

func _reg(id: String, rname: String, icon: String, desc: String,
		boss_tier: int, type: String, needs_target: int,
		needs_upgrade_choice: String = "") -> void:
	_data[id] = {
		"id": id, "name": rname, "icon": icon, "desc": desc,
		"boss_tier": boss_tier, "type": type,
		"needs_target": needs_target,
		"needs_upgrade_choice": needs_upgrade_choice,
	}
	if not _pools.has(boss_tier):
		_pools[boss_tier] = [] as Array[String]
	_pools[boss_tier].append(id)


# ================================================================
# R4 — 기반 (9종)
# ================================================================

func _register_r4() -> void:
	_reg("r4_1", "긴급 보급", "⚡", "카드 1장 선택: ★승급 + 4 테라진",
		4, "instant", 1)
	_reg("r4_2", "용병단 초청", "⚡", "상점에 T3+ 카드 6장 + 10 골드",
		4, "instant", 0)
	_reg("r4_3", "연쇄 반응로", "🔄", "영구: 유닛 추가 시 50% 확률 추가 1기",
		4, "permanent", 0)
	_reg("r4_4", "상점 확장", "🔄", "영구: 상점 슬롯 +1 (6→7)",
		4, "permanent", 0)
	_reg("r4_5", "강화 증폭기", "🔄", "영구: 강화 효과 +50%",
		4, "permanent", 0)
	_reg("r4_6", "자동 징집", "🔄", "영구: 매 라운드 전체 +1기",
		4, "permanent", 0)
	_reg("r4_7", "정예 각성", "💥", "카드 1장: ATK +30%, HP +30%",
		4, "direct", 1)
	_reg("r4_8", "비상 증원", "💥", "카드 1장: 유닛 +5기",
		4, "direct", 1)
	_reg("r4_9", "확장 벤치", "📐", "벤치 +2칸",
		4, "structural", 0)


# ================================================================
# R8 — 전환 (9종)
# ================================================================

func _register_r8() -> void:
	_reg("r8_1", "대규모 징집", "⚡", "카드 1장: ★승급 + 에픽 업글 3택1",
		8, "instant", 1, "epic")
	_reg("r8_2", "전쟁 기금", "⚡", "15골드 + 8 테라진",
		8, "instant", 0)
	_reg("r8_3", "과부하 엔진", "🔄", "영구: 발동 상한 +1",
		8, "permanent", 0)
	_reg("r8_4", "전리품 회수", "🔄", "영구: 승리 +3g, 패배 +2t",
		8, "permanent", 0)
	_reg("r8_5", "광역 강화장", "🔄", "영구: 강화 시 인접 50%",
		8, "permanent", 0)
	_reg("r8_6", "승전 의지", "🔄", "영구: 승리 시 전체 ATK +3%",
		8, "permanent", 0)
	_reg("r8_7", "유전자 강화", "💥", "카드 1장: 유닛 2배 + 레어 업글",
		8, "direct", 1)
	_reg("r8_8", "일괄 증원", "💥", "전체 카드 +3기",
		8, "direct", 0)
	_reg("r8_9", "전선 확장", "📐", "필드 +1칸",
		8, "structural", 0)


# ================================================================
# R12 — 완성 (9종)
# ================================================================

func _register_r12() -> void:
	_reg("r12_1", "궁극 진화", "⚡", "카드 2장: 각각 ★승급",
		12, "instant", 2)
	_reg("r12_2", "제국의 유산", "⚡", "전체 ATK+20% HP+20% + 15t",
		12, "instant", 0)
	_reg("r12_3", "과부하 연쇄", "🔄", "영구: 발동 상한 +2",
		12, "permanent", 0)
	_reg("r12_4", "이중 합성 (재설계 필요)", "🔄", "[효과 재설계 예정 — 2026-04-20 합성 보너스 제거로 dead reward]",
		12, "permanent", 0)
	_reg("r12_5", "전장의 메아리", "🔄", "영구: 사망 시 ATK +3%",
		12, "permanent", 0)
	_reg("r12_6", "물량의 법칙", "🔄", "영구: 50기+ → ATK×1.5, AS×1.3",
		12, "permanent", 0)
	_reg("r12_7", "신의 일격", "💥", "카드 1장: ATK ×2 + 에픽 업글",
		12, "direct", 1, "epic")
	_reg("r12_8", "군단 복제", "💥", "카드 1장: 유닛 3배",
		12, "direct", 1)
	_reg("r12_9", "차원 균열", "📐", "필드+1 + 전체 업글슬롯+1",
		12, "structural", 0)
