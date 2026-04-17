extends GutTest
## UnitDB 데이터 정합성 테스트
## 참조: docs/design/units-*.md
##
## 50종 base 유닛 + N종 enhanced variant이 설계 기준에 맞게 등록되었는지 검증.
## 필수 필드 누락, 음수 스탯, 잘못된 태그는 여기서 잡힌다.
## enhanced 유닛은 `enhanced` 태그로 식별하며 base count에서 제외.


# --- 등록 수 ---
# 설계 불변식: base 50종 (테마당 10종). enhanced variant은 base의 강화형이지
# 별도 유닛 슬롯이 아니므로 base count에서 제외해 집계한다.

func _count_base_units(uids: Array) -> int:
	var n := 0
	for uid in uids:
		var tags: PackedStringArray = UnitDB.get_unit(uid)["tags"]
		if not ("enhanced" in tags):
			n += 1
	return n


func test_total_base_unit_count() -> void:
	assert_eq(_count_base_units(UnitDB.get_all_ids()), 50,
			"총 base 유닛 50종 (enhanced variant 제외)")


func test_steampunk_unit_count() -> void:
	assert_eq(_count_base_units(UnitDB.get_ids_by_theme("steampunk")), 10,
			"스팀펑크 base 유닛 10종")


func test_neutral_unit_count() -> void:
	assert_eq(_count_base_units(UnitDB.get_ids_by_theme("neutral")), 10,
			"중립 base 유닛 10종")


func test_druid_unit_count() -> void:
	assert_eq(_count_base_units(UnitDB.get_ids_by_theme("druid")), 10,
			"드루이드 base 유닛 10종")


func test_predator_unit_count() -> void:
	assert_eq(_count_base_units(UnitDB.get_ids_by_theme("predator")), 10,
			"포식종 base 유닛 10종")


func test_military_unit_count() -> void:
	assert_eq(_count_base_units(UnitDB.get_ids_by_theme("military")), 10,
			"군대 base 유닛 10종 (ml_*_enhanced 제외)")


func test_military_enhanced_variant_count() -> void:
	## Enhanced variant은 base와 짝을 이룸. trace 012에서 6종 도입.
	var mil := UnitDB.get_ids_by_theme("military")
	var enhanced := 0
	for uid in mil:
		var tags: PackedStringArray = UnitDB.get_unit(uid)["tags"]
		if "enhanced" in tags:
			enhanced += 1
	assert_eq(enhanced, 6, "군대 enhanced variant 6종")


func test_get_ids_by_theme_unknown_returns_empty() -> void:
	assert_eq(UnitDB.get_ids_by_theme("nonexistent").size(), 0, "없는 테마 → 빈 배열")


func test_get_ids_by_theme_results_have_correct_tag() -> void:
	for uid in UnitDB.get_ids_by_theme("steampunk"):
		var u: Dictionary = UnitDB.get_unit(uid)
		assert_true("steampunk" in u["tags"], "%s에 steampunk 태그" % uid)


# --- 필수 필드 전수 검사 ---

func test_all_units_have_required_fields() -> void:
	var required := ["id", "name", "atk", "hp", "attack_speed", "range", "move_speed", "tags"]
	for uid in UnitDB.get_all_ids():
		var u: Dictionary = UnitDB.get_unit(uid)
		for field in required:
			assert_true(u.has(field), "유닛 %s: '%s' 필드 누락" % [uid, field])


func test_all_unit_ids_match_key() -> void:
	## id 필드가 딕셔너리 키와 일치하는지 확인
	for uid in UnitDB.get_all_ids():
		var u: Dictionary = UnitDB.get_unit(uid)
		assert_eq(u["id"], uid, "id 필드 = 키: %s" % uid)


func test_all_units_have_nonempty_name() -> void:
	for uid in UnitDB.get_all_ids():
		var u: Dictionary = UnitDB.get_unit(uid)
		assert_true(u["name"].length() > 0, "이름 비어있음: %s" % uid)


# --- 스탯 유효성 ---

func test_all_units_atk_positive() -> void:
	for uid in UnitDB.get_all_ids():
		var u: Dictionary = UnitDB.get_unit(uid)
		assert_true(u["atk"] > 0, "ATK > 0: %s" % uid)


func test_all_units_hp_positive() -> void:
	for uid in UnitDB.get_all_ids():
		var u: Dictionary = UnitDB.get_unit(uid)
		assert_true(u["hp"] > 0, "HP > 0: %s" % uid)


func test_all_units_attack_speed_positive() -> void:
	for uid in UnitDB.get_all_ids():
		var u: Dictionary = UnitDB.get_unit(uid)
		assert_true(u["attack_speed"] > 0.0, "AS > 0: %s" % uid)


func test_all_units_range_nonnegative() -> void:
	for uid in UnitDB.get_all_ids():
		var u: Dictionary = UnitDB.get_unit(uid)
		assert_true(u["range"] >= 0, "Range >= 0: %s" % uid)


func test_all_units_move_speed_nonnegative() -> void:
	for uid in UnitDB.get_all_ids():
		var u: Dictionary = UnitDB.get_unit(uid)
		assert_true(u["move_speed"] >= 0, "MS >= 0: %s" % uid)


func test_all_units_atk_within_design_ceiling() -> void:
	## 설계 상한: ATK ≤ 20
	for uid in UnitDB.get_all_ids():
		var u: Dictionary = UnitDB.get_unit(uid)
		assert_true(u["atk"] <= 20, "ATK ≤ 20: %s (실제: %d)" % [uid, u["atk"]])


# --- 태그 검사 ---

func test_all_units_have_nonempty_tags() -> void:
	for uid in UnitDB.get_all_ids():
		var u: Dictionary = UnitDB.get_unit(uid)
		var tags: PackedStringArray = u["tags"]
		assert_true(tags.size() > 0, "태그 비어있음: %s" % uid)


func test_steampunk_units_have_steampunk_tag() -> void:
	for uid in UnitDB.get_all_ids():
		if not uid.begins_with("sp_"):
			continue
		var u: Dictionary = UnitDB.get_unit(uid)
		var tags: PackedStringArray = u["tags"]
		assert_true("steampunk" in tags, "sp_ 유닛에 steampunk 태그 없음: %s" % uid)


func test_druid_units_have_druid_tag() -> void:
	for uid in UnitDB.get_all_ids():
		if not uid.begins_with("dr_"):
			continue
		var u: Dictionary = UnitDB.get_unit(uid)
		var tags: PackedStringArray = u["tags"]
		assert_true("druid" in tags, "dr_ 유닛에 druid 태그 없음: %s" % uid)


func test_predator_units_have_predator_tag() -> void:
	for uid in UnitDB.get_all_ids():
		if not uid.begins_with("pr_"):
			continue
		var u: Dictionary = UnitDB.get_unit(uid)
		var tags: PackedStringArray = u["tags"]
		assert_true("predator" in tags, "pr_ 유닛에 predator 태그 없음: %s" % uid)


func test_military_units_have_military_tag() -> void:
	for uid in UnitDB.get_all_ids():
		if not uid.begins_with("ml_"):
			continue
		var u: Dictionary = UnitDB.get_unit(uid)
		var tags: PackedStringArray = u["tags"]
		assert_true("military" in tags, "ml_ 유닛에 military 태그 없음: %s" % uid)


func test_all_units_have_size_tag() -> void:
	## 모든 유닛은 small / medium / large 중 하나를 가짐
	var valid_sizes := PackedStringArray(["small", "medium", "large"])
	for uid in UnitDB.get_all_ids():
		var u: Dictionary = UnitDB.get_unit(uid)
		var tags: PackedStringArray = u["tags"]
		var found := false
		for sz in valid_sizes:
			if sz in tags:
				found = true
				break
		assert_true(found, "size 태그(small/medium/large) 없음: %s" % uid)


func test_all_units_have_combat_style_tag() -> void:
	## 모든 유닛은 melee / ranged 중 하나를 가짐
	for uid in UnitDB.get_all_ids():
		var u: Dictionary = UnitDB.get_unit(uid)
		var tags: PackedStringArray = u["tags"]
		var has_style := ("melee" in tags) or ("ranged" in tags)
		assert_true(has_style, "melee/ranged 태그 없음: %s" % uid)


# --- 조회 API ---

func test_get_unit_unknown_id_returns_empty() -> void:
	var u: Dictionary = UnitDB.get_unit("nonexistent_unit")
	assert_true(u.is_empty(), "존재하지 않는 ID는 빈 딕셔너리")


# --- 대표 유닛 수치 스냅샷 (설계문서 직접 대조) ---

func test_sp_spider_stats() -> void:
	var u: Dictionary = UnitDB.get_unit("sp_spider")
	assert_eq(u["atk"], 2, "태엽 거미 ATK 2")
	assert_eq(u["hp"], 20, "태엽 거미 HP 20")
	assert_almost_eq(u["attack_speed"], 0.5, 0.001, "AS 0.5")
	assert_eq(u["range"], 0, "근접")
	assert_eq(u["move_speed"], 3, "MS 3")


func test_dr_spore_highest_atk() -> void:
	## 드루이드 포자 대포: 설계상 가장 높은 ATK(14)
	var u: Dictionary = UnitDB.get_unit("dr_spore")
	assert_eq(u["atk"], 14, "포자 대포 ATK 14")


func test_ml_artillery_longest_range() -> void:
	## 궤도 포대: Range 6 (최장)
	var u: Dictionary = UnitDB.get_unit("ml_artillery")
	assert_eq(u["range"], 6, "궤도 포대 Range 6")
