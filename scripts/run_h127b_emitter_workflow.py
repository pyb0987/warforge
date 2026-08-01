#!/usr/bin/env python3
"""Print or run the H127B Druid trace-emitter verification workflow."""

from __future__ import annotations

import argparse
import shlex
import subprocess
from dataclasses import dataclass
from pathlib import Path


DEFAULT_SEED = "2026080101"
DEFAULT_RUNS = 60
DEFAULT_STRATEGY = "soft_druid"
DEFAULT_PREFIX = "warforge_h127b_druid_emitter60"


@dataclass(frozen=True)
class WorkflowCommand:
    label: str
    cmd: list[str]
    stdout_path: str | None = None


def build_commands(args: argparse.Namespace) -> list[WorkflowCommand]:
    prefix = args.prefix
    trace_dir = args.trace_dir or f"/private/tmp/{prefix}_traces"
    report_path = args.report or f"/private/tmp/{prefix}.json"
    summary_path = args.summary or f"/private/tmp/{prefix}_summary.md"
    analysis_path = args.analysis or f"/private/tmp/{prefix}_contribution.txt"
    home_dir = args.home or f"/private/tmp/warforge_godot_home_{prefix}"
    log_path = args.log or f"/private/tmp/{prefix}.log"

    commands = [
        WorkflowCommand("source state", ["git", "status", "--short", "--branch"]),
        WorkflowCommand(
            "H127B changed-file boundary",
            [
                "python3",
                "scripts/check_h127b_emitter_boundary.py",
                "--allow-records",
            ],
        ),
        WorkflowCommand(
            "focused HeadlessRunner tests",
            _godot_test_cmd(
                args.godot,
                home_dir + "_headless",
                "res://tests/test_headless_runner.gd",
            ),
        ),
        WorkflowCommand(
            "focused Druid snapshot tests",
            _godot_test_cmd(
                args.godot,
                home_dir + "_druid",
                "res://tests/test_druid_system.gd",
            ),
        ),
        WorkflowCommand(
            "Druid contribution analyzer tests",
            ["python3", "-m", "unittest", "scripts.tests.test_analyze_ai_trace"],
        ),
    ]

    if not args.skip_self_play:
        commands.extend([
            WorkflowCommand(
                "fresh Druid self-play traces",
                [
                    "/usr/bin/env",
                    f"HOME={home_dir}",
                    args.godot,
                    "--headless",
                    "--log-file",
                    log_path,
                    "--path",
                    "godot/",
                    "-s",
                    "tools/self_play_observer.gd",
                    "--",
                    f"--runs={args.runs}",
                    f"--strategies={args.strategy}",
                    "--difficulty=1",
                    "--commander=gambler",
                    "--talisman=flint",
                    f"--seed={args.seed}",
                    f"--out={report_path}",
                    f"--trace-dir={trace_dir}",
                    "--quiet-progress=true",
                ],
            ),
            WorkflowCommand(
                "self-play summary",
                [
                    "python3",
                    "scripts/summarize_self_play_report.py",
                    "--report",
                    report_path,
                    "--out",
                    summary_path,
                ],
            ),
            WorkflowCommand(
                "Druid contribution analyzer",
                [
                    "python3",
                    "scripts/analyze_ai_trace.py",
                    trace_dir,
                    f"--strategy={args.strategy}",
                    "--druid-contribution-ledger",
                ],
                stdout_path=analysis_path,
            ),
            WorkflowCommand(
                "Druid contribution readiness gate",
                [
                    "python3",
                    "scripts/check_druid_contribution_ledger_ready.py",
                    trace_dir,
                    f"--strategy={args.strategy}",
                ],
            ),
        ])

    commands.append(WorkflowCommand("diff whitespace", ["git", "diff", "--check"]))

    if args.full_gut:
        commands.append(
            WorkflowCommand(
                "full GUT",
                [
                    "/usr/bin/env",
                    f"HOME={home_dir}_full_gut",
                    args.godot,
                    "--headless",
                    "--path",
                    "godot/",
                    "-s",
                    "addons/gut/gut_cmdln.gd",
                    "-gdir=res://tests/",
                    "-glog=1",
                    "-gexit",
                ],
            )
        )
    return commands


def _godot_test_cmd(godot: str, home: str, test_path: str) -> list[str]:
    return [
        "/usr/bin/env",
        f"HOME={home}",
        godot,
        "--headless",
        "--path",
        "godot/",
        "-s",
        "addons/gut/gut_cmdln.gd",
        f"-gtest={test_path}",
        "-glog=1",
        "-gexit",
    ]


def render_commands(commands: list[WorkflowCommand]) -> str:
    lines = [
        "# H127B Druid Trace-Emitter Workflow",
        "",
        "Dry-run command list:",
    ]
    for idx, command in enumerate(commands, start=1):
        lines.append(f"{idx}. {command.label}")
        lines.append("")
        lines.append("```bash")
        rendered = shlex.join(command.cmd)
        if command.stdout_path:
            rendered += f" > {shlex.quote(command.stdout_path)}"
        lines.append(rendered)
        lines.append("```")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def run_commands(commands: list[WorkflowCommand], cwd: Path) -> int:
    for command in commands:
        print(f"## {command.label}", flush=True)
        if command.stdout_path:
            stdout_path = Path(command.stdout_path)
            stdout_path.parent.mkdir(parents=True, exist_ok=True)
            with stdout_path.open("w", encoding="utf-8") as stdout:
                completed = subprocess.run(command.cmd, cwd=cwd, stdout=stdout)
        else:
            completed = subprocess.run(command.cmd, cwd=cwd)
        if completed.returncode != 0:
            return completed.returncode
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--skip-self-play", action="store_true")
    parser.add_argument("--full-gut", action="store_true")
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--runs", type=int, default=DEFAULT_RUNS)
    parser.add_argument("--seed", default=DEFAULT_SEED)
    parser.add_argument("--strategy", default=DEFAULT_STRATEGY)
    parser.add_argument("--prefix", default=DEFAULT_PREFIX)
    parser.add_argument("--trace-dir", default=None)
    parser.add_argument("--report", default=None)
    parser.add_argument("--summary", default=None)
    parser.add_argument("--analysis", default=None)
    parser.add_argument("--home", default=None)
    parser.add_argument("--log", default=None)
    parser.add_argument("--cwd", default=".")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    commands = build_commands(args)
    if not args.execute:
        print(render_commands(commands), end="")
        return 0
    return run_commands(commands, Path(args.cwd))


if __name__ == "__main__":
    raise SystemExit(main())
