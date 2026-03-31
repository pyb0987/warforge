extends Node
## Upgrade database. Autoloaded as "UpgradeDB".
## 26종 업그레이드 아이템. 설계 문서(upgrades-items.md) 기준 정확 이식.

var _upgrades: Dictionary = {}


func _ready() -> void:
	_register_common()
	_register_rare()
	_register_epic()
	print("[UpgradeDB] Registered %d upgrades." % _upgrades.size())


func get_upgrade(id: String) -> Dictionary:
	return _upgrades.get(id, {})


func get_all_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_upgrades.keys())
	return ids


func get_ids_by_rarity(rarity: int) -> Array[String]:
	var ids: Array[String] = []
	for key in _upgrades:
		if _upgrades[key]["rarity"] == rarity:
			ids.append(key)
	return ids


func _reg(id: String, uname: String, rarity: int, cost: int,
		stat_mods: Dictionary, mechanics: Array) -> void:
	_upgrades[id] = {
		"id": id, "name": uname, "rarity": rarity, "cost": cost,
		"stat_mods": stat_mods, "mechanics": mechanics,
	}


# ═══ 커먼 (11종, 4 테라진) ═══

func _register_common() -> void:
	var C := Enums.UpgradeRarity.COMMON

	# C1 강화합금 — ATK +15%
	_reg("C1", "강화합금", C, 4,
		{"atk_pct": 0.15}, [])

	# C2 생체보강제 — HP +15%
	_reg("C2", "생체보강제", C, 4,
		{"hp_pct": 0.15}, [])

	# C3 경량장갑 — DEF +1
	_reg("C3", "경량장갑", C, 4,
		{"def": 1}, [])

	# C4 사거리확장기 — Range +1
	_reg("C4", "사거리확장기", C, 4,
		{"range": 1}, [])

	# C5 추진부스터 — MS +15
	_reg("C5", "추진부스터", C, 4,
		{"move_speed": 15}, [])

	# C6 가속장치 — 공격속도 +15% (attack_interval × 0.85)
	_reg("C6", "가속장치", C, 4,
		{"as_mult": 0.85}, [])

	# C7 가시외피 — 피격 시 ATK 20% 반사
	_reg("C7", "가시외피", C, 4,
		{}, [{"type": "thorns", "reflect_pct": 0.20}])

	# C8 응급수리 — 전투 시작 시 HP 10% 회복
	_reg("C8", "응급수리", C, 4,
		{}, [{"type": "battle_start_heal", "heal_hp_pct": 0.10}])

	# C9 관통탄 — DEF 50% 무시
	_reg("C9", "관통탄", C, 4,
		{}, [{"type": "armor_pierce", "ignore_def_pct": 0.50}])

	# C10 집중사격 — 동일 대상 연속 공격 시 ATK +10% 누적
	_reg("C10", "집중사격", C, 4,
		{}, [{"type": "focus_fire", "stack_atk_pct": 0.10}])

	# C11 보호막발생기 — 전투 시작 시 HP 15% 방어막
	_reg("C11", "보호막발생기", C, 4,
		{}, [{"type": "battle_start_shield", "shield_hp_pct": 0.15}])


# ═══ 레어 (9종, 8 테라진) ═══

func _register_rare() -> void:
	var R := Enums.UpgradeRarity.RARE

	# R1 흡혈송곳니 — 공격 데미지 15% HP 회복
	_reg("R1", "흡혈송곳니", R, 8,
		{}, [{"type": "lifesteal", "steal_pct": 0.15}])

	# R2 산탄개조 — 주변 1칸 50% 스플래시
	_reg("R2", "산탄개조", R, 8,
		{}, [{"type": "splash", "splash_range": 1, "splash_pct": 0.50}])

	# R3 위상변환기 — 첫 피격 무효 (전투당 1회)
	_reg("R3", "위상변환기", R, 8,
		{}, [{"type": "phase_shift", "uses_per_combat": 1}])

	# R4 전술후퇴 — HP 25% 이하 시 MS ×2 + 5초 무적, 복귀
	_reg("R4", "전술후퇴", R, 8,
		{}, [{"type": "tactical_retreat",
			"hp_threshold": 0.25, "ms_mult": 2.0, "invuln_sec": 5.0}])

	# R5 연쇄방전 — 처치 시 주변 ATK 30% 데미지
	_reg("R5", "연쇄방전", R, 8,
		{}, [{"type": "chain_discharge", "chain_dmg_pct": 0.30}])

	# R6 재생프로토콜 — 3초마다 HP 5% 회복
	_reg("R6", "재생프로토콜", R, 8,
		{}, [{"type": "regen", "interval_sec": 3.0, "heal_hp_pct": 0.05}])

	# R7 중력앵커 — 사거리 내 적 MS -30% (최대 -60%)
	_reg("R7", "중력앵커", R, 8,
		{}, [{"type": "slow_aura", "slow_pct": 0.30, "max_slow_pct": 0.60}])

	# R8 정밀조준 — 크리티컬 15%, 데미지 ×2.5
	_reg("R8", "정밀조준", R, 8,
		{}, [{"type": "critical", "crit_chance": 0.15, "crit_mult": 2.5}])

	# R9 중장갑 — DEF +2, HP +20%
	_reg("R9", "중장갑", R, 8,
		{"def": 2, "hp_pct": 0.20}, [])


# ═══ 에픽 (6종, 보스 보상 / ★3 합성 전용) ═══

func _register_epic() -> void:
	var E := Enums.UpgradeRarity.EPIC

	# E1 광폭화 — HP 30% 이하 시 ATK ×2, AS ×2, 회복 불가
	_reg("E1", "광폭화", E, 0,
		{}, [{"type": "berserk",
			"hp_threshold": 0.30, "atk_mult": 2.0, "as_mult": 2.0,
			"no_heal": true}])

	# E2 연쇄폭발 — 스플래시 70% + 처치 시 ATK 50% AOE (반경 2칸)
	_reg("E2", "연쇄폭발", E, 0,
		{}, [{"type": "chain_explosion",
			"splash_pct": 0.70, "kill_aoe_pct": 0.50, "aoe_range": 2}])

	# E3 불멸의핵 — 치명타 시 HP 1 생존 + 3초 무적 (1회), HP 50% 회복
	_reg("E3", "불멸의핵", E, 0,
		{}, [{"type": "immortal_core",
			"uses_per_combat": 1, "invuln_sec": 3.0, "recover_hp_pct": 0.50}])

	# E4 영혼수확 — 처치 시 ATK +5% 영구 누적, 10킬 시 AS ×1.5
	_reg("E4", "영혼수확", E, 0,
		{}, [{"type": "soul_harvest",
			"kill_atk_pct": 0.05, "kill_threshold": 10, "as_bonus_mult": 1.5}])

	# E5 분열증식 — 사망 시 같은 유닛 2기 소환 (HP 50%, ATK 50%), 분열 불가
	_reg("E5", "분열증식", E, 0,
		{}, [{"type": "fission",
			"clone_count": 2, "clone_hp_pct": 0.50, "clone_atk_pct": 0.50}])

	# E6 차원붕괴 — 공격 시 대상 현재 HP 8% 추가 데미지 (DEF 무시)
	_reg("E6", "차원붕괴", E, 0,
		{}, [{"type": "hp_percent_dmg",
			"dmg_pct": 0.08, "ignore_def": true}])
