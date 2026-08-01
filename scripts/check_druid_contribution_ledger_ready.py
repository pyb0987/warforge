#!/usr/bin/env python3
"""Fail unless Druid contribution snapshots are present and analyzer-ready."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import analyze_ai_trace
except ModuleNotFoundError:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import analyze_ai_trace


BLOCKING_SIGNALS = (
    "SNAPSHOT_EMISSION_REQUIRED",
    "SNAPSHOT_SCHEMA_INVALID",
    "PARTIAL_SNAPSHOT_SCHEMA_INVALID",
    "PARTIAL_SNAPSHOT_COVERAGE",
)


def check_trace_dir(
    trace_dir: str,
    strategy: str,
    round_min: int = 9,
    round_max: int = 11,
) -> dict:
    runs_by_strategy = analyze_ai_trace.load_runs(trace_dir, strategy)
    events_per_run = runs_by_strategy.get(strategy, [])
    if not events_per_run:
        return {
            "ok": False,
            "strategy": strategy,
            "trace_dir": trace_dir,
            "errors": [f"no traces found for strategy {strategy!r}"],
        }

    summary = analyze_ai_trace.summarize_druid_contribution_ledger(
        events_per_run,
        round_min=round_min,
        round_max=round_max,
    )
    errors = []
    focus_total = (
        int(summary["focus_frames"])
        + int(summary["missing_focus_snapshot"])
        + int(summary["invalid_focus_snapshot"])
    )
    if int(summary["in_scope_battles"]) <= 0:
        errors.append("no in-scope battles")
    if focus_total <= 0:
        errors.append("no in-scope Druid focus battles")
    if int(summary["snapshot_battles"]) <= 0:
        errors.append("no valid H126 snapshot battles")
    if int(summary["focus_frames"]) <= 0:
        errors.append("no valid Druid focus snapshot frames")
    if int(summary["missing_focus_snapshot"]) > 0:
        errors.append(
            f"missing focus snapshots: {summary['missing_focus_snapshot']}"
        )
    if int(summary["invalid_focus_snapshot"]) > 0:
        errors.append(
            f"invalid focus snapshots: {summary['invalid_focus_snapshot']}"
        )
    next_signal = str(summary["next_signal"])
    for signal in BLOCKING_SIGNALS:
        if signal in next_signal:
            errors.append(f"blocking next signal: {signal}")
            break

    return {
        "ok": not errors,
        "strategy": strategy,
        "trace_dir": trace_dir,
        "round_min": round_min,
        "round_max": round_max,
        "summary": summary,
        "errors": errors,
    }


def render_result(result: dict) -> str:
    lines = [
        "# Druid Contribution Ledger Readiness Check",
        "",
        f"Result: {'PASS' if result['ok'] else 'FAIL'}",
        f"Trace dir: {result['trace_dir']}",
        f"Strategy: {result['strategy']}",
    ]
    summary = result.get("summary") or {}
    if summary:
        lines.extend([
            f"Scope: R{summary['round_min']}-R{summary['round_max']}",
            (
                "Snapshot coverage: "
                f"{summary['snapshot_battles']}/{summary['in_scope_battles']} "
                f"({summary['snapshot_coverage']:.1%})"
            ),
            (
                "Focus coverage: "
                f"{summary['focus_snapshot_coverage']:.1%}; "
                f"valid {summary['focus_frames']}; "
                f"missing {summary['missing_focus_snapshot']}; "
                f"invalid {summary['invalid_focus_snapshot']}"
            ),
            f"Spore+offense frames: {summary['spore_offense_frames']}",
            f"Spore+offense losses: {summary['spore_offense_losses']}",
            f"Next signal: {summary['next_signal']}",
        ])
    if result["errors"]:
        lines.append("")
        lines.append("## Errors")
        for error in result["errors"]:
            lines.append(f"- {error}")
    lines.append("")
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("trace_dir")
    parser.add_argument("--strategy", default="soft_druid")
    parser.add_argument("--round-min", type=int, default=9)
    parser.add_argument("--round-max", type=int, default=11)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = check_trace_dir(
        args.trace_dir,
        args.strategy,
        round_min=args.round_min,
        round_max=args.round_max,
    )
    print(render_result(result))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
