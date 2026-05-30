#!/usr/bin/env python3
"""Validate the Warforge AI Agent Meta-Harness v2 project surface."""

from __future__ import annotations

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
REQUIRED_FILES = [
    ROOT / "spec.md",
    ROOT / "Plans.md",
    ROOT / "AGENTS.md",
    ROOT / "CLAUDE.md",
]
TRACE_ROOT = ROOT / ".claude" / "traces"
ALT_TRACE_ROOT = ROOT / ".harness" / "traces"
SEARCH_SET = TRACE_ROOT / "search-set.md"
REQUIRED_TRACE_PATHS = [
    TRACE_ROOT / "evolution",
    TRACE_ROOT / "failures",
    TRACE_ROOT / "experiments",
    SEARCH_SET,
]
TRACE_ROOT_FILES = REQUIRED_FILES + [
    TRACE_ROOT / "evolution" / "025-ai-agent-meta-harness-v2.md",
]
SOURCE_FILES = [
    ROOT / "spec.md",
    ROOT / "Plans.md",
    ROOT / "AGENTS.md",
    TRACE_ROOT / "evolution" / "025-ai-agent-meta-harness-v2.md",
]
FORBIDDEN_EXTERNAL_HARNESS_MARKERS = [
    "Chachamaru127",
    "doctor --migration-report",
    "Claude Code Harness plugin",
]
SS012_VERIFY = "- **verify**: `python3 scripts/check_harness_v2_surface.py`"


def has_competing_trace_files(path: Path) -> bool:
    if not path.exists():
        return False
    if not path.is_dir():
        return True
    for child in path.rglob("*"):
        if child.is_file() and child.name != ".keep":
            return True
    return False


def main() -> int:
    failures: list[str] = []

    for path in REQUIRED_FILES:
        if not path.is_file():
            failures.append(f"missing required file: {path.relative_to(ROOT)}")

    for path in REQUIRED_TRACE_PATHS:
        if not path.exists():
            failures.append(f"missing trace path: {path.relative_to(ROOT)}")

    if has_competing_trace_files(ALT_TRACE_ROOT):
        failures.append(
            "competing .harness/traces root exists; review migration before splitting trace history"
        )

    if SEARCH_SET.is_file():
        search_set_text = SEARCH_SET.read_text(encoding="utf-8")
        active_text = search_set_text.split("## Archived", 1)[0]
        if "### SS-012:" not in active_text:
            failures.append(".claude/traces/search-set.md is missing active SS-012")
        if SS012_VERIFY not in active_text:
            failures.append(".claude/traces/search-set.md SS-012 verify command drifted")

    for path in TRACE_ROOT_FILES:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)
        if ".claude/traces" not in text:
            failures.append(f"{rel} does not name .claude/traces")
        for marker in FORBIDDEN_EXTERNAL_HARNESS_MARKERS:
            if marker in text:
                failures.append(f"{rel} still references external harness marker: {marker}")

    for path in SOURCE_FILES:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)
        if "pyb0987/ai-agent-meta-harness" not in text:
            failures.append(f"{rel} does not name pyb0987/ai-agent-meta-harness")

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1

    print("PASS: Warforge AI Agent Meta-Harness v2 surface is coherent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
