import importlib.util
import pathlib
import unittest


MODULE_PATH = (
    pathlib.Path(__file__).resolve().parents[1]
    / "check_h105_spore_forest_boundary.py"
)
SPEC = importlib.util.spec_from_file_location("check_h105", MODULE_PATH)
check_h105 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check_h105)


class CheckH105SporeForestBoundaryTest(unittest.TestCase):
    def test_allows_only_runtime_probe_files(self):
        result = check_h105.check_paths([
            "godot/core/druid_system.gd",
            "godot/tests/test_druid_system.gd",
            "godot/tests/test_chain_engine.gd",
        ])

        self.assertTrue(result["ok"])
        self.assertEqual(result["violations"], [])

    def test_allows_records_when_requested(self):
        result = check_h105.check_paths(
            [
                "godot/core/druid_system.gd",
                "Plans.md",
                ".claude/traces/experiments/105-example.md",
            ],
            allow_records=True,
        )

        self.assertTrue(result["ok"])

    def test_rejects_records_without_records_mode(self):
        result = check_h105.check_paths(["Plans.md"])

        self.assertFalse(result["ok"])
        self.assertEqual(result["violations"][0]["path"], "Plans.md")

    def test_rejects_card_yaml_and_generated_db(self):
        result = check_h105.check_paths([
            "data/cards/druid.yaml",
            "godot/core/data/card_db.gd",
        ])

        self.assertFalse(result["ok"])
        self.assertEqual(len(result["violations"]), 2)
        self.assertIn("YAML", result["violations"][0]["reason"])
        self.assertIn("generated", result["violations"][1]["reason"])

    def test_rejects_ai_simulator_files(self):
        result = check_h105.check_paths(["godot/sim/ai_agent.gd"])

        self.assertFalse(result["ok"])
        self.assertIn("AI simulator", result["violations"][0]["reason"])

    def test_normalizes_git_status_style_paths(self):
        result = check_h105.check_paths(["M\tgodot/core/druid_system.gd"])

        self.assertTrue(result["ok"])


if __name__ == "__main__":
    unittest.main()
