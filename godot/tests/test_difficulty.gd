extends GutTest
## Difficulty rule contract.


func test_cumulative_economy_rules() -> void:
	assert_eq(Difficulty.get_starting_gold(13, 1), 13, "D1 시작 골드 유지")
	assert_eq(Difficulty.get_starting_gold(13, 3), 10, "D3 시작 골드 -3")
	assert_eq(Difficulty.get_starting_gold(3, 3), 2, "D3 현재 경제 시작 골드 -1")
	assert_eq(Difficulty.get_starting_gold(0, 3), 0, "D3 시작 골드 floor 0")
	assert_eq(Difficulty.get_shop_size(6, 5), 6, "D5 상점 크기 유지")
	assert_eq(Difficulty.get_shop_size(6, 6), 4, "D6 상점 4장")
	assert_eq(Difficulty.get_reroll_cost(1, 6), 2, "D6 리롤 2골드")
	assert_eq(Difficulty.get_player_hp(30, 8), 20, "D8 플레이어 HP 20")


func test_cumulative_enemy_stat_rules() -> void:
	assert_almost_eq(Difficulty.get_enemy_hp_mult(1), 1.0, 0.001)
	assert_almost_eq(Difficulty.get_enemy_hp_mult(2), 1.2, 0.001)
	assert_almost_eq(Difficulty.get_enemy_count_mult(4), 1.10, 0.001)
	assert_almost_eq(Difficulty.get_enemy_atk_mult(7), 1.10, 0.001)


func test_apply_enemy_modifiers_scales_hp_and_atk() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var units := [{
		"atk": 10.0, "hp": 100.0, "attack_speed": 1.0,
		"range": 1, "move_speed": 2, "mechanics": [],
	}]
	Difficulty.apply_enemy_modifiers(units, 1, rng, 7)
	assert_almost_eq(float(units[0]["hp"]), 120.0, 0.001, "D2+ HP")
	assert_almost_eq(float(units[0]["atk"]), 11.0, 0.001, "D7 ATK")


func test_apply_enemy_count_modifier_duplicates_floor_percent_bonus() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var units := []
	for i in 10:
		units.append({
			"atk": 10.0 + i, "hp": 100.0, "attack_speed": 1.0,
			"range": 1, "move_speed": 2, "mechanics": [],
		})
	Difficulty.apply_enemy_count_modifier(units, 4, rng)
	assert_eq(units.size(), 11, "D4 10기 편성 → 10% floor로 1기 추가")


func test_apply_enemy_count_modifier_does_not_round_up_tiny_armies() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var units := [{
		"atk": 10.0, "hp": 100.0, "attack_speed": 1.0,
		"range": 1, "move_speed": 2, "mechanics": [],
	}]
	Difficulty.apply_enemy_count_modifier(units, 4, rng)
	assert_eq(units.size(), 1, "D4 1기 편성은 억지로 2기가 되지 않음")


func test_boss_upgrade_rarities_follow_actual_boss_rounds() -> void:
	assert_eq(Difficulty.get_boss_upgrade_rarities(3, 8).size(), 0,
		"비보스 라운드는 업그레이드 없음")
	assert_eq(Difficulty.get_boss_upgrade_rarities(4, 5), [Enums.UpgradeRarity.COMMON],
		"D5 보스 커먼")
	assert_eq(Difficulty.get_boss_upgrade_rarities(8, 7), [
		Enums.UpgradeRarity.COMMON,
	], "D7 R8 보스 커먼만")
	assert_eq(Difficulty.get_boss_upgrade_rarities(12, 7), [
		Enums.UpgradeRarity.COMMON,
		Enums.UpgradeRarity.RARE,
	], "D7 R12 보스 커먼+레어")
	assert_eq(Difficulty.get_boss_upgrade_rarities(15, 7), [
		Enums.UpgradeRarity.COMMON,
		Enums.UpgradeRarity.EPIC,
	], "D7 R15 보스 커먼+에픽")


func test_boss_upgrades_are_marked_on_enemy_units() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var units := [{
		"atk": 10.0, "hp": 100.0, "attack_speed": 1.0,
		"range": 1, "move_speed": 2, "mechanics": [],
	}]
	Difficulty.apply_enemy_modifiers(units, 4, rng, 5)
	assert_true(units[0].has("enemy_upgrades"), "보스 업그레이드 ID 기록")
	assert_eq((units[0]["enemy_upgrades"] as Array).size(), 1, "D5 보스 커먼 1개")
