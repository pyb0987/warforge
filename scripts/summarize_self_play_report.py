from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

SCHEMA = "warforge-self-play-observer/v1"


@dataclass
class SummaryResult:
    ok: bool
    markdown: str
    errors: list[str]


def summarize_report(report_path: Path | str) -> SummaryResult:
    path = Path(report_path)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        markdown = _render_summary(path, {}, [f"failed to read report: {exc}"])
        return SummaryResult(False, markdown, [f"failed to read report: {exc}"])

    errors = _validate_report(data)
    markdown = _render_summary(path, data, errors)
    return SummaryResult(not errors, markdown, errors)


def _validate_report(data: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if data.get("schema") != SCHEMA:
        errors.append(f"schema must be {SCHEMA!r}")
    if not isinstance(data.get("metadata"), dict):
        errors.append("metadata is required")
    overall = _as_dict(data.get("overall"))
    if int(overall.get("total_runs", 0)) <= 0:
        errors.append("overall.total_runs must be positive")
    if "clear_rate" not in overall:
        errors.append("overall.clear_rate is required")
    if not isinstance(data.get("per_strategy"), dict):
        errors.append("per_strategy is required")
    if not isinstance(data.get("per_round"), list):
        errors.append("per_round is required")

    completion = _as_dict(data.get("completion"))
    if not completion:
        errors.append("completion is required")
    elif not _as_list(completion.get("boss_milestones")):
        errors.append("completion.boss_milestones is required")

    readiness = _as_dict(data.get("completion_readiness"))
    if not readiness:
        errors.append("completion_readiness is required")
    else:
        if not readiness.get("status"):
            errors.append("completion_readiness.status is required")
        if not readiness.get("recommended_next_slice"):
            errors.append("completion_readiness.recommended_next_slice is required")
        if not isinstance(readiness.get("top_risks"), list):
            errors.append("completion_readiness.top_risks is required")

    projection = _as_dict(data.get("unlock_projection"))
    if not projection:
        errors.append("unlock_projection is required")
    else:
        if not _as_list(projection.get("metrics")):
            errors.append("unlock_projection.metrics is required")
        if not _as_list(projection.get("runs")):
            errors.append("unlock_projection.runs is required")
    return errors


def _render_summary(path: Path, data: dict[str, Any], errors: list[str]) -> str:
    metadata = _as_dict(data.get("metadata"))
    overall = _as_dict(data.get("overall"))
    completion = _as_dict(data.get("completion"))
    readiness = _as_dict(data.get("completion_readiness"))
    readiness_sample = _as_dict(readiness.get("sample"))
    projection = _as_dict(data.get("unlock_projection"))
    pacing = _as_dict(projection.get("pacing_model"))
    alerts = _as_list(data.get("alerts"))

    lines = [
        "# Warforge Self-Play Completion Summary",
        "",
        f"Source: `{path}`",
        f"Verdict: {'INCOMPLETE' if errors else 'PASS'}",
        f"Schema: `{data.get('schema', 'missing')}`",
        "",
        "## Run",
        f"- Difficulty: D{metadata.get('difficulty', '?')}",
        f"- Commander: {metadata.get('commander_name', '?')}",
        f"- Talisman: {metadata.get('talisman_name', '?')}",
        f"- Strategies: {_join(metadata.get('strategies', []))}",
        f"- Total runs: {overall.get('total_runs', '?')}",
        "",
        "## Completion",
        (
            "- Overall: "
            f"{overall.get('wins', '?')}/{overall.get('total_runs', '?')} clears "
            f"({ _pct(overall.get('clear_rate', 0.0)) }), "
            f"avg rounds { _fmt(overall.get('avg_rounds_played', 0.0)) }, "
            f"avg final HP { _fmt(overall.get('avg_final_hp', 0.0)) }."
        ),
        f"- Loss rounds: {_count_line(completion.get('top_loss_rounds'))}.",
        f"- Final rounds: {_count_line(completion.get('top_final_rounds'))}.",
        "",
        "## Completion Readiness",
        f"- Status: {readiness.get('status', 'missing')}.",
        f"- Recommended next slice: {readiness.get('recommended_next_slice', 'missing')}",
        (
            "- Sample: "
            f"{readiness_sample.get('total_runs', '?')} runs, "
            f"min {readiness_sample.get('min_runs_per_strategy', '?')}/strategy, "
            f"D{readiness_sample.get('difficulty', metadata.get('difficulty', '?'))}."
        ),
        "",
        "## Top Completion Risks",
    ]
    risks = _as_list(readiness.get("top_risks"))
    if risks:
        for risk in risks:
            row = _as_dict(risk)
            lines.append(
                "- #{rank} [{severity}] {code}: {title} Evidence: {evidence} "
                "Next: {next}.".format(
                    rank=row.get("rank", "?"),
                    severity=row.get("severity", "?"),
                    code=row.get("code", "?"),
                    title=row.get("title", ""),
                    evidence=row.get("evidence", ""),
                    next=str(row.get("recommended_next_slice", "")).rstrip("."),
                )
            )
    else:
        lines.append("- None")

    lines.extend(
        [
            "",
        "## Strategy Split",
        ]
    )
    for name, row in sorted(_as_dict(data.get("per_strategy")).items()):
        stats = _as_dict(row)
        lines.append(
            "- {name}: {wins}/{runs} clears ({rate}), avg rounds {rounds}, "
            "avg boss rewards {boss_rewards}.".format(
                name=name,
                wins=stats.get("wins", "?"),
                runs=stats.get("total_runs", "?"),
                rate=_pct(stats.get("clear_rate", 0.0)),
                rounds=_fmt(stats.get("avg_rounds_played", 0.0)),
                boss_rewards=_fmt(stats.get("avg_boss_rewards", 0.0)),
            )
        )

    lines.extend(
        [
            "",
        "## Boss Milestones",
        ]
    )
    for row in _as_list(completion.get("boss_milestones")):
        eligible = row.get("eligible_runs")
        if eligible is None:
            lines.append(
                "- R{round}: reached {reached}, reward applied {reward}, "
                "missed after reach {missed}, reward/reached {rate}.".format(
                    round=row.get("round", "?"),
                    reached=row.get("reached_runs", "?"),
                    reward=row.get("reward_runs", "?"),
                    missed=row.get("missed_after_reach", "?"),
                    rate=_pct(row.get("reward_rate_of_reached", 0.0)),
                )
            )
        else:
            lines.append(
                "- R{round}: reached {reached}, eligible {eligible}, "
                "reward applied {reward}, missed after eligible {missed}, "
                "reward/eligible {rate}.".format(
                    round=row.get("round", "?"),
                    reached=row.get("reached_runs", "?"),
                    eligible=eligible,
                    reward=row.get("reward_runs", "?"),
                    missed=row.get(
                        "missed_after_eligible",
                        row.get("missed_after_reach", "?"),
                    ),
                    rate=_pct(row.get("reward_rate_of_eligible", 0.0)),
                )
            )

    lines.extend(
        [
            "",
            "## Unlock Projection",
            f"- Status: {projection.get('status', 'missing')}",
            (
                "- Runs with projected unlocks: "
                f"{projection.get('runs_with_projected_unlocks', '?')}; "
                "largest raw single-run projection: "
                f"{projection.get('largest_raw_projected_unlock_count', projection.get('largest_projected_unlock_count', '?'))}."
            ),
        ]
    )
    if pacing:
        lines.append(
            "- Reveal pacing model: {status}, cap {cap}/run; deferred in {runs} runs, "
            "largest deferred {deferred}.".format(
                status=pacing.get("status", "?"),
                cap=pacing.get("reveal_cap_per_run", "?"),
                runs=projection.get("runs_with_projected_deferred_unlocks", "?"),
                deferred=projection.get("largest_projected_deferred_unlock_count", "?"),
            )
        )
    for row in _as_list(projection.get("metrics")):
        best = row.get("best_value")
        best_text = "n/a" if best is None else _fmt(best)
        lines.append(
            "- {id}: best {best} / threshold {threshold}; hits {hits}; "
            "confidence {confidence}; unlocks {unlocks}.".format(
                id=row.get("id", "?"),
                best=best_text,
                threshold=row.get("threshold", "?"),
                hits=row.get("runs_at_threshold", 0),
                confidence=row.get("confidence", "?"),
                unlocks=_join(row.get("unlocks", [])),
            )
        )

    unobservable = _as_list(projection.get("unobservable_metrics"))
    if unobservable:
        lines.append(
            "- Partial metrics: "
            + _join([str(row.get("id", "?")) for row in unobservable])
            + "."
        )

    burst_rows = sorted(
        (_as_dict(row) for row in _as_list(projection.get("runs"))),
        key=lambda row: int(row.get(
            "raw_projected_unlock_count", row.get("projected_unlock_count", 0))),
        reverse=True,
    )[:3]
    lines.extend(["", "## Largest Projected Runs"])
    if burst_rows:
        for row in burst_rows:
            raw_count = row.get(
                "raw_projected_unlock_count", row.get("projected_unlock_count", "?"))
            revealed_count = row.get("projected_revealed_unlock_count", raw_count)
            deferred_count = row.get("projected_deferred_unlock_count", 0)
            revealed_unlocks = row.get(
                "projected_revealed_unlocks", row.get("projected_unlocks", []))
            deferred_unlocks = row.get("projected_deferred_unlocks", [])
            lines.append(
                "- #{idx} {strategy}: raw {raw} unlocks, reveal {revealed}, "
                "defer {deferred}, {outcome} R{rounds}; shown {shown}; deferred {deferred_list}.".format(
                    idx=row.get("idx", "?"),
                    strategy=row.get("strategy", "?"),
                    raw=raw_count,
                    revealed=revealed_count,
                    deferred=deferred_count,
                    outcome="clear" if row.get("won") else "loss",
                    rounds=row.get("rounds_played", "?"),
                    shown=_join(revealed_unlocks),
                    deferred_list=_join(deferred_unlocks),
                )
            )
    else:
        lines.append("- None")

    lines.extend(["", "## Alerts"])
    if alerts:
        for alert in alerts:
            row = _as_dict(alert)
            lines.append(
                f"- {row.get('level', 'info')} {row.get('code', '?')}: "
                f"{row.get('message', '')}"
            )
    else:
        lines.append("- None")

    if errors:
        lines.extend(["", "## Issues"])
        lines.extend(f"- {error}" for error in errors)
    return "\n".join(lines) + "\n"


def _as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _as_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def _join(value: Any) -> str:
    if isinstance(value, list):
        return ", ".join(str(item) for item in value) if value else "none"
    return str(value)


def _count_line(value: Any) -> str:
    rows = _as_list(value)
    if not rows:
        return "none"
    return ", ".join(
        f"{_as_dict(row).get('id', '?')} x{_as_dict(row).get('count', '?')}"
        for row in rows
    )


def _pct(value: Any) -> str:
    try:
        return f"{float(value) * 100:.1f}%"
    except (TypeError, ValueError):
        return "n/a"


def _fmt(value: Any) -> str:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return str(value)
    if number.is_integer():
        return str(int(number))
    return f"{number:.2f}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()

    result = summarize_report(args.report)
    if args.out:
        args.out.write_text(result.markdown, encoding="utf-8")
    else:
        print(result.markdown, end="")
    return 0 if result.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
