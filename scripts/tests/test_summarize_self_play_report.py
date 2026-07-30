from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import summarize_self_play_report as summary  # noqa: E402


class SelfPlayReportSummaryTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self._tmp.name)
        self.report_path = self.tmpdir / "selfplay.json"

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _write_report(self, report: dict) -> Path:
        self.report_path.write_text(json.dumps(report), encoding="utf-8")
        return self.report_path

    def _valid_report(self) -> dict:
        return {
            "schema": summary.SCHEMA,
            "metadata": {
                "difficulty": 2,
                "commander_name": "Gambler",
                "talisman_name": "Flint",
                "strategies": ["adaptive"],
                "source_state": {
                    "available": True,
                    "vcs": "git",
                    "commit": "abcdef1234567890",
                    "branch": "main",
                    "dirty": True,
                    "status_short": ["M Plans.md"],
                },
            },
            "overall": {
                "total_runs": 2,
                "wins": 1,
                "clear_rate": 0.5,
                "avg_rounds_played": 11.5,
                "avg_final_hp": 3.0,
            },
            "per_strategy": {
                "adaptive": {
                    "total_runs": 2,
                    "wins": 1,
                    "clear_rate": 0.5,
                    "avg_rounds_played": 11.5,
                    "avg_boss_rewards": 1.5,
                }
            },
            "per_round": [{"round": 1, "samples": 2}],
            "completion": {
                "top_loss_rounds": [{"id": "R8", "count": 1}],
                "top_final_rounds": [
                    {"id": "R15", "count": 1},
                    {"id": "R8", "count": 1},
                ],
                "boss_milestones": [
                    {
                        "round": 4,
                        "reached_runs": 2,
                        "eligible_runs": 2,
                        "reward_runs": 2,
                        "missed_after_reach": 0,
                        "missed_after_eligible": 0,
                        "reward_rate_of_reached": 1.0,
                        "reward_rate_of_eligible": 1.0,
                    },
                    {
                        "round": 8,
                        "reached_runs": 2,
                        "eligible_runs": 2,
                        "reward_runs": 1,
                        "missed_after_reach": 1,
                        "missed_after_eligible": 1,
                        "reward_rate_of_reached": 0.5,
                        "reward_rate_of_eligible": 0.5,
                    },
                ],
            },
            "completion_readiness": {
                "status": "needs_attention",
                "recommended_next_slice": "Repair the weakest strategy lane.",
                "sample": {
                    "total_runs": 2,
                    "min_runs_per_strategy": 2,
                    "difficulty": 2,
                    "strategies": ["adaptive"],
                },
                "top_risks": [
                    {
                        "rank": 1,
                        "code": "weak_strategy_floor",
                        "severity": "high",
                        "title": "One strategy has an unsafe floor",
                        "evidence": "adaptive 1/2 clears, avg R11.5",
                        "recommended_next_slice": "Repair the weakest strategy lane.",
                    }
                ],
            },
            "unlock_projection": {
                "status": "partial",
                "runs_with_projected_unlocks": 1,
                "runs_with_projected_deferred_unlocks": 1,
                "largest_projected_unlock_count": 4,
                "largest_raw_projected_unlock_count": 4,
                "largest_projected_revealed_unlock_count": 3,
                "largest_projected_deferred_unlock_count": 1,
                "pacing_model": {
                    "status": "ui_reveal",
                    "reveal_cap_per_run": 3,
                    "source": "matches UI reveal cap",
                },
                "metrics": [
                    {
                        "id": "clear",
                        "best_value": 1.0,
                        "threshold": True,
                        "runs_at_threshold": 1,
                        "confidence": "exact",
                        "unlocks": ["difficulty: D3", "talisman: glass_eye"],
                    },
                    {
                        "id": "cards_sold_20",
                        "best_value": None,
                        "threshold": 20,
                        "runs_at_threshold": 0,
                        "confidence": "unobservable",
                        "unlocks": ["commander: alchemist"],
                    },
                ],
                "runs": [
                    {
                        "idx": 0,
                        "strategy": "adaptive",
                        "raw_projected_unlock_count": 4,
                        "raw_projected_unlocks": [
                            "difficulty: D3",
                            "talisman: glass_eye",
                            "commander: raider",
                            "talisman: war_drum",
                        ],
                        "projected_unlock_count": 4,
                        "projected_unlocks": [
                            "difficulty: D3",
                            "talisman: glass_eye",
                            "commander: raider",
                            "talisman: war_drum",
                        ],
                        "projected_revealed_unlock_count": 3,
                        "projected_revealed_unlocks": [
                            "difficulty: D3",
                            "talisman: glass_eye",
                            "commander: raider",
                        ],
                        "projected_deferred_unlock_count": 1,
                        "projected_deferred_unlocks": ["talisman: war_drum"],
                        "won": True,
                        "rounds_played": 15,
                    }
                ],
                "unobservable_metrics": [{"id": "cards_sold_20"}],
            },
            "alerts": [
                {
                    "level": "info",
                    "code": "partial_unlock_projection",
                    "message": "Unlock projection is partial.",
                }
            ],
        }

    def test_summary_mentions_completion_and_unlock_projection(self) -> None:
        result = summary.summarize_report(self._write_report(self._valid_report()))

        self.assertTrue(result.ok)
        self.assertIn("Verdict: PASS", result.markdown)
        self.assertIn("Source State", result.markdown)
        self.assertIn("Git abcdef123456 on main; dirty, 1 changed file(s)", result.markdown)
        self.assertIn("Overall: 1/2 clears", result.markdown)
        self.assertIn("Completion Readiness", result.markdown)
        self.assertIn("Status: needs_attention", result.markdown)
        self.assertIn("Recommended next slice: Repair the weakest strategy lane.", result.markdown)
        self.assertIn("#1 [high] weak_strategy_floor", result.markdown)
        self.assertIn("adaptive: 1/2 clears", result.markdown)
        self.assertIn("R8: reached 2, eligible 2, reward applied 1", result.markdown)
        self.assertIn("Status: partial", result.markdown)
        self.assertIn("Reveal pacing model: ui_reveal, cap 3/run", result.markdown)
        self.assertIn("raw 4 unlocks, reveal 3, defer 1", result.markdown)
        self.assertIn("difficulty: D3", result.markdown)
        self.assertIn("deferred talisman: war_drum", result.markdown)
        self.assertIn("Largest Projected Runs", result.markdown)
        self.assertIn("Partial metrics: cards_sold_20", result.markdown)

    def test_missing_completion_marks_incomplete(self) -> None:
        report = self._valid_report()
        report.pop("completion")

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertIn("Verdict: INCOMPLETE", result.markdown)
        self.assertIn("completion is required", result.errors)

    def test_missing_completion_readiness_marks_incomplete(self) -> None:
        report = self._valid_report()
        report.pop("completion_readiness")

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertIn("Verdict: INCOMPLETE", result.markdown)
        self.assertIn("completion_readiness is required", result.errors)

    def test_legacy_report_without_source_state_still_summarizes(self) -> None:
        report = self._valid_report()
        report["metadata"].pop("source_state")

        result = summary.summarize_report(self._write_report(report))

        self.assertTrue(result.ok)
        self.assertIn("Source State", result.markdown)
        self.assertIn("Not recorded by this report", result.markdown)

    def test_malformed_source_state_marks_incomplete(self) -> None:
        report = self._valid_report()
        report["metadata"]["source_state"] = ["not", "a", "dict"]

        result = summary.summarize_report(self._write_report(report))

        self.assertFalse(result.ok)
        self.assertIn("metadata.source_state must be an object", result.errors)


if __name__ == "__main__":
    unittest.main()
