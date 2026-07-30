import importlib.util
import pathlib
import unittest


MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / "analyze_ai_trace.py"
SPEC = importlib.util.spec_from_file_location("analyze_ai_trace", MODULE_PATH)
analyze_ai_trace = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(analyze_ai_trace)


class AnalyzeAITraceTest(unittest.TestCase):
    def test_summarize_theme_commitment_metrics(self):
        events_per_run = [
            [
                {
                    "t": "round_end",
                    "round": 5,
                    "board": ["dr_cradle", "ne_earth_echo"],
                    "detected_path": "druid_garden",
                    "theme_metrics": {
                        "board_theme_ratio": 0.5,
                        "board_theme": 1,
                        "board_neutral": 1,
                        "board_off_theme": 0,
                    },
                    "path_progress": [
                        {"id": "druid_garden", "current_owned": 1, "current_total": 3},
                    ],
                    "active_path_progress": [
                        {"id": "druid_garden", "current_owned": 0, "current_total": 3},
                    ],
                },
                {"t": "battle", "round": 5, "won": False},
            ],
            [
                {
                    "t": "round_end",
                    "round": 8,
                    "board": ["dr_cradle", "dr_prune", "sp_workshop"],
                    "detected_path": "druid_garden",
                    "theme_metrics": {
                        "board_theme_ratio": 2.0 / 3.0,
                        "board_theme": 2,
                        "board_neutral": 0,
                        "board_off_theme": 1,
                    },
                    "path_progress": [
                        {"id": "druid_garden", "current_owned": 2, "current_total": 3},
                    ],
                    "active_path_progress": [
                        {"id": "druid_garden", "current_owned": 1, "current_total": 3},
                    ],
                },
                {"t": "battle", "round": 8, "won": True},
            ],
        ]

        summary = analyze_ai_trace.summarize_strategy(events_per_run)

        self.assertEqual(summary["n_runs"], 2)
        self.assertAlmostEqual(summary["win_rate"], 0.5)
        self.assertAlmostEqual(summary["avg_final_theme_ratio"], (0.5 + 2.0 / 3.0) / 2.0)
        self.assertAlmostEqual(summary["avg_final_theme_cards"], 1.5)
        self.assertAlmostEqual(summary["avg_final_neutral_cards"], 0.5)
        self.assertAlmostEqual(summary["avg_final_off_theme_cards"], 0.5)
        self.assertAlmostEqual(summary["path_detection_rate"], 1.0)
        self.assertAlmostEqual(summary["avg_first_path_round"], 6.5)
        self.assertAlmostEqual(
            summary["avg_final_phase_progress"]["druid_garden"],
            (1.0 / 3.0 + 2.0 / 3.0) / 2.0,
        )
        self.assertAlmostEqual(
            summary["avg_final_active_phase_progress"]["druid_garden"],
            (0.0 / 3.0 + 1.0 / 3.0) / 2.0,
        )

    def test_run_end_result_overrides_last_battle_result(self):
        events_per_run = [
            [
                {"t": "battle", "round": 15, "won": False},
                {"t": "run_end", "rounds_played": 15, "won": True, "final_hp": 20},
            ],
            [
                {"t": "battle", "round": 15, "won": True},
                {"t": "run_end", "rounds_played": 15, "won": False, "final_hp": -4},
            ],
        ]

        summary = analyze_ai_trace.summarize_strategy(events_per_run)

        self.assertEqual(summary["n_runs"], 2)
        self.assertEqual(summary["wins"], 1)
        self.assertAlmostEqual(summary["win_rate"], 0.5)
        self.assertAlmostEqual(summary["avg_final_hp"], 8.0)
        self.assertAlmostEqual(summary["avg_rounds"], 15.0)

    def test_summarize_level_timing_from_levelup_and_round_start(self):
        events_per_run = [
            [
                {"t": "levelup", "round": 7, "from_level": 3, "to_level": 4},
                {"t": "levelup", "round": 9, "from_level": 4, "to_level": 5},
                {"t": "run_end", "rounds_played": 15, "won": True},
            ],
            [
                {"t": "round_start", "round": 8, "shop_level": 4},
                {"t": "round_start", "round": 11, "shop_level": 5},
                {"t": "run_end", "rounds_played": 12, "won": False},
            ],
        ]

        summary = analyze_ai_trace.summarize_strategy(events_per_run)

        self.assertAlmostEqual(summary["avg_levelups"], 1.0)
        self.assertAlmostEqual(summary["level4_reach_rate"], 1.0)
        self.assertAlmostEqual(summary["avg_first_level4_round"], 7.5)
        self.assertAlmostEqual(summary["level5_reach_rate"], 1.0)
        self.assertAlmostEqual(summary["avg_first_level5_round"], 10.0)

    def test_summarize_enemy_debuff_metrics(self):
        events_per_run = [
            [
                {
                    "t": "battle",
                    "round": 7,
                    "won": False,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.225},
                },
                {
                    "t": "battle",
                    "round": 8,
                    "won": True,
                    "enemy_debuffs": {"atk_pct": 0.3, "as_pct": 0.3},
                },
            ],
            [
                {"t": "battle", "round": 7, "won": False},
            ],
        ]

        summary = analyze_ai_trace.summarize_strategy(events_per_run)

        self.assertAlmostEqual(summary["enemy_debuff_run_rate"], 0.5)
        self.assertAlmostEqual(summary["avg_max_enemy_atk_debuff"], 0.15)
        self.assertAlmostEqual(summary["avg_max_enemy_as_debuff"], 0.15)

    def test_druid_loss_buckets_classify_access_and_conversion(self):
        events_per_run = [
            [
                {"t": "round_start", "round": 8, "shop_level": 3},
                {
                    "t": "round_end",
                    "round": 8,
                    "detected_path": "druid_garden",
                    "theme_metrics": {"board_theme_ratio": 0.5},
                    "path_progress": [
                        {
                            "id": "druid_garden",
                            "current_phase": "payoff",
                            "current_owned": 0,
                            "current_total": 2,
                        },
                    ],
                    "active_path_progress": [
                        {
                            "id": "druid_garden",
                            "current_phase": "payoff",
                            "current_owned": 0,
                            "current_total": 2,
                        },
                    ],
                },
                {"t": "battle", "round": 8, "won": False},
                {"t": "run_end", "rounds_played": 8, "final_hp": -2, "won": False},
            ],
            [
                {"t": "round_start", "round": 8, "shop_level": 4},
                {
                    "t": "buy",
                    "round": 8,
                    "card_id": "dr_spore_cloud",
                    "offers": [
                        {"id": "dr_spore_cloud", "affordable": True, "cost": 4},
                    ],
                },
                {
                    "t": "round_end",
                    "round": 8,
                    "active_board": ["dr_spore_cloud"],
                    "detected_path": "druid_garden",
                    "theme_metrics": {"board_theme_ratio": 1.0},
                    "path_progress": [
                        {
                            "id": "druid_garden",
                            "current_phase": "payoff",
                            "current_owned": 1,
                            "current_total": 2,
                        },
                    ],
                    "active_path_progress": [
                        {
                            "id": "druid_garden",
                            "current_phase": "payoff",
                            "current_owned": 1,
                            "current_total": 2,
                        },
                    ],
                },
                {
                    "t": "battle",
                    "round": 8,
                    "won": False,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.15},
                },
                {"t": "run_end", "rounds_played": 8, "final_hp": -1, "won": False},
            ],
            [
                {"t": "battle", "round": 15, "won": True},
                {"t": "run_end", "rounds_played": 15, "final_hp": 30, "won": True},
            ],
        ]

        summary = analyze_ai_trace.summarize_druid_loss_buckets(events_per_run)

        self.assertEqual(summary["n_runs"], 3)
        self.assertEqual(summary["wins"], 1)
        self.assertEqual(summary["losses"], 2)
        self.assertEqual(summary["bucket_counts"]["tier_access_lag"], 2)
        self.assertEqual(summary["bucket_counts"]["payoff_acquisition_lag"], 1)
        self.assertEqual(summary["bucket_counts"]["combat_conversion_failure"], 1)
        self.assertEqual(summary["bucket_counts"]["low_druid_board_ratio"], 1)
        self.assertEqual(summary["loss_payoff_offered_runs"], 1)
        self.assertEqual(summary["loss_payoff_affordable_runs"], 1)
        self.assertEqual(summary["loss_payoff_bought_runs"], 1)

    def test_druid_loss_buckets_use_levelup_event_for_level4_timing(self):
        events_per_run = [
            [
                {"t": "round_start", "round": 8, "shop_level": 3},
                {"t": "levelup", "round": 8, "from_level": 3, "to_level": 4},
                {
                    "t": "round_end",
                    "round": 8,
                    "detected_path": "druid_garden",
                    "theme_metrics": {"board_theme_ratio": 1.0},
                    "path_progress": [
                        {
                            "id": "druid_garden",
                            "current_phase": "payoff",
                            "current_owned": 0,
                            "current_total": 2,
                        },
                    ],
                    "active_path_progress": [
                        {
                            "id": "druid_garden",
                            "current_phase": "payoff",
                            "current_owned": 0,
                            "current_total": 2,
                        },
                    ],
                },
                {"t": "battle", "round": 9, "won": False},
                {"t": "run_end", "rounds_played": 9, "final_hp": -1, "won": False},
            ],
        ]

        summary = analyze_ai_trace.summarize_druid_loss_buckets(events_per_run)

        self.assertEqual(summary["first_level4_rounds"][8], 1)
        self.assertNotIn("tier_access_lag", summary["bucket_counts"])

    def test_druid_loss_buckets_count_affordable_payoff_skips(self):
        events_per_run = [
            [
                {"t": "round_start", "round": 9, "shop_level": 4},
                {
                    "t": "buy",
                    "round": 9,
                    "card_id": "ne_earth_echo",
                    "offers": [
                        {"id": "dr_spore_cloud", "affordable": True, "cost": 4},
                        {"id": "ne_earth_echo", "affordable": True, "cost": 2},
                    ],
                },
                {
                    "t": "buy_skip",
                    "round": 9,
                    "reason": "path_lag_hold",
                    "offers": [
                        {"id": "dr_wrath", "affordable": True, "cost": 5},
                    ],
                },
                {
                    "t": "round_end",
                    "round": 9,
                    "detected_path": "druid_garden",
                    "theme_metrics": {"board_theme_ratio": 0.75},
                    "path_progress": [
                        {
                            "id": "druid_garden",
                            "current_phase": "payoff",
                            "current_owned": 0,
                            "current_total": 2,
                        },
                    ],
                    "active_path_progress": [
                        {
                            "id": "druid_garden",
                            "current_phase": "payoff",
                            "current_owned": 0,
                            "current_total": 2,
                        },
                    ],
                },
                {"t": "battle", "round": 9, "won": False},
                {"t": "run_end", "rounds_played": 9, "final_hp": -1, "won": False},
            ],
        ]

        summary = analyze_ai_trace.summarize_druid_loss_buckets(events_per_run)

        self.assertEqual(summary["loss_payoff_offered_runs"], 1)
        self.assertEqual(summary["loss_payoff_affordable_runs"], 1)
        self.assertEqual(summary["loss_affordable_payoff_skip_runs"], 1)
        self.assertEqual(summary["loss_affordable_payoff_skip_events"], 2)

    def test_druid_battle_conversion_summarizes_focus_active_frames(self):
        events_per_run = [
            [
                {
                    "t": "round_end",
                    "round": 9,
                    "active_board": ["dr_origin", "dr_lifebeat", "dr_spore_cloud"],
                    "detected_path": "druid_garden",
                    "states": {
                        "dr_origin": {"trees": 4},
                        "dr_lifebeat": {"trees": 1},
                        "dr_spore_cloud": {},
                    },
                },
                {
                    "t": "battle",
                    "round": 9,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 12,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.15},
                },
                {"t": "run_end", "rounds_played": 9, "final_hp": -1, "won": False},
            ],
            [
                {
                    "t": "round_end",
                    "round": 12,
                    "active_board": ["dr_wrath", "dr_world", "ne_earth_echo"],
                    "detected_path": "druid_world_tree",
                    "states": {
                        "dr_wrath": {},
                        "dr_world": {"trees": 3},
                        "ne_earth_echo": {},
                    },
                },
                {
                    "t": "battle",
                    "round": 12,
                    "won": True,
                    "ally_survived": 14,
                    "enemy_survived": 0,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.0},
                },
                {"t": "run_end", "rounds_played": 15, "final_hp": 20, "won": True},
            ],
        ]

        summary = analyze_ai_trace.summarize_druid_battle_conversion(events_per_run)

        self.assertEqual(summary["n_runs"], 2)
        self.assertEqual(summary["payoff_active_runs"], 2)
        self.assertEqual(summary["payoff_active_loss_runs"], 1)
        self.assertEqual(summary["payoff_active_battles"], 2)
        self.assertEqual(summary["payoff_active_wins"], 1)
        self.assertEqual(summary["payoff_active_losses"], 1)
        self.assertAlmostEqual(summary["payoff_active_battle_win_rate"], 0.5)
        self.assertEqual(summary["active_battle_debuffs"], 1)
        self.assertEqual(summary["active_loss_after_debuff"], 1)
        self.assertEqual(summary["active_loss_without_debuff"], 0)
        self.assertEqual(summary["active_loss_enemy_survived"], 1)
        self.assertAlmostEqual(summary["avg_active_druid_cards"], 2.5)
        self.assertAlmostEqual(summary["avg_active_neutral_cards"], 0.5)
        self.assertAlmostEqual(summary["avg_active_tree_counters"], 4.0)
        self.assertEqual(summary["payoff_card_counts"]["dr_spore_cloud"], 1)
        self.assertEqual(summary["payoff_card_counts"]["dr_wrath"], 1)
        self.assertEqual(summary["payoff_card_counts"]["dr_world"], 1)
        self.assertEqual(summary["per_payoff"]["dr_spore_cloud"]["losses"], 1)
        self.assertEqual(summary["per_payoff"]["dr_world"]["wins"], 1)
        self.assertEqual(summary["examples"][0]["round"], 9)

    def test_druid_active_ledger_classifies_r9_r11_loss_margins(self):
        events_per_run = [
            [
                {
                    "t": "round_end",
                    "round": 8,
                    "active_board": ["dr_wrath", "dr_cradle", "dr_lifebeat"],
                    "detected_path": "druid_garden",
                    "states": {
                        "dr_wrath": {"star": 1, "trees": 0},
                        "dr_cradle": {"star": 1, "trees": 4},
                        "dr_lifebeat": {"star": 1, "trees": 2},
                    },
                },
                {
                    "t": "battle",
                    "round": 8,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 12,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.0},
                },
            ],
            [
                {
                    "t": "round_end",
                    "round": 9,
                    "active_board": ["dr_wrath", "dr_cradle", "dr_lifebeat"],
                    "detected_path": "druid_garden",
                    "states": {
                        "dr_wrath": {"star": 1, "trees": 0},
                        "dr_cradle": {"star": 2, "trees": 10},
                        "dr_lifebeat": {"star": 1, "trees": 4},
                    },
                },
                {
                    "t": "battle",
                    "round": 9,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 14,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.0},
                },
                {"t": "run_end", "rounds_played": 9, "final_hp": -3, "won": False},
            ],
            [
                {
                    "t": "round_end",
                    "round": 10,
                    "active_board": [
                        "dr_spore_cloud",
                        "dr_cradle",
                        "dr_origin",
                        "dr_lifebeat",
                    ],
                    "detected_path": "druid_world_tree",
                    "states": {
                        "dr_spore_cloud": {"star": 1, "trees": 0},
                        "dr_cradle": {"star": 2, "trees": 18},
                        "dr_origin": {"star": 1, "trees": 5},
                        "dr_lifebeat": {"star": 1, "trees": 7},
                    },
                },
                {
                    "t": "battle",
                    "round": 10,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 13,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.15},
                },
                {"t": "run_end", "rounds_played": 10, "final_hp": -5, "won": False},
            ],
            [
                {
                    "t": "round_end",
                    "round": 11,
                    "active_board": [
                        "dr_spore_cloud",
                        "dr_wrath",
                        "dr_cradle",
                        "dr_lifebeat",
                    ],
                    "detected_path": "druid_garden",
                    "states": {
                        "dr_spore_cloud": {"star": 2, "trees": 5},
                        "dr_wrath": {"star": 1, "trees": 3},
                        "dr_cradle": {"star": 2, "trees": 20},
                        "dr_lifebeat": {"star": 1, "trees": 8},
                    },
                },
                {
                    "t": "battle",
                    "round": 11,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 4,
                    "enemy_debuffs": {"atk_pct": 0.1, "as_pct": 0.25},
                },
                {"t": "run_end", "rounds_played": 11, "final_hp": -1, "won": False},
            ],
            [
                {
                    "t": "round_end",
                    "round": 11,
                    "active_board": ["dr_world", "dr_wrath", "dr_cradle"],
                    "detected_path": "druid_world_tree",
                    "states": {
                        "dr_world": {"star": 1, "trees": 5},
                        "dr_wrath": {"star": 1, "trees": 2},
                        "dr_cradle": {"star": 3, "trees": 24},
                    },
                },
                {
                    "t": "battle",
                    "round": 11,
                    "won": True,
                    "ally_survived": 9,
                    "enemy_survived": 0,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.0},
                },
                {"t": "run_end", "rounds_played": 15, "final_hp": 18, "won": True},
            ],
        ]

        summary = analyze_ai_trace.summarize_druid_active_ledger(events_per_run)

        self.assertEqual(summary["frames"], 4)
        self.assertEqual(summary["wins"], 1)
        self.assertEqual(summary["losses"], 3)
        self.assertAlmostEqual(summary["detail_coverage"], 1.0)
        self.assertAlmostEqual(summary["star_coverage"], 1.0)
        self.assertAlmostEqual(summary["tree_coverage"], 1.0)
        self.assertEqual(summary["primary_bottlenecks"]["debuff_missing"], 1)
        self.assertEqual(summary["primary_bottlenecks"]["debuff_too_small"], 1)
        self.assertEqual(summary["primary_bottlenecks"]["near_miss_survivability"], 1)
        self.assertEqual(summary["by_focus_combo"]["dr_wrath"]["losses"], 1)
        self.assertEqual(
            summary["by_focus_card"]["dr_spore_cloud"]["primary_bottlenecks"][
                "debuff_too_small"
            ],
            1,
        )
        self.assertTrue(summary["next_signal"].startswith("Debuff-missing"))

    def test_druid_run_phase_binds_timing_to_survival_window(self):
        events_per_run = [
            [
                {"t": "round_start", "round": 8, "hp": 14, "shop_level": 3},
                {
                    "t": "round_end",
                    "round": 8,
                    "board": ["dr_cradle", "dr_lifebeat"],
                    "active_board": ["dr_cradle", "dr_lifebeat"],
                    "detected_path": "druid_garden",
                },
                {
                    "t": "battle",
                    "round": 8,
                    "won": False,
                    "hp_after": -2,
                    "ally_survived": 0,
                    "enemy_survived": 18,
                },
                {"t": "run_end", "rounds_played": 8, "final_hp": -2, "won": False},
            ],
            [
                {"t": "round_start", "round": 9, "hp": 18, "shop_level": 4},
                {
                    "t": "buy_skip",
                    "round": 9,
                    "reason": "path_lag_hold",
                    "offers": [
                        {"id": "dr_spore_cloud", "affordable": True, "cost": 4},
                    ],
                },
                {"t": "round_start", "round": 10, "hp": 9, "shop_level": 4},
                {
                    "t": "buy",
                    "round": 10,
                    "card_id": "dr_spore_cloud",
                    "offers": [
                        {"id": "dr_spore_cloud", "affordable": True, "cost": 4},
                    ],
                },
                {
                    "t": "buy",
                    "round": 10,
                    "card_id": "dr_wrath",
                    "offers": [
                        {"id": "dr_wrath", "affordable": True, "cost": 5},
                    ],
                },
                {
                    "t": "round_end",
                    "round": 10,
                    "board": ["dr_spore_cloud", "dr_wrath", "dr_cradle"],
                    "active_board": ["dr_spore_cloud", "dr_wrath", "dr_cradle"],
                    "detected_path": "druid_garden",
                    "states": {
                        "dr_cradle": {"trees": 8},
                        "dr_spore_cloud": {"trees": 1},
                        "dr_wrath": {"trees": 1},
                    },
                },
                {
                    "t": "battle",
                    "round": 10,
                    "won": False,
                    "hp_after": -1,
                    "ally_survived": 0,
                    "enemy_survived": 9,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.2},
                },
                {"t": "run_end", "rounds_played": 10, "final_hp": -1, "won": False},
            ],
            [
                {"t": "round_start", "round": 8, "hp": 24, "shop_level": 4},
                {
                    "t": "buy",
                    "round": 8,
                    "card_id": "dr_spore_cloud",
                    "offers": [
                        {"id": "dr_spore_cloud", "affordable": True, "cost": 4},
                    ],
                },
                {
                    "t": "round_end",
                    "round": 8,
                    "board": ["dr_spore_cloud", "dr_cradle"],
                    "active_board": ["dr_spore_cloud", "dr_cradle"],
                    "detected_path": "druid_world_tree",
                    "states": {
                        "dr_cradle": {"trees": 10},
                        "dr_spore_cloud": {"trees": 2},
                    },
                },
                {
                    "t": "battle",
                    "round": 8,
                    "won": True,
                    "hp_after": 24,
                    "ally_survived": 7,
                    "enemy_survived": 0,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.2},
                },
                {"t": "round_start", "round": 9, "hp": 24, "shop_level": 4},
                {
                    "t": "buy",
                    "round": 9,
                    "card_id": "dr_wrath",
                    "offers": [
                        {"id": "dr_wrath", "affordable": True, "cost": 5},
                    ],
                },
                {
                    "t": "round_end",
                    "round": 9,
                    "board": ["dr_spore_cloud", "dr_wrath", "dr_cradle"],
                    "active_board": ["dr_spore_cloud", "dr_wrath", "dr_cradle"],
                    "detected_path": "druid_world_tree",
                    "states": {
                        "dr_cradle": {"trees": 12},
                        "dr_spore_cloud": {"trees": 3},
                        "dr_wrath": {"trees": 1},
                    },
                },
                {
                    "t": "battle",
                    "round": 9,
                    "won": True,
                    "hp_after": 24,
                    "ally_survived": 10,
                    "enemy_survived": 0,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.2},
                },
                {"t": "run_end", "rounds_played": 15, "final_hp": 20, "won": True},
            ],
        ]

        summary = analyze_ai_trace.summarize_druid_run_phase(events_per_run)

        self.assertEqual(summary["n_runs"], 3)
        self.assertEqual(summary["wins"], 1)
        self.assertEqual(summary["conversion_buckets"]["no_payoff_seen"], 1)
        self.assertEqual(summary["conversion_buckets"]["active_too_late"], 1)
        self.assertEqual(summary["conversion_buckets"]["converted"], 1)
        self.assertAlmostEqual(summary["timing"]["all"]["payoff_buy_rate"], 2.0 / 3.0)
        self.assertAlmostEqual(summary["timing"]["all"]["focus_active_rate"], 2.0 / 3.0)
        self.assertAlmostEqual(summary["timing"]["all"]["both_payoffs_active_rate"], 2.0 / 3.0)
        self.assertAlmostEqual(summary["timing"]["losses"]["avg_hp_at_first_focus_active"], 9.0)
        self.assertEqual(summary["timing"]["losses"]["active_dead_same_round"], 1)
        self.assertEqual(summary["rounds"][9]["path_lag_holds"], 1)
        self.assertAlmostEqual(summary["rounds"][10]["battle_win_rate"], 0.0)
        self.assertAlmostEqual(summary["rounds"][10]["both_payoffs_active_rate"], 1.0)
        self.assertEqual(summary["false_green_examples"][0]["bucket"], "active_too_late")
        self.assertIn("lethal window", summary["next_signal"])

    def test_druid_run_phase_comparison_reports_bucket_deltas(self):
        baseline_events = [
            [
                {"t": "round_start", "round": 8, "hp": 12, "shop_level": 3},
                {
                    "t": "round_end",
                    "round": 8,
                    "board": ["dr_cradle"],
                    "active_board": ["dr_cradle"],
                    "detected_path": "druid_garden",
                },
                {"t": "battle", "round": 8, "won": False, "hp_after": -2},
                {"t": "run_end", "rounds_played": 8, "final_hp": -2, "won": False},
            ],
        ]
        candidate_events = [
            [
                {"t": "round_start", "round": 10, "hp": 8, "shop_level": 4},
                {
                    "t": "buy",
                    "round": 10,
                    "card_id": "dr_spore_cloud",
                    "offers": [
                        {"id": "dr_spore_cloud", "affordable": True, "cost": 4},
                    ],
                },
                {
                    "t": "round_end",
                    "round": 10,
                    "board": ["dr_spore_cloud", "dr_cradle"],
                    "active_board": ["dr_spore_cloud", "dr_cradle"],
                    "detected_path": "druid_garden",
                },
                {
                    "t": "battle",
                    "round": 10,
                    "won": False,
                    "hp_after": -1,
                    "ally_survived": 0,
                    "enemy_survived": 11,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.2},
                },
                {"t": "run_end", "rounds_played": 10, "final_hp": -1, "won": False},
            ],
        ]

        comparison = analyze_ai_trace.summarize_druid_run_phase_comparison(
            candidate_events,
            baseline_events,
        )

        self.assertEqual(comparison["bucket_deltas"]["no_payoff_seen"], -1)
        self.assertEqual(comparison["bucket_deltas"]["active_too_late"], 1)
        self.assertAlmostEqual(comparison["round_deltas"][10]["focus_active_rate_delta"], 1.0)
        self.assertIn("active_too_late", comparison["next_signal"])

    def test_druid_activation_audit_attributes_payoff_gap_frames(self):
        events_per_run = [
            [
                {"t": "round_start", "round": 9, "hp": 14, "shop_level": 4},
                {"t": "buy", "round": 9, "card_id": "dr_spore_cloud"},
                {
                    "t": "promote_skip",
                    "round": 9,
                    "reason": "path_focus_value_gap",
                    "current_phase": "payoff",
                    "bench_card_id": "dr_spore_cloud",
                    "board_card_id": "dr_cradle",
                    "board_idx": 2,
                    "bench_value": 42.0,
                    "board_value": 55.0,
                    "allowed_gap": 6.0,
                },
                {
                    "t": "round_end",
                    "round": 9,
                    "board": ["dr_cradle", "dr_lifebeat"],
                    "bench": ["dr_spore_cloud"],
                    "active_board": ["dr_cradle", "dr_lifebeat"],
                    "detected_path": "druid_garden",
                },
                {
                    "t": "battle",
                    "round": 9,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 16,
                },
                {"t": "run_end", "rounds_played": 9, "final_hp": -3, "won": False},
            ],
            [
                {"t": "round_start", "round": 10, "hp": 16, "shop_level": 4},
                {"t": "buy", "round": 10, "card_id": "dr_wrath"},
                {
                    "t": "round_end",
                    "round": 10,
                    "board": ["dr_wrath", "dr_cradle", "dr_lifebeat"],
                    "bench": [],
                    "active_board": ["dr_cradle", "dr_lifebeat"],
                    "detected_path": "druid_world_tree",
                },
                {
                    "t": "battle",
                    "round": 10,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 12,
                },
                {"t": "run_end", "rounds_played": 10, "final_hp": -1, "won": False},
            ],
            [
                {"t": "round_start", "round": 9, "hp": 22, "shop_level": 4},
                {"t": "buy", "round": 9, "card_id": "dr_spore_cloud"},
                {
                    "t": "round_end",
                    "round": 9,
                    "board": ["dr_cradle"],
                    "bench": ["dr_spore_cloud"],
                    "active_board": ["dr_cradle"],
                    "detected_path": "druid_garden",
                },
                {
                    "t": "battle",
                    "round": 9,
                    "won": True,
                    "ally_survived": 4,
                    "enemy_survived": 0,
                },
                {"t": "run_end", "rounds_played": 15, "final_hp": 12, "won": True},
            ],
        ]

        summary = analyze_ai_trace.summarize_druid_activation_audit(events_per_run)

        self.assertEqual(summary["n_runs"], 3)
        self.assertEqual(summary["payoff_buy_runs"], 3)
        self.assertEqual(summary["bought_payoff_copies"], 3)
        self.assertEqual(summary["active_after_buy_copies"], 0)
        self.assertEqual(summary["gap_frames"], 3)
        self.assertEqual(summary["bench_gap_frames"], 2)
        self.assertEqual(summary["board_gap_frames"], 1)
        self.assertEqual(summary["no_attempt_bench_frames"], 1)
        self.assertEqual(summary["promotion_skips"], 1)
        self.assertEqual(
            summary["promotion_skip_reasons"]["path_focus_value_gap"],
            1,
        )
        self.assertEqual(summary["top_blocking_cards"][0], ("dr_cradle", 1))
        self.assertEqual(summary["gap_by_card"]["dr_spore_cloud"], 2)
        self.assertEqual(summary["gap_by_card"]["dr_wrath"], 1)
        self.assertIn("druid_garden", summary["by_path"])
        self.assertEqual(summary["by_path"]["druid_garden"]["bench_gap_frames"], 2)
        self.assertEqual(summary["examples"][0]["status"], "bench_not_promoted")
        self.assertEqual(summary["examples"][0]["first_skip_reason"], "path_focus_value_gap")
        self.assertEqual(summary["examples"][0]["blocked_by_card"], "dr_cradle")
        self.assertEqual(
            summary["examples"][0]["trace_note"],
            "promotion_decision_observed",
        )
        self.assertIn("aggregate", summary["trace_limitations"][0])

    def test_druid_activation_comparison_reports_gap_deltas(self):
        baseline_events = [
            [
                {"t": "round_start", "round": 9, "hp": 14, "shop_level": 4},
                {"t": "buy", "round": 9, "card_id": "dr_spore_cloud"},
                {
                    "t": "round_end",
                    "round": 9,
                    "board": ["dr_cradle"],
                    "bench": ["dr_spore_cloud"],
                    "active_board": ["dr_cradle"],
                    "detected_path": "druid_garden",
                },
                {"t": "battle", "round": 9, "won": False},
                {"t": "run_end", "rounds_played": 9, "final_hp": -2, "won": False},
            ],
        ]
        candidate_events = [
            [
                {"t": "round_start", "round": 9, "hp": 20, "shop_level": 4},
                {"t": "buy", "round": 9, "card_id": "dr_spore_cloud"},
                {
                    "t": "round_end",
                    "round": 9,
                    "board": ["dr_spore_cloud", "dr_cradle"],
                    "bench": [],
                    "active_board": ["dr_spore_cloud", "dr_cradle"],
                    "detected_path": "druid_garden",
                },
                {"t": "battle", "round": 9, "won": True},
                {"t": "run_end", "rounds_played": 15, "final_hp": 20, "won": True},
            ],
        ]

        comparison = analyze_ai_trace.summarize_druid_activation_comparison(
            candidate_events,
            baseline_events,
        )

        self.assertEqual(comparison["deltas"]["gap_frames"], -1)
        self.assertEqual(comparison["deltas"]["bench_gap_frames"], -1)
        self.assertEqual(comparison["status_deltas"]["bench_not_promoted"], -1)
        self.assertIn("reduces activation gaps", comparison["next_signal"])

    def test_druid_path_lag_audit_attributes_no_focus_holds(self):
        def held_loss(best_card_id, best_score, path_id="druid_garden"):
            return [
                {"t": "round_start", "round": 9, "hp": 12, "gold": 8, "shop_level": 4},
                {
                    "t": "buy_skip",
                    "round": 9,
                    "reason": "path_lag_hold",
                    "best_card_id": best_card_id,
                    "best_score": best_score,
                    "current_phase": "payoff",
                    "focus": ["dr_spore_cloud", "dr_wrath"],
                    "offers": [
                        {"id": best_card_id, "affordable": True, "cost": 4},
                        {"id": "ne_scrapyard", "affordable": True, "cost": 3},
                    ],
                },
                {"t": "reroll", "round": 9, "n": 1, "budget": 9, "gold_after": 7},
                {
                    "t": "round_end",
                    "round": 9,
                    "board": ["dr_cradle", "dr_origin"],
                    "active_board": ["dr_cradle", "dr_origin"],
                    "detected_path": path_id,
                },
                {
                    "t": "battle",
                    "round": 9,
                    "won": False,
                    "hp_after": -1,
                    "ally_survived": 0,
                    "enemy_survived": 14,
                },
                {"t": "run_end", "rounds_played": 9, "final_hp": -1, "won": False},
            ]

        events_per_run = [
            held_loss("dr_grace", 51.2),
            held_loss("ne_ancient_catalyst", 18.4),
            held_loss("dr_lifebeat", 30.8, "druid_world_tree"),
        ]

        summary = analyze_ai_trace.summarize_druid_path_lag_audit(events_per_run)

        self.assertEqual(summary["holds"], 3)
        self.assertEqual(summary["hold_loss_runs"], 3)
        self.assertEqual(summary["focus_offered_holds"], 0)
        self.assertEqual(summary["affordable_focus_holds"], 0)
        self.assertAlmostEqual(summary["no_focus_offer_rate"], 1.0)
        self.assertEqual(summary["actionable_no_focus_loss_runs"], 3)
        self.assertEqual(
            summary["category_counts"]["no_focus_offer_druid_body_held"],
            2,
        )
        self.assertEqual(
            summary["category_counts"]["no_focus_offer_high_value_neutral_held"],
            1,
        )
        self.assertEqual(
            summary["approval_gate"],
            "GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD",
        )
        self.assertIn("Protected AI probe recommended", summary["next_signal"])
        self.assertEqual(summary["by_path"]["druid_garden"]["holds"], 2)
        self.assertEqual(summary["examples"][0]["category"], "no_focus_offer_druid_body_held")

    def test_druid_path_lag_comparison_reports_decision_deltas(self):
        baseline_events = [
            [
                {"t": "round_start", "round": 9, "hp": 18, "gold": 8, "shop_level": 4},
                {
                    "t": "buy_skip",
                    "round": 9,
                    "reason": "path_lag_hold",
                    "best_card_id": "dr_grace",
                    "best_score": 35.0,
                    "current_phase": "payoff",
                    "focus": ["dr_spore_cloud", "dr_wrath"],
                    "offers": [
                        {"id": "dr_grace", "affordable": True, "cost": 4},
                    ],
                },
                {
                    "t": "round_end",
                    "round": 9,
                    "board": ["dr_cradle"],
                    "active_board": ["dr_cradle"],
                    "detected_path": "druid_garden",
                },
                {"t": "battle", "round": 9, "won": False, "hp_after": -1},
                {"t": "run_end", "rounds_played": 9, "final_hp": -1, "won": False},
            ],
        ]
        candidate_events = baseline_events + [
            [
                {"t": "round_start", "round": 10, "hp": 10, "gold": 6, "shop_level": 4},
                {
                    "t": "buy_skip",
                    "round": 10,
                    "reason": "path_lag_hold",
                    "best_card_id": "ne_ancient_catalyst",
                    "best_score": 22.0,
                    "current_phase": "payoff",
                    "focus": ["dr_spore_cloud", "dr_wrath"],
                    "offers": [
                        {"id": "ne_ancient_catalyst", "affordable": True, "cost": 4},
                    ],
                },
                {
                    "t": "round_end",
                    "round": 10,
                    "board": ["dr_cradle"],
                    "active_board": ["dr_cradle"],
                    "detected_path": "druid_garden",
                },
                {"t": "battle", "round": 10, "won": False, "hp_after": -2},
                {"t": "run_end", "rounds_played": 10, "final_hp": -2, "won": False},
            ],
            [
                {"t": "round_start", "round": 10, "hp": 9, "gold": 6, "shop_level": 4},
                {
                    "t": "buy_skip",
                    "round": 10,
                    "reason": "path_lag_hold",
                    "best_card_id": "dr_lifebeat",
                    "best_score": 28.0,
                    "current_phase": "payoff",
                    "focus": ["dr_spore_cloud", "dr_wrath"],
                    "offers": [
                        {"id": "dr_lifebeat", "affordable": True, "cost": 2},
                    ],
                },
                {
                    "t": "round_end",
                    "round": 10,
                    "board": ["dr_cradle"],
                    "active_board": ["dr_cradle"],
                    "detected_path": "druid_garden",
                },
                {"t": "battle", "round": 10, "won": False, "hp_after": -3},
                {"t": "run_end", "rounds_played": 10, "final_hp": -3, "won": False},
            ],
        ]

        comparison = analyze_ai_trace.summarize_druid_path_lag_comparison(
            candidate_events,
            baseline_events,
        )

        self.assertEqual(comparison["deltas"]["holds"], 2)
        self.assertEqual(comparison["deltas"]["actionable_no_focus_loss_runs"], 2)
        self.assertEqual(
            comparison["candidate"]["approval_gate"],
            "GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD",
        )
        self.assertIn("protected AI policy probe", comparison["next_signal"])

    def test_druid_probe_comparison_anchors_candidate_to_baseline(self):
        baseline_events = [
            [
                {
                    "t": "round_end",
                    "round": 9,
                    "board": ["dr_spore_cloud"],
                    "active_board": ["dr_spore_cloud", "dr_cradle", "dr_lifebeat"],
                    "detected_path": "druid_garden",
                    "states": {
                        "dr_spore_cloud": {"star": 1, "trees": 0},
                        "dr_cradle": {"star": 1, "trees": 5},
                        "dr_lifebeat": {"star": 1, "trees": 4},
                    },
                },
                {
                    "t": "battle",
                    "round": 9,
                    "won": True,
                    "ally_survived": 5,
                    "enemy_survived": 0,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.15},
                },
                {"t": "run_end", "rounds_played": 15, "final_hp": 10, "won": True},
            ],
            [
                {
                    "t": "round_end",
                    "round": 10,
                    "board": ["dr_spore_cloud"],
                    "active_board": ["dr_spore_cloud", "dr_cradle", "dr_lifebeat"],
                    "detected_path": "druid_garden",
                    "states": {
                        "dr_spore_cloud": {"star": 1, "trees": 0},
                        "dr_cradle": {"star": 1, "trees": 8},
                        "dr_lifebeat": {"star": 1, "trees": 5},
                    },
                },
                {
                    "t": "battle",
                    "round": 10,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 13,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.15},
                },
                {"t": "run_end", "rounds_played": 10, "final_hp": -5, "won": False},
            ],
        ]
        candidate_events = [
            [
                {
                    "t": "round_end",
                    "round": 9,
                    "board": ["dr_spore_cloud"],
                    "active_board": ["dr_spore_cloud", "dr_cradle", "dr_lifebeat"],
                    "detected_path": "druid_garden",
                    "states": {
                        "dr_spore_cloud": {"star": 1, "trees": 0},
                        "dr_cradle": {"star": 1, "trees": 5},
                        "dr_lifebeat": {"star": 1, "trees": 4},
                    },
                },
                {
                    "t": "battle",
                    "round": 9,
                    "won": True,
                    "ally_survived": 5,
                    "enemy_survived": 0,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.20},
                },
                {"t": "run_end", "rounds_played": 15, "final_hp": 14, "won": True},
            ],
            [
                {
                    "t": "round_end",
                    "round": 10,
                    "board": ["dr_spore_cloud"],
                    "active_board": ["dr_spore_cloud", "dr_cradle", "dr_lifebeat"],
                    "detected_path": "druid_garden",
                    "states": {
                        "dr_spore_cloud": {"star": 1, "trees": 0},
                        "dr_cradle": {"star": 1, "trees": 8},
                        "dr_lifebeat": {"star": 1, "trees": 5},
                    },
                },
                {
                    "t": "battle",
                    "round": 10,
                    "won": True,
                    "ally_survived": 2,
                    "enemy_survived": 0,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.20},
                },
                {"t": "run_end", "rounds_played": 15, "final_hp": 8, "won": True},
            ],
        ]

        summary = analyze_ai_trace.summarize_druid_probe_comparison(
            candidate_events,
            baseline_events,
        )

        self.assertEqual(summary["baseline"]["wins"], 1)
        self.assertEqual(summary["candidate"]["wins"], 2)
        self.assertEqual(summary["deltas"]["wins"], 1)
        self.assertAlmostEqual(summary["deltas"]["win_rate"], 0.5)
        self.assertAlmostEqual(summary["deltas"]["avg_final_hp"], 8.5)
        self.assertAlmostEqual(summary["ledger"]["win_rate_delta"], 0.5)
        self.assertEqual(summary["ledger"]["bottleneck_deltas"]["debuff_too_small"], -1)
        self.assertEqual(summary["ledger"]["debuff_gap_delta"], -1)
        self.assertAlmostEqual(
            summary["ledger"]["focus_combo_deltas"]["dr_spore_cloud"][
                "avg_debuff_delta"
            ],
            0.05,
        )
        self.assertEqual(summary["screen_verdict"], "WEAK_LOCAL_SIGNAL_DO_NOT_ADOPT")

    def test_druid_loss_buckets_stratify_by_detected_path(self):
        events_per_run = [
            [
                {
                    "t": "round_end",
                    "round": 8,
                    "detected_path": "druid_garden",
                    "theme_metrics": {"board_theme_ratio": 1.0},
                    "path_progress": [
                        {
                            "id": "druid_garden",
                            "current_phase": "payoff",
                            "current_owned": 0,
                            "current_total": 2,
                        },
                    ],
                    "active_path_progress": [
                        {
                            "id": "druid_garden",
                            "current_phase": "payoff",
                            "current_owned": 0,
                            "current_total": 2,
                        },
                    ],
                },
                {"t": "battle", "round": 8, "won": False},
                {"t": "run_end", "rounds_played": 8, "final_hp": -2, "won": False},
            ],
            [
                {
                    "t": "round_end",
                    "round": 10,
                    "detected_path": "druid_world_tree",
                    "active_board": ["dr_spore_cloud"],
                    "theme_metrics": {"board_theme_ratio": 1.0},
                    "path_progress": [
                        {
                            "id": "druid_world_tree",
                            "current_phase": "payoff",
                            "current_owned": 1,
                            "current_total": 2,
                        },
                    ],
                    "active_path_progress": [
                        {
                            "id": "druid_world_tree",
                            "current_phase": "payoff",
                            "current_owned": 1,
                            "current_total": 2,
                        },
                    ],
                },
                {
                    "t": "battle",
                    "round": 10,
                    "won": False,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.2},
                },
                {"t": "run_end", "rounds_played": 10, "final_hp": -1, "won": False},
            ],
            [
                {"t": "battle", "round": 15, "won": True},
                {"t": "run_end", "rounds_played": 15, "final_hp": 30, "won": True},
            ],
        ]

        summary = analyze_ai_trace.summarize_druid_loss_buckets(events_per_run)
        by_path = summary["by_path"]

        self.assertEqual(by_path["druid_garden"]["n_runs"], 1)
        self.assertEqual(by_path["druid_garden"]["losses"], 1)
        self.assertEqual(by_path["druid_garden"]["bucket_counts"]["payoff_acquisition_lag"], 1)
        self.assertEqual(by_path["druid_world_tree"]["n_runs"], 1)
        self.assertEqual(by_path["druid_world_tree"]["bucket_counts"]["combat_conversion_failure"], 1)
        self.assertEqual(by_path["undetected"]["n_runs"], 1)
        self.assertEqual(by_path["undetected"]["wins"], 1)

    def test_steampunk_loss_buckets_classify_access_phase_and_pressure(self):
        events_per_run = [
            [
                {"t": "round_start", "round": 10, "shop_level": 3},
                {
                    "t": "buy_skip",
                    "round": 10,
                    "reason": "no_space",
                    "offers": [
                        {"id": "sp_charger", "affordable": False, "cost": 5},
                    ],
                },
                {"t": "buy_skip", "round": 10, "reason": "no_space", "offers": []},
                {"t": "buy_skip", "round": 10, "reason": "no_space", "offers": []},
                {"t": "buy_skip", "round": 10, "reason": "nothing_affordable", "offers": []},
                {"t": "buy_skip", "round": 10, "reason": "nothing_affordable", "offers": []},
                {"t": "buy_skip", "round": 10, "reason": "nothing_affordable", "offers": []},
                {"t": "buy_skip", "round": 10, "reason": "below_threshold", "offers": []},
                {"t": "buy_skip", "round": 10, "reason": "below_threshold", "offers": []},
                {"t": "buy_skip", "round": 10, "reason": "below_threshold", "offers": []},
                {
                    "t": "round_end",
                    "round": 10,
                    "board": ["sp_assembly", "sp_furnace", "sp_workshop"],
                    "active_board": ["sp_assembly", "sp_furnace"],
                    "detected_path": "steampunk_focus",
                    "theme_metrics": {"board_theme_ratio": 0.66},
                    "path_progress": [
                        {
                            "id": "steampunk_focus",
                            "current_phase": "payoff",
                            "current_owned": 0,
                            "current_total": 2,
                        },
                    ],
                    "active_path_progress": [
                        {
                            "id": "steampunk_focus",
                            "current_phase": "payoff",
                            "current_owned": 0,
                            "current_total": 2,
                        },
                    ],
                },
                {"t": "battle", "round": 10, "won": False},
                {"t": "run_end", "rounds_played": 10, "final_hp": -2, "won": False},
            ],
            [
                {"t": "levelup", "round": 8, "from_level": 3, "to_level": 4},
                {
                    "t": "buy",
                    "round": 9,
                    "card_id": "sp_charger",
                    "offers": [
                        {"id": "sp_charger", "affordable": True, "cost": 5},
                    ],
                },
                {
                    "t": "round_end",
                    "round": 9,
                    "board": ["sp_furnace", "sp_charger"],
                    "active_board": ["sp_furnace"],
                    "detected_path": "steampunk_focus",
                    "theme_metrics": {"board_theme_ratio": 1.0},
                    "path_progress": [
                        {
                            "id": "steampunk_focus",
                            "current_phase": "payoff",
                            "current_owned": 1,
                            "current_total": 2,
                        },
                    ],
                    "active_path_progress": [
                        {
                            "id": "steampunk_focus",
                            "current_phase": "payoff",
                            "current_owned": 0,
                            "current_total": 2,
                        },
                    ],
                },
                {"t": "battle", "round": 9, "won": False},
                {"t": "run_end", "rounds_played": 9, "final_hp": -1, "won": False},
            ],
            [
                {"t": "battle", "round": 15, "won": True},
                {"t": "run_end", "rounds_played": 15, "final_hp": 30, "won": True},
            ],
        ]

        summary = analyze_ai_trace.summarize_steampunk_loss_buckets(events_per_run)

        self.assertEqual(summary["n_runs"], 3)
        self.assertEqual(summary["wins"], 1)
        self.assertEqual(summary["losses"], 2)
        self.assertEqual(summary["bucket_counts"]["tier_access_lag"], 1)
        self.assertEqual(summary["bucket_counts"]["payoff_acquisition_lag"], 1)
        self.assertEqual(summary["bucket_counts"]["payoff_activation_gap"], 1)
        self.assertEqual(summary["bucket_counts"]["branch_mix"], 1)
        self.assertEqual(summary["bucket_counts"]["current_phase_lag"], 1)
        self.assertEqual(summary["bucket_counts"]["owned_not_active_gap"], 1)
        self.assertEqual(summary["bucket_counts"]["no_space_pressure"], 1)
        self.assertEqual(summary["bucket_counts"]["affordability_pressure"], 1)
        self.assertEqual(summary["bucket_counts"]["threshold_pressure"], 1)
        self.assertEqual(summary["bucket_counts"]["low_steampunk_board_ratio"], 1)
        self.assertEqual(summary["loss_payoff_offered_runs"], 2)
        self.assertEqual(summary["loss_payoff_affordable_runs"], 1)
        self.assertEqual(summary["loss_payoff_bought_runs"], 1)

    def test_steampunk_loss_buckets_stratify_by_detected_path(self):
        events_per_run = [
            [
                {
                    "t": "round_end",
                    "round": 10,
                    "board": ["sp_furnace"],
                    "active_board": ["sp_furnace"],
                    "detected_path": "steampunk_focus",
                    "theme_metrics": {"board_theme_ratio": 1.0},
                    "path_progress": [
                        {
                            "id": "steampunk_focus",
                            "current_phase": "payoff",
                            "current_owned": 0,
                            "current_total": 2,
                        },
                    ],
                    "active_path_progress": [
                        {
                            "id": "steampunk_focus",
                            "current_phase": "payoff",
                            "current_owned": 0,
                            "current_total": 2,
                        },
                    ],
                },
                {"t": "battle", "round": 10, "won": False},
                {"t": "run_end", "rounds_played": 10, "final_hp": -2, "won": False},
            ],
            [
                {
                    "t": "round_end",
                    "round": 12,
                    "board": ["sp_assembly", "sp_warmachine"],
                    "active_board": ["sp_assembly", "sp_warmachine"],
                    "detected_path": "steampunk_spread",
                    "theme_metrics": {"board_theme_ratio": 1.0},
                    "path_progress": [
                        {
                            "id": "steampunk_spread",
                            "current_phase": "capstone",
                            "current_owned": 0,
                            "current_total": 1,
                        },
                    ],
                    "active_path_progress": [
                        {
                            "id": "steampunk_spread",
                            "current_phase": "capstone",
                            "current_owned": 0,
                            "current_total": 1,
                        },
                    ],
                },
                {"t": "battle", "round": 12, "won": True},
                {"t": "run_end", "rounds_played": 12, "final_hp": 10, "won": True},
            ],
            [
                {"t": "battle", "round": 8, "won": False},
                {"t": "run_end", "rounds_played": 8, "final_hp": -1, "won": False},
            ],
        ]

        summary = analyze_ai_trace.summarize_steampunk_loss_buckets(events_per_run)
        by_path = summary["by_path"]

        self.assertEqual(by_path["steampunk_focus"]["n_runs"], 1)
        self.assertEqual(by_path["steampunk_focus"]["losses"], 1)
        self.assertEqual(
            by_path["steampunk_focus"]["bucket_counts"]["payoff_acquisition_lag"],
            1,
        )
        self.assertEqual(by_path["steampunk_spread"]["n_runs"], 1)
        self.assertEqual(by_path["steampunk_spread"]["wins"], 1)
        self.assertEqual(by_path["undetected"]["n_runs"], 1)
        self.assertEqual(by_path["undetected"]["losses"], 1)

    def test_steampunk_loss_buckets_classify_active_payoff_engine_gaps(self):
        events_per_run = [
            [
                {"t": "levelup", "round": 8, "from_level": 3, "to_level": 4},
                {"t": "buy", "round": 9, "card_id": "sp_warmachine"},
                {
                    "t": "sell",
                    "round": 9,
                    "reason": "weakest_for_upgrade",
                    "zone": "bench",
                    "card_id": "sp_line",
                },
                {
                    "t": "round_end",
                    "round": 9,
                    "board": ["sp_assembly", "sp_workshop", "sp_warmachine"],
                    "active_board": ["sp_assembly", "sp_workshop", "sp_warmachine"],
                    "detected_path": "steampunk_spread",
                    "theme_metrics": {"board_theme_ratio": 1.0},
                    "path_progress": [
                        {
                            "id": "steampunk_spread",
                            "current_phase": "payoff",
                            "current_owned": 1,
                            "current_total": 2,
                        },
                    ],
                    "active_path_progress": [
                        {
                            "id": "steampunk_spread",
                            "current_phase": "payoff",
                            "current_owned": 1,
                            "current_total": 2,
                        },
                    ],
                },
                {"t": "battle", "round": 9, "won": False},
                {"t": "run_end", "rounds_played": 9, "final_hp": -3, "won": False},
            ],
            [
                {"t": "levelup", "round": 8, "from_level": 3, "to_level": 4},
                {"t": "levelup", "round": 10, "from_level": 4, "to_level": 5},
                {"t": "buy", "round": 10, "card_id": "sp_arsenal"},
                {
                    "t": "round_end",
                    "round": 10,
                    "board": ["sp_furnace", "sp_workshop", "sp_circulator", "sp_arsenal"],
                    "active_board": [
                        "sp_furnace",
                        "sp_workshop",
                        "sp_circulator",
                        "sp_arsenal",
                    ],
                    "detected_path": "steampunk_focus",
                    "theme_metrics": {"board_theme_ratio": 1.0},
                    "path_progress": [
                        {
                            "id": "steampunk_focus",
                            "current_phase": "capstone",
                            "current_owned": 1,
                            "current_total": 1,
                        },
                    ],
                    "active_path_progress": [
                        {
                            "id": "steampunk_focus",
                            "current_phase": "capstone",
                            "current_owned": 1,
                            "current_total": 1,
                        },
                    ],
                },
                {"t": "battle", "round": 10, "won": False},
                {"t": "run_end", "rounds_played": 10, "final_hp": -5, "won": False},
            ],
        ]

        summary = analyze_ai_trace.summarize_steampunk_loss_buckets(events_per_run)

        self.assertEqual(summary["bucket_counts"]["payoff_engine_gap"], 1)
        self.assertEqual(summary["bucket_counts"]["capstone_support_gap"], 1)
        self.assertEqual(summary["loss_payoff_engine_gap_runs"], 1)
        self.assertEqual(summary["loss_capstone_support_gap_runs"], 1)
        self.assertEqual(
            summary["examples"][0]["engine_gaps"][0]["missing"],
            ["sp_line"],
        )
        self.assertEqual(
            summary["examples"][1]["engine_gaps"][0]["missing"],
            ["sp_charger"],
        )

    def test_steampunk_target_funnel_tracks_engine_offer_space_gap(self):
        events_per_run = [
            [
                {
                    "t": "buy_skip",
                    "round": 9,
                    "reason": "no_space",
                    "offers": [
                        {
                            "id": "sp_line",
                            "cost": 4,
                            "score": 32.0,
                            "affordable": True,
                        },
                        {
                            "id": "sp_warmachine",
                            "cost": 7,
                            "score": None,
                            "affordable": False,
                        },
                    ],
                },
                {"t": "buy", "round": 9, "card_id": "sp_warmachine"},
                {
                    "t": "sell",
                    "round": 9,
                    "reason": "weakest_for_upgrade",
                    "zone": "bench",
                    "card_id": "sp_line",
                },
                {
                    "t": "round_end",
                    "round": 9,
                    "board": ["sp_assembly", "sp_workshop", "sp_warmachine"],
                    "active_board": ["sp_assembly", "sp_workshop", "sp_warmachine"],
                    "detected_path": "steampunk_spread",
                    "theme_metrics": {"board_theme_ratio": 1.0},
                    "path_progress": [
                        {
                            "id": "steampunk_spread",
                            "current_phase": "payoff",
                            "current_owned": 1,
                            "current_total": 2,
                        },
                    ],
                    "active_path_progress": [
                        {
                            "id": "steampunk_spread",
                            "current_phase": "payoff",
                            "current_owned": 1,
                            "current_total": 2,
                        },
                    ],
                },
                {"t": "battle", "round": 9, "won": False},
                {"t": "run_end", "rounds_played": 9, "final_hp": -4, "won": False},
            ],
        ]

        summary = analyze_ai_trace.summarize_steampunk_loss_buckets(events_per_run)
        engine = summary["loss_target_funnels"]["engine"]
        payoff = summary["loss_target_funnels"]["payoff"]

        self.assertEqual(engine["offered_runs"], 1)
        self.assertEqual(engine["affordable_runs"], 1)
        self.assertEqual(engine["bought_runs"], 0)
        self.assertEqual(engine["sold_runs"], 1)
        self.assertEqual(engine["complete_owned_runs"], 0)
        self.assertEqual(engine["complete_active_runs"], 0)
        self.assertEqual(engine["missing_final_runs"], 1)
        self.assertEqual(engine["affordable_skip_reasons"]["no_space"], 1)
        self.assertEqual(engine["sold_cards"]["sp_line"], 1)
        self.assertEqual(engine["missing_final_cards"]["sp_line"], 1)
        self.assertEqual(payoff["bought_runs"], 1)
        self.assertEqual(payoff["complete_owned_runs"], 1)
        self.assertEqual(summary["examples"][0]["target_gaps"]["engine"]["missing_final"], ["sp_line"])


if __name__ == "__main__":
    unittest.main()
