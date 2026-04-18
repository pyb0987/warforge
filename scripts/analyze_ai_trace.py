#!/usr/bin/env python3
"""Aggregate AI trace JSONL files into per-strategy statistics.

Usage:
    python3 scripts/analyze_ai_trace.py <trace_dir>
    python3 scripts/analyze_ai_trace.py <trace_dir> --strategy=soft_druid
    python3 scripts/analyze_ai_trace.py <trace_dir> --diff=<other_dir>

Output: Markdown tables + insights.
"""

import argparse
import glob
import json
import os
import sys
from collections import Counter, defaultdict


def load_runs(trace_dir, strategy_filter=None):
    """Returns {strategy: [events_per_run]}."""
    runs = defaultdict(list)
    for path in sorted(glob.glob(os.path.join(trace_dir, "*.jsonl"))):
        fname = os.path.basename(path)
        # fname format: {strategy}_{seed}.jsonl  (strategy may contain underscores)
        stem = fname.rsplit(".", 1)[0]
        strat = stem.rsplit("_", 1)[0]
        if strategy_filter and strat != strategy_filter:
            continue
        events = []
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    events.append(json.loads(line))
        runs[strat].append(events)
    return runs


def summarize_strategy(events_per_run):
    """Per-run → aggregated summary."""
    n_runs = len(events_per_run)
    wins = 0
    total_rerolls = 0
    total_buys = 0
    total_buy_skips = 0
    buy_counter = Counter()
    skip_reasons = Counter()
    path_counter = Counter()
    final_boards = []
    hp_final = []
    rounds_reached = []
    merge_counter = Counter()

    for events in events_per_run:
        won_last = False
        last_round = 0
        last_board = []
        path_seen = None
        for ev in events:
            t = ev["t"]
            if t == "buy":
                buy_counter[ev["card_id"]] += 1
                total_buys += 1
            elif t == "buy_skip":
                skip_reasons[ev["reason"]] += 1
                total_buy_skips += 1
            elif t == "reroll":
                total_rerolls += 1
            elif t == "merge":
                merge_counter[f"{ev['card_id']}★{ev['new_star']}"] += 1
            elif t == "battle":
                won_last = ev["won"]
                last_round = ev["round"]
                hp_final_val = ev.get("hp_after", 0)
            elif t == "round_end":
                last_board = ev["board"]
                if ev.get("detected_path"):
                    path_seen = ev["detected_path"]
        if won_last:
            wins += 1
        if path_seen:
            path_counter[path_seen] += 1
        final_boards.append(last_board)
        rounds_reached.append(last_round)

    return {
        "n_runs": n_runs,
        "win_rate": wins / n_runs if n_runs else 0,
        "avg_rerolls": total_rerolls / n_runs if n_runs else 0,
        "avg_buys": total_buys / n_runs if n_runs else 0,
        "avg_skips": total_buy_skips / n_runs if n_runs else 0,
        "avg_rounds": sum(rounds_reached) / n_runs if n_runs else 0,
        "buy_top10": buy_counter.most_common(10),
        "skip_reasons": dict(skip_reasons),
        "detected_paths": dict(path_counter),
        "merges_top5": merge_counter.most_common(5),
    }


def print_summary(strat, summary):
    print(f"## {strat} ({summary['n_runs']} runs)")
    print(f"- WR: {summary['win_rate']:.1%}")
    print(f"- avg rounds reached: {summary['avg_rounds']:.1f}")
    print(f"- avg buys/run: {summary['avg_buys']:.1f}")
    print(f"- avg rerolls/run: {summary['avg_rerolls']:.1f}")
    print(f"- avg buy_skips/run: {summary['avg_skips']:.1f}")
    print(f"- skip reasons: {summary['skip_reasons']}")
    print(f"- detected paths: {summary['detected_paths']}")
    print(f"- top 10 buys: {summary['buy_top10']}")
    print(f"- top 5 merges: {summary['merges_top5']}")
    print()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace_dir")
    ap.add_argument("--strategy", default=None)
    ap.add_argument("--diff", default=None, help="Compare with another trace dir")
    args = ap.parse_args()

    runs = load_runs(args.trace_dir, args.strategy)
    if not runs:
        print(f"No traces found in {args.trace_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"# AI Trace Summary — {args.trace_dir}\n")
    for strat in sorted(runs):
        summary = summarize_strategy(runs[strat])
        print_summary(strat, summary)

    if args.diff:
        print(f"\n# Diff vs {args.diff}\n")
        other_runs = load_runs(args.diff, args.strategy)
        for strat in sorted(set(runs) | set(other_runs)):
            a = summarize_strategy(runs.get(strat, []))
            b = summarize_strategy(other_runs.get(strat, []))
            dwr = a["win_rate"] - b["win_rate"]
            print(f"- {strat}: WR Δ = {dwr:+.1%} ({b['win_rate']:.1%} → {a['win_rate']:.1%})")


if __name__ == "__main__":
    main()
