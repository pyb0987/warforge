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
    / "run_h127b_emitter_workflow.py"
)
SPEC = importlib.util.spec_from_file_location("run_h127b", MODULE_PATH)
run_h127b = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = run_h127b
SPEC.loader.exec_module(run_h127b)


class RunH127BEmitterWorkflowTest(unittest.TestCase):
    def test_dry_run_lists_h127b_core_commands(self):
        commands = run_h127b.build_commands(_args(skip_self_play=False))
        rendered = run_h127b.render_commands(commands)

        self.assertIn("scripts/check_h127b_emitter_boundary.py --allow-records", rendered)
        self.assertIn("res://tests/test_headless_runner.gd", rendered)
        self.assertIn("res://tests/test_druid_system.gd", rendered)
        self.assertIn("scripts.tests.test_analyze_ai_trace", rendered)
        self.assertIn("tools/self_play_observer.gd", rendered)
        self.assertIn("--druid-contribution-ledger", rendered)
        self.assertIn("scripts/check_druid_contribution_ledger_ready.py", rendered)
        self.assertIn(
            "> /private/tmp/warforge_h127b_druid_emitter60_contribution.txt",
            rendered,
        )

    def test_skip_self_play_keeps_preflight_and_boundary_only(self):
        commands = run_h127b.build_commands(_args(skip_self_play=True))
        labels = [command.label for command in commands]

        self.assertIn("H127B changed-file boundary", labels)
        self.assertIn("focused HeadlessRunner tests", labels)
        self.assertIn("focused Druid snapshot tests", labels)
        self.assertIn("Druid contribution analyzer tests", labels)
        self.assertNotIn("fresh Druid self-play traces", labels)
        self.assertNotIn("Druid contribution readiness gate", labels)

    def test_required_command_failure_aborts_execution(self):
        commands = [
            run_h127b.WorkflowCommand(
                "required failure",
                ["python3", "-c", "import sys; sys.exit(2)"],
            ),
            run_h127b.WorkflowCommand(
                "not reached",
                ["python3", "-c", "raise SystemExit(99)"],
            ),
        ]

        with contextlib.redirect_stdout(io.StringIO()):
            exit_code = run_h127b.run_commands(commands, pathlib.Path("."))

        self.assertEqual(exit_code, 2)

    def test_stdout_path_is_written(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp) / "out.txt"
            commands = [
                run_h127b.WorkflowCommand(
                    "writes output",
                    ["python3", "-c", "print('ready')"],
                    stdout_path=str(out),
                ),
            ]

            with contextlib.redirect_stdout(io.StringIO()):
                exit_code = run_h127b.run_commands(commands, pathlib.Path("."))

            output = out.read_text(encoding="utf-8").strip()

        self.assertEqual(exit_code, 0)
        self.assertEqual(output, "ready")


def _args(skip_self_play):
    return argparse.Namespace(
        execute=False,
        skip_self_play=skip_self_play,
        full_gut=False,
        godot="godot",
        runs=60,
        seed="2026080101",
        strategy="soft_druid",
        prefix="warforge_h127b_druid_emitter60",
        trace_dir=None,
        report=None,
        summary=None,
        analysis=None,
        home=None,
        log=None,
        cwd=".",
    )


if __name__ == "__main__":
    unittest.main()
