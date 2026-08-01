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

    def test_druid_offense_ledger_splits_shortfall_by_wrath_world_presence(self):
        events_per_run = [
            [
                {
                    "t": "round_end",
                    "round": 9,
                    "active_board": ["dr_spore_cloud", "dr_cradle", "dr_lifebeat"],
                    "detected_path": "druid_garden",
                    "states": {
                        "dr_spore_cloud": {"star": 1, "trees": 0},
                        "dr_cradle": {"star": 2, "trees": 12},
                        "dr_lifebeat": {"star": 1, "trees": 4},
                    },
                },
                {
                    "t": "battle",
                    "round": 9,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 14,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.24},
                },
                {"t": "run_end", "rounds_played": 9, "final_hp": -3, "won": False},
            ],
            [
                {
                    "t": "round_end",
                    "round": 10,
                    "active_board": [
                        "dr_spore_cloud",
                        "dr_wrath",
                        "dr_cradle",
                        "dr_lifebeat",
                    ],
                    "detected_path": "druid_garden",
                    "states": {
                        "dr_spore_cloud": {"star": 1, "trees": 1},
                        "dr_wrath": {"star": 2, "trees": 3},
                        "dr_cradle": {"star": 2, "trees": 10},
                        "dr_lifebeat": {"star": 1, "trees": 4},
                    },
                },
                {
                    "t": "battle",
                    "round": 10,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 13,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.22},
                },
                {"t": "run_end", "rounds_played": 10, "final_hp": -2, "won": False},
            ],
            [
                {
                    "t": "round_end",
                    "round": 11,
                    "active_board": ["dr_wrath", "dr_cradle", "dr_lifebeat"],
                    "detected_path": "druid_world_tree",
                    "states": {
                        "dr_wrath": {"star": 1, "trees": 2},
                        "dr_cradle": {"star": 2, "trees": 10},
                        "dr_lifebeat": {"star": 1, "trees": 4},
                    },
                },
                {
                    "t": "battle",
                    "round": 11,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 16,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.0},
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

        summary = analyze_ai_trace.summarize_druid_offense_ledger(events_per_run)

        self.assertEqual(summary["frames"], 4)
        self.assertEqual(summary["wins"], 1)
        self.assertEqual(summary["losses"], 3)
        self.assertEqual(summary["offense_active_frames"], 3)
        self.assertEqual(summary["offense_active_losses"], 2)
        self.assertEqual(summary["no_offense_losses"], 1)
        self.assertEqual(summary["damage_shortfall_losses"], 2)
        self.assertEqual(summary["damage_shortfall_with_offense"], 1)
        self.assertEqual(summary["damage_shortfall_without_offense"], 1)
        self.assertEqual(summary["debuff_gap_losses"], 1)
        self.assertEqual(summary["by_offense_combo"]["none"]["damage_shortfall_losses"], 1)
        self.assertEqual(
            summary["by_spore_pairing"]["spore+dr_wrath"]["damage_shortfall_losses"],
            1,
        )
        self.assertAlmostEqual(
            summary["by_offense_combo"]["dr_wrath"]["avg_offense_star_sum"],
            1.5,
        )
        self.assertIn("OFFENSE_ACCESS", summary["next_signal"])

    def test_druid_offense_comparison_flags_debuff_repair_exposed_shortfall(self):
        baseline_events = [
            [
                {
                    "t": "round_end",
                    "round": 9,
                    "active_board": ["dr_spore_cloud", "dr_cradle", "dr_lifebeat"],
                    "detected_path": "druid_garden",
                    "states": {
                        "dr_spore_cloud": {"star": 1, "trees": 0},
                        "dr_cradle": {"star": 2, "trees": 12},
                        "dr_lifebeat": {"star": 1, "trees": 4},
                    },
                },
                {
                    "t": "battle",
                    "round": 9,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 14,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.10},
                },
                {"t": "run_end", "rounds_played": 9, "final_hp": -3, "won": False},
            ],
        ]
        candidate_events = [
            [
                {
                    "t": "round_end",
                    "round": 9,
                    "active_board": ["dr_spore_cloud", "dr_cradle", "dr_lifebeat"],
                    "detected_path": "druid_garden",
                    "states": {
                        "dr_spore_cloud": {"star": 1, "trees": 0},
                        "dr_cradle": {"star": 2, "trees": 12},
                        "dr_lifebeat": {"star": 1, "trees": 4},
                    },
                },
                {
                    "t": "battle",
                    "round": 9,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 14,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.24},
                },
                {"t": "run_end", "rounds_played": 9, "final_hp": -3, "won": False},
            ],
        ]

        comparison = analyze_ai_trace.summarize_druid_offense_comparison(
            candidate_events,
            baseline_events,
        )

        self.assertEqual(comparison["deltas"]["damage_shortfall_losses"], 1)
        self.assertEqual(comparison["deltas"]["debuff_gap_losses"], -1)
        self.assertIn("DEBUFF_REPAIR_EXPOSED", comparison["next_signal"])

    def test_druid_offense_causal_split_classifies_access_timing_and_conversion(self):
        events_per_run = [
            [
                {"t": "round_start", "round": 9, "hp": 18},
                {"t": "buy", "round": 9, "card_id": "dr_spore_cloud"},
                {"t": "buy", "round": 9, "card_id": "dr_wrath"},
                {
                    "t": "round_end",
                    "round": 9,
                    "board": ["dr_spore_cloud", "dr_wrath", "dr_cradle"],
                    "bench": ["dr_wrath"],
                    "active_board": ["dr_spore_cloud", "dr_cradle"],
                    "detected_path": "druid_garden",
                    "states": {
                        "dr_spore_cloud": {"star": 1, "trees": 0},
                        "dr_cradle": {"star": 2, "trees": 12},
                    },
                },
                {
                    "t": "battle",
                    "round": 9,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 14,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.24},
                },
                {"t": "run_end", "rounds_played": 9, "final_hp": -3, "won": False},
            ],
            [
                {"t": "round_start", "round": 10, "hp": 4},
                {
                    "t": "buy_skip",
                    "round": 10,
                    "reason": "path_lag_hold",
                    "offers": [
                        {"id": "dr_wrath", "affordable": True, "cost": 5},
                    ],
                },
                {
                    "t": "round_end",
                    "round": 10,
                    "board": ["dr_spore_cloud", "dr_cradle"],
                    "bench": [],
                    "active_board": ["dr_spore_cloud", "dr_cradle"],
                    "detected_path": "druid_garden",
                    "states": {
                        "dr_spore_cloud": {"star": 1, "trees": 1},
                        "dr_cradle": {"star": 2, "trees": 10},
                    },
                },
                {
                    "t": "battle",
                    "round": 10,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 13,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.22},
                },
                {"t": "run_end", "rounds_played": 10, "final_hp": -2, "won": False},
            ],
            [
                {"t": "round_start", "round": 10, "hp": 17},
                {
                    "t": "round_end",
                    "round": 10,
                    "board": ["dr_spore_cloud", "dr_wrath", "dr_cradle"],
                    "bench": [],
                    "active_board": ["dr_spore_cloud", "dr_wrath", "dr_cradle"],
                    "detected_path": "druid_world_tree",
                    "states": {
                        "dr_spore_cloud": {"star": 1, "trees": 2},
                        "dr_wrath": {"star": 1, "trees": 1},
                        "dr_cradle": {"star": 2, "trees": 12},
                    },
                },
                {
                    "t": "battle",
                    "round": 10,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 15,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.25},
                },
                {"t": "run_end", "rounds_played": 10, "final_hp": -1, "won": False},
            ],
            [
                {"t": "round_start", "round": 11, "hp": 16},
                {
                    "t": "round_end",
                    "round": 11,
                    "board": ["dr_wrath", "dr_cradle", "dr_lifebeat"],
                    "bench": [],
                    "active_board": ["dr_wrath", "dr_cradle", "dr_lifebeat"],
                    "detected_path": "druid_world_tree",
                    "states": {
                        "dr_wrath": {"star": 1, "trees": 2},
                        "dr_cradle": {"star": 2, "trees": 10},
                        "dr_lifebeat": {"star": 1, "trees": 4},
                    },
                },
                {
                    "t": "battle",
                    "round": 11,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 16,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.0},
                },
                {"t": "run_end", "rounds_played": 11, "final_hp": -1, "won": False},
            ],
        ]

        summary = analyze_ai_trace.summarize_druid_offense_causal_split(events_per_run)

        self.assertEqual(summary["losses"], 4)
        self.assertEqual(summary["spore_offense_frames"], 1)
        self.assertEqual(summary["spore_offense_losses"], 1)
        self.assertEqual(summary["active_pair_under_damage_losses"], 1)
        self.assertEqual(summary["owned_inactive_losses"], 1)
        self.assertEqual(summary["offered_not_bought_losses"], 1)
        self.assertEqual(summary["not_seen_or_unavailable_losses"], 1)
        self.assertEqual(summary["active_too_late_losses"], 1)
        self.assertEqual(summary["primary_causal_buckets"]["owned_inactive"], 1)
        self.assertEqual(summary["primary_causal_buckets"]["active_too_late"], 1)
        self.assertEqual(
            summary["primary_causal_buckets"]["active_pair_under_damaging"],
            1,
        )
        self.assertEqual(
            summary["primary_causal_buckets"]["not_seen_or_unavailable"],
            1,
        )
        self.assertEqual(summary["access_buckets"]["active_pair"], 1)
        self.assertEqual(summary["access_buckets"]["owned_inactive"], 1)
        self.assertEqual(summary["access_buckets"]["offered_not_bought"], 1)
        self.assertEqual(summary["missing_targets"]["offense"], 2)
        self.assertEqual(summary["missing_targets"]["spore"], 1)
        self.assertIn("ACTIVATION_PACKET_CANDIDATE", summary["next_signal"])

    def test_druid_offense_causal_comparison_routes_owned_inactive_growth(self):
        baseline_events = [
            [
                {"t": "round_start", "round": 9, "hp": 18},
                {
                    "t": "round_end",
                    "round": 9,
                    "board": ["dr_spore_cloud", "dr_cradle"],
                    "bench": [],
                    "active_board": ["dr_spore_cloud", "dr_cradle"],
                    "detected_path": "druid_garden",
                    "states": {
                        "dr_spore_cloud": {"star": 1, "trees": 0},
                        "dr_cradle": {"star": 2, "trees": 12},
                    },
                },
                {
                    "t": "battle",
                    "round": 9,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 14,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.24},
                },
            ],
        ]
        candidate_events = []
        for idx in range(6):
            candidate_events.append([
                {"t": "round_start", "round": 9, "hp": 18},
                {"t": "buy", "round": 9, "card_id": "dr_wrath"},
                {
                    "t": "round_end",
                    "round": 9,
                    "board": ["dr_spore_cloud", "dr_wrath", "dr_cradle"],
                    "bench": ["dr_wrath"],
                    "active_board": ["dr_spore_cloud", "dr_cradle"],
                    "detected_path": "druid_garden",
                    "states": {
                        "dr_spore_cloud": {"star": 1, "trees": idx},
                        "dr_cradle": {"star": 2, "trees": 12},
                    },
                },
                {
                    "t": "battle",
                    "round": 9,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 14,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.24},
                },
            ])

        comparison = analyze_ai_trace.summarize_druid_offense_causal_comparison(
            candidate_events,
            baseline_events,
        )

        self.assertEqual(comparison["deltas"]["owned_inactive_losses"], 6)
        self.assertIn("PAIR_ACTIVATION_CANDIDATE", comparison["next_signal"])

    def test_druid_spore_tree_gap_audits_own_vs_active_forest_depth(self):
        events_per_run = [
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
                    "active_board": ["dr_spore_cloud", "dr_cradle"],
                    "detected_path": "druid_garden",
                    "states": {
                        "dr_spore_cloud": {"star": 1, "trees": 0},
                        "dr_cradle": {"star": 1, "trees": 10},
                    },
                },
                {
                    "t": "battle",
                    "round": 11,
                    "won": True,
                    "ally_survived": 6,
                    "enemy_survived": 0,
                    "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.22},
                },
                {"t": "run_end", "rounds_played": 15, "final_hp": 12, "won": True},
            ],
        ]

        summary = analyze_ai_trace.summarize_druid_spore_tree_gap(events_per_run)

        self.assertEqual(summary["focus_frames"], 4)
        self.assertEqual(summary["focus_losses"], 3)
        self.assertEqual(summary["spore_frames"], 3)
        self.assertEqual(summary["spore_wins"], 1)
        self.assertEqual(summary["spore_losses"], 2)
        self.assertAlmostEqual(summary["avg_spore_own_trees"], 5 / 3)
        self.assertAlmostEqual(summary["avg_active_tree_counters"], 76 / 3)
        self.assertAlmostEqual(summary["loss_avg_active_tree_counters"], 33.0)
        self.assertEqual(summary["zero_own_high_forest_loss_frames"], 1)
        self.assertEqual(summary["low_own_high_forest_loss_frames"], 1)
        self.assertEqual(summary["low_debuff_losses"], 1)
        self.assertEqual(summary["low_debuff_loss_crossings"], 1)
        self.assertEqual(summary["winning_low_debuff_crossings"], 0)
        self.assertEqual(
            summary["bottlenecks_by_forest_band"]["9-17"]["debuff_missing"],
            1,
        )
        self.assertEqual(
            summary["bottlenecks_by_forest_band"]["27+"]["debuff_too_small"],
            1,
        )
        self.assertEqual(summary["spore_loss_by_forest_band"]["27+"]["frames"], 2)
        self.assertAlmostEqual(
            summary["spore_loss_by_forest_band"]["27+"]["avg_probe_debuff"],
            (0.225 + 0.3275) / 2,
        )
        self.assertTrue(
            summary["next_signal"].startswith(
                "PACKET_CANDIDATE_FOREST_DEPTH_SPORE_SCALING"
            )
        )

    def _h126_stack(
        self,
        unit_id,
        count,
        final_attack_interval,
        base_attack_interval=None,
    ):
        base_interval = (
            final_attack_interval
            if base_attack_interval is None
            else base_attack_interval
        )
        return {
            "unit_id": unit_id,
            "count": count,
            "eff_atk": 10.0,
            "eff_hp": 50.0,
            "base_attack_interval": base_interval,
            "upgrade_as_mult": 1.0,
            "unique_as_mult": 1.0,
            "temp_as_mult": 1.0,
            "final_attack_interval": final_attack_interval,
            "total_atk": 10.0 * count,
            "total_hp": 50.0 * count,
            "total_dps": (10.0 * count) / max(final_attack_interval, 0.01),
            "range": 1,
            "move_speed": 1,
            "def": 0,
        }

    def _h126_card(
        self,
        idx,
        card_id,
        star,
        trees,
        units,
        total_atk,
        total_hp,
        total_dps,
        stacks=None,
        enemy_atk_debuff=0.0,
        enemy_as_debuff=0.0,
    ):
        return {
            "idx": idx,
            "id": card_id,
            "star": star,
            "trees": trees,
            "units": units,
            "total_atk": total_atk,
            "total_hp": total_hp,
            "total_dps": total_dps,
            "growth_atk_pct": 0.0,
            "growth_hp_pct": 0.0,
            "unique_buff_pct": 0.0,
            "upgrade_as_mult": 1.0,
            "unique_as_mult": 1.0,
            "temp_as_mult": 1.0,
            "shield_hp_pct": 0.0,
            "enemy_atk_debuff": enemy_atk_debuff,
            "enemy_as_debuff": enemy_as_debuff,
            "kill_hp_recover_pct": 0.0,
            "mechanics": [],
            "stacks": stacks or [],
        }

    def _h126_snapshot(self, cards, enemy_debuffs=None):
        return {
            "forest_depth": sum(int(card["trees"]) for card in cards),
            "druid_count": len(cards),
            "druid_units": sum(int(card["units"]) for card in cards),
            "druid_total_atk": sum(float(card["total_atk"]) for card in cards),
            "druid_total_hp": sum(float(card["total_hp"]) for card in cards),
            "druid_total_dps": sum(float(card["total_dps"]) for card in cards),
            "enemy_debuffs": enemy_debuffs or {"atk_pct": 0.0, "as_pct": 0.0},
            "cards": cards,
        }

    def test_druid_contribution_ledger_reads_h126_snapshot_pairs(self):
        spore = self._h126_card(
            0,
            "dr_spore_cloud",
            2,
            4,
            3,
            35.0,
            180.0,
            25.0,
            stacks=[
                self._h126_stack("dr_spore", 2, 1.5),
                self._h126_stack("dr_toad", 1, 1.0),
            ],
            enemy_atk_debuff=0.05,
            enemy_as_debuff=0.05,
        )
        wrath = self._h126_card(
            1,
            "dr_wrath",
            1,
            3,
            3,
            80.0,
            140.0,
            100.0,
            stacks=[
                self._h126_stack("dr_spore", 1, 1.5, base_attack_interval=3.0),
                self._h126_stack("dr_boar", 1, 1.0, base_attack_interval=2.5),
                self._h126_stack("dr_wolf", 1, 0.5, base_attack_interval=2.0),
            ],
        )
        cradle = self._h126_card(
            2,
            "dr_cradle",
            1,
            11,
            2,
            25.0,
            100.0,
            20.0,
        )
        events_per_run = [
            [
                {
                    "t": "round_end",
                    "round": 9,
                    "active_board": ["dr_spore_cloud", "dr_wrath", "dr_cradle"],
                    "detected_path": "druid_garden",
                },
                {
                    "t": "battle",
                    "round": 9,
                    "won": False,
                    "hp_after": -2,
                    "ally_survived": 0,
                    "enemy_survived": 12,
                    "druid_combat_snapshot": self._h126_snapshot(
                        [spore, wrath, cradle],
                        enemy_debuffs={"atk_pct": 0.28, "as_pct": 0.28},
                    ),
                },
            ],
        ]

        summary = analyze_ai_trace.summarize_druid_contribution_ledger(events_per_run)

        self.assertEqual(summary["in_scope_battles"], 1)
        self.assertEqual(summary["snapshot_battles"], 1)
        self.assertEqual(summary["focus_frames"], 1)
        self.assertEqual(summary["losses"], 1)
        self.assertAlmostEqual(summary["focus_snapshot_coverage"], 1.0)
        self.assertEqual(summary["spore_offense_frames"], 1)
        self.assertEqual(summary["spore_offense_losses"], 1)
        self.assertEqual(summary["runtime_buckets"]["pair_no_ally_survival"], 1)
        self.assertAlmostEqual(summary["avg_pair_loss_spore_atk_debuff"], 0.28)
        self.assertAlmostEqual(summary["avg_pair_loss_spore_as_debuff"], 0.28)
        self.assertAlmostEqual(summary["avg_pair_loss_offense_units"], 3.0)
        self.assertAlmostEqual(summary["avg_pair_loss_offense_dps"], 100.0)
        self.assertAlmostEqual(summary["avg_pair_loss_offense_attack_interval"], 1.0)
        self.assertEqual(
            summary["by_pairing"]["spore+dr_wrath"]["runtime_buckets"],
            {"pair_no_ally_survival": 1},
        )
        self.assertIn("PAIR_CONTRIBUTION_TRACE_READY", summary["next_signal"])

    def test_druid_contribution_ledger_reports_missing_focus_snapshots(self):
        events_per_run = [
            [
                {
                    "t": "round_end",
                    "round": 9,
                    "active_board": ["dr_spore_cloud", "dr_cradle"],
                    "detected_path": "druid_garden",
                },
                {
                    "t": "battle",
                    "round": 9,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 14,
                },
            ],
        ]

        summary = analyze_ai_trace.summarize_druid_contribution_ledger(events_per_run)

        self.assertEqual(summary["in_scope_battles"], 1)
        self.assertEqual(summary["snapshot_battles"], 0)
        self.assertEqual(summary["focus_frames"], 0)
        self.assertEqual(summary["missing_focus_snapshot"], 1)
        self.assertAlmostEqual(summary["focus_snapshot_coverage"], 0.0)
        self.assertIn("SNAPSHOT_EMISSION_REQUIRED", summary["next_signal"])

    def test_druid_contribution_ledger_rejects_malformed_snapshot(self):
        spore = self._h126_card(
            0,
            "dr_spore_cloud",
            2,
            4,
            3,
            35.0,
            180.0,
            25.0,
            stacks=[
                self._h126_stack("dr_spore", 2, 1.5),
                self._h126_stack("dr_toad", 1, 1.0),
            ],
        )
        wrath = self._h126_card(
            1,
            "dr_wrath",
            1,
            3,
            3,
            80.0,
            140.0,
            100.0,
            stacks=[
                self._h126_stack("dr_spore", 1, 1.5),
                self._h126_stack("dr_boar", 1, 1.0),
                self._h126_stack("dr_wolf", 1, 0.5),
            ],
        )
        snapshot = self._h126_snapshot(
            [spore, wrath],
            enemy_debuffs={"atk_pct": 0.28, "as_pct": 0.28},
        )
        del snapshot["enemy_debuffs"]
        del snapshot["cards"][1]["stacks"][0]["final_attack_interval"]
        events_per_run = [
            [
                {
                    "t": "round_end",
                    "round": 9,
                    "active_board": ["dr_spore_cloud", "dr_wrath"],
                    "detected_path": "druid_garden",
                },
                {
                    "t": "battle",
                    "round": 9,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 12,
                    "druid_combat_snapshot": snapshot,
                },
            ],
        ]

        summary = analyze_ai_trace.summarize_druid_contribution_ledger(events_per_run)

        self.assertEqual(summary["in_scope_battles"], 1)
        self.assertEqual(summary["snapshot_battles"], 0)
        self.assertEqual(summary["focus_frames"], 0)
        self.assertEqual(summary["invalid_snapshot_battles"], 1)
        self.assertEqual(summary["invalid_focus_snapshot"], 1)
        self.assertAlmostEqual(summary["focus_snapshot_coverage"], 0.0)
        self.assertIn("SNAPSHOT_SCHEMA_INVALID", summary["next_signal"])

    def test_druid_contribution_ledger_marks_snapshot_without_cards_invalid(self):
        events_per_run = [
            [
                {
                    "t": "round_end",
                    "round": 9,
                    "active_board": ["dr_spore_cloud"],
                    "detected_path": "druid_garden",
                },
                {
                    "t": "battle",
                    "round": 9,
                    "won": False,
                    "ally_survived": 0,
                    "enemy_survived": 12,
                    "druid_combat_snapshot": {
                        "forest_depth": 4,
                        "enemy_debuffs": {"atk_pct": 0.0, "as_pct": 0.2},
                    },
                },
            ],
        ]

        summary = analyze_ai_trace.summarize_druid_contribution_ledger(events_per_run)

        self.assertEqual(summary["in_scope_battles"], 1)
        self.assertEqual(summary["snapshot_battles"], 0)
        self.assertEqual(summary["focus_frames"], 0)
        self.assertEqual(summary["missing_focus_snapshot"], 0)
        self.assertEqual(summary["invalid_snapshot_battles"], 1)
        self.assertEqual(summary["invalid_focus_snapshot"], 1)
        self.assertIn("SNAPSHOT_SCHEMA_INVALID", summary["next_signal"])

    def test_druid_contribution_ledger_rejects_wrong_scalar_types(self):
        def valid_snapshot():
            spore = self._h126_card(
                0,
                "dr_spore_cloud",
                2,
                4,
                3,
                35.0,
                180.0,
                25.0,
                stacks=[
                    self._h126_stack("dr_spore", 2, 1.5),
                    self._h126_stack("dr_toad", 1, 1.0),
                ],
            )
            wrath = self._h126_card(
                1,
                "dr_wrath",
                1,
                3,
                3,
                80.0,
                140.0,
                100.0,
                stacks=[
                    self._h126_stack("dr_spore", 1, 1.5),
                    self._h126_stack("dr_boar", 1, 1.0),
                ],
            )
            return self._h126_snapshot(
                [spore, wrath],
                enemy_debuffs={"atk_pct": 0.28, "as_pct": 0.28},
            )

        cases = {
            "top_level_int_string": lambda snap: snap.update({"forest_depth": "7"}),
            "top_level_non_finite_number": lambda snap: snap.update(
                {"druid_total_dps": float("nan")}
            ),
            "debuff_bool": lambda snap: snap["enemy_debuffs"].update({"atk_pct": True}),
            "card_id_number": lambda snap: snap["cards"][0].update({"id": 123}),
            "stack_count_fraction": lambda snap: snap["cards"][1]["stacks"][0].update(
                {"count": 1.5}
            ),
            "stack_interval_string": lambda snap: snap["cards"][1]["stacks"][0].update(
                {"final_attack_interval": "1.5"}
            ),
        }
        for case, mutate in cases.items():
            with self.subTest(case=case):
                snapshot = valid_snapshot()
                mutate(snapshot)
                events_per_run = [
                    [
                        {
                            "t": "round_end",
                            "round": 9,
                            "active_board": ["dr_spore_cloud", "dr_wrath"],
                            "detected_path": "druid_garden",
                        },
                        {
                            "t": "battle",
                            "round": 9,
                            "won": False,
                            "ally_survived": 0,
                            "enemy_survived": 12,
                            "druid_combat_snapshot": snapshot,
                        },
                    ],
                ]

                summary = analyze_ai_trace.summarize_druid_contribution_ledger(
                    events_per_run
                )

                self.assertEqual(summary["snapshot_battles"], 0)
                self.assertEqual(summary["focus_frames"], 0)
                self.assertEqual(summary["invalid_snapshot_battles"], 1)
                self.assertEqual(summary["invalid_focus_snapshot"], 1)
                self.assertIn("SNAPSHOT_SCHEMA_INVALID", summary["next_signal"])

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
