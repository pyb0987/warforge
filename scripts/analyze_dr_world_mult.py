#!/usr/bin/env python3
"""dr_world unique_atk_mult 누적 분석.

iter 21 도입 후 정책:
  - dr_world per RS: card.multiply_unique_stats(atk_mult - 1.0, hp_mult - 1.0)
  - atk_mult = atk_base + floor(forest_depth / atk_tree_step) * atk_per_tree
  - ★ 합성 시 unique_*_mult는 max 정책 (cascade 폭발 차단)

남은 우려: **단일 카드 내 multiplicative 누적**. dr_world가 N RS 트리거하면
mult = product(per_round_mult) for N rounds. forest_depth 성장 시 폭발 가능.

본 스크립트는 시나리오별 누적 mult를 계산해 (i) 매 RS 덮어쓰기 / (ii) per-source cap /
(iii) ★3 damping 옵션 검토 근거를 만든다.

YAML 정의 (data/cards/druid.yaml dr_world):
  ★1: atk_base=1.10, atk_per_tree=0.10, atk_tree_step=30
  ★2: atk_base=1.15, atk_per_tree=0.10, atk_tree_step=20
  ★3: atk_base=1.30, atk_per_tree=0.10, atk_tree_step=10

forest_depth: 보드 전체 드루이드 카드 🌳 합.
  - dr_world 자기 RS: self +2/+3 추가 + 다른 druid에 +1
  - dr_origin: self +1, adj_druids 흡수
  - dr_lifebeat (BS): self +1
  - dr_cradle: self +1, right_adj +1
  ⇒ druid 빌드에서 round당 ~4-8 trees 추가가 현실적
"""

from __future__ import annotations

import math
from typing import NamedTuple


class WorldStarConfig(NamedTuple):
    star: int
    atk_base: float
    atk_tree_step: int  # trees per +0.1 mult bonus
    atk_per_tree: float


CONFIGS = {
    1: WorldStarConfig(1, 1.10, 30, 0.10),
    2: WorldStarConfig(2, 1.15, 20, 0.10),
    3: WorldStarConfig(3, 1.30, 10, 0.10),
}


def per_round_mult(config: WorldStarConfig, trees: int) -> float:
    return config.atk_base + math.floor(trees / config.atk_tree_step) * config.atk_per_tree


def simulate_accumulation(
    star: int,
    rounds: int,
    initial_trees: int,
    trees_per_round: int,
) -> dict:
    """Multiplicative within-card accumulation (current iter 21 policy)."""
    config = CONFIGS[star]
    cumulative = 1.0
    history: list[tuple[int, int, float, float]] = []  # (round, trees, per_round, cumulative)
    trees = initial_trees
    for r in range(1, rounds + 1):
        m = per_round_mult(config, trees)
        cumulative *= m
        history.append((r, trees, m, cumulative))
        trees += trees_per_round
    return {
        "policy": "current (multiply)",
        "star": star,
        "final_mult": cumulative,
        "history": history,
    }


def simulate_overwrite(
    star: int,
    rounds: int,
    initial_trees: int,
    trees_per_round: int,
) -> dict:
    """Option (i): each RS sets unique_atk_mult to current per-round value (no accumulation)."""
    config = CONFIGS[star]
    trees = initial_trees + trees_per_round * (rounds - 1)  # final round trees
    final = per_round_mult(config, trees)
    return {
        "policy": "(i) overwrite",
        "star": star,
        "final_mult": final,
    }


def simulate_capped(
    star: int,
    rounds: int,
    initial_trees: int,
    trees_per_round: int,
    cap: float,
) -> dict:
    """Option (ii): multiplicative accumulation, but capped at `cap`."""
    config = CONFIGS[star]
    cumulative = 1.0
    trees = initial_trees
    for _ in range(rounds):
        m = per_round_mult(config, trees)
        cumulative = min(cumulative * m, cap)
        trees += trees_per_round
    return {
        "policy": f"(ii) cap@{cap}",
        "star": star,
        "final_mult": cumulative,
    }


def main() -> None:
    # 시나리오: best (early ★3, high tree growth) / median / worst (late ★3, low growth)
    scenarios = [
        ("best", {"star": 3, "rounds": 10, "initial_trees": 5, "trees_per_round": 8}),
        ("median", {"star": 3, "rounds": 8, "initial_trees": 3, "trees_per_round": 5}),
        ("worst", {"star": 3, "rounds": 5, "initial_trees": 2, "trees_per_round": 3}),
        ("★2 mid", {"star": 2, "rounds": 8, "initial_trees": 3, "trees_per_round": 5}),
        ("★1 long", {"star": 1, "rounds": 12, "initial_trees": 2, "trees_per_round": 4}),
    ]

    print("=" * 80)
    print("dr_world unique_atk_mult 누적 분석 — 4 정책 비교")
    print("=" * 80)

    for label, params in scenarios:
        print(f"\n## 시나리오: {label}")
        print(f"   ★{params['star']}, {params['rounds']}라운드, 초기 트리 {params['initial_trees']}, +{params['trees_per_round']}/round")

        cur = simulate_accumulation(**params)
        ovr = simulate_overwrite(**params)
        cap2 = simulate_capped(**params, cap=2.0)
        cap3 = simulate_capped(**params, cap=3.0)
        cap5 = simulate_capped(**params, cap=5.0)

        print(f"   현행 (multiply):       {cur['final_mult']:.2f}×")
        print(f"   (i) overwrite:         {ovr['final_mult']:.2f}×")
        print(f"   (ii) cap@2.0:          {cap2['final_mult']:.2f}×")
        print(f"   (ii) cap@3.0:          {cap3['final_mult']:.2f}×")
        print(f"   (ii) cap@5.0:          {cap5['final_mult']:.2f}×")

    print("\n" + "=" * 80)
    print("디테일: best 시나리오 round-by-round (현행 정책)")
    print("=" * 80)
    best = simulate_accumulation(star=3, rounds=10, initial_trees=5, trees_per_round=8)
    print(f"{'Round':>6} {'Trees':>6} {'per_round':>10} {'cumulative':>12}")
    for r, trees, per_round, cum in best["history"]:
        print(f"{r:>6} {trees:>6} {per_round:>10.2f} {cum:>12.2f}")


if __name__ == "__main__":
    main()
