extends GutTest
## 업그레이드 DB 데이터 정합성 테스트
## 참조: docs/design/upgrades-items.md
##
## 설계 문서의 수치가 upgrade_db.gd에 정확히 등록되었는지 검증.
## 이 테스트가 깨지면 설계 문서와 코드 간 불일치 발생.


func test_total_count() -> void:
	assert_eq(UpgradeDB.get_all_ids().size(), 26, "총 업그레이드 26종")


func test_common_count() -> void:
	var ids := UpgradeDB.get_ids_by_rarity(Enums.UpgradeRarity.COMMON)
	assert_eq(ids.size(), 11, "커먼 11종")


func test_rare_count() -> void:
	var ids := UpgradeDB.get_ids_by_rarity(Enums.UpgradeRarity.RARE)
	assert_eq(ids.size(), 9, "레어 9종")


func test_epic_count() -> void:
	var ids := UpgradeDB.get_ids_by_rarity(Enums.UpgradeRarity.EPIC)
	assert_eq(ids.size(), 6, "에픽 6종")


func test_common_cost_all_4() -> void:
	for id in UpgradeDB.get_ids_by_rarity(Enums.UpgradeRarity.COMMON):
		var tmpl := UpgradeDB.get_upgrade(id)
		assert_eq(tmpl["cost"], 4, "커먼 비용 4t: %s" % id)


func test_rare_cost_all_8() -> void:
	for id in UpgradeDB.get_ids_by_rarity(Enums.UpgradeRarity.RARE):
		var tmpl := UpgradeDB.get_upgrade(id)
		assert_eq(tmpl["cost"], 8, "레어 비용 8t: %s" % id)


func test_epic_cost_all_0() -> void:
	for id in UpgradeDB.get_ids_by_rarity(Enums.UpgradeRarity.EPIC):
		var tmpl := UpgradeDB.get_upgrade(id)
		assert_eq(tmpl["cost"], 0, "에픽 비용 0 (보상 전용): %s" % id)


# --- 개별 아이템 수치 검증 ---
# upgrades-items.md 수치를 직접 대조

func test_C1_강화합금() -> void:
	var t := UpgradeDB.get_upgrade("C1")
	assert_eq(t["rarity"], Enums.UpgradeRarity.COMMON)
	assert_almost_eq(t["stat_mods"].get("atk_pct", 0.0), 0.15, 0.001, "ATK +15%")
	assert_eq(t["mechanics"].size(), 0, "메카닉 없음")


func test_C2_생체보강제() -> void:
	var t := UpgradeDB.get_upgrade("C2")
	assert_almost_eq(t["stat_mods"].get("hp_pct", 0.0), 0.15, 0.001, "HP +15%")


func test_C3_경량장갑() -> void:
	var t := UpgradeDB.get_upgrade("C3")
	assert_eq(t["stat_mods"].get("def", 0), 1, "DEF +1")


func test_C4_사거리확장기() -> void:
	var t := UpgradeDB.get_upgrade("C4")
	assert_eq(t["stat_mods"].get("range", 0), 1, "Range +1")


func test_C5_추진부스터() -> void:
	var t := UpgradeDB.get_upgrade("C5")
	assert_eq(t["stat_mods"].get("move_speed", 0), 15, "MS +15")


func test_C6_가속장치() -> void:
	var t := UpgradeDB.get_upgrade("C6")
	# AS +15% = attack_interval × 0.85
	assert_almost_eq(t["stat_mods"].get("as_mult", 1.0), 0.85, 0.001, "AS interval ×0.85")


func test_C7_가시외피() -> void:
	var t := UpgradeDB.get_upgrade("C7")
	var m := _find_mechanic(t["mechanics"], "thorns")
	assert_false(m.is_empty(), "thorns 메카닉 존재")
	assert_almost_eq(m.get("reflect_pct", 0.0), 0.20, 0.001, "반사 20%")


func test_C8_응급수리() -> void:
	var t := UpgradeDB.get_upgrade("C8")
	var m := _find_mechanic(t["mechanics"], "battle_start_heal")
	assert_false(m.is_empty(), "메카닉 존재")
	assert_almost_eq(m.get("heal_hp_pct", 0.0), 0.10, 0.001, "전투 시작 HP +10%")


func test_C9_관통탄() -> void:
	var t := UpgradeDB.get_upgrade("C9")
	var m := _find_mechanic(t["mechanics"], "armor_pierce")
	assert_false(m.is_empty(), "메카닉 존재")
	assert_almost_eq(m.get("ignore_def_pct", 0.0), 0.50, 0.001, "DEF 50% 무시")


func test_C10_집중사격() -> void:
	var t := UpgradeDB.get_upgrade("C10")
	var m := _find_mechanic(t["mechanics"], "focus_fire")
	assert_false(m.is_empty(), "메카닉 존재")
	assert_almost_eq(m.get("stack_atk_pct", 0.0), 0.10, 0.001, "스택당 ATK +10%")


func test_C11_보호막발생기() -> void:
	var t := UpgradeDB.get_upgrade("C11")
	var m := _find_mechanic(t["mechanics"], "battle_start_shield")
	assert_false(m.is_empty(), "메카닉 존재")
	assert_almost_eq(m.get("shield_hp_pct", 0.0), 0.15, 0.001, "방어막 HP 15%")


func test_R1_흡혈송곳니() -> void:
	var t := UpgradeDB.get_upgrade("R1")
	var m := _find_mechanic(t["mechanics"], "lifesteal")
	assert_false(m.is_empty(), "메카닉 존재")
	assert_almost_eq(m.get("steal_pct", 0.0), 0.15, 0.001, "라이프스틸 15%")


func test_R2_산탄개조() -> void:
	var t := UpgradeDB.get_upgrade("R2")
	var m := _find_mechanic(t["mechanics"], "splash")
	assert_false(m.is_empty(), "메카닉 존재")
	assert_almost_eq(m.get("splash_pct", 0.0), 0.50, 0.001, "스플래시 50%")


func test_R3_위상변환기() -> void:
	var t := UpgradeDB.get_upgrade("R3")
	var m := _find_mechanic(t["mechanics"], "phase_shift")
	assert_false(m.is_empty(), "메카닉 존재")


func test_R4_전술후퇴() -> void:
	var t := UpgradeDB.get_upgrade("R4")
	var m := _find_mechanic(t["mechanics"], "tactical_retreat")
	assert_false(m.is_empty(), "메카닉 존재")
	assert_almost_eq(m.get("hp_threshold", 0.0), 0.25, 0.001, "HP 25% 임계")


func test_R5_연쇄방전() -> void:
	var t := UpgradeDB.get_upgrade("R5")
	var m := _find_mechanic(t["mechanics"], "chain_discharge")
	assert_false(m.is_empty(), "메카닉 존재")
	assert_almost_eq(m.get("chain_dmg_pct", 0.0), 0.30, 0.001, "연쇄 데미지 30%")


func test_R6_재생프로토콜() -> void:
	var t := UpgradeDB.get_upgrade("R6")
	var m := _find_mechanic(t["mechanics"], "regen")
	assert_false(m.is_empty(), "메카닉 존재")
	assert_almost_eq(m.get("interval_sec", 0.0), 3.0, 0.001, "3초 간격")
	assert_almost_eq(m.get("heal_hp_pct", 0.0), 0.05, 0.001, "HP 5% 회복")


func test_R7_중력앵커() -> void:
	var t := UpgradeDB.get_upgrade("R7")
	var m := _find_mechanic(t["mechanics"], "slow_aura")
	assert_false(m.is_empty(), "메카닉 존재")
	assert_almost_eq(m.get("slow_pct", 0.0), 0.30, 0.001, "감속 30%")


func test_R8_정밀조준() -> void:
	var t := UpgradeDB.get_upgrade("R8")
	var m := _find_mechanic(t["mechanics"], "critical")
	assert_false(m.is_empty(), "메카닉 존재")
	assert_almost_eq(m.get("crit_chance", 0.0), 0.15, 0.001, "크리티컬 15%")
	assert_almost_eq(m.get("crit_mult", 0.0), 2.5, 0.001, "배율 ×2.5")


func test_R9_중장갑() -> void:
	var t := UpgradeDB.get_upgrade("R9")
	assert_eq(t["stat_mods"].get("def", 0), 2, "DEF +2")
	assert_almost_eq(t["stat_mods"].get("hp_pct", 0.0), 0.20, 0.001, "HP +20%")


func test_E1_광폭화() -> void:
	var t := UpgradeDB.get_upgrade("E1")
	var m := _find_mechanic(t["mechanics"], "berserk")
	assert_false(m.is_empty(), "메카닉 존재")
	assert_almost_eq(m.get("hp_threshold", 0.0), 0.30, 0.001, "HP 30% 임계")
	assert_almost_eq(m.get("atk_mult", 0.0), 2.0, 0.001, "ATK ×2")
	assert_almost_eq(m.get("as_mult", 0.0), 2.0, 0.001, "AS ×2")


func test_E2_연쇄폭발() -> void:
	var t := UpgradeDB.get_upgrade("E2")
	var m := _find_mechanic(t["mechanics"], "chain_explosion")
	assert_false(m.is_empty(), "메카닉 존재")
	assert_almost_eq(m.get("splash_pct", 0.0), 0.70, 0.001, "스플래시 70%")


func test_E3_불멸의핵() -> void:
	var t := UpgradeDB.get_upgrade("E3")
	var m := _find_mechanic(t["mechanics"], "immortal_core")
	assert_false(m.is_empty(), "메카닉 존재")


func test_E4_영혼수확() -> void:
	var t := UpgradeDB.get_upgrade("E4")
	var m := _find_mechanic(t["mechanics"], "soul_harvest")
	assert_false(m.is_empty(), "메카닉 존재")
	assert_almost_eq(m.get("kill_atk_pct", 0.0), 0.05, 0.001, "처치당 ATK +5%")


func test_E5_분열증식() -> void:
	var t := UpgradeDB.get_upgrade("E5")
	var m := _find_mechanic(t["mechanics"], "fission")
	assert_false(m.is_empty(), "메카닉 존재")
	assert_eq(m.get("clone_count", 0), 2, "2기 복제")


func test_E6_차원붕괴() -> void:
	var t := UpgradeDB.get_upgrade("E6")
	var m := _find_mechanic(t["mechanics"], "hp_percent_dmg")
	assert_false(m.is_empty(), "메카닉 존재")
	assert_almost_eq(m.get("dmg_pct", 0.0), 0.08, 0.001, "현재 HP 8% 추가뎀")


func test_unknown_id_returns_empty() -> void:
	var t := UpgradeDB.get_upgrade("nonexistent_id")
	assert_true(t.is_empty(), "존재하지 않는 ID는 빈 딕셔너리")


# --- Helper ---

func _find_mechanic(mechanics: Array, mtype: String) -> Dictionary:
	for m: Dictionary in mechanics:
		if m.get("type", "") == mtype:
			return m
	return {}
