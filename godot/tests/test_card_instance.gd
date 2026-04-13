extends GutTest
## CardInstance 동작 테스트
## 참조: card_instance.gd, handoff.md P1
##
## 생성 / 3-레이어 스탯 / 유닛 관리 / 활성화 제한 / 진화를 검증.


# ================================================================
# 생성
# ================================================================

func test_create_valid_id_returns_non_null() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	assert_not_null(card, "유효 ID → non-null")


func test_create_invalid_id_returns_null() -> void:
	var card: CardInstance = CardInstance.create("nonexistent_card_xyz")
	assert_null(card, "존재하지 않는 ID → null")
	assert_push_error_count(1, "push_error 1회 발생")


func test_initial_star_level_1() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	assert_eq(card.star_level, 1, "초기 ★1")


func test_initial_upgrades_empty() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	assert_eq(card.upgrades.size(), 0, "초기 업그레이드 없음")


func test_initial_tenure_0() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	assert_eq(card.tenure, 0, "초기 tenure=0")


# ================================================================
# Layer1: enhance (growth)
# ================================================================

func test_enhance_null_increases_atk_pct() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	var base: float = card.get_total_atk()
	card.enhance(null, 0.10, 0.0)
	assert_almost_eq(card.get_total_atk(), base * 1.10, 0.01, "enhance(null,0.10) → ATK ×1.10")


func test_enhance_hp_pct() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	var base: float = card.get_total_hp()
	card.enhance(null, 0.0, 0.10)
	assert_almost_eq(card.get_total_hp(), base * 1.10, 0.01, "enhance hp ×1.10")


func test_enhance_tag_gear_affects_only_gear_units() -> void:
	## sp_assembly: spider(gear)×2, rat(steam)×1
	var card: CardInstance = CardInstance.create("sp_assembly")
	var base: float = card.get_total_atk()
	card.enhance("gear", 0.20, 0.0)
	var after: float = card.get_total_atk()
	# gear 유닛만 영향 → 전체보다 작지만 base보다 큼
	assert_gt(after, base, "gear enhance → ATK 증가")
	assert_lt(after, base * 1.20, "gear만 적용 → 전체 ×1.20 미만")


func test_enhance_unknown_tag_no_effect() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	var base: float = card.get_total_atk()
	card.enhance("nonexistent", 0.50, 0.0)
	assert_almost_eq(card.get_total_atk(), base, 0.01, "없는 태그 → 변화 없음")


# ================================================================
# Layer2: multiply_stats
# ================================================================

func test_multiply_stats_atk() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	var base: float = card.get_total_atk()
	card.multiply_stats(0.30, 0.0)
	assert_almost_eq(card.get_total_atk(), base * 1.30, 0.01, "multiply ×1.30")


func test_multiply_stats_stacks_multiplicatively() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	var base: float = card.get_total_atk()
	card.multiply_stats(0.30, 0.0)
	card.multiply_stats(0.30, 0.0)
	assert_almost_eq(card.get_total_atk(), base * 1.69, 0.01, "×1.30 × ×1.30 = ×1.69")


func test_three_layer_combined() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	var base: float = card.get_total_atk()
	card.enhance(null, 0.10, 0.0)
	card.multiply_stats(0.30, 0.0)
	assert_almost_eq(card.get_total_atk(), base * 1.10 * 1.30, 0.01, "L1+L2 = ×1.10×1.30")


# ================================================================
# 유닛 관리
# ================================================================

func test_get_total_units_initial_3() -> void:
	## sp_assembly: spider×2 + rat×1 = 3
	var card: CardInstance = CardInstance.create("sp_assembly")
	assert_eq(card.get_total_units(), 3, "초기 3기")


func test_spawn_random_increases_by_1() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	card.spawn_random(rng)
	assert_eq(card.get_total_units(), 4, "spawn 후 4기")


func test_spawn_random_respects_60_cap() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# 3기 → 60기까지 57번 spawn
	for i in 57:
		card.spawn_random(rng)
	assert_eq(card.get_total_units(), 60, "60기 도달")
	var result: bool = card.spawn_random(rng)
	assert_false(result, "60기 초과 시 false")
	assert_eq(card.get_total_units(), 60, "60기 유지")


func test_add_specific_unit_creates_new_stack() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	var before: int = card.stacks.size()
	card.add_specific_unit("sp_titan", 1)
	assert_eq(card.stacks.size(), before + 1, "새 스택 생성")


func test_add_specific_unit_existing_stack() -> void:
	## sp_spider는 이미 sp_assembly에 존재
	var card: CardInstance = CardInstance.create("sp_assembly")
	var before: int = card.get_total_units()
	card.add_specific_unit("sp_spider", 2)
	assert_eq(card.get_total_units(), before + 2, "기존 스택 count +2")


func test_breed_strongest_picks_highest_cp_unit() -> void:
	## sp_spider CP=2/0.5×20=80, sp_rat CP=2/0.5×15=60
	var card: CardInstance = CardInstance.create("sp_assembly")
	# spider 초기 2기
	var spider_before := 0
	for s in card.stacks:
		if s["unit_type"]["id"] == "sp_spider":
			spider_before = s["count"]
	card.breed_strongest()
	var spider_after := 0
	for s in card.stacks:
		if s["unit_type"]["id"] == "sp_spider":
			spider_after = s["count"]
	assert_eq(spider_after, spider_before + 1, "최강 CP 유닛(spider) +1")


func test_metamorphosis_reduces_units_correctly() -> void:
	## 초기 3기, metamorphosis(2) → 2기 소비 + 최강 1기 추가
	var card: CardInstance = CardInstance.create("sp_assembly")
	assert_eq(card.get_total_units(), 3, "전: 3기")
	var result: bool = card.metamorphosis(2)
	assert_true(result, "성공")
	assert_eq(card.get_total_units(), 2, "후: 3-2+1=2기")


func test_metamorphosis_fails_if_not_enough() -> void:
	## 3기에서 metamorphosis(3) → 3소비+1생존=4 필요, 현재 3 → 부족
	var card: CardInstance = CardInstance.create("sp_assembly")
	var result: bool = card.metamorphosis(3)
	assert_false(result, "유닛 부족 시 false")
	assert_eq(card.get_total_units(), 3, "변화 없음")


# ================================================================
# remove_weakest (폐품 상회 등)
# ================================================================

func test_remove_weakest_removes_lowest_cp_first() -> void:
	## sp_assembly: spider×2 (ATK2), rat×1 (ATK1) — rat이 최약
	var card: CardInstance = CardInstance.create("sp_assembly")
	var before: int = card.get_total_units()
	var removed: int = card.remove_weakest(1)
	assert_eq(removed, 1, "1기 제거")
	assert_eq(card.get_total_units(), before - 1, "총 유닛 -1")


func test_remove_weakest_zero_count_noop() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	var before: int = card.get_total_units()
	var removed: int = card.remove_weakest(0)
	assert_eq(removed, 0, "0 → noop")
	assert_eq(card.get_total_units(), before, "변화 없음")


func test_remove_weakest_more_than_total_caps() -> void:
	## 3기에서 10기 제거 요청 → 실제 3기만 제거됨
	var card: CardInstance = CardInstance.create("sp_assembly")
	var removed: int = card.remove_weakest(10)
	assert_eq(removed, 3, "최대 보유 수까지만")
	assert_eq(card.get_total_units(), 0, "0기로 비워짐")


func test_remove_weakest_empty_card_returns_zero() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	card.remove_weakest(99)  # 비우기
	var removed: int = card.remove_weakest(1)
	assert_eq(removed, 0, "빈 카드 → 0")


# ================================================================
# 활성화 제한
# ================================================================

func test_can_activate_unlimited() -> void:
	## sp_assembly max_activations=-1 → 항상 true
	var card: CardInstance = CardInstance.create("sp_assembly")
	assert_true(card.can_activate(), "unlimited → true")
	card.activations_used = 100
	assert_true(card.can_activate(), "100회 후에도 true")


func test_can_activate_limited_sp_workshop() -> void:
	## sp_workshop max_activations=2
	var card: CardInstance = CardInstance.create("sp_workshop")
	assert_true(card.can_activate(), "0/2 → true")
	card.activations_used = 1
	assert_true(card.can_activate(), "1/2 → true")
	card.activations_used = 2
	assert_false(card.can_activate(), "2/2 → false")


func test_reset_round_clears_activations() -> void:
	var card: CardInstance = CardInstance.create("sp_workshop")
	card.activations_used = 2
	card.reset_round()
	assert_eq(card.activations_used, 0, "reset 후 0")


func test_tenure_increments_on_reset() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	assert_eq(card.tenure, 0, "초기 0")
	card.reset_round()
	assert_eq(card.tenure, 1, "reset 후 1")
	card.reset_round()
	assert_eq(card.tenure, 2, "두 번째 reset 후 2")


# ================================================================
# 진화
# ================================================================

func test_evolve_star_increments() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	card.evolve_star()
	assert_eq(card.star_level, 2, "★1→★2")
	card.evolve_star()
	assert_eq(card.star_level, 3, "★2→★3")


func test_evolve_star_capped_at_3() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	card.evolve_star()
	card.evolve_star()
	card.evolve_star()
	card.evolve_star()
	assert_eq(card.star_level, 3, "4번 호출해도 ★3")


func test_evolve_star_template_id_stays_base() -> void:
	var card: CardInstance = CardInstance.create("sp_warmachine")
	card.evolve_star()
	assert_eq(card.template_id, "sp_warmachine", "evolve 후 template_id 불변")
	card.evolve_star()
	assert_eq(card.template_id, "sp_warmachine", "★3에서도 template_id 불변")


func test_evolve_star_swaps_to_star2_template() -> void:
	var card: CardInstance = CardInstance.create("sp_warmachine")
	card.evolve_star()
	assert_eq(card.template["name"], "전쟁 기계 ★2", "★2 이름 반영")


func test_evolve_star_swaps_to_star3_template() -> void:
	var card: CardInstance = CardInstance.create("sp_warmachine")
	card.evolve_star()
	card.evolve_star()
	assert_eq(card.template["name"], "전쟁 기계 ★3", "★3 이름 반영")


func test_get_base_id_equals_template_id() -> void:
	var card: CardInstance = CardInstance.create("sp_warmachine")
	card.evolve_star()
	assert_eq(card.get_base_id(), card.template_id, "get_base_id == template_id")


# ================================================================
# roll_bonus_count (정적 유틸리티)
# ================================================================

func test_roll_bonus_count_zero_chance_returns_0() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	assert_eq(CardInstance.roll_bonus_count(5, 0.0, rng), 0, "확률 0 → 보너스 0")


func test_roll_bonus_count_zero_added_returns_0() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	assert_eq(CardInstance.roll_bonus_count(0, 0.5, rng), 0, "추가 0 → 보너스 0")


func test_roll_bonus_count_null_rng_returns_0() -> void:
	assert_eq(CardInstance.roll_bonus_count(5, 0.5, null), 0, "rng null → 보너스 0")


func test_roll_bonus_count_full_chance_returns_all() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	assert_eq(CardInstance.roll_bonus_count(7, 1.0, rng), 7, "확률 100% → 전부 보너스")


func test_roll_bonus_count_distribution_reasonable() -> void:
	## 50% 확률, 100회 × 10개 = 1000롤 → 400~600 범위
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var total := 0
	for _i in 100:
		total += CardInstance.roll_bonus_count(10, 0.5, rng)
	assert_gt(total, 350, "50% 확률 1000롤 → 350 초과")
	assert_lt(total, 650, "50% 확률 1000롤 → 650 미만")
