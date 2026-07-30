from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import lint_live_ui_screenshots as screenshot_lint  # noqa: E402
import summarize_live_ui_report as summary  # noqa: E402


class LiveUiReportSummaryTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self._tmp.name)
        self.report_path = self.tmpdir / "report.json"

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _write_report(self, report: dict) -> Path:
        self.report_path.write_text(json.dumps(report), encoding="utf-8")
        return self.report_path

    def _valid_report(self, screenshot_status: str = "disabled") -> dict:
        def choice_summary(choice_id: str, idx: int, name: str, desc: str) -> dict:
            return {
                "id": choice_id,
                "idx": idx,
                "name": name,
                "desc": desc,
                "text": f"{name}\n{desc}",
                "rect": {
                    "x": 100 + idx * 240,
                    "y": 200,
                    "w": 230,
                    "h": 150,
                    "visible": True,
                },
            }

        initial_commander_summaries = [
            choice_summary("1", 0, "Gambler", "50% free rerolls; star3 merge refund"),
            choice_summary("2", 1, "Breeder", "Unit cap +20; extra unit chance"),
        ]
        initial_talisman_summaries = [
            choice_summary("8", 0, "Flint", "First growth x2 each round"),
            choice_summary("5", 1, "Two-Faced Coin", "One shop card discounted and one marked up"),
            choice_summary("9", 2, "Cracked Skull", "First lethal hit survives at 1 HP"),
        ]
        initial_commander_context = "커맨더 = 런 전체 방향을 바꾸는 큰 규칙"
        initial_talisman_context = (
            "선택한 커맨더: 🎲 Gambler - 50% free rerolls; star3 merge refund\n"
            "부적 = 커맨더를 보조하는 작은 규칙 1개"
        )
        post_commander_summaries = [
            choice_summary("1", 0, "Gambler", "50% free rerolls; star3 merge refund"),
            choice_summary("2", 1, "Breeder", "Unit cap +20; extra unit chance"),
            choice_summary("3", 2, "Smith", "Upgrade slot +1; Common discount"),
            choice_summary("4", 3, "Strategist", "Field +1; swap two cards"),
            choice_summary("5", 4, "Collector", "Diverse field ATK bonus"),
            choice_summary("6", 5, "Raider", "Win gold and free upgrades"),
            choice_summary("7", 6, "Alchemist", "Epic shop and round Terazin"),
        ]
        post_talisman_summaries = [
            choice_summary("3", 0, "Mercury Drop", "Enhance effects +25%"),
            choice_summary("7", 1, "Cracked Egg", "Star2+ unit spawns +1"),
            choice_summary("8", 2, "Flint", "First growth x2 each round"),
            choice_summary("9", 3, "Cracked Skull", "First lethal hit survives at 1 HP"),
            choice_summary("10", 4, "Rusty Wrench", "Detach upgrades for 50% refund"),
            choice_summary("11", 5, "Soul Jar", "First sell distributes units"),
        ]
        post_commander_context = "커맨더 = 런 전체 방향을 바꾸는 큰 규칙"
        post_talisman_context = (
            "선택한 커맨더: 💰 Alchemist - Epic shop and round Terazin\n"
            "부적 = 커맨더를 보조하는 작은 규칙 1개"
        )
        context_rect = {
            "x": 120,
            "y": 160,
            "w": 760,
            "h": 42,
            "visible": True,
        }
        readiness_rect = {
            "x": 760,
            "y": 354,
            "w": 500,
            "h": 96,
            "visible": True,
        }
        build_readiness_text = (
            "FIELD: 0장 체인/전투 참가\n"
            "BENCH: 비어 있음\n"
            "ENEMY: R1 1-3기 · ATK 12-24 HP 80-160\n"
            "Next: SHOP에서 카드를 구매"
        )
        post_build_readiness_text = (
            "FIELD: 0장 체인/전투 참가\n"
            "BENCH: 비어 있음\n"
            "ENEMY: R1 1-3기 · ATK 12-24 HP 80-160\n"
            "Next: SHOP에서 카드를 구매"
        )
        enemy_preview_text = "ENEMY: R1 1-3기 · ATK 12-24 HP 80-160"
        build_layout_rects = {
            "build_readiness_panel": readiness_rect,
            "confirm_button": {
                "x": 540,
                "y": 688,
                "w": 200,
                "h": 30,
                "visible": True,
            },
            "field_container": {
                "x": 20,
                "y": 455,
                "w": 1240,
                "h": 165,
                "visible": True,
            },
        }
        build_card_offer_ids = ["sp_assembly", "sp_workshop", "ne_envoy"]
        build_card_offer_costs = [2, 2, 3]

        def shop_role(slot_idx: int, card_id: str, name: str, role: str) -> dict:
            return {
                "slot_idx": slot_idx,
                "card_id": card_id,
                "name": name,
                "role_text": role,
                "tier_text": f"T1 ★1 · {build_card_offer_costs[slot_idx]}g",
                "visible": True,
                "rect": {
                    "x": 20 + slot_idx * 130,
                    "y": 70,
                    "w": 120,
                    "h": 160,
                    "visible": True,
                },
            }

        def shop_role_summaries() -> list[dict]:
            return [
                shop_role(0, "sp_assembly", "증기 조립소", "시작 · 유닛+"),
                shop_role(1, "sp_workshop", "태엽 공방", "반응 · 강화"),
                shop_role(2, "ne_envoy", "떠돌이 사절단", "시작 · 경제"),
            ]

        def shop_snapshot() -> dict:
            return {
                "shop_label_text": "CARD SHOP Lv1 (R:cards -1g | F:levelup -4g)",
                "upgrade_shop_label_text": "UPGRADES (T:upgrades only)",
                "card_offer_ids": list(build_card_offer_ids),
                "card_offer_costs": list(build_card_offer_costs),
                "card_offer_roles": shop_role_summaries(),
                "upgrade_offer_ids": ["C1", "R1"],
                "upgrade_offer_costs": [1, 2],
            }

        def run_milestone_entry(
            round_label_text: str,
            text: str,
            progress_rail_text: str,
        ) -> dict:
            return {
                "text": text,
                "round_label_text": round_label_text,
                "progress_rail_text": progress_rail_text,
                "visible": True,
                "rect": {
                    "x": 0,
                    "y": 0,
                    "w": 260,
                    "h": 23,
                    "visible": True,
                },
            }

        rail_r1 = "R1 NOW | rewards R4 next, R8, R12 | R15 final"
        rail_r2 = "R2 NOW | rewards R4 next, R8, R12 | R15 final"

        def enemy_preview_entry(text: str) -> dict:
            return {
                "text": text,
                "visible": True,
                "rect": readiness_rect,
                "data": {
                    "round": 1,
                    "difficulty": 1,
                    "boss": False,
                    "exact": False,
                    "preset_count": 4,
                    "enemy_count_min": 1,
                    "enemy_count_max": 3,
                    "enemy_count_avg": 2.0,
                    "total_atk_min": 12.0,
                    "total_atk_max": 24.0,
                    "total_atk_avg": 18.0,
                    "total_hp_min": 80.0,
                    "total_hp_max": 160.0,
                    "total_hp_avg": 120.0,
                    "text": text,
                },
            }

        battle_status_rect = {
            "x": 440,
            "y": 20,
            "w": 410,
            "h": 24,
            "visible": True,
        }
        battle_status_text = (
            "BATTLE R1 | Start 12A vs 2E | Now 12A vs 2E | Tick 0 | 1x"
        )
        battle_status_entry = {
            "text": battle_status_text,
            "visible": True,
            "rect": battle_status_rect,
            "data": {
                "round": 1,
                "ally_start": 12,
                "enemy_start": 2,
                "ally_remaining": 12,
                "enemy_remaining": 2,
                "tick": 0,
                "speed": 1.0,
                "text": battle_status_text,
                "visible": True,
            },
        }

        report = {
            "schema": screenshot_lint.SCHEMA,
            "ok": True,
            "metadata": {
                "commander_type": 1,
                "commander_name": "Gambler",
                "talisman_type": 8,
                "talisman_name": "Flint",
                "unlock_selected": False,
                "preunlocked_selected_commanders": [],
                "preunlocked_selected_talismans": [],
                "screenshot_status": screenshot_status,
                "screenshot_dir": str(self.tmpdir / "shots"),
            },
            "steps": [],
            "events": {
                "run_identity": {
                    "commander_name": "Gambler",
                    "talisman_name": "Flint",
                    "build_entry": {
                        "text": (
                            "Commander: Gambler - reroll 50%, star3 merge refund\n"
                            "Talisman: Flint - first growth x2 ready"
                        ),
                        "visible": True,
                        "rect": {"x": 100, "y": 0, "w": 440, "h": 40, "visible": True},
                    },
                    "during_chain_feedback": {
                        "text": (
                            "Commander: Gambler - reroll 50%, star3 merge refund\n"
                            "Talisman: Flint - first growth x2 used"
                        ),
                        "visible": True,
                        "rect": {"x": 100, "y": 0, "w": 440, "h": 40, "visible": True},
                    },
                    "after_chain_feedback": {
                        "text": (
                            "Commander: Gambler - reroll 50%, star3 merge refund\n"
                            "Talisman: Flint - first growth x2 ready"
                        ),
                        "visible": True,
                        "rect": {"x": 100, "y": 0, "w": 440, "h": 40, "visible": True},
                    },
                },
                "run_milestone": {
                    "build_entry": run_milestone_entry(
                        "Round 1/15 · R4 boss reward in 4 fights\n%s" % rail_r1,
                        "Goal: R4 boss reward in 4 fights",
                        rail_r1,
                    ),
                    "after_chain_feedback": run_milestone_entry(
                        "Round 2/15 · R4 boss reward in 3 fights\n%s" % rail_r2,
                        "Goal: R4 boss reward in 3 fights",
                        rail_r2,
                    ),
                    "post_unlock_build_entry": run_milestone_entry(
                        "Round 1/15 · R4 boss reward in 4 fights\n%s" % rail_r1,
                        "Goal: R4 boss reward in 4 fights",
                        rail_r1,
                    ),
                },
                "run_selection": {
                    "selected_commander": 1,
                    "selected_talisman": 8,
                    "commander_choice_summaries": initial_commander_summaries,
                    "talisman_choice_summaries": initial_talisman_summaries,
                    "selected_commander_summary": initial_commander_summaries[0],
                    "selected_talisman_summary": initial_talisman_summaries[0],
                    "commander_context_text": initial_commander_context,
                    "talisman_context_text": initial_talisman_context,
                },
                "build_readiness": {
                    "build_entry": {
                        "text": build_readiness_text,
                        "visible": True,
                        "rect": readiness_rect,
                    },
                    "post_unlock_build_entry": {
                        "text": post_build_readiness_text,
                        "visible": True,
                        "rect": readiness_rect,
                    },
                },
                "enemy_pressure_preview": {
                    "build_entry": enemy_preview_entry(enemy_preview_text),
                    "post_unlock_build_entry": enemy_preview_entry(
                        enemy_preview_text
                    ),
                },
                "battle_status": {
                    "battle_status_live": battle_status_entry,
                },
                "shop_role_cues": {
                    "build_entry": {
                        "card_offer_ids": list(build_card_offer_ids),
                        "card_offer_roles": shop_role_summaries(),
                    },
                    "post_unlock_build_entry": {
                        "card_offer_ids": list(build_card_offer_ids),
                        "card_offer_roles": shop_role_summaries(),
                    },
                },
                "chain_feedback": {
                    "counter_text": "Triggers: 2",
                    "event_log_text": (
                        "#1 Round Start: A -> B +Unit\n"
                        "#2 Cascade: B -> B +Stats\n"
                        "Complete: 2 triggers, no gold"
                    ),
                    "last_history_display_text": (
                        "2 triggers\n#1 A -> B +Unit\n#2 B -> B +Stats"
                    ),
                },
                "settlement_recap": {
                    "visible": True,
                    "text": (
                        "LAST SETTLEMENT R1\n"
                        "Gold: 11 -> 16 (+5; +5 income, +0 interest)\n"
                        "Terazin: 0 -> 2 (+2; +2 round)\n"
                        "Next: R2 BUILD · R4 boss reward in 3 fights"
                    ),
                    "data": {
                        "round": 1,
                        "next_round": 2,
                        "gold_before": 11,
                        "gold_after": 16,
                        "gold_delta": 5,
                        "base_income": 5,
                        "interest": 0,
                        "interest_basis_gold": 10,
                        "terazin_before": 0,
                        "terazin_after": 2,
                        "terazin_delta": 2,
                        "terazin_gain": 2,
                        "commander_terazin": 0,
                    },
                },
                "merge_reward": {
                    "attached": True,
                    "selected_upgrade": "R6",
                    "survivor_card_id": "sp_assembly",
                    "survivor_star": 2,
                    "gold_before_purchase": 10,
                    "purchase_cost": 2,
                    "expected_merge_refund": 0,
                    "gold_after_merge": 8,
                    "expected_gold_after_merge": 8,
                    "merge_history_visible": True,
                    "merge_history_text": (
                        "MERGE: Steam Assembly ★1 -> ★2 · free Rare upgrade"
                    ),
                    "merge_history_entries": [
                        "MERGE: Steam Assembly ★1 -> ★2 · free Rare upgrade"
                    ],
                },
                "shop_reroll_scope": {
                    "labels": {
                        "shop_label_text": (
                            "CARD SHOP Lv1 (R:cards -1g | F:levelup -4g)"
                        ),
                        "upgrade_shop_label_text": "UPGRADES (T:upgrades only)",
                        "upgrade_reroll_button_text": "UPG REROLL (T) -1T",
                    },
                    "card_reroll": {
                        "attempts": 1,
                        "gold_before": 30,
                        "gold_after": 29,
                        "before_card_offer_ids": [
                            "sp_assembly",
                            "sp_workshop",
                            "sp_foundry",
                        ],
                        "after_card_offer_ids": [
                            "ne_recruiter",
                            "sp_workshop",
                            "ne_blacksmith",
                        ],
                        "before_upgrade_offer_ids": ["C1", "R1"],
                        "after_upgrade_offer_ids": ["C1", "R1"],
                        "cards_changed": True,
                        "upgrades_preserved": True,
                    },
                    "upgrade_reroll": {
                        "attempts": 1,
                        "terazin_before": 10,
                        "terazin_after": 9,
                        "before_card_offer_ids": [
                            "ne_recruiter",
                            "sp_workshop",
                            "ne_blacksmith",
                        ],
                        "after_card_offer_ids": [
                            "ne_recruiter",
                            "sp_workshop",
                            "ne_blacksmith",
                        ],
                        "before_upgrade_offer_ids": ["C1", "R1"],
                        "after_upgrade_offer_ids": ["C2", "R2"],
                        "cards_preserved": True,
                        "upgrades_changed": True,
                    },
                },
                "boss_reward": {
                    "selected_reward": "r4_4",
                    "open_title": "Boss Reward (choose 1 / 2 choices)",
                    "open_choice_count": 2,
                    "phase_after": "BUILD",
                    "round_after": 5,
                    "open_choice_summaries": [
                        {
                            "id": "r4_2",
                            "idx": 0,
                            "name": "Emergency Funds",
                            "type": "Instant",
                            "desc": "+12 gold",
                            "text": "Emergency Funds\nInstant\n+12 gold",
                            "needs_target": False,
                        },
                        {
                            "id": "r4_4",
                            "idx": 1,
                            "name": "Shop Expansion",
                            "type": "Structure",
                            "desc": "Shop slot +1",
                            "text": "Shop Expansion\nStructure\nShop slot +1",
                            "needs_target": False,
                        },
                    ],
                    "selected_choice_summary": {
                        "id": "r4_4",
                        "idx": 1,
                        "name": "Shop Expansion",
                        "type": "Structure",
                        "desc": "Shop slot +1",
                        "text": "Shop Expansion\nStructure\nShop slot +1",
                        "needs_target": False,
                    },
                },
                "targeted_boss_reward": {
                    "selected_reward": "r4_1",
                    "selected_field_idx": 0,
                    "target_star_before": 1,
                    "target_star_after": 2,
                    "terazin_delta_after_settlement": 6,
                    "open_choice_summaries": [
                        {
                            "id": "r4_1",
                            "idx": 0,
                            "name": "Emergency Supply",
                            "type": "Instant",
                            "desc": "Choose a card: star up + 4 Terazin",
                            "text": (
                                "Emergency Supply\nInstant\n"
                                "Choose a card: star up + 4 Terazin"
                            ),
                            "needs_target": True,
                        },
                    ],
                },
                "unlock_recap": {
                    "title_text": "VICTORY!",
                    "summary_text": (
                        "All 15 rounds cleared!\n"
                        "HP remaining: 7\n\n"
                        "New unlocks available\n"
                        "- 커맨더: 전략가\n"
                        "- 커맨더: 단조사\n"
                        "- 커맨더: 수집가\n"
                        "+9 more unlocked - all available in PROGRESS"
                    ),
                    "raw_unlocks": [
                        "커맨더: 전략가",
                        "커맨더: 단조사",
                        "커맨더: 수집가",
                        "커맨더: 약탈자",
                        "커맨더: 연금술사",
                        "부적: 수은 방울",
                        "부적: 깨진 알",
                        "부적: 전쟁 북",
                        "부적: 녹슨 렌치",
                        "부적: 터진 자루",
                        "부적: 영혼 항아리",
                        "난이도 2",
                    ],
                    "shown_unlocks": [
                        "커맨더: 전략가",
                        "커맨더: 단조사",
                        "커맨더: 수집가",
                    ],
                    "shown_count": 3,
                    "overflow_count": 9,
                    "raw_unlock_count": 12,
                    "run_stats_source": "synthetic_overflow_fixture",
                    "run_stats_note": (
                        "Scripted full-clear stats used only to verify capped "
                        "unlock recap and overflow availability."
                    ),
                    "run_stats": {
                        "max_field_units": 120,
                        "max_attached_upgrades": 16,
                        "max_unique_field_cards": 7,
                        "best_win_streak": 8,
                        "cards_sold": 20,
                        "growth_events": 120,
                        "max_star2_cards": 5,
                        "unit_advantage_win": True,
                        "unit_advantage_wins": 5,
                    },
                },
                "post_unlock_progress": {
                    "recent_unlocks_text": (
                        "최근 해금\n"
                        "- 커맨더: 전략가\n"
                        "- 커맨더: 단조사\n"
                        "- 커맨더: 수집가\n"
                        "+9 more unlocked - all available in PROGRESS"
                    ),
                    "unlocks_text": (
                        "Commanders: 도박꾼, 양성가, 전략가, 단조사, "
                        "수집가, 약탈자, 연금술사\n"
                        "Talismans: 부싯돌, 양면 동전, 금간 해골, 수은 방울, "
                        "깨진 알, 전쟁 북, 녹슨 렌치, 터진 자루, 영혼 항아리"
                    ),
                    "difficulty_text": "Difficulty 1 / 2",
                    "details_text": (
                        "진행 상세\n"
                        "난이도 2/8 해금\n\n"
                        "커맨더 7/7\n"
                        "- 연금술사: 해금 (한 런 카드 20장 판매)\n\n"
                        "부적 9/12\n"
                        "- 영혼 항아리: 해금 (한 런 카드 12장 판매)\n\n"
                        "완료 업적\n"
                        "- 한 런 카드 20장 판매"
                    ),
                    "details_visible": True,
                },
                "post_unlock_availability": {
                    "selected_commander": 7,
                    "selected_talisman": 11,
                    "commander_choices": ["1", "2", "3", "4", "5", "6", "7"],
                    "talisman_choices": ["3", "7", "8", "9", "10", "11"],
                    "commander_choice_summaries": post_commander_summaries,
                    "talisman_choice_summaries": post_talisman_summaries,
                    "selected_commander_summary": post_commander_summaries[6],
                    "selected_talisman_summary": post_talisman_summaries[5],
                    "commander_context_text": post_commander_context,
                    "talisman_context_text": post_talisman_context,
                    "identity_text_after": (
                        "Commander: Alchemist - Epic shop and round Terazin\n"
                        "Talisman: Soul Jar - first sell ready"
                    ),
                    "phase_after": "BUILD",
                    "round_after": 1,
                    "has_modal_after": False,
                },
            },
            "screenshots": [],
            "errors": [],
            "final": {
                "phase": "BUILD",
                "round": 1,
                "has_modal": False,
                "chain_visible": False,
                "active_modals": [],
                "identity": {
                    "text": (
                        "Commander: Alchemist - Epic shop and round Terazin\n"
                        "Talisman: Soul Jar - first sell ready"
                    )
                },
            },
        }
        for label in screenshot_lint.EXPECTED_SCREENSHOT_LABELS[:-1]:
            step = {
                "label": label,
                "phase": "BUILD",
                "round": 1,
                "has_modal": False,
                "active_modals": [],
            }
            if label == "after_run_start":
                step.update(
                    {
                        "active_modals": ["commander_select"],
                        "has_modal": True,
                        "choices": {"commander_select": ["1", "2"]},
                        "actionable": {"commander_select": True},
                        "commander_select": {
                            "choice_summaries": initial_commander_summaries,
                            "context_text": initial_commander_context,
                            "context_rect": context_rect,
                        },
                    }
                )
            elif label == "after_commander":
                step.update(
                    {
                        "active_modals": ["talisman_select"],
                        "has_modal": True,
                        "choices": {"talisman_select": ["8", "5", "9"]},
                        "actionable": {"talisman_select": True},
                        "talisman_select": {
                            "choice_summaries": initial_talisman_summaries,
                            "context_text": initial_talisman_context,
                            "context_rect": context_rect,
                        },
                    }
                )
            elif label == "chain_feedback_open":
                step.update(
                    {
                        "phase": "CHAIN",
                        "chain_visible": True,
                        "chain_feedback": {
                            "counter_text": "Triggers: 2",
                            "event_log_text": report["events"]["chain_feedback"][
                                "event_log_text"
                            ],
                            "event_panel_visible": True,
                        },
                    }
                )
            elif label == "battle_status_live":
                step.update(
                    {
                        "phase": "BATTLE",
                        "battle_status": battle_status_entry,
                        "layout_rects": {"battle_status": battle_status_rect},
                    }
                )
            elif label == "battle_result_open":
                step.update(
                    {
                        "phase": "BATTLE",
                        "active_modals": ["battle_result"],
                        "battle_result_visible": True,
                        "battle_result": {
                            "result_text": "VICTORY",
                            "detail_text": (
                                "Round 1 cleared\n"
                                "Allies: 1/2 survived; enemies cleared\n"
                                "HP: 30 -> 30 (+0)\n"
                                "Gold: 10 -> 11 (+1 win, +0 cards)\n"
                                "Next: return to BUILD after income"
                            ),
                            "summary_text": "Next: return to BUILD after income",
                            "context": {},
                        },
                    }
                )
            elif label == "boss_reward_open":
                step.update(
                    {
                        "phase": "BATTLE",
                        "active_modals": ["boss_reward"],
                        "choices": {"boss_reward": ["r4_2", "r4_4"]},
                        "actionable": {"boss_reward": True},
                        "boss_reward": {
                            "title": "Boss Reward",
                            "choice_summaries": report["events"]["boss_reward"][
                                "open_choice_summaries"
                            ],
                        },
                    }
                )
            elif label == "chain_feedback_last_history":
                step.update(
                    {
                        "round": 2,
                        "chain_visible": False,
                        "last_chain_history": {
                            "visible": True,
                            "text": report["events"]["chain_feedback"][
                                "event_log_text"
                            ],
                            "display_text": report["events"]["chain_feedback"][
                                "last_history_display_text"
                            ],
                        },
                        "last_settlement_recap": report["events"][
                            "settlement_recap"
                        ],
                        "run_milestone": report["events"]["run_milestone"][
                            "after_chain_feedback"
                        ],
                    }
                )
            elif label == "targeted_boss_reward_open":
                step.update(
                    {
                        "phase": "BATTLE",
                        "active_modals": ["boss_reward"],
                        "choices": {"boss_reward": ["r4_1"]},
                        "actionable": {"boss_reward": True},
                        "boss_reward": {
                            "title": "Boss Reward",
                            "choice_summaries": report["events"][
                                "targeted_boss_reward"
                            ]["open_choice_summaries"],
                        },
                    }
                )
            elif label == "targeted_boss_reward_target_open":
                step.update(
                    {
                        "active_modals": ["target_select"],
                        "target_select": {
                            "instruction": "r4_1 choose target card",
                            "detail": "select one card",
                            "preview_texts": ["star1 -> star2", "MAX star3"],
                        },
                    }
                )
            elif label == "unlock_game_over_open":
                step.update(
                    {
                        "phase": "SETTLEMENT",
                        "round": 16,
                        "active_modals": ["game_over"],
                        "has_modal": True,
                        "game_over_visible": True,
                        "game_over": {
                            "title_text": report["events"]["unlock_recap"][
                                "title_text"
                            ],
                            "summary_text": report["events"]["unlock_recap"][
                                "summary_text"
                            ],
                        },
                    }
                )
            elif label in ("post_unlock_run_start", "post_unlock_progress_details"):
                step.update(
                    {
                        "active_modals": ["run_start"],
                        "has_modal": True,
                        "run_start": {
                            "recent_unlocks_text": report["events"][
                                "post_unlock_progress"
                            ]["recent_unlocks_text"],
                            "unlocks_text": report["events"][
                                "post_unlock_progress"
                            ]["unlocks_text"],
                            "difficulty_text": report["events"][
                                "post_unlock_progress"
                            ]["difficulty_text"],
                            "details_text": report["events"][
                                "post_unlock_progress"
                            ]["details_text"],
                            "details_visible": label == "post_unlock_progress_details",
                        },
                    }
                )
            elif label == "post_unlock_commander_select":
                step.update(
                    {
                        "active_modals": ["commander_select"],
                        "has_modal": True,
                        "choices": {
                            "commander_select": report["events"][
                                "post_unlock_availability"
                            ]["commander_choices"]
                        },
                        "actionable": {"commander_select": True},
                        "commander_select": {
                            "choice_summaries": post_commander_summaries,
                            "context_text": post_commander_context,
                            "context_rect": context_rect,
                        },
                    }
                )
            elif label == "post_unlock_talisman_select":
                step.update(
                    {
                        "active_modals": ["talisman_select"],
                        "has_modal": True,
                        "choices": {
                            "talisman_select": report["events"][
                                "post_unlock_availability"
                            ]["talisman_choices"]
                        },
                        "actionable": {"talisman_select": True},
                        "talisman_select": {
                            "choice_summaries": post_talisman_summaries,
                            "context_text": post_talisman_context,
                            "context_rect": context_rect,
                        },
                    }
                )
            elif label == "post_unlock_build_entry":
                step.update(
                    {
                        "round": 1,
                        "has_modal": False,
                        "active_modals": [],
                        "shop": shop_snapshot(),
                        "build_readiness": report["events"]["build_readiness"][
                            "post_unlock_build_entry"
                        ],
                        "run_milestone": report["events"]["run_milestone"][
                            "post_unlock_build_entry"
                        ],
                        "enemy_pressure_preview": report["events"][
                            "enemy_pressure_preview"
                        ]["post_unlock_build_entry"],
                        "layout_rects": build_layout_rects,
                    }
                )
            elif label == "build_entry":
                step.update(
                    {
                        "shop": shop_snapshot(),
                        "build_readiness": report["events"]["build_readiness"][
                            "build_entry"
                        ],
                        "run_milestone": report["events"]["run_milestone"][
                            "build_entry"
                        ],
                        "enemy_pressure_preview": report["events"][
                            "enemy_pressure_preview"
                        ]["build_entry"],
                        "layout_rects": build_layout_rects,
                    }
                )
            report["steps"].append(step)
        return report

    def test_summary_mentions_core_flow(self) -> None:
        result = summary.summarize_report(self._write_report(self._valid_report()))

        self.assertTrue(result.ok)
        self.assertIn("Verdict: PASS", result.markdown)
        self.assertIn("Commander: Gambler", result.markdown)
        self.assertIn("Selected identity setup: normal profile", result.markdown)
        self.assertIn("Run identity rendered", result.markdown)
        self.assertIn("first growth x2 used", result.markdown)
        self.assertIn("BUILD readiness cue", result.markdown)
        self.assertIn("SHOP에서 카드를 구매", result.markdown)
        self.assertIn("Enemy pressure preview rendered before commit", result.markdown)
        self.assertIn("ENEMY: R1", result.markdown)
        self.assertIn("First-shop role cues rendered", result.markdown)
        self.assertIn("증기 조립소=시작 · 유닛+", result.markdown)
        self.assertIn("Choice context before BUILD", result.markdown)
        self.assertIn("선택한 커맨더", result.markdown)
        self.assertIn("Selection cards rendered before BUILD", result.markdown)
        self.assertIn("Gambler: 50% free rerolls", result.markdown)
        self.assertIn("Run milestone rendered", result.markdown)
        self.assertIn("Run progression rail rendered", result.markdown)
        self.assertIn("R4 boss reward in 3 fights", result.markdown)
        self.assertIn("Post-unlock selection cards rendered", result.markdown)
        self.assertIn("Alchemist: Epic shop", result.markdown)
        self.assertIn("Chain feedback paused", result.markdown)
        self.assertIn("Battle start status rendered", result.markdown)
        self.assertIn("BATTLE R1", result.markdown)
        self.assertIn("Battle aftermath popup explained", result.markdown)
        self.assertIn("Settlement recap displayed", result.markdown)
        self.assertIn("Shop reroll scope held", result.markdown)
        self.assertIn("Boss reward choices rendered", result.markdown)
        self.assertIn("merge history visible yes", result.markdown)
        self.assertIn("+0g merge refund", result.markdown)
        self.assertIn("Shop Expansion", result.markdown)
        self.assertIn("Targeted boss reward choice rendered", result.markdown)
        self.assertIn("base_income=5", result.markdown)
        self.assertIn("Triggers: 2", result.markdown)
        self.assertIn("sp_assembly", result.markdown)
        self.assertIn("r4_1", result.markdown)
        self.assertIn(
            "Run-end unlock recap used synthetic_overflow_fixture stats; "
            "showed 3/12",
            result.markdown,
        )
        self.assertIn("Overflow availability was actionable", result.markdown)
        self.assertIn("Final state: BUILD R1", result.markdown)

    def test_optional_commander_free_upgrade_event_is_summarized(self) -> None:
        report = self._valid_report()
        report["events"]["commander_free_upgrade"] = {
            "smith_start_upgrade": {
                "selected_upgrade": "C1",
                "selected_field_idx": 0,
                "instruction": "Smith bonus: attach Reinforced Alloy",
                "phase_after": "BUILD",
                "round_after": 1,
            }
        }

        result = summary.summarize_report(self._write_report(report))

        self.assertTrue(result.ok)
        self.assertIn("Commander free upgrade flow resolved", result.markdown)
        self.assertIn("smith_start_upgrade: C1 -> field 0", result.markdown)
        self.assertIn("Smith bonus", result.markdown)

    def test_invalid_commander_free_upgrade_event_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"]["commander_free_upgrade"] = {
            "raider_terminal_upgrade": {
                "selected_upgrade": "",
                "selected_field_idx": -1,
                "instruction": "",
                "phase_after": "INIT",
                "round_after": 0,
            }
        }

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(
            any("commander_free_upgrade.raider_terminal_upgrade" in error
                for error in result.errors)
        )

    def test_raider_reward_event_on_non_raider_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"]["raider_win_streak_reward"] = {
            "selected_upgrade": "C1",
            "selected_field_idx": 0,
            "instruction": "Raider 3-win reward: attach Reinforced Alloy",
            "target_upgrade_count_before": 0,
            "target_upgrade_count_after": 1,
            "win_count_after": 0,
            "phase_after": "BUILD",
            "round_after": 3,
            "has_modal_after": False,
        }

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(
            any("only expected for Raider" in error for error in result.errors)
        )

    def test_raider_reward_validator_requires_event_for_raider(self) -> None:
        errors: list[str] = []

        summary._validate_raider_win_streak_reward({}, 6, "Raider", errors)

        self.assertIn(
            "events.raider_win_streak_reward is required for Raider reports",
            errors,
        )

    def test_raider_reward_validator_accepts_live_reward_shape(self) -> None:
        errors: list[str] = []

        summary._validate_raider_win_streak_reward(
            {
                "selected_upgrade": "C1",
                "selected_field_idx": 0,
                "instruction": "Raider 3-win reward: attach Reinforced Alloy",
                "target_upgrade_count_before": 0,
                "target_upgrade_count_after": 1,
                "win_count_after": 0,
                "phase_after": "BUILD",
                "round_after": 3,
                "has_modal_after": False,
            },
            6,
            "Raider",
            errors,
        )

        self.assertEqual(errors, [])

    def test_missing_expected_step_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["steps"] = [
            step for step in report["steps"] if step["label"] != "merge_reward_open"
        ]

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("step labels" in error for error in result.errors))
        self.assertIn("Verdict: INCOMPLETE", result.markdown)

    def test_missing_merge_history_marks_incomplete(self) -> None:
        report = self._valid_report()
        merge_event = report["events"]["merge_reward"]
        merge_event["merge_history_visible"] = False
        merge_event["merge_history_text"] = ""
        merge_event["merge_history_entries"] = []

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("merge_history" in error for error in result.errors))

    def test_missing_run_identity_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"].pop("run_identity")

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("run_identity" in error for error in result.errors))

    def test_missing_run_milestone_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"]["run_milestone"]["after_chain_feedback"]["text"] = ""
        report["events"]["run_milestone"]["after_chain_feedback"]["round_label_text"] = ""
        report["events"]["run_milestone"]["after_chain_feedback"]["progress_rail_text"] = ""
        step = next(
            step for step in report["steps"] if step["label"] == "chain_feedback_last_history"
        )
        step["run_milestone"]["text"] = ""
        step["run_milestone"]["round_label_text"] = ""
        step["run_milestone"]["progress_rail_text"] = ""

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("run_milestone" in error for error in result.errors))

    def test_missing_run_progress_rail_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"]["run_milestone"]["build_entry"]["progress_rail_text"] = ""
        step = next(step for step in report["steps"] if step["label"] == "build_entry")
        step["run_milestone"]["progress_rail_text"] = ""

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("progress_rail_text" in error for error in result.errors))

    def test_run_identity_shorthand_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"]["run_identity"]["build_entry"]["text"] = (
            "Commander: Gambler\nC: reroll 50%\nTalisman: Flint\nT: ready"
        )

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("C:/T:" in error for error in result.errors))

    def test_missing_run_selection_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"].pop("run_selection")

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("run_selection" in error for error in result.errors))

    def test_blank_commander_selection_desc_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"]["run_selection"]["commander_choice_summaries"][0]["desc"] = ""
        report["steps"][1]["commander_select"]["choice_summaries"][0]["desc"] = ""

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("commander_select" in error for error in result.errors))

    def test_missing_talisman_selection_context_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"]["run_selection"]["talisman_context_text"] = ""
        report["steps"][2]["talisman_select"]["context_text"] = ""

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("talisman_select" in error for error in result.errors))

    def test_missing_build_readiness_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"]["build_readiness"]["build_entry"]["text"] = ""
        report["events"]["build_readiness"]["build_entry"]["visible"] = False
        step = next(step for step in report["steps"] if step["label"] == "build_entry")
        step["build_readiness"]["text"] = ""
        step["build_readiness"]["visible"] = False

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("build_readiness" in error for error in result.errors))

    def test_missing_enemy_pressure_preview_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"]["enemy_pressure_preview"]["build_entry"]["text"] = ""
        report["events"]["enemy_pressure_preview"]["build_entry"]["visible"] = False
        report["events"]["enemy_pressure_preview"]["build_entry"]["data"]["exact"] = True
        step = next(step for step in report["steps"] if step["label"] == "build_entry")
        step["enemy_pressure_preview"]["text"] = ""
        step["enemy_pressure_preview"]["visible"] = False
        step["enemy_pressure_preview"]["data"]["exact"] = True

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("enemy_pressure_preview" in error for error in result.errors))

    def test_missing_shop_role_cue_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"]["shop_role_cues"]["build_entry"]["card_offer_roles"][0][
            "role_text"
        ] = ""
        step = next(step for step in report["steps"] if step["label"] == "build_entry")
        step["shop"]["card_offer_roles"][0]["role_text"] = ""

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("shop role" in error for error in result.errors))

    def test_unexpected_star2_merge_refund_marks_incomplete(self) -> None:
        report = self._valid_report()
        merge_event = report["events"]["merge_reward"]
        merge_event["expected_merge_refund"] = 3
        merge_event["gold_after_merge"] = 11

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("expected_merge_refund" in error for error in result.errors))

    def test_report_not_ok_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["ok"] = False

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("report ok" in error for error in result.errors))

    def test_require_screenshots_without_enabled_status_fails(self) -> None:
        result = summary.summarize_report(
            self._write_report(self._valid_report()),
            require_screenshots=True,
        )

        self.assertFalse(result.ok)
        self.assertTrue(any("screenshots are required" in error for error in result.errors))

    def test_enabled_screenshots_without_lint_warns(self) -> None:
        report = self._valid_report(screenshot_status="enabled")
        report["screenshots"] = [
            {"label": label, "path": f"/tmp/{label}.png", "width": 1280, "height": 720}
            for label in screenshot_lint.EXPECTED_SCREENSHOT_LABELS
        ]

        result = summary.summarize_report(self._write_report(report))

        self.assertTrue(result.ok)
        self.assertTrue(any("screenshot lint was not run" in item for item in result.warnings))
        self.assertIn("Screenshot lint: NOT RUN", result.markdown)

    def test_lint_screenshot_failure_marks_incomplete(self) -> None:
        report = self._valid_report(screenshot_status="enabled")
        report["screenshots"] = [
            {"label": label, "path": f"/tmp/{label}.png", "width": 1280, "height": 720}
            for label in screenshot_lint.EXPECTED_SCREENSHOT_LABELS
        ]

        result = summary.summarize_report(
            self._write_report(report),
            lint_screenshots=True,
        )

        self.assertFalse(result.ok)
        self.assertTrue(any(error.startswith("screenshot lint:") for error in result.errors))

    def test_battle_aftermath_without_next_hint_marks_incomplete(self) -> None:
        report = self._valid_report()
        battle_step = next(
            step for step in report["steps"] if step["label"] == "battle_result_open"
        )
        battle_step["battle_result"]["detail_text"] = (
            "Round 1 cleared\nHP: 30 -> 30 (+0)\nGold: 10 -> 11 (+1 win, +0 cards)"
        )

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("next-step" in error for error in result.errors))

    def test_missing_battle_status_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"]["battle_status"]["battle_status_live"]["visible"] = False
        report["events"]["battle_status"]["battle_status_live"]["text"] = ""
        battle_step = next(
            step for step in report["steps"] if step["label"] == "battle_status_live"
        )
        battle_step["battle_status"]["visible"] = False
        battle_step["battle_status"]["text"] = ""
        battle_step["battle_status"]["rect"]["visible"] = False

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("battle_status" in error for error in result.errors))

    def test_settlement_recap_without_interest_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"]["settlement_recap"]["text"] = (
            "LAST SETTLEMENT R1\n"
            "Gold: 11 -> 16 (+5 income)\n"
            "Terazin: 0 -> 2 (+2 round)\n"
            "Next: R2 BUILD · R4 boss reward in 3 fights"
        )
        del report["events"]["settlement_recap"]["data"]["interest"]

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("settlement_recap.text" in error for error in result.errors))
        self.assertTrue(any("settlement_recap.data" in error for error in result.errors))

    def test_boss_reward_without_rendered_desc_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"]["boss_reward"]["open_choice_summaries"][0]["desc"] = ""
        boss_step = next(
            step for step in report["steps"] if step["label"] == "boss_reward_open"
        )
        boss_step["boss_reward"]["choice_summaries"][0]["desc"] = ""

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("missing rendered desc" in error for error in result.errors))

    def test_boss_reward_choice_count_mismatch_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"]["boss_reward"]["open_choice_count"] = 6

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("open_choice_count" in error for error in result.errors))

    def test_targeted_boss_reward_without_target_marker_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"]["targeted_boss_reward"]["open_choice_summaries"][0][
            "needs_target"
        ] = False
        targeted_step = next(
            step for step in report["steps"] if step["label"] == "targeted_boss_reward_open"
        )
        targeted_step["boss_reward"]["choice_summaries"][0]["needs_target"] = False

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("targeted reward summary" in error for error in result.errors))

    def test_missing_unlock_recap_marks_incomplete(self) -> None:
        report = self._valid_report()
        del report["events"]["unlock_recap"]

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("unlock_recap" in error for error in result.errors))

    def test_unlock_recap_raw_count_mismatch_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"]["unlock_recap"]["raw_unlock_count"] = 99

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("raw_unlock_count" in error for error in result.errors))

    def test_unlock_recap_without_stats_source_marks_incomplete(self) -> None:
        report = self._valid_report()
        del report["events"]["unlock_recap"]["run_stats_source"]

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("run_stats_source" in error for error in result.errors))

    def test_missing_shop_reroll_scope_marks_incomplete(self) -> None:
        report = self._valid_report()
        del report["events"]["shop_reroll_scope"]

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("shop_reroll_scope" in error for error in result.errors))

    def test_card_reroll_touching_upgrade_offers_marks_incomplete(self) -> None:
        report = self._valid_report()
        event = report["events"]["shop_reroll_scope"]["card_reroll"]
        event["after_upgrade_offer_ids"] = ["C2", "R2"]
        event["upgrades_preserved"] = False

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(
            any("upgrades_preserved" in error for error in result.errors)
        )

    def test_upgrade_reroll_touching_card_offers_marks_incomplete(self) -> None:
        report = self._valid_report()
        event = report["events"]["shop_reroll_scope"]["upgrade_reroll"]
        event["after_card_offer_ids"] = ["sp_assembly", "sp_workshop", "sp_foundry"]
        event["cards_preserved"] = False

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("cards_preserved" in error for error in result.errors))

    def test_missing_overflow_availability_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["events"]["post_unlock_availability"]["talisman_choices"] = ["3", "7"]

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertTrue(any("Soul Jar" in error for error in result.errors))


if __name__ == "__main__":
    unittest.main()
