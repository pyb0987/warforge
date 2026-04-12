extends GutTest
## CardDB 데이터 정합성 테스트
## 참조: docs/design/cards-*.md, DESIGN.md
##
## 54장 기본 카드(★1)와 star_overrides 기반 ★2/★3가 설계 기준대로 등록됐는지 검증.
## composition의 unit_id가 UnitDB에 실제 존재하는지 교차 검증.


# ================================================================
# 등록 수
# ================================================================

func test_total_card_count_55() -> void:
	## 기본 카드 = 55장 (스팀10 + 중립15 + 드루10 + 포식10 + 군대10).
	## 중립 15장: ne_scrapyard(폐품 상회, 2026-04-09 추가) 포함.
	assert_eq(CardDB.get_all_ids().size(), 55, "기본 카드 55장")


func test_steampunk_base_count() -> void:
	var ids := CardDB.get_ids_by_theme(Enums.CardTheme.STEAMPUNK)
	assert_eq(ids.size(), 10, "스팀펑크 기본 10장")


func test_neutral_base_count() -> void:
	var ids := CardDB.get_ids_by_theme(Enums.CardTheme.NEUTRAL)
	assert_eq(ids.size(), 15, "중립 기본 15장 (폐품 상회 포함)")


func test_druid_base_count() -> void:
	var ids := CardDB.get_ids_by_theme(Enums.CardTheme.DRUID)
	assert_eq(ids.size(), 10, "드루이드 기본 10장")


func test_predator_base_count() -> void:
	var ids := CardDB.get_ids_by_theme(Enums.CardTheme.PREDATOR)
	assert_eq(ids.size(), 10, "포식종 기본 10장")


func test_military_base_count() -> void:
	var ids := CardDB.get_ids_by_theme(Enums.CardTheme.MILITARY)
	assert_eq(ids.size(), 10, "군대 기본 10장")


# ================================================================
# 필수 필드 전수 검사
# ================================================================

func test_all_cards_have_required_fields() -> void:
	var required := ["id", "name", "tier", "theme", "composition",
		"trigger_timing", "max_activations", "effects", "cost", "card_tags"]
	for cid in CardDB.get_all_ids():
		var t: Dictionary = CardDB.get_template(cid)
		for field in required:
			assert_true(t.has(field), "카드 %s: '%s' 필드 누락" % [cid, field])


func test_all_card_ids_match_key() -> void:
	for cid in CardDB.get_all_ids():
		var t: Dictionary = CardDB.get_template(cid)
		assert_eq(t["id"], cid, "id 필드 = 키: %s" % cid)


func test_all_cards_have_nonempty_name() -> void:
	for cid in CardDB.get_all_ids():
		var t: Dictionary = CardDB.get_template(cid)
		assert_true(t["name"].length() > 0, "이름 비어있음: %s" % cid)


func test_all_cards_have_nonempty_composition() -> void:
	## PERSISTENT 카드도 최소 1개 유닛 구성
	for cid in CardDB.get_all_ids():
		var t: Dictionary = CardDB.get_template(cid)
		assert_true(t["composition"].size() > 0, "composition 비어있음: %s" % cid)


func test_all_cards_effects_is_array() -> void:
	for cid in CardDB.get_all_ids():
		var t: Dictionary = CardDB.get_template(cid)
		assert_true(t["effects"] is Array, "effects가 Array 아님: %s" % cid)


# ================================================================
# composition → UnitDB 교차 검증
# ================================================================

func test_all_composition_unit_ids_exist_in_unit_db() -> void:
	## 가장 중요한 정합성 체크: 카드가 참조하는 유닛이 실제 존재해야 함
	for cid in CardDB.get_all_ids():
		var t: Dictionary = CardDB.get_template(cid)
		for comp in t["composition"]:
			var uid: String = comp["unit_id"]
			var unit: Dictionary = UnitDB.get_unit(uid)
			assert_false(unit.is_empty(),
				"카드 %s → unit_id '%s' UnitDB에 없음" % [cid, uid])


func test_all_composition_counts_positive() -> void:
	for cid in CardDB.get_all_ids():
		var t: Dictionary = CardDB.get_template(cid)
		for comp in t["composition"]:
			assert_true(comp["count"] > 0,
				"카드 %s: count <= 0 (unit: %s)" % [cid, comp["unit_id"]])


# ================================================================
# 티어·비용
# ================================================================

func test_tier_cost_mapping() -> void:
	## 설계: T1=2, T2=3, T3=4, T4=5, T5=6
	var expected_cost := {1: 2, 2: 3, 3: 4, 4: 5, 5: 6}
	for cid in CardDB.get_all_ids():
		var t: Dictionary = CardDB.get_template(cid)
		var tier: int = t["tier"]
		var cost: int = t["cost"]
		assert_eq(cost, expected_cost[tier],
			"카드 %s: T%d 비용 %d (기대 %d)" % [cid, tier, cost, expected_cost[tier]])


func test_all_base_cards_tier_in_range() -> void:
	## 기본 카드는 T1~T5
	for cid in CardDB.get_all_ids():
		var t: Dictionary = CardDB.get_template(cid)
		var tier: int = t["tier"]
		assert_true(tier >= 1 and tier <= 5,
			"카드 %s: 티어 %d는 1~5 범위 외" % [cid, tier])


# ================================================================
# max_activations
# ================================================================

func test_all_cards_max_activations_valid() -> void:
	## -1(무제한) 또는 양수여야 함. 0이면 영구 비활성 = 버그.
	for cid in CardDB.get_all_ids():
		var t: Dictionary = CardDB.get_template(cid)
		var ma: int = t["max_activations"]
		assert_true(ma == -1 or ma > 0,
			"카드 %s: max_activations=%d (0 또는 음수 금지)" % [cid, ma])


# ================================================================
# trigger_timing
# ================================================================

func test_all_cards_trigger_timing_valid_enum() -> void:
	## TriggerTiming 최댓값: PERSISTENT(11) — ON_COMBAT_DEATH(10) 추가로 밀림
	var max_timing := Enums.TriggerTiming.PERSISTENT
	for cid in CardDB.get_all_ids():
		var t: Dictionary = CardDB.get_template(cid)
		var timing: int = t["trigger_timing"]
		assert_true(timing >= 0 and timing <= max_timing,
			"카드 %s: trigger_timing=%d 범위 외" % [cid, timing])


# ================================================================
# get_star_template API
# ================================================================

func test_get_star_template_star1_returns_base() -> void:
	## star_level=1이면 기본 템플릿과 동일
	var base: Dictionary = CardDB.get_template("sp_warmachine")
	var star1: Dictionary = CardDB.get_star_template("sp_warmachine", 1)
	assert_eq(star1["name"], base["name"], "★1은 기본 템플릿")


func test_get_star_template_star2_returns_override() -> void:
	var star2: Dictionary = CardDB.get_star_template("sp_warmachine", 2)
	assert_eq(star2["name"], "전쟁 기계 ★2", "★2 이름 오버라이드")


func test_get_star_template_star3_returns_override() -> void:
	var star3: Dictionary = CardDB.get_star_template("sp_warmachine", 3)
	assert_eq(star3["name"], "전쟁 기계 ★3", "★3 이름 오버라이드")


func test_get_star_template_always_has_star_name() -> void:
	## 모든 카드는 star_overrides에 ★N 이름 포함
	var star2: Dictionary = CardDB.get_star_template("dr_cradle", 2)
	assert_eq(star2["name"], "숲의 요람 ★2", "★2 이름 오버라이드")


func test_get_star_template_unknown_returns_empty() -> void:
	var result: Dictionary = CardDB.get_star_template("nonexistent", 2)
	assert_true(result.is_empty(), "미등록 카드는 빈 딕셔너리")


func test_star_override_preserves_base_fields() -> void:
	## tier, theme, cost는 ★ 레벨과 무관하게 동일
	var base: Dictionary = CardDB.get_template("sp_warmachine")
	var star2: Dictionary = CardDB.get_star_template("sp_warmachine", 2)
	var star3: Dictionary = CardDB.get_star_template("sp_warmachine", 3)
	assert_eq(star2["tier"], base["tier"], "★2 tier 보존")
	assert_eq(star2["theme"], base["theme"], "★2 theme 보존")
	assert_eq(star2["cost"], base["cost"], "★2 cost 보존")
	assert_eq(star3["tier"], base["tier"], "★3 tier 보존")
	assert_eq(star3["theme"], base["theme"], "★3 theme 보존")
	assert_eq(star3["cost"], base["cost"], "★3 cost 보존")


func test_star_override_has_required_fields() -> void:
	## star_overrides 전수 검사
	var star_cards := [
		"sp_assembly", "sp_furnace", "sp_workshop", "sp_circulator",
		"sp_interest", "sp_line", "sp_barrier",
		"sp_warmachine", "sp_charger", "sp_arsenal",
		"ne_earth_echo", "ne_wild_pulse", "ne_ruin_resonance",
		"ne_wanderers", "ne_mutant_adapt",
		"ne_mana_crystal", "ne_ancient_catalyst",
		"ne_wildforce", "ne_chimera_cry", "ne_ruins",
		"ne_merchant", "ne_scrapyard",
		"ne_spirit_blessing", "ne_dim_merchant", "ne_awakening",
		"dr_wrath", "dr_wt_root", "dr_world",
		"pr_parasite", "pr_apex_hunt", "pr_transcend",
		"ml_special_ops", "ml_factory", "ml_command",
	]
	var required := ["name", "composition", "trigger_timing",
		"max_activations", "effects", "card_tags"]
	for base_id in star_cards:
		for star in [2, 3]:
			var t: Dictionary = CardDB.get_star_template(base_id, star)
			assert_false(t.is_empty(),
				"%s ★%d 템플릿 존재" % [base_id, star])
			for field in required:
				assert_true(t.has(field),
					"%s ★%d: '%s' 필드 누락" % [base_id, star, field])


func test_star_override_composition_units_exist() -> void:
	## star_overrides의 composition도 UnitDB 교차 검증
	var star_cards := [
		"sp_assembly", "sp_furnace", "sp_workshop", "sp_circulator",
		"sp_interest", "sp_line", "sp_barrier",
		"sp_warmachine", "sp_charger", "sp_arsenal",
		"ne_earth_echo", "ne_wild_pulse", "ne_ruin_resonance",
		"ne_wanderers", "ne_mutant_adapt",
		"ne_mana_crystal", "ne_ancient_catalyst",
		"ne_wildforce", "ne_chimera_cry", "ne_ruins",
		"ne_merchant", "ne_scrapyard",
		"ne_spirit_blessing", "ne_dim_merchant", "ne_awakening",
		"dr_wrath", "dr_wt_root", "dr_world",
		"pr_parasite", "pr_apex_hunt", "pr_transcend",
		"ml_special_ops", "ml_factory", "ml_command",
	]
	for base_id in star_cards:
		for star in [2, 3]:
			var t: Dictionary = CardDB.get_star_template(base_id, star)
			for comp in t.get("composition", []):
				var uid: String = comp["unit_id"]
				assert_false(UnitDB.get_unit(uid).is_empty(),
					"%s ★%d → unit '%s' UnitDB에 없음" % [base_id, star, uid])


func test_get_all_ids_no_star_suffixes() -> void:
	## get_all_ids()에 _s2/_s3 접미사 없음
	for cid in CardDB.get_all_ids():
		assert_false(cid.ends_with("_s2"), "_s2 없어야 함: %s" % cid)
		assert_false(cid.ends_with("_s3"), "_s3 없어야 함: %s" % cid)


# ================================================================
# 조회 API
# ================================================================

func test_get_template_unknown_returns_empty() -> void:
	var t: Dictionary = CardDB.get_template("nonexistent_card")
	assert_true(t.is_empty(), "존재하지 않는 ID는 빈 딕셔너리")


func test_get_ids_by_theme_excludes_other_themes() -> void:
	## 스팀펑크 조회에 드루이드 카드가 섞이면 안 됨
	var sp_ids := CardDB.get_ids_by_theme(Enums.CardTheme.STEAMPUNK)
	for cid in sp_ids:
		assert_false(cid.begins_with("dr_"), "스팀펑크 조회에 드루이드 카드 포함: %s" % cid)
		assert_false(cid.begins_with("pr_"), "스팀펑크 조회에 포식종 카드 포함: %s" % cid)


# ================================================================
# 대표 카드 수치 스냅샷 (설계문서 직접 대조)
# ================================================================

func test_sp_assembly_template() -> void:
	var t: Dictionary = CardDB.get_template("sp_assembly")
	assert_eq(t["name"], "증기 조립소")
	assert_eq(t["tier"], 1)
	assert_eq(t["cost"], 2)
	assert_eq(t["theme"], Enums.CardTheme.STEAMPUNK)
	assert_eq(t["trigger_timing"], Enums.TriggerTiming.ROUND_START)


func test_sp_assembly_composition() -> void:
	var t: Dictionary = CardDB.get_template("sp_assembly")
	## sp_spider×2 + sp_rat×1
	assert_eq(t["composition"].size(), 2)
	assert_eq(t["composition"][0]["unit_id"], "sp_spider")
	assert_eq(t["composition"][0]["count"], 2)
	assert_eq(t["composition"][1]["unit_id"], "sp_rat")
	assert_eq(t["composition"][1]["count"], 1)


func test_sp_workshop_listens_on_event() -> void:
	var t: Dictionary = CardDB.get_template("sp_workshop")
	assert_eq(t["trigger_timing"], Enums.TriggerTiming.ON_EVENT)
	assert_eq(t["max_activations"], 2)


func test_sp_warmachine_is_persistent() -> void:
	var t: Dictionary = CardDB.get_template("sp_warmachine")
	assert_eq(t["trigger_timing"], Enums.TriggerTiming.PERSISTENT)
	assert_eq(t["effects"].size(), 0, "PERSISTENT 효과는 테마 시스템에서 처리")
