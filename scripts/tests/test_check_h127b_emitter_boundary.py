import importlib.util
import pathlib
import unittest


MODULE_PATH = (
    pathlib.Path(__file__).resolve().parents[1]
    / "check_h127b_emitter_boundary.py"
)
SPEC = importlib.util.spec_from_file_location("check_h127b", MODULE_PATH)
check_h127b = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check_h127b)


class CheckH127BEmitterBoundaryTest(unittest.TestCase):
    def test_allows_only_emitter_files(self):
        result = check_h127b.check_paths([
            "godot/sim/headless_runner.gd",
            "godot/tests/test_headless_runner.gd",
        ])

        self.assertTrue(result["ok"])
        self.assertEqual(result["violations"], [])

    def test_allows_records_when_requested(self):
        result = check_h127b.check_paths(
            [
                "godot/sim/headless_runner.gd",
                "godot/tests/test_headless_runner.gd",
                "Plans.md",
                "docs/tools/self-play-observer.md",
                ".claude/traces/experiments/127-h127b-druid-trace-emitter.md",
            ],
            allow_records=True,
        )

        self.assertTrue(result["ok"])

    def test_rejects_records_without_records_mode(self):
        result = check_h127b.check_paths(["Plans.md"])

        self.assertFalse(result["ok"])
        self.assertEqual(result["violations"][0]["path"], "Plans.md")

    def test_rejects_ai_and_runtime_scope_creep(self):
        result = check_h127b.check_paths([
            "godot/sim/ai_agent.gd",
            "godot/core/druid_system.gd",
            "godot/core/chain_engine.gd",
            "godot/combat/combat_engine.gd",
        ])

        self.assertFalse(result["ok"])
        self.assertEqual(len(result["violations"]), 4)
        self.assertIn("AI policy", result["violations"][0]["reason"])
        self.assertIn("Druid runtime", result["violations"][1]["reason"])
        self.assertIn("chain", result["violations"][2]["reason"])
        self.assertIn("combat semantics", result["violations"][3]["reason"])

    def test_rejects_analyzer_and_observer_masking(self):
        result = check_h127b.check_paths([
            "scripts/analyze_ai_trace.py",
            "godot/tools/self_play_observer.gd",
        ])

        self.assertFalse(result["ok"])
        self.assertEqual(len(result["violations"]), 2)
        self.assertIn("analyzer", result["violations"][0]["reason"])
        self.assertIn("observer", result["violations"][1]["reason"])

    def test_rejects_card_data_and_evaluator_files(self):
        result = check_h127b.check_paths([
            "data/cards/druid.yaml",
            "godot/core/data/card_db.gd",
            "godot/sim/evaluator.gd",
        ])

        self.assertFalse(result["ok"])
        self.assertEqual(len(result["violations"]), 3)
        self.assertIn("YAML", result["violations"][0]["reason"])
        self.assertIn("generated", result["violations"][1]["reason"])
        self.assertIn("evaluator", result["violations"][2]["reason"])

    def test_normalizes_git_status_style_paths(self):
        result = check_h127b.check_paths(["M\tgodot/sim/headless_runner.gd"])

        self.assertTrue(result["ok"])


if __name__ == "__main__":
    unittest.main()
