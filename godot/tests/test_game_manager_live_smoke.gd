extends GutTest
## End-to-end live-scene smoke for the main run flow.

const MainScene = preload("res://scenes/main.tscn")
const MetaProgressScript = preload("res://core/meta_progress.gd")
const LiveUiProbe = preload("res://tools/live_ui_probe.gd")
const TEST_META_PATH := "user://meta_progress_live_smoke_test.cfg"

var _previous_time_scale: float = 1.0


func before_each() -> void:
	_previous_time_scale = Engine.time_scale
	seed(12345)
	var progress = MetaProgressScript.new()
	assert_eq(progress.save(TEST_META_PATH), OK,
		"smoke test profile reset")


func after_each() -> void:
	Engine.time_scale = _previous_time_scale


func test_live_run_start_reaches_build_phase() -> void:
	var main = await _start_main_to_build()

	assert_eq(main.current_phase, main.Phase.BUILD)
	assert_true(main.build_phase.visible, "BuildPhase visible after run setup")
	assert_false(main.run_start_screen.visible, "RunStartScreen hidden after start")
	assert_false(main.commander_select_popup.visible, "Commander popup closed")
	assert_false(main.talisman_select_popup.visible, "Talisman popup closed")
	assert_eq(main.game_state.commander_type, Enums.CommanderType.GAMBLER)
	assert_eq(main.game_state.talisman_type, Enums.TalismanType.FLINT)
	assert_eq(main._meta_progress.runs_started, 1)
	assert_false(main._meta_progress.should_show_tutorial(),
		"run start marks tutorial seen")
	var ui := LiveUiProbe.snapshot(main)
	var identity: Dictionary = ui.get("identity", {})
	var identity_text := str(identity.get("text", ""))
	assert_true(bool(identity.get("visible", false)),
		"commander/talisman identity HUD is visible in the live observer")
	assert_string_contains(identity_text, "커맨더:")
	assert_string_contains(identity_text, "도박꾼")
	assert_string_contains(identity_text, "부적:")
	assert_string_contains(identity_text, "부싯돌")
	assert_string_contains(identity_text, "첫 성장 효과 ×2 준비")
	assert_false(identity_text.contains("C:"),
		"live identity HUD avoids commander shorthand")
	assert_false(identity_text.contains("T:"),
		"live identity HUD avoids talisman shorthand")
	var identity_rect: Dictionary = identity.get("rect", {})
	assert_gt(float(identity_rect.get("w", 0.0)), 0.0)
	assert_gt(float(identity_rect.get("h", 0.0)), 0.0)
	var shop: Dictionary = ui.get("shop", {})
	var offer_ids: Array = shop.get("card_offer_ids", [])
	var offer_roles: Array = shop.get("card_offer_roles", [])
	assert_eq(offer_roles.size(), offer_ids.size(),
		"live observer binds one rendered role summary per shop offer")
	for i in offer_ids.size():
		if str(offer_ids[i]) == "":
			continue
		var summary: Dictionary = offer_roles[i]
		assert_eq(summary.get("slot_idx", -1), i)
		assert_eq(str(summary.get("card_id", "")), str(offer_ids[i]))
		assert_true(bool(summary.get("visible", false)),
			"shop role summary comes from a visible card face")
		assert_ne(str(summary.get("role_text", "")).strip_edges(), "",
			"shop offer exposes a compact role cue")
		var role_rect: Dictionary = summary.get("rect", {})
		assert_gt(float(role_rect.get("w", 0.0)), 0.0)
		assert_gt(float(role_rect.get("h", 0.0)), 0.0)


func test_live_two_faced_coin_marks_discount_and_markup_shop_slots() -> void:
	var main = await _start_main_to_build(Enums.TalismanType.TWO_FACED_COIN)

	assert_eq(main.game_state.talisman_type, Enums.TalismanType.TWO_FACED_COIN)
	assert_false(main.build_phase.shop._coin_slots.is_empty(),
		"Two-Faced Coin rolls shop modifier slots")
	var discount_idx: int = int(main.build_phase.shop._coin_slots.get("discount_idx", -1))
	var markup_idx: int = int(main.build_phase.shop._coin_slots.get("markup_idx", -1))
	assert_ne(discount_idx, markup_idx)
	assert_gte(discount_idx, 0)
	assert_gte(markup_idx, 0)

	var discount_visual = main.build_phase.shop._shop_slots[discount_idx]
	var markup_visual = main.build_phase.shop._shop_slots[markup_idx]
	assert_true(discount_visual.visible, "discount slot is visible")
	assert_true(markup_visual.visible, "markup slot is visible")
	assert_eq(discount_visual.get_shop_price_note(), "-50%")
	assert_eq(markup_visual.get_shop_price_note(), "+50%")
	assert_string_contains(discount_visual.get_face_tier_text(), "COIN -50%")
	assert_string_contains(markup_visual.get_face_tier_text(), "COIN +50%")

	var identity_text: String = main.build_phase.get_identity_text()
	assert_string_contains(identity_text, "커맨더:")
	assert_string_contains(identity_text, "부적:")
	assert_string_contains(identity_text, "양면 동전")
	assert_string_contains(identity_text, "할인 %d" % (discount_idx + 1))
	assert_string_contains(identity_text, "할증 %d" % (markup_idx + 1))
	assert_false(identity_text.contains("C:"))
	assert_false(identity_text.contains("T:"))


func test_live_golden_die_boss_reward_shows_six_choices() -> void:
	var progress = MetaProgressScript.new()
	progress.load_or_create(TEST_META_PATH)
	progress.unlocked_talismans.append(Enums.TalismanType.GOLDEN_DIE)
	assert_eq(progress.save(TEST_META_PATH), OK,
		"Golden Die smoke profile unlocks the talisman before run start")

	var main = await _start_main_to_build(Enums.TalismanType.GOLDEN_DIE)
	_clear_run_cards(main)
	main.game_state.board[0] = CardInstance.create("sp_assembly")
	main.game_state.round_num = 4
	main._gold_before_effects = main.game_state.gold
	main.current_phase = main.Phase.BATTLE
	main.build_phase.visible = false

	await main._on_battle_finished({
		"player_won": true,
		"ally_survived": 1,
		"enemy_survived": 0,
	})
	await wait_process_frames(1)

	assert_true(main.boss_reward_popup.visible,
		"Golden Die run pauses on real boss reward popup")
	var ui := LiveUiProbe.snapshot(main)
	var choice_ids: Array[String] = LiveUiProbe.choice_ids(
		main, LiveUiProbe.BOSS_REWARD)
	var boss_details: Dictionary = ui.get("boss_reward", {})
	var summaries: Array = boss_details.get("choice_summaries", [])

	assert_eq(choice_ids.size(), 6,
		"Golden Die exposes the promised 6 boss reward choices")
	assert_eq(summaries.size(), 6,
		"observer sees one rendered summary per Golden Die reward choice")
	assert_string_contains(str(boss_details.get("title", "")), "6개 후보")
	assert_true(_boss_reward_summaries_have_rendered_text(summaries, choice_ids))


func test_live_merge_reward_popup_selection_attaches_upgrade() -> void:
	var main = await _start_main_to_build()
	_clear_run_cards(main)
	main.game_state.gold = 10
	main.game_state.bench[0] = CardInstance.create("sp_assembly")
	main.game_state.bench[1] = CardInstance.create("sp_assembly")
	main.game_state.state_changed.emit()
	await wait_process_frames(1)

	assert_gt(main.build_phase.shop._offered_ids.size(), 0,
		"live shop has at least one purchase slot")
	main.build_phase.shop._offered_ids[0] = "sp_assembly"
	main.build_phase.shop._coin_slots.clear()
	main.build_phase.shop._update_visuals()

	assert_true(main.build_phase.shop.try_purchase(0),
		"buying the third visible copy triggers the live merge signal")
	await wait_process_frames(2)

	assert_true(main.upgrade_choice_popup.visible,
		"★1→★2 merge opens the real upgrade reward popup")
	var ui := LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.UPGRADE_CHOICE],
		"merge reward popup owns the live UI")
	assert_true(ui["actionable"][LiveUiProbe.UPGRADE_CHOICE],
		"merge reward popup has an actionable selection")
	var choices: Array[String] = LiveUiProbe.choice_ids(main, LiveUiProbe.UPGRADE_CHOICE)
	assert_eq(choices.size(), 3,
		"merge reward popup offers three upgrades")
	var selected_upgrade: String = choices[0]
	var survivor: CardInstance = main.game_state.bench[0]
	assert_not_null(survivor)
	assert_eq(survivor.star_level, 2)
	assert_eq(survivor.upgrades.size(), 0,
		"merge reward waits for popup selection before attachment")

	assert_true(LiveUiProbe.select_choice(main, LiveUiProbe.UPGRADE_CHOICE, 0),
		"popup selection path accepts the visible merge reward")
	await wait_process_frames(2)

	ui = LiveUiProbe.snapshot(main)
	assert_false(ui["has_modal"],
		"merge reward selection returns modal ownership to build")
	assert_false(ui["chain_visible"],
		"merge reward selection does not leave chain feedback visible")
	assert_false(main.upgrade_choice_popup.visible,
		"merge reward popup closes through its own selection path")
	assert_eq(LiveUiProbe.choice_ids(main, LiveUiProbe.UPGRADE_CHOICE).size(), 0,
		"merge reward popup clears choices after selection")
	assert_eq(survivor.upgrades.size(), 1,
		"selected merge reward attaches to the survivor")
	assert_true(_card_has_upgrade_id(survivor, selected_upgrade),
		"the exact selected upgrade is attached through merge_bonus")
	assert_true(main.build_phase.visible,
		"build phase remains actionable after merge reward selection")


func test_live_first_build_shows_chain_feedback_before_battle() -> void:
	var main = await _start_main_to_build()
	main.chain_feedback_delay_sec = 0.01
	main.chain_feedback_delay_per_event_sec = 0.0
	main.game_state.board[0] = CardInstance.create("ne_wanderers")
	main.build_phase._refresh_all()

	main.build_phase.confirm_button.pressed.emit()

	assert_eq(main.current_phase, main.Phase.CHAIN,
		"BUILD COMPLETE enters visible chain phase before battle")
	assert_true(main.chain_visual.visible,
		"first growth chain feedback is visible")
	assert_string_contains(main.chain_visual.counter_label.text, "Triggers")
	await main.get_tree().create_timer(0.03).timeout
	assert_eq(main.current_phase, main.Phase.BATTLE,
		"test drains the short chain pause before cleanup")
	var ui := LiveUiProbe.snapshot(main)
	var battle_status: Dictionary = ui.get("battle_status", {})
	var battle_text := str(battle_status.get("text", ""))
	var battle_data: Dictionary = battle_status.get("data", {})
	assert_true(bool(battle_status.get("visible", false)),
		"battle start status is visible after real battle start")
	assert_string_contains(battle_text, "BATTLE R1")
	assert_string_contains(battle_text, "Start")
	assert_string_contains(battle_text, "Now")
	assert_eq(int(battle_data.get("round", 0)), 1)
	assert_gt(int(battle_data.get("ally_start", 0)), 0)
	assert_gt(int(battle_data.get("enemy_start", 0)), 0)
	assert_gte(int(battle_data.get("ally_remaining", -1)), 0)
	assert_gte(int(battle_data.get("enemy_remaining", -1)), 0)
	assert_lte(
		int(battle_data.get("ally_remaining", 0)),
		int(battle_data.get("ally_start", 0)))
	assert_lte(
		int(battle_data.get("enemy_remaining", 0)),
		int(battle_data.get("enemy_start", 0)))
	main.battle_phase.stop()


func test_live_chain_event_history_is_readable_before_battle() -> void:
	var main = await _start_main_to_build()
	main.chain_feedback_delay_sec = 0.03
	main.chain_feedback_delay_per_event_sec = 0.0
	main.game_state.board[0] = CardInstance.create("sp_assembly")
	main.game_state.board[1] = CardInstance.create("sp_workshop")
	main.build_phase._refresh_all()

	main.build_phase.confirm_button.pressed.emit()

	assert_eq(main.current_phase, main.Phase.CHAIN)
	assert_true(main.chain_visual.visible)
	assert_true(main.chain_visual.event_panel.visible,
		"real chain events open the readability panel")
	var log: String = main.chain_visual.get_event_log_text()
	assert_string_contains(log, "증기 조립소 -> 태엽 공방")
	assert_string_contains(log, "+Unit")
	assert_string_contains(log, "+Stats")
	assert_string_contains(log, "Complete:")
	assert_string_contains(main.chain_visual.counter_label.text, "Triggers:")
	var ui := LiveUiProbe.snapshot(main)
	assert_eq(ui["phase"], "CHAIN")
	assert_true(ui["layout_rects"].get("chain_event_panel", {}).get("visible", false),
		"observer exports visible chain event panel rect")
	assert_string_contains(ui["chain_feedback"].get("event_log_text", ""), "Complete:")
	await main.get_tree().create_timer(0.05).timeout
	assert_eq(main.current_phase, main.Phase.BATTLE)
	main.battle_phase.stop()

	await main._on_battle_finished({
		"player_won": true,
		"ally_survived": 1,
		"enemy_survived": 0,
	})

	assert_eq(main.current_phase, main.Phase.BUILD)
	assert_true(main.build_phase.is_last_chain_history_visible(),
		"next build keeps a reviewable last-chain history")
	var last_chain: String = main.build_phase.get_last_chain_history_text()
	assert_string_contains(last_chain, "Complete:")
	assert_string_contains(last_chain, "증기 조립소 -> 태엽 공방")
	ui = LiveUiProbe.snapshot(main)
	assert_true(ui["layout_rects"].get("last_chain_panel", {}).get("visible", false),
		"observer exports visible last-chain panel rect")
	assert_false(ui["layout_rects"].get("battle_status", {}).get("visible", false),
		"observer confirms battle status is hidden after returning to build")
	assert_true(ui["last_chain_history"].get("visible", false))


func test_live_chain_feedback_delay_scales_and_can_be_skipped_once() -> void:
	var main = await _start_main_to_build()
	main.chain_feedback_delay_sec = 0.12
	main.chain_feedback_delay_per_event_sec = 0.10
	main.chain_feedback_max_delay_sec = 0.25
	assert_almost_eq(main._get_chain_feedback_delay(1), 0.12, 0.001)
	assert_almost_eq(main._get_chain_feedback_delay(4), 0.25, 0.001)
	main.game_state.board[0] = CardInstance.create("sp_assembly")
	main.game_state.board[1] = CardInstance.create("sp_workshop")
	main.build_phase._refresh_all()

	main.build_phase.confirm_button.pressed.emit()

	assert_eq(main.current_phase, main.Phase.CHAIN)
	assert_true(main.skip_chain_feedback(),
		"manual skip advances out of the readable chain pause")
	assert_eq(main.current_phase, main.Phase.BATTLE)
	assert_false(main.skip_chain_feedback(),
		"skip is idempotent after the phase has already advanced")
	await main.get_tree().create_timer(0.28).timeout
	assert_eq(main.current_phase, main.Phase.BATTLE,
		"the original timer cannot advance the phase a second time")
	main.battle_phase.stop()


func test_live_battle_result_settlement_and_gameover_save_meta() -> void:
	var main = await _start_main_to_build()
	main.game_state.board[0] = CardInstance.create("sp_assembly")
	main._gold_before_effects = main.game_state.gold

	await main._on_battle_finished({
		"player_won": false,
		"ally_survived": 0,
		"enemy_survived": 1,
	})

	assert_eq(main.game_state.round_num, 2,
		"nonfatal battle result advances through settlement to next round")
	assert_eq(main.current_phase, main.Phase.BUILD)
	assert_false(main.game_over_popup.visible,
		"nonfatal settlement does not show game over")

	main.game_state.hp = 1
	main._gold_before_effects = main.game_state.gold
	await main._on_battle_finished({
		"player_won": false,
		"ally_survived": 0,
		"enemy_survived": 10,
	})

	assert_true(main._game_over, "fatal battle result sets game over flag")
	assert_true(main.game_over_popup.visible, "fatal result shows game over popup")
	var defeat_summary: String = main.game_over_popup.summary_label.text
	assert_string_contains(defeat_summary, "Final HP: -2")
	assert_string_contains(defeat_summary, "Last fight: 0 allies / 10 enemies survived")
	assert_string_contains(defeat_summary, "Damage: 3 HP (1 -> -2)")
	assert_string_contains(defeat_summary,
		"Next run: last fight left 10 enemies; add damage or growth before the R4 boss.")
	assert_eq(main._meta_progress.runs_finished, 1)
	assert_eq(main._meta_progress.last_result, "defeat")

	var loaded = MetaProgressScript.new()
	loaded.load_or_create(TEST_META_PATH)
	assert_eq(loaded.runs_started, 1)
	assert_eq(loaded.runs_finished, 1)
	assert_eq(loaded.last_result, "defeat")


func test_live_battle_result_popup_explains_aftermath_before_settlement() -> void:
	var main = await _start_main_to_build()
	main.battle_result_delay_sec = 0.08
	main.game_state.round_num = 3
	main.game_state.hp = 30
	main.game_state.gold = 12
	main._gold_before_effects = main.game_state.gold
	main._last_ally_count = 4
	main._last_enemy_count = 9

	main._on_battle_finished({
		"player_won": false,
		"ally_survived": 0,
		"enemy_survived": 3,
	})
	await wait_process_frames(2)

	var ui := LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.BATTLE_RESULT],
		"battle result popup owns the UI before settlement continues")
	var details: Dictionary = ui["battle_result"]
	assert_eq(details.get("result_text", ""), "DEFEAT")
	var detail_text := str(details.get("detail_text", ""))
	assert_string_contains(detail_text, "Round 3 lost")
	assert_string_contains(detail_text, "Enemies: 3/9 survived")
	assert_string_contains(detail_text, "HP: 30 ->")
	assert_string_contains(detail_text, "Gold: 12 ->")
	assert_string_contains(detail_text, "Next:")
	var context: Dictionary = details.get("context", {})
	assert_eq(int(context.get("damage", -1)),
		GameState.compute_defeat_damage(3, 3),
		"popup context records the exact HP damage basis")

	await main.get_tree().create_timer(0.1).timeout
	assert_eq(main.current_phase, main.Phase.BUILD,
		"battle result auto-continues to settlement after the readable pause")
	ui = LiveUiProbe.snapshot(main)
	var recap: Dictionary = ui.get("last_settlement_recap", {})
	assert_true(bool(recap.get("visible", false)),
		"next BUILD shows a settlement recap after income is applied")
	var recap_text := str(recap.get("text", ""))
	assert_string_contains(recap_text, "LAST SETTLEMENT R3")
	assert_string_contains(recap_text, "Gold:")
	assert_string_contains(recap_text, "income")
	assert_string_contains(recap_text, "interest")
	assert_string_contains(recap_text, "Terazin:")
	assert_string_contains(recap_text, "Next: R4 BUILD")
	assert_string_contains(recap_text, "R4 boss reward this fight")
	var recap_data: Dictionary = recap.get("data", {})
	assert_eq(int(recap_data.get("round", -1)), 3)
	assert_eq(int(recap_data.get("next_round", -1)), 4)
	assert_eq(int(recap_data.get("gold_before", -1)), 12)
	assert_eq(int(recap_data.get("interest_basis_gold", -1)), 12)
	assert_eq(int(recap_data.get("gold_after", -1)),
		int(recap_data.get("gold_before", 0))
		+ int(recap_data.get("base_income", 0))
		+ int(recap_data.get("interest", 0)))


func test_live_first_boss_reward_pause_is_visible_and_actionable() -> void:
	var main = await _start_main_to_build()
	main.game_state.board[0] = CardInstance.create("sp_assembly")
	main.game_state.round_num = 4
	main._gold_before_effects = main.game_state.gold
	main.current_phase = main.Phase.BATTLE
	main.build_phase.visible = false

	await main._on_battle_finished({
		"player_won": true,
		"ally_survived": 1,
		"enemy_survived": 0,
	})

	assert_true(main.boss_reward_popup.visible,
		"surviving R4 pauses on boss reward choices")
	assert_false(main.battle_result_popup.visible,
		"battle result is cleared before reward selection")
	assert_eq(main.current_phase, main.Phase.BATTLE,
		"reward selection pauses before settlement advances")
	assert_eq(main.game_state.round_num, 4,
		"reward selection does not advance the round before a choice")
	var ui := LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.BOSS_REWARD],
		"boss reward popup owns the live UI")
	assert_true(ui["actionable"][LiveUiProbe.BOSS_REWARD],
		"boss reward popup has at least one visible selection")
	var choice_ids: Array[String] = LiveUiProbe.choice_ids(main, LiveUiProbe.BOSS_REWARD)
	assert_gt(choice_ids.size(), 0,
		"reward popup has selectable choices")
	var boss_details: Dictionary = ui.get("boss_reward", {})
	var summaries: Array = boss_details.get("choice_summaries", [])
	assert_eq(summaries.size(), choice_ids.size(),
		"observer exports rendered text for each boss reward card")
	assert_true(_boss_reward_summaries_have_rendered_text(summaries, choice_ids))

	var no_target_idx := _first_no_target_reward_index(choice_ids)
	assert_gte(no_target_idx, 0, "smoke chooses an immediately actionable reward")
	assert_false(bool(summaries[no_target_idx].get("needs_target", true)),
		"rendered summary marks the immediate reward as no-target")
	var no_target_reward := choice_ids[no_target_idx]
	assert_true(LiveUiProbe.select_choice(main, LiveUiProbe.BOSS_REWARD, no_target_idx),
		"popup selection path accepts the immediate reward")
	await wait_process_frames(2)

	assert_eq(main.game_state.round_num, 5,
		"selecting a reward settles R4 and advances to R5 build")
	assert_eq(main.current_phase, main.Phase.BUILD)
	assert_true(main.build_phase.visible, "build phase resumes after reward")
	ui = LiveUiProbe.snapshot(main)
	assert_false(ui["chain_visible"],
		"boss reward settlement returns to build without stale chain feedback")
	assert_false(main.boss_reward_popup.visible,
		"reward popup closes through its own selection path")
	assert_eq(LiveUiProbe.choice_ids(main, LiveUiProbe.BOSS_REWARD).size(), 0,
		"reward popup clears choices after selection")


func test_live_targeted_boss_reward_uses_target_overlay_and_applies_effect() -> void:
	var main = await _start_main_to_build()
	_clear_run_cards(main)
	var target: CardInstance = CardInstance.create("sp_assembly")
	var max_star_card: CardInstance = CardInstance.create("sp_workshop")
	max_star_card.evolve_star()
	max_star_card.evolve_star()
	main.game_state.board[0] = target
	main.game_state.board[1] = max_star_card
	main.game_state.terazin = 0
	main.game_state.round_num = 4
	main._gold_before_effects = main.game_state.gold
	main.current_phase = main.Phase.BATTLE
	main.build_phase.visible = false
	main.build_phase._refresh_all()

	var forced_choices: Array[String] = ["r4_1"]
	main.boss_reward_popup.show_choices(forced_choices)
	await wait_process_frames(1)

	var ui := LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.BOSS_REWARD],
		"forced targeted boss reward owns the live UI before selection")
	assert_eq(ui["choices"][LiveUiProbe.BOSS_REWARD], ["r4_1"])
	var boss_details: Dictionary = ui.get("boss_reward", {})
	var summaries: Array = boss_details.get("choice_summaries", [])
	assert_eq(summaries.size(), 1)
	assert_true(_boss_reward_summaries_have_rendered_text(summaries, ["r4_1"]))
	assert_true(bool(summaries[0].get("needs_target", false)),
		"rendered summary marks targeted rewards before target overlay opens")
	assert_true(LiveUiProbe.select_choice(main, LiveUiProbe.BOSS_REWARD, 0),
		"popup selection path accepts the targeted reward")
	await wait_process_frames(2)

	ui = LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.TARGET_SELECT],
		"targeted reward opens the field target overlay")
	assert_true(ui["actionable"][LiveUiProbe.TARGET_SELECT],
		"target overlay has an eligible field target")
	assert_true(main.build_phase.visible,
		"build surface is visible while choosing a boss reward target")
	assert_false(main.boss_reward_popup.visible,
		"boss reward popup closes before target selection")
	assert_eq(LiveUiProbe.target_field_indices(main), [0],
		"only non-max-star card is selectable for r4_1")
	var target_details: Dictionary = ui["target_select"]
	var preview_text := "\n".join(target_details.get("preview_texts", []))
	assert_string_contains(str(target_details.get("instruction", "")),
		"choose target card")
	assert_string_contains(preview_text, "★1 -> ★2")
	assert_string_contains(preview_text, "MAX ★3")
	var layout_rects: Dictionary = ui["layout_rects"]
	assert_true(layout_rects.get("target_instruction", {}).get("visible", false),
		"observer exports visible target instruction rect")
	assert_true(layout_rects.get("target_detail", {}).get("visible", false),
		"observer exports visible target detail rect")
	assert_true(layout_rects.get("confirm_button", {}).get("visible", false),
		"observer exports visible confirm button rect")

	assert_eq(target.star_level, 1)
	assert_eq(main.game_state.terazin, 0)
	assert_true(LiveUiProbe.select_target(main, 0),
		"public target overlay selection accepts the eligible card")
	await wait_process_frames(2)

	ui = LiveUiProbe.snapshot(main)
	assert_eq(target.star_level, 2,
		"r4_1 evolves the selected target")
	assert_gte(main.game_state.terazin, 4,
		"r4_1 grants its target reward terazin before settlement income")
	assert_eq(main.game_state.round_num, 5,
		"targeted reward settles R4 and advances to R5")
	assert_eq(main.current_phase, main.Phase.BUILD)
	assert_true(main.build_phase.visible)
	assert_false(ui["has_modal"],
		"targeted reward selection returns modal ownership to build")
	assert_false(ui["chain_visible"],
		"targeted reward settlement does not leave stale chain feedback")
	assert_false(main.build_phase.target_overlay.visible,
		"target overlay closes after target selection")


func test_live_boss_reward_continuity_r4_r8_r12() -> void:
	var main = await _start_main_to_build()
	main.game_state.board[0] = CardInstance.create("sp_assembly")
	var selected_rewards: Array[String] = []

	for boss_round in [4, 8, 12]:
		var selected_reward: String = await _win_boss_round_and_select_immediate_reward(
			main, boss_round)
		selected_rewards.append(selected_reward)

	assert_eq(main.current_phase, main.Phase.BUILD)
	assert_eq(main.game_state.round_num, 13)
	assert_true(main.build_phase.visible,
		"R12 reward settlement resumes the R13 build")
	assert_false(main.boss_reward_popup.visible)
	assert_false(main.battle_result_popup.visible)
	assert_eq(selected_rewards.size(), 3,
		"three boss reward selections completed")
	for reward_id in selected_rewards:
		assert_ne(reward_id, "")


func test_live_final_round_victory_saves_meta() -> void:
	var main = await _start_main_to_build()
	main.game_state.board[0] = CardInstance.create("sp_assembly")
	main.game_state.round_num = Enums.MAX_ROUNDS
	main.game_state.hp = 7
	main._gold_before_effects = main.game_state.gold

	await main._on_battle_finished({
		"player_won": true,
		"ally_survived": 1,
		"enemy_survived": 0,
	})

	assert_true(main._game_over, "final-round win ends the run")
	assert_true(main.game_over_popup.visible, "victory result shows overlay")
	assert_eq(main.game_over_popup.title_label.text, "VICTORY!")
	assert_string_contains(main.game_over_popup.summary_label.text,
		"New unlocks available")
	assert_string_contains(main.game_over_popup.summary_label.text, "난이도 2")
	var ui := LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.GAME_OVER],
		"observer reports game-over ownership")
	assert_string_contains(ui["game_over"].get("summary_text", ""),
		"New unlocks available")
	assert_eq(main._meta_progress.runs_finished, 1)
	assert_eq(main._meta_progress.last_result, "victory")

	var loaded = MetaProgressScript.new()
	loaded.load_or_create(TEST_META_PATH)
	assert_eq(loaded.runs_started, 1)
	assert_eq(loaded.runs_finished, 1)
	assert_eq(loaded.last_result, "victory")
	assert_eq(loaded.max_difficulty_unlocked, 2)


func test_live_visible_control_playthrough_reaches_terminal_overlay() -> void:
	await _run_visible_control_playthrough_to_terminal(
		Enums.CommanderType.GAMBLER,
		Enums.TalismanType.FLINT)


func test_live_breeder_visible_control_playthrough_reaches_terminal_overlay() -> void:
	await _run_visible_control_playthrough_to_terminal(
		Enums.CommanderType.BREEDER,
		Enums.TalismanType.FLINT)


func test_live_smith_visible_control_playthrough_resolves_start_upgrade() -> void:
	_unlock_commander_for_smoke(Enums.CommanderType.SMITH)

	var result: Dictionary = await _run_visible_control_playthrough_to_terminal(
		Enums.CommanderType.SMITH,
		Enums.TalismanType.FLINT)

	var free_upgrade_sources: Dictionary = result.get("free_upgrade_sources", {})
	assert_gt(int(free_upgrade_sources.get("smith_start", 0)), 0,
		"Smith natural run resolves the start upgrade through visible controls")


func test_live_raider_visible_control_playthrough_resolves_carried_win_count_upgrade() -> void:
	_unlock_commander_for_smoke(Enums.CommanderType.RAIDER)

	var result: Dictionary = await _run_visible_control_playthrough_to_terminal(
		Enums.CommanderType.RAIDER,
		Enums.TalismanType.FLINT,
		{"win_count": 2})

	var free_upgrade_sources: Dictionary = result.get("free_upgrade_sources", {})
	assert_gt(int(free_upgrade_sources.get("raider_win_streak", 0)), 0,
		"Raider carried win counter resolves a 3-win upgrade through visible controls")


func test_live_strategist_visible_control_playthrough_resolves_swap() -> void:
	_unlock_commander_for_smoke(Enums.CommanderType.STRATEGIST)
	_unlock_talisman_for_smoke(Enums.TalismanType.WAR_DRUM)

	var result: Dictionary = await _run_visible_control_playthrough_to_terminal(
		Enums.CommanderType.STRATEGIST,
		Enums.TalismanType.WAR_DRUM,
		{},
		{"use_strategist_swap": true})

	assert_gt(int(result.get("strategist_swaps", 0)), 0,
		"Strategist live run resolves SWAP through visible controls")


func _run_visible_control_playthrough_to_terminal(
		commander_type: int,
		talisman_type: int,
		commander_state_setup: Dictionary = {},
		play_options: Dictionary = {}) -> Dictionary:
	Engine.time_scale = 8.0
	var main = await _start_main_to_build(talisman_type, commander_type)
	main.chain_feedback_delay_sec = 0.01
	main.chain_feedback_delay_per_event_sec = 0.0
	main.chain_feedback_max_delay_sec = 0.01
	main.battle_result_delay_sec = 0.0
	main.battle_phase.set_speed(80.0)
	assert_eq(main.game_state.commander_type, commander_type)
	assert_eq(main.game_state.talisman_type, talisman_type)
	for key in commander_state_setup:
		main.game_state.commander_state[key] = commander_state_setup[key]

	var purchased := 0
	var moved := 0
	var upgrades_bought := 0
	var commander_free_upgrades := 0
	var free_upgrade_sources := {}
	var strategist_swaps := 0
	var battles_seen := 0
	var rounds_seen: Array[int] = []
	var safety := 0

	while not main._game_over and safety < 80:
		safety += 1
		var ui := LiveUiProbe.snapshot(main)
		var active_modals: Array = ui.get("active_modals", [])
		if active_modals == [LiveUiProbe.GAME_OVER]:
			break
		if active_modals == [LiveUiProbe.BATTLE_RESULT]:
			await wait_process_frames(3)
			continue
		if bool(ui.get("has_modal", false)):
			var before_free_upgrades := _count_attached_upgrades(main)
			var pending_upgrade_source := str(
				main.build_phase._pending_upgrade.get("source", ""))
			assert_true(await _resolve_visible_modal_by_controls(main),
				"visible-control playthrough resolves modal %s" % [active_modals])
			var after_free_upgrades := _count_attached_upgrades(main)
			if pending_upgrade_source != "" \
					and after_free_upgrades > before_free_upgrades:
				commander_free_upgrades += 1
				free_upgrade_sources[pending_upgrade_source] = \
					int(free_upgrade_sources.get(pending_upgrade_source, 0)) + 1
			await wait_process_frames(2)
			continue

		match main.current_phase:
			main.Phase.BUILD:
				if not rounds_seen.has(main.game_state.round_num):
					rounds_seen.append(main.game_state.round_num)
				var build_actions: Dictionary = \
					await _play_build_by_visible_controls(main)
				purchased += int(build_actions.get("purchased", 0))
				moved += int(build_actions.get("moved", 0))
				upgrades_bought += int(build_actions.get("upgrades_bought", 0))
				if bool(play_options.get("use_strategist_swap", false)) \
						and strategist_swaps <= 0 \
						and await _perform_strategist_swap_by_visible_controls(main):
					strategist_swaps += 1
				assert_true(_press_build_complete_by_controls(main),
					"visible BUILD COMPLETE button advances the run")
				await wait_process_frames(2)
			main.Phase.CHAIN:
				assert_true(_press_space_by_controls(main),
					"visible-control playthrough can skip readable chain pause")
				await wait_process_frames(2)
			main.Phase.BATTLE:
				battles_seen += 1
				assert_true(await _wait_for_next_control_surface(main, 900),
					"natural battle returned to a control surface")
			_:
				await wait_process_frames(2)

	assert_true(main._game_over,
		"visible-control playthrough reaches natural defeat or victory")
	assert_true(main.game_over_popup.visible,
		"terminal result is shown through the real game-over popup")
	assert_gt(purchased, 0, "playthrough bought at least one visible shop card")
	assert_gt(moved, 0, "playthrough drag/dropped at least one card onto FIELD")
	assert_gt(battles_seen, 0, "playthrough entered at least one real battle")
	assert_gt(rounds_seen.size(), 0, "playthrough visited at least one BUILD round")

	var ui_final := LiveUiProbe.snapshot(main)
	assert_eq(ui_final["active_modals"], [LiveUiProbe.GAME_OVER],
		"observer reports final game-over ownership")
	var final_summary := str(ui_final["game_over"].get("summary_text", ""))
	assert_string_contains(final_summary, "Run bests:")
	assert_true(["defeat", "victory"].has(main._meta_progress.last_result))
	if main._meta_progress.last_result == "defeat":
		assert_string_contains(final_summary, "Defeated at round")
		assert_string_contains(final_summary, "Final HP:")
		assert_string_contains(final_summary, "Last fight:")
		assert_string_contains(final_summary, "Damage:")
		assert_string_contains(final_summary, "Next run:")
	else:
		assert_string_contains(final_summary, "All 15 rounds cleared!")
	assert_eq(main._meta_progress.runs_finished, 1)
	var loaded = MetaProgressScript.new()
	loaded.load_or_create(TEST_META_PATH)
	assert_eq(loaded.runs_finished, 1)
	assert_eq(loaded.last_result, main._meta_progress.last_result)
	assert_gt(upgrades_bought, 0,
		"playthrough bought and targeted at least one visible upgrade")
	return {
		"commander_free_upgrades": commander_free_upgrades,
		"free_upgrade_sources": free_upgrade_sources,
		"purchased": purchased,
		"moved": moved,
		"upgrades_bought": upgrades_bought,
		"battles_seen": battles_seen,
		"strategist_swaps": strategist_swaps,
	}


func _start_main_to_build(
		talisman_type: int = Enums.TalismanType.FLINT,
		commander_type: int = Enums.CommanderType.GAMBLER):
	var main = MainScene.instantiate()
	main.meta_progress_save_path = TEST_META_PATH
	main.battle_result_delay_sec = 0.0
	main.play_logger_enabled = false
	add_child_autofree(main)
	await wait_process_frames(2)

	var ui := LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.RUN_START],
		"main scene starts with run-start owning the UI")
	assert_true(ui["actionable"][LiveUiProbe.RUN_START],
		"run-start screen has an actionable start button")
	assert_true(LiveUiProbe.press_run_start(main),
		"observer presses the run-start button")
	await wait_process_frames(2)

	ui = LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.COMMANDER_SELECT],
		"commander selection owns the UI after start")
	assert_true(str(commander_type) in ui["choices"][LiveUiProbe.COMMANDER_SELECT],
		"requested commander is visible")
	var commander_details: Dictionary = ui.get("commander_select", {})
	var commander_context: String = str(commander_details.get("context_text", ""))
	assert_string_contains(commander_context, "커맨더")
	assert_string_contains(commander_context, "런 전체")
	assert_true(_rect_is_visible(commander_details.get("context_rect", {})),
		"commander selection context is visible")
	assert_true(LiveUiProbe.select_commander(main, commander_type),
		"observer selects the requested commander")
	await wait_process_frames(2)

	ui = LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.TALISMAN_SELECT],
		"talisman selection owns the UI after commander")
	assert_true(str(talisman_type) in ui["choices"][LiveUiProbe.TALISMAN_SELECT],
		"requested talisman is visible")
	var talisman_details: Dictionary = ui.get("talisman_select", {})
	var talisman_context: String = str(talisman_details.get("context_text", ""))
	var commander_name := str(Commander.get_data(commander_type).get("name", ""))
	assert_string_contains(talisman_context, "선택한 커맨더")
	assert_string_contains(talisman_context, commander_name)
	assert_string_contains(talisman_context, "부적")
	assert_true(_rect_is_visible(talisman_details.get("context_rect", {})),
		"talisman selection context is visible")
	assert_true(LiveUiProbe.select_talisman(main, talisman_type),
		"observer selects the requested talisman")
	await wait_process_frames(3)

	ui = LiveUiProbe.snapshot(main)
	assert_false(ui["has_modal"],
		"run setup returns control to the build phase")
	var readiness: Dictionary = ui.get("build_readiness", {})
	var readiness_text: String = str(readiness.get("text", ""))
	assert_true(bool(readiness.get("visible", false)),
		"BUILD readiness cue is visible after real run setup")
	assert_string_contains(readiness_text, "FIELD:")
	assert_string_contains(readiness_text, "체인/전투")
	assert_string_contains(readiness_text, "BENCH:")
	assert_string_contains(readiness_text, "ENEMY:")
	assert_string_contains(readiness_text, "Next:")
	assert_true(_rect_is_visible(readiness.get("rect", {})),
		"BUILD readiness cue has a visible rect")
	var milestone: Dictionary = ui.get("run_milestone", {})
	var milestone_text := str(milestone.get("text", ""))
	var round_label_text := str(milestone.get("round_label_text", ""))
	var progress_rail_text := str(milestone.get("progress_rail_text", ""))
	assert_true(bool(milestone.get("visible", false)),
		"run milestone is visible in the BUILD HUD")
	assert_string_contains(milestone_text, "Goal:")
	assert_string_contains(milestone_text, "R4 boss reward")
	assert_string_contains(round_label_text, "Round 1/15")
	assert_string_contains(round_label_text, "R4 boss reward")
	assert_string_contains(progress_rail_text, "R1 NOW")
	assert_string_contains(progress_rail_text, "rewards")
	assert_string_contains(progress_rail_text, "R4 next")
	assert_string_contains(progress_rail_text, "R8")
	assert_string_contains(progress_rail_text, "R12")
	assert_string_contains(progress_rail_text, "R15 final")
	assert_string_contains(round_label_text, progress_rail_text)
	assert_true(_rect_is_visible(milestone.get("rect", {})),
		"run milestone has a visible rect")
	var enemy_preview: Dictionary = ui.get("enemy_pressure_preview", {})
	var enemy_preview_text := str(enemy_preview.get("text", ""))
	var enemy_preview_data: Dictionary = enemy_preview.get("data", {})
	assert_true(bool(enemy_preview.get("visible", false)),
		"enemy pressure preview is visible before BUILD COMPLETE")
	assert_string_contains(enemy_preview_text, "ENEMY:")
	assert_string_contains(enemy_preview_text, "ATK")
	assert_string_contains(enemy_preview_text, "HP")
	assert_false(bool(enemy_preview_data.get("exact", true)),
		"enemy pressure preview is explicitly non-exact")
	var rects: Dictionary = ui.get("layout_rects", {})
	assert_false(_rects_intersect(
		readiness.get("rect", {}),
		rects.get("confirm_button", {})),
		"BUILD readiness cue does not overlap BUILD COMPLETE")
	assert_false(_rects_intersect(
		readiness.get("rect", {}),
		rects.get("field_container", {})),
		"BUILD readiness cue does not overlap FIELD cards")

	return main


func _unlock_commander_for_smoke(commander_type: int) -> void:
	var progress = MetaProgressScript.new()
	progress.load_or_create(TEST_META_PATH)
	if not progress.unlocked_commanders.has(commander_type):
		progress.unlocked_commanders.append(commander_type)
	assert_eq(progress.save(TEST_META_PATH), OK,
		"smoke profile unlocks requested commander")


func _unlock_talisman_for_smoke(talisman_type: int) -> void:
	var progress = MetaProgressScript.new()
	progress.load_or_create(TEST_META_PATH)
	if not progress.unlocked_talismans.has(talisman_type):
		progress.unlocked_talismans.append(talisman_type)
	assert_eq(progress.save(TEST_META_PATH), OK,
		"smoke profile unlocks requested talisman")


func _count_attached_upgrades(main) -> int:
	var total := 0
	for card in main.game_state.board:
		if card != null:
			total += (card as CardInstance).upgrades.size()
	for card in main.game_state.bench:
		if card != null:
			total += (card as CardInstance).upgrades.size()
	return total


func _first_no_target_reward_index(reward_ids: Array[String]) -> int:
	for i in reward_ids.size():
		if int(BossRewardDB.get_data(reward_ids[i]).get("needs_target", 0)) == 0:
			return i
	return -1


func _clear_run_cards(main) -> void:
	for i in main.game_state.board.size():
		main.game_state.board[i] = null
	for i in main.game_state.bench.size():
		main.game_state.bench[i] = null


func _card_has_upgrade_id(card: CardInstance, upgrade_id: String) -> bool:
	for upgrade in card.upgrades:
		if upgrade.get("id", "") == upgrade_id:
			return true
	return false


func _boss_reward_summaries_have_rendered_text(
		summaries: Array, ids: Array[String]) -> bool:
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


func _rect_is_visible(value) -> bool:
	var rect: Dictionary = value if value is Dictionary else {}
	return bool(rect.get("visible", false)) \
		and float(rect.get("w", 0.0)) > 0.0 \
		and float(rect.get("h", 0.0)) > 0.0


func _rects_intersect(a_value, b_value) -> bool:
	var a: Dictionary = a_value if a_value is Dictionary else {}
	var b: Dictionary = b_value if b_value is Dictionary else {}
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


func _win_boss_round_and_select_immediate_reward(main, boss_round: int) -> String:
	main.game_state.round_num = boss_round
	main._gold_before_effects = main.game_state.gold
	main.current_phase = main.Phase.BATTLE
	main.build_phase.visible = false

	await main._on_battle_finished({
		"player_won": true,
		"ally_survived": 1,
		"enemy_survived": 0,
	})

	assert_true(main.boss_reward_popup.visible,
		"R%d survival pauses on boss reward choices" % boss_round)
	assert_false(main.battle_result_popup.visible,
		"R%d clears battle result before reward choice" % boss_round)
	assert_eq(main.current_phase, main.Phase.BATTLE,
		"R%d reward pauses before settlement" % boss_round)
	assert_eq(main.game_state.round_num, boss_round,
		"R%d does not advance until reward is selected" % boss_round)
	var ui := LiveUiProbe.snapshot(main)
	assert_eq(ui["active_modals"], [LiveUiProbe.BOSS_REWARD],
		"R%d boss reward owns the live UI" % boss_round)
	assert_true(ui["actionable"][LiveUiProbe.BOSS_REWARD],
		"R%d boss reward has actionable choices" % boss_round)
	var choice_ids: Array[String] = LiveUiProbe.choice_ids(main, LiveUiProbe.BOSS_REWARD)
	assert_gt(choice_ids.size(), 0,
		"R%d has selectable reward choices" % boss_round)

	var no_target_idx := _first_no_target_reward_index(choice_ids)
	assert_gte(no_target_idx, 0,
		"R%d smoke chooses an immediately actionable reward" % boss_round)
	var no_target_reward := choice_ids[no_target_idx]
	assert_true(LiveUiProbe.select_choice(main, LiveUiProbe.BOSS_REWARD, no_target_idx),
		"R%d popup selection path accepts the immediate reward" % boss_round)
	await wait_process_frames(2)

	assert_eq(main.game_state.round_num, boss_round + 1,
		"R%d reward settles and advances one round" % boss_round)
	assert_eq(main.current_phase, main.Phase.BUILD,
		"R%d reward resumes build phase" % boss_round)
	assert_true(main.build_phase.visible,
		"R%d build phase visible after reward" % boss_round)
	var ui_after := LiveUiProbe.snapshot(main)
	assert_false(ui_after["chain_visible"],
		"R%d reward settlement returns to build without stale chain feedback" % boss_round)
	assert_false(main.boss_reward_popup.visible,
		"R%d reward popup closed after selection" % boss_round)
	assert_eq(LiveUiProbe.choice_ids(main, LiveUiProbe.BOSS_REWARD).size(), 0,
		"R%d reward popup choices cleared after selection" % boss_round)
	assert_false(main.battle_result_popup.visible,
		"R%d battle result remains cleared after settlement" % boss_round)
	return no_target_reward


func _play_build_by_visible_controls(main) -> Dictionary:
	var result := {"purchased": 0, "moved": 0, "upgrades_bought": 0}
	result["moved"] = int(result["moved"]) \
		+ _move_bench_to_field_by_visible_drop(main)

	for _i in 3:
		if _first_empty_bench_idx(main) < 0:
			break
		var slot_idx := _first_affordable_shop_slot(main)
		if slot_idx < 0:
			break
		if not _click_shop_slot_by_controls(main, slot_idx):
			break
		result["purchased"] = int(result["purchased"]) + 1
		await wait_process_frames(2)
		if bool(LiveUiProbe.snapshot(main).get("has_modal", false)):
			assert_true(await _resolve_visible_modal_by_controls(main),
				"shop action modal resolves through visible controls")
		result["moved"] = int(result["moved"]) \
			+ _move_bench_to_field_by_visible_drop(main)
		await wait_process_frames(1)

	if await _try_buy_upgrade_by_visible_controls(main):
		result["upgrades_bought"] = int(result["upgrades_bought"]) + 1
		await wait_process_frames(1)
	return result


func _first_affordable_shop_slot(main) -> int:
	var shop = main.build_phase.shop
	for i in shop._offered_ids.size():
		if str(shop._offered_ids[i]) == "":
			continue
		if main.game_state.gold >= shop.get_slot_cost(i):
			return i
	return -1


func _first_empty_bench_idx(main) -> int:
	for i in main.game_state.bench.size():
		if main.game_state.bench[i] == null:
			return i
	return -1


func _first_empty_field_idx(main) -> int:
	for i in main.game_state.field_slots:
		if main.game_state.board[i] == null:
			return i
	return -1


func _click_shop_slot_by_controls(main, slot_idx: int) -> bool:
	var slots: Array = main.build_phase.shop._shop_slots
	if slot_idx < 0 or slot_idx >= slots.size():
		return false
	return _emit_left_click(slots[slot_idx])


func _perform_strategist_swap_by_visible_controls(main) -> bool:
	if main.game_state.commander_type != Enums.CommanderType.STRATEGIST:
		return false
	var button: Button = main.build_phase.strategist_swap_button
	if button == null or not button.visible or button.disabled:
		return false
	var first_idx := _first_occupied_field_idx(main)
	var second_idx := _next_occupied_field_idx(main, first_idx)
	if first_idx < 0 or second_idx < 0:
		return false
	var first_before: CardInstance = main.game_state.board[first_idx]
	var second_before: CardInstance = main.game_state.board[second_idx]
	assert_false(bool(main.game_state.commander_state.get("hero_used", false)),
		"Strategist SWAP starts unused in this BUILD")
	assert_eq(button.text, "SWAP (H)")

	button.pressed.emit()
	await wait_process_frames(1)
	assert_true(main.build_phase._strategist_swap_active,
		"visible SWAP button starts Strategist swap mode")
	assert_eq(button.text, "PICK FIRST")
	assert_true(_click_field_card_by_controls(main, first_idx),
		"visible field card selects first Strategist swap target")
	await wait_process_frames(1)
	assert_eq(main.build_phase._strategist_swap_first_idx, first_idx)
	assert_eq(button.text, "PICK SECOND")
	assert_true(_click_field_card_by_controls(main, second_idx),
		"visible field card selects second Strategist swap target")
	await wait_process_frames(1)

	assert_false(main.build_phase._strategist_swap_active,
		"Strategist SWAP mode closes after the second target")
	assert_true(bool(main.game_state.commander_state.get("hero_used", false)),
		"Strategist SWAP marks the build action as used")
	assert_eq(main.game_state.board[first_idx], second_before,
		"first selected field card receives the second card")
	assert_eq(main.game_state.board[second_idx], first_before,
		"second selected field card receives the first card")
	assert_true(button.disabled)
	assert_eq(button.text, "SWAP USED")
	assert_string_contains(main.build_phase.get_identity_text(), "SWAP 사용됨")
	return true


func _first_occupied_field_idx(main) -> int:
	for i in main.game_state.field_slots:
		if main.game_state.board[i] != null:
			return i
	return -1


func _next_occupied_field_idx(main, after_idx: int) -> int:
	for i in main.game_state.field_slots:
		if i == after_idx:
			continue
		if main.game_state.board[i] != null:
			return i
	return -1


func _click_field_card_by_controls(main, field_idx: int) -> bool:
	if field_idx < 0 or field_idx >= main.build_phase._field_visuals.size():
		return false
	var visual = main.build_phase._field_visuals[field_idx]
	if visual == null or not visual.visible or visual.card_instance == null:
		return false
	visual.card_clicked.emit(visual)
	return true


func _move_bench_to_field_by_visible_drop(main) -> int:
	var moved := 0
	for bench_idx in main.game_state.bench.size():
		if main.game_state.bench[bench_idx] == null:
			continue
		var field_idx := _first_empty_field_idx(main)
		if field_idx < 0:
			break
		var bench_visual = main.build_phase._bench_visuals[bench_idx]
		var field_visual = main.build_phase._field_visuals[field_idx]
		field_visual._drop_data(Vector2.ZERO, {
			"source_zone": "bench",
			"source_idx": bench_idx,
			"card_visual": bench_visual,
		})
		moved += 1
	return moved


func _try_buy_upgrade_by_visible_controls(main) -> bool:
	if main.game_state.board_count() <= 0:
		return false
	var shop = main.build_phase.upgrade_shop
	for i in shop._offered_ids.size():
		if str(shop._offered_ids[i]) == "":
			continue
		if main.game_state.terazin < shop.get_upgrade_cost(i):
			continue
		if not _emit_left_click(shop._upgrade_slots[i]):
			return false
		await wait_process_frames(2)
		if LiveUiProbe.snapshot(main).get("active_modals", []) \
				== [LiveUiProbe.TARGET_SELECT]:
			return _click_first_target_by_controls(main)
		return true
	return false


func _resolve_visible_modal_by_controls(main) -> bool:
	var ui := LiveUiProbe.snapshot(main)
	var active_modals: Array = ui.get("active_modals", [])
	if active_modals.is_empty():
		return true
	match str(active_modals[0]):
		LiveUiProbe.UPGRADE_CHOICE:
			return LiveUiProbe.select_choice(main, LiveUiProbe.UPGRADE_CHOICE, 0)
		LiveUiProbe.BOSS_REWARD:
			var choice_ids: Array[String] = LiveUiProbe.choice_ids(
				main, LiveUiProbe.BOSS_REWARD)
			var choice_idx := _first_no_target_reward_index(choice_ids)
			if choice_idx < 0:
				choice_idx = 0
			return LiveUiProbe.select_choice(
				main, LiveUiProbe.BOSS_REWARD, choice_idx)
		LiveUiProbe.TARGET_SELECT:
			return _click_first_target_by_controls(main)
		LiveUiProbe.THEME_CHOICE:
			return _click_first_theme_choice_by_controls(main)
		LiveUiProbe.GAME_OVER:
			return true
	return false


func _click_first_target_by_controls(main) -> bool:
	var targets := LiveUiProbe.target_field_indices(main)
	if targets.is_empty():
		return false
	var field_idx: int = targets[0]
	var visuals: Array = main.build_phase._field_visuals
	if field_idx < 0 or field_idx >= visuals.size():
		return false
	return _emit_left_click(visuals[field_idx])


func _click_first_theme_choice_by_controls(main) -> bool:
	if not main.theme_choice_popup.visible:
		return false
	var container = main.theme_choice_popup.get_node("VBox/ChoiceContainer")
	for child in container.get_children():
		if child is Button:
			(child as Button).pressed.emit()
			return true
	return false


func _press_build_complete_by_controls(main) -> bool:
	if main.current_phase != main.Phase.BUILD:
		return false
	if main.build_phase.confirm_button.disabled:
		return false
	main.build_phase.confirm_button.pressed.emit()
	return true


func _press_space_by_controls(main) -> bool:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = true
	main._unhandled_input(event)
	return true


func _emit_left_click(control: Control) -> bool:
	if control == null or not control.visible:
		return false
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	control.emit_signal("gui_input", event)
	return true


func _wait_for_next_control_surface(main, max_frames: int) -> bool:
	for _i in max_frames:
		await wait_process_frames(1)
		var ui := LiveUiProbe.snapshot(main)
		if main._game_over:
			return true
		if bool(ui.get("has_modal", false)):
			return true
		if main.current_phase == main.Phase.BUILD \
				or main.current_phase == main.Phase.CHAIN:
			return true
	return false
