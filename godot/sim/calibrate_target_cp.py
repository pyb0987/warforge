#!/usr/bin/env python3
"""Calibrate target_cp_per_round to match target_wr_curve.json.

Two-step evaluator foundation (2026-04-22):
  Step 1 (THIS FILE): derive per-round target WR from design curve,
                      then adjust target_cp[r] so measured_wr[r] ≈ target_wr[r].
  Step 2 (autoresearch): mutate economy/shop/etc; per-round WR match replaces
                         WIN_RATE_TARGET + ARC_SEGMENTS as the fitness signal.

Usage:
    # Standalone (manual calibration of a genome):
    python3 godot/sim/calibrate_target_cp.py \
        --genome godot/sim/best_genome.json \
        --curve godot/sim/target_wr_curve.json \
        --output godot/sim/best_genome.json

    # Integration (inner loop): import calibrate() directly.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import re
import subprocess
import sys
from typing import Sequence

GODOT_PATH = "/opt/homebrew/bin/godot"
PROJECT_PATH = "godot/"

# ================================================================
# Math layer (no simulation required — unit-testable)
# ================================================================


def derive_target_survival(anchors: dict) -> list[float]:
    """Expand anchor points into per-round cumulative survival P(reached_r).

    Returns 15 floats for R1..R15. anchors["values"][0] must be 1.0 at round 0.
    Geometric interpolation: constant per-round clear rate within each segment.
    """
    rounds = anchors["rounds"]
    values = anchors["values"]
    assert len(rounds) == len(values) >= 2, "Need >=2 anchors"
    assert rounds[0] == 0, "First anchor must be round 0"
    assert values[0] == 1.0, "First anchor value must be 1.0 (all runs start)"
    for i in range(1, len(rounds)):
        assert rounds[i] > rounds[i - 1], "Anchor rounds must be increasing"
        assert 0.0 < values[i] <= values[i - 1], "Survival must be non-increasing, positive"

    survival = [0.0] * 16  # index 0..15
    survival[0] = 1.0
    for seg in range(len(rounds) - 1):
        r_start = rounds[seg]
        r_end = rounds[seg + 1]
        v_start = values[seg]
        v_end = values[seg + 1]
        per_round_clear = (v_end / v_start) ** (1.0 / (r_end - r_start))
        for r in range(r_start + 1, r_end + 1):
            survival[r] = survival[r - 1] * per_round_clear
    return survival[1:]  # R1..R15


def derive_target_wr(survival: Sequence[float]) -> list[float]:
    """Convert cumulative survival to per-round clear rate.

    target_wr[r] = P(clear_r | reached_r) = survival[r] / survival[r-1].
    Conditional on reaching round r, this is the probability of clearing it.
    """
    assert len(survival) == 15
    wr = []
    prev = 1.0
    for s in survival:
        wr.append(s / prev if prev > 0 else 0.0)
        prev = s
    return wr


# ================================================================
# Simulation layer (requires godot)
# ================================================================


def run_batch(genome_path: str, runs: int = 20) -> dict | None:
    """Run calibration_runner.gd (lightweight — no evaluator, just per-round WR)."""
    cmd = [
        GODOT_PATH, "--headless", "--path", PROJECT_PATH,
        "--script", "res://sim/calibration_runner.gd", "--",
        f"--genome={genome_path.replace('godot/', 'res://')}", f"--runs={runs}",
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    except subprocess.TimeoutExpired:
        print("  TIMEOUT (900s)", file=sys.stderr)
        return None
    m = re.search(r"\{[\s\S]*\}", proc.stdout)
    if not m:
        print(f"  ERROR: no JSON in stdout. stderr: {proc.stderr[:200]}", file=sys.stderr)
        return None
    text = m.group()
    depth = 0
    for i, c in enumerate(text):
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                try:
                    return json.loads(text[: i + 1])
                except json.JSONDecodeError as e:
                    print(f"  ERROR: JSON parse: {e}", file=sys.stderr)
                    return None
    return None


def measure_per_round_wr(batch_result: dict) -> list[float]:
    """Extract per-round WR from batch_runner output.

    Expected structure: result["per_round"] = [{"round": 1, "win_rate": 0.92}, ...]
    Falls back to aggregating round_data across all runs if per_round absent.
    """
    if "per_round_wr" in batch_result:
        return list(batch_result["per_round_wr"])

    # Fallback: aggregate from per-run round_data
    wins = [0] * 15
    totals = [0] * 15
    for run in batch_result.get("results", []):
        for rd in run.get("round_data", []):
            r = rd.get("round_num", 0) - 1
            if 0 <= r < 15:
                totals[r] += 1
                if rd.get("battle_won"):
                    wins[r] += 1
    return [wins[i] / totals[i] if totals[i] > 0 else 0.0 for i in range(15)]


# ================================================================
# Calibration loop
# ================================================================

# Segment-based tolerances (pp). Noise floor from binomial SE at typical n:
#   early (n≈140): SE~2.5pp, tol 5pp = 2σ
#   mid   (n≈80):  SE~5pp,   tol 8pp ≈ 1.6σ
#   late  (n≈30):  SE~9pp,   tol 12pp ≈ 1.3σ
# Tighter tolerances are mathematically unreachable at runs=20.
SEGMENT_TOLERANCES_PP = {
    "early": 5.0,  # R1-R8
    "mid":   8.0,  # R9-R12
    "late": 12.0,  # R13-R15
}
MOVING_AVG_WINDOW = 3  # iters


def _segment_of(r: int) -> str:
    """0-indexed round → segment name."""
    if r < 8:
        return "early"
    if r < 12:
        return "mid"
    return "late"


def _check_segment_convergence(
    per_round_errors: Sequence[float],
    totals: Sequence[int],
    min_samples: int,
) -> tuple[bool, dict[str, float]]:
    """Check if per-segment max error is within that segment's tolerance.

    Returns (converged, {segment: max_err_pp})
    """
    seg_max: dict[str, float] = {}
    for r in range(15):
        if totals[r] < min_samples:
            continue
        seg = _segment_of(r)
        err_pp = per_round_errors[r] * 100.0
        seg_max[seg] = max(seg_max.get(seg, 0.0), err_pp)

    converged = True
    for seg, tol_pp in SEGMENT_TOLERANCES_PP.items():
        if seg in seg_max and seg_max[seg] > tol_pp:
            converged = False
    return converged, seg_max


def calibrate(
    genome: dict,
    target_wr: Sequence[float],
    max_iter: int = 8,
    runs: int = 20,
    cp_range: tuple[float, float] = (100.0, 500000.0),
    adjust_exponent: float = 0.7,
    min_samples: int = 10,
    tmp_path: str = "godot/sim/_calibrate_tmp.json",
    verbose: bool = True,
) -> tuple[dict, dict]:
    """Iteratively adjust genome["target_cp_per_round"] to match target_wr.

    Algorithm:
      Per iteration:
        1. Snapshot current genome, run batch → actual_wr[r], totals[r]
        2. For each round with totals[r] >= min_samples:
             ratio = actual_wr[r] / target_wr[r]  (clamped to [0.2, 5.0])
             target_cp[r] *= ratio ** adjust_exponent
        3. Clamp to cp_range + enforce monotonic non-decreasing
        4. Track best iter (by instantaneous max_err); save genome snapshot.

      Stop conditions (whichever first):
        - Segment-based convergence on moving average of last 3 iters
          (early≤5pp, mid≤8pp, late≤12pp)
        - max_iter reached

      Return: genome snapshot from the best iter (lowest max_err seen),
              not the final iter (which may have oscillated).

    Returns: (best_genome, diag)
      diag: {
        "iterations": int,              # actual iterations run
        "best_iter": int,               # iter with lowest instant max_err
        "best_max_err_pp": float,       # that iter's instantaneous error
        "best_actual_wr": [15 floats],  # measured WR at best iter
        "final_segment_errors_pp": {"early": float, "mid": float, "late": float},
        "target_wr": [15 floats],
        "per_round_totals": [15 ints],  # from last iter
        "converged": bool,              # moving-avg convergence hit
        "err_history": [[15 floats], …] # per-iter per-round errors
      }
    """
    g = copy.deepcopy(genome)
    assert len(g.get("target_cp_per_round", [])) == 15, "genome missing target_cp_per_round[15]"

    best_genome: dict | None = None
    best_actual_wr: list[float] = []
    best_max_err = float("inf")
    best_iter = 0

    err_history: list[list[float]] = []  # one list[15] per iter
    totals: list[int] = [0] * 15
    converged = False

    for it in range(1, max_iter + 1):
        # Snapshot genome that WILL produce this iter's measurement
        snapshot = copy.deepcopy(g)
        with open(tmp_path, "w") as f:
            json.dump(snapshot, f, indent=2)

        result = run_batch(tmp_path, runs=runs)
        if result is None:
            raise RuntimeError(f"calibration iter {it}: batch run failed")

        actual_wr = measure_per_round_wr(result)
        totals = result.get("per_round_totals", [runs * 4] * 15)

        per_round_err = [abs(actual_wr[r] - target_wr[r]) for r in range(15)]
        err_history.append(per_round_err)

        # Instantaneous max error (only rounds with signal)
        signal_rounds = [r for r in range(15) if totals[r] >= min_samples]
        if not signal_rounds:
            raise RuntimeError(f"iter {it}: no rounds met min_samples={min_samples}")
        inst_max_err = max(per_round_err[r] for r in signal_rounds)

        # Track best iter (save the genome that PRODUCED this measurement)
        if inst_max_err < best_max_err:
            best_max_err = inst_max_err
            best_genome = snapshot
            best_actual_wr = list(actual_wr)
            best_iter = it

        # Moving average error over last N iters (per round)
        window = err_history[-MOVING_AVG_WINDOW:]
        avg_err = [sum(w[r] for w in window) / len(window) for r in range(15)]

        seg_converged, seg_maxes = _check_segment_convergence(avg_err, totals, min_samples)

        if verbose:
            summary = " ".join(
                f"R{r+1}:{int(actual_wr[r]*100):02d}/n{totals[r]:02d}({'+' if actual_wr[r]>=target_wr[r] else '-'}{int(abs(actual_wr[r]-target_wr[r])*100):02d})"
                for r in range(15)
            )
            seg_str = " ".join(f"{s}:{seg_maxes.get(s, 0.0):.1f}" for s in ["early", "mid", "late"])
            print(f"[cal {it}/{max_iter}] inst_max={inst_max_err*100:.1f}pp  avg3[{seg_str}]pp  {summary}")

        # Stop on moving-avg segment convergence (requires >= window iters)
        if len(err_history) >= MOVING_AVG_WINDOW and seg_converged:
            converged = True
            break

        # Adjust target_cp per round (only rounds with sufficient samples)
        new_cp = list(g["target_cp_per_round"])
        for r in range(15):
            if target_wr[r] <= 0.001:
                continue
            if totals[r] < min_samples:
                continue
            ratio = actual_wr[r] / target_wr[r]
            ratio = max(0.2, min(5.0, ratio))
            new_cp[r] = new_cp[r] * (ratio ** adjust_exponent)

        for r in range(15):
            new_cp[r] = max(cp_range[0], min(cp_range[1], new_cp[r]))
        for r in range(1, 15):
            if new_cp[r] < new_cp[r - 1]:
                new_cp[r] = new_cp[r - 1]
        g["target_cp_per_round"] = [round(v, 2) for v in new_cp]

    if os.path.exists(tmp_path):
        os.remove(tmp_path)

    # Final segment errors (moving average at last iter)
    window = err_history[-MOVING_AVG_WINDOW:]
    avg_err = [sum(w[r] for w in window) / len(window) for r in range(15)]
    _, final_seg_maxes = _check_segment_convergence(avg_err, totals, min_samples)

    diag = {
        "iterations": it,
        "best_iter": best_iter,
        "best_max_err_pp": best_max_err * 100,
        "best_actual_wr": best_actual_wr,
        "final_segment_errors_pp": final_seg_maxes,
        "target_wr": list(target_wr),
        "per_round_totals": totals,
        "converged": converged,
        "err_history": err_history,
    }
    return best_genome if best_genome is not None else g, diag


# ================================================================
# CLI
# ================================================================


def main():
    parser = argparse.ArgumentParser(description="Calibrate target_cp to match survival curve")
    parser.add_argument("--genome", required=True, help="input genome JSON path")
    parser.add_argument("--curve", required=True, help="target_wr_curve.json path")
    parser.add_argument("--output", required=True, help="output genome JSON path")
    parser.add_argument("--runs", type=int, default=20)
    parser.add_argument("--max-iter", type=int, default=8)
    parser.add_argument("--dry-run-math", action="store_true",
                        help="only compute target_wr from curve, no simulation")
    args = parser.parse_args()

    with open(args.curve) as f:
        curve = json.load(f)
    target_survival = derive_target_survival(curve["survival_anchors"])
    target_wr = derive_target_wr(target_survival)

    print("=" * 64)
    print("Design curve → target WR per round")
    print("=" * 64)
    for r in range(15):
        tag = " (boss)" if (r + 1) in (4, 8, 12, 15) else ""
        print(f"  R{r+1:2d}: survival={target_survival[r]:.3f}  target_wr={target_wr[r]*100:5.1f}%{tag}")

    if args.dry_run_math:
        return

    with open(args.genome) as f:
        genome = json.load(f)

    calibrated, diag = calibrate(
        genome, target_wr,
        max_iter=args.max_iter,
        runs=args.runs,
    )

    with open(args.output, "w") as f:
        json.dump(calibrated, f, indent=2)

    print("=" * 64)
    status = "CONVERGED" if diag["converged"] else "MAX_ITER"
    print(f"Calibration {status} after {diag['iterations']} iter (best iter: {diag['best_iter']})")
    print(f"Best iter instantaneous max err: {diag['best_max_err_pp']:.1f}pp")
    seg = diag["final_segment_errors_pp"]
    print(f"Final moving-avg (3-iter) segment errors:")
    for s in ["early", "mid", "late"]:
        tol = SEGMENT_TOLERANCES_PP[s]
        marker = "✓" if seg.get(s, 0.0) <= tol else "✗"
        print(f"  {s:6} (tol {tol:4.1f}pp): {seg.get(s, 0.0):5.1f}pp {marker}")
    print(f"Saved best-iter genome → {args.output}")
    print("=" * 64)


if __name__ == "__main__":
    main()
