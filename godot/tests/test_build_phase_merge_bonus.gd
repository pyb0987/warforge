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


func test_star2_to_star3_merge_does_not_show_epic_popup() -> void:
	## R5 OBS-011 결정: ★3 머지 시 epic 보너스 제거.
	var card: CardInstance = CardInstance.create("sp_assembly")
	_bp._on_card_merged(card, 2, 3)
	assert_eq(_popup.calls.size(), 0, "epic 팝업 호출되지 않아야 함")
	assert_null(_bp._pending_merge_card, "pending_merge_card 설정되지 않음")
