extends GutTest
## build_phase 머지 보너스 팝업 트리거 검증
## 참조: build_phase.gd:_on_card_merged
##
## ★1→★2 머지: rare 팝업 호출
## ★2→★3 머지: epic 팝업 미호출 (R5 OBS-011 결정 — ★3 ceremony 는 스탯 + 누적 시각화로 충분)


class MockPopup:
	extends RefCounted
	var calls: Array = []  # [{rarity, n}]
	signal upgrade_chosen(upgrade_id: String)

	func show_choices(rarity: int, n: int) -> void:
		calls.append({"rarity": rarity, "n": n})


var _bp = null
var _popup: MockPopup = null


func before_each() -> void:
	# Control 인스턴스를 직접 생성. _on_card_merged 는 @onready 노드를 사용하지 않으므로
	# 트리에 추가하지 않아도 충분히 단위 테스트 가능.
	_bp = load("res://scripts/build/build_phase.gd").new()
	_popup = MockPopup.new()
	_bp._upgrade_choice_popup = _popup


func after_each() -> void:
	if _bp != null:
		_bp.free()
		_bp = null


func test_star1_to_star2_merge_shows_rare_popup() -> void:
	var card: CardInstance = CardInstance.create("sp_assembly")
	_bp._on_card_merged(card, 1, 2)
	assert_eq(_popup.calls.size(), 1, "rare 팝업 1회 호출")
	assert_eq(_popup.calls[0]["rarity"], Enums.UpgradeRarity.RARE, "rarity = RARE")
	assert_eq(_bp._pending_merge_card, card, "pending_merge_card 설정")
	assert_string_contains(_bp.get_merge_summary_text(), "MERGE:")
	assert_string_contains(_bp.get_merge_summary_text(), "★1 -> ★2")
	assert_string_contains(_bp.get_merge_summary_text(), "무료 Rare")


func test_star2_to_star3_merge_does_not_show_epic_popup() -> void:
	## R5 OBS-011 결정: ★3 머지 시 epic 보너스 제거.
	var card: CardInstance = CardInstance.create("sp_assembly")
	_bp._on_card_merged(card, 2, 3)
	assert_eq(_popup.calls.size(), 0, "epic 팝업 호출되지 않아야 함")
	assert_null(_bp._pending_merge_card, "pending_merge_card 설정되지 않음")
	assert_string_contains(_bp.get_merge_summary_text(), "★2 -> ★3")
	assert_string_contains(_bp.get_merge_summary_text(), "최종 합성")


func test_cascade_star1_to_star3_retargets_pending_to_final_survivor() -> void:
	## 캐스케이드 ★1→★2→★3: step1 ★2 survivor 가 step2 에서 도너로 흡수되므로
	## free rare 부착 대상을 ★3 최종 survivor 로 retarget 해야 함 (분실 방지).
	var step1_survivor: CardInstance = CardInstance.create("sp_assembly")
	var final_survivor: CardInstance = CardInstance.create("sp_assembly")
	_bp._on_card_merged(step1_survivor, 1, 2)
	assert_eq(_bp._pending_merge_card, step1_survivor, "step1 후 pending = step1 survivor")
	_bp._on_card_merged(final_survivor, 2, 3)
	assert_eq(_bp._pending_merge_card, final_survivor,
		"step2 후 pending = ★3 final survivor (retarget)")
	assert_eq(_popup.calls.size(), 1, "RARE popup 만 1회 (sp_assembly 는 epic popup 없음)")
	assert_string_contains(_bp.get_merge_summary_text(), "★2 -> ★3")
	assert_string_contains(_bp.get_merge_summary_text(), "보상 대상 이전")


func test_plain_star2_to_star3_no_pending_no_retarget() -> void:
	## 캐스케이드 아닌 단순 ★2→★3 머지: _pending_merge_card 가 null 이면 retarget 발생 X.
	var card: CardInstance = CardInstance.create("sp_assembly")
	_bp._on_card_merged(card, 2, 3)
	assert_null(_bp._pending_merge_card, "단순 ★2→★3 은 pending 미설정 유지")


func test_merge_summary_records_even_without_bonus_popup() -> void:
	## popup 연결 전에도 최근 합성 피드백은 남아야 한다.
	var card: CardInstance = CardInstance.create("sp_assembly")
	_bp._upgrade_choice_popup = null
	_bp._on_card_merged(card, 1, 2)
	assert_string_contains(_bp.get_merge_summary_text(), "MERGE:")
	assert_string_contains(_bp.get_merge_summary_text(), "★1 -> ★2")
