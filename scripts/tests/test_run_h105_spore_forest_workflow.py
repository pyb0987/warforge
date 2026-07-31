import argparse
import contextlib
import importlib.util
import io
import pathlib
import sys
import tempfile
import unittest


MODULE_PATH = (
    pathlib.Path(__file__).resolve().parents[1]
    / "run_h105_spore_forest_workflow.py"
)
SPEC = importlib.util.spec_from_file_location("run_h105", MODULE_PATH)
run_h105 = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = run_h105
SPEC.loader.exec_module(run_h105)


class RunH105SporeForestWorkflowTest(unittest.TestCase):
    def test_dry_run_lists_h105_core_commands(self):
        commands = run_h105.build_commands(_args(skip_self_play=False))
        rendered = run_h105.render_commands(commands)

        self.assertIn("scripts/codegen_card_db.py --check", rendered)
        self.assertIn("tools/self_play_observer.gd", rendered)
        self.assertIn("scripts/evaluate_h105_spore_forest_probe.py", rendered)
        self.assertIn("scripts/check_h105_spore_forest_boundary.py --allow-records", rendered)
        self.assertIn("--druid-spore-tree-gap", rendered)
        self.assertIn("> /private/tmp/warforge_h105_spore_forest60_vs_h104.txt", rendered)

    def test_skip_self_play_keeps_preflight_and_boundary_only(self):
        commands = run_h105.build_commands(_args(skip_self_play=True))
        labels = [command.label for command in commands]

        self.assertIn("focused Druid runtime tests", labels)
        self.assertIn("H105 changed-file boundary", labels)
        self.assertNotIn("same-seed self-play", labels)
        self.assertNotIn("H105 gate evaluator", labels)

    def test_nonzero_allowed_command_does_not_abort_execution(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp) / "out.txt"
            commands = [
                run_h105.WorkflowCommand(
                    "allowed failure",
                    ["python3", "-c", "import sys; print('weak'); sys.exit(1)"],
                    allow_failure=True,
                    stdout_path=str(out),
                ),
                run_h105.WorkflowCommand(
                    "still runs",
                    ["python3", "-c", "print('ok')"],
                    stdout_path=str(pathlib.Path(tmp) / "ok.txt"),
                ),
            ]

            with contextlib.redirect_stdout(io.StringIO()):
                exit_code = run_h105.run_commands(commands, pathlib.Path("."))
            output = out.read_text(encoding="utf-8").strip()

        self.assertEqual(exit_code, 0)
        self.assertEqual(output, "weak")

    def test_required_command_failure_aborts_execution(self):
        commands = [
            run_h105.WorkflowCommand(
                "required failure",
                ["python3", "-c", "import sys; sys.exit(2)"],
            ),
            run_h105.WorkflowCommand(
                "not reached",
                ["python3", "-c", "raise SystemExit(99)"],
            ),
        ]

        with contextlib.redirect_stdout(io.StringIO()):
            exit_code = run_h105.run_commands(commands, pathlib.Path("."))

        self.assertEqual(exit_code, 2)


def _args(skip_self_play):
    return argparse.Namespace(
        execute=False,
        skip_self_play=skip_self_play,
        full_gut=False,
        godot="godot",
        runs=60,
        seed="2026072901",
        strategy="soft_druid",
        baseline_trace_dir="/private/tmp/warforge_h104_clean_druid60_traces",
        prefix="warforge_h105_spore_forest60",
        trace_dir=None,
        report=None,
        summary=None,
        analysis=None,
        eval_json=None,
        home=None,
        log=None,
        cwd=".",
    )


if __name__ == "__main__":
    unittest.main()
