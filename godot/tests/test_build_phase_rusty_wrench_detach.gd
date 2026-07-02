extends GutTest
## 녹슨 렌치 부적의 빌드 페이즈 업그레이드 분리 UI 진입점 테스트.

const BuildPhaseScript = preload("res://scripts/build/build_phase.gd")

var _bp = null
var _state: GameState = null


func before_each() -> void:
	_bp = BuildPhaseScript.new()
	_state = GameState.new()
	_state.talisman_type = Enums.TalismanType.RUSTY_WRENCH
	_state.terazin = 0
	_state.board[0] = CardInstance.create("sp_assembly")
	_bp.game_state = _state


func after_each() -> void:
	if _bp != null:
		_bp.free()
		_bp = null


func test_detach_requires_rusty_wrench() -> void:
	_state.talisman_type = Enums.TalismanType.NONE
	_state.board[0].attach_upgrade("C1")
	assert_false(_bp.detach_upgrade_from_field(0), "녹슨 렌치 없으면 분리 불가")


func test_detach_requires_card_with_upgrade() -> void:
	assert_false(_bp.detach_upgrade_from_field(0), "업그레이드 없는 카드는 분리 불가")


func test_detach_last_upgrade_refunds_and_emits() -> void:
	var card: CardInstance = _state.board[0]
	card.attach_upgrade("C1")  # common cost 4 → 50% refund = 2
	card.attach_upgrade("C2")
	var refunds: Array = []
	var state_changed := [0]
	_state.upgrade_refunded.connect(func(upgrade_id: String, cost: int, reason: String, terazin_after: int):
		refunds.append({
			"upgrade_id": upgrade_id,
			"cost": cost,
			"reason": reason,
			"terazin_after": terazin_after,
		}))
	_state.state_changed.connect(func(): state_changed[0] += 1)

	assert_true(_bp.detach_upgrade_from_field(0), "분리 성공")
	assert_eq(card.upgrades.size(), 1, "마지막 업그레이드 1개 제거")
	assert_eq(card.upgrades[0]["id"], "C1", "C2가 제거되고 C1 유지")
	assert_eq(_state.terazin, 2, "50% 테라진 환급")
	assert_eq(refunds.size(), 1, "환급 신호 1회")
	assert_eq(refunds[0]["upgrade_id"], "C2")
	assert_eq(refunds[0]["cost"], 2)
	assert_eq(refunds[0]["reason"], "rusty_wrench_detach")
	assert_eq(refunds[0]["terazin_after"], 2)
	assert_eq(state_changed[0], 1, "state_changed 1회")
