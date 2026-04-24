#!/usr/bin/env python3
"""Autoresearch orchestrator for CP formula constants.

Mutates K_RANGE, MS_REF, K_DENSITY, K_LANCHESTER in both preset_generator.gd
and preset_generator.py, runs parity_evaluator.py, logs to experiments.jsonl.
Auto-reverts on REJECT.

This file is the MUTATOR ONLY — it does not score (parity_evaluator.py does).
Separation: agent=mutator, evaluator=scorer, per autoresearch protocol.

Usage:
    python3 godot/sim/cp_formula_research/cp_formula_autoresearch.py [--iterations=100] [--start=N]
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PRESET_GD = ROOT / "godot/sim/preset_generator.gd"
PRESET_PY = ROOT / "scripts/preset_generator.py"
RESEARCH_DIR = ROOT / "godot/sim/cp_formula_research"
EVALUATOR = RESEARCH_DIR / "parity_evaluator.py"
EXPERIMENTS = RESEARCH_DIR / "experiments.jsonl"
BEST_SCORE = RESEARCH_DIR / "best_score.txt"

# Phase 2 Option A: CP = BASE + (atk/as)^α × hp^β × (1+range)^γ × ms^δ
BOUNDS = {
    "FORMULA_BASE":  (0.0, 150.0),
    "FORMULA_ALPHA": (0.0, 1.2),
    "FORMULA_BETA":  (0.0, 1.2),
    "FORMULA_GAMMA": (0.0, 1.5),
    "FORMULA_DELTA": (0.0, 1.5),
}
# Seed from Phase 2 best (known optimum for 3-param subspace).
DEFAULTS = {"FORMULA_BASE": 19.35, "FORMULA_ALPHA": 0.249, "FORMULA_BETA": 0.905,
            "FORMULA_GAMMA": 0.0, "FORMULA_DELTA": 0.0}


# ================================================================
# Constant I/O (patch gd + py files)
# ================================================================


def _read_const(text: str, name: str) -> float | None:
    """Parse `const K_NAME := <float>` from GDScript."""
    m = re.search(rf"const\s+{name}\s*:=\s*([\d.]+)", text)
    return float(m.group(1)) if m else None


def read_gd_constants() -> dict:
    text = PRESET_GD.read_text()
    return {k: _read_const(text, k) for k in BOUNDS}


def _patch_gd_const(text: str, name: str, value: float) -> str:
    return re.sub(
        rf"(const\s+{name}\s*:=\s*)[\d.]+",
        lambda m: f"{m.group(1)}{value}",
        text,
        count=1,
    )


def _patch_py_const(text: str, name: str, value: float) -> str:
    # Python: K_RANGE = 20.0
    return re.sub(
        rf"(^{name}\s*=\s*)[\d.]+",
        lambda m: f"{m.group(1)}{value}",
        text,
        count=1,
        flags=re.MULTILINE,
    )


def apply_constants(constants: dict) -> None:
    gd = PRESET_GD.read_text()
    py = PRESET_PY.read_text()
    for k, v in constants.items():
        gd = _patch_gd_const(gd, k, v)
        py = _patch_py_const(py, k, v)
    PRESET_GD.write_text(gd)
    PRESET_PY.write_text(py)


# ================================================================
# Candidate generation
# ================================================================


def clamp(name: str, v: float) -> float:
    lo, hi = BOUNDS[name]
    return max(lo, min(hi, v))


def random_candidate(rng: random.Random) -> tuple[str, dict]:
    """Phase A: random uniform over bounds."""
    c = {}
    for k, (lo, hi) in BOUNDS.items():
        c[k] = round(rng.uniform(lo, hi), 3)
    hyp = f"random: {c}"
    return hyp, c


def perturb_candidate(rng: random.Random, center: dict, scale: float = 0.15) -> tuple[str, dict]:
    """Phase B/C: Gaussian perturbation around current best."""
    c = {}
    for k, (lo, hi) in BOUNDS.items():
        sigma = (hi - lo) * scale
        c[k] = round(clamp(k, rng.gauss(center[k], sigma)), 3)
    hyp = f"perturb(σ={scale:.2f}) from {center}"
    return hyp, c


def corner_candidate(rng: random.Random) -> tuple[str, dict]:
    """Edge exploration: fix 2 constants to corners, sample other 2."""
    c = dict(DEFAULTS)
    # pick 2 random axes to corner
    axes = list(BOUNDS)
    rng.shuffle(axes)
    corners = axes[:2]
    samples = axes[2:]
    for a in corners:
        lo, hi = BOUNDS[a]
        c[a] = rng.choice([lo, hi])
    for a in samples:
        lo, hi = BOUNDS[a]
        c[a] = round(rng.uniform(lo, hi), 3)
    hyp = f"corner {corners}={[c[a] for a in corners]}, sample {samples}"
    return hyp, c


def generate_candidate(rng: random.Random, n: int, best: dict | None) -> tuple[str, dict]:
    # If we know a prior best, perturb aggressively around it from iter 1.
    # Random/corner exploration is mixed in at low rate for diversity.
    if best is not None:
        # Ensure best has all current BOUNDS keys (pad with DEFAULTS for new dims).
        full_best = {k: best.get(k, DEFAULTS.get(k, 0.0)) for k in BOUNDS}
        r = rng.random()
        if r < 0.15:
            return random_candidate(rng)        # diversity sample
        if r < 0.30:
            return corner_candidate(rng)        # edge exploration
        scale = 0.20 if n % 3 == 0 else 0.10    # mix near/far perturbs
        return perturb_candidate(rng, full_best, scale)

    # No prior best — original phased exploration
    if n <= 30:
        return random_candidate(rng)
    if n <= 60:
        if rng.random() < 0.3:
            return corner_candidate(rng)
        return perturb_candidate(rng, DEFAULTS, scale=0.15)
    scale = 0.10 if rng.random() < 0.7 else 0.20
    return perturb_candidate(rng, DEFAULTS, scale)


# ================================================================
# Evaluator call
# ================================================================


def run_evaluator() -> dict:
    proc = subprocess.run(
        ["python3", str(EVALUATOR)],
        capture_output=True,
        text=True,
        timeout=900,  # 15 min generous (evaluator uses 10 min internal)
    )
    stdout = proc.stdout.strip()
    # Evaluator should emit exactly one JSON to stdout
    try:
        return json.loads(stdout.splitlines()[-1])
    except (json.JSONDecodeError, IndexError) as e:
        return {
            "verdict": "ERROR",
            "error": f"orchestrator JSON parse: {e}\nstdout:\n{stdout[:500]}\nstderr:\n{proc.stderr[-500:]}",
            "returncode": proc.returncode,
        }


# ================================================================
# Logging
# ================================================================


def append_experiment(record: dict) -> None:
    with EXPERIMENTS.open("a") as f:
        f.write(json.dumps(record) + "\n")


def git_sha() -> str:
    try:
        r = subprocess.run(["git", "rev-parse", "--short", "HEAD"],
                           capture_output=True, text=True, cwd=ROOT)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def read_last_n() -> int:
    if not EXPERIMENTS.exists():
        return 0
    n = 0
    with EXPERIMENTS.open() as f:
        for line in f:
            if line.strip():
                n += 1
    return n


def read_best_so_far() -> tuple[dict | None, float]:
    """Return (best constants, best score) scanning experiments.jsonl."""
    if not EXPERIMENTS.exists():
        return None, 0.0
    best_score = -1.0
    best_const = None
    with EXPERIMENTS.open() as f:
        for line in f:
            try:
                r = json.loads(line)
            except json.JSONDecodeError:
                continue
            if r.get("verdict") == "ADOPT":
                s = r.get("metric", 0.0)
                if s > best_score:
                    best_score = s
                    best_const = r.get("constants")
    return best_const, max(best_score, 0.0)


# ================================================================
# Main loop
# ================================================================


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--iterations", type=int, default=100)
    ap.add_argument("--seed", type=int, default=1337)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    start_n = read_last_n()
    best_const, best_score = read_best_so_far()
    consecutive_rejects = 0

    print(f"[autoresearch] start iter={start_n+1}, budget={args.iterations}")
    print(f"[autoresearch] current best: {best_const} score={best_score:.4f}")

    for iteration in range(args.iterations):
        n = start_n + iteration + 1
        if n > start_n + args.iterations:
            break

        hyp, candidate = generate_candidate(rng, n, best_const)
        prev_const = read_gd_constants()

        print(f"\n[iter {n}] hypothesis: {hyp}")
        print(f"[iter {n}] candidate: {candidate}")

        apply_constants(candidate)
        t0 = time.time()
        result = run_evaluator()
        dt = time.time() - t0

        verdict = result.get("verdict", "ERROR")
        metric = result.get("metric", 0.0)
        metrics = result.get("metrics", {})

        record = {
            "ts": datetime.now().isoformat(),
            "n": n,
            "hypothesis": hyp,
            "constants": candidate,
            "verdict": verdict,
            "metric": metric,
            "score_raw": metrics.get("score_raw"),
            "in_band_count": metrics.get("in_band_count"),
            "extreme_count": metrics.get("extreme_count"),
            "max_extreme_tier": metrics.get("max_extreme_tier"),
            "baseline": result.get("baseline"),
            "improvement": result.get("improvement"),
            "guards": result.get("guards", {}),
            "eval_sec": round(dt, 1),
            "sha": git_sha(),
            "reverted": verdict != "ADOPT",
            "error": result.get("error"),
        }

        print(f"[iter {n}] verdict={verdict} metric={metric:.4f} "
              f"in_band={metrics.get('in_band_count', '?')}/36 "
              f"extreme={metrics.get('extreme_count', '?')}/36  ({dt:.1f}s)")

        if verdict == "ADOPT":
            append_experiment(record)
            best_const = candidate
            best_score = metric
            consecutive_rejects = 0
        else:
            # Revert
            apply_constants(prev_const)
            append_experiment(record)
            consecutive_rejects += 1

        if consecutive_rejects >= 20:
            print(f"[autoresearch] TERMINATING — {consecutive_rejects} consecutive rejects")
            break

    print(f"\n[autoresearch] DONE. best score: {best_score:.4f}")
    print(f"[autoresearch] best constants: {best_const}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
