from __future__ import annotations

import copy
import json
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import lint_live_ui_screenshots as lint  # noqa: E402


def _png_chunk(chunk_type: bytes, payload: bytes) -> bytes:
    crc = zlib.crc32(chunk_type)
    crc = zlib.crc32(payload, crc)
    return struct.pack(">I", len(payload)) + chunk_type + payload + struct.pack(">I", crc)


def _write_png(path: Path, width: int, height: int, blank: bool = False) -> None:
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            if blank:
                rows.extend((64, 64, 64, 255))
            else:
                rows.extend(((x * 31) % 256, (y * 47) % 256, ((x + y) * 59) % 256, 255))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    path.write_bytes(
        lint.PNG_SIGNATURE
        + _png_chunk(b"IHDR", ihdr)
        + _png_chunk(b"IDAT", zlib.compress(bytes(rows)))
        + _png_chunk(b"IEND", b"")
    )


class LiveUiScreenshotLintTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self._tmp.name)
        self.report_path = self.tmpdir / "report.json"

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _write_report(self, report: dict) -> Path:
        self.report_path.write_text(json.dumps(report), encoding="utf-8")
        return self.report_path

    def _valid_report(self, width: int = 4, height: int = 3) -> dict:
        report = {
            "schema": lint.SCHEMA,
            "ok": True,
            "metadata": {
                "screenshot_status": "enabled",
                "screenshot_dir": str(self.tmpdir),
            },
            "steps": [],
            "events": {},
            "screenshots": [],
            "final": {},
            "errors": [],
        }
        for idx, label in enumerate(lint.EXPECTED_SCREENSHOT_LABELS, start=1):
            path = self.tmpdir / f"{idx:03d}-{lint._safe_filename(label)}.png"
            _write_png(path, width, height)
            record = {
                "label": label,
                "path": str(path),
                "width": width,
                "height": height,
            }
            report["screenshots"].append(record)
            if label == "final":
                report["final"] = {"screenshot": copy.deepcopy(record)}
            else:
                step = {
                    "label": label,
                    "active_modals": [],
                    "choices": {},
                    "actionable": {},
                    "target_select": {},
                    "layout_rects": {},
                    "screenshot": copy.deepcopy(record),
                }
                if label == lint.TARGET_FRAME_LABEL:
                    step.update(
                        {
                            "active_modals": ["target_select"],
                            "choices": {"target_select": [0]},
                            "actionable": {"target_select": True},
                            "target_select": {
                                "instruction": "r4_1 choose target card",
                                "detail": "select one card",
                                "preview_texts": [
                                    "\u26051 -> \u26052",
                                    "MAX \u26053",
                                ],
                            },
                            "layout_rects": {
                                "target_instruction": {
                                    "x": 420,
                                    "y": 390,
                                    "w": 320,
                                    "h": 24,
                                    "visible": True,
                                },
                                "target_detail": {
                                    "x": 420,
                                    "y": 334,
                                    "w": 320,
                                    "h": 54,
                                    "visible": True,
                                },
                                "confirm_button": {
                                    "x": 540,
                                    "y": 688,
                                    "w": 200,
                                    "h": 30,
                                    "visible": True,
                                },
                                "tutorial_panel": {
                                    "x": 760,
                                    "y": 240,
                                    "w": 500,
                                    "h": 110,
                                    "visible": True,
                                },
                            },
                        }
                    )
                elif label == lint.CHAIN_FRAME_LABEL:
                    step.update(
                        {
                            "phase": "CHAIN",
                            "active_modals": [],
                            "chain_visible": True,
                            "chain_feedback": {
                                "counter_text": "Triggers: 2",
                                "event_log_text": (
                                    "#1 Round Start: A -> B +Unit\n"
                                    "Complete: 2 triggers, no gold"
                                ),
                                "event_panel_visible": True,
                            },
                            "layout_rects": {
                                "chain_counter": {
                                    "x": 20,
                                    "y": 20,
                                    "w": 200,
                                    "h": 24,
                                    "visible": True,
                                },
                                "hp_label": {
                                    "x": 590,
                                    "y": 10,
                                    "w": 60,
                                    "h": 24,
                                    "visible": True,
                                },
                                "gold_label": {
                                    "x": 870,
                                    "y": 10,
                                    "w": 110,
                                    "h": 24,
                                    "visible": True,
                                },
                                "terazin_label": {
                                    "x": 1180,
                                    "y": 10,
                                    "w": 90,
                                    "h": 24,
                                    "visible": True,
                                },
                                "chain_event_panel": {
                                    "x": 20,
                                    "y": 48,
                                    "w": 420,
                                    "h": 120,
                                    "visible": True,
                                },
                            },
                        }
                    )
                elif label == lint.BATTLE_RESULT_FRAME_LABEL:
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
                                "context": {
                                    "round": 1,
                                    "hp_before": 30,
                                    "hp_after": 30,
                                    "gold_before": 10,
                                    "gold_after": 11,
                                },
                            },
                            "layout_rects": {
                                "battle_result_popup": {
                                    "x": 0,
                                    "y": 0,
                                    "w": 1280,
                                    "h": 720,
                                    "visible": True,
                                },
                            },
                        }
                    )
                elif label == lint.BOSS_REWARD_FRAME_LABEL:
                    step.update(
                        {
                            "phase": "BATTLE",
                            "active_modals": ["boss_reward"],
                            "choices": {"boss_reward": ["r4_2", "r4_4"]},
                            "actionable": {"boss_reward": True},
                            "boss_reward": {
                                "title": "보스 보상 선택 (1개)",
                                "choice_summaries": [
                                    {
                                        "id": "r4_2",
                                        "idx": 0,
                                        "name": "긴급 자금",
                                        "type": "즉시",
                                        "desc": "+12 골드",
                                        "text": "긴급 자금\n즉시\n+12 골드",
                                        "needs_target": False,
                                        "rect": {
                                            "x": 300,
                                            "y": 250,
                                            "w": 180,
                                            "h": 200,
                                            "visible": True,
                                        },
                                    },
                                    {
                                        "id": "r4_4",
                                        "idx": 1,
                                        "name": "상점 확장",
                                        "type": "구조",
                                        "desc": "상점 칸 +1",
                                        "text": "상점 확장\n구조\n상점 칸 +1",
                                        "needs_target": False,
                                        "rect": {
                                            "x": 500,
                                            "y": 250,
                                            "w": 180,
                                            "h": 200,
                                            "visible": True,
                                        },
                                    },
                                ],
                            },
                            "layout_rects": {
                                "boss_reward_popup": {
                                    "x": 0,
                                    "y": 0,
                                    "w": 1280,
                                    "h": 720,
                                    "visible": True,
                                },
                            },
                        }
                    )
                elif label == lint.TARGETED_BOSS_REWARD_FRAME_LABEL:
                    step.update(
                        {
                            "phase": "BATTLE",
                            "active_modals": ["boss_reward"],
                            "choices": {"boss_reward": ["r4_1"]},
                            "actionable": {"boss_reward": True},
                            "boss_reward": {
                                "title": "보스 보상 선택 (1개)",
                                "choice_summaries": [
                                    {
                                        "id": "r4_1",
                                        "idx": 0,
                                        "name": "긴급 보급",
                                        "type": "즉시",
                                        "desc": "카드 1장 ★승급 + 4 테라진",
                                        "text": (
                                            "긴급 보급\n즉시\n"
                                            "카드 1장 ★승급 + 4 테라진"
                                        ),
                                        "needs_target": True,
                                        "rect": {
                                            "x": 550,
                                            "y": 250,
                                            "w": 180,
                                            "h": 200,
                                            "visible": True,
                                        },
                                    },
                                ],
                            },
                            "layout_rects": {
                                "boss_reward_popup": {
                                    "x": 0,
                                    "y": 0,
                                    "w": 1280,
                                    "h": 720,
                                    "visible": True,
                                },
                            },
                        }
                    )
                elif label == lint.LAST_CHAIN_FRAME_LABEL:
                    step.update(
                        {
                            "phase": "BUILD",
                            "active_modals": [],
                            "build_visible": True,
                            "chain_visible": False,
                            "last_chain_history": {
                                "visible": True,
                                "text": (
                                    "2 triggers\n"
                                    "#1 Round Start: A -> B +Unit\n"
                                    "#2 Cascade: B -> B +Stats\n"
                                    "Complete: 2 triggers, no gold"
                                ),
                                "display_text": (
                                    "2 triggers\n"
                                    "#1 A -> B +Unit\n"
                                    "#2 B -> B +Stats"
                                ),
                            },
                            "last_settlement_recap": {
                                "visible": True,
                                "text": (
                                    "LAST SETTLEMENT R1\n"
                                    "Gold: 11 -> 16 (+5; +5 income, +0 interest)\n"
                                    "Terazin: 0 -> 2 (+2; +2 round)\n"
                                    "Next: R2 BUILD"
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
                            "layout_rects": {
                                "settlement_recap_panel": {
                                    "x": 760,
                                    "y": 240,
                                    "w": 500,
                                    "h": 110,
                                    "visible": True,
                                },
                                "tutorial_panel": {
                                    "x": 760,
                                    "y": 240,
                                    "w": 500,
                                    "h": 110,
                                    "visible": False,
                                },
                                "last_chain_panel": {
                                    "x": 760,
                                    "y": 354,
                                    "w": 500,
                                    "h": 96,
                                    "visible": True,
                                },
                                "field_container": {
                                    "x": 20,
                                    "y": 455,
                                    "w": 1240,
                                    "h": 165,
                                    "visible": True,
                                },
                                "confirm_button": {
                                    "x": 540,
                                    "y": 688,
                                    "w": 200,
                                    "h": 30,
                                    "visible": True,
                                },
                                "battle_status": {
                                    "x": 10,
                                    "y": 10,
                                    "w": 590,
                                    "h": 30,
                                    "visible": False,
                                },
                            },
                        }
                    )
                report["steps"].append(step)
        return report

    def _validate(self, report: dict, width: int = 4, height: int = 3) -> list[str]:
        return lint.validate_report(
            self._write_report(report),
            expected_width=width,
            expected_height=height,
            min_file_size=1,
            min_channel_range=4,
        )

    def test_valid_report_passes(self) -> None:
        self.assertEqual(self._validate(self._valid_report()), [])

    def test_headless_unsupported_status_fails(self) -> None:
        report = self._valid_report()
        report["metadata"]["screenshot_status"] = "unsupported"

        errors = self._validate(report)

        self.assertTrue(any("screenshot_status" in error for error in errors))

    def test_missing_screenshot_file_fails(self) -> None:
        report = self._valid_report()
        missing = Path(report["screenshots"][0]["path"])
        missing.unlink()

        errors = self._validate(report)

        self.assertTrue(any("file is missing" in error for error in errors))

    def test_blank_image_fails(self) -> None:
        report = self._valid_report()
        blank_path = Path(report["screenshots"][0]["path"])
        _write_png(blank_path, 4, 3, blank=True)

        errors = self._validate(report)

        self.assertTrue(any("appears blank" in error for error in errors))

    def test_duplicate_label_fails(self) -> None:
        report = self._valid_report()
        report["screenshots"][1]["label"] = report["screenshots"][0]["label"]

        errors = self._validate(report)

        self.assertTrue(any("duplicate screenshot labels" in error for error in errors))

    def test_wrong_dimensions_fail(self) -> None:
        report = self._valid_report()
        wrong_path = Path(report["screenshots"][0]["path"])
        _write_png(wrong_path, 5, 3)

        errors = self._validate(report)

        self.assertTrue(any("PNG dimensions disagree" in error for error in errors))

    def test_target_overlay_overlap_fails(self) -> None:
        report = self._valid_report()
        target_step = next(
            step
            for step in report["steps"]
            if step["label"] == lint.TARGET_FRAME_LABEL
        )
        target_step["layout_rects"]["target_instruction"]["x"] = 560
        target_step["layout_rects"]["target_instruction"]["y"] = 694

        errors = self._validate(report)

        self.assertTrue(any("overlaps confirm_button" in error for error in errors))

    def test_chain_frame_missing_complete_fails(self) -> None:
        report = self._valid_report()
        chain_step = next(
            step
            for step in report["steps"]
            if step["label"] == lint.CHAIN_FRAME_LABEL
        )
        chain_step["chain_feedback"]["event_log_text"] = "#1 Round Start: A -> B +Unit"

        errors = self._validate(report)

        self.assertTrue(any("missing Complete line" in error for error in errors))

    def test_chain_counter_overlapping_hud_fails(self) -> None:
        report = self._valid_report()
        chain_step = next(
            step
            for step in report["steps"]
            if step["label"] == lint.CHAIN_FRAME_LABEL
        )
        chain_step["layout_rects"]["chain_counter"]["x"] = 1200
        chain_step["layout_rects"]["chain_counter"]["y"] = 12

        errors = self._validate(report)

        self.assertTrue(any("chain_counter overlaps HUD labels" in error for error in errors))

    def test_last_chain_panel_hidden_fails(self) -> None:
        report = self._valid_report()
        last_step = next(
            step
            for step in report["steps"]
            if step["label"] == lint.LAST_CHAIN_FRAME_LABEL
        )
        last_step["last_chain_history"]["visible"] = False

        errors = self._validate(report)

        self.assertTrue(any("last-chain panel must be visible" in error for error in errors))

    def test_last_chain_uncompacted_display_text_fails(self) -> None:
        report = self._valid_report()
        last_step = next(
            step
            for step in report["steps"]
            if step["label"] == lint.LAST_CHAIN_FRAME_LABEL
        )
        last_step["last_chain_history"]["display_text"] = (
            "2 triggers\n"
            "#1 Round Start: A -> B +Unit (Unit Added / Manufacture)\n"
            "Complete: 2 triggers, no gold"
        )

        errors = self._validate(report)

        self.assertTrue(any("display text repeats Complete line" in error for error in errors))

    def test_last_chain_panel_too_short_fails(self) -> None:
        report = self._valid_report()
        last_step = next(
            step
            for step in report["steps"]
            if step["label"] == lint.LAST_CHAIN_FRAME_LABEL
        )
        last_step["layout_rects"]["last_chain_panel"]["h"] = 76

        errors = self._validate(report)

        self.assertTrue(any("last_chain_panel is too short" in error for error in errors))

    def test_settlement_recap_without_interest_fails(self) -> None:
        report = self._valid_report()
        last_step = next(
            step
            for step in report["steps"]
            if step["label"] == lint.LAST_CHAIN_FRAME_LABEL
        )
        last_step["last_settlement_recap"]["text"] = (
            "LAST SETTLEMENT R1\n"
            "Gold: 11 -> 16 (+5 income)\n"
            "Terazin: 0 -> 2 (+2 round)\n"
            "Next: R2 BUILD"
        )
        del last_step["last_settlement_recap"]["data"]["interest"]

        errors = self._validate(report)

        self.assertTrue(any("settlement recap missing 'interest'" in error for error in errors))
        self.assertTrue(any("settlement data missing 'interest'" in error for error in errors))

    def test_settlement_recap_overlapping_tutorial_fails(self) -> None:
        report = self._valid_report()
        last_step = next(
            step
            for step in report["steps"]
            if step["label"] == lint.LAST_CHAIN_FRAME_LABEL
        )
        last_step["layout_rects"]["tutorial_panel"]["visible"] = True

        errors = self._validate(report)

        self.assertTrue(any("overlaps tutorial_panel" in error for error in errors))

    def test_battle_result_without_hp_line_fails(self) -> None:
        report = self._valid_report()
        battle_step = next(
            step
            for step in report["steps"]
            if step["label"] == lint.BATTLE_RESULT_FRAME_LABEL
        )
        battle_step["battle_result"]["detail_text"] = (
            "Round 1 cleared\nGold: 10 -> 11 (+1 win, +0 cards)\n"
            "Next: return to BUILD after income"
        )

        errors = self._validate(report)

        self.assertTrue(any("detail text missing 'HP:'" in error for error in errors))

    def test_boss_reward_without_rendered_desc_fails(self) -> None:
        report = self._valid_report()
        boss_step = next(
            step
            for step in report["steps"]
            if step["label"] == lint.BOSS_REWARD_FRAME_LABEL
        )
        boss_step["boss_reward"]["choice_summaries"][0]["desc"] = ""
        boss_step["boss_reward"]["choice_summaries"][0]["text"] = "긴급 자금\n즉시"

        errors = self._validate(report)

        self.assertTrue(any("missing rendered desc" in error for error in errors))

    def test_targeted_boss_reward_without_target_marker_fails(self) -> None:
        report = self._valid_report()
        targeted_step = next(
            step
            for step in report["steps"]
            if step["label"] == lint.TARGETED_BOSS_REWARD_FRAME_LABEL
        )
        targeted_step["boss_reward"]["choice_summaries"][0]["needs_target"] = False

        errors = self._validate(report)

        self.assertTrue(any("expected a targeted reward summary" in error for error in errors))

    def test_last_chain_frame_visible_battle_status_fails(self) -> None:
        report = self._valid_report()
        last_step = next(
            step
            for step in report["steps"]
            if step["label"] == lint.LAST_CHAIN_FRAME_LABEL
        )
        last_step["layout_rects"]["battle_status"]["visible"] = True

        errors = self._validate(report)

        self.assertTrue(any("battle_status must be hidden" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
