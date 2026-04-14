#!/usr/bin/env python3
"""AI Agent autoresearch — tune ai_params while freezing game balance parameters.

Layer 2 autoresearch: optimizes AI decision parameters (17 Tier 1 knobs)
without modifying game balance. Evaluated by game balance Evaluator (better AI
→ better game outcomes) + AIEvaluator (decision quality diagnostics).

Usage:
    python3 godot/sim/ai_research/ai_autoresearch.py --iterations=20 --strength=0.20

Unlike Layer 1 (godot/sim/autoresearch.py), this has no phase system — all 17
ai_params are in a single searchable tier.
"""

import argparse
import copy
import json
import math
import os
import random
import re
import subprocess
import sys
import time

GODOT_PATH = "/opt/homebrew/bin/godot"
PROJECT_PATH = "godot/"

# Layer 2 paths (separate from Layer 1)
AI_BASELINE_PATH = "godot/sim/ai_research/ai_baseline.json"
AI_BEST_GENOME_PATH = "godot/sim/ai_research/ai_best_genome.json"
AI_TEMP_GENOME_PATH = "godot/sim/ai_research/ai_candidate_genome.json"

# Layer 1 source (frozen game params)
LAYER1_BEST_PATH = "godot/sim/best_genome.json"
LAYER1_DEFAULT_PATH = "godot/sim/default_genome.json"

# AI param defaults and ranges (must match genome.gd)
AI_PARAMS_DEFAULTS = {
    "theme_match_bonus": 15.0,
    "off_theme_penalty": 20.0,
    "merge_imminent_bonus": 30.0,
    "merge_progress_bonus": 8.0,
    "core_card_bonus": 12.0,
    "critical_path_bonus": 8.0,
    "synergy_pair_bonus": 6.0,
    "late_tier_bonus": 6.0,
    "slow_roll_min_round": 5,
    "slow_roll_board_cp_ratio": 1.5,
    "interest_all_start": 4,
    "aggro_transition_round": 10,
    "chain_pair_reroll_bonus": 3,
    "foundation_urgency_rerolls": 5,
    "capstone_urgency_rerolls": 3,
    "bench_sell_threshold": 12.0,
    "arsenal_fuel_bonus": 15.0,
    # Theme state scoring
    "tree_value_per": 2.0,
    "rank_value_per": 3.0,
    "counter_near_bonus": 10.0,
    "unit_cap_penalty": 15.0,
    "theme_state_weight": 1.0,
}

AI_PARAMS_RANGES = {
    "theme_match_bonus": (5.0, 30.0),
    "off_theme_penalty": (5.0, 35.0),
    "merge_imminent_bonus": (15.0, 50.0),
    "merge_progress_bonus": (2.0, 20.0),
    "core_card_bonus": (4.0, 25.0),
    "critical_path_bonus": (2.0, 20.0),
    "synergy_pair_bonus": (2.0, 15.0),
    "late_tier_bonus": (2.0, 15.0),
    "slow_roll_min_round": (3, 8),
    "slow_roll_board_cp_ratio": (0.8, 3.0),
    "interest_all_start": (2, 8),
    "aggro_transition_round": (7, 14),
    "chain_pair_reroll_bonus": (0, 8),
    "foundation_urgency_rerolls": (0, 10),
    "capstone_urgency_rerolls": (0, 8),
    "bench_sell_threshold": (5.0, 25.0),
    "arsenal_fuel_bonus": (5.0, 30.0),
    # Theme state scoring
    "tree_value_per": (0.5, 6.0),
    "rank_value_per": (1.0, 8.0),
    "counter_near_bonus": (3.0, 25.0),
    "unit_cap_penalty": (5.0, 30.0),
    "theme_state_weight": (0.3, 3.0),
}

# Integer params (mutated as ints, not floats)
INT_PARAMS = {
    "slow_roll_min_round", "interest_all_start", "aggro_transition_round",
    "chain_pair_reroll_bonus", "foundation_urgency_rerolls", "capstone_urgency_rerolls",
}


def load_json(path):
    with open(path) as f:
        return json.load(f)


def save_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


def validate_ai_params(ai_params):
    """Validate ai_params against ranges. Returns error string or empty."""
    for k, v in ai_params.items():
        if k not in AI_PARAMS_RANGES:
            return f"Unknown ai_param: {k}"
        lo, hi = AI_PARAMS_RANGES[k]
        if v < lo or v > hi:
            return f"ai_params[{k}] = {v} out of range [{lo}, {hi}]"
    return ""


def mutate_ai_params(genome, strength=0.20):
    """Mutate 1-3 random ai_params within their allowed ranges.

    Strategy: pick a small subset per mutation to avoid high-dimensional noise.
    Integer params are rounded after mutation.
    """
    g = copy.deepcopy(genome)
    ai = g.get("ai_params", copy.deepcopy(AI_PARAMS_DEFAULTS))

    # Ensure all keys present
    for k, v in AI_PARAMS_DEFAULTS.items():
        if k not in ai:
            ai[k] = v

    # Pick 1-3 random params to mutate
    keys = list(AI_PARAMS_RANGES.keys())
    n_mutate = random.choices([1, 2, 3], weights=[0.5, 0.35, 0.15])[0]
    chosen = random.sample(keys, min(n_mutate, len(keys)))

    for k in chosen:
        val = ai[k]
        lo, hi = AI_PARAMS_RANGES[k]
        # Gaussian mutation centered on current value
        sigma = (hi - lo) * strength * 0.5
        new_val = val + random.gauss(0, sigma)
        new_val = max(lo, min(hi, new_val))

        if k in INT_PARAMS:
            new_val = int(round(new_val))

        ai[k] = round(new_val, 2) if k not in INT_PARAMS else new_val

    g["ai_params"] = ai
    return g


def run_batch(genome_path, baseline_path=None, runs=20):
    """Run ai_batch_runner and return parsed result."""
    cmd = [
        GODOT_PATH, "--headless", "--path", PROJECT_PATH,
        "--script", "res://sim/ai_research/ai_batch_runner.gd", "--",
        f"--genome={genome_path.replace('godot/', 'res://')}",
        f"--runs={runs}",
    ]
    if baseline_path:
        cmd.append(f"--baseline={baseline_path.replace('godot/', 'res://')}")

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=1200)
    except subprocess.TimeoutExpired:
        print(" TIMEOUT (1200s)", flush=True)
        return None

    stdout = result.stdout
    stderr = result.stderr

    json_match = re.search(r'\{[\s\S]*\}', stdout)
    if not json_match:
        print(f"  ERROR: No JSON in output. stderr: {stderr[:300]}", file=sys.stderr)
        return None

    try:
        return json.loads(json_match.group())
    except json.JSONDecodeError:
        text = json_match.group()
        depth = 0
        for i, c in enumerate(text):
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    try:
                        return json.loads(text[:i + 1])
                    except json.JSONDecodeError:
                        pass
        print(f"  ERROR: JSON parse failed", file=sys.stderr)
        return None


def format_strategy_summary(stats):
    """Format per-strategy win rates for display."""
    return " ".join(
        f"{s[:2].upper()}{int(v['win_rate']*100):d}"
        for s, v in sorted(stats.items())
    )


def format_ai_quality(ai_scores):
    """Format AI quality axes for display."""
    keys = ["economy_efficiency", "merge_rate", "board_strength_curve", "card_diversity"]
    parts = []
    for k in keys:
        v = ai_scores.get(k, 0.0)
        parts.append(f"{k[:4]}={v:.2f}")
    return " ".join(parts)


def main():
    parser = argparse.ArgumentParser(description="AI Agent parameter optimizer (Layer 2)")
    parser.add_argument("--iterations", type=int, default=20,
                        help="Number of mutation iterations")
    parser.add_argument("--strength", type=float, default=0.20,
                        help="Mutation strength (0.08-0.40)")
    parser.add_argument("--seed", type=int, default=None,
                        help="Random seed for reproducibility")
    parser.add_argument("--runs", type=int, default=20,
                        help="Simulation runs per strategy per iteration")
    parser.add_argument("--init", action="store_true",
                        help="Initialize baseline from current best genome + default ai_params")
    args = parser.parse_args()

    if args.seed is not None:
        random.seed(args.seed)

    # --- Initialization ---
    if args.init or not os.path.exists(AI_BEST_GENOME_PATH):
        print("Initializing AI research from Layer 1 best genome...")
        if os.path.exists(LAYER1_BEST_PATH):
            base = load_json(LAYER1_BEST_PATH)
        else:
            base = load_json(LAYER1_DEFAULT_PATH)

        # Inject default ai_params
        base["ai_params"] = copy.deepcopy(AI_PARAMS_DEFAULTS)
        save_json(AI_BEST_GENOME_PATH, base)
        print(f"  Saved: {AI_BEST_GENOME_PATH}")

        # Generate initial baseline by running evaluation
        print("  Running initial baseline evaluation...")
        save_json(AI_TEMP_GENOME_PATH, base)
        result = run_batch(AI_TEMP_GENOME_PATH, runs=args.runs)
        if result is None:
            print("  ERROR: Failed to generate baseline. Fix and retry with --init.")
            sys.exit(1)
        save_json(AI_BASELINE_PATH, result)
        print(f"  Baseline score: {result['weighted_score']:.4f}")
        print(f"  AI quality: {result.get('ai_quality', {}).get('ai_quality_score', 0.0):.4f}")
        if os.path.exists(AI_TEMP_GENOME_PATH):
            os.remove(AI_TEMP_GENOME_PATH)

        if args.init:
            print("\nInitialization complete. Run without --init to start optimization.")
            return

    # --- Load state ---
    best_genome = load_json(AI_BEST_GENOME_PATH)
    baseline = load_json(AI_BASELINE_PATH)
    best_score = baseline["weighted_score"]
    best_ai_score = baseline.get("ai_quality", {}).get("ai_quality_score", 0.0)

    print(f"Loaded AI best genome: {AI_BEST_GENOME_PATH}")
    print(f"Baseline: game={best_score:.4f}  ai_quality={best_ai_score:.4f}")

    consecutive_rejects = 0
    total_adopts = 0
    strength = args.strength

    print(f"\n{'='*70}")
    print(f"AI AUTORESEARCH — {args.iterations} iterations, strength={strength:.2f}")
    print(f"Mutating: {len(AI_PARAMS_RANGES)} ai_params (game balance frozen)")
    print(f"{'='*70}\n")

    for iteration in range(1, args.iterations + 1):
        # Mutate ai_params only
        candidate = mutate_ai_params(best_genome, strength)

        # Validate
        err = validate_ai_params(candidate.get("ai_params", {}))
        if err:
            print(f"[{iteration:3d}] INVALID: {err}")
            continue

        # Save candidate
        save_json(AI_TEMP_GENOME_PATH, candidate)
        time.sleep(1)

        # Evaluate
        print(f"[{iteration:3d}] Testing ai_params mutation (strength={strength:.2f})...",
              end="", flush=True)
        result = run_batch(AI_TEMP_GENOME_PATH, AI_BASELINE_PATH, runs=args.runs)

        if result is None:
            print(" ERROR — batch runner failed")
            continue

        new_score = result["weighted_score"]
        new_ai_score = result.get("ai_quality", {}).get("ai_quality_score", 0.0)
        delta = new_score - best_score
        ai_delta = new_ai_score - best_ai_score

        # Strategy summary
        stats = result.get("strategy_stats", {})
        wr_summary = format_strategy_summary(stats)

        # AI quality summary
        ai_scores = result.get("ai_quality", {})
        ai_summary = format_ai_quality(ai_scores)

        # ADOPT/REJECT — primary: game balance weighted_score
        # Guard: don't adopt if game score drops (even if AI quality improves)
        if new_score > best_score:
            best_score = new_score
            best_ai_score = new_ai_score
            best_genome = candidate
            save_json(AI_BEST_GENOME_PATH, best_genome)
            save_json(AI_BASELINE_PATH, result)
            consecutive_rejects = 0
            total_adopts += 1

            # Show what params changed
            changed = _diff_ai_params(
                baseline.get("ai_quality", {}),
                candidate.get("ai_params", {}),
                best_genome.get("ai_params", {}))

            print(f" ADOPT game={new_score:.4f}(+{delta:.4f}) "
                  f"ai={new_ai_score:.2f}({ai_delta:+.2f}) [{wr_summary}]")
            print(f"       {ai_summary}")

            if "axis_delta" in result:
                deltas = result["axis_delta"]
                top = sorted(deltas.items(), key=lambda x: abs(x[1]), reverse=True)[:3]
                changes_str = ", ".join(f"{k}:{v:+.3f}" for k, v in top
                                         if k != "weighted_score")
                if changes_str:
                    print(f"       Top deltas: {changes_str}")
        else:
            consecutive_rejects += 1
            print(f" REJECT game={new_score:.4f}({delta:+.4f}) "
                  f"ai={new_ai_score:.2f}({ai_delta:+.2f}) [{wr_summary}]")

        # Adaptive strength
        if consecutive_rejects >= 5:
            strength = min(strength * 1.2, 0.40)
            print(f"       [Widening search: strength -> {strength:.2f}]")
        elif consecutive_rejects == 0 and strength > 0.10:
            strength = max(strength * 0.9, 0.08)

        # Escalation
        if consecutive_rejects >= 20:
            print(f"\n{'!'*70}")
            print(f"ESCALATION: 20 consecutive REJECTs. Stopping for user review.")
            print(f"Current best ai_params:")
            for k, v in sorted(best_genome.get("ai_params", {}).items()):
                default = AI_PARAMS_DEFAULTS.get(k, "?")
                marker = " *" if v != default else ""
                print(f"  {k}: {v}{marker}")
            print(f"{'!'*70}")
            break

    # Summary
    print(f"\n{'='*70}")
    print(f"AI AUTORESEARCH COMPLETE")
    print(f"  Iterations: {iteration}")
    print(f"  ADOPTs: {total_adopts}")
    print(f"  Final game score: {best_score:.4f}")
    print(f"  Final AI quality: {best_ai_score:.4f}")
    print(f"  Best genome: {AI_BEST_GENOME_PATH}")
    print(f"\nOptimized ai_params:")
    for k, v in sorted(best_genome.get("ai_params", {}).items()):
        default = AI_PARAMS_DEFAULTS.get(k, "?")
        marker = " *" if v != default else ""
        print(f"  {k}: {v}{marker}")
    print(f"{'='*70}")

    if os.path.exists(AI_TEMP_GENOME_PATH):
        os.remove(AI_TEMP_GENOME_PATH)


def _diff_ai_params(old_params, new_params, best_params):
    """Show which ai_params changed (for logging)."""
    changed = []
    defaults = AI_PARAMS_DEFAULTS
    for k in defaults:
        old_v = old_params.get(k, defaults[k])
        new_v = new_params.get(k, defaults[k])
        if old_v != new_v:
            changed.append(f"{k}: {old_v}->{new_v}")
    return changed


if __name__ == "__main__":
    main()
