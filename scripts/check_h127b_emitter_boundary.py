#!/usr/bin/env python3
"""Check changed files stay inside the H127B Druid trace-emitter boundary."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


ALLOWED_EMITTER_FILES = {
    "godot/sim/headless_runner.gd",
    "godot/tests/test_headless_runner.gd",
}

ALLOWED_RECORD_FILES = {
    "Plans.md",
    "docs/tools/self-play-observer.md",
}
ALLOWED_RECORD_PREFIXES = (
    ".claude/traces/experiments/",
)

FORBIDDEN_PATTERNS = {
    "godot/sim/ai_agent.gd": "AI policy is out of scope for trace-emitter H127B",
    "godot/tests/test_ai_agent.gd": "AI policy tests are out of scope for H127B",
    "godot/core/druid_system.gd": "Druid runtime behavior is already covered by H126",
    "godot/tests/test_druid_system.gd": "Druid runtime tests are out of scope for H127B",
    "godot/tests/test_chain_engine.gd": "ChainEngine tests are out of scope for H127B",
    "godot/tools/self_play_observer.gd": "observer aggregation is out of scope for H127B",
    "scripts/analyze_ai_trace.py": "analyzer masking is out of scope for H127B",
    "data/cards/druid.yaml": "card YAML is out of scope for H127B",
    "godot/core/data/card_db.gd": "generated card DB must not be edited",
    "godot/core/data/card_descs.gd": "generated card descs must not be edited",
    "godot/sim/evaluator.gd": "evaluator scoring is out of scope for H127B",
    "godot/combat/combat_engine.gd": "combat semantics are out of scope for H127B",
    "godot/core/chain_engine.gd": "chain/combat-start semantics are out of scope",
}
FORBIDDEN_PREFIXES = {
    "data/cards/": "card YAML is out of scope for H127B",
    "godot/core/data/": "generated card data is out of scope",
}


def check_paths(paths: list[str], allow_records: bool = False) -> dict:
    normalized = [_normalize_path(path) for path in paths if path.strip()]
    violations = []
    for path in normalized:
        reason = _violation_reason(path, allow_records)
        if reason:
            violations.append({"path": path, "reason": reason})
    return {
        "ok": not violations,
        "allow_records": allow_records,
        "checked": normalized,
        "violations": violations,
    }


def _violation_reason(path: str, allow_records: bool) -> str:
    if path in ALLOWED_EMITTER_FILES:
        return ""
    if allow_records and _is_allowed_record_path(path):
        return ""
    if path in FORBIDDEN_PATTERNS:
        return FORBIDDEN_PATTERNS[path]
    for prefix, reason in FORBIDDEN_PREFIXES.items():
        if path.startswith(prefix):
            return reason
    return "not in the H127B trace-emitter allowlist"


def _is_allowed_record_path(path: str) -> bool:
    if path in ALLOWED_RECORD_FILES:
        return True
    return any(path.startswith(prefix) for prefix in ALLOWED_RECORD_PREFIXES)


def _normalize_path(path: str) -> str:
    path = path.strip()
    if "\t" in path:
        path = path.split("\t", 1)[-1]
    path = path.replace("\\", "/")
    if path.startswith("./"):
        path = path[2:]
    return path


def changed_files_from_git(cwd: Path) -> list[str]:
    staged = _git_lines(cwd, ["git", "diff", "--cached", "--name-only"])
    unstaged = _git_lines(cwd, ["git", "diff", "--name-only"])
    untracked = _git_lines(
        cwd,
        ["git", "ls-files", "--others", "--exclude-standard"],
    )
    return sorted(set(staged + unstaged + untracked))


def _git_lines(cwd: Path, cmd: list[str]) -> list[str]:
    result = subprocess.run(
        cmd,
        cwd=cwd,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def render_result(result: dict) -> str:
    lines = [
        "# H127B Druid Trace-Emitter Boundary Check",
        "",
        f"Result: {'PASS' if result['ok'] else 'FAIL'}",
        f"Allow records: {result['allow_records']}",
        f"Checked files: {len(result['checked'])}",
    ]
    if result["checked"]:
        lines.append("")
        lines.append("## Files")
        for path in result["checked"]:
            lines.append(f"- `{path}`")
    if result["violations"]:
        lines.append("")
        lines.append("## Violations")
        for row in result["violations"]:
            lines.append(f"- `{row['path']}`: {row['reason']}")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--allow-records",
        action="store_true",
        help="Allow Plans.md, observer docs, and trace records alongside H127B files.",
    )
    parser.add_argument(
        "--changed-file",
        action="append",
        default=[],
        help="Explicit changed file path. If omitted, read current git changes.",
    )
    parser.add_argument(
        "--cwd",
        default=".",
        help="Repository directory for git change discovery.",
    )
    args = parser.parse_args()

    paths = args.changed_file or changed_files_from_git(Path(args.cwd))
    result = check_paths(paths, allow_records=args.allow_records)
    print(render_result(result))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
