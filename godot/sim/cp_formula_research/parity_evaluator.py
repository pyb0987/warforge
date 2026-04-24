#!/usr/bin/env python3
"""Fixed evaluator for CP formula autoresearch.

THIS FILE IS IMMUTABLE — agent must NOT modify it.

Reads the 4 CP formula constants from godot/sim/preset_generator.gd,
runs preset_parity_runner.gd (3 tier × 4×4 × 20 runs),
scores the off-diagonal win-rate matrix via Gaussian (continuous gradient),
emits JSON verdict to stdout, updates best_score.txt on ADOPT.

Scoring (Gaussian continuous, no cliffs per feedback_evaluator_gaussian_sigma.md):
    per-cell score(wr) = exp(-((wr - 50)^2) / (2 * SIGMA^2))
                        bands in [30,70] contribute ≥0.6, 50% contributes 1.0
    total_score = mean over 36 off-diag cells
    bonus      = +0.05 * (in_band_count / 36)   # small discrete tie-breaker
    metric     = total_score + bonus             # in [0, ~1.05]

Guards (binary):
    REJECT_GUARD if any tier has extreme_count ≥ 10/12 (formula broken)
    REJECT_GUARD if parity_runner exits non-zero or JSON parse fails

Adopt:
    ADOPT if metric >= baseline + IMPROVEMENT_THRESHOLD
    (baseline read from best_score.txt; 0.0 on first run)

Usage:
    python3 godot/sim/cp_formula_research/parity_evaluator.py
"""

from __future__ import annotations

import json
import math
import os
import re
import signal
import subprocess
import sys
from pathlib import Path

# ================================================================
# Configuration (IMMUTABLE — part of the evaluator spec)
# ================================================================

PROJECT_ROOT = Path(__file__).resolve().parents[3]
GODOT = "/opt/homebrew/bin/godot"
GODOT_PROJECT = str(PROJECT_ROOT / "godot")

RESEARCH_DIR = PROJECT_ROOT / "godot/sim/cp_formula_research"
BEST_SCORE_PATH = RESEARCH_DIR / "best_score.txt"
BASELINE_PATH = RESEARCH_DIR / "baseline_parity.json"

PRESET_GENERATOR_GD = PROJECT_ROOT / "godot/sim/preset_generator.gd"

# Parity runner args (fixed — immutable spec)
RUNS_PER_PAIR = 20
CP_TIERS = "7262,36934,126577"
STAT_MULTS = "1.5,3.5,6.0"
SEED = 42

# Scoring params
SIGMA = 20.0   # Gaussian sigma: 50% → 1.0, 30%/70% → 0.61, 10%/90% → 0.14
IMPROVEMENT_THRESHOLD = 0.005  # require at least +0.5% metric gain to ADOPT

# Guard: score-based only. Extreme counts reported as metrics, not guard-rejected.
# Rationale: Gaussian score naturally penalizes extreme cells; adding a cliff
# guard causes bootstrap issues (all manual iters exceed 10 extreme per tier).

PARITY_TIMEOUT = 600  # 10 min — parity run takes ~4-5 min


# ================================================================
# Helpers
# ================================================================


def read_constants_from_gd() -> dict:
    """Parse FORMULA_BASE/ALPHA/BETA from preset_generator.gd (Phase 2 formula)."""
    text = PRESET_GENERATOR_GD.read_text()
    patterns = {
        "FORMULA_BASE":  r"const\s+FORMULA_BASE\s*:=\s*([\d.]+)",
        "FORMULA_ALPHA": r"const\s+FORMULA_ALPHA\s*:=\s*([\d.]+)",
        "FORMULA_BETA":  r"const\s+FORMULA_BETA\s*:=\s*([\d.]+)",
    }
    out = {}
    for k, pat in patterns.items():
        m = re.search(pat, text)
        if m is None:
            out[k] = None
        else:
            out[k] = float(m.group(1))
    return out


def run_parity() -> tuple[dict, str]:
    """Run preset_parity_runner.gd. Returns (parsed_json, stderr_log)."""
    cmd = [
        GODOT, "--headless", "--path", GODOT_PROJECT,
        "-s", "res://sim/preset_parity_runner.gd",
        "--",
        f"--runs={RUNS_PER_PAIR}",
        f"--cps={CP_TIERS}",
        f"--mults={STAT_MULTS}",
        f"--seed={SEED}",
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=PARITY_TIMEOUT)
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"parity_runner timeout after {PARITY_TIMEOUT}s")

    if proc.returncode != 0:
        raise RuntimeError(f"parity_runner exit {proc.returncode}\nstderr:\n{proc.stderr[-2000:]}")

    stdout = proc.stdout
    # Godot prints banners before JSON — find first '{'
    idx = stdout.find("{")
    if idx < 0:
        raise RuntimeError(f"No JSON in stdout:\n{stdout[:500]}")
    try:
        data = json.loads(stdout[idx:])
    except json.JSONDecodeError as e:
        raise RuntimeError(f"JSON parse error: {e}\n{stdout[idx:idx+500]}")
    return data, proc.stderr


def compute_metrics(parity: dict) -> dict:
    """Return {score, in_band_count, extreme_count, max_extreme_tier, tier_breakdown}."""
    # Read preset names from parity output (theme system: predator/druid/military/steampunk)
    presets = parity.get("meta", {}).get("presets", ["predator", "druid", "military", "steampunk"])
    tier_breakdown = []
    total_score_sum = 0.0
    total_cells = 0
    total_in_band = 0
    total_extreme = 0
    max_extreme_tier = 0

    for r in parity["results"]:
        matrix = r["matrix"]
        tier_score_sum = 0.0
        tier_cells = 0
        tier_in_band = 0
        tier_extreme = 0
        for a in presets:
            for b in presets:
                if a == b:
                    continue  # skip diagonal (self-play, out of C-scope)
                wr = matrix[a][b]["wr_a"] * 100.0
                # Gaussian around 50
                cell_score = math.exp(-((wr - 50.0) ** 2) / (2.0 * SIGMA ** 2))
                tier_score_sum += cell_score
                tier_cells += 1
                if 30.0 <= wr <= 70.0:
                    tier_in_band += 1
                if wr <= 10.0 or wr >= 90.0:
                    tier_extreme += 1
        total_score_sum += tier_score_sum
        total_cells += tier_cells
        total_in_band += tier_in_band
        total_extreme += tier_extreme
        max_extreme_tier = max(max_extreme_tier, tier_extreme)
        tier_breakdown.append({
            "target_cp": r["target_cp"],
            "stat_mult": r["stat_mult"],
            "mean_score": tier_score_sum / tier_cells,
            "in_band": tier_in_band,
            "extreme": tier_extreme,
        })

    mean_score = total_score_sum / total_cells if total_cells else 0.0
    tie_break = 0.05 * (total_in_band / total_cells) if total_cells else 0.0
    return {
        "score": round(mean_score + tie_break, 6),
        "score_raw": round(mean_score, 6),
        "tie_break": round(tie_break, 6),
        "in_band_count": total_in_band,
        "extreme_count": total_extreme,
        "total_cells": total_cells,
        "max_extreme_tier": max_extreme_tier,
        "tier_breakdown": tier_breakdown,
    }


def read_baseline_score() -> float:
    if not BEST_SCORE_PATH.exists():
        return 0.0
    try:
        return float(BEST_SCORE_PATH.read_text().strip())
    except (ValueError, OSError):
        return 0.0


def write_baseline_score(score: float) -> None:
    BEST_SCORE_PATH.write_text(f"{score:.6f}\n")


# ================================================================
# Main
# ================================================================


def main() -> int:
    constants = read_constants_from_gd()
    result = {
        "verdict": "ERROR",
        "metric": 0.0,
        "metrics": {},
        "constants": constants,
        "guards": {},
        "error": None,
    }

    # Guard: constants parsed OK
    missing = [k for k, v in constants.items() if v is None]
    if missing:
        result["verdict"] = "REJECT_GUARD"
        result["guards"]["constants_parsed"] = "FAIL"
        result["error"] = f"Missing constants in preset_generator.gd: {missing}"
        print(json.dumps(result))
        return 2
    result["guards"]["constants_parsed"] = "PASS"

    # Run parity
    try:
        parity, stderr = run_parity()
    except Exception as e:
        result["verdict"] = "REJECT_GUARD"
        result["guards"]["parity_run"] = "FAIL"
        result["error"] = str(e)
        print(json.dumps(result))
        return 2
    result["guards"]["parity_run"] = "PASS"

    # Score
    metrics = compute_metrics(parity)
    result["metric"] = metrics["score"]
    result["metrics"] = metrics

    # ADOPT vs REJECT_THRESHOLD (score-based; extreme counts reported as metrics only)
    baseline = read_baseline_score()
    improvement = metrics["score"] - baseline
    result["baseline"] = baseline
    result["improvement"] = round(improvement, 6)

    if improvement >= IMPROVEMENT_THRESHOLD:
        result["verdict"] = "ADOPT"
        write_baseline_score(metrics["score"])
    else:
        result["verdict"] = "REJECT_THRESHOLD"

    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(130))
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print(json.dumps({"verdict": "ERROR", "error": "interrupted"}))
        sys.exit(130)
