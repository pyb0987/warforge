#!/usr/bin/env python3
"""
analyze_card_coverage.py — Decompose card coverage from sim runs.

Reads `dump_coverage.gd` output (140 runs × purchase_log + final_deck) and
classifies each card in the 68-card pool by appearance frequency.

Usage:
    godot --headless --path godot/ -s sim/dump_coverage.gd -- --out=/tmp/coverage.json
    python3 scripts/analyze_card_coverage.py /tmp/coverage.json

Classification thresholds (per backlog B-3 spec):
    dead   : appearance_rate < 0.05  (carded < 7 of 140 runs)
    weak   : 0.05 <= rate < 0.15
    active : rate >= 0.15
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
CARDS_DIR = ROOT / "data" / "cards"

# 13 cards added in commit 0fd2d5e (2026-04-25 pool expansion 55→68).
NEW_13 = {
    # Neutral 9
    "ne_pawnbroker", "ne_envoy", "ne_hoarder", "ne_legion", "ne_masquerade",
    "ne_void_force", "ne_fusion_end", "ne_council", "ne_nexus",
    # Theme 4
    "sp_global_workshop", "dr_resonance", "pr_parasitic_swarm", "ml_alliance",
}


def load_card_pool() -> dict[str, dict]:
    """Return {card_id: {tier, theme}} for all 68 cards."""
    pool = {}
    for theme_file in ["neutral", "steampunk", "druid", "predator", "military"]:
        with open(CARDS_DIR / f"{theme_file}.yaml") as fh:
            data = yaml.safe_load(fh)
        for cid, cdata in data["cards"].items():
            pool[cid] = {
                "tier": cdata.get("tier", 0),
                "theme": cdata.get("theme", theme_file),
                "name": cdata.get("name", cid),
            }
    return pool


def classify(rate: float) -> str:
    if rate < 0.05:
        return "dead"
    if rate < 0.15:
        return "weak"
    return "active"


def analyze(coverage_path: Path) -> dict:
    pool = load_card_pool()
    with open(coverage_path) as fh:
        data = json.load(fh)
    runs = data["runs"]
    n_runs = len(runs)

    # Per-card aggregates (overall)
    appears_in_purchase: Counter = Counter()
    total_purchases: Counter = Counter()
    appears_in_final: Counter = Counter()

    # Per-strategy splits
    per_strategy: dict[str, dict] = defaultdict(
        lambda: {"runs": 0, "purchase_seen": Counter(), "final_seen": Counter()}
    )

    for run in runs:
        strat = run["strategy"]
        per_strategy[strat]["runs"] += 1

        purchases = run["purchase_log"]
        seen_in_run = set(purchases)
        for cid in seen_in_run:
            appears_in_purchase[cid] += 1
            per_strategy[strat]["purchase_seen"][cid] += 1
        for cid in purchases:
            total_purchases[cid] += 1

        final_seen = {entry["card_id"] for entry in run["final_deck"]}
        for cid in final_seen:
            appears_in_final[cid] += 1
            per_strategy[strat]["final_seen"][cid] += 1

    # Build per-card report
    rows = []
    for cid, meta in pool.items():
        purchase_runs = appears_in_purchase[cid]
        final_runs = appears_in_final[cid]
        purchase_rate = purchase_runs / n_runs
        final_rate = final_runs / n_runs
        rows.append({
            "card_id": cid,
            "tier": meta["tier"],
            "theme": meta["theme"],
            "name": meta["name"],
            "is_new_13": cid in NEW_13,
            "purchase_runs": purchase_runs,
            "purchase_rate": purchase_rate,
            "total_purchases": total_purchases[cid],
            "avg_purchases_per_run": total_purchases[cid] / n_runs,
            "final_deck_runs": final_runs,
            "final_deck_rate": final_rate,
            "class": classify(purchase_rate),
        })

    # Per-strategy zero-coverage report (cards never bought by that strategy)
    strategy_zero: dict[str, list[str]] = {}
    for strat, sd in per_strategy.items():
        zeros = sorted([cid for cid in pool if sd["purchase_seen"][cid] == 0])
        strategy_zero[strat] = zeros

    # Reproduce evaluator.gd::_eval_card_coverage:
    #   for each of 4 themes (steampunk, druid, predator, military):
    #       theme_coverage = mean(usage_rate over theme's cards)
    #       where usage_rate = (final_deck OR purchase_log) appearance / total_runs
    #   card_coverage = min(theme_coverages)
    seen_per_run: dict[str, set] = {}
    for i, run in enumerate(runs):
        seen = set(run["purchase_log"])
        for entry in run["final_deck"]:
            seen.add(entry["card_id"])
        seen_per_run[i] = seen
    card_runs: Counter = Counter()
    for s in seen_per_run.values():
        for cid in s:
            card_runs[cid] += 1
    theme_coverages: dict[str, float] = {}
    for theme in ["steampunk", "druid", "predator", "military"]:
        theme_ids = [cid for cid, m in pool.items() if m["theme"] == theme]
        if not theme_ids:
            continue
        rate_sum = sum(card_runs[cid] / n_runs for cid in theme_ids)
        theme_coverages[theme] = rate_sum / len(theme_ids)
    eval_card_coverage = min(theme_coverages.values()) if theme_coverages else 0.0

    return {
        "n_runs": n_runs,
        "n_strategies": len(per_strategy),
        "per_card": rows,
        "per_strategy_runs": {s: per_strategy[s]["runs"] for s in per_strategy},
        "per_strategy_zero_cards": strategy_zero,
        "per_strategy_purchase_rate": {
            s: {
                cid: per_strategy[s]["purchase_seen"][cid] / per_strategy[s]["runs"]
                for cid in pool
            }
            for s in per_strategy
        },
        "evaluator_card_coverage": eval_card_coverage,
        "theme_coverages": theme_coverages,
    }


def fmt_pct(x: float) -> str:
    return f"{x*100:5.1f}%"


def print_report(result: dict, *, top_dead: int | None = None) -> None:
    rows = sorted(result["per_card"], key=lambda r: r["purchase_rate"])
    n = result["n_runs"]
    counts = Counter(r["class"] for r in rows)

    print(f"# Card Coverage Report ({n} runs, {result['n_strategies']} strategies)")
    print()
    print(f"Pool: {len(rows)} cards | dead {counts['dead']} | weak {counts['weak']} | active {counts['active']}")
    print(f"Threshold: dead < 5% | weak 5–15% | active ≥ 15% (purchase appearance rate)")
    print()
    print(f"## Evaluator metric reproduction")
    print(f"  evaluator.gd card_coverage = min(per-theme avg usage_rate) = {result['evaluator_card_coverage']:.4f}")
    for theme, cov in sorted(result["theme_coverages"].items(), key=lambda x: x[1]):
        print(f"    {theme:<10}: {cov:.4f}")
    print()
    print(f"## All cards (sorted by purchase rate, ascending)")
    print()
    print(f"| {'Card ID':<22} | {'T':>1} | {'Theme':<9} | {'Class':<6} | {'PurchRate':>10} | {'AvgBuy/Run':>11} | {'FinalRate':>10} | New13 |")
    print(f"|{'-'*24}|{'-'*3}|{'-'*11}|{'-'*8}|{'-'*12}|{'-'*13}|{'-'*12}|{'-'*7}|")
    for r in rows:
        new_mark = " ★" if r["is_new_13"] else ""
        print(
            f"| {r['card_id']:<22} | {r['tier']:>1} | {r['theme']:<9} | "
            f"{r['class']:<6} | {fmt_pct(r['purchase_rate']):>10} | "
            f"{r['avg_purchases_per_run']:>11.2f} | {fmt_pct(r['final_deck_rate']):>10} |{new_mark:<6}|"
        )

    print()
    print("## New 13 cards (commit 0fd2d5e, 2026-04-25 pool expansion)")
    print()
    new_rows = sorted(
        [r for r in rows if r["is_new_13"]],
        key=lambda r: r["purchase_rate"],
    )
    for r in new_rows:
        print(
            f"  [{r['class']:<6}] {r['card_id']:<22} T{r['tier']} {r['theme']:<9} "
            f"purch={fmt_pct(r['purchase_rate'])} final={fmt_pct(r['final_deck_rate'])}"
        )

    print()
    print("## Per-strategy zero-coverage (cards never purchased by that AI)")
    print()
    for strat in sorted(result["per_strategy_zero_cards"]):
        zeros = result["per_strategy_zero_cards"][strat]
        runs = result["per_strategy_runs"][strat]
        print(f"  {strat:<18} ({runs} runs): {len(zeros)} cards never bought")
        if zeros:
            # Show grouped by theme prefix
            grouped: dict[str, list[str]] = defaultdict(list)
            for cid in zeros:
                prefix = cid.split("_")[0]
                grouped[prefix].append(cid)
            for prefix in sorted(grouped):
                print(f"    {prefix}: {', '.join(grouped[prefix])}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("coverage_path", type=Path, help="Path to coverage.json from dump_coverage.gd")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of text")
    args = parser.parse_args()

    if not args.coverage_path.exists():
        print(f"ERROR: {args.coverage_path} not found", file=sys.stderr)
        return 1

    result = analyze(args.coverage_path)
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print_report(result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
