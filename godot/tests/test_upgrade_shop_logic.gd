extends GutTest
## Upgrade Shop 순수 로직 테스트 (UI 우회)
## 참조: upgrade_shop.gd
##
## 레어리티 분포 / 리롤 비용 / 슬롯 관리 / 가용성 게이팅 검증.


const UpShopScript = preload("res://scripts/build/upgrade_shop.gd")

var _shop = null
var _state: GameState = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_shop = UpShopScript.new()
	_state = GameState.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42
	# UI 생성 우회: 내부 상태 직접 주입
	_shop._game_state = _state
	_shop._rng = _rng


func after_each() -> void:
	if _shop != null:
		_shop.free()


# ================================================================
# _roll_rarity 분포 (70% Common / 30% Rare)
# ================================================================

func test_roll_rarity_returns_common_or_rare() -> void:
	for _i in 100:
		var r: int = _shop._roll_rarity()
		assert_true(r == Enums.UpgradeRarity.COMMON or r == Enums.UpgradeRarity.RARE,
			"COMMON 또는 RARE만")


func test_roll_rarity_distribution_roughly_70_30() -> void:
	var common_count: int = 0
	for _i in 1000:
		if _shop._roll_rarity() == Enums.UpgradeRarity.COMMON:
			common_count += 1
	# 70% ± 5% tolerance
	assert_gt(common_count, 600, "Common > 60%")
	assert_lt(common_count, 800, "Common < 80%")


func test_roll_rarity_never_epic() -> void:
	for _i in 500:
		assert_ne(_shop._roll_rarity(), Enums.UpgradeRarity.EPIC, "에픽은 상점 출현 불가")


# ================================================================
# _pick_upgrade
# ================================================================

func test_pick_upgrade_common_returns_common_id() -> void:
	var uid: String = _shop._pick_upgrade(Enums.UpgradeRarity.COMMON)
	assert_ne(uid, "", "비어있지 않음")
	var upg: Dictionary = UpgradeDB.get_upgrade(uid)
	assert_eq(upg.get("rarity", -1), Enums.UpgradeRarity.COMMON, "커먼 레어리티")


func test_pick_upgrade_rare_returns_rare_id() -> void:
	var uid: String = _shop._pick_upgrade(Enums.UpgradeRarity.RARE)
	assert_ne(uid, "", "비어있지 않음")
	var upg: Dictionary = UpgradeDB.get_upgrade(uid)
	assert_eq(upg.get("rarity", -1), Enums.UpgradeRarity.RARE, "레어 레어리티")


# ================================================================
# refresh_upgrades
# ================================================================

func test_refresh_fills_2_slots() -> void:
	_shop.refresh_upgrades()
	assert_eq(_shop._offered_ids.size(), Enums.UPGRADE_SHOP_SLOTS, "슬롯 수 = UPGRADE_SHOP_SLOTS")
	for uid in _shop._offered_ids:
		assert_ne(uid, "", "모든 슬롯 채워짐")


# ================================================================
# reroll_upgrades
# ================================================================

func test_reroll_costs_1_terazin() -> void:
	_state.terazin = 5
	_shop._offered_ids.assign(["C1", "C2"])
	var result: bool = _shop.reroll_upgrades()
	assert_true(result, "리롤 성공")
	assert_eq(_state.terazin, 4, "1테라진 차감")


func test_reroll_fails_if_no_terazin() -> void:
	_state.terazin = 0
	var result: bool = _shop.reroll_upgrades()
	assert_false(result, "테라진 부족 → 실패")
	assert_eq(_state.terazin, 0, "테라진 불변")


func test_reroll_refreshes_slots() -> void:
	_state.terazin = 5
	_state.round_num = 5
	_shop._offered_ids.assign(["", ""])
	_shop.reroll_upgrades()
	for uid in _shop._offered_ids:
		assert_ne(uid, "", "리롤 후 모든 슬롯 채워짐")


# ================================================================
# is_available (라운드 게이팅)
# ================================================================

func test_available_false_round_1() -> void:
	_state.round_num = 1
	assert_false(_shop.is_available(), "R1 → 불가")


func test_available_false_round_2() -> void:
	_state.round_num = 2
	assert_false(_shop.is_available(), "R2 → 불가")


func test_available_true_round_3() -> void:
	_state.round_num = 3
	assert_true(_shop.is_available(), "R3 → 가용")


func test_available_true_round_10() -> void:
	_state.round_num = 10
	assert_true(_shop.is_available(), "R10 → 가용")


# ================================================================
# get_upgrade_cost
# ================================================================

func test_get_cost_valid_slot() -> void:
	_shop.refresh_upgrades()
	var cost: int = _shop.get_upgrade_cost(0)
	assert_gt(cost, 0, "유효 슬롯 → 비용 > 0")


func test_get_cost_empty_slot_returns_0() -> void:
	_shop._offered_ids.assign(["", "C1"])
	assert_eq(_shop.get_upgrade_cost(0), 0, "빈 슬롯 → 0")


func test_get_cost_invalid_idx_returns_0() -> void:
	_shop._offered_ids.assign(["C1", "C2"])
	assert_eq(_shop.get_upgrade_cost(-1), 0, "음수 인덱스 → 0")
	assert_eq(_shop.get_upgrade_cost(99), 0, "범위 초과 → 0")


# ================================================================
# mark_sold
# ================================================================

func test_mark_sold_clears_slot() -> void:
	_shop._offered_ids.assign(["C1", "C2"])
	_shop.mark_sold(0)
	assert_eq(_shop._offered_ids[0], "", "슬롯 0 비워짐")
	assert_eq(_shop._offered_ids[1], "C2", "슬롯 1 유지")


func test_mark_sold_invalid_idx_no_crash() -> void:
	_shop._offered_ids.assign(["C1", "C2"])
	_shop.mark_sold(-1)  # 크래시 없어야 함
	_shop.mark_sold(99)  # 크래시 없어야 함
	assert_eq(_shop._offered_ids[0], "C1", "유효 슬롯 불변")
