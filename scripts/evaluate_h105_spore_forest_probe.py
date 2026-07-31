#!/usr/bin/env python3
"""Evaluate the H105 Druid Spore forest-depth probe adoption gates."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import analyze_ai_trace  # noqa: E402


SCHEMA = "warforge-h105-spore-forest-eval/v1"
VERDICT_NOMINATE = "NOMINATE_DISJOINT_SEED_CONFIRMATION"
VERDICT_REJECT = "REJECT_H105_GATE_FAILURE"
VERDICT_WEAK = "WEAK_LOCAL_SIGNAL_DO_NOT_ADOPT"

GATES = {
    "min_wins": 14,
    "min_avg_final_hp": -3.25,
    "min_hp_delta": 1.0,
    "min_focus_wr": 0.426,
    "min_focus_wr_delta": 0.08,
    "max_active_loss_enemy": 12.5,
    "min_active_loss_ally": 0.2,
    "max_spore_cap_rate": 0.5,
}


def evaluate_h105(candidate_events: list[list[dict[str, Any]]],
                  baseline_events: list[list[dict[str, Any]]]) -> dict[str, Any]:
    """Return a structured H105 gate result for one strategy."""
    comparison = analyze_ai_trace.summarize_druid_probe_comparison(
        candidate_events,
        baseline_events,
    )
    candidate_spore = analyze_ai_trace.summarize_druid_spore_tree_gap(candidate_events)
    baseline_spore = analyze_ai_trace.summarize_druid_spore_tree_gap(baseline_events)
    cap_summary = _summarize_spore_cap_rate(candidate_events)

    gate_rows = _h105_gate_rows(comparison, cap_summary)
    failures = [row for row in gate_rows if not row["passed"]]
    hard_rejects = [
        row for row in failures
        if row["severity"] == "reject"
    ]
    warnings = [row for row in failures if row["severity"] == "warning"]

    if not hard_rejects and comparison["screen_verdict"] != "REJECT_FLAT_OR_NOISY":
        verdict = VERDICT_NOMINATE
    elif _is_flat_or_noisy(comparison):
        verdict = VERDICT_REJECT
    else:
        verdict = VERDICT_WEAK

    return {
        "schema": SCHEMA,
        "verdict": verdict,
        "gates": gate_rows,
        "failed_gates": [row["id"] for row in failures],
        "warnings": [row["id"] for row in warnings],
        "comparison": comparison,
        "spore_tree_gap": {
            "baseline": _spore_gate_context(baseline_spore),
            "candidate": _spore_gate_context(candidate_spore),
        },
        "spore_cap_rate": cap_summary,
        "next_step": _next_step(verdict),
    }


def _h105_gate_rows(comparison: dict[str, Any],
                    cap_summary: dict[str, Any]) -> list[dict[str, Any]]:
    candidate = comparison["candidate"]
    baseline = comparison["baseline"]
    deltas = comparison["deltas"]
    ledger = comparison["ledger"]
    bottleneck_deltas = ledger["bottleneck_deltas"]

    return [
        _gate(
            "clears_materially_improve",
            int(candidate["wins"]) >= GATES["min_wins"],
            int(candidate["wins"]),
            f">= {GATES['min_wins']} clears",
            "reject",
            f"baseline {baseline['wins']}/60, candidate must beat H104 9/60 materially",
        ),
        _gate(
            "avg_final_hp_improves",
            (
                float(candidate["avg_final_hp"]) >= GATES["min_avg_final_hp"]
                and float(deltas["avg_final_hp"]) >= GATES["min_hp_delta"]
            ),
            round(float(candidate["avg_final_hp"]), 3),
            (
                f">= {GATES['min_avg_final_hp']} and delta "
                f">= +{GATES['min_hp_delta']}"
            ),
            "reject",
            f"delta {float(deltas['avg_final_hp']):+.3f}",
        ),
        _gate(
            "focus_wr_improves",
            (
                float(ledger["candidate_win_rate"]) >= GATES["min_focus_wr"]
                and float(ledger["win_rate_delta"]) >= GATES["min_focus_wr_delta"]
            ),
            round(float(ledger["candidate_win_rate"]), 4),
            (
                f">= {GATES['min_focus_wr']:.1%} and delta "
                f">= +{GATES['min_focus_wr_delta']:.1%}"
            ),
            "reject",
            f"delta {float(ledger['win_rate_delta']):+.1%}",
        ),
        _gate(
            "h74_screen_not_flat",
            comparison["screen_verdict"] != "REJECT_FLAT_OR_NOISY",
            comparison["screen_verdict"],
            "not REJECT_FLAT_OR_NOISY",
            "reject",
            "H74 screen guards against local/noisy probe wins",
        ),
        _gate(
            "active_loss_enemy_survivors_fall",
            (
                float(ledger["candidate_avg_loss_enemy_survived"])
                <= GATES["max_active_loss_enemy"]
            ),
            round(float(ledger["candidate_avg_loss_enemy_survived"]), 3),
            f"<= {GATES['max_active_loss_enemy']}",
            "reject",
            f"baseline {float(ledger['baseline_avg_loss_enemy_survived']):.3f}",
        ),
        _gate(
            "active_loss_allied_survivors_move",
            (
                float(ledger["candidate_avg_loss_ally_survived"])
                >= GATES["min_active_loss_ally"]
            ),
            round(float(ledger["candidate_avg_loss_ally_survived"]), 3),
            f">= {GATES['min_active_loss_ally']}",
            "reject",
            f"baseline {float(ledger['baseline_avg_loss_ally_survived']):.3f}",
        ),
        _gate(
            "debuff_too_small_decreases",
            int(bottleneck_deltas.get("debuff_too_small", 0)) < 0,
            int(bottleneck_deltas.get("debuff_too_small", 0)),
            "< 0 delta",
            "reject",
            "must improve the measured Spore pressure bucket",
        ),
        _gate(
            "not_cap_heavy",
            (
                int(cap_summary["spore_frames"]) < 10
                or float(cap_summary["cap_rate"]) < GATES["max_spore_cap_rate"]
            ),
            round(float(cap_summary["cap_rate"]), 4),
            f"< {GATES['max_spore_cap_rate']:.0%} of Spore-active R9-R11 frames capped",
            "reject",
            "cap-heavy behavior can mask overtuning",
        ),
    ]


def _gate(gate_id: str, passed: bool, observed: Any, target: str,
          severity: str, note: str) -> dict[str, Any]:
    return {
        "id": gate_id,
        "passed": bool(passed),
        "observed": observed,
        "target": target,
        "severity": severity,
        "note": note,
    }


def _is_flat_or_noisy(comparison: dict[str, Any]) -> bool:
    return (
        comparison["screen_verdict"] == "REJECT_FLAT_OR_NOISY"
        or int(comparison["candidate"]["wins"]) <= int(comparison["baseline"]["wins"])
        or float(comparison["deltas"]["avg_final_hp"]) < 1.0
        or float(comparison["ledger"]["win_rate_delta"]) < 0.05
    )


def _spore_gate_context(summary: dict[str, Any]) -> dict[str, Any]:
    return {
        "spore_frames": summary["spore_frames"],
        "spore_wins": summary["spore_wins"],
        "spore_losses": summary["spore_losses"],
        "avg_spore_own_trees": summary["avg_spore_own_trees"],
        "avg_active_tree_counters": summary["avg_active_tree_counters"],
        "loss_avg_current_debuff": summary["loss_avg_current_debuff"],
        "low_debuff_losses": summary["low_debuff_losses"],
        "next_signal": summary["next_signal"],
    }


def _summarize_spore_cap_rate(events_per_run: list[list[dict[str, Any]]],
                              round_min: int = 9,
                              round_max: int = 11) -> dict[str, Any]:
    frames = 0
    capped = 0
    for events in events_per_run:
        round_end_by_round = {
            int(ev.get("round", 0)): ev
            for ev in events
            if ev.get("t") == "round_end"
        }
        for battle in [ev for ev in events if ev.get("t") == "battle"]:
            round_num = int(battle.get("round", 0))
            if round_num < round_min or round_num > round_max:
                continue
            round_end = round_end_by_round.get(round_num)
            if not isinstance(round_end, dict):
                continue
            active_board = set(round_end.get("active_board") or [])
            if "dr_spore_cloud" not in active_board:
                continue
            frames += 1
            if analyze_ai_trace._battle_max_enemy_debuff(battle) >= 0.49:
                capped += 1
    return {
        "round_min": round_min,
        "round_max": round_max,
        "spore_frames": frames,
        "capped_frames": capped,
        "cap_rate": capped / frames if frames else 0.0,
    }


def _next_step(verdict: str) -> str:
    if verdict == VERDICT_NOMINATE:
        return "Run a disjoint 60-run seed before adoption."
    if verdict == VERDICT_REJECT:
        return "Rollback the H105 gameplay files and record failed gates."
    return "Treat as weak local signal; do not adopt without new evidence."


def render_markdown(result: dict[str, Any]) -> str:
    comparison = result["comparison"]
    candidate = comparison["candidate"]
    baseline = comparison["baseline"]
    ledger = comparison["ledger"]
    lines = [
        "# H105 Druid Spore Forest-Depth Gate",
        "",
        f"Verdict: `{result['verdict']}`",
        f"Next: {result['next_step']}",
        "",
        "## Run Result",
        (
            f"- Clears: {baseline['wins']}/{baseline['runs']} -> "
            f"{candidate['wins']}/{candidate['runs']}"
        ),
        (
            f"- Avg final HP: {baseline['avg_final_hp']:.2f} -> "
            f"{candidate['avg_final_hp']:.2f} "
            f"(delta {comparison['deltas']['avg_final_hp']:+.2f})"
        ),
        (
            f"- R9-R11 focus WR: {ledger['baseline_win_rate']:.1%} -> "
            f"{ledger['candidate_win_rate']:.1%} "
            f"(delta {ledger['win_rate_delta']:+.1%})"
        ),
        (
            "- Active-loss survivors A/E: "
            f"{ledger['baseline_avg_loss_ally_survived']:.1f}/"
            f"{ledger['baseline_avg_loss_enemy_survived']:.1f} -> "
            f"{ledger['candidate_avg_loss_ally_survived']:.1f}/"
            f"{ledger['candidate_avg_loss_enemy_survived']:.1f}"
        ),
        f"- H74 screen: `{comparison['screen_verdict']}`",
        "",
        "## Gates",
    ]
    for row in result["gates"]:
        status = "PASS" if row["passed"] else "FAIL"
        lines.append(
            f"- {status} `{row['id']}` observed `{row['observed']}`; "
            f"target {row['target']}. {row['note']}"
        )
    cap = result["spore_cap_rate"]
    lines.extend([
        "",
        "## Cap Check",
        (
            f"- Spore-active R{cap['round_min']}-R{cap['round_max']} frames: "
            f"{cap['spore_frames']}, capped {cap['capped_frames']} "
            f"({cap['cap_rate']:.1%})"
        ),
        "",
    ])
    return "\n".join(lines)


def _load_strategy_events(trace_dir: str, strategy: str) -> list[list[dict[str, Any]]]:
    runs = analyze_ai_trace.load_runs(trace_dir, strategy)
    events = runs.get(strategy, [])
    if not events:
        raise SystemExit(f"No {strategy!r} traces found in {trace_dir}")
    return events


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("candidate_trace_dir")
    parser.add_argument("--baseline-trace-dir", required=True)
    parser.add_argument("--strategy", default="soft_druid")
    parser.add_argument("--json-out", default=None)
    args = parser.parse_args()

    candidate_events = _load_strategy_events(args.candidate_trace_dir, args.strategy)
    baseline_events = _load_strategy_events(args.baseline_trace_dir, args.strategy)
    result = evaluate_h105(candidate_events, baseline_events)

    if args.json_out:
        Path(args.json_out).write_text(
            json.dumps(result, indent=2, sort_keys=True),
            encoding="utf-8",
        )
    print(render_markdown(result))
    return 0 if result["verdict"] == VERDICT_NOMINATE else 1


if __name__ == "__main__":
    raise SystemExit(main())
