extends Node
## Live UI smoke reporter.
##
## Example:
## godot --headless --path godot/ res://tools/live_ui_smoke_report.tscn -- \
##   --out=/private/tmp/warforge_live_ui_smoke.json \
##   --screenshot-dir=/private/tmp/warforge_live_ui_smoke_shots

const LiveUiProbe = preload("res://tools/live_ui_probe.gd")

const DEFAULT_META_PATH := "user://meta_progress_live_ui_smoke_report.cfg"
const DEFAULT_COMMANDER := "gambler"
const DEFAULT_TALISMAN := "flint"

const COMMANDER_IDS := {
	"none": 0,
	"gambler": 1,
	"breeder": 2,
	"smith": 3,
	"strategist": 4,
	"collector": 5,
	"raider": 6,
	"alchemist": 7,
}
const TALISMAN_IDS := {
	"none": 0,
	"burst_sack": 1,
	"war_drum": 2,
	"mercury_drop": 3,
	"glass_eye": 4,
	"two_faced_coin": 5,
	"golden_die": 6,
	"cracked_egg": 7,
	"flint": 8,
	"cracked_skull": 9,
	"rusty_wrench": 10,
	"soul_jar": 11,
	"copper_wire": 12,
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := _parse_args()
	var commander_type := _parse_named_id(
		args.get("commander", DEFAULT_COMMANDER), COMMANDER_IDS, "commander")
	var talisman_type := _parse_named_id(
		args.get("talisman", DEFAULT_TALISMAN), TALISMAN_IDS, "talisman")
	if commander_type < 0 or talisman_type < 0:
		get_tree().quit(2)
		return

	var meta_path: String = str(args.get("meta-path", DEFAULT_META_PATH))
	var reset_meta: bool = _bool_arg(args, "reset-meta", true)
	var screenshot_dir: String = str(args.get("screenshot-dir", ""))
	var report: Dictionary = await _run_report(commander_type, talisman_type,
		meta_path, reset_meta, screenshot_dir)

	var out_path: String = str(args.get("out", ""))
	if out_path != "":
		var write_err := _write_json(out_path, report)
		if write_err != OK:
			printerr("ERROR: failed to write report %s: %s" % [
			out_path, error_string(write_err)])
			get_tree().quit(1)
			return

	print(JSON.stringify(report, "\t"))
	get_tree().quit(0 if bool(report.get("ok", false)) else 1)


func _run_report(commander_type: int, talisman_type: int, meta_path: String,
		reset_meta: bool, screenshot_dir: String = "") -> Dictionary:
	var report := {
		"schema": "warforge-live-ui-smoke/v1",
		"ok": false,
		"metadata": {
			"meta_path": meta_path,
			"reset_meta": reset_meta,
			"screenshot_dir": _global_path(screenshot_dir),
			"screenshot_status": "disabled" if screenshot_dir == "" else "requested",
			"display_server": DisplayServer.get_name(),
			"commander_type": commander_type,
			"commander_name": _autoload_data("Commander", commander_type).get(
				"name", str(commander_type)),
			"talisman_type": talisman_type,
			"talisman_name": _autoload_data("Talisman", talisman_type).get(
				"name", str(talisman_type)),
		},
		"steps": [],
		"events": {},
		"screenshots": [],
		"errors": [],
	}

	if screenshot_dir != "":
		if DisplayServer.get_name() == "headless":
			report["metadata"]["screenshot_status"] = "unsupported"
			_fail(report,
				"screenshot-dir requires a rendering display; current display server is headless")
		else:
			var screenshot_dir_err := _ensure_dir(screenshot_dir)
			if screenshot_dir_err != OK:
				_fail(report, "failed to create screenshot dir %s: %s" % [
					screenshot_dir, error_string(screenshot_dir_err)])
				return report
			report["metadata"]["screenshot_status"] = "enabled"

	if not reset_meta:
		_fail(report,
			"unlock recap evidence requires reset-meta=true to avoid stale profile false greens")
		return report

	if reset_meta:
		var progress = load("res://core/meta_progress.gd").new()
		var save_err: Error = progress.save(meta_path)
		if save_err != OK:
			_fail(report, "failed to reset meta profile: %s" % error_string(save_err))
			return report

	var main = load("res://scenes/main.tscn").instantiate()
	main.meta_progress_save_path = meta_path
	main.battle_result_delay_sec = 0.0
	main.play_logger_enabled = false
	get_tree().root.add_child(main)
	await _wait_frames(2)

	if not _expect_modal(report, main, LiveUiProbe.RUN_START, "initial"):
		return report
	if not LiveUiProbe.press_run_start(main):
		_fail(report, "run-start button was not actionable")
		return report
	await _wait_frames(2)

	if not _expect_modal(report, main, LiveUiProbe.COMMANDER_SELECT,
			"after_run_start"):
		return report
	var commander_step := _last_snapshot(report)
	var commander_choices: Array = commander_step.get("choices", {}).get(
		LiveUiProbe.COMMANDER_SELECT, [])
	var commander_summaries := _choice_card_summaries(
		commander_step, LiveUiProbe.COMMANDER_SELECT)
	if not _require(report, _choice_card_summaries_are_rendered(
			commander_summaries, commander_choices),
			"commander selection did not expose rendered choice summaries"):
		return report
	var selected_commander_summary := _choice_card_summary_for_id(
		commander_summaries, str(commander_type))
	if not _require(report, not selected_commander_summary.is_empty(),
			"selected commander summary was not rendered before selection"):
		return report
	var commander_context_text := _choice_context_text(
		commander_step, LiveUiProbe.COMMANDER_SELECT)
	if not _require(report,
			commander_context_text.contains("커맨더") \
				and commander_context_text.contains("런 전체") \
				and _choice_context_rect_is_visible(
					commander_step, LiveUiProbe.COMMANDER_SELECT),
			"commander selection did not expose its visible role context"):
		return report
	report["events"]["run_selection"] = {
		"selected_commander": commander_type,
		"commander_choice_summaries": commander_summaries,
		"selected_commander_summary": selected_commander_summary,
		"commander_context_text": commander_context_text,
	}
	if not LiveUiProbe.select_commander(main, commander_type):
		_fail(report, "commander %d was not visible/actionable" % commander_type)
		return report
	await _wait_frames(2)

	if not _expect_modal(report, main, LiveUiProbe.TALISMAN_SELECT,
			"after_commander"):
		return report
	var talisman_step := _last_snapshot(report)
	var talisman_choices: Array = talisman_step.get("choices", {}).get(
		LiveUiProbe.TALISMAN_SELECT, [])
	var talisman_summaries := _choice_card_summaries(
		talisman_step, LiveUiProbe.TALISMAN_SELECT)
	if not _require(report, _choice_card_summaries_are_rendered(
			talisman_summaries, talisman_choices),
			"talisman selection did not expose rendered choice summaries"):
		return report
	var selected_talisman_summary := _choice_card_summary_for_id(
		talisman_summaries, str(talisman_type))
	if not _require(report, not selected_talisman_summary.is_empty(),
			"selected talisman summary was not rendered before selection"):
		return report
	var talisman_context_text := _choice_context_text(
		talisman_step, LiveUiProbe.TALISMAN_SELECT)
	if not _require(report,
			talisman_context_text.contains("부적") \
				and talisman_context_text.contains("선택한 커맨더") \
				and talisman_context_text.contains(
					str(selected_commander_summary.get("name", ""))) \
				and _choice_context_rect_is_visible(
					talisman_step, LiveUiProbe.TALISMAN_SELECT),
			"talisman selection did not carry the selected commander context"):
		return report
	var run_selection: Dictionary = report["events"].get("run_selection", {})
	run_selection["selected_talisman"] = talisman_type
	run_selection["talisman_choice_summaries"] = talisman_summaries
	run_selection["selected_talisman_summary"] = selected_talisman_summary
	run_selection["talisman_context_text"] = talisman_context_text
	report["events"]["run_selection"] = run_selection
	if not LiveUiProbe.select_talisman(main, talisman_type):
		_fail(report, "talisman %d was not visible/actionable" % talisman_type)
		return report
	await _wait_frames(3)

	_add_step(report, "build_entry", main)
	if not _capture_run_identity(report, _last_snapshot(report), "build_entry"):
		return report
	if not _capture_run_milestone(report, _last_snapshot(report), "build_entry"):
		return report
	if not _require(report, _selection_names_match_identity(
			report, _last_snapshot(report), "run_selection"),
			"build identity did not match selected commander/talisman cards"):
		return report
	if not _capture_build_readiness(report, _last_snapshot(report), "build_entry"):
		return report
	if not _capture_enemy_pressure_preview(report, _last_snapshot(report),
			"build_entry"):
		return report
	if not _capture_shop_role_cues(report, _last_snapshot(report), "build_entry"):
		return report
	if not _require(report, not bool(_last_snapshot(report).get("has_modal", true)),
			"run setup did not return to modal-free build"):
		return report
	if not await _run_shop_reroll_scope_event(report, main):
		return report

	if not await _run_chain_feedback_event(report, main):
		return report
	if not await _run_merge_reward_event(report, main):
		return report
	if not await _run_boss_reward_event(report, main):
		return report
	if not await _run_targeted_boss_reward_event(report, main):
		return report
	var final_main = await _run_unlock_recap_event(report, main, meta_path)
	if final_main == null:
		return report

	report["final"] = LiveUiProbe.snapshot(final_main)
	_capture_screenshot(report, "final", report["final"])
	var errors: Array = report.get("errors", [])
	report["ok"] = errors.is_empty()
	return report


func _run_shop_reroll_scope_event(report: Dictionary, main) -> bool:
	main.game_state.gold = maxi(main.game_state.gold, 30)
	main.game_state.terazin = maxi(
		main.game_state.terazin, Enums.UPGRADE_REROLL_COST * 10)
	main.game_state.state_changed.emit()
	main.build_phase.refresh_shop(true)
	main.build_phase._refresh_all()
	await _wait_frames(1)

	var before := _shop_snapshot(main)
	var card_before: Array = before.get("card_offer_ids", [])
	var upgrade_before: Array = before.get("upgrade_offer_ids", [])
	if not _require(report, not card_before.is_empty(),
			"shop reroll scope event had no card offers"):
		return false
	if not _require(report, not upgrade_before.is_empty(),
			"shop reroll scope event had no upgrade offers"):
		return false
	if not _require(report,
			str(before.get("shop_label_text", "")).contains("CARD SHOP") \
				and str(before.get("shop_label_text", "")).contains("R:cards") \
				and str(before.get("upgrade_shop_label_text", "")).contains(
					"T:upgrades only") \
				and str(before.get("upgrade_reroll_button_text", "")).contains(
					"UPG REROLL"),
			"shop labels did not distinguish card and upgrade reroll scope"):
		return false

	var gold_before: int = main.game_state.gold
	var card_after := {}
	var card_attempts := 0
	while card_attempts < 6:
		card_attempts += 1
		if not main.build_phase.reroll():
			_fail(report, "card shop reroll failed during scope event")
			return false
		await _wait_frames(1)
		card_after = _shop_snapshot(main)
		if not _same_array(card_before, card_after.get("card_offer_ids", [])):
			break

	var card_after_ids: Array = card_after.get("card_offer_ids", [])
	var upgrade_after_card_reroll: Array = card_after.get("upgrade_offer_ids", [])
	if not _require(report, not _same_array(card_before, card_after_ids),
			"card shop reroll did not change card offers after repeated attempts"):
		return false
	if not _require(report, _same_array(upgrade_before, upgrade_after_card_reroll),
			"card shop reroll changed upgrade offers"):
		return false

	var cards_before_upgrade_reroll := card_after_ids.duplicate()
	var upgrades_before_upgrade_reroll := upgrade_after_card_reroll.duplicate()
	var terazin_before: int = main.game_state.terazin
	var upgrade_after := {}
	var upgrade_attempts := 0
	while upgrade_attempts < 8:
		upgrade_attempts += 1
		if not main.build_phase.reroll_upgrades():
			_fail(report, "upgrade shop reroll failed during scope event")
			return false
		await _wait_frames(1)
		upgrade_after = _shop_snapshot(main)
		if not _same_array(
				upgrades_before_upgrade_reroll,
				upgrade_after.get("upgrade_offer_ids", [])):
			break

	var card_after_upgrade_reroll: Array = upgrade_after.get("card_offer_ids", [])
	var upgrade_after_ids: Array = upgrade_after.get("upgrade_offer_ids", [])
	if not _require(report,
			not _same_array(upgrades_before_upgrade_reroll, upgrade_after_ids),
			"upgrade shop reroll did not change upgrade offers after repeated attempts"):
		return false
	if not _require(report,
			_same_array(cards_before_upgrade_reroll, card_after_upgrade_reroll),
			"upgrade shop reroll changed card offers"):
		return false

	report["events"]["shop_reroll_scope"] = {
		"labels": {
			"shop_label_text": str(before.get("shop_label_text", "")),
			"upgrade_shop_label_text": str(before.get("upgrade_shop_label_text", "")),
			"upgrade_reroll_button_text": str(before.get(
				"upgrade_reroll_button_text", "")),
		},
		"card_reroll": {
			"attempts": card_attempts,
			"gold_before": gold_before,
			"gold_after": main.game_state.gold,
			"before_card_offer_ids": card_before,
			"after_card_offer_ids": card_after_ids,
			"before_upgrade_offer_ids": upgrade_before,
			"after_upgrade_offer_ids": upgrade_after_card_reroll,
			"cards_changed": not _same_array(card_before, card_after_ids),
			"upgrades_preserved": _same_array(
				upgrade_before, upgrade_after_card_reroll),
		},
		"upgrade_reroll": {
			"attempts": upgrade_attempts,
			"terazin_before": terazin_before,
			"terazin_after": main.game_state.terazin,
			"before_card_offer_ids": cards_before_upgrade_reroll,
			"after_card_offer_ids": card_after_upgrade_reroll,
			"before_upgrade_offer_ids": upgrades_before_upgrade_reroll,
			"after_upgrade_offer_ids": upgrade_after_ids,
			"cards_preserved": _same_array(
				cards_before_upgrade_reroll, card_after_upgrade_reroll),
			"upgrades_changed": not _same_array(
				upgrades_before_upgrade_reroll, upgrade_after_ids),
		},
	}
	return true


func _run_chain_feedback_event(report: Dictionary, main) -> bool:
	var card_instance = load("res://core/card_instance.gd")
	_clear_run_cards(main)
	main.chain_feedback_delay_sec = 0.8
	main.chain_feedback_delay_per_event_sec = 0.0
	main.chain_feedback_max_delay_sec = 0.8
	main.game_state.board[0] = card_instance.create("sp_assembly")  # lint:allow zone-assign
	main.game_state.board[1] = card_instance.create("sp_workshop")  # lint:allow zone-assign
	main.game_state.state_changed.emit()
	main.build_phase._refresh_all()
	await _wait_frames(1)

	main.build_phase.confirm_button.pressed.emit()
	await _wait_frames(2)
	_add_step(report, "chain_feedback_open", main)
	var chain_step := _last_snapshot(report)
	if not _capture_run_identity(report, chain_step, "during_chain_feedback"):
		return false
	var chain_details: Dictionary = chain_step.get("chain_feedback", {})
	if not _require(report, str(chain_step.get("phase", "")) == "CHAIN",
			"chain feedback did not enter CHAIN phase"):
		return false
	if not _require(report, bool(chain_step.get("chain_visible", false)),
			"chain feedback was not visible during CHAIN phase"):
		return false
	if not _require(report, not bool(chain_step.get("has_modal", true)),
			"chain feedback pause should not be owned by a modal"):
		return false
	if not _require(report, bool(chain_details.get("event_panel_visible", false)),
			"chain feedback event panel was not visible"):
		return false
	var event_log := str(chain_details.get("event_log_text", ""))
	if not _require(report, event_log.contains("Complete:") and event_log.contains("+Unit"),
			"chain feedback log did not include complete/unit event text"):
		return false

	if not _require(report, main.skip_chain_feedback(),
			"chain feedback pause could not be skipped into BATTLE"):
		return false
	await _wait_frames(1)
	if not _require(report, main.current_phase == main.Phase.BATTLE,
			"chain feedback pause did not enter BATTLE"):
		return false
	_add_step(report, "battle_status_live", main)
	if not _capture_battle_status(report, _last_snapshot(report),
			"battle_status_live"):
		return false
	main.battle_phase.stop()
	var previous_battle_delay: float = main.battle_result_delay_sec
	main.battle_result_delay_sec = 0.2
	main._on_battle_finished({
		"player_won": true,
		"ally_survived": 1,
		"enemy_survived": 0,
	})
	await _wait_frames(2)
	_add_step(report, "battle_result_open", main)
	var battle_step := _last_snapshot(report)
	var battle_details: Dictionary = battle_step.get("battle_result", {})
	var battle_text := str(battle_details.get("detail_text", ""))
	report["events"]["battle_result"] = {
		"result_text": str(battle_details.get("result_text", "")),
		"detail_text": battle_text,
		"summary_text": str(battle_details.get("summary_text", "")),
		"context": battle_details.get("context", {}),
	}
	if not _require(report,
			battle_step.get("active_modals", []) == [LiveUiProbe.BATTLE_RESULT] \
				and battle_text.contains("HP:") \
				and battle_text.contains("Gold:") \
				and battle_text.contains("Next:"),
			"battle result popup did not expose HP/gold/next-step aftermath"):
		main.battle_result_delay_sec = previous_battle_delay
		return false
	await get_tree().create_timer(0.25).timeout
	main.battle_result_delay_sec = previous_battle_delay
	await _wait_frames(2)
	_add_step(report, "chain_feedback_last_history", main)
	var last_step := _last_snapshot(report)
	if not _capture_run_identity(report, last_step, "after_chain_feedback"):
		return false
	if not _capture_run_milestone(report, last_step, "after_chain_feedback"):
		return false
	var last_details: Dictionary = last_step.get("last_chain_history", {})
	var last_text := str(last_details.get("text", ""))
	var settlement_details: Dictionary = last_step.get("last_settlement_recap", {})
	var settlement_text := str(settlement_details.get("text", ""))
	var settlement_data: Dictionary = settlement_details.get("data", {})
	report["events"]["chain_feedback"] = {
		"phase_during_pause": str(chain_step.get("phase", "")),
		"counter_text": str(chain_details.get("counter_text", "")),
		"event_log_text": event_log,
		"last_history_display_text": str(last_details.get("display_text", "")),
		"last_history_visible": bool(last_details.get("visible", false)),
		"last_history_text": last_text,
		"round_after": main.game_state.round_num,
	}
	report["events"]["settlement_recap"] = {
		"visible": bool(settlement_details.get("visible", false)),
		"text": settlement_text,
		"data": settlement_data,
		"round_after": main.game_state.round_num,
	}
	return _require(report,
		str(last_step.get("phase", "")) == "BUILD" \
			and not bool(last_step.get("chain_visible", true)) \
			and bool(last_details.get("visible", false)) \
			and last_text.contains("Complete:") \
			and bool(settlement_details.get("visible", false)) \
			and settlement_text.contains("Gold:") \
			and settlement_text.contains("income") \
			and settlement_text.contains("interest") \
			and settlement_text.contains("Terazin:") \
			and settlement_text.contains("boss reward") \
			and settlement_data.has("base_income") \
			and settlement_data.has("interest"),
		"chain feedback did not leave visible last-chain and settlement recap in BUILD")


func _run_merge_reward_event(report: Dictionary, main) -> bool:
	_clear_run_cards(main)
	var card_instance = load("res://core/card_instance.gd")
	main.game_state.gold = 10
	main.game_state.bench[0] = card_instance.create("sp_assembly")  # lint:allow zone-assign
	main.game_state.bench[1] = card_instance.create("sp_assembly")  # lint:allow zone-assign
	main.game_state.state_changed.emit()
	await _wait_frames(1)

	if not _require(report, main.build_phase.shop._offered_ids.size() > 0,
			"shop had no visible purchase slots before merge event"):
		return false
	main.build_phase.shop._offered_ids[0] = "sp_assembly"
	main.build_phase.shop._coin_slots.clear()
	main.build_phase.shop._update_visuals()
	_add_step(report, "merge_shop_seeded", main)

	var gold_before_purchase := int(main.game_state.gold)
	var purchase_cost := int(CardDB.get_template("sp_assembly").get("cost", 0))
	if not main.build_phase.shop.try_purchase(0):
		_fail(report, "buying the third sp_assembly copy failed")
		return false
	await _wait_frames(2)

	if not _expect_modal(report, main, LiveUiProbe.UPGRADE_CHOICE,
			"merge_reward_open"):
		return false
	var choices := LiveUiProbe.choice_ids(main, LiveUiProbe.UPGRADE_CHOICE)
	if not _require(report, choices.size() > 0,
			"merge reward popup had no visible choices"):
		return false
	var selected_upgrade: String = choices[0]
	var survivor = main.game_state.bench[0]
	if not _require(report, survivor != null and survivor.star_level == 2,
			"merge survivor was not a visible star-2 card"):
		return false
	var expected_merge_refund := Commander.calc_merge_refund(main.game_state, {
		"card": survivor,
		"old_star": 1,
		"new_star": 2,
	})
	var expected_gold_after_merge := gold_before_purchase - purchase_cost \
		+ expected_merge_refund
	var gold_after_merge := int(main.game_state.gold)
	if not _require(report, gold_after_merge == expected_gold_after_merge,
			"star1 to star2 merge gold did not match expected refund rule"):
		return false

	if not LiveUiProbe.select_choice(main, LiveUiProbe.UPGRADE_CHOICE, 0):
		_fail(report, "merge reward popup selection failed")
		return false
	await _wait_frames(2)
	_add_step(report, "merge_reward_closed", main)

	var attached := _card_has_upgrade_id(survivor, selected_upgrade)
	var merge_history: Dictionary = _last_snapshot(report).get("merge_history", {})
	var merge_history_text := str(merge_history.get("text", ""))
	var merge_history_entries: Array = merge_history.get("entries", [])
	report["events"]["merge_reward"] = {
		"selected_upgrade": selected_upgrade,
		"survivor_card_id": survivor.get_base_id(),
		"survivor_star": survivor.star_level,
		"attached": attached,
		"gold_before_purchase": gold_before_purchase,
		"purchase_cost": purchase_cost,
		"expected_merge_refund": expected_merge_refund,
		"gold_after_merge": gold_after_merge,
		"expected_gold_after_merge": expected_gold_after_merge,
		"merge_history_visible": bool(merge_history.get("visible", false)),
		"merge_history_text": merge_history_text,
		"merge_history_entries": merge_history_entries,
	}
	if not _require(report, attached, "selected merge reward did not attach"):
		return false
	if not _require(report,
			bool(merge_history.get("visible", false)) \
			and merge_history_entries.size() >= 1 \
			and merge_history_text.contains("MERGE:") \
			and merge_history_text.contains("★1 -> ★2"),
			"merge history did not expose the star1 to star2 merge"):
		return false
	return _require(report, not bool(_last_snapshot(report).get("chain_visible", true)),
		"merge reward returned to build with stale chain feedback visible")


func _run_boss_reward_event(report: Dictionary, main) -> bool:
	var card_instance = load("res://core/card_instance.gd")
	main.game_state.board[0] = card_instance.create("sp_assembly")  # lint:allow zone-assign
	main.game_state.round_num = 4
	main._gold_before_effects = main.game_state.gold
	main.current_phase = main.Phase.BATTLE
	main.build_phase.visible = false

	await main._on_battle_finished({
		"player_won": true,
		"ally_survived": 1,
		"enemy_survived": 0,
	})
	await _wait_frames(1)

	if not _expect_modal(report, main, LiveUiProbe.BOSS_REWARD,
			"boss_reward_open"):
		return false
	var open_step := _last_snapshot(report)
	var choices := LiveUiProbe.choice_ids(main, LiveUiProbe.BOSS_REWARD)
	var choice_summaries: Array = _boss_reward_choice_summaries(open_step)
	if not _require(report, _boss_reward_summaries_are_rendered(
			choice_summaries, choices),
			"boss reward choices did not expose rendered comparison text"):
		return false
	var no_target_idx := _first_no_target_reward_index(choices)
	if not _require(report, no_target_idx >= 0,
			"boss reward choices had no immediately actionable reward"):
		return false
	if not _require(report,
			no_target_idx < choice_summaries.size() \
				and not bool(choice_summaries[no_target_idx].get(
					"needs_target", true)),
			"boss reward rendered summaries did not identify no-target reward"):
		return false
	var selected_reward: String = choices[no_target_idx]
	var selected_summary: Dictionary = choice_summaries[no_target_idx]
	if not LiveUiProbe.select_choice(main, LiveUiProbe.BOSS_REWARD, no_target_idx):
		_fail(report, "boss reward popup selection failed")
		return false
	await _wait_frames(2)
	_add_step(report, "boss_reward_closed", main)

	report["events"]["boss_reward"] = {
		"selected_reward": selected_reward,
		"round_after": main.game_state.round_num,
		"phase_after": str(_last_snapshot(report).get("phase", "")),
		"build_visible_after": bool(_last_snapshot(report).get("build_visible", false)),
		"chain_visible_after": bool(_last_snapshot(report).get("chain_visible", false)),
		"open_choice_summaries": choice_summaries,
		"selected_choice_summary": selected_summary,
	}
	return _require(report,
		main.game_state.round_num == 5 and main.build_phase.visible \
			and not bool(_last_snapshot(report).get("chain_visible", true)),
		"boss reward did not settle into R5 build")


func _run_targeted_boss_reward_event(report: Dictionary, main) -> bool:
	var card_instance = load("res://core/card_instance.gd")
	_clear_run_cards(main)
	var target = card_instance.create("sp_assembly")
	var ineligible = card_instance.create("sp_workshop")
	ineligible.evolve_star()
	ineligible.evolve_star()
	main.game_state.board[0] = target  # lint:allow zone-assign
	main.game_state.board[1] = ineligible  # lint:allow zone-assign
	main.game_state.terazin = 0
	main.game_state.round_num = 4
	main._gold_before_effects = main.game_state.gold
	main.current_phase = main.Phase.BATTLE
	main.build_phase.visible = false
	main.build_phase._refresh_all()

	var selected_reward := "r4_1"
	var forced_choices: Array[String] = [selected_reward]
	main.boss_reward_popup.show_choices(forced_choices)
	await _wait_frames(1)

	if not _expect_modal(report, main, LiveUiProbe.BOSS_REWARD,
			"targeted_boss_reward_open"):
		return false
	var open_step := _last_snapshot(report)
	var open_summaries := _boss_reward_choice_summaries(open_step)
	if not _require(report, _boss_reward_summaries_are_rendered(
			open_summaries, forced_choices),
			"targeted boss reward choice did not expose rendered comparison text"):
		return false
	if not _require(report,
			open_summaries.size() == 1 and bool(open_summaries[0].get(
				"needs_target", false)),
			"targeted boss reward rendered summary did not identify target need"):
		return false
	if not LiveUiProbe.select_choice(main, LiveUiProbe.BOSS_REWARD, 0):
		_fail(report, "targeted boss reward popup selection failed")
		return false
	await _wait_frames(2)

	if not _expect_modal(report, main, LiveUiProbe.TARGET_SELECT,
			"targeted_boss_reward_target_open"):
		return false
	var target_step := _last_snapshot(report)
	var choice_map: Dictionary = target_step.get("choices", {})
	var target_choices: Array = choice_map.get(LiveUiProbe.TARGET_SELECT, [])
	if not _require(report, target_choices == [0],
			"targeted boss reward expected only field 0 selectable, got %s" % [
				target_choices]):
		return false
	var target_details: Dictionary = target_step.get("target_select", {})
	var preview_text := "\n".join(target_details.get("preview_texts", []))
	if not _require(report, preview_text.contains("★1 -> ★2"),
			"targeted boss reward missing eligible star preview"):
		return false
	if not _require(report, preview_text.contains("MAX ★3"),
			"targeted boss reward missing ineligible star preview"):
		return false
	var terazin_before: int = main.game_state.terazin
	var star_before: int = target.star_level

	if not LiveUiProbe.select_target(main, 0):
		_fail(report, "targeted boss reward field selection failed")
		return false
	await _wait_frames(2)
	_add_step(report, "targeted_boss_reward_closed", main)
	var terazin_delta_after_settlement: int = int(main.game_state.terazin) - terazin_before

	report["events"]["targeted_boss_reward"] = {
		"selected_reward": selected_reward,
		"forced_choice": true,
		"selected_field_idx": 0,
		"selectable_field_indices": target_choices,
		"target_star_before": star_before,
		"target_star_after": target.star_level,
		"terazin_before": terazin_before,
		"terazin_after": main.game_state.terazin,
		"terazin_delta_after_settlement": terazin_delta_after_settlement,
		"round_after": main.game_state.round_num,
		"phase_after": str(_last_snapshot(report).get("phase", "")),
		"build_visible_after": bool(_last_snapshot(report).get("build_visible", false)),
		"chain_visible_after": bool(_last_snapshot(report).get("chain_visible", false)),
		"open_choice_summaries": open_summaries,
	}
	return _require(report,
		target.star_level == 2 and terazin_delta_after_settlement >= 4 \
			and main.game_state.round_num == 5 and main.build_phase.visible \
			and not bool(_last_snapshot(report).get("has_modal", true)) \
			and not bool(_last_snapshot(report).get("chain_visible", true)),
		"targeted boss reward did not apply and settle into clean R5 build")


func _run_unlock_recap_event(report: Dictionary, main, meta_path: String):
	var card_instance = load("res://core/card_instance.gd")
	_clear_run_cards(main)
	main.game_state.board[0] = card_instance.create("sp_assembly")  # lint:allow zone-assign
	main.game_state.round_num = Enums.MAX_ROUNDS
	main.game_state.hp = 7
	main.game_state.gold = 20
	main._gold_before_effects = main.game_state.gold
	main._last_ally_count = 10
	main._last_enemy_count = 5
	main._current_win_streak = 7
	main._run_stats = _overflow_unlock_run_stats()
	main.current_phase = main.Phase.BATTLE
	main.build_phase.visible = false

	await main._on_battle_finished({
		"player_won": true,
		"ally_survived": 1,
		"enemy_survived": 0,
	})
	await _wait_frames(2)

	if not _expect_modal(report, main, LiveUiProbe.GAME_OVER,
			"unlock_game_over_open"):
		return null
	var game_over_step := _last_snapshot(report)
	var game_over_details: Dictionary = game_over_step.get("game_over", {})
	var game_over_summary := str(game_over_details.get("summary_text", ""))
	var shown_unlocks := _unlock_bullet_lines(game_over_summary)
	var overflow_count := _unlock_overflow_count(game_over_summary)
	report["events"]["unlock_recap"] = {
		"title_text": str(game_over_details.get("title_text", "")),
		"summary_text": game_over_summary,
		"shown_unlocks": shown_unlocks,
		"shown_count": shown_unlocks.size(),
		"overflow_count": overflow_count,
		"raw_unlock_count": shown_unlocks.size() + overflow_count,
	}
	if not _require(report,
			str(game_over_details.get("title_text", "")) == "VICTORY!" \
				and game_over_summary.contains("New unlocks available") \
				and shown_unlocks.size() == 3 \
				and overflow_count > 0 \
				and game_over_summary.contains(
					"more unlocked - all available in PROGRESS") \
				and game_over_summary.contains("- 커맨더: 전략가") \
				and game_over_summary.contains("- 커맨더: 단조사") \
				and game_over_summary.contains("- 커맨더: 수집가") \
				and not game_over_summary.contains("- 부적: 영혼 항아리"),
			"game-over unlock recap did not show capped top-three plus overflow"):
		return null

	main.queue_free()
	await _wait_frames(2)

	var next_main = load("res://scenes/main.tscn").instantiate()
	next_main.meta_progress_save_path = meta_path
	next_main.battle_result_delay_sec = 0.0
	next_main.play_logger_enabled = false
	get_tree().root.add_child(next_main)
	await _wait_frames(2)

	if not _expect_modal(report, next_main, LiveUiProbe.RUN_START,
			"post_unlock_run_start"):
		return null
	var run_start_step := _last_snapshot(report)
	var run_start_details: Dictionary = run_start_step.get("run_start", {})
	var recent_text := str(run_start_details.get("recent_unlocks_text", ""))
	if not _require(report,
			recent_text.contains("최근 해금") \
				and recent_text.contains("- 커맨더: 전략가") \
				and recent_text.contains("- 커맨더: 단조사") \
				and recent_text.contains("- 커맨더: 수집가") \
				and recent_text.contains("more unlocked - all available in PROGRESS") \
				and not recent_text.contains("- 부적: 영혼 항아리") \
				and str(run_start_details.get("difficulty_text", "")).contains(
					"Difficulty 1 / 2") \
				and str(run_start_details.get("unlocks_text", "")).contains("연금술사") \
				and str(run_start_details.get("unlocks_text", "")).contains("영혼 항아리"),
			"post-unlock run-start screen did not show recap and availability text"):
		return null

	next_main.run_start_screen.progress_details_button.pressed.emit()
	await _wait_frames(1)
	_add_step(report, "post_unlock_progress_details", next_main)
	var progress_step := _last_snapshot(report)
	var progress_details: Dictionary = progress_step.get("run_start", {})
	var details_text := str(progress_details.get("details_text", ""))
	report["events"]["post_unlock_progress"] = {
		"recent_unlocks_text": recent_text,
		"unlocks_text": str(run_start_details.get("unlocks_text", "")),
		"difficulty_text": str(run_start_details.get("difficulty_text", "")),
		"details_text": details_text,
		"details_visible": bool(progress_details.get("details_visible", false)),
	}
	if not _require(report,
			bool(progress_details.get("details_visible", false)) \
				and details_text.contains("난이도 2/8 해금") \
				and details_text.contains("- 연금술사: 해금") \
				and details_text.contains("- 영혼 항아리: 해금") \
				and details_text.contains("완료 업적"),
			"post-unlock progress details did not expose full availability"):
		return null

	if not LiveUiProbe.press_run_start(next_main):
		_fail(report, "post-unlock run-start button was not actionable")
		return null
	await _wait_frames(2)
	if not _expect_modal(report, next_main, LiveUiProbe.COMMANDER_SELECT,
			"post_unlock_commander_select"):
		return null
	var commander_step := _last_snapshot(report)
	var commander_choices: Array = commander_step.get("choices", {}).get(
		LiveUiProbe.COMMANDER_SELECT, [])
	var commander_summaries := _choice_card_summaries(
		commander_step, LiveUiProbe.COMMANDER_SELECT)
	if not _require(report, _choice_card_summaries_are_rendered(
			commander_summaries, commander_choices),
			"post-unlock commander selection did not expose rendered summaries"):
		return null
	var selected_commander_summary := _choice_card_summary_for_id(
		commander_summaries, str(Enums.CommanderType.ALCHEMIST))
	if not _require(report, str(Enums.CommanderType.ALCHEMIST) in commander_choices,
			"overflow commander Alchemist was not selectable after unlock"):
		return null
	if not _require(report, not selected_commander_summary.is_empty(),
			"overflow commander Alchemist summary was not rendered after unlock"):
		return null
	var commander_context_text := _choice_context_text(
		commander_step, LiveUiProbe.COMMANDER_SELECT)
	if not _require(report,
			commander_context_text.contains("커맨더") \
				and commander_context_text.contains("런 전체") \
				and _choice_context_rect_is_visible(
					commander_step, LiveUiProbe.COMMANDER_SELECT),
			"post-unlock commander selection did not expose visible role context"):
		return null
	if not LiveUiProbe.select_commander(next_main, Enums.CommanderType.ALCHEMIST):
		_fail(report, "selecting overflow commander Alchemist failed")
		return null
	await _wait_frames(2)

	if not _expect_modal(report, next_main, LiveUiProbe.TALISMAN_SELECT,
			"post_unlock_talisman_select"):
		return null
	var talisman_step := _last_snapshot(report)
	var talisman_choices: Array = talisman_step.get("choices", {}).get(
		LiveUiProbe.TALISMAN_SELECT, [])
	var talisman_summaries := _choice_card_summaries(
		talisman_step, LiveUiProbe.TALISMAN_SELECT)
	if not _require(report, _choice_card_summaries_are_rendered(
			talisman_summaries, talisman_choices),
			"post-unlock talisman selection did not expose rendered summaries"):
		return null
	var selected_talisman_summary := _choice_card_summary_for_id(
		talisman_summaries, str(Enums.TalismanType.SOUL_JAR))
	if not _require(report, str(Enums.TalismanType.SOUL_JAR) in talisman_choices,
			"overflow talisman Soul Jar was not selectable after unlock"):
		return null
	if not _require(report, not selected_talisman_summary.is_empty(),
			"overflow talisman Soul Jar summary was not rendered after unlock"):
		return null
	var talisman_context_text := _choice_context_text(
		talisman_step, LiveUiProbe.TALISMAN_SELECT)
	if not _require(report,
			talisman_context_text.contains("부적") \
				and talisman_context_text.contains("선택한 커맨더") \
				and talisman_context_text.contains(
					str(selected_commander_summary.get("name", ""))) \
				and _choice_context_rect_is_visible(
					talisman_step, LiveUiProbe.TALISMAN_SELECT),
			"post-unlock talisman selection did not carry commander context"):
		return null
	if not LiveUiProbe.select_talisman(next_main, Enums.TalismanType.SOUL_JAR):
		_fail(report, "selecting overflow talisman Soul Jar failed")
		return null
	await _wait_frames(3)

	_add_step(report, "post_unlock_build_entry", next_main)
	var build_step := _last_snapshot(report)
	report["events"]["post_unlock_availability"] = {
		"selected_commander": Enums.CommanderType.ALCHEMIST,
		"selected_talisman": Enums.TalismanType.SOUL_JAR,
		"commander_choices": commander_choices,
		"talisman_choices": talisman_choices,
		"commander_choice_summaries": commander_summaries,
		"talisman_choice_summaries": talisman_summaries,
		"selected_commander_summary": selected_commander_summary,
		"selected_talisman_summary": selected_talisman_summary,
		"commander_context_text": commander_context_text,
		"talisman_context_text": talisman_context_text,
		"phase_after": str(build_step.get("phase", "")),
		"round_after": int(build_step.get("round", 0)),
		"has_modal_after": bool(build_step.get("has_modal", true)),
		"identity_text_after": str(build_step.get("identity", {}).get("text", "")),
	}
	if not _require(report,
			str(build_step.get("phase", "")) == "BUILD" \
				and not bool(build_step.get("has_modal", true)) \
				and next_main.game_state.commander_type == Enums.CommanderType.ALCHEMIST \
				and next_main.game_state.talisman_type == Enums.TalismanType.SOUL_JAR,
			"post-unlock overflow commander/talisman did not start a clean BUILD"):
		return null
	if not _require(report, _selection_names_match_identity(
			report, build_step, "post_unlock_availability"),
			"post-unlock build identity did not match selected choice cards"):
		return null
	if not _capture_run_milestone(report, build_step, "post_unlock_build_entry"):
		return null
	if not _capture_build_readiness(report, build_step, "post_unlock_build_entry"):
		return null
	if not _capture_enemy_pressure_preview(report, build_step,
			"post_unlock_build_entry"):
		return null
	if not _capture_shop_role_cues(report, build_step, "post_unlock_build_entry"):
		return null
	return next_main


func _overflow_unlock_run_stats() -> Dictionary:
	return {
		"max_field_units": 120,
		"max_attached_upgrades": 16,
		"max_unique_field_cards": 7,
		"best_win_streak": 8,
		"cards_sold": 20,
		"growth_events": 120,
		"max_star2_cards": 5,
		"unit_advantage_win": true,
		"unit_advantage_wins": 5,
	}


func _expect_modal(report: Dictionary, main, modal_id: String,
		step_label: String) -> bool:
	var step := _add_step(report, step_label, main)
	var active: Array = step.get("active_modals", [])
	if not _require(report, active == [modal_id],
			"%s expected active modal %s, got %s" % [step_label, modal_id, active]):
		return false
	var actionable: Dictionary = step.get("actionable", {})
	return _require(report, bool(actionable.get(modal_id, false)),
		"%s modal %s was not actionable" % [step_label, modal_id])


func _boss_reward_choice_summaries(step: Dictionary) -> Array:
	var details: Dictionary = step.get("boss_reward", {})
	var raw: Array = details.get("choice_summaries", [])
	var result: Array = []
	for item in raw:
		if item is Dictionary:
			result.append(item)
	return result


func _choice_card_summaries(step: Dictionary, modal_id: String) -> Array:
	var details: Dictionary = step.get(modal_id, {})
	var raw: Array = details.get("choice_summaries", [])
	var result: Array = []
	for item in raw:
		if item is Dictionary:
			result.append(item)
	return result


func _choice_context_text(step: Dictionary, modal_id: String) -> String:
	var details: Dictionary = step.get(modal_id, {})
	return str(details.get("context_text", ""))


func _choice_context_rect_is_visible(step: Dictionary, modal_id: String) -> bool:
	var details: Dictionary = step.get(modal_id, {})
	var rect: Dictionary = details.get("context_rect", {})
	return bool(rect.get("visible", false)) \
		and float(rect.get("w", 0.0)) > 0.0 \
		and float(rect.get("h", 0.0)) > 0.0


func _choice_card_summary_for_id(summaries: Array, choice_id: String) -> Dictionary:
	for item in summaries:
		var summary: Dictionary = item
		if str(summary.get("id", "")) == choice_id:
			return summary
	return {}


func _choice_card_summaries_are_rendered(summaries: Array, ids: Array) -> bool:
	if summaries.size() != ids.size():
		return false
	for i in summaries.size():
		var summary: Dictionary = summaries[i]
		if str(summary.get("id", "")) != str(ids[i]):
			return false
		if int(summary.get("idx", -1)) != i:
			return false
		for key in ["name", "desc", "text"]:
			if str(summary.get(key, "")).strip_edges() == "":
				return false
		var text := str(summary.get("text", ""))
		if not text.contains(str(summary.get("name", ""))):
			return false
		if not text.contains(str(summary.get("desc", ""))):
			return false
		var rect: Dictionary = summary.get("rect", {})
		if float(rect.get("w", 0.0)) <= 0.0 or float(rect.get("h", 0.0)) <= 0.0:
			return false
		if not bool(rect.get("visible", false)):
			return false
	return true


func _selection_names_match_identity(report: Dictionary, snapshot: Dictionary,
		event_key: String) -> bool:
	var identity: Dictionary = snapshot.get("identity", {})
	var identity_text := str(identity.get("text", ""))
	var event: Dictionary = report.get("events", {}).get(event_key, {})
	var commander_summary: Dictionary = event.get("selected_commander_summary", {})
	var talisman_summary: Dictionary = event.get("selected_talisman_summary", {})
	var commander_name := str(commander_summary.get("name", "")).strip_edges()
	var talisman_name := str(talisman_summary.get("name", "")).strip_edges()
	return commander_name != "" and talisman_name != "" \
		and identity_text.contains(commander_name) \
		and identity_text.contains(talisman_name)


func _boss_reward_summaries_are_rendered(summaries: Array, ids: Array[String]) -> bool:
	if summaries.size() != ids.size():
		return false
	for i in summaries.size():
		var summary: Dictionary = summaries[i]
		if str(summary.get("id", "")) != ids[i]:
			return false
		for key in ["name", "type", "desc", "text"]:
			if str(summary.get(key, "")).strip_edges() == "":
				return false
		var text := str(summary.get("text", ""))
		if not text.contains(str(summary.get("name", ""))):
			return false
		if not text.contains(str(summary.get("desc", ""))):
			return false
		var rect: Dictionary = summary.get("rect", {})
		if float(rect.get("w", 0.0)) <= 0.0 or float(rect.get("h", 0.0)) <= 0.0:
			return false
	return true


func _add_step(report: Dictionary, label: String, main) -> Dictionary:
	var snapshot := LiveUiProbe.snapshot(main)
	snapshot["label"] = label
	report["steps"].append(snapshot)
	_capture_screenshot(report, label, snapshot)
	return snapshot


func _capture_run_identity(report: Dictionary, snapshot: Dictionary,
		label: String) -> bool:
	var identity: Dictionary = snapshot.get("identity", {})
	var text := str(identity.get("text", ""))
	var rect: Dictionary = identity.get("rect", {})
	var event: Dictionary = report["events"].get("run_identity", {})
	var metadata: Dictionary = report.get("metadata", {})
	var commander_name := str(metadata.get("commander_name", "")).strip_edges()
	var talisman_name := str(metadata.get("talisman_name", "")).strip_edges()
	event["commander_name"] = commander_name
	event["talisman_name"] = talisman_name
	event[label] = {
		"text": text,
		"visible": bool(identity.get("visible", false)),
		"rect": rect,
	}
	report["events"]["run_identity"] = event
	if not _require(report,
			bool(identity.get("visible", false)) \
				and float(rect.get("w", 0.0)) > 0.0 \
				and float(rect.get("h", 0.0)) > 0.0 \
				and commander_name != "" and text.contains(commander_name) \
				and talisman_name != "" and text.contains(talisman_name) \
				and text.contains("커맨더:") and text.contains("부적:") \
				and not text.contains("C:") and not text.contains("T:"),
			"%s identity HUD did not expose commander/talisman names cleanly" % label):
		return false
	if int(metadata.get("talisman_type", -1)) == Enums.TalismanType.FLINT:
		var expected_state := ""
		if label == "build_entry":
			expected_state = "준비"
		elif label == "during_chain_feedback":
			expected_state = "사용됨"
		elif label == "after_chain_feedback":
			expected_state = "준비"
		if expected_state != "" and not _require(report,
				text.contains("첫 성장") and text.contains(expected_state),
				"%s identity HUD did not show Flint state %s" % [
					label, expected_state]):
			return false
	return true


func _capture_run_milestone(report: Dictionary, snapshot: Dictionary,
		label: String) -> bool:
	var milestone: Dictionary = snapshot.get("run_milestone", {})
	var text := str(milestone.get("text", ""))
	var round_label_text := str(milestone.get("round_label_text", ""))
	var rect: Dictionary = milestone.get("rect", {})
	var event: Dictionary = report["events"].get("run_milestone", {})
	event[label] = {
		"text": text,
		"round_label_text": round_label_text,
		"visible": bool(milestone.get("visible", false)),
		"rect": rect,
	}
	report["events"]["run_milestone"] = event
	if not _require(report,
			bool(milestone.get("visible", false)) \
				and text.contains("Goal:") \
				and text.contains("boss") \
				and round_label_text.contains("Round") \
				and round_label_text.contains("boss") \
				and float(rect.get("w", 0.0)) > 0.0 \
				and float(rect.get("h", 0.0)) > 0.0,
			"%s run milestone HUD did not expose next boss reward/final boss" % label):
		return false
	return true


func _capture_build_readiness(report: Dictionary, snapshot: Dictionary,
		label: String) -> bool:
	var readiness: Dictionary = snapshot.get("build_readiness", {})
	var text := str(readiness.get("text", ""))
	var rect: Dictionary = readiness.get("rect", {})
	var layout_rects: Dictionary = snapshot.get("layout_rects", {})
	var event: Dictionary = report["events"].get("build_readiness", {})
	event[label] = {
		"text": text,
		"visible": bool(readiness.get("visible", false)),
		"rect": rect,
	}
	report["events"]["build_readiness"] = event

	if not _require(report,
			bool(readiness.get("visible", false)) \
				and float(rect.get("w", 0.0)) > 0.0 \
				and float(rect.get("h", 0.0)) > 0.0 \
				and text.contains("FIELD:") \
				and text.contains("체인/전투") \
				and text.contains("BENCH:") \
				and text.contains("ENEMY:") \
				and text.contains("Next:"),
			"%s BUILD readiness cue did not expose field/bench/enemy/next-action text" % label):
		return false

	var confirm_rect: Dictionary = layout_rects.get("confirm_button", {})
	var field_rect: Dictionary = layout_rects.get("field_container", {})
	if not _require(report,
			not _visible_rects_intersect(rect, confirm_rect) \
				and not _visible_rects_intersect(rect, field_rect),
			"%s BUILD readiness cue overlapped primary BUILD controls" % label):
		return false
	return true


func _capture_enemy_pressure_preview(report: Dictionary, snapshot: Dictionary,
		label: String) -> bool:
	var preview: Dictionary = snapshot.get("enemy_pressure_preview", {})
	var data: Dictionary = preview.get("data", {})
	var text := str(preview.get("text", ""))
	var rect: Dictionary = preview.get("rect", {})
	var event: Dictionary = report["events"].get("enemy_pressure_preview", {})
	event[label] = {
		"text": text,
		"visible": bool(preview.get("visible", false)),
		"rect": rect,
		"data": data,
	}
	report["events"]["enemy_pressure_preview"] = event

	if not _require(report,
			bool(preview.get("visible", false)) \
				and text.contains("ENEMY:") \
				and text.contains("R") \
				and text.contains("ATK") \
				and text.contains("HP") \
				and bool(data.get("exact", true)) == false \
				and int(data.get("preset_count", 0)) >= 1 \
				and int(data.get("enemy_count_max", 0)) >= int(
					data.get("enemy_count_min", 0)) \
				and float(rect.get("w", 0.0)) > 0.0 \
				and float(rect.get("h", 0.0)) > 0.0,
				"%s enemy pressure preview was not visible or not marked as non-exact" % label):
		return false
	return true


func _capture_battle_status(report: Dictionary, snapshot: Dictionary,
		label: String) -> bool:
	var status: Dictionary = snapshot.get("battle_status", {})
	var data: Dictionary = status.get("data", {})
	var text := str(status.get("text", ""))
	var rect: Dictionary = status.get("rect", {})
	var event: Dictionary = report["events"].get("battle_status", {})
	event[label] = {
		"text": text,
		"visible": bool(status.get("visible", false)),
		"rect": rect,
		"data": data,
	}
	report["events"]["battle_status"] = event

	var ally_start := int(data.get("ally_start", 0))
	var enemy_start := int(data.get("enemy_start", 0))
	var ally_remaining := int(data.get("ally_remaining", -1))
	var enemy_remaining := int(data.get("enemy_remaining", -1))
	if not _require(report,
			bool(status.get("visible", false)) \
				and float(rect.get("w", 0.0)) > 0.0 \
				and float(rect.get("h", 0.0)) > 0.0 \
				and str(snapshot.get("phase", "")) == "BATTLE" \
				and text.contains("BATTLE R") \
				and text.contains("Start") \
				and text.contains("Now") \
				and int(data.get("round", 0)) >= 1 \
				and ally_start > 0 \
				and enemy_start > 0 \
				and ally_remaining >= 0 \
				and enemy_remaining >= 0 \
				and ally_remaining <= ally_start \
				and enemy_remaining <= enemy_start,
			"%s battle status did not expose actual start/current counts" % label):
		return false
	return true


func _capture_shop_role_cues(report: Dictionary, snapshot: Dictionary,
		label: String) -> bool:
	var shop: Dictionary = snapshot.get("shop", {})
	var offer_ids: Array = shop.get("card_offer_ids", [])
	var offer_roles: Array = shop.get("card_offer_roles", [])
	var event: Dictionary = report["events"].get("shop_role_cues", {})
	event[label] = {
		"card_offer_ids": offer_ids,
		"card_offer_roles": offer_roles,
	}
	report["events"]["shop_role_cues"] = event
	if not _require(report, offer_roles.size() == offer_ids.size(),
			"%s shop role cue count did not match card offers" % label):
		return false
	for i in offer_ids.size():
		var card_id := str(offer_ids[i])
		if card_id == "":
			continue
		var summary: Dictionary = offer_roles[i]
		var role_text := str(summary.get("role_text", "")).strip_edges()
		var rect: Dictionary = summary.get("rect", {})
		if not _require(report,
				int(summary.get("slot_idx", -1)) == i \
					and str(summary.get("card_id", "")) == card_id \
					and bool(summary.get("visible", false)) \
					and role_text != "" \
					and float(rect.get("w", 0.0)) > 0.0 \
					and float(rect.get("h", 0.0)) > 0.0,
				"%s shop offer %d did not expose a visible role cue" % [
					label, i]):
			return false
	return true


func _visible_rects_intersect(a: Dictionary, b: Dictionary) -> bool:
	if not bool(a.get("visible", false)) or not bool(b.get("visible", false)):
		return false
	var ax := float(a.get("x", 0.0))
	var ay := float(a.get("y", 0.0))
	var aw := float(a.get("w", 0.0))
	var ah := float(a.get("h", 0.0))
	var bx := float(b.get("x", 0.0))
	var by := float(b.get("y", 0.0))
	var bw := float(b.get("w", 0.0))
	var bh := float(b.get("h", 0.0))
	return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by


func _capture_screenshot(report: Dictionary, label: String,
		snapshot: Dictionary) -> void:
	var screenshot_dir: String = str(report.get("metadata", {}).get(
		"screenshot_dir", ""))
	if screenshot_dir == "":
		return
	if str(report.get("metadata", {}).get("screenshot_status", "")) != "enabled":
		return
	var screenshot_idx: int = int(report.get("screenshots", []).size()) + 1
	var path := _join_path(screenshot_dir, "%03d-%s.png" % [
		screenshot_idx, _safe_filename(label)])
	var texture := get_viewport().get_texture()
	if texture == null:
		_fail(report, "screenshot %s had no viewport texture" % label)
		return
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		_fail(report, "screenshot %s had no image data" % label)
		return
	var save_err := image.save_png(path)
	if save_err != OK:
		_fail(report, "failed to save screenshot %s: %s" % [
			path, error_string(save_err)])
		return
	var record := {
		"label": label,
		"path": _global_path(path),
		"width": image.get_width(),
		"height": image.get_height(),
	}
	report["screenshots"].append(record)
	snapshot["screenshot"] = record


func _last_snapshot(report: Dictionary) -> Dictionary:
	var steps: Array = report.get("steps", [])
	if steps.is_empty():
		return {}
	return steps[steps.size() - 1]


func _shop_snapshot(main) -> Dictionary:
	var snapshot := LiveUiProbe.snapshot(main)
	return snapshot.get("shop", {})


func _same_array(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for i in left.size():
		if str(left[i]) != str(right[i]):
			return false
	return true


func _require(report: Dictionary, condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(report, message)
	return false


func _fail(report: Dictionary, message: String) -> void:
	report["ok"] = false
	report["errors"].append(message)
	printerr("ERROR: %s" % message)


func _first_no_target_reward_index(reward_ids: Array[String]) -> int:
	var boss_reward_db = get_node("/root/BossRewardDB")
	for i in reward_ids.size():
		if int(boss_reward_db.get_data(reward_ids[i]).get("needs_target", 0)) == 0:
			return i
	return -1


func _clear_run_cards(main) -> void:
	for i in main.game_state.board.size():
		main.game_state.board[i] = null  # lint:allow zone-assign
	for i in main.game_state.bench.size():
		main.game_state.bench[i] = null  # lint:allow zone-assign


func _card_has_upgrade_id(card, upgrade_id: String) -> bool:
	for upgrade in card.upgrades:
		if upgrade.get("id", "") == upgrade_id:
			return true
	return false


func _unlock_bullet_lines(text: String) -> Array[String]:
	var result: Array[String] = []
	for line in text.split("\n"):
		var trimmed := str(line).strip_edges()
		if trimmed.begins_with("- "):
			result.append(trimmed.trim_prefix("- "))
	return result


func _unlock_overflow_count(text: String) -> int:
	for line in text.split("\n"):
		var trimmed := str(line).strip_edges()
		if not trimmed.begins_with("+"):
			continue
		var space_idx := trimmed.find(" ")
		if space_idx <= 1:
			continue
		var raw_count := trimmed.substr(1, space_idx - 1)
		if raw_count.is_valid_int():
			return raw_count.to_int()
	return 0


func _wait_frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _autoload_data(node_name: String, type_id: int) -> Dictionary:
	var node = get_node_or_null("/root/%s" % node_name)
	if node == null or not node.has_method("get_data"):
		return {}
	return node.call("get_data", type_id)


func _parse_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var parts: PackedStringArray = arg.substr(2).split("=", true, 1)
		var key: String = str(parts[0])
		var raw_value: String = "true" if parts.size() == 1 else str(parts[1])
		if raw_value.is_valid_int():
			result[key] = raw_value.to_int()
		else:
			result[key] = raw_value
	return result


func _parse_named_id(value: Variant, lookup: Dictionary, label: String) -> int:
	var normalized: String = str(value).strip_edges().to_lower().replace("-", "_")
	if normalized.is_valid_int():
		return normalized.to_int()
	if lookup.has(normalized):
		return int(lookup[normalized])
	printerr("ERROR: unknown %s '%s'" % [label, str(value)])
	return -1


func _bool_arg(args: Dictionary, key: String, default_value: bool) -> bool:
	if not args.has(key):
		return default_value
	var value = args[key]
	if value is bool:
		return value
	var value_text: String = str(value).to_lower()
	return value_text in ["1", "true", "yes", "on"]


func _write_json(path: String, data: Dictionary) -> Error:
	var dir: String = path.get_base_dir()
	if dir != "":
		var dir_err := _ensure_dir(dir)
		if dir_err != OK:
			return dir_err

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.store_line("")
	file.close()
	return OK


func _ensure_dir(path: String) -> Error:
	if path == "":
		return OK
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _join_path(dir: String, file_name: String) -> String:
	if dir.ends_with("/"):
		return dir + file_name
	return dir + "/" + file_name


func _global_path(path: String) -> String:
	if path == "":
		return ""
	return ProjectSettings.globalize_path(path)


func _safe_filename(value: String) -> String:
	var text := value.strip_edges().to_lower()
	var result := ""
	var allowed := "abcdefghijklmnopqrstuvwxyz0123456789-_"
	for i in text.length():
		var ch := text.substr(i, 1)
		if allowed.contains(ch):
			result += ch
		elif not result.ends_with("-"):
			result += "-"
	if result == "":
		return "snapshot"
	return result.trim_suffix("-")
