extends RefCounted
## Observer/driver for live-scene UI ownership.

const RUN_START := "run_start"
const COMMANDER_SELECT := "commander_select"
const TALISMAN_SELECT := "talisman_select"
const UPGRADE_CHOICE := "upgrade_choice"
const BOSS_REWARD := "boss_reward"
const TARGET_SELECT := "target_select"
const THEME_CHOICE := "theme_choice"
const BATTLE_RESULT := "battle_result"
const GAME_OVER := "game_over"

const _PHASE_NAMES := ["INIT", "BUILD", "CHAIN", "BATTLE", "SETTLEMENT"]


static func snapshot(main) -> Dictionary:
	var active_modals: Array[String] = []
	var choices: Dictionary = {}
	var actionable: Dictionary = {}

	_record_simple_modal(main.run_start_screen, RUN_START, active_modals,
		actionable, _run_start_actionable(main))
	_record_grid_modal(main.commander_select_popup, COMMANDER_SELECT,
		active_modals, choices, actionable, "Commander_")
	_record_grid_modal(main.talisman_select_popup, TALISMAN_SELECT,
		active_modals, choices, actionable, "Talisman_")
	_record_choice_id_modal(main.upgrade_choice_popup, UPGRADE_CHOICE,
		active_modals, choices, actionable)
	_record_choice_id_modal(main.boss_reward_popup, BOSS_REWARD,
		active_modals, choices, actionable)
	_record_target_select_modal(main.build_phase.target_overlay, active_modals,
		choices, actionable)
	_record_theme_modal(main.theme_choice_popup, active_modals, choices,
		actionable)
	_record_simple_modal(main.battle_result_popup, BATTLE_RESULT, active_modals,
		actionable, false)
	_record_simple_modal(main.game_over_popup, GAME_OVER, active_modals,
		actionable, main.game_over_popup.visible)

	return {
		"phase": _phase_name(main),
		"round": main.game_state.round_num if main.game_state != null else 0,
		"active_modals": active_modals,
		"has_modal": not active_modals.is_empty(),
		"choices": choices,
		"actionable": actionable,
		"commander_select": _choice_card_details(main.commander_select_popup),
		"talisman_select": _choice_card_details(main.talisman_select_popup),
		"target_select": _target_select_details(main.build_phase.target_overlay),
		"chain_feedback": _chain_feedback_details(main),
		"last_chain_history": _last_chain_history_details(main),
		"merge_history": _merge_history_details(main),
		"identity": _identity_details(main),
		"run_milestone": _run_milestone_details(main),
		"build_readiness": _build_readiness_details(main),
		"enemy_pressure_preview": _enemy_pressure_preview_details(main),
		"last_settlement_recap": _last_settlement_recap_details(main),
		"shop": _shop_details(main),
			"run_start": _run_start_details(main),
			"boss_reward": _boss_reward_details(main),
			"battle_status": _battle_status_details(main),
			"battle_result": _battle_result_details(main),
			"game_over": _game_over_details(main),
		"layout_rects": _layout_rects(main),
		"build_visible": main.build_phase.visible,
		"chain_visible": main.chain_visual.visible,
		"battle_result_visible": main.battle_result_popup.visible,
		"game_over_visible": main.game_over_popup.visible,
	}


static func press_run_start(main) -> bool:
	if not main.run_start_screen.visible:
		return false
	var button: Button = main.run_start_screen.get_node("VBox/StartButton") as Button
	if button == null or button.disabled:
		return false
	button.pressed.emit()
	return true


static func select_commander(main, commander_type: int) -> bool:
	if not main.commander_select_popup.visible:
		return false
	var choices := _grid_choice_values(main.commander_select_popup, "Commander_")
	if not (str(commander_type) in choices):
		return false
	main.commander_select_popup.select_commander(commander_type)
	return true


static func select_talisman(main, talisman_type: int) -> bool:
	if not main.talisman_select_popup.visible:
		return false
	var choices := _grid_choice_values(main.talisman_select_popup, "Talisman_")
	if not (str(talisman_type) in choices):
		return false
	main.talisman_select_popup.select_talisman(talisman_type)
	return true


static func select_choice(main, modal_id: String, idx: int) -> bool:
	match modal_id:
		UPGRADE_CHOICE:
			if not main.upgrade_choice_popup.visible:
				return false
			return main.upgrade_choice_popup.select_choice_index(idx)
		BOSS_REWARD:
			if not main.boss_reward_popup.visible:
				return false
			return main.boss_reward_popup.select_choice_index(idx)
	return false


static func choice_ids(main, modal_id: String) -> Array[String]:
	match modal_id:
		UPGRADE_CHOICE:
			return main.upgrade_choice_popup.get_choice_ids()
		BOSS_REWARD:
			return main.boss_reward_popup.get_choice_ids()
	return []


static func select_target(main, field_idx: int) -> bool:
	if main.build_phase == null or main.build_phase.target_overlay == null:
		return false
	var overlay = main.build_phase.target_overlay
	if not overlay.has_method("select_field_index"):
		return false
	return bool(overlay.call("select_field_index", field_idx))


static func target_field_indices(main) -> Array[int]:
	if main.build_phase == null or main.build_phase.target_overlay == null:
		return []
	var overlay = main.build_phase.target_overlay
	if not overlay.has_method("get_selectable_field_indices"):
		return []
	var raw: Array = overlay.call("get_selectable_field_indices")
	var result: Array[int] = []
	for idx in raw:
		result.append(int(idx))
	return result


static func _record_simple_modal(node: CanvasItem, modal_id: String,
		active_modals: Array[String], actionable: Dictionary,
		is_actionable: bool) -> void:
	if node == null or not node.visible:
		return
	active_modals.append(modal_id)
	actionable[modal_id] = is_actionable


static func _record_grid_modal(popup: CanvasItem, modal_id: String,
		active_modals: Array[String], choices: Dictionary,
		actionable: Dictionary, prefix: String) -> void:
	if popup == null or not popup.visible:
		return
	var values := _grid_choice_values(popup, prefix)
	active_modals.append(modal_id)
	choices[modal_id] = values
	actionable[modal_id] = not values.is_empty()


static func _record_choice_id_modal(popup: CanvasItem, modal_id: String,
		active_modals: Array[String], choices: Dictionary,
		actionable: Dictionary) -> void:
	if popup == null or not popup.visible:
		return
	var ids: Array[String] = popup.call("get_choice_ids")
	active_modals.append(modal_id)
	choices[modal_id] = ids
	actionable[modal_id] = not ids.is_empty()


static func _record_target_select_modal(overlay: CanvasItem,
		active_modals: Array[String], choices: Dictionary,
		actionable: Dictionary) -> void:
	if overlay == null or not overlay.visible:
		return
	var indices: Array[int] = []
	if overlay.has_method("get_selectable_field_indices"):
		var raw: Array = overlay.call("get_selectable_field_indices")
		for idx in raw:
			indices.append(int(idx))
	active_modals.append(TARGET_SELECT)
	choices[TARGET_SELECT] = indices
	actionable[TARGET_SELECT] = not indices.is_empty()


static func _record_theme_modal(popup: CanvasItem, active_modals: Array[String],
		choices: Dictionary, actionable: Dictionary) -> void:
	if popup == null or not popup.visible:
		return
	var texts: Array[String] = []
	for child in popup.get_node("VBox/ChoiceContainer").get_children():
		if child is Button:
			texts.append((child as Button).text)
	active_modals.append(THEME_CHOICE)
	choices[THEME_CHOICE] = texts
	actionable[THEME_CHOICE] = not texts.is_empty()


static func _grid_choice_values(popup: CanvasItem, prefix: String) -> Array[String]:
	var values: Array[String] = []
	var grid := popup.get_node("VBox/ChoiceGrid")
	for child in grid.get_children():
		var child_name := str(child.name)
		if child_name.begins_with(prefix):
			values.append(child_name.trim_prefix(prefix))
	return values


static func _run_start_actionable(main) -> bool:
	if main.run_start_screen == null or not main.run_start_screen.visible:
		return false
	var button: Button = main.run_start_screen.get_node("VBox/StartButton") as Button
	return button != null and not button.disabled


static func _target_select_details(overlay: CanvasItem) -> Dictionary:
	if overlay == null or not overlay.visible:
		return {}
	var previews: Array[String] = []
	if overlay.has_method("get_preview_texts"):
		var raw_previews: Array = overlay.call("get_preview_texts")
		for text in raw_previews:
			previews.append(str(text))
	var instruction := ""
	if overlay.has_method("get_instruction_text"):
		instruction = str(overlay.call("get_instruction_text"))
	var detail := ""
	if overlay.has_method("get_detail_text"):
		detail = str(overlay.call("get_detail_text"))
	return {
		"instruction": instruction,
		"detail": detail,
		"preview_texts": previews,
	}


static func _choice_card_details(popup: CanvasItem) -> Dictionary:
	if popup == null or not popup.visible:
		return {}
	var details := {
		"choice_summaries": [],
		"context_text": "",
		"context_rect": {},
	}
	if popup.has_method("get_context_text"):
		details["context_text"] = str(popup.call("get_context_text"))
	if popup.has_method("get_context_rect"):
		details["context_rect"] = popup.call("get_context_rect")
	if popup.has_method("get_choice_summaries"):
		details["choice_summaries"] = popup.call("get_choice_summaries")
	return details


static func _layout_rects(main) -> Dictionary:
	if main == null or main.build_phase == null:
		return {}
	var build_phase = main.build_phase
	return {
		"target_instruction": _control_rect(
			build_phase.get_node_or_null("TargetSelectOverlay/InstructionLabel") as Control),
		"target_detail": _control_rect(
			build_phase.get_node_or_null("TargetSelectOverlay/DetailLabel") as Control),
		"confirm_button": _control_rect(
			build_phase.get_node_or_null("ConfirmButton") as Control),
		"field_container": _control_rect(
			build_phase.get_node_or_null("FieldContainer") as Control),
		"identity_label": _control_rect(
			build_phase.get_node_or_null("HUD/IdentityLabel") as Control),
		"round_label": _control_rect(
			build_phase.get_node_or_null("HUD/RoundLabel") as Control),
		"tutorial_panel": _control_rect(
			build_phase.get_node_or_null("TutorialHintPanel") as Control),
		"last_chain_panel": _control_rect(
			build_phase.get_node_or_null("LastChainPanel") as Control),
		"build_readiness_panel": _control_rect(
			build_phase.get_node_or_null("BuildReadinessPanel") as Control),
		"settlement_recap_panel": _control_rect(
			build_phase.get_node_or_null("SettlementRecapPanel") as Control),
		"hp_label": _control_rect(
			build_phase.get_node_or_null("HUD/HPLabel") as Control),
		"gold_label": _control_rect(
			build_phase.get_node_or_null("HUD/GoldLabel") as Control),
		"terazin_label": _control_rect(
			build_phase.get_node_or_null("HUD/TerazinLabel") as Control),
		"chain_counter": _control_rect(
			main.chain_visual.get_node_or_null("EventPanel/VBox/CounterLabel") as Control),
		"chain_event_panel": _control_rect(
			main.chain_visual.get_node_or_null("EventPanel") as Control),
		"battle_status": _control_rect(
			main.battle_phase.get_node_or_null("CanvasLayer/StatusLabel") as Control),
		"boss_reward_popup": _control_rect(main.boss_reward_popup as Control),
		"battle_result_popup": _control_rect(main.battle_result_popup as Control),
	}


static func _chain_feedback_details(main) -> Dictionary:
	if main == null or main.chain_visual == null:
		return {}
	if not main.chain_visual.visible:
		return {}
	var details := {
		"counter_text": "",
		"event_log_text": "",
		"event_panel_visible": false,
	}
	if main.chain_visual.has_method("get_event_log_text"):
		details["event_log_text"] = main.chain_visual.call("get_event_log_text")
	var counter: Label = main.chain_visual.get_node_or_null(
		"EventPanel/VBox/CounterLabel") as Label
	if counter != null:
		details["counter_text"] = counter.text
	var event_panel: Control = main.chain_visual.get_node_or_null("EventPanel") as Control
	if event_panel != null:
		details["event_panel_visible"] = event_panel.is_visible_in_tree()
	return details


static func _last_chain_history_details(main) -> Dictionary:
	if main == null or main.build_phase == null:
		return {}
	var details := {
		"display_text": "",
		"visible": false,
		"text": "",
	}
	if main.build_phase.has_method("is_last_chain_history_visible"):
		details["visible"] = bool(main.build_phase.call("is_last_chain_history_visible"))
	if main.build_phase.has_method("get_last_chain_history_display_text"):
		details["display_text"] = str(main.build_phase.call(
			"get_last_chain_history_display_text"))
	if main.build_phase.has_method("get_last_chain_history_text"):
		details["text"] = str(main.build_phase.call("get_last_chain_history_text"))
	return details


static func _merge_history_details(main) -> Dictionary:
	if main == null or main.build_phase == null:
		return {}
	var details := {
		"entries": [],
		"text": "",
		"visible": false,
	}
	if main.build_phase.has_method("is_merge_history_visible"):
		details["visible"] = bool(main.build_phase.call("is_merge_history_visible"))
	if main.build_phase.has_method("get_merge_history_text"):
		details["text"] = str(main.build_phase.call("get_merge_history_text"))
	if main.build_phase.has_method("get_merge_history_entries"):
		details["entries"] = main.build_phase.call("get_merge_history_entries")
	return details


static func _identity_details(main) -> Dictionary:
	if main == null or main.build_phase == null:
		return {}
	var identity_control := main.build_phase.get_node_or_null("HUD/IdentityLabel") as Control
	var details := {
		"text": "",
		"visible": identity_control != null and identity_control.is_visible_in_tree(),
		"rect": _control_rect(identity_control),
	}
	if main.build_phase.has_method("get_identity_text"):
		details["text"] = str(main.build_phase.call("get_identity_text"))
	else:
		details["text"] = _label_text(main.build_phase, "HUD/IdentityLabel")
	return details


static func _run_milestone_details(main) -> Dictionary:
	if main == null or main.build_phase == null:
		return {}
	var round_control := main.build_phase.get_node_or_null("HUD/RoundLabel") as Control
	var details := {
		"text": "",
		"round_label_text": "",
		"visible": round_control != null and round_control.is_visible_in_tree(),
		"rect": _control_rect(round_control),
	}
	if main.build_phase.has_method("get_run_milestone_text"):
		details["text"] = str(main.build_phase.call("get_run_milestone_text"))
	if main.build_phase.has_method("get_round_label_text"):
		details["round_label_text"] = str(main.build_phase.call("get_round_label_text"))
	else:
		details["round_label_text"] = _label_text(main.build_phase, "HUD/RoundLabel")
	return details


static func _build_readiness_details(main) -> Dictionary:
	if main == null or main.build_phase == null:
		return {}
	var readiness_control := main.build_phase.get_node_or_null(
		"BuildReadinessPanel") as Control
	var details := {
		"text": "",
		"visible": readiness_control != null and readiness_control.is_visible_in_tree(),
		"rect": _control_rect(readiness_control),
	}
	if main.build_phase.has_method("get_build_readiness_text"):
		details["text"] = str(main.build_phase.call("get_build_readiness_text"))
	return details


static func _enemy_pressure_preview_details(main) -> Dictionary:
	if main == null or main.build_phase == null:
		return {}
	var readiness_control := main.build_phase.get_node_or_null(
		"BuildReadinessPanel") as Control
	var details := {
		"text": "",
		"visible": readiness_control != null and readiness_control.is_visible_in_tree(),
		"rect": _control_rect(readiness_control),
		"data": {},
	}
	if main.build_phase.has_method("get_enemy_pressure_preview_text"):
		details["text"] = str(main.build_phase.call(
			"get_enemy_pressure_preview_text"))
	if main.build_phase.has_method("get_enemy_pressure_preview_data"):
		details["data"] = main.build_phase.call("get_enemy_pressure_preview_data")
	return details


static func _battle_status_details(main) -> Dictionary:
	if main == null or main.battle_phase == null:
		return {}
	var status_control := main.battle_phase.get_node_or_null(
		"CanvasLayer/StatusLabel") as Control
	var details := {
		"text": _label_text(main.battle_phase, "CanvasLayer/StatusLabel"),
		"visible": status_control != null and status_control.is_visible_in_tree(),
		"rect": _control_rect(status_control),
		"data": {},
	}
	if main.battle_phase.has_method("get_status_details"):
		var data: Dictionary = main.battle_phase.call("get_status_details")
		details["data"] = data
		if str(data.get("text", "")) != "":
			details["text"] = str(data.get("text", ""))
		if data.has("visible"):
			details["visible"] = bool(data.get("visible", false))
	return details


static func _last_settlement_recap_details(main) -> Dictionary:
	if main == null or main.build_phase == null:
		return {}
	var details := {
		"data": {},
		"text": "",
		"visible": false,
	}
	if main.build_phase.has_method("is_last_settlement_recap_visible"):
		details["visible"] = bool(main.build_phase.call(
			"is_last_settlement_recap_visible"))
	if main.build_phase.has_method("get_last_settlement_recap_text"):
		details["text"] = str(main.build_phase.call(
			"get_last_settlement_recap_text"))
	if main.build_phase.has_method("get_last_settlement_recap_data"):
		details["data"] = main.build_phase.call("get_last_settlement_recap_data")
	return details


static func _shop_details(main) -> Dictionary:
	if main == null or main.build_phase == null:
		return {}
	var build_phase = main.build_phase
	var details := {
		"shop_label_text": _label_text(build_phase, "ShopLabel"),
		"upgrade_shop_label_text": _label_text(build_phase, "UpgradeShopLabel"),
		"upgrade_reroll_button_text": _button_text(
			build_phase, "UpgradeRerollButton"),
		"upgrade_reroll_button_disabled": _button_disabled(
			build_phase, "UpgradeRerollButton"),
		"upgrade_reroll_button_visible": _control_visible(
			build_phase, "UpgradeRerollButton"),
		"card_offer_ids": [],
		"upgrade_offer_ids": [],
		"card_offer_costs": [],
		"card_offer_roles": [],
		"upgrade_offer_costs": [],
	}
	if build_phase.shop != null:
		details["card_offer_ids"] = _string_ids(build_phase.shop._offered_ids)
		var card_costs: Array[int] = []
		var card_roles: Array[Dictionary] = []
		for i in build_phase.shop._offered_ids.size():
			card_costs.append(int(build_phase.shop.get_slot_cost(i)))
			card_roles.append(_shop_card_role_summary(build_phase.shop, i))
		details["card_offer_costs"] = card_costs
		details["card_offer_roles"] = card_roles
	if build_phase.upgrade_shop != null:
		details["upgrade_offer_ids"] = _string_ids(
			build_phase.upgrade_shop._offered_ids)
		var upgrade_costs: Array[int] = []
		for i in build_phase.upgrade_shop._offered_ids.size():
			upgrade_costs.append(int(build_phase.upgrade_shop.get_upgrade_cost(i)))
		details["upgrade_offer_costs"] = upgrade_costs
	return details


static func _shop_card_role_summary(shop, slot_idx: int) -> Dictionary:
	var offered_ids: Array = shop._offered_ids
	var card_id := ""
	if slot_idx >= 0 and slot_idx < offered_ids.size():
		card_id = str(offered_ids[slot_idx])
	var visual: Control = null
	if slot_idx >= 0 and slot_idx < shop._shop_slots.size():
		visual = shop._shop_slots[slot_idx] as Control
	var role_text := ""
	var tier_text := ""
	if visual != null and visual.has_method("get_face_role_text"):
		role_text = str(visual.call("get_face_role_text"))
	if visual != null and visual.has_method("get_face_tier_text"):
		tier_text = str(visual.call("get_face_tier_text"))
	var tmpl: Dictionary = CardDB.get_template(card_id)
	return {
		"slot_idx": slot_idx,
		"card_id": card_id,
		"name": str(tmpl.get("name", card_id)),
		"role_text": role_text,
		"tier_text": tier_text,
		"visible": visual != null and visual.is_visible_in_tree(),
		"rect": _control_rect(visual),
	}


static func _boss_reward_details(main) -> Dictionary:
	if main == null or main.boss_reward_popup == null:
		return {}
	if not main.boss_reward_popup.visible:
		return {}
	var popup = main.boss_reward_popup
	var details := {
		"title": "",
		"choice_summaries": [],
	}
	var title_label := popup.get_node_or_null("VBox/TitleLabel") as Label
	if title_label != null:
		details["title"] = title_label.text
	if popup.has_method("get_choice_summaries"):
		details["choice_summaries"] = popup.call("get_choice_summaries")
	return details


static func _battle_result_details(main) -> Dictionary:
	if main == null or main.battle_result_popup == null:
		return {}
	if not main.battle_result_popup.visible:
		return {}
	var popup = main.battle_result_popup
	var details := {
		"result_text": "",
		"detail_text": "",
		"summary_text": "",
		"context": {},
	}
	if popup.has_method("get_result_text"):
		details["result_text"] = str(popup.call("get_result_text"))
	if popup.has_method("get_detail_text"):
		details["detail_text"] = str(popup.call("get_detail_text"))
	if popup.has_method("get_summary_text"):
		details["summary_text"] = str(popup.call("get_summary_text"))
	if popup.has_method("get_context"):
		details["context"] = popup.call("get_context")
	return details


static func _run_start_details(main) -> Dictionary:
	if main == null or main.run_start_screen == null:
		return {}
	if not main.run_start_screen.visible:
		return {}
	var screen = main.run_start_screen
	return {
		"stats_text": _label_text(screen, "VBox/StatsLabel"),
		"difficulty_text": _label_text(screen, "VBox/DifficultyRow/DifficultyLabel"),
		"difficulty_down_disabled": _button_disabled(screen,
			"VBox/DifficultyRow/DifficultyDownButton"),
		"difficulty_up_disabled": _button_disabled(screen,
			"VBox/DifficultyRow/DifficultyUpButton"),
		"details_button_text": _button_text(screen, "VBox/ProgressDetailsButton"),
		"details_visible": _control_visible(screen, "VBox/ProgressDetailsScroll"),
		"details_text": _label_text(
			screen, "VBox/ProgressDetailsScroll/ProgressDetailsLabel"),
		"start_button_disabled": _button_disabled(screen, "VBox/StartButton"),
		"profile_text": _label_text(screen, "VBox/ProfileLabel"),
		"unlocks_text": _label_text(screen, "VBox/UnlocksLabel"),
		"recent_unlocks_text": _label_text(screen, "VBox/RecentUnlocksLabel"),
		"goals_text": _label_text(screen, "VBox/GoalsLabel"),
		"guide_text": _label_text(screen, "VBox/GuideLabel"),
	}


static func _game_over_details(main) -> Dictionary:
	if main == null or main.game_over_popup == null:
		return {}
	if not main.game_over_popup.visible:
		return {}
	var popup = main.game_over_popup
	return {
		"title_text": _label_text(popup, "VBox/TitleLabel"),
		"summary_text": _label_text(popup, "VBox/SummaryLabel"),
	}


static func _label_text(root: Node, path: String) -> String:
	var label := root.get_node_or_null(path) as Label
	if label == null:
		return ""
	return label.text


static func _button_text(root: Node, path: String) -> String:
	var button := root.get_node_or_null(path) as Button
	if button == null:
		return ""
	return button.text


static func _button_disabled(root: Node, path: String) -> bool:
	var button := root.get_node_or_null(path) as Button
	if button == null:
		return true
	return button.disabled


static func _control_visible(root: Node, path: String) -> bool:
	var control := root.get_node_or_null(path) as Control
	if control == null:
		return false
	return control.is_visible_in_tree()


static func _string_ids(value: Array) -> Array[String]:
	var result: Array[String] = []
	for item in value:
		result.append(str(item))
	return result


static func _control_rect(control: Control) -> Dictionary:
	if control == null:
		return {}
	var rect := control.get_global_rect()
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"w": rect.size.x,
		"h": rect.size.y,
		"visible": control.is_visible_in_tree(),
	}


static func _phase_name(main) -> String:
	var idx := int(main.current_phase)
	if idx < 0 or idx >= _PHASE_NAMES.size():
		return str(idx)
	return _PHASE_NAMES[idx]
