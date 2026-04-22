#!/usr/bin/env python3
"""Autoresearch loop — mutate genome, evaluate, ADOPT/REJECT.

Usage:
    python3 godot/sim/autoresearch.py --iterations=10 --phase=1

Phases:
    1: CP curve + economy (biggest lever — fix win_rate_band first)
    2: Shop tier weights (card_coverage + diversity)
    3: Enemy composition + stats (combat dynamics)
    4: Activation caps + boss scaling (theme balance — suppress military dominance)
    5: Combined caps + boss (joint mutation)
    6: Card effects Tier A (non-military theme scaling: dr_deep, pr_swarm_sense, etc.)
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
GENOME_PATH = "godot/sim/default_genome.json"
BASELINE_PATH = "godot/sim/baseline.json"
BEST_GENOME_PATH = "godot/sim/best_genome.json"
TEMP_GENOME_PATH = "godot/sim/candidate_genome.json"

# Validation bounds — single source: genome_bounds.json.
# Do NOT hardcode here or in genome.gd. Drift caused 40min waste on 2026-04-18.
_BOUNDS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "genome_bounds.json")
with open(_BOUNDS_PATH) as _f:
    _BOUNDS = json.load(_f)
CP_RANGE = tuple(_BOUNDS["cp_range"])
TARGET_CP_RANGE = tuple(_BOUNDS.get("target_cp_range", [100.0, 100000.0]))
INCOME_RANGE = tuple(_BOUNDS["income_range"])
LEVELUP_RANGE = tuple(_BOUNDS["levelup_range"])


def load_json(path):
    with open(path) as f:
        return json.load(f)


def save_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


def validate_genome(g):
    """Validate genome constraints. Returns error string or empty string."""
    tc = g.get("target_cp_per_round", [])
    if len(tc) != 15:
        return f"target_cp_per_round must have 15 values, got {len(tc)}"
    for i, v in enumerate(tc):
        if v < TARGET_CP_RANGE[0] or v > TARGET_CP_RANGE[1]:
            return f"target_cp[{i}] = {v} out of range {TARGET_CP_RANGE}"
        if i > 0 and tc[i] < tc[i - 1]:
            return f"target_cp not monotonic at {i}"

    inc = g["economy"]["base_income"]
    for i, v in enumerate(inc):
        if v < INCOME_RANGE[0] or v > INCOME_RANGE[1]:
            return f"income[{i}] = {v} out of range"
        if i > 0 and inc[i] < inc[i - 1]:
            return f"income not monotonic at {i}"

    lc = g["economy"]["levelup_cost"]
    prev = 0
    for lv in ["2", "3", "4", "5", "6"]:
        c = lc[lv]
        if c < LEVELUP_RANGE[0] or c > LEVELUP_RANGE[1]:
            return f"levelup_cost[{lv}] = {c} out of range"
        if c <= prev:
            return f"levelup_cost not monotonic at lv{lv}"
        prev = c

    tw = g["economy"]["terazin_win"]
    tl = g["economy"]["terazin_lose"]
    if tw <= tl:
        return f"terazin_win ({tw}) must be > terazin_lose ({tl})"

    ip = g["economy"]["interest_per_5g"]
    mi = g["economy"]["max_interest"]
    if mi < ip:
        return f"max_interest ({mi}) must be >= interest_per_5g ({ip})"

    # Shop tier weights
    stw = g.get("shop_tier_weights", {})
    for lv in ["1", "2", "3", "4", "5", "6"]:
        w = stw.get(lv, [])
        if len(w) != 5:
            return f"tier_weights[{lv}] must have 5 values"
        if sum(w) != 100:
            return f"tier_weights[{lv}] sums to {sum(w)}, must be 100"
    if stw.get("1", [100])[0] != 100:
        return "Lv1 must be [100,0,0,0,0]"
    # Weighted tier monotonic
    prev_wt = 0
    for lv in [1, 2, 3, 4, 5, 6]:
        w = stw.get(str(lv), [100, 0, 0, 0, 0])
        wt = sum((ti + 1) * w[ti] / 100.0 for ti in range(5))
        if lv > 1 and wt < prev_wt:
            return f"weighted_tier not monotonic: Lv{lv}"
        prev_wt = wt

    # Heavy must have highest HP
    es = g.get("enemy_stats", {})
    if es:
        heavy_hp = es.get("heavy", {}).get("hp", 60)
        for t in ["swarm", "melee", "ranged", "sniper"]:
            hp = es.get(t, {}).get("hp", 20)
            if heavy_hp < hp:
                return f"heavy.hp ({heavy_hp}) must be >= {t}.hp ({hp})"

    # Activation caps: valid card IDs and range [1,10]
    ALL_CARDS = MILITARY_CARDS + NON_MILITARY_CARDS + [
        "ne_earth_echo", "ne_wild_pulse", "ne_ruin_resonance", "ne_wanderers",
        "ne_mutant_adapt", "ne_mana_crystal", "ne_ancient_catalyst", "ne_merchant",
        "ne_spirit_blessing", "ne_dim_merchant", "ne_wildforce", "ne_chimera_cry",
        "ne_ruins", "ne_awakening",
    ]
    caps = g.get("activation_caps", {})
    for cid, cap in caps.items():
        if cid not in ALL_CARDS:
            return f"activation_caps has unknown card_id: {cid}"
        if cap < 1 or cap > 10:
            return f"activation_caps[{cid}] = {cap} out of range [1,10]"

    # Boss scaling
    bs = g.get("boss_scaling", {})
    for key in ["atk_mult", "hp_mult"]:
        val = bs.get(key, 1.3)
        if val < 1.0 or val > 2.0:
            return f"boss_scaling.{key} = {val} out of range [1.0, 2.0]"

    # Starting resources
    sr = g.get("starting_resources", {})
    sr_gold = sr.get("gold", 10)
    if sr_gold < 5 or sr_gold > 15:
        return f"starting_resources.gold = {sr_gold} out of range [5, 15]"
    sr_tz = sr.get("terazin", 2)
    if sr_tz < 0 or sr_tz > 5:
        return f"starting_resources.terazin = {sr_tz} out of range [0, 5]"

    # Card effects (Tier A)
    CARD_EFFECTS_RANGE = {
        "dr_deep_rate": (0.004, 0.020),
        "pr_swarm_sense_buff": (0.05, 0.25),
        "sp_charger_enhance_atk": (0.02, 0.12),
        "pr_carapace_growth": (0.02, 0.15),
        "pr_transcend_death_atk": (0.01, 0.10),
    }
    ce = g.get("card_effects", {})
    for k, v in ce.items():
        if k not in CARD_EFFECTS_RANGE:
            return f"card_effects has unknown key: {k}"
        lo, hi = CARD_EFFECTS_RANGE[k]
        if v < lo or v > hi:
            return f"card_effects[{k}] = {v} out of range [{lo}, {hi}]"

    return ""


def mutate_target_cp_curve(genome, strength=0.15):
    """Mutate target_cp_per_round — 유닛 수 기반 난이도 scalar.
    
    2026-04-22 신설: enemy_cp_curve + enemy_composition 통합 대체.
    Geometric perturbation (multiplicative) — curve이 기하급수이므로 log scale 자연.
    """
    g = copy.deepcopy(genome)
    curve = list(g["target_cp_per_round"])
    for i in range(15):
        delta = curve[i] * strength * random.uniform(-1, 1)
        curve[i] = max(TARGET_CP_RANGE[0], min(TARGET_CP_RANGE[1], curve[i] + delta))
    # Monotonic
    for i in range(1, 15):
        if curve[i] < curve[i - 1]:
            curve[i] = curve[i - 1]
    g["target_cp_per_round"] = [round(v, 2) for v in curve]
    return g


def mutate_cp_curve(genome, strength=0.15):
    """Mutate enemy_cp_curve — the primary lever for win_rate_band."""
    g = copy.deepcopy(genome)
    cp = g["enemy_cp_curve"]
    for i in range(15):
        delta = cp[i] * strength * random.uniform(-1, 1)
        cp[i] = max(CP_RANGE[0], min(CP_RANGE[1], cp[i] + delta))
    # Enforce monotonic
    for i in range(1, 15):
        if cp[i] < cp[i - 1]:
            cp[i] = cp[i - 1]
    g["enemy_cp_curve"] = [round(v, 3) for v in cp]
    return g


def mutate_cp_curve_geometric(genome, strength=0.15):
    """Mutate CP curve in ratio (compound growth) space.

    매 라운드 개별 변이 + monotonic clamp 방식(mutate_cp_curve)은 인접 라운드를
    같은 값으로 끌어당기는 plateau artifact를 만듭니다. 이 geometric 변이는
    14개 성장률(cp[i]/cp[i-1])을 변수로 탐색하여 SC-style 복리 성장 구조를 보존.

    - R1은 [0.5, 2.0] 앵커로 유지 (여유 구간 정체성)
    - 각 ratio >= 1.0 (단조성 자연 보존)
    - 각 ratio <= 3.0 (라운드당 3배 이하 — SC 레퍼런스 130배/14R => 평균 ~1.4배)
    - 상한 clamp는 CP curve upper만 적용 (monotonic은 이미 보장)
    """
    g = copy.deepcopy(genome)
    cp = list(g["enemy_cp_curve"])
    # Extract 14 growth ratios
    ratios = [cp[i] / max(cp[i-1], 1e-6) for i in range(1, 15)]
    # Perturb each multiplicatively, clamp [1.1, 3.0] — floor 1.1 enforces
    # SC tavern-style 최소 10% 복리 성장 (absorbing boundary artifact 방지, 2026-04-19)
    new_ratios = []
    for r in ratios:
        new_r = r * (1.0 + strength * random.uniform(-1, 1))
        new_r = max(1.1, min(3.0, new_r))
        new_ratios.append(new_r)
    # R1 anchor — smaller strength, range [0.5, 2.0]
    new_r1 = cp[0] * (1.0 + strength * 0.5 * random.uniform(-1, 1))
    new_r1 = max(CP_RANGE[0], min(2.0, new_r1))
    # Reconstruct with upper clamp
    new_cp = [new_r1]
    for r in new_ratios:
        nxt = min(new_cp[-1] * r, CP_RANGE[1])
        new_cp.append(nxt)
    g["enemy_cp_curve"] = [round(v, 3) for v in new_cp]
    return g


def mutate_economy(genome, strength=0.15):
    """Mutate economy parameters.

    Phase 1 재탐색 (2026-04-19): 사용자가 base_income / reroll_cost / interest_per_5g /
    terazin_win / terazin_lose를 고정값으로 결정. 이 mutator는 두 축만 변이한다:
    - levelup_cost (lv2~6 각각, range [5, 13])
    - max_interest (range [1, 4], interest_per_5g 이상 유지)
    """
    g = copy.deepcopy(genome)
    econ = g["economy"]

    # levelup_cost — 각 레벨 개별 변이
    # 각 position은 monotonic headroom을 가져야 함 (2026-04-19 버그 수정):
    # Lv2: [lo, hi-4], Lv3: [lo+1, hi-3], ..., Lv6: [lo+4, hi]
    # 이 제약 안에서만 변이 → monotonic enforcement가 range를 초과 못함.
    lc = econ["levelup_cost"]
    lv_order = ["2", "3", "4", "5", "6"]
    lo = LEVELUP_RANGE[0]
    hi = LEVELUP_RANGE[1]
    for i, lv in enumerate(lv_order):
        delta = max(1, int(abs(lc[lv] * strength * random.uniform(-1, 1))))
        new_v = lc[lv] + delta * random.choice([-1, 1])
        # Position-specific clamp: leave headroom for other levels
        pos_lo = lo + i
        pos_hi = hi - (len(lv_order) - 1 - i)
        lc[lv] = max(pos_lo, min(pos_hi, new_v))
    # Enforce monotonic (now safe — position ranges guarantee feasibility)
    prev = lo - 1
    for lv in lv_order:
        if lc[lv] <= prev:
            lc[lv] = prev + 1
        prev = lc[lv]

    # max_interest — interest_per_5g는 고정, max_interest만 변이
    if random.random() < 0.4:
        econ["max_interest"] = max(econ["interest_per_5g"], random.choice([1, 2, 3, 4]))

    return g


def mutate_shop_tiers(genome, strength=0.15):
    """Mutate shop tier weights."""
    g = copy.deepcopy(genome)
    stw = g["shop_tier_weights"]
    for lv in ["2", "3", "4", "5", "6"]:  # Lv1 is fixed
        w = stw[lv]
        for i in range(5):
            delta = int(strength * 20 * random.uniform(-1, 1))
            w[i] = max(0, w[i] + delta)
        # Normalize to 100
        total = sum(w)
        if total == 0:
            w[0] = 100
        else:
            w = [int(v * 100 / total) for v in w]
            diff = 100 - sum(w)
            w[w.index(max(w))] += diff
        stw[lv] = w
    return g


def mutate_enemy_comp(genome, strength=0.15):
    """Mutate enemy unit composition (count formula) only.

    2026-04-19 pivot: 유닛 수가 autoresearch 대상, 유닛 스탯은 고정.
    사용자 설계 의도: 적은 '수가 많아도 개별은 약한' 방향. 정예화 금지.
    - base: [1, 20] (R1 기본 유닛 수 확대)
    - per_r: [0.1, 8.0] (라운드당 증가율 확대)
    """
    g = copy.deepcopy(genome)
    comp = g["enemy_composition"]
    for preset in comp:
        for key in comp[preset]:
            val = comp[preset][key]
            if key.endswith("_base"):
                delta = max(1, int(val * strength))
                comp[preset][key] = max(1, min(40, val + delta * random.choice([-1, 1])))
            elif key.endswith("_per_r"):
                delta = val * strength * random.uniform(-1, 1)
                comp[preset][key] = round(max(0.1, min(15.0, val + delta)), 1)
    return g


# All card IDs by theme (for activation_caps mutation)
MILITARY_CARDS = [
    "ml_barracks", "ml_outpost", "ml_academy", "ml_conscript", "ml_supply",
    "ml_tactical", "ml_assault", "ml_special_ops", "ml_factory", "ml_command",
]
NON_MILITARY_CARDS = [
    "sp_assembly", "sp_furnace", "sp_workshop", "sp_circulator", "sp_interest",
    "sp_line", "sp_barrier", "sp_warmachine", "sp_charger", "sp_arsenal",
    "dr_cradle", "dr_lifebeat", "dr_origin", "dr_grace", "dr_earth",
    "dr_deep", "dr_spore_cloud", "dr_wrath", "dr_wt_root", "dr_world",
    "pr_nest", "pr_farm", "pr_molt", "pr_swarm_sense", "pr_harvest",
    "pr_queen", "pr_carapace", "pr_parasite", "pr_apex_hunt", "pr_transcend",
]


def mutate_activation_caps(genome, strength=0.15):
    """Mutate activation caps — suppress military dominance, boost non-military."""
    g = copy.deepcopy(genome)
    caps = g.get("activation_caps", {})

    # Strategy: randomly cap/uncap some cards
    # Military cards: lower caps to suppress (1-5)
    # Non-military cards: raise or remove caps to boost
    num_changes = random.randint(1, 3)

    for _ in range(num_changes):
        if random.random() < 0.6:
            # Cap a military card
            card = random.choice(MILITARY_CARDS)
            current = caps.get(card, -1)
            if current == -1:
                # Set a new cap
                caps[card] = random.randint(1, 5)
            else:
                # Modify existing cap
                delta = random.choice([-1, 1])
                caps[card] = max(1, min(10, current + delta))
        else:
            # Boost a non-military card (raise cap or remove cap)
            card = random.choice(NON_MILITARY_CARDS)
            current = caps.get(card, -1)
            if current > 0:
                # Raise or remove cap
                if random.random() < 0.3:
                    del caps[card]  # Remove cap entirely
                else:
                    caps[card] = min(10, current + random.randint(1, 2))
            else:
                # Optionally set a high cap (rarely restricts)
                if random.random() < 0.2:
                    caps[card] = random.randint(4, 8)

    g["activation_caps"] = caps
    return g


def mutate_boss_scaling(genome, strength=0.15):
    """Mutate boss ATK/HP multipliers."""
    g = copy.deepcopy(genome)
    bs = g.get("boss_scaling", {"atk_mult": 1.3, "hp_mult": 1.3})

    for key in ["atk_mult", "hp_mult"]:
        val = bs[key]
        delta = val * strength * random.uniform(-1, 1)
        bs[key] = round(max(1.0, min(2.0, val + delta)), 2)

    g["boss_scaling"] = bs
    return g


def mutate_caps_and_boss(genome, strength=0.15):
    """Combined mutation: activation caps + boss scaling."""
    g = mutate_activation_caps(genome, strength)
    g = mutate_boss_scaling(g, strength)
    return g


CARD_EFFECTS_DEFAULTS = {
    "dr_deep_rate": 0.008,
    "pr_swarm_sense_buff": 0.10,
    "sp_charger_enhance_atk": 0.05,
    "pr_carapace_growth": 0.05,
    "pr_transcend_death_atk": 0.03,
}

CARD_EFFECTS_RANGES = {
    "dr_deep_rate": (0.004, 0.020),
    "pr_swarm_sense_buff": (0.05, 0.25),
    "sp_charger_enhance_atk": (0.02, 0.12),
    "pr_carapace_growth": (0.02, 0.15),
    "pr_transcend_death_atk": (0.01, 0.10),
}


def mutate_card_effects(genome, strength=0.15):
    """Mutate 1-2 random card effect parameters."""
    g = copy.deepcopy(genome)
    ce = g.get("card_effects", copy.deepcopy(CARD_EFFECTS_DEFAULTS))

    # Ensure all keys present
    for k, v in CARD_EFFECTS_DEFAULTS.items():
        if k not in ce:
            ce[k] = v

    # Pick 1-2 random params to mutate
    keys = list(CARD_EFFECTS_RANGES.keys())
    n_mutate = random.choice([1, 1, 2])  # 67% single, 33% double
    chosen = random.sample(keys, min(n_mutate, len(keys)))

    for k in chosen:
        val = ce[k]
        lo, hi = CARD_EFFECTS_RANGES[k]
        delta = val * strength * random.uniform(-1, 1)
        ce[k] = round(max(lo, min(hi, val + delta)), 4)

    g["card_effects"] = ce
    return g


PHASE_MUTATORS = {
    1: [("target_cp", mutate_target_cp_curve), ("economy", mutate_economy)],  # 2026-04-22: target_cp + economy
    2: [("shop_tiers", mutate_shop_tiers)],
    3: [("enemy_comp", mutate_enemy_comp)],
    4: [("activation_caps", mutate_activation_caps), ("boss_scaling", mutate_boss_scaling)],
    5: [("caps_and_boss", mutate_caps_and_boss)],
    6: [("card_effects", mutate_card_effects)],
}


def run_batch(genome_path, baseline_path=None, runs=20):
    """Run batch_runner and return parsed result.

    runs default 20 (was 10) per Pragmatist 2026-04-07 — n=10 had 95% CI 0-34%
    for per-strategy claims, insufficient for detecting per-strategy signals.
    """
    cmd = [
        GODOT_PATH, "--headless", "--path", PROJECT_PATH,
        "--script", "res://sim/batch_runner.gd", "--",
        f"--genome={genome_path.replace('godot/', 'res://')}", f"--runs={runs}",
    ]
    if baseline_path:
        cmd.append(f"--baseline={baseline_path.replace('godot/', 'res://')}")

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    except subprocess.TimeoutExpired:
        print(" TIMEOUT (300s)", flush=True)
        return None
    stdout = result.stdout
    stderr = result.stderr

    # Parse JSON from stdout (skip Godot banner)
    json_match = re.search(r'\{[\s\S]*\}', stdout)
    if not json_match:
        print(f"  ERROR: No JSON in output. stderr: {stderr[:200]}", file=sys.stderr)
        return None

    try:
        return json.loads(json_match.group())
    except json.JSONDecodeError as e:
        # Try to find the first complete JSON object
        text = json_match.group()
        depth = 0
        for i, c in enumerate(text):
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    return json.loads(text[:i + 1])
        print(f"  ERROR: JSON parse failed: {e}", file=sys.stderr)
        return None


def main():
    parser = argparse.ArgumentParser(description="Autoresearch genome optimizer")
    parser.add_argument("--iterations", type=int, default=10)
    parser.add_argument("--phase", type=int, default=1, choices=[1, 2, 3, 4, 5, 6])
    parser.add_argument("--strength", type=float, default=0.20)
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--runs", type=int, default=20, help="runs per strategy (default 20)")
    args = parser.parse_args()

    if args.seed is not None:
        random.seed(args.seed)

    # Load current best genome (or default)
    if os.path.exists(BEST_GENOME_PATH):
        best_genome = load_json(BEST_GENOME_PATH)
        print(f"Loaded best genome from {BEST_GENOME_PATH}")
    else:
        best_genome = load_json(GENOME_PATH)
        save_json(BEST_GENOME_PATH, best_genome)
        print(f"Initialized best genome from {GENOME_PATH}")

    # Load baseline score
    baseline = load_json(BASELINE_PATH)
    best_score = baseline["weighted_score"]
    print(f"Baseline weighted_score: {best_score:.4f}")

    mutators = PHASE_MUTATORS[args.phase]
    consecutive_rejects = 0
    total_adopts = 0
    strength = args.strength

    print(f"\n{'='*60}")
    print(f"AUTORESEARCH Phase {args.phase} — {args.iterations} iterations, strength={strength:.2f}")
    print(f"Mutators: {[m[0] for m in mutators]}")
    print(f"{'='*60}\n")

    for iteration in range(1, args.iterations + 1):
        # Pick a random mutator from this phase
        mut_name, mut_fn = random.choice(mutators)

        # Mutate
        candidate = mut_fn(best_genome, strength)

        # Validate
        err = validate_genome(candidate)
        if err:
            print(f"[{iteration:3d}] INVALID ({mut_name}): {err}")
            continue

        # Save candidate
        save_json(TEMP_GENOME_PATH, candidate)

        # Brief pause between godot invocations to prevent resource exhaustion
        time.sleep(1)

        # Evaluate
        print(f"[{iteration:3d}] Testing {mut_name} mutation (strength={strength:.2f})...", end="", flush=True)
        result = run_batch(TEMP_GENOME_PATH, BASELINE_PATH, runs=args.runs)

        if result is None:
            print(" ERROR — batch runner failed")
            continue

        new_score = result["weighted_score"]
        delta = new_score - best_score

        # Strategy summary (now includes avg_hp for per-strategy signal detection)
        stats = result.get("strategy_stats", {})
        wr_summary = " ".join(
            f"{s[:2].upper()}{int(v['win_rate']*100):d}"
            for s, v in sorted(stats.items())
        )

        # Per-strategy delta vs baseline (Pragmatist 2026-04-07)
        baseline_full = load_json(BASELINE_PATH) if os.path.exists(BASELINE_PATH) else {}
        baseline_stats = baseline_full.get("strategy_stats", {})
        hp_deltas = []
        for s, v in sorted(stats.items()):
            base_hp = baseline_stats.get(s, {}).get("avg_hp", v["avg_hp"])
            delta_hp = v["avg_hp"] - base_hp
            if abs(delta_hp) >= 1.0:  # only report meaningful changes
                hp_deltas.append(f"{s[:2].upper()}{delta_hp:+.0f}")
        hp_delta_str = (" Δhp[" + " ".join(hp_deltas) + "]") if hp_deltas else ""

        if new_score > best_score:
            # ADOPT
            best_score = new_score
            best_genome = candidate
            save_json(BEST_GENOME_PATH, best_genome)
            save_json(BASELINE_PATH, result)
            consecutive_rejects = 0
            total_adopts += 1
            print(f" ADOPT {new_score:.4f} (+{delta:.4f}) [{wr_summary}]{hp_delta_str}")

            # Show axis deltas if available
            if "axis_delta" in result:
                deltas = result["axis_delta"]
                top_changes = sorted(deltas.items(), key=lambda x: abs(x[1]), reverse=True)[:3]
                changes_str = ", ".join(f"{k}:{v:+.3f}" for k, v in top_changes if k != "weighted_score")
                print(f"       Top deltas: {changes_str}")
        else:
            # REJECT
            consecutive_rejects += 1
            print(f" REJECT {new_score:.4f} ({delta:+.4f}) [{wr_summary}]{hp_delta_str}")

        # Adaptive strength
        if consecutive_rejects >= 5:
            strength = min(strength * 1.2, 0.40)
            print(f"       [Widening search: strength → {strength:.2f}]")
        elif consecutive_rejects == 0 and strength > 0.10:
            strength = max(strength * 0.9, 0.08)

        # Escalation check
        if consecutive_rejects >= 20:
            print(f"\n{'!'*60}")
            print(f"ESCALATION: 20 consecutive REJECTs. Stopping for user review.")
            print(f"{'!'*60}")
            break

    # Summary
    print(f"\n{'='*60}")
    print(f"AUTORESEARCH COMPLETE")
    print(f"  Iterations: {iteration}")
    print(f"  ADOPTs: {total_adopts}")
    print(f"  Final score: {best_score:.4f}")
    print(f"  Best genome: {BEST_GENOME_PATH}")
    print(f"{'='*60}")

    # Cleanup temp
    if os.path.exists(TEMP_GENOME_PATH):
        os.remove(TEMP_GENOME_PATH)


if __name__ == "__main__":
    main()
