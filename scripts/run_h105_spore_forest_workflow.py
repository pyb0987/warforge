#!/usr/bin/env python3
"""Print or run the H105 Spore forest-depth probe verification workflow."""

from __future__ import annotations

import argparse
import shlex
import subprocess
from dataclasses import dataclass
from pathlib import Path


DEFAULT_BASELINE_TRACE_DIR = "/private/tmp/warforge_h104_clean_druid60_traces"
DEFAULT_SEED = "2026072901"
DEFAULT_RUNS = 60
DEFAULT_STRATEGY = "soft_druid"
DEFAULT_PREFIX = "warforge_h105_spore_forest60"


@dataclass(frozen=True)
class WorkflowCommand:
    label: str
    cmd: list[str]
    allow_failure: bool = False
    stdout_path: str | None = None


def build_commands(args: argparse.Namespace) -> list[WorkflowCommand]:
    prefix = args.prefix
    trace_dir = args.trace_dir or f"/private/tmp/{prefix}_traces"
    report_path = args.report or f"/private/tmp/{prefix}.json"
    summary_path = args.summary or f"/private/tmp/{prefix}_summary.md"
    analysis_path = args.analysis or f"/private/tmp/{prefix}_vs_h104.txt"
    eval_json_path = args.eval_json or f"/private/tmp/{prefix}_h105_gate.json"
    home_dir = args.home or f"/private/tmp/warforge_godot_home_{prefix}"
    log_path = args.log or f"/private/tmp/{prefix}.log"

    commands = [
        WorkflowCommand("source state", ["git", "status", "--short", "--branch"]),
        WorkflowCommand(
            "codegen parity",
            ["python3", "scripts/codegen_card_db.py", "--check"],
        ),
        WorkflowCommand("card spawn guard", ["python3", "scripts/lint_card_spawn.py"]),
        WorkflowCommand(
            "focused Druid runtime tests",
            _godot_test_cmd(args.godot, home_dir + "_druid", "res://tests/test_druid_system.gd"),
        ),
        WorkflowCommand(
            "focused ChainEngine tests",
            _godot_test_cmd(args.godot, home_dir + "_chain", "res://tests/test_chain_engine.gd"),
        ),
    ]

    if not args.skip_self_play:
        commands.extend([
            WorkflowCommand(
                "same-seed self-play",
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
                "Druid analyzer",
                [
                    "python3",
                    "scripts/analyze_ai_trace.py",
                    trace_dir,
                    f"--strategy={args.strategy}",
                    "--druid-active-ledger",
                    "--druid-spore-tree-gap",
                    "--druid-run-phase",
                    "--druid-activation-audit",
                    f"--druid-compare-baseline={args.baseline_trace_dir}",
                ],
                stdout_path=analysis_path,
            ),
            WorkflowCommand(
                "H105 gate evaluator",
                [
                    "python3",
                    "scripts/evaluate_h105_spore_forest_probe.py",
                    trace_dir,
                    f"--baseline-trace-dir={args.baseline_trace_dir}",
                    f"--strategy={args.strategy}",
                    "--json-out",
                    eval_json_path,
                ],
                allow_failure=True,
            ),
        ])

    commands.append(
        WorkflowCommand(
            "H105 changed-file boundary",
            [
                "python3",
                "scripts/check_h105_spore_forest_boundary.py",
                "--allow-records",
            ],
        )
    )
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
        "# H105 Spore Forest Workflow",
        "",
        "Dry-run command list:",
    ]
    for idx, command in enumerate(commands, start=1):
        suffix = " (nonzero allowed)" if command.allow_failure else ""
        lines.append(f"{idx}. {command.label}{suffix}")
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
        if completed.returncode != 0 and not command.allow_failure:
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
    parser.add_argument("--baseline-trace-dir", default=DEFAULT_BASELINE_TRACE_DIR)
    parser.add_argument("--prefix", default=DEFAULT_PREFIX)
    parser.add_argument("--trace-dir", default=None)
    parser.add_argument("--report", default=None)
    parser.add_argument("--summary", default=None)
    parser.add_argument("--analysis", default=None)
    parser.add_argument("--eval-json", default=None)
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
