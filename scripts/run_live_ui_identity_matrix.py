#!/usr/bin/env python3
"""Run the live UI smoke report across curated commander/talisman identities."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

import summarize_live_ui_report

SCHEMA = "warforge-live-ui-identity-matrix/v1"
REPORT_SCENE = "res://tools/live_ui_smoke_report.tscn"
REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROJECT_PATH = REPO_ROOT / "godot"
DEFAULT_OUTPUT_DIR = Path(tempfile.gettempdir()) / "warforge_live_ui_identity_matrix"
DEFAULT_TIMEOUT_SEC = 180
DEFAULT_IDENTITIES = (
    "baseline=gambler:flint",
    "coin=gambler:two_faced_coin",
    "golden_die=gambler:golden_die",
    "locked_economy=alchemist:soul_jar",
)
EXPANDED_IDENTITIES = (
    "breeder=breeder:cracked_egg",
    "collector=collector:glass_eye",
    "strategist=strategist:war_drum",
    "smith=smith:rusty_wrench",
    "raider=raider:mercury_drop",
)
PRESET_IDENTITIES = {
    "default": DEFAULT_IDENTITIES,
    "expanded": EXPANDED_IDENTITIES,
}


@dataclass(frozen=True)
class IdentityCase:
    label: str
    commander: str
    talisman: str


def parse_identity(value: str) -> IdentityCase:
    raw = value.strip()
    if not raw:
        raise ValueError("identity cannot be empty")
    if "=" in raw:
        label, pair = raw.split("=", 1)
        label = _slug(label)
    else:
        label = ""
        pair = raw
    if ":" not in pair:
        raise ValueError("identity must be commander:talisman or label=commander:talisman")
    commander, talisman = (part.strip() for part in pair.split(":", 1))
    if not commander or not talisman:
        raise ValueError("identity must include both commander and talisman")
    commander = _slug(commander)
    talisman = _slug(talisman)
    if not label:
        label = _slug(f"{commander}_{talisman}")
    return IdentityCase(label=label, commander=commander, talisman=talisman)


def default_identities() -> list[IdentityCase]:
    return [parse_identity(value) for value in DEFAULT_IDENTITIES]


def preset_identities(preset: str) -> list[IdentityCase]:
    if preset not in PRESET_IDENTITIES:
        choices = ", ".join(sorted(PRESET_IDENTITIES))
        raise ValueError(f"unknown preset {preset!r}; choose one of: {choices}")
    return [parse_identity(value) for value in PRESET_IDENTITIES[preset]]


def run_matrix(
    identities: list[IdentityCase],
    output_dir: Path,
    *,
    godot_bin: str = "godot",
    project_path: Path = DEFAULT_PROJECT_PATH,
    timeout_sec: int = DEFAULT_TIMEOUT_SEC,
    unlock_selected: bool = True,
    preset: str = "custom",
    run_command: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
    summarize_func: Callable[..., summarize_live_ui_report.SummaryResult]
        = summarize_live_ui_report.summarize_report,
) -> dict[str, Any]:
    errors = _validate_identities(identities)
    output_dir.mkdir(parents=True, exist_ok=True)
    if errors:
        return {
            "schema": SCHEMA,
            "ok": False,
            "metadata": _metadata(output_dir, godot_bin, project_path, timeout_sec,
                unlock_selected, preset),
            "identities": [],
            "errors": errors,
        }

    rows: list[dict[str, Any]] = []
    for identity in identities:
        rows.append(_run_identity(
            identity,
            output_dir,
            godot_bin=godot_bin,
            project_path=project_path,
            timeout_sec=timeout_sec,
            unlock_selected=unlock_selected,
            run_command=run_command,
            summarize_func=summarize_func,
        ))

    matrix_errors: list[str] = []
    for row in rows:
        if row.get("ok") is not True:
            matrix_errors.append(
                "%s failed: %s" % (
                    row.get("label", "unknown"),
                    "; ".join(str(error) for error in row.get("errors", []))
                    or "unknown error",
                )
            )

    return {
        "schema": SCHEMA,
        "ok": not matrix_errors,
        "metadata": _metadata(output_dir, godot_bin, project_path, timeout_sec,
            unlock_selected, preset),
        "identities": rows,
        "errors": matrix_errors,
    }


def render_matrix_summary(matrix: dict[str, Any]) -> str:
    rows = _as_list(matrix.get("identities"))
    passing = sum(1 for row in rows if isinstance(row, dict) and row.get("ok") is True)
    lines = [
        "# Warforge Live UI Identity Matrix",
        "",
        f"Verdict: {'PASS' if matrix.get('ok') is True else 'INCOMPLETE'}",
        f"Schema: `{matrix.get('schema', '')}`",
        f"Preset: `{matrix.get('metadata', {}).get('preset', 'unknown')}`",
        f"Passing identities: {passing}/{len(rows)}",
        "",
        "## Identities",
    ]
    if not rows:
        lines.append("- None")
    for row in rows:
        if not isinstance(row, dict):
            continue
        status = "PASS" if row.get("ok") is True else "FAIL"
        commander = _name_or_id(row, "commander_name", "commander")
        talisman = _name_or_id(row, "talisman_name", "talisman")
        lines.append(
            "- {status} `{label}`: {commander} + {talisman}; setup {setup}; "
            "report `{report}`.".format(
                status=status,
                label=row.get("label", "?"),
                commander=commander,
                talisman=talisman,
                setup=row.get("selected_identity_setup", "unknown"),
                report=row.get("report_path", ""),
            )
        )

    lines.extend(["", "## Issues"])
    errors = _as_list(matrix.get("errors"))
    if errors:
        lines.extend(f"- ERROR: {error}" for error in errors)
    else:
        lines.append("- None")
    return "\n".join(lines) + "\n"


def _run_identity(
    identity: IdentityCase,
    output_dir: Path,
    *,
    godot_bin: str,
    project_path: Path,
    timeout_sec: int,
    unlock_selected: bool,
    run_command: Callable[..., subprocess.CompletedProcess[str]],
    summarize_func: Callable[..., summarize_live_ui_report.SummaryResult],
) -> dict[str, Any]:
    case_dir = output_dir / identity.label
    case_dir.mkdir(parents=True, exist_ok=True)
    report_path = case_dir / "report.json"
    summary_path = case_dir / "summary.md"
    log_path = case_dir / "godot.log"
    home_dir = case_dir / "godot_home"
    home_dir.mkdir(parents=True, exist_ok=True)

    cmd = [
        godot_bin,
        "--headless",
        "--log-file",
        str(log_path),
        "--path",
        str(project_path),
        REPORT_SCENE,
        "--",
        f"--out={report_path}",
        f"--commander={identity.commander}",
        f"--talisman={identity.talisman}",
        f"--unlock-selected={_bool_text(unlock_selected)}",
        "--reset-meta=true",
        f"--meta-path=user://live_ui_matrix_{identity.label}.cfg",
    ]
    env = os.environ.copy()
    env["HOME"] = str(home_dir)

    errors: list[str] = []
    warnings: list[str] = []
    returncode = -1
    stdout_tail = ""
    stderr_tail = ""
    try:
        completed = run_command(
            cmd,
            cwd=str(REPO_ROOT),
            env=env,
            capture_output=True,
            text=True,
            timeout=timeout_sec,
        )
        returncode = completed.returncode
        stdout_tail = _tail(completed.stdout)
        stderr_tail = _tail(completed.stderr)
        if completed.returncode != 0:
            errors.append(f"live UI report exited {completed.returncode}")
    except FileNotFoundError as exc:
        errors.append(f"failed to launch Godot: {exc}")
    except subprocess.TimeoutExpired as exc:
        errors.append(f"live UI report timed out after {timeout_sec}s")
        stdout_tail = _tail(exc.stdout)
        stderr_tail = _tail(exc.stderr)

    report_metadata: dict[str, Any] = {}
    if report_path.exists():
        report_metadata = _load_report_metadata(report_path, errors)
        summary = summarize_func(report_path)
        summary_path.write_text(summary.markdown, encoding="utf-8")
        if summary.ok is not True:
            errors.extend(summary.errors)
        warnings.extend(summary.warnings)
    else:
        errors.append(f"report was not written: {report_path}")

    row = {
        "label": identity.label,
        "ok": not errors,
        "commander": identity.commander,
        "talisman": identity.talisman,
        "commander_name": report_metadata.get("commander_name", ""),
        "talisman_name": report_metadata.get("talisman_name", ""),
        "selected_identity_setup": _selected_identity_setup_line(report_metadata),
        "returncode": returncode,
        "report_path": str(report_path),
        "summary_path": str(summary_path) if summary_path.exists() else "",
        "log_path": str(log_path),
        "home_dir": str(home_dir),
        "errors": errors,
        "warnings": warnings,
        "stdout_tail": stdout_tail,
        "stderr_tail": stderr_tail,
    }
    return row


def _metadata(
    output_dir: Path,
    godot_bin: str,
    project_path: Path,
    timeout_sec: int,
    unlock_selected: bool,
    preset: str,
) -> dict[str, Any]:
    return {
        "output_dir": str(output_dir),
        "godot_bin": godot_bin,
        "project_path": str(project_path),
        "timeout_sec": timeout_sec,
        "unlock_selected": unlock_selected,
        "preset": preset,
    }


def _validate_identities(identities: list[IdentityCase]) -> list[str]:
    errors: list[str] = []
    if not identities:
        errors.append("at least one identity is required")
        return errors
    seen: set[str] = set()
    for identity in identities:
        if identity.label in seen:
            errors.append(f"duplicate identity label: {identity.label}")
        seen.add(identity.label)
    return errors


def _load_report_metadata(path: Path, errors: list[str]) -> dict[str, Any]:
    try:
        report = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"failed to read report metadata {path}: {exc}")
        return {}
    metadata = report.get("metadata")
    return metadata if isinstance(metadata, dict) else {}


def _selected_identity_setup_line(metadata: dict[str, Any]) -> str:
    if metadata.get("unlock_selected") is not True:
        return "normal profile"
    commanders = ", ".join(
        str(value) for value in _as_list(metadata.get("preunlocked_selected_commanders"))
    )
    talismans = ", ".join(
        str(value) for value in _as_list(metadata.get("preunlocked_selected_talismans"))
    )
    parts: list[str] = []
    if commanders:
        parts.append(f"commanders {commanders}")
    if talismans:
        parts.append(f"talismans {talismans}")
    unlocked = "; ".join(parts) if parts else "requested identity was already unlocked"
    return f"unlock-selected profile ({unlocked})"


def _slug(value: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9_]+", "_", value.strip()).strip("_").lower()
    if not slug:
        raise ValueError(f"invalid slug value: {value!r}")
    return slug


def _bool_text(value: bool) -> str:
    return "true" if value else "false"


def _tail(value: Any, max_lines: int = 12) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        value = value.decode("utf-8", errors="replace")
    lines = str(value).splitlines()
    return "\n".join(lines[-max_lines:])


def _name_or_id(row: dict[str, Any], name_key: str, id_key: str) -> str:
    name = str(row.get(name_key, "")).strip()
    if name:
        return name
    return str(row.get(id_key, "")).strip() or "unknown"


def _as_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def _parse_identity_arg(value: str) -> IdentityCase:
    try:
        return parse_identity(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(str(exc)) from exc


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--identity",
        action="append",
        type=_parse_identity_arg,
        help=(
            "identity to run as commander:talisman or label=commander:talisman. "
            "May be repeated; replaces the selected preset."
        ),
    )
    parser.add_argument(
        "--preset",
        choices=sorted(PRESET_IDENTITIES),
        default="default",
        help="named identity matrix to run when --identity is omitted",
    )
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--summary-out", type=Path)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--project-path", type=Path, default=DEFAULT_PROJECT_PATH)
    parser.add_argument("--timeout-sec", type=int, default=DEFAULT_TIMEOUT_SEC)
    parser.add_argument(
        "--unlock-selected",
        choices=("true", "false"),
        default="true",
        help="preunlock selected locked identities before exercising selection UI",
    )
    args = parser.parse_args(argv)

    preset_name = "custom" if args.identity else args.preset
    identities = args.identity if args.identity else preset_identities(args.preset)
    matrix = run_matrix(
        identities,
        args.output_dir,
        godot_bin=args.godot,
        project_path=args.project_path,
        timeout_sec=args.timeout_sec,
        unlock_selected=args.unlock_selected == "true",
        preset=preset_name,
    )
    summary = render_matrix_summary(matrix)

    out_path = args.out or args.output_dir / "matrix.json"
    summary_path = args.summary_out or args.output_dir / "matrix.md"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(matrix, indent=2, ensure_ascii=False), encoding="utf-8")
    summary_path.write_text(summary, encoding="utf-8")
    print(summary)
    return 0 if matrix.get("ok") is True else 1


if __name__ == "__main__":
    sys.exit(main())
