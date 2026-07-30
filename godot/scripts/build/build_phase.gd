extends Control
## Build phase UI: shop + field slots + bench slots + card drag-and-drop.

signal build_confirmed
signal sell_performed(zone: String, idx: int, sold_card: CardInstance)
signal merge_performed(card: CardInstance)
signal free_upgrade_finished(applied: bool)
signal upgrade_rerolled(cost: int, terazin_after: int)
signal tutorial_dismissed

var merge_history_max := 4
var game_state: GameState = null
var _field_visuals: Array = []
var _bench_visuals: Array = []
var _pending_upgrade: Dictionary = {}  # {upgrade_id, slot_idx, cost}
var _pending_merge_card: CardInstance = null
var _upgrade_choice_popup = null  # set by game_manager
var _pending_detach_upgrade: bool = false
var _strategist_swap_active: bool = false
var _strategist_swap_first_idx: int = -1
var _genome: Genome = null
var _tutorial_enabled: bool = false
var _tutorial_dismissed: bool = false
var _last_merge_summary: String = ""
var _merge_history: PackedStringArray = []
var _last_chain_summary: String = ""
var _last_chain_history: String = ""
var _last_settlement_recap: Dictionary = {}
var _build_readiness_text: String = ""
var _enemy_pressure_preview_text: String = ""
var _enemy_pressure_preview_data: Dictionary = {}

@onready var shop: HBoxContainer = $Shop
@onready var upgrade_shop: HBoxContainer = $UpgradeShop
@onready var target_overlay: Control = $TargetSelectOverlay
@onready var field_container: HBoxContainer = $FieldContainer
@onready var bench_container: HBoxContainer = $BenchContainer
@onready var confirm_button: Button = $ConfirmButton
@onready var detach_upgrade_button: Button = get_node_or_null("DetachUpgradeButton") as Button
@onready var strategist_swap_button: Button = get_node_or_null("StrategistSwapButton") as Button
@onready var upgrade_reroll_button: Button = get_node_or_null("UpgradeRerollButton") as Button
@onready var gold_label: Label = $HUD/GoldLabel
@onready var terazin_label: Label = $HUD/TerazinLabel
@onready var round_label: Label = $HUD/RoundLabel
@onready var hp_label: Label = $HUD/HPLabel
@onready var identity_label: Label = get_node_or_null("HUD/IdentityLabel") as Label
@onready var shop_label: Label = $ShopLabel
@onready var upgrade_shop_label: Label = $UpgradeShopLabel
@onready var merge_history_panel: PanelContainer = \
	get_node_or_null("MergeHistoryPanel") as PanelContainer
@onready var merge_history_log_label: Label = \
	get_node_or_null("MergeHistoryPanel/VBox/MergeHistoryLogLabel") as Label
@onready var tutorial_hint_panel: PanelContainer = \
	get_node_or_null("TutorialHintPanel") as PanelContainer
@onready var tutorial_hint_label: Label = \
	get_node_or_null("TutorialHintPanel/VBox/TutorialHintLabel") as Label
@onready var tutorial_dismiss_button: Button = \
	get_node_or_null("TutorialHintPanel/VBox/TutorialDismissButton") as Button
@onready var last_chain_panel: PanelContainer = \
	get_node_or_null("LastChainPanel") as PanelContainer
@onready var last_chain_summary_label: Label = \
	get_node_or_null("LastChainPanel/VBox/LastChainSummaryLabel") as Label
@onready var last_chain_log_label: Label = \
	get_node_or_null("LastChainPanel/VBox/LastChainLogLabel") as Label
@onready var build_readiness_panel: PanelContainer = \
	get_node_or_null("BuildReadinessPanel") as PanelContainer
@onready var build_readiness_body_label: Label = \
	get_node_or_null("BuildReadinessPanel/VBox/BuildReadinessBodyLabel") as Label
@onready var settlement_recap_panel: PanelContainer = \
	get_node_or_null("SettlementRecapPanel") as PanelContainer
@onready var settlement_recap_title_label: Label = \
	get_node_or_null("SettlementRecapPanel/VBox/SettlementTitleLabel") as Label
@onready var settlement_recap_gold_label: Label = \
	get_node_or_null("SettlementRecapPanel/VBox/SettlementGoldLabel") as Label
@onready var settlement_recap_terazin_label: Label = \
	get_node_or_null("SettlementRecapPanel/VBox/SettlementTerazinLabel") as Label
@onready var settlement_recap_next_label: Label = \
	get_node_or_null("SettlementRecapPanel/VBox/SettlementNextLabel") as Label


func setup(state: GameState, rng: RandomNumberGenerator, genome: Genome = null) -> void:
	game_state = state
	_genome = genome
	game_state.state_changed.connect(_refresh_all)
	confirm_button.pressed.connect(_on_confirm_pressed)
	if detach_upgrade_button:
		detach_upgrade_button.pressed.connect(_on_detach_upgrade_pressed)
	if strategist_swap_button:
		strategist_swap_button.pressed.connect(_on_strategist_swap_pressed)
	if upgrade_reroll_button:
		upgrade_reroll_button.pressed.connect(_on_upgrade_reroll_pressed)
	if tutorial_dismiss_button:
		tutorial_dismiss_button.pressed.connect(_on_tutorial_dismiss_pressed)
	_create_slots()
	shop.setup(state, rng, genome)
	shop.card_merged.connect(_on_card_merged)
	upgrade_shop.setup(state, rng)
	upgrade_shop.upgrade_purchase_requested.connect(_on_upgrade_purchase_requested)
	target_overlay.target_selected.connect(_on_target_selected)
	target_overlay.target_cancelled.connect(_on_target_cancelled)
	target_overlay.visibility_changed.connect(_refresh_tutorial_hint)
	target_overlay.visibility_changed.connect(_refresh_last_chain_history_panel)
	target_overlay.visibility_changed.connect(_refresh_settlement_recap_panel)
	target_overlay.visibility_changed.connect(_refresh_merge_history_panel)
	target_overlay.visibility_changed.connect(_refresh_build_readiness_panel)
	target_overlay.visible = false
	_refresh_all()


func set_tutorial_enabled(enabled: bool) -> void:
	_tutorial_enabled = enabled
	_tutorial_dismissed = false
	_refresh_tutorial_hint()


func get_tutorial_hint_text() -> String:
	if tutorial_hint_panel == null or tutorial_hint_label == null:
		return ""
	if not tutorial_hint_panel.visible:
		return ""
	return tutorial_hint_label.text


func get_build_readiness_text() -> String:
	if build_readiness_panel == null or not build_readiness_panel.is_visible_in_tree():
		return ""
	return _build_readiness_text


func get_enemy_pressure_preview_text() -> String:
	if build_readiness_panel == null or not build_readiness_panel.is_visible_in_tree():
		return ""
	return _enemy_pressure_preview_text


func get_enemy_pressure_preview_data() -> Dictionary:
	if get_enemy_pressure_preview_text() == "":
		return {}
	return _enemy_pressure_preview_data.duplicate(true)


func is_build_readiness_visible() -> bool:
	return build_readiness_panel != null and build_readiness_panel.is_visible_in_tree()


func get_merge_summary_text() -> String:
	return _last_merge_summary


func get_merge_history_entries() -> Array:
	var entries: Array = []
	for entry in _merge_history:
		entries.append(entry)
	return entries


func get_merge_history_text() -> String:
	return "\n".join(_merge_history)


func is_merge_history_visible() -> bool:
	return merge_history_panel != null and merge_history_panel.is_visible_in_tree()


func clear_merge_history() -> void:
	_last_merge_summary = ""
	_merge_history.clear()
	_refresh_merge_history_panel()
	_refresh_settlement_recap_panel()
	_refresh_tutorial_hint()


func set_last_chain_history(summary: String, history: String) -> void:
	_last_chain_summary = summary
	_last_chain_history = history
	_refresh_last_chain_history_panel()
	_refresh_build_readiness_panel()


func clear_last_chain_history() -> void:
	_last_chain_summary = ""
	_last_chain_history = ""
	_refresh_last_chain_history_panel()
	_refresh_build_readiness_panel()


func set_last_settlement_recap(recap: Dictionary) -> void:
	_last_settlement_recap = recap.duplicate(true)
	_refresh_settlement_recap_panel()
	_refresh_tutorial_hint()


func clear_last_settlement_recap() -> void:
	_last_settlement_recap = {}
	_refresh_settlement_recap_panel()
	_refresh_tutorial_hint()


func get_last_settlement_recap_data() -> Dictionary:
	return _last_settlement_recap.duplicate(true)


func get_last_settlement_recap_text() -> String:
	if settlement_recap_panel == null or not settlement_recap_panel.is_visible_in_tree():
		return ""
	var lines := PackedStringArray()
	if settlement_recap_title_label != null:
		lines.append(settlement_recap_title_label.text)
	if settlement_recap_gold_label != null:
		lines.append(settlement_recap_gold_label.text)
	if settlement_recap_terazin_label != null:
		lines.append(settlement_recap_terazin_label.text)
	if settlement_recap_next_label != null:
		lines.append(settlement_recap_next_label.text)
	return "\n".join(lines)


func is_last_settlement_recap_visible() -> bool:
	return settlement_recap_panel != null and settlement_recap_panel.is_visible_in_tree()


func get_last_chain_history_text() -> String:
	if last_chain_panel == null or not last_chain_panel.is_visible_in_tree():
		return ""
	if _last_chain_history == "":
		return _last_chain_summary
	return "%s\n%s" % [_last_chain_summary, _last_chain_history]


func get_last_chain_history_display_text() -> String:
	if last_chain_panel == null or not last_chain_panel.is_visible_in_tree():
		return ""
	if last_chain_log_label == null or last_chain_log_label.text == "":
		return _last_chain_summary
	return "%s\n%s" % [_last_chain_summary, last_chain_log_label.text]


func is_last_chain_history_visible() -> bool:
	return last_chain_panel != null and last_chain_panel.is_visible_in_tree()


func set_upgrade_choice_popup(popup) -> void:
	_upgrade_choice_popup = popup
	if _upgrade_choice_popup:
		_upgrade_choice_popup.upgrade_chosen.connect(_on_merge_upgrade_chosen)
		if not _upgrade_choice_popup.visibility_changed.is_connected(_refresh_tutorial_hint):
			_upgrade_choice_popup.visibility_changed.connect(_refresh_tutorial_hint)
		if not _upgrade_choice_popup.visibility_changed.is_connected(_refresh_last_chain_history_panel):
			_upgrade_choice_popup.visibility_changed.connect(_refresh_last_chain_history_panel)
		if not _upgrade_choice_popup.visibility_changed.is_connected(_refresh_settlement_recap_panel):
			_upgrade_choice_popup.visibility_changed.connect(_refresh_settlement_recap_panel)
		if not _upgrade_choice_popup.visibility_changed.is_connected(_refresh_merge_history_panel):
			_upgrade_choice_popup.visibility_changed.connect(_refresh_merge_history_panel)
		if not _upgrade_choice_popup.visibility_changed.is_connected(_refresh_build_readiness_panel):
			_upgrade_choice_popup.visibility_changed.connect(_refresh_build_readiness_panel)


func refresh_shop(refresh_upgrades: bool = false) -> void:
	# Player card rerolls must not disturb upgrade offers. Round/phase refreshes
	# pass refresh_upgrades=true when both shops should be newly dealt.
	shop.refresh_shop()
	if refresh_upgrades and upgrade_shop.is_available():
		upgrade_shop.refresh_upgrades()


func refresh_display() -> void:
	_refresh_all()


func get_identity_text() -> String:
	if identity_label == null:
		return _format_identity_label()
	return identity_label.text


func get_run_milestone_text() -> String:
	if game_state == null:
		return ""
	return _format_run_milestone_text(game_state.round_num)


func get_run_progress_rail_text() -> String:
	if game_state == null:
		return ""
	return _format_run_progress_rail_text(game_state.round_num)


func get_round_label_text() -> String:
	if round_label == null:
		return _format_round_label()
	return round_label.text


func get_shop_offered() -> Array:
	return shop._offered_ids


func reroll() -> bool:
	return shop.reroll()


func reroll_upgrades() -> bool:
	if not can_reroll_upgrades():
		return false
	var ok: bool = upgrade_shop.reroll_upgrades()
	if ok:
		upgrade_rerolled.emit(Enums.UPGRADE_REROLL_COST, game_state.terazin)
	_update_upgrade_reroll_button()
	return ok


func can_reroll_upgrades() -> bool:
	if game_state == null or upgrade_shop == null:
		return false
	if not upgrade_shop.is_available():
		return false
	if not _pending_upgrade.is_empty() or _pending_detach_upgrade or _strategist_swap_active:
		return false
	return game_state.terazin >= Enums.UPGRADE_REROLL_COST


func _create_slots() -> void:
	for i in Enums.MAX_FIELD_SLOTS:
		var slot := _create_card_slot("board", i)
		field_container.add_child(slot)
		_field_visuals.append(slot)
		slot.visible = i < game_state.field_slots

	for i in Enums.MAX_BENCH_SLOTS:
		var slot := _create_card_slot("bench", i)
		bench_container.add_child(slot)
		_bench_visuals.append(slot)


func _create_card_slot(zone_name: String, idx: int) -> Panel:
	var slot: Panel = preload("res://scenes/build/card_visual.tscn").instantiate()
	slot.zone = zone_name
	slot.slot_idx = idx
	slot.custom_minimum_size = Vector2(120, 160)
	slot.card_clicked.connect(_on_card_clicked)
	return slot


func _refresh_all() -> void:
	for i in _field_visuals.size():
		_field_visuals[i].visible = i < game_state.field_slots
		var card = game_state.board[i]
		_field_visuals[i].setup(card, "board", i)

	for i in _bench_visuals.size():
		var card = game_state.bench[i]
		_bench_visuals[i].setup(card, "bench", i)

	if gold_label:
		var interest: int = game_state.calc_interest()
		gold_label.text = "Gold: %d (+%di)" % [game_state.gold, interest]
	if terazin_label:
		terazin_label.text = "Terazin: %d" % game_state.terazin
	if round_label:
		round_label.text = _format_round_label()
	if hp_label:
		hp_label.text = "HP: %d" % game_state.hp
	if identity_label:
		identity_label.text = _format_identity_label()
	if shop_label:
		var level: int = shop._get_shop_level()
		var reroll_cost: int = _get_reroll_cost()
		if level < Enums.LEVELUP_MAX:
			shop_label.text = "CARD SHOP Lv%d (R:cards -%dg | F:levelup -%dg)" % [
				level, reroll_cost, game_state.levelup_current_cost]
		else:
			shop_label.text = "CARD SHOP Lv%d MAX (R:cards -%dg)" % [
				level, reroll_cost]
		# 이번 라운드 한정 무료 리롤 저축분이 있으면 배지 표시.
		# 사용자가 R 키를 누를 때 commander 확률 후 우선 소진된다.
		if game_state.pending_free_rerolls > 0:
			shop_label.text += "  [무료 리롤 ×%d]" % game_state.pending_free_rerolls

	_refresh_merge_history_panel()

	# Upgrade shop is visible from R1 now that every run starts with a commander.
	var upg_visible: bool = upgrade_shop.is_available()
	upgrade_shop.visible = upg_visible
	if upgrade_shop_label:
		upgrade_shop_label.visible = upg_visible
		if upg_visible:
			upgrade_shop_label.text = "UPGRADES (T:upgrades only)"
	if upgrade_shop.visible:
		upgrade_shop.refresh_offer_visuals()

	_update_strategist_swap_button()
	_update_detach_upgrade_button()
	_update_upgrade_reroll_button()
	_refresh_settlement_recap_panel()
	_refresh_tutorial_hint()
	_refresh_last_chain_history_panel()
	_refresh_build_readiness_panel()


func _format_identity_label() -> String:
	if game_state == null:
		return ""
	var commander_data: Dictionary = Commander.get_data(game_state.commander_type)
	var talisman_data: Dictionary = Talisman.get_data(game_state.talisman_type)
	var commander_name: String = commander_data.get("name", "없음")
	var talisman_name: String = talisman_data.get("name", "없음")
	var commander_icon: String = commander_data.get("icon", "")
	var talisman_icon: String = talisman_data.get("icon", "")
	var commander_line := "커맨더: %s%s" % [
		("%s " % commander_icon) if commander_icon != "" else "",
		commander_name,
	]
	var commander_status := _format_commander_status()
	if commander_status != "":
		commander_line += " - %s" % commander_status
	var talisman_line := "부적: %s%s" % [
		("%s " % talisman_icon) if talisman_icon != "" else "",
		talisman_name,
	]
	var talisman_status := _format_talisman_status()
	if talisman_status != "":
		talisman_line += " - %s" % talisman_status
	return "%s\n%s" % [commander_line, talisman_line]


func _format_round_label() -> String:
	if game_state == null:
		return ""
	return "Round %d/%d · %s\n%s" % [
		game_state.round_num,
		Enums.MAX_ROUNDS,
		_format_run_milestone_short(game_state.round_num),
		_format_run_progress_rail_text(game_state.round_num),
	]


func _format_run_progress_rail_text(round_num: int) -> String:
	var reward_parts := PackedStringArray()
	for boss_round in Enums.BOSS_ROUNDS:
		var milestone := int(boss_round)
		if milestone == Enums.MAX_ROUNDS:
			continue
		var status := _format_run_rail_status(round_num, milestone)
		reward_parts.append("R%d%s" % [
			milestone,
			(" %s" % status) if status != "" else "",
		])
	var final_status := _format_run_rail_status(round_num, Enums.MAX_ROUNDS)
	return "R%d NOW | rewards %s | R%d final%s" % [
		clampi(round_num, 1, Enums.MAX_ROUNDS),
		", ".join(reward_parts),
		Enums.MAX_ROUNDS,
		(" %s" % final_status) if final_status != "" else "",
	]


func _format_run_rail_status(round_num: int, milestone: int) -> String:
	if round_num > milestone:
		return "done"
	if round_num == milestone:
		return "now"
	for boss_round in Enums.BOSS_ROUNDS:
		var candidate := int(boss_round)
		if round_num <= candidate:
			return "next" if candidate == milestone else ""
	return ""


func _format_run_milestone_short(round_num: int) -> String:
	var text := _format_run_milestone_text(round_num)
	if text.begins_with("Goal: "):
		return text.trim_prefix("Goal: ")
	return text


func _format_run_milestone_text(round_num: int) -> String:
	if round_num > Enums.MAX_ROUNDS:
		return "Goal: Run complete"
	for boss_round in Enums.BOSS_ROUNDS:
		if round_num > int(boss_round):
			continue
		var label := "final boss" if int(boss_round) == Enums.MAX_ROUNDS \
			else "boss reward"
		var fights_to_goal := int(boss_round) - round_num + 1
		if fights_to_goal <= 1:
			return "Goal: R%d %s this fight" % [int(boss_round), label]
		return "Goal: R%d %s in %d fights" % [
			int(boss_round),
			label,
			fights_to_goal,
		]
	return "Goal: Run complete"


func _format_commander_status() -> String:
	match game_state.commander_type:
		Enums.CommanderType.GAMBLER:
			return "리롤 50% 무료, ★3 합성 환급"
		Enums.CommanderType.BREEDER:
			return "유닛상한 +20, 추가생성 30%"
		Enums.CommanderType.SMITH:
			return "업글 슬롯 +1, Common -1t"
		Enums.CommanderType.STRATEGIST:
			var swap_state := "사용됨" if bool(game_state.commander_state.get("hero_used", false)) else "가능"
			return "필드 +1, 인접 2칸, SWAP %s" % swap_state
		Enums.CommanderType.COLLECTOR:
			var unique_count := _count_board_card_types()
			var atk_pct := int(round(unique_count * Commander.COLLECTOR_ATK_PER_TYPE * 100.0))
			var terazin_note := ", +1t 준비" if unique_count >= Commander.COLLECTOR_TERAZIN_THRESHOLD else ""
			return "종류 %d개: ATK +%d%%%s" % [unique_count, atk_pct, terazin_note]
		Enums.CommanderType.RAIDER:
			var wins := int(game_state.commander_state.get("win_count", 0))
			return "승리 +2g, 업글 %d/%d승" % [wins, Commander.RAIDER_UPGRADE_INTERVAL]
		Enums.CommanderType.ALCHEMIST:
			return "매 라운드 +1t, Epic 상점"
	return ""


func _format_talisman_status() -> String:
	match game_state.talisman_type:
		Enums.TalismanType.FLINT:
			var flint_state := "사용됨" if bool(game_state.talisman_state.get("first_growth_used", false)) else "준비"
			return "첫 성장 효과 ×2 %s" % flint_state
		Enums.TalismanType.TWO_FACED_COIN:
			var coin_status: String = ""
			if shop:
				coin_status = shop.get_coin_slot_status()
			if coin_status != "":
				return "상점 -50%%/+50%% (%s)" % coin_status
			return "상점 1장 -50%, 1장 +50%"
		Enums.TalismanType.CRACKED_SKULL:
			return "각 유닛 첫 치사 생존"
		Enums.TalismanType.MERCURY_DROP:
			return "강화 효과 +25%"
		Enums.TalismanType.CRACKED_EGG:
			return "★2+ 유닛추가 +1"
		Enums.TalismanType.WAR_DRUM:
			return "수적 우위면 적 ATK -10%"
		Enums.TalismanType.GLASS_EYE:
			return "보유 카드 리롤확률 ×1.15"
		Enums.TalismanType.GOLDEN_DIE:
			return "보스 보상 선택지 6"
		Enums.TalismanType.RUSTY_WRENCH:
			return "업그레이드 분리, 50% 환급"
		Enums.TalismanType.SOUL_JAR:
			var jar_state := "사용됨" if bool(game_state.talisman_state.get("first_sell_used", false)) else "준비"
			return "첫 판매 유닛배분 %s" % jar_state
		Enums.TalismanType.BURST_SACK:
			return "업그레이드 상점 +1"
		Enums.TalismanType.COPPER_WIRE:
			return "풀업글 인접 전파 30%"
	return ""


func _count_board_card_types() -> int:
	var seen := {}
	for card in game_state.board:
		if card == null:
			continue
		seen[(card as CardInstance).get_base_id()] = true
	return seen.size()


func _refresh_build_readiness_panel() -> void:
	if build_readiness_panel == null or build_readiness_body_label == null:
		return
	if game_state == null or _is_tutorial_suppressed_by_modal():
		build_readiness_panel.visible = false
		_enemy_pressure_preview_text = ""
		_enemy_pressure_preview_data = {}
		return
	if _last_chain_summary != "" or _last_chain_history != "":
		build_readiness_panel.visible = false
		_enemy_pressure_preview_text = ""
		_enemy_pressure_preview_data = {}
		return
	_build_readiness_text = _format_build_readiness_text()
	build_readiness_body_label.text = _build_readiness_text
	build_readiness_panel.visible = _build_readiness_text != ""


func _format_build_readiness_text() -> String:
	var field_count := _count_board_cards()
	var bench_count := _count_bench_cards()
	var next_action := _format_build_readiness_next_action(field_count, bench_count)
	var lines := PackedStringArray()
	lines.append("FIELD: %d장 체인/전투 참가" % field_count)
	lines.append("BENCH: %s" % _format_bench_readiness(bench_count))
	var enemy_line := _format_enemy_pressure_preview_line()
	if enemy_line != "":
		lines.append(enemy_line)
	lines.append("Next: %s" % next_action)
	return "\n".join(lines)


func _format_enemy_pressure_preview_line() -> String:
	_enemy_pressure_preview_text = ""
	_enemy_pressure_preview_data = {}
	if game_state == null:
		return ""
	var profile := EnemyDB.pressure_profile(
		game_state.round_num, _genome, game_state.difficulty)
	if profile.is_empty():
		return ""
	var count_text := _format_preview_range(profile, "enemy_count")
	var atk_text := _format_preview_range(profile, "total_atk")
	var hp_text := _format_preview_range(profile, "total_hp")
	var boss_text := "BOSS " if bool(profile.get("boss", false)) else ""
	var line := "ENEMY: R%d %s%s기 · ATK %s HP %s" % [
		int(profile.get("round", game_state.round_num)),
		boss_text,
		count_text,
		atk_text,
		hp_text,
	]
	if int(profile.get("boss_upgrade_count", 0)) > 0:
		line += " · 업글"
	profile["text"] = line
	_enemy_pressure_preview_text = line
	_enemy_pressure_preview_data = profile.duplicate(true)
	return line


func _format_preview_range(profile: Dictionary, key: String) -> String:
	var min_value := roundi(float(profile.get("%s_min" % key, 0.0)))
	var max_value := roundi(float(profile.get("%s_max" % key, 0.0)))
	if min_value == max_value:
		return str(min_value)
	return "%d-%d" % [min_value, max_value]


func _format_build_readiness_next_action(field_count: int, bench_count: int) -> String:
	if field_count <= 0:
		if bench_count > 0:
			return "BENCH 카드를 FIELD로 드래그"
		return "SHOP에서 카드를 구매"
	if _has_affordable_upgrade_offer() and _has_upgrade_target():
		return "업그레이드하거나 BUILD COMPLETE"
	return "BUILD COMPLETE로 체인/전투 시작"


func _format_bench_readiness(bench_count: int) -> String:
	if bench_count <= 0:
		return "비어 있음"
	return "%d장 대기(전투 불참)" % bench_count


func _count_bench_cards() -> int:
	var count := 0
	if game_state == null:
		return count
	for card in game_state.bench:
		if card != null:
			count += 1
	return count


func _refresh_merge_history_panel() -> void:
	if merge_history_panel == null or merge_history_log_label == null:
		return
	if _merge_history.is_empty() or _is_tutorial_suppressed_by_modal():
		merge_history_panel.visible = false
		return
	merge_history_log_label.text = "\n".join(_merge_history)
	merge_history_panel.visible = true


func _refresh_last_chain_history_panel() -> void:
	if last_chain_panel == null or last_chain_summary_label == null or last_chain_log_label == null:
		return
	if _last_chain_summary == "" and _last_chain_history == "":
		last_chain_panel.visible = false
		return
	if _is_tutorial_suppressed_by_modal():
		last_chain_panel.visible = false
		return
	last_chain_summary_label.text = _last_chain_summary
	last_chain_log_label.text = _format_last_chain_panel_log(_last_chain_history)
	last_chain_panel.visible = true


func _refresh_settlement_recap_panel() -> void:
	if settlement_recap_panel == null \
			or settlement_recap_title_label == null \
			or settlement_recap_gold_label == null \
			or settlement_recap_terazin_label == null \
			or settlement_recap_next_label == null:
		return
	if _last_settlement_recap.is_empty():
		settlement_recap_panel.visible = false
		return
	if not _merge_history.is_empty():
		settlement_recap_panel.visible = false
		return
	if _is_tutorial_suppressed_by_modal():
		settlement_recap_panel.visible = false
		return
	settlement_recap_title_label.text = "LAST SETTLEMENT R%d" % int(
		_last_settlement_recap.get("round", 0))
	settlement_recap_gold_label.text = _format_settlement_gold_line(
		_last_settlement_recap)
	settlement_recap_terazin_label.text = _format_settlement_terazin_line(
		_last_settlement_recap)
	settlement_recap_next_label.text = "Next: R%d BUILD" % int(
		_last_settlement_recap.get("next_round", game_state.round_num))
	var milestone := _format_run_milestone_short(int(
		_last_settlement_recap.get("next_round", game_state.round_num)))
	if milestone != "":
		settlement_recap_next_label.text += " · %s" % milestone
	settlement_recap_panel.visible = true


func _format_settlement_gold_line(recap: Dictionary) -> String:
	var gold_before := int(recap.get("gold_before", 0))
	var gold_after := int(recap.get("gold_after", 0))
	var delta := int(recap.get("gold_delta", gold_after - gold_before))
	var parts := PackedStringArray()
	parts.append("%s income" % _format_signed_int(int(recap.get("base_income", 0))))
	parts.append("%s interest" % _format_signed_int(int(recap.get("interest", 0))))
	return "Gold: %d -> %d (%s; %s)" % [
		gold_before,
		gold_after,
		_format_signed_int(delta),
		", ".join(parts),
	]


func _format_settlement_terazin_line(recap: Dictionary) -> String:
	var terazin_before := int(recap.get("terazin_before", 0))
	var terazin_after := int(recap.get("terazin_after", 0))
	var delta := int(recap.get("terazin_delta", terazin_after - terazin_before))
	var parts := PackedStringArray()
	parts.append("%s round" % _format_signed_int(int(
		recap.get("terazin_gain", 0))))
	var commander_bonus := int(recap.get("commander_terazin", 0))
	if commander_bonus != 0:
		parts.append("%s commander" % _format_signed_int(commander_bonus))
	return "Terazin: %d -> %d (%s; %s)" % [
		terazin_before,
		terazin_after,
		_format_signed_int(delta),
		", ".join(parts),
	]


func _format_signed_int(value: int) -> String:
	if value >= 0:
		return "+%d" % value
	return "%d" % value


func _format_last_chain_panel_log(text: String) -> String:
	if text == "":
		return ""
	var lines := text.split("\n")
	var events := PackedStringArray()
	for line in lines:
		var compact := _compact_last_chain_line(str(line))
		if compact != "":
			events.append(compact)
	var start := maxi(events.size() - 2, 0)
	var tail := PackedStringArray()
	for i in range(start, events.size()):
		tail.append(events[i])
	return "\n".join(tail)


func _compact_last_chain_line(line: String) -> String:
	var compact := line.strip_edges()
	if compact == "" or compact.begins_with("Complete:"):
		return ""
	var detail_idx := compact.find(" (")
	if detail_idx >= 0:
		compact = compact.substr(0, detail_idx)
	compact = compact.replace("Round Start: ", "")
	compact = compact.replace("Cascade: ", "")
	return compact


func _get_reroll_cost() -> int:
	var base_cost: int = _genome.get_reroll_cost() if _genome else Enums.REROLL_COST
	return Difficulty.get_reroll_cost(base_cost, game_state.difficulty)


func _on_tutorial_dismiss_pressed() -> void:
	_tutorial_dismissed = true
	_refresh_tutorial_hint()
	tutorial_dismissed.emit()


func _refresh_tutorial_hint() -> void:
	if tutorial_hint_panel == null or tutorial_hint_label == null:
		return
	if not _tutorial_enabled or _tutorial_dismissed or game_state == null:
		tutorial_hint_panel.visible = false
		return
	if _is_tutorial_suppressed_by_modal():
		tutorial_hint_panel.visible = false
		return
	if not _merge_history.is_empty():
		tutorial_hint_panel.visible = false
		return
	if not _last_settlement_recap.is_empty():
		tutorial_hint_panel.visible = false
		return
	var text := _get_current_tutorial_hint()
	tutorial_hint_label.text = text
	tutorial_hint_panel.visible = text != ""


func _is_tutorial_suppressed_by_modal() -> bool:
	if target_overlay != null and target_overlay.visible:
		return true
	if _upgrade_choice_popup != null and _upgrade_choice_popup.visible:
		return true
	return false


func _get_current_tutorial_hint() -> String:
	if not _pending_upgrade.is_empty():
		return "업그레이드 대상 선택\n초록 테두리 카드에 장착됩니다. 카드 위 슬롯 표시를 보고 선택하세요."
	if game_state.board_count() <= 0:
		if _has_bench_cards():
			return "필드 배치\n벤치 카드를 FIELD 슬롯으로 드래그하면 성장 체인과 전투에 참여합니다."
		return "카드 구매\nSHOP의 카드를 클릭해 벤치에 추가하세요. 같은 카드 3장은 자동으로 합성됩니다."
	if _has_affordable_upgrade_offer() and _has_upgrade_target():
		return "업그레이드\nUPGRADES 카드를 클릭하면 테라진을 쓰고, 필드 카드에 영구 장착합니다."
	return "전투 준비\n배치가 끝났으면 BUILD COMPLETE를 눌러 성장 체인과 전투를 진행하세요."


func _has_bench_cards() -> bool:
	if game_state == null:
		return false
	for card in game_state.bench:
		if card != null:
			return true
	return false


func _has_upgrade_target() -> bool:
	if game_state == null:
		return false
	for card in game_state.board:
		if _can_attach_upgrade_predicate(card):
			return true
	return false


func _has_affordable_upgrade_offer() -> bool:
	if game_state == null or upgrade_shop == null or not upgrade_shop.visible:
		return false
	for i in upgrade_shop._offered_ids.size():
		if upgrade_shop._offered_ids[i] == "":
			continue
		if game_state.terazin >= upgrade_shop.get_upgrade_cost(i):
			return true
	return false


func _on_card_dropped(data: Dictionary, to_zone: String, to_idx: int) -> void:
	if _pending_detach_upgrade:
		return
	if _strategist_swap_active:
		return
	var from_zone: String = data["source_zone"]
	var from_idx: int = data["source_idx"]
	if from_zone == to_zone and from_idx == to_idx:
		return
	game_state.move_card(from_zone, from_idx, to_zone, to_idx)
	_refresh_tutorial_hint()


func _on_card_sell(zone: String, idx: int) -> void:
	if _pending_detach_upgrade:
		cancel_rusty_wrench_detach()
	if _strategist_swap_active:
		cancel_strategist_swap()
	# 카드 정보를 판매 전에 캡처 (영혼 항아리용)
	var zone_arr := game_state.board if zone == "board" else game_state.bench
	var sold_card: CardInstance = zone_arr[idx] if idx < zone_arr.size() else null
	# 슬롯 위치를 판매 전에 캡처 (플로팅 텍스트용)
	var visuals := _field_visuals if zone == "board" else _bench_visuals
	var slot_pos: Vector2 = visuals[idx].global_position if idx < visuals.size() else Vector2.ZERO
	var refund := game_state.sell_card(zone, idx)
	if refund > 0:
		print("[Sell] +%dg refund | Gold=%d" % [refund, game_state.gold])
		_show_floating_gold(slot_pos, refund)
		sell_performed.emit(zone, idx, sold_card)


func _on_confirm_pressed() -> void:
	if _pending_detach_upgrade:
		cancel_rusty_wrench_detach()
		return
	if _strategist_swap_active:
		cancel_strategist_swap()
		return
	_tutorial_dismissed = true
	_refresh_tutorial_hint()
	build_confirmed.emit()


# --- Strategist hero swap flow ---


func begin_strategist_swap() -> bool:
	if game_state == null:
		return false
	if not _pending_upgrade.is_empty():
		return false
	if game_state.commander_type != Enums.CommanderType.STRATEGIST:
		return false
	if bool(game_state.commander_state.get("hero_used", false)):
		return false
	if _count_board_cards() < 2:
		return false
	_strategist_swap_active = true
	_strategist_swap_first_idx = -1
	_update_strategist_swap_button()
	_refresh_strategist_swap_highlights()
	return true


func cancel_strategist_swap() -> void:
	if not _strategist_swap_active and _strategist_swap_first_idx < 0:
		return
	_strategist_swap_active = false
	_strategist_swap_first_idx = -1
	_update_strategist_swap_button()
	_refresh_strategist_swap_highlights()


func _select_strategist_swap_slot(field_idx: int) -> bool:
	if not _strategist_swap_active:
		return false
	if field_idx < 0 or field_idx >= game_state.board.size():
		return false
	if game_state.board[field_idx] == null:
		return false
	if _strategist_swap_first_idx < 0:
		_strategist_swap_first_idx = field_idx
		_update_strategist_swap_button()
		_refresh_strategist_swap_highlights()
		return true
	if field_idx == _strategist_swap_first_idx:
		return false

	var ok := Commander.hero_swap(game_state, _strategist_swap_first_idx, field_idx)
	cancel_strategist_swap()
	return ok


func _on_strategist_swap_pressed() -> void:
	if _strategist_swap_active:
		cancel_strategist_swap()
	else:
		begin_strategist_swap()


func _on_card_clicked(card_visual) -> void:
	if not _strategist_swap_active:
		return
	if card_visual.zone != "board":
		return
	_select_strategist_swap_slot(card_visual.slot_idx)


func _count_board_cards() -> int:
	var count := 0
	for card in game_state.board:
		if card != null:
			count += 1
	return count


func _update_strategist_swap_button() -> void:
	if strategist_swap_button == null or game_state == null:
		return
	var is_strategist := game_state.commander_type == Enums.CommanderType.STRATEGIST
	strategist_swap_button.visible = is_strategist
	if not is_strategist:
		return
	var used := bool(game_state.commander_state.get("hero_used", false))
	strategist_swap_button.disabled = used or _count_board_cards() < 2
	if used:
		strategist_swap_button.text = "SWAP USED"
	elif _strategist_swap_active and _strategist_swap_first_idx >= 0:
		strategist_swap_button.text = "PICK SECOND"
	elif _strategist_swap_active:
		strategist_swap_button.text = "PICK FIRST"
	else:
		strategist_swap_button.text = "SWAP (H)"


func _refresh_strategist_swap_highlights() -> void:
	for i in _field_visuals.size():
		var vis: Panel = _field_visuals[i]
		if not _strategist_swap_active or i >= game_state.board.size() or game_state.board[i] == null:
			if vis.has_method("refresh"):
				vis.call("refresh")
			continue
		_set_strategist_swap_highlight(vis, i == _strategist_swap_first_idx)


func _set_strategist_swap_highlight(vis: Panel, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.45, 0.9, 0.35) if selected else Color(0.2, 0.8, 0.8, 0.25)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.4, 0.75, 1.0) if selected else Color(0.3, 1.0, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	vis.add_theme_stylebox_override("panel", style)


# --- Upgrade purchase flow ---


func _on_upgrade_purchase_requested(upgrade_id: String, slot_idx: int) -> void:
	if _pending_detach_upgrade:
		cancel_rusty_wrench_detach()
	var cost: int = upgrade_shop.get_upgrade_cost(slot_idx)
	# Terazin already deducted by upgrade_shop. Refund on failure/cancel.
	game_state.upgrade_purchased.emit(upgrade_id, slot_idx, cost, game_state.terazin)
	var has_eligible := false
	for card in game_state.board:
		if card != null and (card as CardInstance).can_attach_upgrade():
			has_eligible = true
			break
	if not has_eligible:
		print("[UpgradeShop] No eligible field cards — refund %dt" % cost)
		game_state.terazin += cost
		game_state.upgrade_refunded.emit(upgrade_id, cost, "no_eligible_cards", game_state.terazin)
		game_state.state_changed.emit()
		return

	_pending_upgrade = {"upgrade_id": upgrade_id, "slot_idx": slot_idx, "cost": cost}
	_update_upgrade_reroll_button()
	_start_upgrade_target_selection(upgrade_id)
	_refresh_tutorial_hint()


func start_free_upgrade_selection(upgrade_id: String, source: String) -> void:
	_pending_upgrade = {
		"upgrade_id": upgrade_id,
		"slot_idx": -1,
		"cost": 0,
		"source": source,
		"free": true,
	}
	_start_upgrade_target_selection(upgrade_id)
	_refresh_tutorial_hint()


func _can_attach_upgrade_predicate(card) -> bool:
	if card == null:
		return false
	return (card as CardInstance).can_attach_upgrade()


func _on_target_selected(field_idx: int) -> void:
	if _pending_detach_upgrade:
		_pending_detach_upgrade = false
		detach_upgrade_from_field(field_idx)
		_update_detach_upgrade_button()
		return
	if _pending_upgrade.is_empty():
		return
	var card: CardInstance = game_state.board[field_idx]
	var upgrade_id: String = _pending_upgrade["upgrade_id"]
	if card == null or not card.can_attach_upgrade():
		print("[UpgradeShop] Card no longer eligible — refund %dt" % _pending_upgrade["cost"])
		_refund_pending_upgrade("card_invalid")
		return
	# Terazin already deducted — just attach
	card.attach_upgrade(upgrade_id)
	var slot_idx: int = int(_pending_upgrade.get("slot_idx", -1))
	if slot_idx >= 0:
		upgrade_shop.mark_sold(slot_idx)
	var source: String = _pending_upgrade.get("source", "shop")
	var was_free: bool = bool(_pending_upgrade.get("free", false))
	var upg_name: String = UpgradeDB.get_upgrade(upgrade_id).get("name", "???")
	print("[UpgradeShop] %s → %s (-%dt)" % [upg_name, card.get_name(), _pending_upgrade["cost"]])
	game_state.upgrade_attached_to_card.emit(upgrade_id, source, card.get_base_id(), field_idx)
	_pending_upgrade = {}
	if target_overlay:
		target_overlay.end_selection()
	game_state.state_changed.emit()
	if was_free:
		free_upgrade_finished.emit(true)


func _on_target_cancelled() -> void:
	if _pending_detach_upgrade:
		_pending_detach_upgrade = false
		_update_detach_upgrade_button()
		return
	if not _pending_upgrade.is_empty():
		var was_free: bool = bool(_pending_upgrade.get("free", false))
		if was_free:
			print("[UpgradeShop] Free upgrade target selection cancelled")
		else:
			print("[UpgradeShop] Cancelled — refund %dt" % _pending_upgrade["cost"])
		_refund_pending_upgrade("cancelled")


func _refund_pending_upgrade(reason: String = "unknown") -> void:
	var upgrade_id: String = _pending_upgrade.get("upgrade_id", "")
	var cost: int = _pending_upgrade.get("cost", 0)
	var was_free: bool = bool(_pending_upgrade.get("free", false))
	if not was_free:
		game_state.terazin += cost
	_pending_upgrade = {}
	if target_overlay:
		target_overlay.end_selection()
	if not was_free:
		game_state.upgrade_refunded.emit(upgrade_id, cost, reason, game_state.terazin)
	game_state.state_changed.emit()
	if was_free:
		free_upgrade_finished.emit(false)


# --- Rusty Wrench detach flow ---


func begin_rusty_wrench_detach() -> bool:
	if game_state == null:
		return false
	if _pending_detach_upgrade:
		return false
	if not _pending_upgrade.is_empty():
		return false
	if _strategist_swap_active:
		return false
	if not Talisman.can_detach_upgrade(game_state):
		return false
	if not _has_detachable_upgrade_target():
		return false
	_pending_detach_upgrade = true
	_update_detach_upgrade_button()
	if target_overlay != null:
		target_overlay.start_selection(_field_visuals, game_state.board,
			Callable(self, "_can_detach_upgrade_predicate"))
	return true


func cancel_rusty_wrench_detach() -> void:
	if not _pending_detach_upgrade:
		return
	_pending_detach_upgrade = false
	if target_overlay != null:
		target_overlay.end_selection()
	_update_detach_upgrade_button()


func detach_upgrade_from_field(field_idx: int) -> bool:
	if game_state == null:
		return false
	if not Talisman.can_detach_upgrade(game_state):
		return false
	if field_idx < 0 or field_idx >= game_state.board.size():
		return false
	var card: CardInstance = game_state.board[field_idx]
	if card == null or card.upgrades.is_empty():
		return false
	var upgrade_idx := card.upgrades.size() - 1
	var upgrade_id := String(card.upgrades[upgrade_idx].get("id", ""))
	var upgrade_count_before := card.upgrades.size()
	var refund := Talisman.detach_upgrade(game_state, card, upgrade_idx)
	if card.upgrades.size() != upgrade_count_before - 1:
		return false
	game_state.upgrade_refunded.emit(upgrade_id, refund, "rusty_wrench_detach", game_state.terazin)
	game_state.state_changed.emit()
	return true


func _on_detach_upgrade_pressed() -> void:
	if _pending_detach_upgrade:
		cancel_rusty_wrench_detach()
	else:
		begin_rusty_wrench_detach()


func _has_detachable_upgrade_target() -> bool:
	if game_state == null:
		return false
	for card in game_state.board:
		if _can_detach_upgrade_predicate(card):
			return true
	return false


func _can_detach_upgrade_predicate(card) -> bool:
	return card != null and not (card as CardInstance).upgrades.is_empty()


func _start_upgrade_target_selection(upgrade_id: String) -> void:
	if target_overlay == null:
		return
	var upg := UpgradeDB.get_upgrade(upgrade_id)
	var upg_name: String = upg.get("name", upgrade_id)
	var effect := _format_upgrade_preview(upg)
	var detail := "%s" % upg_name
	if effect != "":
		detail += " — %s" % effect
	var source: String = _pending_upgrade.get("source", "shop")
	target_overlay.start_selection(_field_visuals, game_state.board,
		Callable(self, "_can_attach_upgrade_predicate"), {
			"instruction": _format_upgrade_target_instruction(upg_name, source),
			"detail": detail,
			"note_formatter": Callable(self, "_format_upgrade_target_note").bind(upgrade_id),
		})


func _format_upgrade_target_instruction(upg_name: String, source: String) -> String:
	match source:
		"smith_start":
			return "Smith bonus: attach %s (ESC to cancel)" % upg_name
		"raider_win_streak":
			return "Raider 3-win reward: attach %s (ESC to skip)" % upg_name
	return "Attach %s (ESC to cancel/refund)" % upg_name


func _format_upgrade_target_note(card, eligible: bool, _field_idx: int,
		upgrade_id: String) -> String:
	if card == null:
		return ""
	var target: CardInstance = card
	var used := target.upgrades.size()
	var max_slots := target.get_max_upgrade_slots()
	var slots := "Slots %d/%d -> %d/%d" % [
		used, max_slots, used + 1, max_slots] if eligible else "FULL %d/%d" % [
		used, max_slots]
	var effect := _format_upgrade_preview(UpgradeDB.get_upgrade(upgrade_id))
	return slots if effect == "" else "%s\n%s" % [slots, effect]


func _format_upgrade_preview(tmpl: Dictionary) -> String:
	if tmpl.is_empty():
		return ""
	var parts: PackedStringArray = []
	var mods: Dictionary = tmpl.get("stat_mods", {})
	if mods.has("atk_pct"):
		parts.append("ATK +%d%%" % int(float(mods["atk_pct"]) * 100))
	if mods.has("hp_pct"):
		parts.append("HP +%d%%" % int(float(mods["hp_pct"]) * 100))
	if mods.has("def"):
		parts.append("DEF +%d" % int(mods["def"]))
	if mods.has("range"):
		parts.append("Range +%d" % int(mods["range"]))
	if mods.has("move_speed"):
		parts.append("MS +%d" % int(mods["move_speed"]))
	if mods.has("as_mult"):
		var pct := int((1.0 - float(mods["as_mult"])) * 100)
		parts.append("AS +%d%%" % pct)
	for mechanic in tmpl.get("mechanics", []):
		parts.append(_format_upgrade_mechanic_preview(mechanic))
	return ", ".join(parts)


func _format_upgrade_mechanic_preview(mechanic: Dictionary) -> String:
	match mechanic.get("type", ""):
		"thorns": return "Reflect %d%%" % int(float(mechanic["reflect_pct"]) * 100)
		"battle_start_heal": return "Start heal %d%%" % int(float(mechanic["heal_hp_pct"]) * 100)
		"armor_pierce": return "Ignore DEF %d%%" % int(float(mechanic["ignore_def_pct"]) * 100)
		"focus_fire": return "Focus +%d%%/hit" % int(float(mechanic["stack_atk_pct"]) * 100)
		"battle_start_shield": return "Shield HP %d%%" % int(float(mechanic["shield_hp_pct"]) * 100)
		"lifesteal": return "Lifesteal %d%%" % int(float(mechanic["steal_pct"]) * 100)
		"splash": return "Splash %d%%" % int(float(mechanic["splash_pct"]) * 100)
		"phase_shift": return "First hit blocked"
		"tactical_retreat": return "Retreat below %d%% HP" % int(float(mechanic["hp_threshold"]) * 100)
		"chain_discharge": return "Kill chain %d%%" % int(float(mechanic["chain_dmg_pct"]) * 100)
		"regen": return "Regen %d%%" % int(float(mechanic["heal_hp_pct"]) * 100)
		"slow_aura": return "Slow %d%%" % int(float(mechanic["slow_pct"]) * 100)
		"critical": return "Crit %d%%" % int(float(mechanic["crit_chance"]) * 100)
		"berserk": return "Berserk"
		"chain_explosion": return "Kill explosion"
		"immortal_core": return "Immortal core"
		"soul_harvest": return "Soul harvest"
		"fission": return "Fission"
		"hp_percent_dmg": return "Current HP damage"
	return str(mechanic.get("type", "???"))


func _update_detach_upgrade_button() -> void:
	if detach_upgrade_button == null or game_state == null:
		return
	var can_detach := Talisman.can_detach_upgrade(game_state)
	detach_upgrade_button.visible = can_detach
	if not can_detach:
		return
	detach_upgrade_button.disabled = not _has_detachable_upgrade_target()
	detach_upgrade_button.text = "PICK CARD" if _pending_detach_upgrade else "DETACH (D)"


func _on_upgrade_reroll_pressed() -> void:
	reroll_upgrades()


func _update_upgrade_reroll_button() -> void:
	if upgrade_reroll_button == null or game_state == null or upgrade_shop == null:
		return
	var upg_visible: bool = upgrade_shop.is_available()
	upgrade_reroll_button.visible = upg_visible
	if not upg_visible:
		return
	upgrade_reroll_button.text = "UPG REROLL (T) -%dT" % Enums.UPGRADE_REROLL_COST
	upgrade_reroll_button.disabled = not can_reroll_upgrades()


# --- Merge bonus flow ---


func _on_card_merged(card: CardInstance, old_star: int, new_star: int) -> void:
	merge_performed.emit(card)
	var summary_tags: PackedStringArray = []

	if old_star == 1 and new_star == 2:
		_pending_merge_card = card
		summary_tags.append("무료 Rare 업그레이드")
		if _upgrade_choice_popup != null:
			_upgrade_choice_popup.show_choices(Enums.UpgradeRarity.RARE, 3)
	elif old_star == 2 and new_star == 3:
		# 캐스케이드 ★1→★2→★3: step1 ★2 survivor 가 step2 에서 도너로 흡수돼
		# 사라지므로, free rare 부착 대상을 ★3 최종 survivor 로 이전.
		if _pending_merge_card != null and _pending_merge_card != card:
			_pending_merge_card = card
			summary_tags.append("보상 대상 이전")
		else:
			summary_tags.append("최종 합성")
	_record_merge_summary(card, old_star, new_star, summary_tags)


func _record_merge_summary(card: CardInstance, old_star: int, new_star: int,
		tags: PackedStringArray) -> void:
	var card_name := card.get_name() if card != null else "Unknown"
	_last_merge_summary = "MERGE: %s ★%d -> ★%d" % [card_name, old_star, new_star]
	if not tags.is_empty():
		_last_merge_summary += " · " + " · ".join(tags)
	_merge_history.insert(0, _last_merge_summary)
	while _merge_history.size() > merge_history_max:
		_merge_history.remove_at(_merge_history.size() - 1)
	_refresh_merge_history_panel()
	_refresh_settlement_recap_panel()
	_refresh_tutorial_hint()


func _on_merge_upgrade_chosen(upgrade_id: String) -> void:
	if _pending_merge_card == null:
		return
	if not _pending_merge_card.can_attach_upgrade():
		print("[MergeBonus] Card upgrade slots full, bonus lost")
		_pending_merge_card = null
		return
	_pending_merge_card.attach_upgrade(upgrade_id)
	var upg_name: String = UpgradeDB.get_upgrade(upgrade_id).get("name", "???")
	print("[MergeBonus] %s → %s" % [upg_name, _pending_merge_card.get_name()])
	# 머지 보너스 부착 → board/bench 에서 인덱스를 찾아 emit.
	var target_idx := _find_card_index(_pending_merge_card)
	game_state.upgrade_attached_to_card.emit(
		upgrade_id, "merge_bonus", _pending_merge_card.get_base_id(), target_idx)
	_pending_merge_card = null
	game_state.state_changed.emit()


func _show_floating_gold(at_pos: Vector2, amount: int) -> void:
	var lbl := Label.new()
	lbl.text = "+%dg" % amount
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.global_position = at_pos + Vector2(20, -10)
	lbl.z_index = 100
	add_child(lbl)
	var tween := create_tween()
	tween.tween_property(lbl, "global_position:y", lbl.global_position.y - 40, 0.8)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.tween_callback(lbl.queue_free)


func _find_card_index(card: CardInstance) -> int:
	for i in game_state.board.size():
		if game_state.board[i] == card:
			return i
	return -1
