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


DRUID_PAYOFF_CARDS = {"dr_spore_cloud", "dr_wrath"}
DRUID_CAPSTONE_CARDS = {"dr_world"}
DRUID_FOCUS_CARDS = DRUID_PAYOFF_CARDS | DRUID_CAPSTONE_CARDS
DRUID_OFFENSE_CARDS = {"dr_wrath", "dr_world"}
DRUID_SPORE_CARD = "dr_spore_cloud"
DRUID_SPORE_FOREST_DEPTH_PROBE_SCALE = 0.0025
DRUID_SPORE_LOW_DEBUFF_THRESHOLD = 0.20
DRUID_SPORE_LOW_OWN_TREE_MAX = 2
DRUID_SPORE_HIGH_FOREST_MIN = 18
DRUID_SPORE_DEBUFF_CAP = 0.50

STEAMPUNK_BRANCH_CARDS = {"sp_assembly", "sp_furnace"}
STEAMPUNK_PAYOFF_CARDS = {"sp_warmachine", "sp_charger"}
STEAMPUNK_CAPSTONE_CARDS = {"sp_arsenal"}
STEAMPUNK_FOCUS_CARDS = STEAMPUNK_PAYOFF_CARDS | STEAMPUNK_CAPSTONE_CARDS
STEAMPUNK_ENGINE_REQUIREMENTS = {
    "sp_warmachine": {"sp_assembly", "sp_workshop", "sp_line"},
    "sp_charger": {"sp_furnace", "sp_workshop", "sp_circulator"},
    # Arsenal's sell/concentration support is not fully visible in traces; this
    # proxy checks that the focus engine and prior payoff are active.
    "sp_arsenal": {"sp_furnace", "sp_workshop", "sp_circulator", "sp_charger"},
}
STEAMPUNK_PATH_TARGETS = {
    "steampunk_spread": {
        "engine": {"sp_assembly", "sp_workshop", "sp_line"},
        "payoff": {"sp_warmachine"},
        "capstone": set(),
    },
    "steampunk_focus": {
        "engine": {"sp_furnace", "sp_workshop", "sp_circulator"},
        "payoff": {"sp_charger"},
        "capstone": {"sp_arsenal"},
    },
}


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
    final_theme_ratios = []
    final_theme_cards = []
    final_neutral_cards = []
    final_off_theme_cards = []
    first_path_rounds = []
    final_phase_progress = defaultdict(list)
    final_active_phase_progress = defaultdict(list)
    max_enemy_atk_debuffs = []
    max_enemy_as_debuffs = []
    first_level4_rounds = []
    first_level5_rounds = []
    total_levelups = 0

    for events in events_per_run:
        won_last = False
        run_won = None
        last_round = 0
        last_board = []
        hp_final_val = None
        path_seen = None
        first_path_round = None
        last_theme_metrics = None
        last_path_progress = None
        last_active_path_progress = None
        max_enemy_atk_debuff = 0.0
        max_enemy_as_debuff = 0.0
        first_level4_round = None
        first_level5_round = None
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
            elif t == "levelup":
                total_levelups += 1
                to_level = int(ev.get("to_level", 0))
                round_num = int(ev.get("round", 0))
                if to_level >= 4 and first_level4_round is None:
                    first_level4_round = round_num
                if to_level >= 5 and first_level5_round is None:
                    first_level5_round = round_num
            elif t == "merge":
                merge_counter[f"{ev['card_id']}★{ev['new_star']}"] += 1
            elif t == "round_start":
                shop_level = int(ev.get("shop_level", 0))
                round_num = int(ev.get("round", 0))
                if shop_level >= 4 and first_level4_round is None:
                    first_level4_round = round_num
                if shop_level >= 5 and first_level5_round is None:
                    first_level5_round = round_num
            elif t == "battle":
                won_last = ev["won"]
                last_round = ev["round"]
                if "hp_after" in ev:
                    hp_final_val = ev.get("hp_after", 0)
                enemy_debuffs = ev.get("enemy_debuffs")
                if isinstance(enemy_debuffs, dict):
                    max_enemy_atk_debuff = max(
                        max_enemy_atk_debuff,
                        float(enemy_debuffs.get("atk_pct", 0.0)),
                    )
                    max_enemy_as_debuff = max(
                        max_enemy_as_debuff,
                        float(enemy_debuffs.get("as_pct", 0.0)),
                    )
            elif t == "run_end":
                run_won = bool(ev.get("won", False))
                last_round = int(ev.get("rounds_played", last_round))
                if "final_hp" in ev:
                    hp_final_val = ev.get("final_hp", hp_final_val)
            elif t == "round_end":
                last_board = ev["board"]
                metrics = ev.get("theme_metrics")
                if isinstance(metrics, dict):
                    last_theme_metrics = metrics
                progress = ev.get("path_progress")
                if isinstance(progress, list):
                    last_path_progress = progress
                active_progress = ev.get("active_path_progress")
                if isinstance(active_progress, list):
                    last_active_path_progress = active_progress
                if ev.get("detected_path"):
                    path_seen = ev["detected_path"]
                    if first_path_round is None:
                        first_path_round = ev.get("round", 0)
        result_won = run_won if run_won is not None else won_last
        if result_won:
            wins += 1
        if path_seen:
            path_counter[path_seen] += 1
        if first_path_round:
            first_path_rounds.append(first_path_round)
        if last_theme_metrics:
            final_theme_ratios.append(float(last_theme_metrics.get("board_theme_ratio", 0.0)))
            final_theme_cards.append(int(last_theme_metrics.get("board_theme", 0)))
            final_neutral_cards.append(int(last_theme_metrics.get("board_neutral", 0)))
            final_off_theme_cards.append(int(last_theme_metrics.get("board_off_theme", 0)))
        if last_path_progress:
            for row in last_path_progress:
                path_id = row.get("id", "")
                total = int(row.get("current_total", 0))
                if path_id and total > 0:
                    owned = int(row.get("current_owned", 0))
                    final_phase_progress[path_id].append(owned / total)
        if last_active_path_progress:
            for row in last_active_path_progress:
                path_id = row.get("id", "")
                total = int(row.get("current_total", 0))
                if path_id and total > 0:
                    owned = int(row.get("current_owned", 0))
                    final_active_phase_progress[path_id].append(owned / total)
        final_boards.append(last_board)
        rounds_reached.append(last_round)
        hp_final.append(float(hp_final_val or 0))
        max_enemy_atk_debuffs.append(max_enemy_atk_debuff)
        max_enemy_as_debuffs.append(max_enemy_as_debuff)
        if first_level4_round is not None:
            first_level4_rounds.append(first_level4_round)
        if first_level5_round is not None:
            first_level5_rounds.append(first_level5_round)

    return {
        "n_runs": n_runs,
        "wins": wins,
        "win_rate": wins / n_runs if n_runs else 0,
        "avg_final_hp": _avg(hp_final),
        "avg_rerolls": total_rerolls / n_runs if n_runs else 0,
        "avg_levelups": total_levelups / n_runs if n_runs else 0,
        "avg_first_level4_round": _avg(first_level4_rounds),
        "level4_reach_rate": len(first_level4_rounds) / n_runs if n_runs else 0,
        "avg_first_level5_round": _avg(first_level5_rounds),
        "level5_reach_rate": len(first_level5_rounds) / n_runs if n_runs else 0,
        "avg_buys": total_buys / n_runs if n_runs else 0,
        "avg_skips": total_buy_skips / n_runs if n_runs else 0,
        "avg_rounds": sum(rounds_reached) / n_runs if n_runs else 0,
        "buy_top10": buy_counter.most_common(10),
        "skip_reasons": dict(skip_reasons),
        "detected_paths": dict(path_counter),
        "merges_top5": merge_counter.most_common(5),
        "avg_final_theme_ratio": _avg(final_theme_ratios),
        "avg_final_theme_cards": _avg(final_theme_cards),
        "avg_final_neutral_cards": _avg(final_neutral_cards),
        "avg_final_off_theme_cards": _avg(final_off_theme_cards),
        "path_detection_rate": len(first_path_rounds) / n_runs if n_runs else 0,
        "avg_first_path_round": _avg(first_path_rounds),
        "avg_final_phase_progress": {
            path_id: _avg(values) for path_id, values in sorted(final_phase_progress.items())
        },
        "avg_final_active_phase_progress": {
            path_id: _avg(values)
            for path_id, values in sorted(final_active_phase_progress.items())
        },
        "enemy_debuff_run_rate": (
            sum(
                1 for atk, as_ in zip(max_enemy_atk_debuffs, max_enemy_as_debuffs)
                if atk > 0.0 or as_ > 0.0
            ) / n_runs
            if n_runs else 0
        ),
        "avg_max_enemy_atk_debuff": _avg(max_enemy_atk_debuffs),
        "avg_max_enemy_as_debuff": _avg(max_enemy_as_debuffs),
    }


def _avg(values):
    if not values:
        return 0
    return sum(values) / len(values)


def print_summary(strat, summary):
    print(f"## {strat} ({summary['n_runs']} runs)")
    print(f"- WR: {summary['win_rate']:.1%}")
    print(f"- avg final HP: {summary['avg_final_hp']:.1f}")
    print(f"- avg rounds reached: {summary['avg_rounds']:.1f}")
    print(f"- avg buys/run: {summary['avg_buys']:.1f}")
    print(f"- avg rerolls/run: {summary['avg_rerolls']:.1f}")
    if summary["avg_levelups"] or summary["level4_reach_rate"] or summary["level5_reach_rate"]:
        print(
            "- level timing: "
            f"avg levelups/run {summary['avg_levelups']:.1f}, "
            f"Lv4 reached {summary['level4_reach_rate']:.1%} "
            f"(avg R{summary['avg_first_level4_round']:.1f}), "
            f"Lv5 reached {summary['level5_reach_rate']:.1%} "
            f"(avg R{summary['avg_first_level5_round']:.1f})"
        )
    print(f"- avg buy_skips/run: {summary['avg_skips']:.1f}")
    print(f"- skip reasons: {summary['skip_reasons']}")
    print(f"- detected paths: {summary['detected_paths']}")
    if summary["avg_final_theme_cards"] or summary["avg_final_neutral_cards"] or summary["avg_final_off_theme_cards"]:
        print(
            "- final board theme mix: "
            f"{summary['avg_final_theme_ratio']:.1%} theme "
            f"({summary['avg_final_theme_cards']:.1f} theme / "
            f"{summary['avg_final_neutral_cards']:.1f} neutral / "
            f"{summary['avg_final_off_theme_cards']:.1f} off-theme)"
        )
    if summary["path_detection_rate"]:
        print(
            "- path detection: "
            f"{summary['path_detection_rate']:.1%} of runs, "
            f"avg first path R{summary['avg_first_path_round']:.1f}"
        )
    if summary["avg_final_phase_progress"]:
        progress_bits = [
            f"{path_id} {value:.0%}"
            for path_id, value in summary["avg_final_phase_progress"].items()
        ]
        print(f"- avg final current-phase progress: {', '.join(progress_bits)}")
    if summary["avg_final_active_phase_progress"]:
        progress_bits = [
            f"{path_id} {value:.0%}"
            for path_id, value in summary["avg_final_active_phase_progress"].items()
        ]
        print(f"- avg final active current-phase progress: {', '.join(progress_bits)}")
    if summary["avg_max_enemy_atk_debuff"] or summary["avg_max_enemy_as_debuff"]:
        print(
            "- enemy debuffs seen: "
            f"{summary['enemy_debuff_run_rate']:.1%} of runs, "
            f"ATK avg max {summary['avg_max_enemy_atk_debuff']:.1%}, "
            f"AS avg max {summary['avg_max_enemy_as_debuff']:.1%}"
        )
    print(f"- top 10 buys: {summary['buy_top10']}")
    print(f"- top 5 merges: {summary['merges_top5']}")
    print()


def summarize_druid_loss_buckets(events_per_run, include_by_path=True):
    """Classify soft_druid losses into trace-backed failure buckets."""
    bucket_counts = Counter()
    death_rounds = Counter()
    first_level4_rounds = Counter()
    examples = []
    wins = 0
    losses = 0
    loss_payoff_bought_runs = 0
    loss_payoff_offered_runs = 0
    loss_payoff_affordable_runs = 0
    loss_affordable_payoff_skip_runs = 0
    loss_affordable_payoff_skip_events = 0
    loss_path_lag_hold_total = 0
    runs_by_path = defaultdict(list)

    for idx, events in enumerate(events_per_run):
        facts = _druid_run_facts(events, idx)
        path_id = facts["detected_path"] or "undetected"
        runs_by_path[path_id].append(events)
        if facts["won"]:
            wins += 1
            continue

        losses += 1
        death_rounds[facts["death_round"]] += 1
        first_level4_rounds[facts["first_level4_round"]] += 1
        if facts["payoff_buys"] > 0:
            loss_payoff_bought_runs += 1
        if facts["payoff_offered"]:
            loss_payoff_offered_runs += 1
        if facts["payoff_affordable"]:
            loss_payoff_affordable_runs += 1
        if facts["affordable_payoff_skip_events"] > 0:
            loss_affordable_payoff_skip_runs += 1
            loss_affordable_payoff_skip_events += facts["affordable_payoff_skip_events"]
        loss_path_lag_hold_total += facts["skip_reasons"].get("path_lag_hold", 0)

        buckets = _druid_loss_buckets(facts)
        for bucket in buckets:
            bucket_counts[bucket] += 1
        if len(examples) < 8:
            examples.append({
                "run": facts["run_id"],
                "death_round": facts["death_round"],
                "final_hp": facts["final_hp"],
                "first_level4_round": facts["first_level4_round"],
                "payoff_buys": facts["payoff_buys"],
                "payoff_active_rounds": facts["payoff_active_rounds"],
                "max_enemy_debuff": facts["max_enemy_debuff"],
                "detected_path": facts["detected_path"],
                "active_phase": facts["active_phase"],
                "active_progress": "%d/%d" % (
                    facts["active_current_owned"],
                    facts["active_current_total"],
                ),
                "owned_progress": "%d/%d" % (
                    facts["owned_current_owned"],
                    facts["owned_current_total"],
                ),
                "skip_reasons": dict(facts["skip_reasons"]),
                "buckets": buckets,
            })

    summary = {
        "n_runs": len(events_per_run),
        "wins": wins,
        "losses": losses,
        "bucket_counts": dict(bucket_counts),
        "death_rounds": dict(death_rounds),
        "first_level4_rounds": dict(first_level4_rounds),
        "loss_payoff_bought_runs": loss_payoff_bought_runs,
        "loss_payoff_offered_runs": loss_payoff_offered_runs,
        "loss_payoff_affordable_runs": loss_payoff_affordable_runs,
        "loss_affordable_payoff_skip_runs": loss_affordable_payoff_skip_runs,
        "loss_affordable_payoff_skip_events": loss_affordable_payoff_skip_events,
        "avg_loss_path_lag_holds": (
            loss_path_lag_hold_total / losses if losses else 0.0
        ),
        "examples": examples,
    }
    if include_by_path:
        summary["by_path"] = {
            path_id: summarize_druid_loss_buckets(group, include_by_path=False)
            for path_id, group in sorted(runs_by_path.items())
        }
    return summary


def _druid_run_facts(events, run_idx):
    run_end = next((ev for ev in reversed(events) if ev.get("t") == "run_end"), {})
    battles = [ev for ev in events if ev.get("t") == "battle"]
    round_starts = [ev for ev in events if ev.get("t") == "round_start"]
    round_ends = [ev for ev in events if ev.get("t") == "round_end"]
    buys = [ev for ev in events if ev.get("t") == "buy"]
    buy_skips = [ev for ev in events if ev.get("t") == "buy_skip"]
    sells = [ev for ev in events if ev.get("t") == "sell"]
    levelups = [ev for ev in events if ev.get("t") == "levelup"]

    won = bool(run_end.get("won", battles[-1].get("won", False) if battles else False))
    death_round = int(run_end.get(
        "rounds_played",
        battles[-1].get("round", 0) if battles else 0,
    ))
    first_level4_candidates = [
        int(ev.get("round", 0))
        for ev in round_starts
        if int(ev.get("shop_level", 0)) >= 4
    ]
    first_level4_candidates += [
        int(ev.get("round", 0))
        for ev in levelups
        if int(ev.get("to_level", 0)) >= 4
    ]
    first_level4_round = (
        min(first_level4_candidates) if first_level4_candidates else None
    )
    payoff_buys = sum(
        1 for ev in buys if ev.get("card_id", "") in DRUID_PAYOFF_CARDS
    )
    payoff_active_rounds = []
    capstone_active_rounds = []
    final_theme_ratio = 0.0
    detected_path = ""
    active_phase = ""
    active_current_owned = 0
    active_current_total = 0
    owned_current_owned = 0
    owned_current_total = 0

    for ev in round_ends:
        active_board = set(ev.get("active_board", []))
        if active_board & DRUID_PAYOFF_CARDS:
            payoff_active_rounds.append(int(ev.get("round", 0)))
        if active_board & DRUID_CAPSTONE_CARDS:
            capstone_active_rounds.append(int(ev.get("round", 0)))

    if round_ends:
        final_round_end = round_ends[-1]
        detected_path = str(final_round_end.get("detected_path", ""))
        metrics = final_round_end.get("theme_metrics")
        if isinstance(metrics, dict):
            final_theme_ratio = float(metrics.get("board_theme_ratio", 0.0))
        for row in final_round_end.get("active_path_progress") or []:
            if row.get("id", "") == detected_path:
                active_phase = str(row.get("current_phase", ""))
                active_current_owned = int(row.get("current_owned", 0))
                active_current_total = int(row.get("current_total", 0))
        for row in final_round_end.get("path_progress") or []:
            if row.get("id", "") == detected_path:
                owned_current_owned = int(row.get("current_owned", 0))
                owned_current_total = int(row.get("current_total", 0))

    max_enemy_debuff = 0.0
    lost_battle_after_debuff = False
    for battle in battles:
        debuffs = battle.get("enemy_debuffs")
        debuff = 0.0
        if isinstance(debuffs, dict):
            debuff = max(
                float(debuffs.get("atk_pct", 0.0)),
                float(debuffs.get("as_pct", 0.0)),
            )
        max_enemy_debuff = max(max_enemy_debuff, debuff)
        if debuff > 0.0 and not bool(battle.get("won", False)):
            lost_battle_after_debuff = True

    skip_reasons = Counter()
    for ev in buy_skips:
        skip_reasons[str(ev.get("reason", ""))] += 1

    payoff_offered = False
    payoff_affordable = False
    affordable_payoff_skip_events = 0
    for ev in buys + buy_skips:
        offers = ev.get("offers") or []
        affordable_payoffs = []
        for offer in offers:
            if offer.get("id", "") in DRUID_PAYOFF_CARDS:
                payoff_offered = True
                if bool(offer.get("affordable", False)):
                    payoff_affordable = True
                    affordable_payoffs.append(offer)
        if affordable_payoffs:
            bought_payoff = (
                ev.get("t") == "buy"
                and ev.get("card_id", "") in DRUID_PAYOFF_CARDS
            )
            if not bought_payoff:
                affordable_payoff_skip_events += 1

    return {
        "run_id": run_idx,
        "won": won,
        "final_hp": int(run_end.get("final_hp", 0)),
        "death_round": death_round,
        "first_level4_round": first_level4_round,
        "payoff_buys": payoff_buys,
        "payoff_active_rounds": payoff_active_rounds,
        "capstone_active_rounds": capstone_active_rounds,
        "payoff_offered": payoff_offered,
        "payoff_affordable": payoff_affordable,
        "affordable_payoff_skip_events": affordable_payoff_skip_events,
        "max_enemy_debuff": max_enemy_debuff,
        "lost_battle_after_debuff": lost_battle_after_debuff,
        "skip_reasons": skip_reasons,
        "final_theme_ratio": final_theme_ratio,
        "detected_path": detected_path,
        "active_phase": active_phase,
        "active_current_owned": active_current_owned,
        "active_current_total": active_current_total,
        "owned_current_owned": owned_current_owned,
        "owned_current_total": owned_current_total,
    }


def _druid_loss_buckets(facts):
    buckets = []
    first_l4 = facts["first_level4_round"]
    death_round = facts["death_round"]
    if first_l4 is None or first_l4 >= death_round:
        buckets.append("tier_access_lag")
    if facts["payoff_buys"] == 0:
        buckets.append("payoff_acquisition_lag")
    elif not facts["payoff_active_rounds"]:
        buckets.append("payoff_activation_lag")
    if facts["payoff_active_rounds"] and facts["max_enemy_debuff"] <= 0.0:
        buckets.append("payoff_no_debuff_conversion")
    if facts["lost_battle_after_debuff"]:
        buckets.append("combat_conversion_failure")
    if facts["skip_reasons"].get("path_lag_hold", 0) >= 3:
        buckets.append("path_lag_hold_pressure")
    if facts["final_theme_ratio"] and facts["final_theme_ratio"] < 0.6:
        buckets.append("low_druid_board_ratio")
    if (
        facts["owned_current_total"] > 0
        and facts["owned_current_owned"] > facts["active_current_owned"]
    ):
        buckets.append("owned_not_active_gap")
    return buckets


def print_druid_loss_buckets(strat, summary):
    print(f"## {strat} Druid Loss Buckets")
    print(
        f"- losses: {summary['losses']}/{summary['n_runs']} "
        f"(wins {summary['wins']})"
    )
    print(f"- bucket counts: {summary['bucket_counts']}")
    print(f"- death rounds: {summary['death_rounds']}")
    print(f"- first shop level 4 in losses: {summary['first_level4_rounds']}")
    print(
        "- loss payoff funnel: "
        f"offered {summary['loss_payoff_offered_runs']}, "
        f"affordable {summary['loss_payoff_affordable_runs']}, "
        f"bought {summary['loss_payoff_bought_runs']}, "
        f"skipped affordable {summary['loss_affordable_payoff_skip_runs']} runs/"
        f"{summary['loss_affordable_payoff_skip_events']} events"
    )
    print(
        "- avg path_lag_hold skips per loss: "
        f"{summary['avg_loss_path_lag_holds']:.1f}"
    )
    by_path = summary.get("by_path", {})
    if by_path:
        print("- by detected path:")
        for path_id, path_summary in by_path.items():
            print(
                "  - {path}: runs {runs}, losses {losses}, wins {wins}, "
                "buckets {buckets}, payoff funnel offered/affordable/bought "
                "{offered}/{affordable}/{bought}".format(
                    path=path_id,
                    runs=path_summary["n_runs"],
                    losses=path_summary["losses"],
                    wins=path_summary["wins"],
                    buckets=path_summary["bucket_counts"],
                    offered=path_summary["loss_payoff_offered_runs"],
                    affordable=path_summary["loss_payoff_affordable_runs"],
                    bought=path_summary["loss_payoff_bought_runs"],
                )
            )
    if summary["examples"]:
        print("- examples:")
        for example in summary["examples"]:
            print(
                "  - run {run}: R{death_round} HP {final_hp}, L4 {first_level4_round}, "
                "payoff buys {payoff_buys}, active {active_phase} {active_progress}, "
                "owned {owned_progress}, max debuff {max_enemy_debuff:.1%}, "
                "buckets {buckets}".format(**example)
            )
    print()


def summarize_druid_battle_conversion(events_per_run):
    """Summarize battle outcomes when Druid focus cards are active."""
    n_runs = len(events_per_run)
    payoff_active_runs = 0
    payoff_active_loss_runs = 0
    payoff_active_battles = 0
    payoff_active_wins = 0
    payoff_active_losses = 0
    active_battle_debuffs = 0
    active_loss_after_debuff = 0
    active_loss_without_debuff = 0
    active_loss_enemy_survived = 0
    payoff_card_counts = Counter()
    per_payoff = defaultdict(_new_payoff_battle_summary)
    active_druid_cards = []
    active_neutral_cards = []
    active_tree_counters = []
    loss_ally_survivors = []
    loss_enemy_survivors = []
    examples = []

    for idx, events in enumerate(events_per_run):
        run_end = next((ev for ev in reversed(events) if ev.get("t") == "run_end"), {})
        run_won = bool(run_end.get("won", False))
        final_hp = int(run_end.get("final_hp", 0))
        round_end_by_round = {
            int(ev.get("round", 0)): ev
            for ev in events
            if ev.get("t") == "round_end"
        }
        detected_path = ""
        for ev in reversed(events):
            if ev.get("t") == "round_end" and ev.get("detected_path"):
                detected_path = str(ev.get("detected_path", ""))
                break

        run_had_active_payoff = False
        for battle in [ev for ev in events if ev.get("t") == "battle"]:
            round_num = int(battle.get("round", 0))
            round_end = round_end_by_round.get(round_num, {})
            active_board = set(round_end.get("active_board") or [])
            active_focus = sorted(active_board & DRUID_FOCUS_CARDS)
            if not active_focus:
                continue

            run_had_active_payoff = True
            payoff_active_battles += 1
            won_battle = bool(battle.get("won", False))
            if won_battle:
                payoff_active_wins += 1
            else:
                payoff_active_losses += 1

            debuff = _battle_max_enemy_debuff(battle)
            if debuff > 0.0:
                active_battle_debuffs += 1
                if not won_battle:
                    active_loss_after_debuff += 1
            elif not won_battle:
                active_loss_without_debuff += 1

            ally_survived = int(battle.get("ally_survived", 0))
            enemy_survived = int(battle.get("enemy_survived", 0))
            if not won_battle:
                loss_ally_survivors.append(ally_survived)
                loss_enemy_survivors.append(enemy_survived)
                if enemy_survived > 0:
                    active_loss_enemy_survived += 1

            states = round_end.get("states") if isinstance(round_end, dict) else {}
            if not isinstance(states, dict):
                states = {}
            tree_counters = 0
            for card_id in active_board:
                card_state = states.get(card_id)
                if isinstance(card_state, dict):
                    tree_counters += int(card_state.get("trees", 0))
            druid_count = sum(1 for card_id in active_board if str(card_id).startswith("dr_"))
            neutral_count = sum(1 for card_id in active_board if str(card_id).startswith("ne_"))
            active_druid_cards.append(druid_count)
            active_neutral_cards.append(neutral_count)
            active_tree_counters.append(tree_counters)

            payoff_card_counts.update(active_focus)
            for card_id in active_focus:
                payoff_summary = per_payoff[card_id]
                payoff_summary["battles"] += 1
                if won_battle:
                    payoff_summary["wins"] += 1
                else:
                    payoff_summary["losses"] += 1
                if debuff > 0.0:
                    payoff_summary["debuff_battles"] += 1

            if not won_battle and len(examples) < 8:
                examples.append({
                    "run": idx,
                    "round": round_num,
                    "final_hp": final_hp,
                    "run_won": run_won,
                    "detected_path": detected_path,
                    "active_focus": active_focus,
                    "active_druid_cards": druid_count,
                    "active_neutral_cards": neutral_count,
                    "active_tree_counters": tree_counters,
                    "debuff": debuff,
                    "ally_survived": ally_survived,
                    "enemy_survived": enemy_survived,
                })

        if run_had_active_payoff:
            payoff_active_runs += 1
            if not run_won:
                payoff_active_loss_runs += 1

    return {
        "n_runs": n_runs,
        "payoff_active_runs": payoff_active_runs,
        "payoff_active_loss_runs": payoff_active_loss_runs,
        "payoff_active_battles": payoff_active_battles,
        "payoff_active_wins": payoff_active_wins,
        "payoff_active_losses": payoff_active_losses,
        "payoff_active_battle_win_rate": (
            payoff_active_wins / payoff_active_battles
            if payoff_active_battles else 0.0
        ),
        "active_battle_debuffs": active_battle_debuffs,
        "active_loss_after_debuff": active_loss_after_debuff,
        "active_loss_without_debuff": active_loss_without_debuff,
        "active_loss_enemy_survived": active_loss_enemy_survived,
        "avg_active_druid_cards": _avg(active_druid_cards),
        "avg_active_neutral_cards": _avg(active_neutral_cards),
        "avg_active_tree_counters": _avg(active_tree_counters),
        "avg_loss_ally_survived": _avg(loss_ally_survivors),
        "avg_loss_enemy_survived": _avg(loss_enemy_survivors),
        "payoff_card_counts": dict(payoff_card_counts),
        "per_payoff": {
            card_id: _finalize_payoff_battle_summary(summary)
            for card_id, summary in sorted(per_payoff.items())
        },
        "examples": examples,
    }


def _new_payoff_battle_summary():
    return {
        "battles": 0,
        "wins": 0,
        "losses": 0,
        "debuff_battles": 0,
    }


def _finalize_payoff_battle_summary(summary):
    result = dict(summary)
    battles = result["battles"]
    result["win_rate"] = result["wins"] / battles if battles else 0.0
    result["debuff_rate"] = result["debuff_battles"] / battles if battles else 0.0
    return result


def _battle_max_enemy_debuff(battle):
    debuffs = battle.get("enemy_debuffs")
    if not isinstance(debuffs, dict):
        return 0.0
    return max(
        float(debuffs.get("atk_pct", 0.0)),
        float(debuffs.get("as_pct", 0.0)),
    )


def print_druid_battle_conversion(strat, summary):
    print(f"## {strat} Druid Battle Conversion")
    print(
        "- focus-active runs: "
        f"{summary['payoff_active_runs']}/{summary['n_runs']} "
        f"(loss runs {summary['payoff_active_loss_runs']})"
    )
    print(
        "- focus-active battles: "
        f"{summary['payoff_active_battles']} total, "
        f"{summary['payoff_active_wins']} won/"
        f"{summary['payoff_active_losses']} lost, "
        f"WR {summary['payoff_active_battle_win_rate']:.1%}"
    )
    print(
        "- conversion: "
        f"debuff battles {summary['active_battle_debuffs']}, "
        f"losses after debuff {summary['active_loss_after_debuff']}, "
        f"losses without debuff {summary['active_loss_without_debuff']}, "
        f"losses with enemies surviving {summary['active_loss_enemy_survived']}"
    )
    print(
        "- active field averages during focus battles: "
        f"{summary['avg_active_druid_cards']:.1f} Druid, "
        f"{summary['avg_active_neutral_cards']:.1f} neutral, "
        f"{summary['avg_active_tree_counters']:.1f} tree counters"
    )
    if summary["payoff_active_losses"]:
        print(
            "- active loss survivors: "
            f"ally {summary['avg_loss_ally_survived']:.1f}, "
            f"enemy {summary['avg_loss_enemy_survived']:.1f}"
        )
    print(f"- focus card battle counts: {summary['payoff_card_counts']}")
    if summary["per_payoff"]:
        print("- by focus card:")
        for card_id, row in summary["per_payoff"].items():
            print(
                "  - {card}: battles {battles}, wins {wins}, losses {losses}, "
                "WR {win_rate:.1%}, debuff rate {debuff_rate:.1%}".format(
                    card=card_id,
                    **row,
                )
            )
    if summary["examples"]:
        print("- loss examples:")
        for example in summary["examples"]:
            print(
                "  - run {run} R{round} {detected_path}: focus {active_focus}, "
                "Druid {active_druid_cards}, neutral {active_neutral_cards}, "
                "trees {active_tree_counters}, debuff {debuff:.1%}, "
                "survivors A{ally_survived}/E{enemy_survived}, "
                "final HP {final_hp}".format(**example)
            )
    print()


def _collect_druid_active_ledger_frames(events_per_run, round_min, round_max):
    frames = []
    missing_round_end = 0
    detail_frames = 0
    star_detail_frames = 0
    tree_detail_frames = 0

    for idx, events in enumerate(events_per_run):
        run_end = next((ev for ev in reversed(events) if ev.get("t") == "run_end"), {})
        run_won = bool(run_end.get("won", False))
        final_hp = int(run_end.get("final_hp", 0))
        round_start_by_round = {
            int(ev.get("round", 0)): ev
            for ev in events
            if ev.get("t") == "round_start"
        }
        buys_by_round = defaultdict(set)
        offers_by_round = defaultdict(set)
        affordable_by_round = defaultdict(set)
        for ev in events:
            round_num = int(ev.get("round", 0))
            if ev.get("t") == "buy":
                buys_by_round[round_num].add(str(ev.get("card_id", "")))
            if ev.get("t") not in {"buy", "buy_skip"}:
                continue
            offers = ev.get("offers")
            if not isinstance(offers, list):
                continue
            for offer in offers:
                if not isinstance(offer, dict):
                    continue
                offer_id = str(offer.get("id", ""))
                if not offer_id:
                    continue
                offers_by_round[round_num].add(offer_id)
                if bool(offer.get("affordable", False)):
                    affordable_by_round[round_num].add(offer_id)
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
                missing_round_end += 1
                continue

            active_board = set(round_end.get("active_board") or [])
            owned_board = set(round_end.get("board") or [])
            bench = set(round_end.get("bench") or [])
            active_focus = sorted(active_board & DRUID_FOCUS_CARDS)
            if not active_focus:
                continue

            states = round_end.get("states")
            if not isinstance(states, dict):
                states = {}

            focus_details = []
            has_star_details = True
            has_tree_details = True
            for card_id in active_focus:
                card_state = states.get(card_id)
                if not isinstance(card_state, dict):
                    card_state = {}
                    has_star_details = False
                    has_tree_details = False
                if "star" not in card_state:
                    has_star_details = False
                focus_details.append({
                    "card_id": card_id,
                    "star": int(card_state.get("star", 1)),
                    "trees": int(card_state.get("trees", 0)),
                })

            detail_frames += 1
            if has_star_details:
                star_detail_frames += 1
            if has_tree_details:
                tree_detail_frames += 1

            debuff = _battle_max_enemy_debuff(battle)
            won_battle = bool(battle.get("won", False))
            ally_survived = int(battle.get("ally_survived", 0))
            enemy_survived = int(battle.get("enemy_survived", 0))
            active_tree_counters = _sum_active_trees(active_board, states)
            round_start = round_start_by_round.get(round_num, {})
            bought_before_or_at = set()
            offered_before_or_at = set()
            affordable_before_or_at = set()
            for buy_round, card_ids in buys_by_round.items():
                if buy_round <= round_num:
                    bought_before_or_at.update(card_ids)
            for offer_round, card_ids in offers_by_round.items():
                if offer_round <= round_num:
                    offered_before_or_at.update(card_ids)
            for offer_round, card_ids in affordable_by_round.items():
                if offer_round <= round_num:
                    affordable_before_or_at.update(card_ids)
            row = {
                "run": idx,
                "round": round_num,
                "path": str(round_end.get("detected_path", "")) or "undetected",
                "focus": active_focus,
                "focus_details": focus_details,
                "won": won_battle,
                "run_won": run_won,
                "final_hp": final_hp,
                "hp_start": int(round_start.get("hp", 0)) if round_start else None,
                "ally_survived": ally_survived,
                "enemy_survived": enemy_survived,
                "debuff": debuff,
                "active_board": sorted(active_board),
                "owned_board": sorted(owned_board | active_board),
                "bench": sorted(bench),
                "bought_before_or_at": sorted(bought_before_or_at),
                "offered_before_or_at": sorted(offered_before_or_at),
                "affordable_before_or_at": sorted(affordable_before_or_at),
                "active_druid_cards": sum(
                    1 for card_id in active_board if str(card_id).startswith("dr_")
                ),
                "active_neutral_cards": sum(
                    1 for card_id in active_board if str(card_id).startswith("ne_")
                ),
                "active_tree_counters": active_tree_counters,
            }
            if not won_battle:
                row["primary_bottleneck"] = _classify_druid_active_loss(row)
            frames.append(row)

    return {
        "frames": frames,
        "missing_round_end": missing_round_end,
        "detail_frames": detail_frames,
        "star_detail_frames": star_detail_frames,
        "tree_detail_frames": tree_detail_frames,
    }


def summarize_druid_active_ledger(events_per_run, round_min=9, round_max=11):
    """Classify R9-R11 Druid focus-active combat margins."""
    n_runs = len(events_per_run)
    collected = _collect_druid_active_ledger_frames(
        events_per_run,
        round_min,
        round_max,
    )
    frames = collected["frames"]
    missing_round_end = collected["missing_round_end"]
    detail_frames = collected["detail_frames"]
    star_detail_frames = collected["star_detail_frames"]
    tree_detail_frames = collected["tree_detail_frames"]

    loss_frames = [row for row in frames if not row["won"]]
    primary_counts = Counter(row["primary_bottleneck"] for row in loss_frames)
    by_focus_combo = _summarize_druid_ledger_groups(
        frames, lambda row: "+".join(row["focus"])
    )
    by_path = _summarize_druid_ledger_groups(frames, lambda row: row["path"])
    by_focus_card = {}
    for card_id in sorted(DRUID_FOCUS_CARDS):
        group = [row for row in frames if card_id in row["focus"]]
        if group:
            by_focus_card[card_id] = _finalize_druid_ledger_group(group)

    return {
        "n_runs": n_runs,
        "round_min": round_min,
        "round_max": round_max,
        "frames": len(frames),
        "wins": sum(1 for row in frames if row["won"]),
        "losses": len(loss_frames),
        "missing_round_end": missing_round_end,
        "detail_coverage": detail_frames / len(frames) if frames else 0.0,
        "star_coverage": star_detail_frames / len(frames) if frames else 0.0,
        "tree_coverage": tree_detail_frames / len(frames) if frames else 0.0,
        "primary_bottlenecks": dict(primary_counts),
        "by_focus_combo": by_focus_combo,
        "by_focus_card": by_focus_card,
        "by_path": by_path,
        "examples": loss_frames[:8],
        "next_signal": _druid_active_ledger_signal(primary_counts, loss_frames),
    }


def _sum_active_trees(active_board, states):
    total = 0
    for card_id in active_board:
        card_state = states.get(card_id)
        if isinstance(card_state, dict):
            total += int(card_state.get("trees", 0))
    return total


def _classify_druid_active_loss(row):
    enemy_survived = int(row.get("enemy_survived", 0))
    active_focus = set(row.get("focus", []))
    debuff = float(row.get("debuff", 0.0))
    active_druid = int(row.get("active_druid_cards", 0))
    tree_counters = int(row.get("active_tree_counters", 0))

    if active_druid <= 2:
        return "board_mass_shortfall"
    if enemy_survived >= 20:
        return "enemy_pressure_spike"
    if "dr_spore_cloud" not in active_focus and debuff <= 0.0:
        return "debuff_missing"
    if "dr_spore_cloud" in active_focus and debuff < 0.20:
        return "debuff_too_small"
    if enemy_survived >= 12:
        return "damage_shortfall"
    if enemy_survived <= 6:
        return "near_miss_survivability"
    if tree_counters < 12:
        return "tree_depth_shortfall"
    return "mixed_margin"


def _summarize_druid_ledger_groups(frames, key_fn):
    grouped = defaultdict(list)
    for row in frames:
        grouped[key_fn(row)].append(row)
    return {
        key: _finalize_druid_ledger_group(group)
        for key, group in sorted(grouped.items())
    }


def _finalize_druid_ledger_group(group):
    losses = [row for row in group if not row["won"]]
    buckets = Counter(row["primary_bottleneck"] for row in losses)
    return {
        "frames": len(group),
        "wins": sum(1 for row in group if row["won"]),
        "losses": len(losses),
        "win_rate": (
            sum(1 for row in group if row["won"]) / len(group)
            if group else 0.0
        ),
        "avg_debuff": _avg([row["debuff"] for row in group]),
        "avg_active_druid_cards": _avg([row["active_druid_cards"] for row in group]),
        "avg_active_tree_counters": _avg([row["active_tree_counters"] for row in group]),
        "avg_loss_ally_survived": _avg([row["ally_survived"] for row in losses]),
        "avg_loss_enemy_survived": _avg([row["enemy_survived"] for row in losses]),
        "primary_bottlenecks": dict(buckets),
    }


def _druid_active_ledger_signal(primary_counts, loss_frames):
    if not loss_frames:
        return "No R9-R11 focus-active losses in scope."
    if not primary_counts:
        return "No primary bottleneck identified."
    primary, count = primary_counts.most_common(1)[0]
    share = count / len(loss_frames)
    if primary == "debuff_missing":
        return (
            f"Debuff-missing focus frames dominate ({share:.0%}); inspect "
            "Wrath-solo activation or Spore pairing before raw shield buffs."
        )
    if primary == "debuff_too_small":
        return (
            f"Spore is present but under-moving enemy pressure ({share:.0%}); "
            "inspect Spore debuff scaling/caps."
        )
    if primary == "damage_shortfall":
        return (
            f"Damage shortfall dominates ({share:.0%}); inspect Wrath/World "
            "offensive battle math."
        )
    if primary == "enemy_pressure_spike":
        return (
            f"Enemy pressure spikes dominate ({share:.0%}); compare enemy "
            "round pressure against Druid R9-R11 payoff timing."
        )
    if primary == "near_miss_survivability":
        return (
            f"Near-miss survivability dominates ({share:.0%}); a narrow HP/shield "
            "probe may be better than offense."
        )
    return f"{primary} is the largest bucket ({share:.0%}); inspect examples before tuning."


def print_druid_active_ledger(strat, summary):
    print(f"## {strat} Druid Active Battle Ledger")
    print(
        "- scope: "
        f"R{summary['round_min']}-R{summary['round_max']} focus-active battles, "
        f"{summary['frames']} frames from {summary['n_runs']} runs"
    )
    print(
        "- results: "
        f"{summary['wins']} won/{summary['losses']} lost, "
        f"WR {(summary['wins'] / summary['frames'] if summary['frames'] else 0.0):.1%}"
    )
    print(
        "- coverage: "
        f"detail {summary['detail_coverage']:.1%}, "
        f"star {summary['star_coverage']:.1%}, "
        f"tree {summary['tree_coverage']:.1%}, "
        f"missing round_end {summary['missing_round_end']}"
    )
    print(f"- primary bottlenecks: {summary['primary_bottlenecks']}")
    print(f"- next signal: {summary['next_signal']}")
    if summary["by_focus_combo"]:
        print("- by focus combo:")
        for combo, row in summary["by_focus_combo"].items():
            print(
                "  - {combo}: frames {frames}, wins {wins}, losses {losses}, "
                "WR {win_rate:.1%}, loss A/E {ally:.1f}/{enemy:.1f}, "
                "debuff {debuff:.1%}, buckets {buckets}".format(
                    combo=combo,
                    frames=row["frames"],
                    wins=row["wins"],
                    losses=row["losses"],
                    win_rate=row["win_rate"],
                    ally=row["avg_loss_ally_survived"],
                    enemy=row["avg_loss_enemy_survived"],
                    debuff=row["avg_debuff"],
                    buckets=row["primary_bottlenecks"],
                )
            )
    if summary["by_path"]:
        print("- by path:")
        for path_id, row in summary["by_path"].items():
            print(
                "  - {path}: frames {frames}, wins {wins}, losses {losses}, "
                "WR {win_rate:.1%}, loss E {enemy:.1f}, buckets {buckets}".format(
                    path=path_id,
                    frames=row["frames"],
                    wins=row["wins"],
                    losses=row["losses"],
                    win_rate=row["win_rate"],
                    enemy=row["avg_loss_enemy_survived"],
                    buckets=row["primary_bottlenecks"],
                )
            )
    if summary["examples"]:
        print("- loss examples:")
        for row in summary["examples"]:
            detail = ", ".join(
                "{card}★{star}/T{trees}".format(
                    card=item["card_id"],
                    star=item["star"],
                    trees=item["trees"],
                )
                for item in row["focus_details"]
            )
            print(
                "  - run {run} R{round} {path}: {detail}, "
                "Druid {active_druid_cards}, neutral {active_neutral_cards}, "
                "trees {active_tree_counters}, debuff {debuff:.1%}, "
                "survivors A{ally_survived}/E{enemy_survived}, "
                "bucket {primary_bottleneck}, final HP {final_hp}".format(
                    detail=detail,
                    **row,
                )
            )
    print()


def summarize_druid_offense_ledger(events_per_run, round_min=9, round_max=11):
    """Separate Druid late focus losses by Wrath/World offense presence."""
    collected = _collect_druid_active_ledger_frames(
        events_per_run,
        round_min,
        round_max,
    )
    rows = [_druid_offense_row(row) for row in collected["frames"]]
    losses = [row for row in rows if not row["won"]]
    offense_losses = [row for row in losses if row["offense_present"]]
    no_offense_losses = [row for row in losses if not row["offense_present"]]
    shortfall_losses = [
        row for row in losses
        if row["primary_bottleneck"] == "damage_shortfall"
    ]
    debuff_gap_losses = [
        row for row in losses
        if row["primary_bottleneck"] in {"debuff_missing", "debuff_too_small"}
    ]

    summary = {
        "n_runs": len(events_per_run),
        "round_min": round_min,
        "round_max": round_max,
        "frames": len(rows),
        "wins": sum(1 for row in rows if row["won"]),
        "losses": len(losses),
        "missing_round_end": collected["missing_round_end"],
        "detail_coverage": (
            collected["detail_frames"] / len(rows) if rows else 0.0
        ),
        "offense_active_frames": sum(1 for row in rows if row["offense_present"]),
        "offense_active_losses": len(offense_losses),
        "no_offense_losses": len(no_offense_losses),
        "spore_active_frames": sum(1 for row in rows if row["spore_active"]),
        "spore_offense_frames": sum(
            1 for row in rows if row["spore_active"] and row["offense_present"]
        ),
        "damage_shortfall_losses": len(shortfall_losses),
        "damage_shortfall_with_offense": sum(
            1 for row in shortfall_losses if row["offense_present"]
        ),
        "damage_shortfall_without_offense": sum(
            1 for row in shortfall_losses if not row["offense_present"]
        ),
        "debuff_gap_losses": len(debuff_gap_losses),
        "zero_ally_offense_loss_frames": sum(
            1 for row in offense_losses if row["ally_survived"] <= 0
        ),
        "avg_loss_ally_survived": _avg([row["ally_survived"] for row in losses]),
        "avg_loss_enemy_survived": _avg([row["enemy_survived"] for row in losses]),
        "avg_offense_loss_enemy_survived": _avg(
            [row["enemy_survived"] for row in offense_losses]
        ),
        "avg_no_offense_loss_enemy_survived": _avg(
            [row["enemy_survived"] for row in no_offense_losses]
        ),
        "avg_damage_shortfall_enemy_survived": _avg(
            [row["enemy_survived"] for row in shortfall_losses]
        ),
        "primary_bottlenecks": dict(
            Counter(row["primary_bottleneck"] for row in losses)
        ),
        "by_offense_combo": _summarize_druid_offense_groups(
            rows,
            lambda row: row["offense_combo"],
        ),
        "by_spore_pairing": _summarize_druid_offense_groups(
            rows,
            lambda row: row["spore_pairing"],
        ),
        "by_path": _summarize_druid_offense_groups(
            rows,
            lambda row: row["path"],
        ),
        "examples": losses[:8],
        "trace_caveat": (
            "battle traces expose survivors and aggregate card-id states, not "
            "per-unit attack contribution"
        ),
    }
    summary["next_signal"] = _druid_offense_signal(summary)
    return summary


def _druid_offense_row(row):
    offense_cards = sorted(set(row.get("focus", [])) & DRUID_OFFENSE_CARDS)
    offense_details = [
        item for item in row.get("focus_details", [])
        if item.get("card_id") in DRUID_OFFENSE_CARDS
    ]
    offense_combo = "+".join(offense_cards) if offense_cards else "none"
    spore_active = DRUID_SPORE_CARD in set(row.get("focus", []))
    result = dict(row)
    result.update({
        "offense_cards": offense_cards,
        "offense_combo": offense_combo,
        "offense_present": bool(offense_cards),
        "spore_active": spore_active,
        "spore_pairing": (
            ("spore+" if spore_active else "no_spore+") + offense_combo
        ),
        "offense_star_sum": sum(
            int(item.get("star", 1)) for item in offense_details
        ),
        "offense_tree_counters": sum(
            int(item.get("trees", 0)) for item in offense_details
        ),
    })
    return result


def _summarize_druid_offense_groups(frames, key_fn):
    grouped = defaultdict(list)
    for row in frames:
        grouped[key_fn(row)].append(row)
    return {
        key: _finalize_druid_offense_group(group)
        for key, group in sorted(grouped.items())
    }


def _finalize_druid_offense_group(group):
    losses = [row for row in group if not row["won"]]
    shortfall_losses = [
        row for row in losses
        if row["primary_bottleneck"] == "damage_shortfall"
    ]
    buckets = Counter(row["primary_bottleneck"] for row in losses)
    return {
        "frames": len(group),
        "wins": sum(1 for row in group if row["won"]),
        "losses": len(losses),
        "win_rate": _safe_rate(sum(1 for row in group if row["won"]), len(group)),
        "avg_debuff": _avg([row["debuff"] for row in group]),
        "avg_active_tree_counters": _avg(
            [row["active_tree_counters"] for row in group]
        ),
        "avg_offense_star_sum": _avg(
            [row["offense_star_sum"] for row in group]
        ),
        "avg_offense_tree_counters": _avg(
            [row["offense_tree_counters"] for row in group]
        ),
        "avg_loss_ally_survived": _avg([row["ally_survived"] for row in losses]),
        "avg_loss_enemy_survived": _avg([row["enemy_survived"] for row in losses]),
        "damage_shortfall_losses": len(shortfall_losses),
        "damage_shortfall_share": _safe_rate(len(shortfall_losses), len(losses)),
        "avg_damage_shortfall_enemy_survived": _avg(
            [row["enemy_survived"] for row in shortfall_losses]
        ),
        "zero_ally_loss_frames": sum(
            1 for row in losses if row["ally_survived"] <= 0
        ),
        "primary_bottlenecks": dict(buckets),
    }


def _druid_offense_signal(summary):
    losses = int(summary["losses"])
    if not losses:
        return "No R9-R11 Druid focus-active losses in scope."

    shortfalls = int(summary["damage_shortfall_losses"])
    shortfall_share = shortfalls / losses if losses else 0.0
    with_offense = int(summary["damage_shortfall_with_offense"])
    without_offense = int(summary["damage_shortfall_without_offense"])
    with_offense_share = with_offense / shortfalls if shortfalls else 0.0
    without_offense_share = without_offense / shortfalls if shortfalls else 0.0

    if shortfall_share >= 0.30 and without_offense_share >= 0.50:
        return (
            "OFFENSE_ACCESS_OR_ACTIVATION_CANDIDATE: damage shortfall is common, "
            "but most shortfall losses have Spore without Wrath/World online; "
            "inspect acquisition/promotion before buffing offensive math."
        )
    if shortfall_share >= 0.30 and with_offense_share >= 0.50:
        return (
            "OFFENSE_CONVERSION_MATH_CANDIDATE: Wrath/World are present in most "
            "damage-shortfall losses, so inspect their battle math before "
            "another Spore change."
        )

    offense_losses = int(summary["offense_active_losses"])
    zero_ally = int(summary["zero_ally_offense_loss_frames"])
    if offense_losses and zero_ally / offense_losses >= 0.75:
        return (
            "SURVIVAL_BEFORE_DAMAGE_CANDIDATE: offense is often online but allied "
            "survivors are still zero; inspect shields/HP alongside damage."
        )

    if int(summary["debuff_gap_losses"]) > shortfalls:
        return (
            "DEBUFF_GAP_STILL_DOMINATES: Spore/debuff access remains the larger "
            "late-focus loss bucket."
        )
    return "MIXED_OFFENSE_SIGNAL: no single offense/access bucket dominates."


def summarize_druid_offense_comparison(candidate_events, baseline_events):
    candidate = summarize_druid_offense_ledger(candidate_events)
    baseline = summarize_druid_offense_ledger(baseline_events)
    comparison = {
        "baseline": _druid_offense_compare_metrics(baseline),
        "candidate": _druid_offense_compare_metrics(candidate),
        "combo_deltas": _druid_offense_combo_deltas(
            candidate["by_offense_combo"],
            baseline["by_offense_combo"],
        ),
    }
    comparison["deltas"] = {
        key: comparison["candidate"][key] - comparison["baseline"][key]
        for key in (
            "frames",
            "wins",
            "losses",
            "win_rate",
            "damage_shortfall_losses",
            "damage_shortfall_share",
            "damage_shortfall_with_offense",
            "damage_shortfall_without_offense",
            "debuff_gap_losses",
            "avg_loss_enemy_survived",
            "avg_offense_loss_enemy_survived",
            "avg_no_offense_loss_enemy_survived",
        )
    }
    comparison["next_signal"] = _druid_offense_comparison_signal(
        candidate,
        baseline,
    )
    return comparison


def _druid_offense_compare_metrics(summary):
    return {
        "frames": int(summary["frames"]),
        "wins": int(summary["wins"]),
        "losses": int(summary["losses"]),
        "win_rate": _safe_rate(summary["wins"], summary["frames"]),
        "offense_active_frames": int(summary["offense_active_frames"]),
        "offense_active_losses": int(summary["offense_active_losses"]),
        "no_offense_losses": int(summary["no_offense_losses"]),
        "damage_shortfall_losses": int(summary["damage_shortfall_losses"]),
        "damage_shortfall_share": _safe_rate(
            summary["damage_shortfall_losses"],
            summary["losses"],
        ),
        "damage_shortfall_with_offense": int(
            summary["damage_shortfall_with_offense"]
        ),
        "damage_shortfall_without_offense": int(
            summary["damage_shortfall_without_offense"]
        ),
        "debuff_gap_losses": int(summary["debuff_gap_losses"]),
        "avg_loss_enemy_survived": float(summary["avg_loss_enemy_survived"]),
        "avg_offense_loss_enemy_survived": float(
            summary["avg_offense_loss_enemy_survived"]
        ),
        "avg_no_offense_loss_enemy_survived": float(
            summary["avg_no_offense_loss_enemy_survived"]
        ),
    }


def _druid_offense_combo_deltas(candidate_combos, baseline_combos):
    result = {}
    for combo in sorted(set(candidate_combos) | set(baseline_combos)):
        candidate = candidate_combos.get(combo, {})
        baseline = baseline_combos.get(combo, {})
        result[combo] = {
            "frames_delta": int(candidate.get("frames", 0))
            - int(baseline.get("frames", 0)),
            "wins_delta": int(candidate.get("wins", 0))
            - int(baseline.get("wins", 0)),
            "losses_delta": int(candidate.get("losses", 0))
            - int(baseline.get("losses", 0)),
            "win_rate_delta": float(candidate.get("win_rate", 0.0))
            - float(baseline.get("win_rate", 0.0)),
            "damage_shortfall_delta": int(
                candidate.get("damage_shortfall_losses", 0)
            ) - int(baseline.get("damage_shortfall_losses", 0)),
            "avg_loss_enemy_survived_delta": float(
                candidate.get("avg_loss_enemy_survived", 0.0)
            ) - float(baseline.get("avg_loss_enemy_survived", 0.0)),
        }
    return result


def _druid_offense_comparison_signal(candidate, baseline):
    cand_shortfalls = int(candidate["damage_shortfall_losses"])
    base_shortfalls = int(baseline["damage_shortfall_losses"])
    cand_debuff_gaps = int(candidate["debuff_gap_losses"])
    base_debuff_gaps = int(baseline["debuff_gap_losses"])
    if cand_shortfalls > base_shortfalls and cand_debuff_gaps < base_debuff_gaps:
        return (
            "DEBUFF_REPAIR_EXPOSED_OFFENSE_ACCESS: the rejected probe reduced "
            "debuff gaps but converted many losses into damage shortfall; route "
            "next work through offense access/activation evidence."
        )
    if (
        cand_shortfalls > base_shortfalls
        and int(candidate["damage_shortfall_with_offense"])
        >= int(candidate["damage_shortfall_without_offense"])
    ):
        return (
            "OFFENSE_MATH_COMPARISON_CANDIDATE: candidate shortfall growth is "
            "mostly with Wrath/World online; inspect offensive battle formulas."
        )
    if int(candidate["offense_active_losses"]) < int(baseline["offense_active_losses"]):
        return (
            "OFFENSE_ACTIVATION_MOVED_BUT_NOT_ENOUGH: offense-active losses fell; "
            "require clear-rate and survivor-margin gates before adoption."
        )
    return "NO_DECISIVE_OFFENSE_COMPARISON_DELTA: keep as routing evidence only."


def print_druid_offense_ledger(strat, summary):
    print(f"## {strat} Druid Offense Ledger")
    print(
        "- scope: "
        f"R{summary['round_min']}-R{summary['round_max']} focus-active battles, "
        f"{summary['frames']} frames from {summary['n_runs']} runs"
    )
    print(f"- trace caveat: {summary['trace_caveat']}")
    print(
        "- results: "
        f"{summary['wins']} won/{summary['losses']} lost, "
        f"WR {_safe_rate(summary['wins'], summary['frames']):.1%}, "
        f"missing round_end {summary['missing_round_end']}"
    )
    print(
        "- offense presence: "
        f"offense frames {summary['offense_active_frames']}, "
        f"offense losses {summary['offense_active_losses']}, "
        f"no-offense losses {summary['no_offense_losses']}, "
        f"Spore+offense frames {summary['spore_offense_frames']}"
    )
    print(
        "- damage shortfall: "
        f"{summary['damage_shortfall_losses']}/{summary['losses']} losses "
        f"({_safe_rate(summary['damage_shortfall_losses'], summary['losses']):.1%}), "
        f"with offense {summary['damage_shortfall_with_offense']}, "
        f"without offense {summary['damage_shortfall_without_offense']}, "
        f"avg shortfall enemy survived "
        f"{summary['avg_damage_shortfall_enemy_survived']:.1f}"
    )
    print(
        "- loss survivor margin: "
        f"all A/E {summary['avg_loss_ally_survived']:.1f}/"
        f"{summary['avg_loss_enemy_survived']:.1f}, "
        f"offense enemy {summary['avg_offense_loss_enemy_survived']:.1f}, "
        f"no-offense enemy {summary['avg_no_offense_loss_enemy_survived']:.1f}"
    )
    print(f"- primary bottlenecks: {summary['primary_bottlenecks']}")
    print(f"- next signal: {summary['next_signal']}")
    if summary["by_offense_combo"]:
        print("- by offense combo:")
        for combo, row in summary["by_offense_combo"].items():
            print(
                "  - {combo}: frames {frames}, wins {wins}, losses {losses}, "
                "WR {win_rate:.1%}, shortfall {shortfall} ({share:.1%}), "
                "loss A/E {ally:.1f}/{enemy:.1f}, stars {stars:.1f}, "
                "trees {trees:.1f}, buckets {buckets}".format(
                    combo=combo,
                    frames=row["frames"],
                    wins=row["wins"],
                    losses=row["losses"],
                    win_rate=row["win_rate"],
                    shortfall=row["damage_shortfall_losses"],
                    share=row["damage_shortfall_share"],
                    ally=row["avg_loss_ally_survived"],
                    enemy=row["avg_loss_enemy_survived"],
                    stars=row["avg_offense_star_sum"],
                    trees=row["avg_offense_tree_counters"],
                    buckets=row["primary_bottlenecks"],
                )
            )
    if summary["by_spore_pairing"]:
        print("- by Spore/offense pairing:")
        for pairing, row in summary["by_spore_pairing"].items():
            print(
                "  - {pairing}: frames {frames}, wins {wins}, losses {losses}, "
                "WR {win_rate:.1%}, shortfall {shortfall}, loss enemy {enemy:.1f}".format(
                    pairing=pairing,
                    frames=row["frames"],
                    wins=row["wins"],
                    losses=row["losses"],
                    win_rate=row["win_rate"],
                    shortfall=row["damage_shortfall_losses"],
                    enemy=row["avg_loss_enemy_survived"],
                )
            )
    if summary["examples"]:
        print("- loss examples:")
        for row in summary["examples"]:
            print(
                "  - run {run} R{round} {path}: focus {focus}, offense "
                "{offense_combo}, Spore {spore_active}, stars {stars}, "
                "offense trees {trees}, debuff {debuff:.1%}, survivors "
                "A{ally_survived}/E{enemy_survived}, bucket {primary_bottleneck}, "
                "final HP {final_hp}".format(
                    stars=row["offense_star_sum"],
                    trees=row["offense_tree_counters"],
                    **row,
                )
            )
    print()


def print_druid_offense_comparison(strat, comparison, baseline_label):
    print(f"## {strat} Druid Offense Ledger Comparison")
    print(f"- baseline: {baseline_label}")
    base = comparison["baseline"]
    cand = comparison["candidate"]
    deltas = comparison["deltas"]
    print(
        "- R9-R11 focus frames: "
        f"{base['frames']} -> {cand['frames']} "
        f"(Delta {deltas['frames']:+d}), WR {base['win_rate']:.1%} -> "
        f"{cand['win_rate']:.1%} (Delta {deltas['win_rate']:+.1%})"
    )
    print(
        "- damage shortfall: "
        f"{base['damage_shortfall_losses']} -> "
        f"{cand['damage_shortfall_losses']} "
        f"(Delta {deltas['damage_shortfall_losses']:+d}), share "
        f"{base['damage_shortfall_share']:.1%} -> "
        f"{cand['damage_shortfall_share']:.1%}"
    )
    print(
        "- shortfall split: "
        f"with offense {base['damage_shortfall_with_offense']} -> "
        f"{cand['damage_shortfall_with_offense']} "
        f"(Delta {deltas['damage_shortfall_with_offense']:+d}), "
        f"without offense {base['damage_shortfall_without_offense']} -> "
        f"{cand['damage_shortfall_without_offense']} "
        f"(Delta {deltas['damage_shortfall_without_offense']:+d})"
    )
    print(
        "- debuff gaps and survivor margin: "
        f"debuff gaps {base['debuff_gap_losses']} -> "
        f"{cand['debuff_gap_losses']} "
        f"(Delta {deltas['debuff_gap_losses']:+d}), "
        f"loss enemy {base['avg_loss_enemy_survived']:.1f} -> "
        f"{cand['avg_loss_enemy_survived']:.1f}"
    )
    print(f"- next signal: {comparison['next_signal']}")
    if comparison["combo_deltas"]:
        print("- offense combo deltas:")
        for combo, row in comparison["combo_deltas"].items():
            print(
                "  - {combo}: frames {frames_delta:+d}, wins {wins_delta:+d}, "
                "losses {losses_delta:+d}, WR Delta {win_rate_delta:+.1%}, "
                "shortfall {damage_shortfall_delta:+d}, loss enemy Delta "
                "{avg_loss_enemy_survived_delta:+.1f}".format(
                    combo=combo,
                    **row,
                )
            )
    print()


def summarize_druid_offense_causal_split(events_per_run, round_min=9, round_max=11):
    """Classify why late Druid focus losses lack or fail Spore+offense pairing."""
    collected = _collect_druid_active_ledger_frames(
        events_per_run,
        round_min,
        round_max,
    )
    rows = [_druid_offense_causal_row(row) for row in collected["frames"]]
    losses = [row for row in rows if not row["won"]]
    summary = {
        "n_runs": len(events_per_run),
        "round_min": round_min,
        "round_max": round_max,
        "frames": len(rows),
        "wins": sum(1 for row in rows if row["won"]),
        "losses": len(losses),
        "missing_round_end": collected["missing_round_end"],
        "detail_coverage": (
            collected["detail_frames"] / len(rows) if rows else 0.0
        ),
        "primary_causal_buckets": dict(
            Counter(row["primary_causal_bucket"] for row in losses)
        ),
        "access_buckets": dict(Counter(row["access_bucket"] for row in losses)),
        "timing_buckets": dict(Counter(row["timing_bucket"] for row in losses)),
        "missing_targets": dict(Counter(row["missing_target"] for row in losses)),
        "spore_offense_frames": sum(1 for row in rows if row["has_pair"]),
        "spore_offense_losses": sum(1 for row in losses if row["has_pair"]),
        "active_pair_under_damage_losses": sum(
            1 for row in losses
            if row["primary_causal_bucket"] == "active_pair_under_damaging"
        ),
        "owned_inactive_losses": sum(
            1 for row in losses if row["access_bucket"] == "owned_inactive"
        ),
        "offered_not_bought_losses": sum(
            1 for row in losses if row["access_bucket"] == "offered_not_bought"
        ),
        "not_seen_or_unavailable_losses": sum(
            1 for row in losses
            if row["access_bucket"] == "not_seen_or_unavailable"
        ),
        "active_too_late_losses": sum(
            1 for row in losses
            if row["primary_causal_bucket"] == "active_too_late"
        ),
        "damage_shortfall_without_pair_losses": sum(
            1 for row in losses
            if row["primary_bottleneck"] == "damage_shortfall"
            and not row["has_pair"]
        ),
        "damage_shortfall_with_pair_losses": sum(
            1 for row in losses
            if row["primary_bottleneck"] == "damage_shortfall"
            and row["has_pair"]
        ),
        "avg_loss_hp_start": _avg(
            [row["hp_start"] for row in losses if row["hp_start"] is not None]
        ),
        "avg_loss_enemy_survived": _avg([row["enemy_survived"] for row in losses]),
        "by_primary_causal_bucket": _summarize_druid_causal_groups(
            losses,
            lambda row: row["primary_causal_bucket"],
        ),
        "by_access_bucket": _summarize_druid_causal_groups(
            losses,
            lambda row: row["access_bucket"],
        ),
        "by_path": _summarize_druid_causal_groups(
            losses,
            lambda row: row["path"],
        ),
        "examples": losses[:10],
        "trace_caveat": (
            "card-id aggregate only; offer/buy/bench facts locate access stage "
            "but not exact duplicate instances or per-unit damage contribution"
        ),
    }
    summary["next_signal"] = _druid_offense_causal_signal(summary)
    return summary


def _druid_offense_causal_row(row):
    result = _druid_offense_row(row)
    active_focus = set(result.get("focus", []))
    owned_cards = set(result.get("owned_board", [])) | set(result.get("bench", []))
    bench_cards = set(result.get("bench", []))
    bought_cards = set(result.get("bought_before_or_at", []))
    offered_cards = set(result.get("offered_before_or_at", []))
    affordable_cards = set(result.get("affordable_before_or_at", []))

    spore_active = DRUID_SPORE_CARD in active_focus
    offense_active = bool(active_focus & DRUID_OFFENSE_CARDS)
    has_pair = spore_active and offense_active

    missing_targets = []
    if spore_active and not offense_active:
        missing_targets = sorted(DRUID_OFFENSE_CARDS)
    elif offense_active and not spore_active:
        missing_targets = [DRUID_SPORE_CARD]

    access_bucket = "active_pair"
    missing_target = "none"
    if missing_targets:
        missing_target = "offense" if missing_targets != [DRUID_SPORE_CARD] else "spore"
        access_bucket = _druid_missing_access_bucket(
            missing_targets,
            owned_cards,
            bench_cards,
            bought_cards,
            offered_cards,
            affordable_cards,
        )

    timing_bucket = _druid_timing_bucket(result.get("hp_start"))
    primary_causal_bucket = _druid_primary_causal_bucket(
        result,
        has_pair,
        access_bucket,
        timing_bucket,
    )
    result.update({
        "has_pair": has_pair,
        "missing_target": missing_target,
        "missing_target_cards": missing_targets,
        "access_bucket": access_bucket,
        "timing_bucket": timing_bucket,
        "primary_causal_bucket": primary_causal_bucket,
    })
    return result


def _druid_missing_access_bucket(
        targets,
        owned_cards,
        bench_cards,
        bought_cards,
        offered_cards,
        affordable_cards):
    if any(card_id in bench_cards for card_id in targets):
        return "owned_inactive"
    if any(card_id in owned_cards for card_id in targets):
        return "owned_inactive"
    if any(card_id in bought_cards for card_id in targets):
        return "bought_not_owned"
    if any(card_id in affordable_cards for card_id in targets):
        return "offered_not_bought"
    if any(card_id in offered_cards for card_id in targets):
        return "offered_unaffordable"
    return "not_seen_or_unavailable"


def _druid_timing_bucket(hp_start):
    if hp_start is None:
        return "unknown"
    hp_start = int(hp_start)
    if hp_start <= 5:
        return "lethal_window"
    if hp_start <= 10:
        return "danger_window"
    return "stable_window"


def _druid_primary_causal_bucket(row, has_pair, access_bucket, timing_bucket):
    if timing_bucket == "lethal_window":
        return "active_too_late"
    primary = row.get("primary_bottleneck", "")
    if has_pair:
        if primary in {"damage_shortfall", "enemy_pressure_spike"}:
            return "active_pair_under_damaging"
        return "active_pair_mixed"
    if access_bucket == "owned_inactive":
        return "owned_inactive"
    if access_bucket == "bought_not_owned":
        return "bought_not_owned"
    if access_bucket in {"offered_not_bought", "offered_unaffordable"}:
        return access_bucket
    if access_bucket == "not_seen_or_unavailable":
        return "not_seen_or_unavailable"
    return "mixed_or_unknown"


def _summarize_druid_causal_groups(rows, key_fn):
    grouped = defaultdict(list)
    for row in rows:
        grouped[key_fn(row)].append(row)
    return {
        key: _finalize_druid_causal_group(group)
        for key, group in sorted(grouped.items())
    }


def _finalize_druid_causal_group(group):
    return {
        "frames": len(group),
        "avg_hp_start": _avg(
            [row["hp_start"] for row in group if row["hp_start"] is not None]
        ),
        "avg_enemy_survived": _avg([row["enemy_survived"] for row in group]),
        "avg_ally_survived": _avg([row["ally_survived"] for row in group]),
        "damage_shortfall": sum(
            1 for row in group if row["primary_bottleneck"] == "damage_shortfall"
        ),
        "debuff_gap": sum(
            1 for row in group
            if row["primary_bottleneck"] in {"debuff_missing", "debuff_too_small"}
        ),
        "missing_targets": dict(Counter(row["missing_target"] for row in group)),
        "timing_buckets": dict(Counter(row["timing_bucket"] for row in group)),
        "primary_bottlenecks": dict(
            Counter(row["primary_bottleneck"] for row in group)
        ),
    }


def _druid_offense_causal_signal(summary):
    losses = int(summary["losses"])
    if not losses:
        return "No R9-R11 Druid focus-active losses in scope."
    primary = Counter(summary["primary_causal_buckets"])
    if not primary:
        return "No causal bucket identified."
    bucket, count = primary.most_common(1)[0]
    share = count / losses
    if bucket == "owned_inactive" and share >= 0.25:
        return (
            f"ACTIVATION_PACKET_CANDIDATE: owned-inactive missing pair pieces "
            f"are the largest causal bucket ({share:.0%}); prepare a narrow "
            "promotion/access packet with strict outcome gates."
        )
    if bucket in {"offered_not_bought", "not_seen_or_unavailable"} and share >= 0.25:
        return (
            f"ACQUISITION_PACKET_CANDIDATE: {bucket} is the largest causal "
            f"bucket ({share:.0%}); inspect scoring, path-lag holds, and tier "
            "access before promotion logic."
        )
    if bucket == "active_pair_under_damaging" and share >= 0.25:
        return (
            f"RUNTIME_MATH_PACKET_CANDIDATE: active Spore+offense pairs still "
            f"under-damage in {share:.0%} of losses; inspect combat contribution "
            "before more access tuning."
        )
    if bucket == "active_too_late" and share >= 0.25:
        return (
            f"TIMING_PACKET_CANDIDATE: focus appears in the lethal window in "
            f"{share:.0%} of losses; inspect earlier acquisition/economy timing."
        )
    return (
        f"MIXED_CAUSAL_SPLIT: largest bucket {bucket} is {share:.0%}; require "
        "more targeted evidence before gameplay edits."
    )


def summarize_druid_offense_causal_comparison(candidate_events, baseline_events):
    candidate = summarize_druid_offense_causal_split(candidate_events)
    baseline = summarize_druid_offense_causal_split(baseline_events)
    comparison = {
        "baseline": _druid_offense_causal_compare_metrics(baseline),
        "candidate": _druid_offense_causal_compare_metrics(candidate),
        "primary_bucket_deltas": _counter_delta(
            candidate["primary_causal_buckets"],
            baseline["primary_causal_buckets"],
        ),
        "access_bucket_deltas": _counter_delta(
            candidate["access_buckets"],
            baseline["access_buckets"],
        ),
        "timing_bucket_deltas": _counter_delta(
            candidate["timing_buckets"],
            baseline["timing_buckets"],
        ),
    }
    comparison["deltas"] = {
        key: comparison["candidate"][key] - comparison["baseline"][key]
        for key in (
            "losses",
            "spore_offense_frames",
            "spore_offense_losses",
            "owned_inactive_losses",
            "offered_not_bought_losses",
            "not_seen_or_unavailable_losses",
            "active_pair_under_damage_losses",
            "active_too_late_losses",
            "damage_shortfall_without_pair_losses",
            "damage_shortfall_with_pair_losses",
            "avg_loss_enemy_survived",
        )
    }
    comparison["next_signal"] = _druid_offense_causal_comparison_signal(
        candidate,
        baseline,
    )
    return comparison


def _druid_offense_causal_compare_metrics(summary):
    return {
        "losses": int(summary["losses"]),
        "spore_offense_frames": int(summary["spore_offense_frames"]),
        "spore_offense_losses": int(summary["spore_offense_losses"]),
        "owned_inactive_losses": int(summary["owned_inactive_losses"]),
        "offered_not_bought_losses": int(summary["offered_not_bought_losses"]),
        "not_seen_or_unavailable_losses": int(
            summary["not_seen_or_unavailable_losses"]
        ),
        "active_pair_under_damage_losses": int(
            summary["active_pair_under_damage_losses"]
        ),
        "active_too_late_losses": int(summary["active_too_late_losses"]),
        "damage_shortfall_without_pair_losses": int(
            summary["damage_shortfall_without_pair_losses"]
        ),
        "damage_shortfall_with_pair_losses": int(
            summary["damage_shortfall_with_pair_losses"]
        ),
        "avg_loss_enemy_survived": float(summary["avg_loss_enemy_survived"]),
    }


def _druid_offense_causal_comparison_signal(candidate, baseline):
    cand_owned_inactive = int(candidate["owned_inactive_losses"])
    base_owned_inactive = int(baseline["owned_inactive_losses"])
    cand_active_pair_under = int(candidate["active_pair_under_damage_losses"])
    base_active_pair_under = int(baseline["active_pair_under_damage_losses"])
    cand_no_seen = int(candidate["not_seen_or_unavailable_losses"])
    base_no_seen = int(baseline["not_seen_or_unavailable_losses"])
    if cand_owned_inactive > base_owned_inactive and cand_owned_inactive >= 6:
        return (
            "PAIR_ACTIVATION_CANDIDATE: owned-inactive missing pair pieces grew "
            "enough to justify a narrow promotion packet, but outcome gates are "
            "still required."
        )
    if cand_no_seen > base_no_seen and cand_no_seen >= cand_owned_inactive:
        return (
            "ACQUISITION_OR_TIER_ACCESS_CANDIDATE: missing pair pieces are more "
            "often absent/unseen than benched; inspect scoring and shop access."
        )
    if cand_active_pair_under > base_active_pair_under and cand_active_pair_under >= 6:
        return (
            "PAIR_RUNTIME_MATH_CANDIDATE: active pairs increasingly fail combat; "
            "inspect Wrath/World contribution before promotion changes."
        )
    return "NO_DECISIVE_CAUSAL_DELTA: do not implement gameplay from this split alone."


def print_druid_offense_causal_split(strat, summary):
    print(f"## {strat} Druid Offense Causal Split")
    print(
        "- scope: "
        f"R{summary['round_min']}-R{summary['round_max']} focus-active battles, "
        f"{summary['frames']} frames/{summary['losses']} losses from "
        f"{summary['n_runs']} runs"
    )
    print(f"- trace caveat: {summary['trace_caveat']}")
    print(
        "- pair/conversion: "
        f"Spore+offense frames {summary['spore_offense_frames']}, losses "
        f"{summary['spore_offense_losses']}, active-pair under-damage "
        f"{summary['active_pair_under_damage_losses']}, shortfall no-pair "
        f"{summary['damage_shortfall_without_pair_losses']}, shortfall with-pair "
        f"{summary['damage_shortfall_with_pair_losses']}"
    )
    print(
        "- access/timing counts: "
        f"owned-inactive {summary['owned_inactive_losses']}, "
        f"offered-not-bought {summary['offered_not_bought_losses']}, "
        f"not-seen/unavailable {summary['not_seen_or_unavailable_losses']}, "
        f"active-too-late {summary['active_too_late_losses']}"
    )
    print(f"- primary causal buckets: {summary['primary_causal_buckets']}")
    print(f"- access buckets: {summary['access_buckets']}")
    print(f"- timing buckets: {summary['timing_buckets']}")
    print(f"- missing targets: {summary['missing_targets']}")
    print(f"- next signal: {summary['next_signal']}")
    if summary["by_primary_causal_bucket"]:
        print("- by primary causal bucket:")
        for bucket, row in summary["by_primary_causal_bucket"].items():
            print(
                "  - {bucket}: frames {frames}, HP {hp:.1f}, A/E "
                "{ally:.1f}/{enemy:.1f}, shortfall {shortfall}, debuff_gap "
                "{debuff_gap}, timing {timing}, missing {missing}".format(
                    bucket=bucket,
                    frames=row["frames"],
                    hp=row["avg_hp_start"],
                    ally=row["avg_ally_survived"],
                    enemy=row["avg_enemy_survived"],
                    shortfall=row["damage_shortfall"],
                    debuff_gap=row["debuff_gap"],
                    timing=row["timing_buckets"],
                    missing=row["missing_targets"],
                )
            )
    if summary["examples"]:
        print("- examples:")
        for row in summary["examples"]:
            print(
                "  - run {run} R{round} {path}: primary {primary_causal_bucket}, "
                "access {access_bucket}, timing {timing_bucket}, missing "
                "{missing_target}:{missing_target_cards}, HP {hp_start}, "
                "focus {focus}, bench {bench}, A/E {ally_survived}/"
                "{enemy_survived}, bottleneck {primary_bottleneck}".format(**row)
            )
    print()


def print_druid_offense_causal_comparison(strat, comparison, baseline_label):
    print(f"## {strat} Druid Offense Causal Comparison")
    print(f"- baseline: {baseline_label}")
    base = comparison["baseline"]
    cand = comparison["candidate"]
    deltas = comparison["deltas"]
    print(
        "- pair frames/losses: "
        f"{base['spore_offense_frames']} -> {cand['spore_offense_frames']} "
        f"(Delta {deltas['spore_offense_frames']:+d}), losses "
        f"{base['spore_offense_losses']} -> {cand['spore_offense_losses']} "
        f"(Delta {deltas['spore_offense_losses']:+d})"
    )
    print(
        "- causal deltas: "
        f"owned-inactive {deltas['owned_inactive_losses']:+d}, "
        f"offered-not-bought {deltas['offered_not_bought_losses']:+d}, "
        f"not-seen/unavailable {deltas['not_seen_or_unavailable_losses']:+d}, "
        f"active-pair under-damage "
        f"{deltas['active_pair_under_damage_losses']:+d}, "
        f"active-too-late {deltas['active_too_late_losses']:+d}"
    )
    print(
        "- shortfall deltas: "
        f"without-pair {deltas['damage_shortfall_without_pair_losses']:+d}, "
        f"with-pair {deltas['damage_shortfall_with_pair_losses']:+d}, "
        f"loss enemy {base['avg_loss_enemy_survived']:.1f} -> "
        f"{cand['avg_loss_enemy_survived']:.1f}"
    )
    print(f"- primary bucket deltas: {comparison['primary_bucket_deltas']}")
    print(f"- access bucket deltas: {comparison['access_bucket_deltas']}")
    print(f"- timing bucket deltas: {comparison['timing_bucket_deltas']}")
    print(f"- next signal: {comparison['next_signal']}")
    print()


def summarize_druid_spore_tree_gap(events_per_run, round_min=9, round_max=11):
    """Audit whether Spore's own trees lag the active Druid forest depth."""
    n_runs = len(events_per_run)
    collected = _collect_druid_active_ledger_frames(
        events_per_run,
        round_min,
        round_max,
    )
    frames = collected["frames"]
    focus_losses = [row for row in frames if not row["won"]]
    spore_rows = [
        _druid_spore_tree_gap_row(row)
        for row in frames
        if DRUID_SPORE_CARD in row["focus"]
    ]
    spore_losses = [row for row in spore_rows if not row["won"]]
    spore_wins = [row for row in spore_rows if row["won"]]
    low_debuff_losses = [
        row for row in spore_losses
        if row["debuff"] < DRUID_SPORE_LOW_DEBUFF_THRESHOLD
    ]
    low_debuff_loss_crossings = [
        row for row in low_debuff_losses
        if row["probe_crosses_threshold"]
    ]
    winning_low_debuff_crossings = [
        row for row in spore_wins
        if row["probe_crosses_threshold"]
    ]

    focus_loss_bottlenecks = Counter(
        row["primary_bottleneck"] for row in focus_losses
    )
    bottlenecks_by_forest_band = defaultdict(Counter)
    for row in focus_losses:
        band = _druid_forest_depth_band(row["active_tree_counters"])
        bottlenecks_by_forest_band[band][row["primary_bottleneck"]] += 1

    spore_loss_by_forest_band = defaultdict(list)
    for row in spore_losses:
        spore_loss_by_forest_band[row["forest_band"]].append(row)

    summary = {
        "n_runs": n_runs,
        "round_min": round_min,
        "round_max": round_max,
        "focus_frames": len(frames),
        "focus_losses": len(focus_losses),
        "spore_frames": len(spore_rows),
        "spore_wins": len(spore_wins),
        "spore_losses": len(spore_losses),
        "tree_coverage": (
            collected["tree_detail_frames"] / len(frames) if frames else 0.0
        ),
        "probe_scale": DRUID_SPORE_FOREST_DEPTH_PROBE_SCALE,
        "probe_cap": DRUID_SPORE_DEBUFF_CAP,
        "low_debuff_threshold": DRUID_SPORE_LOW_DEBUFF_THRESHOLD,
        "low_own_tree_max": DRUID_SPORE_LOW_OWN_TREE_MAX,
        "high_forest_min": DRUID_SPORE_HIGH_FOREST_MIN,
        "avg_spore_own_trees": _avg([row["spore_own_trees"] for row in spore_rows]),
        "avg_active_tree_counters": _avg(
            [row["active_tree_counters"] for row in spore_rows]
        ),
        "avg_other_druid_trees": _avg([row["other_druid_trees"] for row in spore_rows]),
        "avg_own_total_ratio": _avg([row["own_total_ratio"] for row in spore_rows]),
        "loss_avg_spore_own_trees": _avg(
            [row["spore_own_trees"] for row in spore_losses]
        ),
        "loss_avg_active_tree_counters": _avg(
            [row["active_tree_counters"] for row in spore_losses]
        ),
        "loss_avg_other_druid_trees": _avg(
            [row["other_druid_trees"] for row in spore_losses]
        ),
        "loss_avg_current_debuff": _avg([row["debuff"] for row in spore_losses]),
        "loss_avg_probe_debuff": _avg([row["probe_debuff"] for row in spore_losses]),
        "zero_own_high_forest_loss_frames": sum(
            1 for row in spore_losses if row["zero_own_high_forest"]
        ),
        "low_own_high_forest_loss_frames": sum(
            1 for row in spore_losses if row["low_own_high_forest"]
        ),
        "low_debuff_losses": len(low_debuff_losses),
        "low_debuff_loss_crossings": len(low_debuff_loss_crossings),
        "winning_low_debuff_crossings": len(winning_low_debuff_crossings),
        "focus_loss_bottlenecks": dict(focus_loss_bottlenecks),
        "bottlenecks_by_forest_band": {
            band: dict(counts)
            for band, counts in sorted(
                bottlenecks_by_forest_band.items(),
                key=lambda item: _druid_forest_depth_band_order(item[0]),
            )
        },
        "spore_loss_by_forest_band": {
            band: _finalize_druid_spore_tree_gap_group(group)
            for band, group in sorted(
                spore_loss_by_forest_band.items(),
                key=lambda item: _druid_forest_depth_band_order(item[0]),
            )
        },
        "examples": spore_losses[:8],
        "trace_caveat": (
            "card-id aggregate only; duplicate copies can collapse in trace states, "
            "and buy events do not include per-card tree counters"
        ),
    }
    summary["next_signal"] = _druid_spore_tree_gap_signal(summary)
    return summary


def _druid_spore_tree_gap_row(row):
    spore_detail = next(
        item for item in row["focus_details"]
        if item["card_id"] == DRUID_SPORE_CARD
    )
    spore_own_trees = int(spore_detail.get("trees", 0))
    active_tree_counters = int(row.get("active_tree_counters", 0))
    other_druid_trees = max(0, active_tree_counters - spore_own_trees)
    debuff = float(row.get("debuff", 0.0))
    probe_debuff = min(
        DRUID_SPORE_DEBUFF_CAP,
        debuff + other_druid_trees * DRUID_SPORE_FOREST_DEPTH_PROBE_SCALE,
    )
    result = dict(row)
    result.update({
        "spore_star": int(spore_detail.get("star", 1)),
        "spore_own_trees": spore_own_trees,
        "other_druid_trees": other_druid_trees,
        "own_total_ratio": (
            spore_own_trees / active_tree_counters
            if active_tree_counters else 0.0
        ),
        "forest_band": _druid_forest_depth_band(active_tree_counters),
        "probe_debuff": probe_debuff,
        "probe_debuff_lift": probe_debuff - debuff,
        "probe_crosses_threshold": (
            debuff < DRUID_SPORE_LOW_DEBUFF_THRESHOLD
            and probe_debuff >= DRUID_SPORE_LOW_DEBUFF_THRESHOLD
        ),
        "zero_own_high_forest": (
            spore_own_trees == 0
            and active_tree_counters >= DRUID_SPORE_HIGH_FOREST_MIN
        ),
        "low_own_high_forest": (
            spore_own_trees <= DRUID_SPORE_LOW_OWN_TREE_MAX
            and active_tree_counters >= DRUID_SPORE_HIGH_FOREST_MIN
        ),
    })
    return result


def _druid_forest_depth_band(tree_counters):
    tree_counters = int(tree_counters)
    if tree_counters <= 8:
        return "0-8"
    if tree_counters <= 17:
        return "9-17"
    if tree_counters <= 26:
        return "18-26"
    return "27+"


def _druid_forest_depth_band_order(band):
    return {"0-8": 0, "9-17": 1, "18-26": 2, "27+": 3}.get(band, 99)


def _finalize_druid_spore_tree_gap_group(group):
    return {
        "frames": len(group),
        "low_debuff": sum(
            1 for row in group
            if row["debuff"] < DRUID_SPORE_LOW_DEBUFF_THRESHOLD
        ),
        "crosses_threshold": sum(
            1 for row in group if row["probe_crosses_threshold"]
        ),
        "avg_spore_own_trees": _avg([row["spore_own_trees"] for row in group]),
        "avg_active_tree_counters": _avg(
            [row["active_tree_counters"] for row in group]
        ),
        "avg_other_druid_trees": _avg([row["other_druid_trees"] for row in group]),
        "avg_current_debuff": _avg([row["debuff"] for row in group]),
        "avg_probe_debuff": _avg([row["probe_debuff"] for row in group]),
    }


def _druid_spore_tree_gap_signal(summary):
    spore_losses = int(summary["spore_losses"])
    if not spore_losses:
        return "No R9-R11 Spore-active losses in scope."

    focus_losses = int(summary["focus_losses"])
    debuff_missing = int(summary["focus_loss_bottlenecks"].get("debuff_missing", 0))
    if focus_losses and debuff_missing / focus_losses >= 0.45:
        return (
            "DEFER_FOREST_DEPTH_PACKET_DEBUFF_MISSING_DOMINATES: Spore scaling "
            "cannot address most focus-active losses."
        )

    low_own_high = int(summary["low_own_high_forest_loss_frames"])
    low_debuff_losses = int(summary["low_debuff_losses"])
    low_debuff_crossings = int(summary["low_debuff_loss_crossings"])
    winning_crossings = int(summary["winning_low_debuff_crossings"])
    gap_share = low_own_high / spore_losses if spore_losses else 0.0
    crossing_share = (
        low_debuff_crossings / low_debuff_losses
        if low_debuff_losses else 0.0
    )
    if (
        gap_share >= 0.45
        and low_debuff_losses
        and crossing_share >= 0.45
        and low_debuff_crossings > winning_crossings
    ):
        return (
            "PACKET_CANDIDATE_FOREST_DEPTH_SPORE_SCALING: active Spore losses "
            "show low own trees, high board forest depth, and threshold-crossing "
            "diagnostic lift."
        )
    if low_debuff_losses and not low_debuff_crossings:
        return (
            "NO_PACKET_YET_COUNTERFACTUAL_TOO_WEAK: low-debuff Spore losses do "
            "not cross the diagnostic threshold."
        )
    if gap_share < 0.35:
        return (
            "NO_PACKET_YET_SPORE_OWN_TREE_GAP_WEAK: Spore own counters are not "
            "systematically lagging high forest depth."
        )
    return "INSPECT_MORE: tree-gap signal is mixed; require same-seed outcome movement."


def print_druid_spore_tree_gap(strat, summary):
    print(f"## {strat} Druid Spore Tree-Gap Audit")
    print(
        "- scope: "
        f"R{summary['round_min']}-R{summary['round_max']} focus-active battles, "
        f"{summary['focus_frames']} frames/{summary['focus_losses']} losses "
        f"from {summary['n_runs']} runs"
    )
    print(f"- trace caveat: {summary['trace_caveat']}")
    print(
        "- Spore active: "
        f"{summary['spore_frames']} frames, "
        f"{summary['spore_wins']} won/{summary['spore_losses']} lost, "
        f"tree coverage {summary['tree_coverage']:.1%}"
    )
    print(
        "- tree gap: "
        f"avg Spore own {summary['avg_spore_own_trees']:.1f}, "
        f"avg active Druid trees {summary['avg_active_tree_counters']:.1f}, "
        f"avg other-Druid trees {summary['avg_other_druid_trees']:.1f}, "
        f"own/total ratio {summary['avg_own_total_ratio']:.1%}"
    )
    if summary["spore_losses"]:
        print(
            "- Spore losses: "
            f"avg own {summary['loss_avg_spore_own_trees']:.1f}, "
            f"avg total {summary['loss_avg_active_tree_counters']:.1f}, "
            f"avg other {summary['loss_avg_other_druid_trees']:.1f}, "
            f"current debuff {summary['loss_avg_current_debuff']:.1%}, "
            f"diagnostic probe debuff {summary['loss_avg_probe_debuff']:.1%}"
        )
        print(
            "- low-own/high-forest losses: "
            f"zero-own {summary['zero_own_high_forest_loss_frames']}, "
            f"own<= {summary['low_own_tree_max']} and total>= "
            f"{summary['high_forest_min']}: "
            f"{summary['low_own_high_forest_loss_frames']}"
        )
    print(
        "- diagnostic counterfactual: "
        f"adds other-Druid trees * {summary['probe_scale']:.4f}, "
        f"cap {summary['probe_cap']:.0%}, threshold "
        f"{summary['low_debuff_threshold']:.0%}; "
        f"low-debuff loss crossings "
        f"{summary['low_debuff_loss_crossings']}/{summary['low_debuff_losses']}, "
        f"winning crossings {summary['winning_low_debuff_crossings']}"
    )
    print(f"- focus-loss bottlenecks: {summary['focus_loss_bottlenecks']}")
    if summary["bottlenecks_by_forest_band"]:
        print("- focus-loss bottlenecks by active forest depth:")
        for band, counts in summary["bottlenecks_by_forest_band"].items():
            print(f"  - {band}: {counts}")
    if summary["spore_loss_by_forest_band"]:
        print("- Spore losses by active forest depth:")
        for band, row in summary["spore_loss_by_forest_band"].items():
            print(
                "  - {band}: frames {frames}, low-debuff {low_debuff}, "
                "crosses {crosses_threshold}, own {own:.1f}, total {total:.1f}, "
                "other {other:.1f}, debuff {current:.1%}->{probe:.1%}".format(
                    band=band,
                    frames=row["frames"],
                    low_debuff=row["low_debuff"],
                    crosses_threshold=row["crosses_threshold"],
                    own=row["avg_spore_own_trees"],
                    total=row["avg_active_tree_counters"],
                    other=row["avg_other_druid_trees"],
                    current=row["avg_current_debuff"],
                    probe=row["avg_probe_debuff"],
                )
            )
    print(f"- next signal: {summary['next_signal']}")
    if summary["examples"]:
        print("- Spore loss examples:")
        for row in summary["examples"]:
            print(
                "  - run {run} R{round} {path}: Spore ★{spore_star}/T"
                "{spore_own_trees}, active trees {active_tree_counters} "
                "(other {other_druid_trees}, band {forest_band}), debuff "
                "{debuff:.1%}->{probe_debuff:.1%}, survivors "
                "A{ally_survived}/E{enemy_survived}, bucket "
                "{primary_bottleneck}, final HP {final_hp}".format(**row)
            )
    print()


def summarize_druid_run_phase(events_per_run, round_min=8, round_max=12):
    """Summarize Druid payoff timing against survival and conversion windows."""
    rows = []
    round_summaries = defaultdict(_new_druid_phase_round_summary)
    rows_by_path = defaultdict(list)

    for idx, events in enumerate(events_per_run):
        row = _druid_phase_run_row(events, idx, round_min, round_max)
        rows.append(row)
        rows_by_path[row["detected_path"]].append(row)
        for round_num, round_row in row["rounds"].items():
            _merge_druid_phase_round(round_summaries[round_num], round_row)

    conversion_buckets = Counter(row["conversion_bucket"] for row in rows)
    summary = {
        "n_runs": len(rows),
        "round_min": round_min,
        "round_max": round_max,
        "wins": sum(1 for row in rows if row["run_won"]),
        "losses": sum(1 for row in rows if not row["run_won"]),
        "conversion_buckets": dict(conversion_buckets),
        "timing": {
            "all": _summarize_druid_phase_rows(rows),
            "wins": _summarize_druid_phase_rows(
                [row for row in rows if row["run_won"]]
            ),
            "losses": _summarize_druid_phase_rows(
                [row for row in rows if not row["run_won"]]
            ),
        },
        "by_path": {
            path_id: _summarize_druid_phase_rows(group)
            for path_id, group in sorted(rows_by_path.items())
        },
        "rounds": {
            round_num: _finalize_druid_phase_round(round_summary)
            for round_num, round_summary in sorted(round_summaries.items())
        },
        "false_green_examples": _druid_false_green_examples(rows),
    }
    summary["next_signal"] = _druid_run_phase_signal(summary)
    return summary


def _druid_phase_run_row(events, run_idx, round_min, round_max):
    run_end = next((ev for ev in reversed(events) if ev.get("t") == "run_end"), {})
    battles = [ev for ev in events if ev.get("t") == "battle"]
    round_starts = [ev for ev in events if ev.get("t") == "round_start"]
    round_ends = [ev for ev in events if ev.get("t") == "round_end"]
    buys = [ev for ev in events if ev.get("t") == "buy"]
    buy_skips = [ev for ev in events if ev.get("t") == "buy_skip"]
    levelups = [ev for ev in events if ev.get("t") == "levelup"]

    battle_by_round = {int(ev.get("round", 0)): ev for ev in battles}
    round_start_by_round = {
        int(ev.get("round", 0)): ev for ev in round_starts
    }
    round_end_by_round = {
        int(ev.get("round", 0)): ev for ev in round_ends
    }
    path_lag_by_round = Counter(
        int(ev.get("round", 0))
        for ev in buy_skips
        if ev.get("reason") == "path_lag_hold"
    )
    buy_skip_by_round = Counter(int(ev.get("round", 0)) for ev in buy_skips)

    run_won = bool(run_end.get(
        "won",
        battles[-1].get("won", False) if battles else False,
    ))
    death_round = int(run_end.get(
        "rounds_played",
        battles[-1].get("round", 0) if battles else 0,
    ))
    detected_path = "undetected"
    for ev in reversed(round_ends):
        if ev.get("detected_path"):
            detected_path = str(ev.get("detected_path", ""))
            break

    first_offer_by_card = {card_id: None for card_id in DRUID_PAYOFF_CARDS}
    first_affordable_by_card = {card_id: None for card_id in DRUID_PAYOFF_CARDS}
    first_buy_by_card = {card_id: None for card_id in DRUID_PAYOFF_CARDS}
    affordable_payoff_skip_rounds = []

    for ev in buys + buy_skips:
        round_num = int(ev.get("round", 0))
        affordable_payoffs = set()
        for offer in ev.get("offers") or []:
            card_id = offer.get("id", "")
            if card_id not in DRUID_PAYOFF_CARDS:
                continue
            if first_offer_by_card[card_id] is None:
                first_offer_by_card[card_id] = round_num
            if bool(offer.get("affordable", False)):
                affordable_payoffs.add(card_id)
                if first_affordable_by_card[card_id] is None:
                    first_affordable_by_card[card_id] = round_num

        bought_card = ev.get("card_id", "")
        if ev.get("t") == "buy" and bought_card in DRUID_PAYOFF_CARDS:
            if first_buy_by_card[bought_card] is None:
                first_buy_by_card[bought_card] = round_num
        if affordable_payoffs and bought_card not in affordable_payoffs:
            affordable_payoff_skip_rounds.append(round_num)

    first_payoff_active_round = None
    first_focus_active_round = None
    first_both_payoffs_active_round = None
    focus_cards_at_first_activation = []
    active_druid_at_first_activation = 0
    active_neutral_at_first_activation = 0
    active_trees_at_first_activation = 0
    payoff_owned_not_active_rounds = 0

    for ev in round_ends:
        round_num = int(ev.get("round", 0))
        active_board = set(ev.get("active_board") or [])
        owned_board = set(ev.get("board") or [])
        active_payoffs = active_board & DRUID_PAYOFF_CARDS
        active_focus = active_board & DRUID_FOCUS_CARDS
        inactive_owned_payoffs = (owned_board & DRUID_PAYOFF_CARDS) - active_payoffs
        if inactive_owned_payoffs:
            payoff_owned_not_active_rounds += 1
        if active_payoffs and first_payoff_active_round is None:
            first_payoff_active_round = round_num
        if active_focus and first_focus_active_round is None:
            states = ev.get("states")
            if not isinstance(states, dict):
                states = {}
            first_focus_active_round = round_num
            focus_cards_at_first_activation = sorted(active_focus)
            active_druid_at_first_activation = sum(
                1 for card_id in active_board if str(card_id).startswith("dr_")
            )
            active_neutral_at_first_activation = sum(
                1 for card_id in active_board if str(card_id).startswith("ne_")
            )
            active_trees_at_first_activation = _sum_active_trees(active_board, states)
        if DRUID_PAYOFF_CARDS.issubset(active_board):
            if first_both_payoffs_active_round is None:
                first_both_payoffs_active_round = round_num

    first_offer_round = _min_present(first_offer_by_card.values())
    first_affordable_round = _min_present(first_affordable_by_card.values())
    first_payoff_buy_round = _min_present(first_buy_by_card.values())
    first_both_payoffs_bought_round = (
        max(first_buy_by_card.values())
        if all(value is not None for value in first_buy_by_card.values())
        else None
    )
    hp_at_first_buy = _hp_at_round(first_payoff_buy_round, round_start_by_round, battles)
    hp_at_first_focus_active = _hp_at_round(
        first_focus_active_round,
        round_start_by_round,
        battles,
    )

    pre_activation_battle = None
    post_activation_battle = None
    if first_focus_active_round is not None:
        for battle in battles:
            round_num = int(battle.get("round", 0))
            if round_num < first_focus_active_round:
                pre_activation_battle = _druid_phase_battle_row(battle)
                continue
            round_end = round_end_by_round.get(round_num, {})
            active_board = set(round_end.get("active_board") or [])
            if active_board & DRUID_FOCUS_CARDS:
                post_activation_battle = _druid_phase_battle_row(battle)
                break

    rounds_until_death_after_activation = None
    battles_after_activation = 0
    if first_focus_active_round is not None:
        battles_after_activation = sum(
            1
            for battle in battles
            if int(battle.get("round", 0)) >= first_focus_active_round
        )
        if not run_won:
            rounds_until_death_after_activation = (
                death_round - first_focus_active_round
            )

    round_rows = {}
    for round_num in range(round_min, round_max + 1):
        round_rows[round_num] = _druid_phase_round_row(
            round_num,
            round_start_by_round.get(round_num),
            round_end_by_round.get(round_num),
            battle_by_round.get(round_num),
            int(path_lag_by_round.get(round_num, 0)),
            int(buy_skip_by_round.get(round_num, 0)),
        )

    row = {
        "run": run_idx,
        "run_won": run_won,
        "final_hp": int(run_end.get("final_hp", 0)),
        "death_round": death_round,
        "detected_path": detected_path,
        "first_level4_round": _first_shop_level_round(round_starts, levelups, 4),
        "first_offer_by_card": first_offer_by_card,
        "first_affordable_by_card": first_affordable_by_card,
        "first_buy_by_card": first_buy_by_card,
        "first_payoff_offer_round": first_offer_round,
        "first_payoff_affordable_round": first_affordable_round,
        "first_payoff_buy_round": first_payoff_buy_round,
        "first_both_payoffs_bought_round": first_both_payoffs_bought_round,
        "first_payoff_active_round": first_payoff_active_round,
        "first_focus_active_round": first_focus_active_round,
        "first_both_payoffs_active_round": first_both_payoffs_active_round,
        "hp_at_first_buy": hp_at_first_buy,
        "hp_at_first_focus_active": hp_at_first_focus_active,
        "focus_cards_at_first_activation": focus_cards_at_first_activation,
        "active_druid_at_first_activation": active_druid_at_first_activation,
        "active_neutral_at_first_activation": active_neutral_at_first_activation,
        "active_trees_at_first_activation": active_trees_at_first_activation,
        "payoff_owned_not_active_rounds": payoff_owned_not_active_rounds,
        "affordable_payoff_skip_events": len(affordable_payoff_skip_rounds),
        "path_lag_holds": sum(path_lag_by_round.values()),
        "pre_activation_battle": pre_activation_battle,
        "post_activation_battle": post_activation_battle,
        "rounds_until_death_after_activation": rounds_until_death_after_activation,
        "battles_after_activation": battles_after_activation,
        "rounds": round_rows,
    }
    row["conversion_bucket"] = _classify_druid_phase_conversion(row)
    return row


def _min_present(values):
    present = [value for value in values if value is not None]
    return min(present) if present else None


def _hp_at_round(round_num, round_start_by_round, battles):
    if round_num is None:
        return None
    round_start = round_start_by_round.get(round_num)
    if isinstance(round_start, dict) and "hp" in round_start:
        return int(round_start.get("hp", 0))
    hp = None
    for battle in battles:
        battle_round = int(battle.get("round", 0))
        if battle_round >= round_num:
            break
        if "hp_after" in battle:
            hp = int(battle.get("hp_after", 0))
    return hp


def _druid_phase_battle_row(battle):
    return {
        "round": int(battle.get("round", 0)),
        "won": bool(battle.get("won", False)),
        "hp_after": int(battle.get("hp_after", 0)),
        "ally_survived": int(battle.get("ally_survived", 0)),
        "enemy_survived": int(battle.get("enemy_survived", 0)),
        "debuff": _battle_max_enemy_debuff(battle),
    }


def _druid_phase_round_row(
    round_num,
    round_start,
    round_end,
    battle,
    path_lag_holds,
    buy_skips,
):
    active_board = set()
    owned_board = set()
    states = {}
    if isinstance(round_end, dict):
        active_board = set(round_end.get("active_board") or [])
        owned_board = set(round_end.get("board") or [])
        states = round_end.get("states")
        if not isinstance(states, dict):
            states = {}

    active_payoffs = active_board & DRUID_PAYOFF_CARDS
    active_focus = active_board & DRUID_FOCUS_CARDS
    owned_payoffs = owned_board & DRUID_PAYOFF_CARDS
    inactive_owned_payoffs = owned_payoffs - active_payoffs
    active_druid_cards = sum(
        1 for card_id in active_board if str(card_id).startswith("dr_")
    )
    active_neutral_cards = sum(
        1 for card_id in active_board if str(card_id).startswith("ne_")
    )

    row = {
        "round": round_num,
        "reached": bool(round_start or round_end or battle),
        "round_end_seen": isinstance(round_end, dict),
        "hp_start": None,
        "shop_level": None,
        "gold_start": None,
        "path_lag_holds": path_lag_holds,
        "buy_skips": buy_skips,
        "payoff_owned_not_active": bool(inactive_owned_payoffs),
        "focus_active": bool(active_focus),
        "payoff_active": bool(active_payoffs),
        "both_payoffs_active": DRUID_PAYOFF_CARDS.issubset(active_board),
        "spore_active": "dr_spore_cloud" in active_board,
        "wrath_active": "dr_wrath" in active_board,
        "active_druid_cards": active_druid_cards,
        "active_neutral_cards": active_neutral_cards,
        "active_tree_counters": _sum_active_trees(active_board, states),
        "battle_seen": isinstance(battle, dict),
        "battle_won": False,
        "hp_after": None,
        "ally_survived": 0,
        "enemy_survived": 0,
        "debuff": 0.0,
    }
    if isinstance(round_start, dict):
        row["hp_start"] = int(round_start.get("hp", 0))
        row["shop_level"] = int(round_start.get("shop_level", 0))
        row["gold_start"] = int(round_start.get("gold", 0))
    if isinstance(battle, dict):
        row["battle_won"] = bool(battle.get("won", False))
        row["hp_after"] = int(battle.get("hp_after", 0))
        row["ally_survived"] = int(battle.get("ally_survived", 0))
        row["enemy_survived"] = int(battle.get("enemy_survived", 0))
        row["debuff"] = _battle_max_enemy_debuff(battle)
    return row


def _classify_druid_phase_conversion(row):
    if row["run_won"]:
        return "converted"
    if row["first_payoff_buy_round"] is None:
        if row["first_payoff_offer_round"] is None:
            return "no_payoff_seen"
        return "offered_not_bought"
    if row["first_payoff_active_round"] is None:
        return "bought_not_active"
    rounds_to_death = row["rounds_until_death_after_activation"]
    hp_at_activation = row["hp_at_first_focus_active"]
    if rounds_to_death is not None and rounds_to_death <= 1:
        return "active_too_late"
    if hp_at_activation is not None and hp_at_activation <= 10:
        return "active_too_late"
    post_battle = row["post_activation_battle"]
    if isinstance(post_battle, dict) and not post_battle["won"]:
        return "active_no_combat_swing"
    if isinstance(post_battle, dict) and post_battle["won"]:
        return "active_no_survival_swing"
    return "active_no_combat_swing"


def _new_druid_phase_round_summary():
    return {
        "runs_reached": 0,
        "round_ends": 0,
        "battles": 0,
        "wins": 0,
        "losses": 0,
        "focus_active": 0,
        "payoff_active": 0,
        "both_payoffs_active": 0,
        "spore_active": 0,
        "wrath_active": 0,
        "payoff_owned_not_active": 0,
        "path_lag_holds": 0,
        "buy_skips": 0,
        "hp_start": [],
        "hp_after": [],
        "loss_ally_survived": [],
        "loss_enemy_survived": [],
        "active_druid_cards": [],
        "active_neutral_cards": [],
        "active_tree_counters": [],
        "debuffs": [],
    }


def _merge_druid_phase_round(summary, row):
    if row["reached"]:
        summary["runs_reached"] += 1
    if row["round_end_seen"]:
        summary["round_ends"] += 1
        if row["focus_active"]:
            summary["focus_active"] += 1
        if row["payoff_active"]:
            summary["payoff_active"] += 1
        if row["both_payoffs_active"]:
            summary["both_payoffs_active"] += 1
        if row["spore_active"]:
            summary["spore_active"] += 1
        if row["wrath_active"]:
            summary["wrath_active"] += 1
        if row["payoff_owned_not_active"]:
            summary["payoff_owned_not_active"] += 1
        summary["active_druid_cards"].append(row["active_druid_cards"])
        summary["active_neutral_cards"].append(row["active_neutral_cards"])
        summary["active_tree_counters"].append(row["active_tree_counters"])
    if row["battle_seen"]:
        summary["battles"] += 1
        if row["battle_won"]:
            summary["wins"] += 1
        else:
            summary["losses"] += 1
            summary["loss_ally_survived"].append(row["ally_survived"])
            summary["loss_enemy_survived"].append(row["enemy_survived"])
        if row["hp_after"] is not None:
            summary["hp_after"].append(row["hp_after"])
        summary["debuffs"].append(row["debuff"])
    if row["hp_start"] is not None:
        summary["hp_start"].append(row["hp_start"])
    summary["path_lag_holds"] += row["path_lag_holds"]
    summary["buy_skips"] += row["buy_skips"]


def _finalize_druid_phase_round(summary):
    state_denominator = summary["round_ends"]
    battles = summary["battles"]
    result = dict(summary)
    result["battle_win_rate"] = _safe_rate(summary["wins"], battles)
    result["focus_active_rate"] = _safe_rate(summary["focus_active"], state_denominator)
    result["payoff_active_rate"] = _safe_rate(summary["payoff_active"], state_denominator)
    result["both_payoffs_active_rate"] = _safe_rate(
        summary["both_payoffs_active"],
        state_denominator,
    )
    result["spore_active_rate"] = _safe_rate(summary["spore_active"], state_denominator)
    result["wrath_active_rate"] = _safe_rate(summary["wrath_active"], state_denominator)
    result["payoff_owned_not_active_rate"] = _safe_rate(
        summary["payoff_owned_not_active"],
        state_denominator,
    )
    result["avg_hp_start"] = _avg(summary["hp_start"])
    result["avg_hp_after"] = _avg(summary["hp_after"])
    result["avg_loss_ally_survived"] = _avg(summary["loss_ally_survived"])
    result["avg_loss_enemy_survived"] = _avg(summary["loss_enemy_survived"])
    result["avg_active_druid_cards"] = _avg(summary["active_druid_cards"])
    result["avg_active_neutral_cards"] = _avg(summary["active_neutral_cards"])
    result["avg_active_tree_counters"] = _avg(summary["active_tree_counters"])
    result["avg_debuff"] = _avg(summary["debuffs"])
    return result


def _summarize_druid_phase_rows(rows):
    n_runs = len(rows)
    focus_active_losses = [
        row for row in rows
        if not row["run_won"] and row["first_focus_active_round"] is not None
    ]
    post_activation_battles = [
        row["post_activation_battle"]
        for row in rows
        if isinstance(row["post_activation_battle"], dict)
    ]
    conversion_buckets = Counter(row["conversion_bucket"] for row in rows)
    return {
        "n_runs": n_runs,
        "wins": sum(1 for row in rows if row["run_won"]),
        "losses": sum(1 for row in rows if not row["run_won"]),
        "avg_final_hp": _avg([row["final_hp"] for row in rows]),
        "avg_death_round": _avg([row["death_round"] for row in rows]),
        "payoff_offer_rate": _safe_rate(
            sum(1 for row in rows if row["first_payoff_offer_round"] is not None),
            n_runs,
        ),
        "payoff_affordable_rate": _safe_rate(
            sum(1 for row in rows if row["first_payoff_affordable_round"] is not None),
            n_runs,
        ),
        "payoff_buy_rate": _safe_rate(
            sum(1 for row in rows if row["first_payoff_buy_round"] is not None),
            n_runs,
        ),
        "payoff_active_rate": _safe_rate(
            sum(1 for row in rows if row["first_payoff_active_round"] is not None),
            n_runs,
        ),
        "focus_active_rate": _safe_rate(
            sum(1 for row in rows if row["first_focus_active_round"] is not None),
            n_runs,
        ),
        "both_payoffs_active_rate": _safe_rate(
            sum(
                1
                for row in rows
                if row["first_both_payoffs_active_round"] is not None
            ),
            n_runs,
        ),
        "avg_first_offer_round": _avg([
            row["first_payoff_offer_round"]
            for row in rows
            if row["first_payoff_offer_round"] is not None
        ]),
        "avg_first_affordable_round": _avg([
            row["first_payoff_affordable_round"]
            for row in rows
            if row["first_payoff_affordable_round"] is not None
        ]),
        "avg_first_buy_round": _avg([
            row["first_payoff_buy_round"]
            for row in rows
            if row["first_payoff_buy_round"] is not None
        ]),
        "avg_first_payoff_active_round": _avg([
            row["first_payoff_active_round"]
            for row in rows
            if row["first_payoff_active_round"] is not None
        ]),
        "avg_first_focus_active_round": _avg([
            row["first_focus_active_round"]
            for row in rows
            if row["first_focus_active_round"] is not None
        ]),
        "avg_first_both_payoffs_active_round": _avg([
            row["first_both_payoffs_active_round"]
            for row in rows
            if row["first_both_payoffs_active_round"] is not None
        ]),
        "avg_hp_at_first_buy": _avg([
            row["hp_at_first_buy"]
            for row in rows
            if row["hp_at_first_buy"] is not None
        ]),
        "avg_hp_at_first_focus_active": _avg([
            row["hp_at_first_focus_active"]
            for row in rows
            if row["hp_at_first_focus_active"] is not None
        ]),
        "active_dead_same_round": sum(
            1
            for row in focus_active_losses
            if row["rounds_until_death_after_activation"] is not None
            and row["rounds_until_death_after_activation"] <= 0
        ),
        "active_dead_within_1_round": sum(
            1
            for row in focus_active_losses
            if row["rounds_until_death_after_activation"] is not None
            and row["rounds_until_death_after_activation"] <= 1
        ),
        "active_dead_within_2_rounds": sum(
            1
            for row in focus_active_losses
            if row["rounds_until_death_after_activation"] is not None
            and row["rounds_until_death_after_activation"] <= 2
        ),
        "active_loss_runs": len(focus_active_losses),
        "post_activation_battle_win_rate": _safe_rate(
            sum(1 for battle in post_activation_battles if battle["won"]),
            len(post_activation_battles),
        ),
        "avg_post_activation_enemy_survived": _avg([
            battle["enemy_survived"] for battle in post_activation_battles
        ]),
        "avg_post_activation_ally_survived": _avg([
            battle["ally_survived"] for battle in post_activation_battles
        ]),
        "avg_path_lag_holds": _avg([row["path_lag_holds"] for row in rows]),
        "avg_affordable_payoff_skip_events": _avg([
            row["affordable_payoff_skip_events"] for row in rows
        ]),
        "avg_payoff_owned_not_active_rounds": _avg([
            row["payoff_owned_not_active_rounds"] for row in rows
        ]),
        "conversion_buckets": dict(conversion_buckets),
    }


def _druid_false_green_examples(rows):
    examples = []
    for row in rows:
        if row["run_won"] or row["first_focus_active_round"] is None:
            continue
        post = row["post_activation_battle"] or {}
        rounds_to_death = row["rounds_until_death_after_activation"]
        if rounds_to_death is None or rounds_to_death > 2:
            continue
        examples.append({
            "run": row["run"],
            "path": row["detected_path"],
            "bucket": row["conversion_bucket"],
            "death_round": row["death_round"],
            "final_hp": row["final_hp"],
            "first_focus_active_round": row["first_focus_active_round"],
            "hp_at_activation": row["hp_at_first_focus_active"],
            "rounds_until_death": rounds_to_death,
            "focus": row["focus_cards_at_first_activation"],
            "active_druid_cards": row["active_druid_at_first_activation"],
            "active_tree_counters": row["active_trees_at_first_activation"],
            "post_won": bool(post.get("won", False)),
            "post_enemy_survived": int(post.get("enemy_survived", 0)),
            "post_ally_survived": int(post.get("ally_survived", 0)),
        })
    examples.sort(
        key=lambda item: (
            item["rounds_until_death"],
            item["hp_at_activation"] if item["hp_at_activation"] is not None else 999,
            -item["post_enemy_survived"],
        )
    )
    return examples[:5]


def _druid_run_phase_signal(summary):
    losses = summary["timing"]["losses"]
    if not losses["n_runs"]:
        return "No Druid losses in scope; pivot to broader completion blockers."
    buckets = Counter(summary["conversion_buckets"])
    primary, count = buckets.most_common(1)[0]
    priority = [
        "active_too_late",
        "bought_not_active",
        "active_no_combat_swing",
        "active_no_survival_swing",
        "offered_not_bought",
        "no_payoff_seen",
    ]
    for bucket in priority:
        if buckets.get(bucket, 0) == count and count > 0:
            primary = bucket
            break
    share = count / summary["n_runs"] if summary["n_runs"] else 0.0
    if primary in ("no_payoff_seen", "offered_not_bought"):
        return (
            f"{primary} leads the run-phase read ({share:.0%}); inspect payoff "
            "offer/affordability/path-lag policy before combat numbers."
        )
    if primary == "bought_not_active":
        return (
            f"Bought payoff pieces are not reaching the board ({share:.0%}); "
            "inspect activation/promotion and bench pressure next."
        )
    if primary == "active_too_late":
        return (
            f"Focus activation commonly happens in the lethal window ({share:.0%}); "
            "inspect timing, HP-at-activation, and economy pressure before "
            "more payoff tuning."
        )
    if primary == "active_no_combat_swing":
        return (
            f"Active payoffs still lose their first combat ({share:.0%}); inspect "
            "board-state conversion or combat math instead of acquisition."
        )
    if primary == "active_no_survival_swing":
        return (
            f"Active payoffs win locally but do not stabilize the run ({share:.0%}); "
            "inspect post-activation survival curve and enemy pressure."
        )
    return f"{primary} is the largest conversion bucket ({share:.0%})."


def print_druid_run_phase(strat, summary):
    print(f"## {strat} Druid Run-Phase Survival")
    print(
        "- scope: "
        f"R{summary['round_min']}-R{summary['round_max']} timing window, "
        f"{summary['n_runs']} runs"
    )
    print(
        "- results: "
        f"{summary['wins']} wins/{summary['losses']} losses, "
        f"conversion buckets {summary['conversion_buckets']}"
    )
    print(f"- next signal: {summary['next_signal']}")
    print("- timing funnel:")
    for label in ("all", "wins", "losses"):
        row = summary["timing"][label]
        if not row["n_runs"]:
            continue
        print(
            "  - {label}: runs {runs}, offer/buy/active "
            "{offer:.1%}/{buy:.1%}/{active:.1%}, both-active {both:.1%}, "
            "avg first buy R{buy_round:.1f}, focus R{focus_round:.1f}, "
            "HP at focus {hp_focus:.1f}, post-active WR {post_wr:.1%}, "
            "dead <=1R {dead1}/{active_losses}".format(
                label=label,
                runs=row["n_runs"],
                offer=row["payoff_offer_rate"],
                buy=row["payoff_buy_rate"],
                active=row["focus_active_rate"],
                both=row["both_payoffs_active_rate"],
                buy_round=row["avg_first_buy_round"],
                focus_round=row["avg_first_focus_active_round"],
                hp_focus=row["avg_hp_at_first_focus_active"],
                post_wr=row["post_activation_battle_win_rate"],
                dead1=row["active_dead_within_1_round"],
                active_losses=row["active_loss_runs"],
            )
        )
    if summary["by_path"]:
        print("- by path:")
        for path_id, row in summary["by_path"].items():
            print(
                "  - {path}: runs {runs}, wins {wins}, buckets {buckets}, "
                "buy/active {buy:.1%}/{active:.1%}, focus R{focus_round:.1f}, "
                "HP at focus {hp_focus:.1f}".format(
                    path=path_id,
                    runs=row["n_runs"],
                    wins=row["wins"],
                    buckets=row["conversion_buckets"],
                    buy=row["payoff_buy_rate"],
                    active=row["focus_active_rate"],
                    focus_round=row["avg_first_focus_active_round"],
                    hp_focus=row["avg_hp_at_first_focus_active"],
                )
            )
    if summary["rounds"]:
        print("- round curve:")
        for round_num, row in summary["rounds"].items():
            print(
                "  - R{round}: reached {reached}, battles {battles}, "
                "WR {wr:.1%}, HP start {hp:.1f}, focus {focus:.1%}, "
                "both {both:.1%}, owned-not-active {bench:.1%}, "
                "loss A/E {ally:.1f}/{enemy:.1f}, path_lag {path_lag}".format(
                    round=round_num,
                    reached=row["runs_reached"],
                    battles=row["battles"],
                    wr=row["battle_win_rate"],
                    hp=row["avg_hp_start"],
                    focus=row["focus_active_rate"],
                    both=row["both_payoffs_active_rate"],
                    bench=row["payoff_owned_not_active_rate"],
                    ally=row["avg_loss_ally_survived"],
                    enemy=row["avg_loss_enemy_survived"],
                    path_lag=row["path_lag_holds"],
                )
            )
    if summary["false_green_examples"]:
        print("- false-green examples:")
        for row in summary["false_green_examples"]:
            print(
                "  - run {run} R{first_focus_active_round}->{death_round} "
                "{path}: HP {hp_at_activation}, focus {focus}, "
                "Druid {active_druid_cards}, trees {active_tree_counters}, "
                "post won {post_won}, post A/E "
                "{post_ally_survived}/{post_enemy_survived}, bucket {bucket}".format(
                    **row
                )
            )
    print()


def summarize_druid_run_phase_comparison(candidate_events, baseline_events):
    candidate = summarize_druid_run_phase(candidate_events)
    baseline = summarize_druid_run_phase(baseline_events)
    candidate_all = candidate["timing"]["all"]
    baseline_all = baseline["timing"]["all"]
    candidate_losses = candidate["timing"]["losses"]
    baseline_losses = baseline["timing"]["losses"]
    return {
        "baseline": _druid_phase_compare_metrics(baseline),
        "candidate": _druid_phase_compare_metrics(candidate),
        "deltas": {
            "wins": candidate["wins"] - baseline["wins"],
            "win_rate": _safe_rate(candidate["wins"], candidate["n_runs"])
            - _safe_rate(baseline["wins"], baseline["n_runs"]),
            "avg_final_hp": (
                candidate_all["avg_final_hp"] - baseline_all["avg_final_hp"]
            ),
            "loss_avg_first_focus_active_round": (
                candidate_losses["avg_first_focus_active_round"]
                - baseline_losses["avg_first_focus_active_round"]
            ),
            "loss_avg_hp_at_focus": (
                candidate_losses["avg_hp_at_first_focus_active"]
                - baseline_losses["avg_hp_at_first_focus_active"]
            ),
            "loss_post_activation_wr": (
                candidate_losses["post_activation_battle_win_rate"]
                - baseline_losses["post_activation_battle_win_rate"]
            ),
        },
        "bucket_deltas": _counter_delta(
            candidate["conversion_buckets"],
            baseline["conversion_buckets"],
        ),
        "round_deltas": _druid_phase_round_deltas(candidate, baseline),
        "candidate_false_green_examples": candidate["false_green_examples"],
        "next_signal": _druid_phase_comparison_signal(candidate, baseline),
    }


def _druid_phase_compare_metrics(summary):
    all_rows = summary["timing"]["all"]
    losses = summary["timing"]["losses"]
    return {
        "runs": summary["n_runs"],
        "wins": summary["wins"],
        "win_rate": _safe_rate(summary["wins"], summary["n_runs"]),
        "avg_final_hp": all_rows["avg_final_hp"],
        "loss_avg_first_focus_active_round": losses["avg_first_focus_active_round"],
        "loss_avg_hp_at_focus": losses["avg_hp_at_first_focus_active"],
        "loss_post_activation_wr": losses["post_activation_battle_win_rate"],
        "conversion_buckets": summary["conversion_buckets"],
    }


def _druid_phase_round_deltas(candidate, baseline):
    result = {}
    for round_num in sorted(set(candidate["rounds"]) | set(baseline["rounds"])):
        cand = candidate["rounds"].get(round_num, {})
        base = baseline["rounds"].get(round_num, {})
        result[round_num] = {
            "battle_win_rate_delta": float(cand.get("battle_win_rate", 0.0))
            - float(base.get("battle_win_rate", 0.0)),
            "focus_active_rate_delta": float(cand.get("focus_active_rate", 0.0))
            - float(base.get("focus_active_rate", 0.0)),
            "both_payoffs_active_rate_delta": float(
                cand.get("both_payoffs_active_rate", 0.0)
            ) - float(base.get("both_payoffs_active_rate", 0.0)),
            "avg_hp_start_delta": float(cand.get("avg_hp_start", 0.0))
            - float(base.get("avg_hp_start", 0.0)),
            "loss_enemy_survived_delta": float(
                cand.get("avg_loss_enemy_survived", 0.0)
            ) - float(base.get("avg_loss_enemy_survived", 0.0)),
        }
    return result


def _druid_phase_comparison_signal(candidate, baseline):
    deltas = _counter_delta(
        candidate["conversion_buckets"],
        baseline["conversion_buckets"],
    )
    if deltas.get("active_too_late", 0) > 0:
        return "Candidate increases active_too_late; next work should target timing/economy, not payoff values."
    if deltas.get("bought_not_active", 0) > 0:
        return "Candidate increases bought_not_active; next work should target board activation/promotion."
    if deltas.get("active_no_combat_swing", 0) > 0:
        return "Candidate increases active_no_combat_swing; next work should target board-state conversion or combat math."
    if deltas.get("converted", 0) > 0 and deltas.get("active_too_late", 0) <= 0:
        return "Candidate improves converted bucket without adding late activation; treat as nomination only and require the stricter probe screen plus a disjoint seed before adoption."
    return "No decisive phase improvement; keep diagnostics behavior-neutral and choose the largest remaining bucket."


def print_druid_run_phase_comparison(strat, comparison, baseline_label):
    print(f"## {strat} Druid Run-Phase Comparison")
    print(f"- baseline: {baseline_label}")
    base = comparison["baseline"]
    cand = comparison["candidate"]
    deltas = comparison["deltas"]
    print(
        "- run result: "
        f"{base['wins']}/{base['runs']} -> {cand['wins']}/{cand['runs']} clears "
        f"(Delta {deltas['wins']:+d}, WR Delta {deltas['win_rate']:+.1%}), "
        f"avg HP Delta {deltas['avg_final_hp']:+.2f}"
    )
    print(
        "- loss activation: "
        f"focus R {base['loss_avg_first_focus_active_round']:.1f} -> "
        f"{cand['loss_avg_first_focus_active_round']:.1f} "
        f"(Delta {deltas['loss_avg_first_focus_active_round']:+.1f}), "
        f"HP {base['loss_avg_hp_at_focus']:.1f} -> "
        f"{cand['loss_avg_hp_at_focus']:.1f} "
        f"(Delta {deltas['loss_avg_hp_at_focus']:+.1f}), "
        f"post-active WR {base['loss_post_activation_wr']:.1%} -> "
        f"{cand['loss_post_activation_wr']:.1%} "
        f"(Delta {deltas['loss_post_activation_wr']:+.1%})"
    )
    print(f"- conversion bucket deltas: {comparison['bucket_deltas']}")
    print(f"- next signal: {comparison['next_signal']}")
    if comparison["round_deltas"]:
        print("- R8-R12 deltas:")
        for round_num, row in comparison["round_deltas"].items():
            print(
                "  - R{round}: WR {wr:+.1%}, focus {focus:+.1%}, "
                "both {both:+.1%}, HP {hp:+.1f}, loss enemy {enemy:+.1f}".format(
                    round=round_num,
                    wr=row["battle_win_rate_delta"],
                    focus=row["focus_active_rate_delta"],
                    both=row["both_payoffs_active_rate_delta"],
                    hp=row["avg_hp_start_delta"],
                    enemy=row["loss_enemy_survived_delta"],
                )
            )
    if comparison["candidate_false_green_examples"]:
        print("- candidate false-green examples:")
        for row in comparison["candidate_false_green_examples"]:
            print(
                "  - run {run} R{first_focus_active_round}->{death_round} "
                "{path}: HP {hp_at_activation}, post A/E "
                "{post_ally_survived}/{post_enemy_survived}, bucket {bucket}".format(
                    **row
                )
            )
    print()


def summarize_druid_activation_audit(events_per_run, round_min=8, round_max=12):
    """Attribute Druid payoff bought-but-inactive gaps from existing trace facts."""
    rows = []
    payoff_rows = []
    gap_rows = []
    promotion_rows = []
    rows_by_path = defaultdict(list)

    for idx, events in enumerate(events_per_run):
        row = _druid_activation_run_row(events, idx, round_min, round_max)
        rows.append(row)
        rows_by_path[row["detected_path"]].append(row)
        payoff_rows.extend(row["payoffs"])
        gap_rows.extend(row["gap_frames"])
        promotion_rows.extend(row["promotion_decisions"])

    summary = _finalize_druid_activation_group(
        rows,
        payoff_rows,
        gap_rows,
        promotion_rows,
        round_min,
        round_max,
    )
    summary["by_path"] = {
        path_id: _finalize_druid_activation_group(
            path_rows,
            [payoff for row in path_rows for payoff in row["payoffs"]],
            [gap for row in path_rows for gap in row["gap_frames"]],
            [decision for row in path_rows for decision in row["promotion_decisions"]],
            round_min,
            round_max,
            include_examples=False,
        )
        for path_id, path_rows in sorted(rows_by_path.items())
    }
    summary["next_signal"] = _druid_activation_signal(summary)
    return summary


def _druid_activation_run_row(events, run_idx, round_min, round_max):
    phase_row = _druid_phase_run_row(events, run_idx, round_min, round_max)
    battles_by_round = {
        int(ev.get("round", 0)): ev
        for ev in events
        if ev.get("t") == "battle"
    }
    round_starts_by_round = {
        int(ev.get("round", 0)): ev
        for ev in events
        if ev.get("t") == "round_start"
    }
    round_ends_by_round = {
        int(ev.get("round", 0)): ev
        for ev in events
        if ev.get("t") == "round_end"
    }
    buy_rounds_by_card = defaultdict(list)
    for ev in events:
        if ev.get("t") == "buy" and ev.get("card_id", "") in DRUID_PAYOFF_CARDS:
            buy_rounds_by_card[str(ev.get("card_id", ""))].append(
                int(ev.get("round", 0))
            )

    promotion_decisions = []
    promotion_decisions_by_round_card = defaultdict(list)
    for ev in events:
        if ev.get("t") not in ("promote", "promote_skip"):
            continue
        round_num = int(ev.get("round", 0))
        if round_num < round_min or round_num > round_max:
            continue
        bench_card_id = str(ev.get("bench_card_id", ""))
        board_card_id = str(ev.get("board_card_id", ""))
        if bench_card_id not in DRUID_PAYOFF_CARDS and board_card_id not in DRUID_PAYOFF_CARDS:
            continue
        card_id = bench_card_id if bench_card_id in DRUID_PAYOFF_CARDS else board_card_id
        decision = _druid_activation_promotion_row(ev, card_id, phase_row)
        promotion_decisions.append(decision)
        promotion_decisions_by_round_card[(round_num, card_id)].append(decision)

    payoff_rows = []
    gap_frames = []
    for card_id in sorted(DRUID_PAYOFF_CARDS):
        payoff_row = _druid_activation_payoff_row(
            card_id,
            buy_rounds_by_card.get(card_id, []),
            phase_row,
            round_starts_by_round,
            round_ends_by_round,
            battles_by_round,
            promotion_decisions_by_round_card,
            round_min,
            round_max,
        )
        payoff_rows.append(payoff_row)
        gap_frames.extend(payoff_row["gap_frames"])

    return {
        "run": run_idx,
        "run_won": phase_row["run_won"],
        "final_hp": phase_row["final_hp"],
        "death_round": phase_row["death_round"],
        "detected_path": phase_row["detected_path"],
        "conversion_bucket": phase_row["conversion_bucket"],
        "payoffs": payoff_rows,
        "gap_frames": gap_frames,
        "promotion_decisions": promotion_decisions,
    }


def _druid_activation_promotion_row(ev, card_id, phase_row):
    bench_value = _optional_float(ev.get("bench_value"))
    board_value = _optional_float(ev.get("board_value"))
    allowed_gap = _optional_float(ev.get("allowed_gap"))
    value_delta = None
    if bench_value is not None and board_value is not None:
        value_delta = bench_value - board_value
    round_num = int(ev.get("round", 0))
    return {
        "run": phase_row["run"],
        "round": round_num,
        "path": phase_row["detected_path"],
        "run_won": phase_row["run_won"],
        "final_hp": phase_row["final_hp"],
        "death_round": phase_row["death_round"],
        "conversion_bucket": phase_row["conversion_bucket"],
        "card_id": card_id,
        "event_type": str(ev.get("t", "")),
        "reason": str(ev.get("reason", "")),
        "current_phase": str(ev.get("current_phase", "")),
        "bench_card_id": str(ev.get("bench_card_id", "")),
        "board_card_id": str(ev.get("board_card_id", "")),
        "board_idx": ev.get("board_idx"),
        "bench_value": bench_value,
        "board_value": board_value,
        "value_delta": value_delta,
        "allowed_gap": allowed_gap,
    }


def _druid_activation_payoff_row(
        card_id,
        buy_rounds,
        phase_row,
        round_starts_by_round,
        round_ends_by_round,
        battles_by_round,
        promotion_decisions_by_round_card,
        round_min,
        round_max):
    first_buy_round = min(buy_rounds) if buy_rounds else None
    first_bench_round = None
    first_board_round = None
    first_active_round = None
    gap_frames = []
    status_counts = Counter()

    for round_num in range(round_min, round_max + 1):
        round_end = round_ends_by_round.get(round_num)
        if not isinstance(round_end, dict):
            continue
        board = set(round_end.get("board") or [])
        bench = set(round_end.get("bench") or [])
        active_board = set(round_end.get("active_board") or [])
        if card_id in bench and first_bench_round is None:
            first_bench_round = round_num
        if card_id in board and first_board_round is None:
            first_board_round = round_num
        if card_id in active_board and first_active_round is None:
            first_active_round = round_num
        if first_buy_round is None or round_num < first_buy_round:
            continue
        status = _druid_activation_status(card_id, board, bench, active_board)
        status_counts[status] += 1
        if status == "active":
            continue
        battle = battles_by_round.get(round_num, {})
        round_start = round_starts_by_round.get(round_num, {})
        decisions = promotion_decisions_by_round_card.get((round_num, card_id), [])
        frame = {
            "run": phase_row["run"],
            "round": round_num,
            "path": phase_row["detected_path"],
            "run_won": phase_row["run_won"],
            "final_hp": phase_row["final_hp"],
            "death_round": phase_row["death_round"],
            "conversion_bucket": phase_row["conversion_bucket"],
            "card_id": card_id,
            "first_buy_round": first_buy_round,
            "first_active_round": first_active_round,
            "status": status,
            "hp_start": (
                int(round_start.get("hp", 0))
                if isinstance(round_start, dict) and "hp" in round_start
                else None
            ),
            "battle_seen": isinstance(battle, dict) and bool(battle),
            "battle_won": bool(battle.get("won", False)) if battle else False,
            "ally_survived": int(battle.get("ally_survived", 0)) if battle else 0,
            "enemy_survived": int(battle.get("enemy_survived", 0)) if battle else 0,
            "promotion_attempts": len([
                row for row in decisions if row["event_type"] == "promote"
            ]),
            "promotion_skips": len([
                row for row in decisions if row["event_type"] == "promote_skip"
            ]),
            "first_skip_reason": _first_decision_reason(decisions, "promote_skip"),
            "blocked_by_card": _first_blocking_card(decisions),
            "bench_value": _first_decision_value(decisions, "bench_value"),
            "board_value": _first_decision_value(decisions, "board_value"),
            "allowed_gap": _first_decision_value(decisions, "allowed_gap"),
            "trace_note": _druid_activation_trace_note(status, decisions),
        }
        gap_frames.append(frame)

    first_owned_round = _min_present([first_bench_round, first_board_round])
    buy_to_active_rounds = None
    if first_buy_round is not None and first_active_round is not None:
        buy_to_active_rounds = first_active_round - first_buy_round
    buy_to_death_rounds = None
    if first_buy_round is not None:
        buy_to_death_rounds = phase_row["death_round"] - first_buy_round
    return {
        "run": phase_row["run"],
        "path": phase_row["detected_path"],
        "run_won": phase_row["run_won"],
        "final_hp": phase_row["final_hp"],
        "death_round": phase_row["death_round"],
        "conversion_bucket": phase_row["conversion_bucket"],
        "card_id": card_id,
        "bought": first_buy_round is not None,
        "first_buy_round": first_buy_round,
        "first_owned_round": first_owned_round,
        "first_bench_round": first_bench_round,
        "first_board_round": first_board_round,
        "first_active_round": first_active_round,
        "buy_to_active_rounds": buy_to_active_rounds,
        "buy_to_death_rounds": buy_to_death_rounds,
        "status_counts": dict(status_counts),
        "gap_frames": gap_frames,
    }


def _druid_activation_status(card_id, board, bench, active_board):
    if card_id in active_board:
        return "active"
    if card_id in bench:
        return "bench_not_promoted"
    if card_id in board:
        return "board_not_active"
    return "absent_unobserved"


def _druid_activation_trace_note(status, decisions):
    if status == "absent_unobserved":
        return "aggregate_card_id_trace_no_instance_id"
    if decisions:
        return "promotion_decision_observed"
    if status == "bench_not_promoted":
        return "bench_gap_no_same_round_promotion_decision"
    if status == "board_not_active":
        return "board_gap_no_same_round_promotion_decision"
    return "observed"


def _first_decision_reason(decisions, event_type):
    for row in decisions:
        if row["event_type"] == event_type and row["reason"]:
            return row["reason"]
    return ""


def _first_blocking_card(decisions):
    for row in decisions:
        if row["board_card_id"]:
            return row["board_card_id"]
    return ""


def _first_decision_value(decisions, key):
    for row in decisions:
        if row.get(key) is not None:
            return row.get(key)
    return None


def _finalize_druid_activation_group(
        run_rows,
        payoff_rows,
        gap_rows,
        promotion_rows,
        round_min,
        round_max,
        include_examples=True):
    bought_payoff_rows = [row for row in payoff_rows if row["bought"]]
    bought_runs = {row["run"] for row in bought_payoff_rows}
    active_after_buy_rows = [
        row for row in bought_payoff_rows
        if row["first_active_round"] is not None
    ]
    never_active_after_buy_rows = [
        row for row in bought_payoff_rows
        if row["first_active_round"] is None
    ]
    bench_gap_rows = [
        row for row in gap_rows if row["status"] == "bench_not_promoted"
    ]
    board_gap_rows = [
        row for row in gap_rows if row["status"] == "board_not_active"
    ]
    result = {
        "n_runs": len(run_rows),
        "round_min": round_min,
        "round_max": round_max,
        "wins": sum(1 for row in run_rows if row["run_won"]),
        "losses": sum(1 for row in run_rows if not row["run_won"]),
        "payoff_buy_runs": len(bought_runs),
        "bought_payoff_copies": len(bought_payoff_rows),
        "active_after_buy_copies": len(active_after_buy_rows),
        "never_active_after_buy_copies": len(never_active_after_buy_rows),
        "avg_buy_to_active_rounds": _avg([
            row["buy_to_active_rounds"]
            for row in active_after_buy_rows
            if row["buy_to_active_rounds"] is not None
        ]),
        "avg_buy_to_death_rounds": _avg([
            row["buy_to_death_rounds"]
            for row in bought_payoff_rows
            if row["buy_to_death_rounds"] is not None
        ]),
        "gap_frames": len(gap_rows),
        "gap_runs": len({row["run"] for row in gap_rows}),
        "gap_status_counts": dict(Counter(row["status"] for row in gap_rows)),
        "gap_by_card": dict(Counter(row["card_id"] for row in gap_rows)),
        "gap_by_round": dict(Counter(row["round"] for row in gap_rows)),
        "gap_by_bucket": dict(Counter(row["conversion_bucket"] for row in gap_rows)),
        "bench_gap_frames": len(bench_gap_rows),
        "board_gap_frames": len(board_gap_rows),
        "no_attempt_bench_frames": len([
            row for row in bench_gap_rows
            if row["promotion_attempts"] == 0 and row["promotion_skips"] == 0
        ]),
        "promotion_attempts": len([
            row for row in promotion_rows if row["event_type"] == "promote"
        ]),
        "promotion_skips": len([
            row for row in promotion_rows if row["event_type"] == "promote_skip"
        ]),
        "promotion_skip_reasons": dict(Counter(
            row["reason"] for row in promotion_rows
            if row["event_type"] == "promote_skip"
        )),
        "promotion_skip_by_card": dict(Counter(
            row["card_id"] for row in promotion_rows
            if row["event_type"] == "promote_skip"
        )),
        "top_blocking_cards": Counter(
            row["board_card_id"] for row in promotion_rows
            if row["event_type"] == "promote_skip" and row["board_card_id"]
        ).most_common(8),
        "avg_skip_value_delta": _avg([
            row["value_delta"] for row in promotion_rows
            if row["event_type"] == "promote_skip"
            and row["value_delta"] is not None
        ]),
        "trace_limitations": [
            "card-id aggregate: duplicate payoff copies are not instance-tracked",
            "no same-round promotion decision means not observed, not impossible",
        ],
    }
    if include_examples:
        result["examples"] = _druid_activation_examples(gap_rows, promotion_rows)
    result["next_signal"] = _druid_activation_signal(result)
    return result


def _druid_activation_examples(gap_rows, promotion_rows):
    examples = []
    priority_rows = list(gap_rows)
    priority_rows.sort(
        key=lambda row: (
            row["run_won"],
            row["status"] != "bench_not_promoted",
            row["hp_start"] if row["hp_start"] is not None else 999,
            row["round"],
        )
    )
    seen = set()
    for row in priority_rows:
        key = (row["run"], row["round"], row["card_id"], row["status"])
        if key in seen:
            continue
        seen.add(key)
        examples.append({
            "run": row["run"],
            "round": row["round"],
            "path": row["path"],
            "bucket": row["conversion_bucket"],
            "card_id": row["card_id"],
            "status": row["status"],
            "first_buy_round": row["first_buy_round"],
            "first_active_round": row["first_active_round"],
            "hp_start": row["hp_start"],
            "battle_won": row["battle_won"],
            "ally_survived": row["ally_survived"],
            "enemy_survived": row["enemy_survived"],
            "first_skip_reason": row["first_skip_reason"],
            "blocked_by_card": row["blocked_by_card"],
            "bench_value": row["bench_value"],
            "board_value": row["board_value"],
            "allowed_gap": row["allowed_gap"],
            "death_round": row["death_round"],
            "final_hp": row["final_hp"],
            "trace_note": row["trace_note"],
        })
        if len(examples) >= 8:
            return examples

    for row in promotion_rows:
        if row["event_type"] != "promote_skip":
            continue
        examples.append({
            "run": row["run"],
            "round": row["round"],
            "path": row["path"],
            "bucket": row["conversion_bucket"],
            "card_id": row["card_id"],
            "status": "promotion_skip",
            "first_buy_round": None,
            "first_active_round": None,
            "hp_start": None,
            "battle_won": False,
            "ally_survived": 0,
            "enemy_survived": 0,
            "first_skip_reason": row["reason"],
            "blocked_by_card": row["board_card_id"],
            "bench_value": row["bench_value"],
            "board_value": row["board_value"],
            "allowed_gap": row["allowed_gap"],
            "death_round": row["death_round"],
            "final_hp": row["final_hp"],
            "trace_note": "promotion_skip_without_gap_frame",
        })
        if len(examples) >= 8:
            break
    return examples


def _druid_activation_signal(summary):
    if summary["bought_payoff_copies"] == 0:
        return "No Druid payoff purchases in scope; use acquisition/path-lag diagnostics first."
    gap_share = _safe_rate(
        summary["never_active_after_buy_copies"] + summary["gap_runs"],
        summary["bought_payoff_copies"] + summary["n_runs"],
    )
    if (
        summary["gap_runs"] >= 5
        and (
            summary["bench_gap_frames"] >= 8
            or summary["promotion_skips"] >= 8
        )
    ):
        return (
            "Bench/promotion gaps are common enough to justify an activation "
            "or promotion-policy probe, with fresh protected approval."
        )
    if summary["board_gap_frames"] >= 8:
        return (
            "Owned payoff cards often reach the board but are not active; inspect "
            "active-slot rules or board-state conversion before combat tuning."
        )
    if gap_share <= 0.10 and summary["gap_frames"] <= 4:
        return (
            "Activation gaps are not a dominant trace signal; pivot toward "
            "Spore pressure conversion or late activation survival."
        )
    return (
        "Activation evidence is mixed; compare against run-phase and combat "
        "ledger before requesting protected edits."
    )


def summarize_druid_activation_comparison(candidate_events, baseline_events):
    candidate = summarize_druid_activation_audit(candidate_events)
    baseline = summarize_druid_activation_audit(baseline_events)
    return {
        "baseline": _druid_activation_compare_metrics(baseline),
        "candidate": _druid_activation_compare_metrics(candidate),
        "deltas": {
            "payoff_buy_runs": (
                candidate["payoff_buy_runs"] - baseline["payoff_buy_runs"]
            ),
            "gap_frames": candidate["gap_frames"] - baseline["gap_frames"],
            "gap_runs": candidate["gap_runs"] - baseline["gap_runs"],
            "bench_gap_frames": (
                candidate["bench_gap_frames"] - baseline["bench_gap_frames"]
            ),
            "board_gap_frames": (
                candidate["board_gap_frames"] - baseline["board_gap_frames"]
            ),
            "promotion_skips": (
                candidate["promotion_skips"] - baseline["promotion_skips"]
            ),
            "no_attempt_bench_frames": (
                candidate["no_attempt_bench_frames"]
                - baseline["no_attempt_bench_frames"]
            ),
        },
        "status_deltas": _counter_delta(
            candidate["gap_status_counts"],
            baseline["gap_status_counts"],
        ),
        "skip_reason_deltas": _counter_delta(
            candidate["promotion_skip_reasons"],
            baseline["promotion_skip_reasons"],
        ),
        "next_signal": _druid_activation_comparison_signal(candidate, baseline),
    }


def _druid_activation_compare_metrics(summary):
    return {
        "runs": summary["n_runs"],
        "wins": summary["wins"],
        "payoff_buy_runs": summary["payoff_buy_runs"],
        "bought_payoff_copies": summary["bought_payoff_copies"],
        "active_after_buy_copies": summary["active_after_buy_copies"],
        "never_active_after_buy_copies": summary["never_active_after_buy_copies"],
        "avg_buy_to_active_rounds": summary["avg_buy_to_active_rounds"],
        "gap_frames": summary["gap_frames"],
        "gap_runs": summary["gap_runs"],
        "bench_gap_frames": summary["bench_gap_frames"],
        "board_gap_frames": summary["board_gap_frames"],
        "promotion_skips": summary["promotion_skips"],
        "no_attempt_bench_frames": summary["no_attempt_bench_frames"],
    }


def _druid_activation_comparison_signal(candidate, baseline):
    if candidate["gap_frames"] > baseline["gap_frames"]:
        return "Candidate increases payoff activation gaps; do not adopt as a repair."
    if candidate["gap_frames"] < baseline["gap_frames"]:
        return (
            "Candidate reduces activation gaps; treat as diagnostic movement "
            "only and require outcome gates before adoption."
        )
    if (
        candidate["gap_frames"] <= 4
        and candidate["promotion_skips"] <= 4
        and candidate["never_active_after_buy_copies"] <= 2
    ):
        return (
            "Activation gaps are low in the candidate trace; next repair should "
            "target combat conversion or late survival, not promotion policy."
        )
    return "No decisive activation delta; keep this as routing evidence only."


def print_druid_activation_audit(strat, summary):
    print(f"## {strat} Druid Activation/Promotion Audit")
    print(
        "- scope: "
        f"R{summary['round_min']}-R{summary['round_max']}, "
        f"{summary['n_runs']} runs"
    )
    print(
        "- payoff funnel: "
        f"buy runs {summary['payoff_buy_runs']}/{summary['n_runs']}, "
        f"bought copies {summary['bought_payoff_copies']}, "
        f"active after buy {summary['active_after_buy_copies']}, "
        f"never active after buy {summary['never_active_after_buy_copies']}, "
        f"avg buy->active {summary['avg_buy_to_active_rounds']:.1f}R"
    )
    print(
        "- inactive frames: "
        f"total {summary['gap_frames']} from {summary['gap_runs']} runs, "
        f"bench {summary['bench_gap_frames']}, "
        f"board {summary['board_gap_frames']}, "
        f"no-attempt bench {summary['no_attempt_bench_frames']}"
    )
    print(f"- inactive status counts: {summary['gap_status_counts']}")
    print(f"- inactive by card: {summary['gap_by_card']}")
    print(f"- inactive by round: {summary['gap_by_round']}")
    print(f"- inactive by conversion bucket: {summary['gap_by_bucket']}")
    print(
        "- promotion decisions: "
        f"promotes {summary['promotion_attempts']}, "
        f"skips {summary['promotion_skips']}, "
        f"skip reasons {summary['promotion_skip_reasons']}, "
        f"avg skip value delta {summary['avg_skip_value_delta']:.1f}"
    )
    print(f"- top blocking cards: {summary['top_blocking_cards']}")
    print(f"- trace limitations: {summary['trace_limitations']}")
    print(f"- next signal: {summary['next_signal']}")
    by_path = summary.get("by_path", {})
    if by_path:
        print("- by path:")
        for path_id, row in by_path.items():
            print(
                "  - {path}: buy runs {buy_runs}/{runs}, gaps {gaps}, "
                "bench {bench}, board {board}, skips {skips}, signal {signal}".format(
                    path=path_id,
                    buy_runs=row["payoff_buy_runs"],
                    runs=row["n_runs"],
                    gaps=row["gap_frames"],
                    bench=row["bench_gap_frames"],
                    board=row["board_gap_frames"],
                    skips=row["promotion_skips"],
                    signal=row["next_signal"],
                )
            )
    if summary.get("examples"):
        print("- inactive examples:")
        for row in summary["examples"]:
            print(
                "  - run {run} R{round} {path}: {card_id} {status}, "
                "buy R{first_buy_round}, active R{first_active_round}, "
                "skip {first_skip_reason}, blocked by {blocked_by_card}, "
                "values {bench_value}/{board_value}/gap {allowed_gap}, "
                "battle A/E {ally_survived}/{enemy_survived}, bucket {bucket}, "
                "note {trace_note}".format(**row)
            )
    print()


def print_druid_activation_comparison(strat, comparison, baseline_label):
    print(f"## {strat} Druid Activation/Promotion Comparison")
    print(f"- baseline: {baseline_label}")
    base = comparison["baseline"]
    cand = comparison["candidate"]
    deltas = comparison["deltas"]
    print(
        "- payoff buy runs: "
        f"{base['payoff_buy_runs']}/{base['runs']} -> "
        f"{cand['payoff_buy_runs']}/{cand['runs']} "
        f"(Delta {deltas['payoff_buy_runs']:+d})"
    )
    print(
        "- inactive frames: "
        f"{base['gap_frames']} -> {cand['gap_frames']} "
        f"(Delta {deltas['gap_frames']:+d}), runs "
        f"{base['gap_runs']} -> {cand['gap_runs']} "
        f"(Delta {deltas['gap_runs']:+d})"
    )
    print(
        "- gap shape: "
        f"bench {base['bench_gap_frames']} -> {cand['bench_gap_frames']} "
        f"(Delta {deltas['bench_gap_frames']:+d}), board "
        f"{base['board_gap_frames']} -> {cand['board_gap_frames']} "
        f"(Delta {deltas['board_gap_frames']:+d}), no-attempt bench "
        f"{base['no_attempt_bench_frames']} -> {cand['no_attempt_bench_frames']} "
        f"(Delta {deltas['no_attempt_bench_frames']:+d})"
    )
    print(
        "- promotion skips: "
        f"{base['promotion_skips']} -> {cand['promotion_skips']} "
        f"(Delta {deltas['promotion_skips']:+d})"
    )
    print(f"- status deltas: {comparison['status_deltas']}")
    print(f"- skip reason deltas: {comparison['skip_reason_deltas']}")
    print(f"- next signal: {comparison['next_signal']}")
    print()


def summarize_druid_path_lag_audit(events_per_run, round_min=8, round_max=12):
    """Audit Druid path_lag_hold decisions against offer visibility and outcomes."""
    hold_rows = []
    run_rows = []
    for idx, events in enumerate(events_per_run):
        row = _druid_path_lag_run_row(events, idx, round_min, round_max)
        run_rows.append(row)
        hold_rows.extend(row["holds"])

    summary = _finalize_druid_path_lag_group(
        hold_rows,
        run_rows,
        round_min,
        round_max,
    )
    summary["by_path"] = {
        path: _finalize_druid_path_lag_group(
            [row for row in hold_rows if row["path"] == path],
            [row for row in run_rows if row["path"] == path],
            round_min,
            round_max,
            include_examples=False,
        )
        for path in sorted({row["path"] for row in run_rows})
    }
    summary["next_signal"] = _druid_path_lag_signal(summary)
    return summary


def _druid_path_lag_run_row(events, run_idx, round_min, round_max):
    phase_row = _druid_phase_run_row(events, run_idx, round_min, round_max)
    phase_row["path"] = phase_row["detected_path"]
    round_start_by_round = {
        int(ev.get("round", 0)): ev
        for ev in events
        if ev.get("t") == "round_start"
    }
    battle_by_round = {
        int(ev.get("round", 0)): ev
        for ev in events
        if ev.get("t") == "battle"
    }
    rerolls_by_round = Counter(
        int(ev.get("round", 0))
        for ev in events
        if ev.get("t") == "reroll"
    )
    buys_by_round = Counter(
        int(ev.get("round", 0))
        for ev in events
        if ev.get("t") == "buy"
    )

    holds = []
    for ev in events:
        if ev.get("t") == "buy_skip" and ev.get("reason") == "path_lag_hold":
            round_num = int(ev.get("round", 0))
            if round_num < round_min or round_num > round_max:
                continue
            round_start = round_start_by_round.get(round_num, {})
            battle = battle_by_round.get(round_num, {})
            next_battle = battle_by_round.get(round_num + 1, {})
            offers = ev.get("offers") or []
            focus = set(ev.get("focus") or [])
            focus_offers = [offer for offer in offers if offer.get("id", "") in focus]
            affordable_focus = [
                offer for offer in focus_offers
                if bool(offer.get("affordable", False))
            ]
            best_card_id = str(ev.get("best_card_id", ""))
            best_score = _optional_float(ev.get("best_score"))
            category = _classify_druid_path_lag_hold(
                best_card_id,
                best_score,
                focus_offers,
                affordable_focus,
            )
            holds.append({
                "run": run_idx,
                "round": round_num,
                "path": phase_row["detected_path"],
                "run_won": phase_row["run_won"],
                "final_hp": phase_row["final_hp"],
                "death_round": phase_row["death_round"],
                "conversion_bucket": phase_row["conversion_bucket"],
                "current_phase": str(ev.get("current_phase", "")),
                "focus": sorted(focus),
                "best_card_id": best_card_id,
                "best_score": best_score,
                "category": category,
                "focus_offered": [offer.get("id", "") for offer in focus_offers],
                "affordable_focus": [
                    offer.get("id", "") for offer in affordable_focus
                ],
                "offer_count": len(offers),
                "hp_start": int(round_start.get("hp", 0)) if round_start else None,
                "gold_start": int(round_start.get("gold", 0)) if round_start else None,
                "shop_level": int(round_start.get("shop_level", 0)) if round_start else None,
                "same_round_rerolls": int(rerolls_by_round.get(round_num, 0)),
                "same_round_buys": int(buys_by_round.get(round_num, 0)),
                "battle_seen": bool(battle),
                "battle_won": bool(battle.get("won", False)) if battle else False,
                "hp_after": int(battle.get("hp_after", 0)) if battle else None,
                "ally_survived": int(battle.get("ally_survived", 0)) if battle else 0,
                "enemy_survived": int(battle.get("enemy_survived", 0)) if battle else 0,
                "next_battle_seen": bool(next_battle),
                "next_battle_won": bool(next_battle.get("won", False)) if next_battle else False,
                "next_hp_after": int(next_battle.get("hp_after", 0)) if next_battle else None,
            })

    holds_by_round = Counter(row["round"] for row in holds)
    phase_row["holds"] = holds
    phase_row["path_lag_hold_count"] = len(holds)
    phase_row["path_lag_hold_max_streak"] = max(holds_by_round.values() or [0])
    return phase_row


def _optional_float(value):
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _classify_druid_path_lag_hold(
        best_card_id, best_score, focus_offers, affordable_focus):
    if affordable_focus:
        return "affordable_focus_available"
    if focus_offers:
        return "focus_offered_unaffordable"
    if best_card_id.startswith("dr_"):
        return "no_focus_offer_druid_body_held"
    if best_card_id.startswith("ne_"):
        if best_score is not None and best_score >= 15.0:
            return "no_focus_offer_high_value_neutral_held"
        return "no_focus_offer_neutral_held"
    if best_score is not None and best_score >= 15.0:
        return "no_focus_offer_high_value_offtheme_held"
    return "no_focus_offer_low_value_held"


def _finalize_druid_path_lag_group(
        hold_rows, run_rows, round_min, round_max, include_examples=True):
    loss_runs = [row for row in run_rows if not row["run_won"]]
    hold_runs = {row["run"] for row in hold_rows}
    hold_loss_runs = {
        row["run"] for row in hold_rows
        if not row["run_won"]
    }
    no_focus_rows = [
        row for row in hold_rows
        if not row["focus_offered"]
    ]
    actionable_no_focus_rows = [
        row for row in no_focus_rows
        if row["category"] in (
            "no_focus_offer_druid_body_held",
            "no_focus_offer_high_value_neutral_held",
            "no_focus_offer_high_value_offtheme_held",
        )
    ]
    affordable_focus_rows = [
        row for row in hold_rows
        if row["affordable_focus"]
    ]
    result = {
        "n_runs": len(run_rows),
        "round_min": round_min,
        "round_max": round_max,
        "losses": len(loss_runs),
        "holds": len(hold_rows),
        "hold_runs": len(hold_runs),
        "hold_loss_runs": len(hold_loss_runs),
        "avg_holds_per_run": _safe_rate(len(hold_rows), len(run_rows)),
        "avg_holds_per_loss": _safe_rate(len([
            row for row in hold_rows
            if not row["run_won"]
        ]), len(loss_runs)),
        "max_hold_streak": max(
            [row.get("path_lag_hold_max_streak", 0) for row in run_rows] or [0]
        ),
        "category_counts": dict(Counter(row["category"] for row in hold_rows)),
        "by_round": dict(Counter(row["round"] for row in hold_rows)),
        "by_phase": dict(Counter(row["current_phase"] for row in hold_rows)),
        "top_held_cards": Counter(
            row["best_card_id"] for row in hold_rows
        ).most_common(10),
        "focus_offered_holds": len([
            row for row in hold_rows
            if row["focus_offered"]
        ]),
        "affordable_focus_holds": len(affordable_focus_rows),
        "no_focus_offer_holds": len(no_focus_rows),
        "no_focus_offer_rate": _safe_rate(len(no_focus_rows), len(hold_rows)),
        "actionable_no_focus_holds": len(actionable_no_focus_rows),
        "actionable_no_focus_loss_runs": len({
            row["run"] for row in actionable_no_focus_rows
            if not row["run_won"]
        }),
        "affordable_focus_loss_runs": len({
            row["run"] for row in affordable_focus_rows
            if not row["run_won"]
        }),
        "avg_hold_hp_start": _avg([
            row["hp_start"] for row in hold_rows
            if row["hp_start"] is not None
        ]),
        "avg_hold_hp_after": _avg([
            row["hp_after"] for row in hold_rows
            if row["hp_after"] is not None
        ]),
        "avg_hold_loss_enemy_survived": _avg([
            row["enemy_survived"] for row in hold_rows
            if row["battle_seen"] and not row["battle_won"]
        ]),
        "avg_same_round_rerolls": _avg([
            row["same_round_rerolls"] for row in hold_rows
        ]),
        "approval_gate": _druid_path_lag_approval_gate(
            hold_rows,
            actionable_no_focus_rows,
            affordable_focus_rows,
        ),
    }
    if include_examples:
        result["examples"] = _druid_path_lag_examples(
            hold_rows,
            actionable_no_focus_rows,
            affordable_focus_rows,
        )
    return result


def _druid_path_lag_approval_gate(
        hold_rows, actionable_no_focus_rows, affordable_focus_rows):
    if not hold_rows:
        return "NO_GO_NO_PATH_LAG_HOLDS"
    actionable_loss_runs = {
        row["run"] for row in actionable_no_focus_rows
        if not row["run_won"]
    }
    affordable_loss_runs = {
        row["run"] for row in affordable_focus_rows
        if not row["run_won"]
    }
    actionable_share = _safe_rate(
        len(actionable_no_focus_rows) + len(affordable_focus_rows),
        len(hold_rows),
    )
    if len(affordable_loss_runs) >= 3:
        return "GO_PROTECTED_PROBE_FOCUS_SCORE_ORDERING"
    if len(actionable_loss_runs) >= 3 and actionable_share >= 0.60:
        return "GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD"
    return "NO_GO_NEEDS_STRONGER_DECISION_ATTRIBUTION"


def _druid_path_lag_examples(
        hold_rows, actionable_no_focus_rows, affordable_focus_rows):
    priority_rows = list(affordable_focus_rows) + list(actionable_no_focus_rows)
    priority_rows.sort(
        key=lambda row: (
            row["run_won"],
            row["path"] != "druid_garden",
            row["hp_start"] if row["hp_start"] is not None else 999,
            -float(row["best_score"] or 0.0),
        )
    )
    examples = []
    seen = set()
    for row in priority_rows:
        key = (row["run"], row["round"], row["best_card_id"], row["category"])
        if key in seen:
            continue
        seen.add(key)
        examples.append({
            "run": row["run"],
            "round": row["round"],
            "path": row["path"],
            "bucket": row["conversion_bucket"],
            "category": row["category"],
            "best_card_id": row["best_card_id"],
            "best_score": row["best_score"],
            "focus": row["focus"],
            "focus_offered": row["focus_offered"],
            "affordable_focus": row["affordable_focus"],
            "hp_start": row["hp_start"],
            "hp_after": row["hp_after"],
            "battle_won": row["battle_won"],
            "enemy_survived": row["enemy_survived"],
            "same_round_rerolls": row["same_round_rerolls"],
            "death_round": row["death_round"],
            "final_hp": row["final_hp"],
        })
        if len(examples) >= 8:
            break
    return examples


def _druid_path_lag_signal(summary):
    gate = summary["approval_gate"]
    if gate == "GO_PROTECTED_PROBE_FOCUS_SCORE_ORDERING":
        return (
            "Protected AI probe recommended: path_lag_hold repeatedly skipped "
            "while affordable focus cards were visible."
        )
    if gate == "GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD":
        return (
            "Protected AI probe recommended: path_lag_hold mostly fires with no "
            "focus card offered, so test a narrow stabilizer-buy fallback before "
            "more card-value tuning."
        )
    if summary["holds"] == 0:
        return "No path_lag_hold decisions in scope."
    return (
        "Keep this diagnostic before protected edits: current evidence does not "
        "yet clear the decision-attribution gate."
    )


def print_druid_path_lag_audit(strat, summary):
    print(f"## {strat} Druid Path-Lag Decision Audit")
    print(
        "- scope: "
        f"R{summary['round_min']}-R{summary['round_max']}, "
        f"{summary['holds']} holds from {summary['hold_runs']}/"
        f"{summary['n_runs']} runs"
    )
    print(
        "- decision attribution: "
        f"focus offered {summary['focus_offered_holds']}, "
        f"affordable focus {summary['affordable_focus_holds']}, "
        f"no focus offer {summary['no_focus_offer_holds']} "
        f"({summary['no_focus_offer_rate']:.1%}), "
        f"actionable no-focus loss runs "
        f"{summary['actionable_no_focus_loss_runs']}"
    )
    print(
        "- hold pressure: "
        f"avg holds/loss {summary['avg_holds_per_loss']:.1f}, "
        f"max streak {summary['max_hold_streak']}, "
        f"HP start/after {summary['avg_hold_hp_start']:.1f}/"
        f"{summary['avg_hold_hp_after']:.1f}, "
        f"loss enemy survived {summary['avg_hold_loss_enemy_survived']:.1f}"
    )
    print(f"- categories: {summary['category_counts']}")
    print(f"- by round: {summary['by_round']}")
    print(f"- by phase: {summary['by_phase']}")
    print(f"- top held cards: {summary['top_held_cards']}")
    print(f"- approval gate: {summary['approval_gate']}")
    print(f"- next signal: {summary['next_signal']}")
    by_path = summary.get("by_path", {})
    if by_path:
        print("- by path:")
        for path_id, row in by_path.items():
            print(
                "  - {path}: holds {holds}, losses {losses}, no-focus "
                "{no_focus:.1%}, actionable no-focus loss runs {runs}, "
                "gate {gate}".format(
                    path=path_id,
                    holds=row["holds"],
                    losses=row["losses"],
                    no_focus=row["no_focus_offer_rate"],
                    runs=row["actionable_no_focus_loss_runs"],
                    gate=row["approval_gate"],
                )
            )
    if summary.get("examples"):
        print("- decision examples:")
        for row in summary["examples"]:
            print(
                "  - run {run} R{round} {path}: held {best_card_id} "
                "score {best_score}, category {category}, focus offered "
                "{focus_offered}, HP {hp_start}->{hp_after}, "
                "battle won {battle_won}, enemy {enemy_survived}, "
                "bucket {bucket}".format(**row)
            )
    print()


def summarize_druid_path_lag_comparison(candidate_events, baseline_events):
    candidate = summarize_druid_path_lag_audit(candidate_events)
    baseline = summarize_druid_path_lag_audit(baseline_events)
    return {
        "baseline": _druid_path_lag_compare_metrics(baseline),
        "candidate": _druid_path_lag_compare_metrics(candidate),
        "deltas": {
            "holds": candidate["holds"] - baseline["holds"],
            "hold_runs": candidate["hold_runs"] - baseline["hold_runs"],
            "no_focus_offer_rate": (
                candidate["no_focus_offer_rate"] - baseline["no_focus_offer_rate"]
            ),
            "affordable_focus_holds": (
                candidate["affordable_focus_holds"]
                - baseline["affordable_focus_holds"]
            ),
            "actionable_no_focus_loss_runs": (
                candidate["actionable_no_focus_loss_runs"]
                - baseline["actionable_no_focus_loss_runs"]
            ),
            "avg_holds_per_loss": (
                candidate["avg_holds_per_loss"] - baseline["avg_holds_per_loss"]
            ),
        },
        "category_deltas": _counter_delta(
            candidate["category_counts"],
            baseline["category_counts"],
        ),
        "next_signal": _druid_path_lag_comparison_signal(candidate, baseline),
    }


def _druid_path_lag_compare_metrics(summary):
    return {
        "runs": summary["n_runs"],
        "holds": summary["holds"],
        "hold_runs": summary["hold_runs"],
        "hold_loss_runs": summary["hold_loss_runs"],
        "no_focus_offer_rate": summary["no_focus_offer_rate"],
        "affordable_focus_holds": summary["affordable_focus_holds"],
        "actionable_no_focus_loss_runs": summary["actionable_no_focus_loss_runs"],
        "avg_holds_per_loss": summary["avg_holds_per_loss"],
        "approval_gate": summary["approval_gate"],
    }


def _druid_path_lag_comparison_signal(candidate, baseline):
    if candidate["approval_gate"].startswith("GO_PROTECTED_PROBE"):
        return (
            "Candidate trace confirms a protected AI policy probe is justified; "
            "do not edit godot/sim/** until the user approves that protected surface."
        )
    if candidate["holds"] > baseline["holds"]:
        return "Candidate increased path-lag hold pressure; avoid adoption."
    return "No additional path-lag decision signal beyond the baseline."


def print_druid_path_lag_comparison(strat, comparison, baseline_label):
    print(f"## {strat} Druid Path-Lag Comparison")
    print(f"- baseline: {baseline_label}")
    base = comparison["baseline"]
    cand = comparison["candidate"]
    deltas = comparison["deltas"]
    print(
        "- holds: "
        f"{base['holds']} -> {cand['holds']} "
        f"(Delta {deltas['holds']:+d}), hold runs "
        f"{base['hold_runs']} -> {cand['hold_runs']} "
        f"(Delta {deltas['hold_runs']:+d})"
    )
    print(
        "- no-focus hold rate: "
        f"{base['no_focus_offer_rate']:.1%} -> "
        f"{cand['no_focus_offer_rate']:.1%} "
        f"(Delta {deltas['no_focus_offer_rate']:+.1%})"
    )
    print(
        "- actionable loss runs: "
        f"{base['actionable_no_focus_loss_runs']} -> "
        f"{cand['actionable_no_focus_loss_runs']} "
        f"(Delta {deltas['actionable_no_focus_loss_runs']:+d}), "
        f"affordable focus holds {base['affordable_focus_holds']} -> "
        f"{cand['affordable_focus_holds']} "
        f"(Delta {deltas['affordable_focus_holds']:+d})"
    )
    print(f"- category deltas: {comparison['category_deltas']}")
    print(f"- candidate approval gate: {cand['approval_gate']}")
    print(f"- next signal: {comparison['next_signal']}")
    print()


def summarize_druid_probe_comparison(candidate_events, baseline_events):
    """Compare a Druid candidate trace against a baseline trace."""
    candidate_run = summarize_strategy(candidate_events)
    baseline_run = summarize_strategy(baseline_events)
    candidate_ledger = summarize_druid_active_ledger(candidate_events)
    baseline_ledger = summarize_druid_active_ledger(baseline_events)

    candidate_wr = _safe_rate(candidate_ledger["wins"], candidate_ledger["frames"])
    baseline_wr = _safe_rate(baseline_ledger["wins"], baseline_ledger["frames"])
    candidate_debuff_gaps = _druid_gap_count(candidate_ledger)
    baseline_debuff_gaps = _druid_gap_count(baseline_ledger)

    comparison = {
        "baseline": {
            "runs": baseline_run["n_runs"],
            "wins": baseline_run["wins"],
            "win_rate": baseline_run["win_rate"],
            "avg_final_hp": baseline_run["avg_final_hp"],
            "avg_rounds": baseline_run["avg_rounds"],
        },
        "candidate": {
            "runs": candidate_run["n_runs"],
            "wins": candidate_run["wins"],
            "win_rate": candidate_run["win_rate"],
            "avg_final_hp": candidate_run["avg_final_hp"],
            "avg_rounds": candidate_run["avg_rounds"],
        },
        "deltas": {
            "wins": candidate_run["wins"] - baseline_run["wins"],
            "win_rate": candidate_run["win_rate"] - baseline_run["win_rate"],
            "avg_final_hp": candidate_run["avg_final_hp"] - baseline_run["avg_final_hp"],
            "avg_rounds": candidate_run["avg_rounds"] - baseline_run["avg_rounds"],
        },
        "ledger": {
            "baseline_frames": baseline_ledger["frames"],
            "candidate_frames": candidate_ledger["frames"],
            "baseline_win_rate": baseline_wr,
            "candidate_win_rate": candidate_wr,
            "win_rate_delta": candidate_wr - baseline_wr,
            "baseline_avg_loss_ally_survived": _ledger_loss_avg(
                baseline_ledger, "avg_loss_ally_survived"
            ),
            "candidate_avg_loss_ally_survived": _ledger_loss_avg(
                candidate_ledger, "avg_loss_ally_survived"
            ),
            "baseline_avg_loss_enemy_survived": _ledger_loss_avg(
                baseline_ledger, "avg_loss_enemy_survived"
            ),
            "candidate_avg_loss_enemy_survived": _ledger_loss_avg(
                candidate_ledger, "avg_loss_enemy_survived"
            ),
            "bottleneck_deltas": _counter_delta(
                candidate_ledger["primary_bottlenecks"],
                baseline_ledger["primary_bottlenecks"],
            ),
            "focus_combo_deltas": _druid_focus_combo_deltas(
                candidate_ledger["by_focus_combo"],
                baseline_ledger["by_focus_combo"],
            ),
            "debuff_gap_delta": candidate_debuff_gaps - baseline_debuff_gaps,
        },
    }
    comparison["screen_verdict"] = _druid_probe_screen_verdict(comparison)
    return comparison


def _safe_rate(numer, denom):
    return numer / denom if denom else 0.0


def _ledger_loss_avg(ledger, key):
    losses = ledger["losses"]
    if not losses:
        return 0.0
    values = [
        row[key]
        for row in ledger["by_focus_combo"].values()
        if row["losses"] > 0
    ]
    weights = [
        row["losses"]
        for row in ledger["by_focus_combo"].values()
        if row["losses"] > 0
    ]
    return _weighted_avg(values, weights)


def _weighted_avg(values, weights):
    total_weight = sum(weights)
    if not values or not total_weight:
        return 0.0
    return sum(value * weight for value, weight in zip(values, weights)) / total_weight


def _druid_gap_count(ledger):
    buckets = ledger["primary_bottlenecks"]
    return int(buckets.get("debuff_too_small", 0)) + int(buckets.get("debuff_missing", 0))


def _counter_delta(candidate_counts, baseline_counts):
    keys = sorted(set(candidate_counts) | set(baseline_counts))
    return {
        key: int(candidate_counts.get(key, 0)) - int(baseline_counts.get(key, 0))
        for key in keys
    }


def _druid_focus_combo_deltas(candidate_combos, baseline_combos):
    result = {}
    for combo in sorted(set(candidate_combos) | set(baseline_combos)):
        candidate = candidate_combos.get(combo, {})
        baseline = baseline_combos.get(combo, {})
        result[combo] = {
            "frames_delta": int(candidate.get("frames", 0)) - int(baseline.get("frames", 0)),
            "wins_delta": int(candidate.get("wins", 0)) - int(baseline.get("wins", 0)),
            "losses_delta": int(candidate.get("losses", 0)) - int(baseline.get("losses", 0)),
            "win_rate_delta": float(candidate.get("win_rate", 0.0))
            - float(baseline.get("win_rate", 0.0)),
            "avg_debuff_delta": float(candidate.get("avg_debuff", 0.0))
            - float(baseline.get("avg_debuff", 0.0)),
            "avg_loss_enemy_survived_delta": float(
                candidate.get("avg_loss_enemy_survived", 0.0)
            ) - float(baseline.get("avg_loss_enemy_survived", 0.0)),
        }
    return result


def _druid_probe_screen_verdict(comparison):
    deltas = comparison["deltas"]
    ledger = comparison["ledger"]
    ally_gain = (
        ledger["candidate_avg_loss_ally_survived"]
        - ledger["baseline_avg_loss_ally_survived"]
    )
    enemy_reduction = (
        ledger["baseline_avg_loss_enemy_survived"]
        - ledger["candidate_avg_loss_enemy_survived"]
    )
    if (
        deltas["wins"] >= 3
        and deltas["avg_final_hp"] >= 1.0
        and ledger["win_rate_delta"] >= 0.08
        and (ally_gain >= 0.5 or enemy_reduction >= 2.0)
        and ledger["debuff_gap_delta"] <= 0
    ):
        return "PASS_SCREEN_CONFIRM_ON_DISJOINT_SEED"
    if (
        deltas["wins"] <= 0
        and deltas["avg_final_hp"] < 1.0
        and ledger["win_rate_delta"] < 0.05
        and ally_gain < 0.5
        and enemy_reduction < 1.0
    ):
        return "REJECT_FLAT_OR_NOISY"
    return "WEAK_LOCAL_SIGNAL_DO_NOT_ADOPT"


def print_druid_probe_comparison(strat, comparison, baseline_label):
    print(f"## {strat} Druid Probe Comparison")
    print(f"- baseline: {baseline_label}")
    base = comparison["baseline"]
    cand = comparison["candidate"]
    deltas = comparison["deltas"]
    print(
        "- run result: "
        f"{base['wins']}/{base['runs']} -> {cand['wins']}/{cand['runs']} clears "
        f"(Δ {deltas['wins']:+d}, WR {base['win_rate']:.1%} -> "
        f"{cand['win_rate']:.1%}, Δ {deltas['win_rate']:+.1%})"
    )
    print(
        "- run health: "
        f"avg HP {base['avg_final_hp']:.2f} -> {cand['avg_final_hp']:.2f} "
        f"(Δ {deltas['avg_final_hp']:+.2f}), avg rounds "
        f"{base['avg_rounds']:.2f} -> {cand['avg_rounds']:.2f} "
        f"(Δ {deltas['avg_rounds']:+.2f})"
    )
    ledger = comparison["ledger"]
    print(
        "- R9-R11 focus ledger: "
        f"frames {ledger['baseline_frames']} -> {ledger['candidate_frames']}, "
        f"WR {ledger['baseline_win_rate']:.1%} -> "
        f"{ledger['candidate_win_rate']:.1%} "
        f"(Δ {ledger['win_rate_delta']:+.1%})"
    )
    print(
        "- active-loss survivor margin: "
        f"ally {ledger['baseline_avg_loss_ally_survived']:.1f} -> "
        f"{ledger['candidate_avg_loss_ally_survived']:.1f}, "
        f"enemy {ledger['baseline_avg_loss_enemy_survived']:.1f} -> "
        f"{ledger['candidate_avg_loss_enemy_survived']:.1f}"
    )
    print(f"- bottleneck deltas: {ledger['bottleneck_deltas']}")
    print(f"- debuff gap delta: {ledger['debuff_gap_delta']:+d}")
    print(f"- screen verdict: {comparison['screen_verdict']}")
    if ledger["focus_combo_deltas"]:
        print("- focus combo deltas:")
        for combo, row in ledger["focus_combo_deltas"].items():
            print(
                "  - {combo}: frames {frames_delta:+d}, wins {wins_delta:+d}, "
                "losses {losses_delta:+d}, WR Δ {win_rate_delta:+.1%}, "
                "debuff Δ {avg_debuff_delta:+.1%}, loss enemy Δ "
                "{avg_loss_enemy_survived_delta:+.1f}".format(
                    combo=combo,
                    **row,
                )
            )
    print()


def summarize_steampunk_loss_buckets(events_per_run, include_by_path=True):
    """Classify soft_steampunk losses into trace-backed failure buckets."""
    bucket_counts = Counter()
    death_rounds = Counter()
    first_level4_rounds = Counter()
    first_level5_rounds = Counter()
    examples = []
    wins = 0
    losses = 0
    loss_payoff_bought_runs = 0
    loss_payoff_offered_runs = 0
    loss_payoff_affordable_runs = 0
    loss_affordable_payoff_skip_runs = 0
    loss_affordable_payoff_skip_events = 0
    loss_no_space_total = 0
    loss_nothing_affordable_total = 0
    loss_below_threshold_total = 0
    loss_payoff_engine_gap_runs = 0
    loss_capstone_support_gap_runs = 0
    loss_target_funnels = defaultdict(_new_target_funnel_summary)
    runs_by_path = defaultdict(list)

    for idx, events in enumerate(events_per_run):
        facts = _steampunk_run_facts(events, idx)
        path_id = facts["detected_path"] or "undetected"
        runs_by_path[path_id].append(events)
        if facts["won"]:
            wins += 1
            continue

        losses += 1
        death_rounds[facts["death_round"]] += 1
        first_level4_rounds[facts["first_level4_round"]] += 1
        first_level5_rounds[facts["first_level5_round"]] += 1
        if facts["payoff_buys"] > 0:
            loss_payoff_bought_runs += 1
        if facts["payoff_offered"]:
            loss_payoff_offered_runs += 1
        if facts["payoff_affordable"]:
            loss_payoff_affordable_runs += 1
        if facts["affordable_payoff_skip_events"] > 0:
            loss_affordable_payoff_skip_runs += 1
            loss_affordable_payoff_skip_events += facts["affordable_payoff_skip_events"]
        loss_no_space_total += facts["skip_reasons"].get("no_space", 0)
        loss_nothing_affordable_total += facts["skip_reasons"].get("nothing_affordable", 0)
        loss_below_threshold_total += facts["skip_reasons"].get("below_threshold", 0)
        if facts["payoff_engine_gaps"]:
            loss_payoff_engine_gap_runs += 1
        if facts["capstone_support_gaps"]:
            loss_capstone_support_gap_runs += 1
        _merge_target_funnels(loss_target_funnels, facts["target_funnels"])

        buckets = _steampunk_loss_buckets(facts)
        for bucket in buckets:
            bucket_counts[bucket] += 1
        if len(examples) < 8:
            examples.append({
                "run": facts["run_id"],
                "death_round": facts["death_round"],
                "final_hp": facts["final_hp"],
                "first_level4_round": facts["first_level4_round"],
                "first_level5_round": facts["first_level5_round"],
                "payoff_buys": facts["payoff_buys"],
                "payoff_active_rounds": facts["payoff_active_rounds"],
                "detected_path": facts["detected_path"],
                "active_phase": facts["active_phase"],
                "active_progress": "%d/%d" % (
                    facts["active_current_owned"],
                    facts["active_current_total"],
                ),
                "owned_progress": "%d/%d" % (
                    facts["owned_current_owned"],
                    facts["owned_current_total"],
                ),
                "engine_gaps": facts["payoff_engine_gaps"] + facts["capstone_support_gaps"],
                "target_gaps": facts["target_funnels"],
                "branch_mix": facts["branch_mix"],
                "skip_reasons": dict(facts["skip_reasons"]),
                "buckets": buckets,
            })

    summary = {
        "n_runs": len(events_per_run),
        "wins": wins,
        "losses": losses,
        "bucket_counts": dict(bucket_counts),
        "death_rounds": dict(death_rounds),
        "first_level4_rounds": dict(first_level4_rounds),
        "first_level5_rounds": dict(first_level5_rounds),
        "loss_payoff_bought_runs": loss_payoff_bought_runs,
        "loss_payoff_offered_runs": loss_payoff_offered_runs,
        "loss_payoff_affordable_runs": loss_payoff_affordable_runs,
        "loss_affordable_payoff_skip_runs": loss_affordable_payoff_skip_runs,
        "loss_affordable_payoff_skip_events": loss_affordable_payoff_skip_events,
        "avg_loss_no_space_skips": loss_no_space_total / losses if losses else 0.0,
        "avg_loss_nothing_affordable_skips": (
            loss_nothing_affordable_total / losses if losses else 0.0
        ),
        "avg_loss_below_threshold_skips": (
            loss_below_threshold_total / losses if losses else 0.0
        ),
        "loss_payoff_engine_gap_runs": loss_payoff_engine_gap_runs,
        "loss_capstone_support_gap_runs": loss_capstone_support_gap_runs,
        "loss_target_funnels": {
            category: _finalize_target_funnel_summary(funnel)
            for category, funnel in sorted(loss_target_funnels.items())
        },
        "examples": examples,
    }
    if include_by_path:
        summary["by_path"] = {
            path_id: summarize_steampunk_loss_buckets(group, include_by_path=False)
            for path_id, group in sorted(runs_by_path.items())
        }
    return summary


def _steampunk_run_facts(events, run_idx):
    run_end = next((ev for ev in reversed(events) if ev.get("t") == "run_end"), {})
    battles = [ev for ev in events if ev.get("t") == "battle"]
    round_starts = [ev for ev in events if ev.get("t") == "round_start"]
    round_ends = [ev for ev in events if ev.get("t") == "round_end"]
    buys = [ev for ev in events if ev.get("t") == "buy"]
    buy_skips = [ev for ev in events if ev.get("t") == "buy_skip"]
    sells = [ev for ev in events if ev.get("t") == "sell"]
    levelups = [ev for ev in events if ev.get("t") == "levelup"]

    won = bool(run_end.get("won", battles[-1].get("won", False) if battles else False))
    death_round = int(run_end.get(
        "rounds_played",
        battles[-1].get("round", 0) if battles else 0,
    ))
    first_level4_round = _first_shop_level_round(round_starts, levelups, 4)
    first_level5_round = _first_shop_level_round(round_starts, levelups, 5)

    payoff_buys = sum(
        1 for ev in buys if ev.get("card_id", "") in STEAMPUNK_FOCUS_CARDS
    )
    capstone_buys = sum(
        1 for ev in buys if ev.get("card_id", "") in STEAMPUNK_CAPSTONE_CARDS
    )
    payoff_active_rounds = []
    capstone_active_rounds = []
    payoff_engine_gaps = []
    capstone_support_gaps = []
    final_theme_ratio = 0.0
    detected_path = ""
    active_phase = ""
    active_current_owned = 0
    active_current_total = 0
    owned_current_owned = 0
    owned_current_total = 0
    final_owned = set()
    final_active = set()

    for ev in round_ends:
        active_board = set(ev.get("active_board", []))
        round_num = int(ev.get("round", 0))
        if active_board & STEAMPUNK_PAYOFF_CARDS:
            payoff_active_rounds.append(round_num)
        if active_board & STEAMPUNK_CAPSTONE_CARDS:
            capstone_active_rounds.append(round_num)
        for card_id in sorted(active_board & STEAMPUNK_FOCUS_CARDS):
            missing = STEAMPUNK_ENGINE_REQUIREMENTS.get(card_id, set()) - active_board
            if not missing:
                continue
            gap = {
                "round": round_num,
                "card_id": card_id,
                "missing": sorted(missing),
            }
            if card_id in STEAMPUNK_CAPSTONE_CARDS:
                capstone_support_gaps.append(gap)
            else:
                payoff_engine_gaps.append(gap)

    if round_ends:
        final_round_end = round_ends[-1]
        final_owned = set(final_round_end.get("board", []))
        final_active = set(final_round_end.get("active_board", []))
        detected_path = str(final_round_end.get("detected_path", ""))
        metrics = final_round_end.get("theme_metrics")
        if isinstance(metrics, dict):
            final_theme_ratio = float(metrics.get("board_theme_ratio", 0.0))
        for row in final_round_end.get("active_path_progress") or []:
            if row.get("id", "") == detected_path:
                active_phase = str(row.get("current_phase", ""))
                active_current_owned = int(row.get("current_owned", 0))
                active_current_total = int(row.get("current_total", 0))
        for row in final_round_end.get("path_progress") or []:
            if row.get("id", "") == detected_path:
                owned_current_owned = int(row.get("current_owned", 0))
                owned_current_total = int(row.get("current_total", 0))

    skip_reasons = Counter()
    for ev in buy_skips:
        skip_reasons[str(ev.get("reason", ""))] += 1

    payoff_offered = False
    payoff_affordable = False
    affordable_payoff_skip_events = 0
    for ev in buys + buy_skips:
        offers = ev.get("offers") or []
        affordable_payoffs = []
        for offer in offers:
            if offer.get("id", "") in STEAMPUNK_FOCUS_CARDS:
                payoff_offered = True
                if bool(offer.get("affordable", False)):
                    payoff_affordable = True
                    affordable_payoffs.append(offer)
        if affordable_payoffs:
            bought_focus = (
                ev.get("t") == "buy"
                and ev.get("card_id", "") in STEAMPUNK_FOCUS_CARDS
            )
            if not bought_focus:
                affordable_payoff_skip_events += 1

    target_funnels = _steampunk_target_funnels(
        detected_path, buys, buy_skips, sells, final_owned, final_active)

    return {
        "run_id": run_idx,
        "won": won,
        "final_hp": int(run_end.get("final_hp", 0)),
        "death_round": death_round,
        "first_level4_round": first_level4_round,
        "first_level5_round": first_level5_round,
        "payoff_buys": payoff_buys,
        "capstone_buys": capstone_buys,
        "payoff_active_rounds": payoff_active_rounds,
        "capstone_active_rounds": capstone_active_rounds,
        "payoff_engine_gaps": payoff_engine_gaps,
        "capstone_support_gaps": capstone_support_gaps,
        "payoff_offered": payoff_offered,
        "payoff_affordable": payoff_affordable,
        "affordable_payoff_skip_events": affordable_payoff_skip_events,
        "target_funnels": target_funnels,
        "skip_reasons": skip_reasons,
        "final_theme_ratio": final_theme_ratio,
        "detected_path": detected_path,
        "branch_mix": STEAMPUNK_BRANCH_CARDS.issubset(final_owned),
        "active_branch_mix": STEAMPUNK_BRANCH_CARDS.issubset(final_active),
        "active_phase": active_phase,
        "active_current_owned": active_current_owned,
        "active_current_total": active_current_total,
        "owned_current_owned": owned_current_owned,
        "owned_current_total": owned_current_total,
    }


def _steampunk_target_funnels(detected_path, buys, buy_skips, sells, final_owned, final_active):
    path_targets = STEAMPUNK_PATH_TARGETS.get(detected_path, {})
    funnels = {}
    for category, targets in path_targets.items():
        if not targets:
            continue
        offered = set()
        affordable = set()
        bought = {ev.get("card_id", "") for ev in buys} & targets
        sold = {ev.get("card_id", "") for ev in sells} & targets
        affordable_skip_reasons = Counter()
        for ev in buys + buy_skips:
            affordable_targets = set()
            for offer in ev.get("offers") or []:
                offer_id = offer.get("id", "")
                if offer_id not in targets:
                    continue
                offered.add(offer_id)
                if bool(offer.get("affordable", False)):
                    affordable.add(offer_id)
                    affordable_targets.add(offer_id)
            if affordable_targets and ev.get("card_id", "") not in affordable_targets:
                affordable_skip_reasons[str(ev.get("reason", "chosen_other"))] += 1

        missing_final = targets - final_owned
        inactive_final = targets - final_active
        funnels[category] = {
            "targets": sorted(targets),
            "offered": sorted(offered),
            "affordable": sorted(affordable),
            "bought": sorted(bought),
            "sold": sorted(sold),
            "missing_final": sorted(missing_final),
            "inactive_final": sorted(inactive_final),
            "complete_owned": not missing_final,
            "complete_active": not inactive_final,
            "affordable_skip_reasons": dict(affordable_skip_reasons),
        }
    return funnels


def _new_target_funnel_summary():
    return {
        "offered_runs": 0,
        "affordable_runs": 0,
        "bought_runs": 0,
        "sold_runs": 0,
        "complete_owned_runs": 0,
        "complete_active_runs": 0,
        "missing_final_runs": 0,
        "affordable_skip_reasons": Counter(),
        "sold_cards": Counter(),
        "missing_final_cards": Counter(),
    }


def _merge_target_funnels(summary_by_category, run_funnels):
    for category, funnel in run_funnels.items():
        summary = summary_by_category[category]
        if funnel["offered"]:
            summary["offered_runs"] += 1
        if funnel["affordable"]:
            summary["affordable_runs"] += 1
        if funnel["bought"]:
            summary["bought_runs"] += 1
        if funnel["sold"]:
            summary["sold_runs"] += 1
        if funnel["complete_owned"]:
            summary["complete_owned_runs"] += 1
        if funnel["complete_active"]:
            summary["complete_active_runs"] += 1
        if funnel["missing_final"]:
            summary["missing_final_runs"] += 1
        summary["affordable_skip_reasons"].update(funnel["affordable_skip_reasons"])
        summary["sold_cards"].update(funnel["sold"])
        summary["missing_final_cards"].update(funnel["missing_final"])


def _finalize_target_funnel_summary(summary):
    result = dict(summary)
    result["affordable_skip_reasons"] = dict(summary["affordable_skip_reasons"])
    result["sold_cards"] = dict(summary["sold_cards"])
    result["missing_final_cards"] = dict(summary["missing_final_cards"])
    return result


def _first_shop_level_round(round_starts, levelups, target_level):
    candidates = [
        int(ev.get("round", 0))
        for ev in round_starts
        if int(ev.get("shop_level", 0)) >= target_level
    ]
    candidates += [
        int(ev.get("round", 0))
        for ev in levelups
        if int(ev.get("to_level", 0)) >= target_level
    ]
    return min(candidates) if candidates else None


def _steampunk_loss_buckets(facts):
    buckets = []
    first_l4 = facts["first_level4_round"]
    first_l5 = facts["first_level5_round"]
    death_round = facts["death_round"]
    if first_l4 is None or first_l4 >= death_round or first_l4 > 9:
        buckets.append("tier_access_lag")
    if death_round >= 12 and (first_l5 is None or first_l5 > 12):
        buckets.append("capstone_access_lag")
    if facts["payoff_buys"] == 0:
        buckets.append("payoff_acquisition_lag")
    elif not facts["payoff_active_rounds"] and not facts["capstone_active_rounds"]:
        buckets.append("payoff_activation_gap")
    if facts["payoff_engine_gaps"]:
        buckets.append("payoff_engine_gap")
    if facts["capstone_support_gaps"]:
        buckets.append("capstone_support_gap")
    if facts["owned_current_total"] > 0:
        owned_ratio = facts["owned_current_owned"] / facts["owned_current_total"]
        if owned_ratio < 0.5:
            buckets.append("current_phase_lag")
    if (
        facts["owned_current_total"] > 0
        and facts["owned_current_owned"] > facts["active_current_owned"]
    ):
        buckets.append("owned_not_active_gap")
    if facts["branch_mix"]:
        buckets.append("branch_mix")
    if facts["skip_reasons"].get("no_space", 0) >= 3:
        buckets.append("no_space_pressure")
    if facts["skip_reasons"].get("nothing_affordable", 0) >= 3:
        buckets.append("affordability_pressure")
    if facts["skip_reasons"].get("below_threshold", 0) >= 3:
        buckets.append("threshold_pressure")
    if facts["final_theme_ratio"] and facts["final_theme_ratio"] < 0.75:
        buckets.append("low_steampunk_board_ratio")
    return buckets


def print_steampunk_loss_buckets(strat, summary):
    print(f"## {strat} Steampunk Loss Buckets")
    print(
        f"- losses: {summary['losses']}/{summary['n_runs']} "
        f"(wins {summary['wins']})"
    )
    print(f"- bucket counts: {summary['bucket_counts']}")
    print(f"- death rounds: {summary['death_rounds']}")
    print(f"- first shop level 4 in losses: {summary['first_level4_rounds']}")
    print(f"- first shop level 5 in losses: {summary['first_level5_rounds']}")
    print(
        "- loss payoff funnel: "
        f"offered {summary['loss_payoff_offered_runs']}, "
        f"affordable {summary['loss_payoff_affordable_runs']}, "
        f"bought {summary['loss_payoff_bought_runs']}, "
        f"skipped affordable {summary['loss_affordable_payoff_skip_runs']} runs/"
        f"{summary['loss_affordable_payoff_skip_events']} events"
    )
    print(
        "- avg loss skip pressure: "
        f"no_space {summary['avg_loss_no_space_skips']:.1f}, "
        f"nothing_affordable {summary['avg_loss_nothing_affordable_skips']:.1f}, "
        f"below_threshold {summary['avg_loss_below_threshold_skips']:.1f}"
    )
    print(
        "- active payoff support gaps: "
        f"payoff engine {summary['loss_payoff_engine_gap_runs']} loss runs, "
        f"capstone support {summary['loss_capstone_support_gap_runs']} loss runs"
    )
    target_funnels = summary.get("loss_target_funnels", {})
    if target_funnels:
        print("- loss path target funnel:")
        for category, funnel in target_funnels.items():
            print(
                "  - {category}: offered {offered}, affordable {affordable}, "
                "bought {bought}, sold {sold}, complete owned {owned}, "
                "complete active {active}, missing-final {missing}, "
                "affordable skips {skips}, sold cards {sold_cards}, "
                "missing cards {cards}".format(
                    category=category,
                    offered=funnel["offered_runs"],
                    affordable=funnel["affordable_runs"],
                    bought=funnel["bought_runs"],
                    sold=funnel["sold_runs"],
                    owned=funnel["complete_owned_runs"],
                    active=funnel["complete_active_runs"],
                    missing=funnel["missing_final_runs"],
                    skips=funnel["affordable_skip_reasons"],
                    sold_cards=funnel["sold_cards"],
                    cards=funnel["missing_final_cards"],
                )
            )
    by_path = summary.get("by_path", {})
    if by_path:
        print("- by detected path:")
        for path_id, path_summary in by_path.items():
            print(
                "  - {path}: runs {runs}, losses {losses}, wins {wins}, "
                "buckets {buckets}, payoff funnel offered/affordable/bought "
                "{offered}/{affordable}/{bought}".format(
                    path=path_id,
                    runs=path_summary["n_runs"],
                    losses=path_summary["losses"],
                    wins=path_summary["wins"],
                    buckets=path_summary["bucket_counts"],
                    offered=path_summary["loss_payoff_offered_runs"],
                    affordable=path_summary["loss_payoff_affordable_runs"],
                    bought=path_summary["loss_payoff_bought_runs"],
                )
            )
    if summary["examples"]:
        print("- examples:")
        for example in summary["examples"]:
            print(
                "  - run {run}: R{death_round} HP {final_hp}, "
                "L4 {first_level4_round}, L5 {first_level5_round}, "
                "payoff buys {payoff_buys}, active {active_phase} "
                "{active_progress}, owned {owned_progress}, "
                "engine_gaps {engine_gaps}, branch_mix {branch_mix}, "
                "buckets {buckets}".format(**example)
            )
    print()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace_dir")
    ap.add_argument("--strategy", default=None)
    ap.add_argument("--diff", default=None, help="Compare with another trace dir")
    ap.add_argument(
        "--druid-loss-buckets",
        action="store_true",
        help="Print Druid-specific loss bucket diagnostics for each strategy",
    )
    ap.add_argument(
        "--druid-battle-conversion",
        action="store_true",
        help="Print Druid focus-active battle conversion diagnostics",
    )
    ap.add_argument(
        "--druid-active-ledger",
        action="store_true",
        help="Print R9-R11 Druid focus-active combat margin ledger",
    )
    ap.add_argument(
        "--druid-offense-ledger",
        action="store_true",
        help="Print R9-R11 Druid Wrath/World offense conversion diagnostics",
    )
    ap.add_argument(
        "--druid-offense-causal-split",
        action="store_true",
        help="Print Druid late-offense acquisition/activation/conversion split",
    )
    ap.add_argument(
        "--druid-spore-tree-gap",
        action="store_true",
        help="Print Spore own-tree vs active-forest-depth diagnostics",
    )
    ap.add_argument(
        "--druid-run-phase",
        action="store_true",
        help="Print Druid payoff timing and survival/conversion diagnostics",
    )
    ap.add_argument(
        "--druid-activation-audit",
        action="store_true",
        help="Print Druid payoff activation and promotion-gap diagnostics",
    )
    ap.add_argument(
        "--druid-path-lag-audit",
        action="store_true",
        help="Print Druid path-lag hold decision attribution diagnostics",
    )
    ap.add_argument(
        "--druid-compare-baseline",
        default=None,
        help="Compare Druid probe results against a baseline trace dir",
    )
    ap.add_argument(
        "--steampunk-loss-buckets",
        action="store_true",
        help="Print Steampunk-specific loss bucket diagnostics for each strategy",
    )
    args = ap.parse_args()

    runs = load_runs(args.trace_dir, args.strategy)
    if not runs:
        print(f"No traces found in {args.trace_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"# AI Trace Summary — {args.trace_dir}\n")
    for strat in sorted(runs):
        summary = summarize_strategy(runs[strat])
        print_summary(strat, summary)
        if args.druid_loss_buckets:
            print_druid_loss_buckets(strat, summarize_druid_loss_buckets(runs[strat]))
        if args.druid_battle_conversion:
            print_druid_battle_conversion(
                strat,
                summarize_druid_battle_conversion(runs[strat]),
            )
        if args.druid_active_ledger:
            print_druid_active_ledger(
                strat,
                summarize_druid_active_ledger(runs[strat]),
            )
        if args.druid_offense_ledger:
            print_druid_offense_ledger(
                strat,
                summarize_druid_offense_ledger(runs[strat]),
            )
        if args.druid_offense_causal_split:
            print_druid_offense_causal_split(
                strat,
                summarize_druid_offense_causal_split(runs[strat]),
            )
        if args.druid_spore_tree_gap:
            print_druid_spore_tree_gap(
                strat,
                summarize_druid_spore_tree_gap(runs[strat]),
            )
        if args.druid_run_phase:
            print_druid_run_phase(
                strat,
                summarize_druid_run_phase(runs[strat]),
            )
        if args.druid_activation_audit:
            print_druid_activation_audit(
                strat,
                summarize_druid_activation_audit(runs[strat]),
            )
        if args.druid_path_lag_audit:
            print_druid_path_lag_audit(
                strat,
                summarize_druid_path_lag_audit(runs[strat]),
            )
        if args.steampunk_loss_buckets:
            print_steampunk_loss_buckets(
                strat,
                summarize_steampunk_loss_buckets(runs[strat]),
            )

    if args.druid_compare_baseline:
        print(f"\n# Druid Probe Comparison vs {args.druid_compare_baseline}\n")
        baseline_runs = load_runs(args.druid_compare_baseline, args.strategy)
        for strat in sorted(set(runs) | set(baseline_runs)):
            if not runs.get(strat):
                print(f"## {strat} Druid Probe Comparison")
                print("- skipped: candidate traces missing")
                print()
                continue
            if not baseline_runs.get(strat):
                print(f"## {strat} Druid Probe Comparison")
                print("- skipped: baseline traces missing")
                print()
                continue
            print_druid_probe_comparison(
                strat,
                summarize_druid_probe_comparison(runs[strat], baseline_runs[strat]),
                args.druid_compare_baseline,
            )
            if args.druid_run_phase:
                print_druid_run_phase_comparison(
                    strat,
                    summarize_druid_run_phase_comparison(
                        runs[strat],
                        baseline_runs[strat],
                    ),
                    args.druid_compare_baseline,
                )
            if args.druid_activation_audit:
                print_druid_activation_comparison(
                    strat,
                    summarize_druid_activation_comparison(
                        runs[strat],
                        baseline_runs[strat],
                    ),
                    args.druid_compare_baseline,
                )
            if args.druid_offense_ledger:
                print_druid_offense_comparison(
                    strat,
                    summarize_druid_offense_comparison(
                        runs[strat],
                        baseline_runs[strat],
                    ),
                    args.druid_compare_baseline,
                )
            if args.druid_offense_causal_split:
                print_druid_offense_causal_comparison(
                    strat,
                    summarize_druid_offense_causal_comparison(
                        runs[strat],
                        baseline_runs[strat],
                    ),
                    args.druid_compare_baseline,
                )
            if args.druid_path_lag_audit:
                print_druid_path_lag_comparison(
                    strat,
                    summarize_druid_path_lag_comparison(
                        runs[strat],
                        baseline_runs[strat],
                    ),
                    args.druid_compare_baseline,
                )

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
