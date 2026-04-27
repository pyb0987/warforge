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
	_reg("r4_2", "긴급 자금", "⚡", "+12 골드",
		4, "instant", 0)
	_reg("r4_3", "연쇄 반응로", "🔄", "영구: 유닛 추가 시 25% 확률 추가 1기",
		4, "permanent", 0)
	_reg("r4_4", "상점 확장", "🔄", "즉시 무료 리롤 5회 + 영구 매 라운드 시작 시 +1회",
		4, "permanent", 0)
	_reg("r4_5", "강화 증폭기", "🔄", "영구: 강화 효과 +20%",
		4, "permanent", 0)
	_reg("r4_6", "자동 징집", "🔄", "영구: 매 라운드 전체 +1기",
		4, "permanent", 0)
	_reg("r4_7", "정예 각성", "💥", "카드 1장: ATK +30%, HP +30%",
		4, "direct", 1)
	_reg("r4_8", "보급 호송", "💥", "랜덤 T4 1장 + T3 1장 (T4 우선, 벤치 만석 시 못 받음)",
		4, "direct", 0)
	_reg("r4_9", "확장 벤치", "📐", "벤치 +2칸",
		4, "structural", 0)


# ================================================================
# R8 — 전환 (9종)
# ================================================================

func _register_r8() -> void:
	_reg("r8_1", "대규모 징집", "⚡", "카드 1장: ★승급 + 레어 업글 1개 부착",
		8, "instant", 1, "rare")
	_reg("r8_2", "전쟁 기금", "⚡", "18 골드 + 4 테라진",
		8, "instant", 0)
	_reg("r8_3", "장인의 회수", "🔄", "영구: ★ 합성 시 합성 대상 티어 비용 환급",
		8, "permanent", 0)
	_reg("r8_4", "무한 금고", "🔄", "영구: 이자 cap 무제한",
		8, "permanent", 0)
	_reg("r8_5", "광역 강화장", "🔄", "영구: 강화 시 인접 50%",
		8, "permanent", 0)
	_reg("r8_6", "승전 의지", "🔄", "영구: 승리 시 전체 ATK +3%",
		8, "permanent", 0)
	_reg("r8_7", "유전자 강화", "💥", "카드 1장: 에픽 업글 1개 부착",
		8, "direct", 1)
	_reg("r8_8", "방어선 구축", "🔄", "영구: 전체 카드 DEF +2",
		8, "permanent", 0)
	_reg("r8_9", "전선 확장", "🔄", "R13 전투 승리 시 R12 보상 1개 추가 선택 (1회)",
		8, "permanent", 0)


# ================================================================
# R12 — 완성 (9종)
# ================================================================

func _register_r12() -> void:
	_reg("r12_1", "궁극 진화", "⚡", "★2 카드 1장 → ★3, 그 다음 ★1 카드 1장 → ★2",
		12, "instant", 2)
	_reg("r12_2", "제국의 유산", "⚡", "전체 카드 ATK +25%, HP +25%",
		12, "instant", 0)
	_reg("r12_3", "과부하 연쇄", "🔄", "영구: 발동 상한 +1",
		12, "permanent", 0)
	_reg("r12_4", "상점 대확장", "🔄", "영구: 상점 슬롯 +2 + 매 라운드 무료 리롤 +2",
		12, "permanent", 0)
	_reg("r12_5", "오색 군단", "🔄", "영구: 매 라운드 시작 시 보드 테마 개수×ATK/HP +10%",
		12, "permanent", 0)
	_reg("r12_6", "물량의 법칙", "🔄", "영구: 50기+ 카드 → ATK ×1.4, AS ×1.2",
		12, "permanent", 0)
	_reg("r12_7", "신의 일격", "💥", "카드 1장: 에픽 + 레어 업글 1개씩 부착",
		12, "direct", 1)
	_reg("r12_8", "전사의 영혼", "🔄", "영구: 매 전투 시작 시 부활 풀 20기 활성. 처음 사망한 아군 20기 100% HP 부활 (전투당 풀 리셋).",
		12, "permanent", 0)
	_reg("r12_9", "차원 균열", "📐", "필드+1 + 전체 업글슬롯+1",
		12, "structural", 0)
