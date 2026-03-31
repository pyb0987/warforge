"""Druid sapling system.

Processes druid card effects separately from the standard BFS chain.
Called from game.py after the standard growth chain.
"""

from __future__ import annotations

import random
from .cards import CardInstance


def _is_druid(card: CardInstance) -> bool:
    return card.template.theme == "druid"


def _card_id(card: CardInstance) -> str:
    return card.template.id


def _forest_depth(board: list[CardInstance]) -> int:
    return sum(c.saplings for c in board if _is_druid(c))


def _total_druid_units(board: list[CardInstance]) -> int:
    return sum(c.total_units for c in board if _is_druid(c))


def _druid_cards(board: list[CardInstance]) -> list[tuple[int, CardInstance]]:
    return [(i, c) for i, c in enumerate(board) if _is_druid(c)]


# ── Round processing ─────────────────────────────────────────────


def process_druid_round(board: list[CardInstance], druid_state: dict,
                        rng: random.Random,
                        verbose: bool = False) -> tuple[int, int]:
    """Process druid effects for this round.

    Returns (chain_count, gold_earned).
    Phases: generate -> distribute -> absorb -> growth/breed -> thresholds.
    """
    druid_indices = _druid_cards(board)
    if not druid_indices:
        return 0, 0

    chain_count = 0

    # Phase 1: Self-generation (left to right)
    for _i, card in druid_indices:
        cid = _card_id(card)
        if cid in ("dr_cradle", "dr_cradle_s2"):
            card.saplings += 2 if "_s2" in cid else 1
            chain_count += 1
        elif cid in ("dr_origin", "dr_origin_s2",
                      "dr_deep", "dr_deep_s2",
                      "dr_wt_root", "dr_wt_root_s2",
                      "dr_earth", "dr_earth_s2"):
            card.saplings += 1
            chain_count += 1
        elif cid in ("dr_world", "dr_world_s2"):
            card.saplings += 3 if "_s2" in cid else 2
            chain_count += 1

    # Phase 2: Distribution (left to right)
    for i, card in druid_indices:
        cid = _card_id(card)
        if cid == "dr_cradle":
            if i + 1 < len(board) and _is_druid(board[i + 1]):
                board[i + 1].saplings += 1
        elif cid == "dr_cradle_s2":
            for adj in [i - 1, i + 1]:
                if 0 <= adj < len(board) and _is_druid(board[adj]):
                    board[adj].saplings += 1
        elif cid in ("dr_wt_root", "dr_wt_root_s2"):
            t1 = 3 if "_s2" in cid else 4
            t2 = 6 if "_s2" in cid else 8
            if card.saplings >= t2:
                for _, dc in druid_indices:
                    dc.saplings += 2
            elif card.saplings >= t1:
                for _, dc in druid_indices:
                    dc.saplings += 1
        elif cid in ("dr_world", "dr_world_s2"):
            dist = 2 if "_s2" in cid else 1
            for _, dc in druid_indices:
                dc.saplings += dist

    # Phase 3: Absorption (origin absorbs from adjacent)
    for i, card in druid_indices:
        cid = _card_id(card)
        if cid in ("dr_origin", "dr_origin_s2"):
            absorb = 2 if "_s2" in cid else 1
            for adj in [i - 1, i + 1]:
                if 0 <= adj < len(board) and _is_druid(board[adj]):
                    take = min(board[adj].saplings, absorb)
                    board[adj].saplings -= take
                    card.saplings += take

    # Phase 4a: Earth blessing — unit-count-scaling growth
    for _i, card in druid_indices:
        cid = _card_id(card)
        if cid in ("dr_earth", "dr_earth_s2"):
            is_s2 = "_s2" in cid
            total_units = _total_druid_units(board)
            divisor = 4 if is_s2 else 5
            growth_pct = (total_units // divisor) / 100  # floor: 20 units // 5 = 4%
            for _, dc in druid_indices:
                dc.growth_atk_pct += growth_pct
                dc.growth_hp_pct += growth_pct
            if verbose:
                pct_display = total_units // divisor
                print(f"    🌱 대지의 축복: floor({total_units}/{divisor}) = +{pct_display}% ATK+HP")

    # Phase 4b: Growth effects (deep root)
    for _i, card in druid_indices:
        cid = _card_id(card)
        if cid in ("dr_deep", "dr_deep_s2"):
            is_s2 = "_s2" in cid
            base_pct = 0.012 if is_s2 else 0.008
            bonus_pct = 0.018 if is_s2 else 0.012
            pct = bonus_pct if card.total_units <= 3 else base_pct
            growth = card.saplings * pct
            card.growth_atk_pct += growth
            card.growth_hp_pct += growth
            mult_thresh = 8 if is_s2 else 10
            if card.saplings >= mult_thresh and not card._deep_mult_active:
                card.multiply_stats(0.50, 0.0)
                card._deep_mult_active = True
                if verbose:
                    print(f"    🌳 {card.template.name}: x1.5 ATK!")

    # Phase 5: Breeding (origin breeds adjacent)
    for i, card in druid_indices:
        cid = _card_id(card)
        if cid in ("dr_origin", "dr_origin_s2"):
            is_s2 = "_s2" in cid
            thresh = 5 if is_s2 else 6
            count = 2 if is_s2 else 1
            penalty = 0.03 if is_s2 else 0.04
            if card.saplings >= thresh:
                for adj in [i - 1, i + 1]:
                    if 0 <= adj < len(board) and _is_druid(board[adj]):
                        for _ in range(count):
                            board[adj].breed_strongest()
                        board[adj].growth_atk_pct -= penalty
                        board[adj].growth_hp_pct -= penalty

    if verbose and druid_indices:
        depth = _forest_depth(board)
        sap_str = " ".join(f"sap{c.saplings}" for _, c in druid_indices)
        print(f"    forest depth: {depth} [{sap_str}]")

    return chain_count, 0


# ── Pre-combat ───────────────────────────────────────────────────


def apply_druid_precombat(board: list[CardInstance],
                          druid_state: dict) -> float:
    """Apply druid BATTLE_START effects. Returns enemy_as_debuff."""
    druid_indices = _druid_cards(board)
    if not druid_indices:
        return 0.0

    enemy_as_debuff = 0.0

    for i, card in druid_indices:
        cid = _card_id(card)

        # lifebeat: +1 sap, shield to self + adjacent (not all)
        if cid in ("dr_lifebeat", "dr_lifebeat_s2"):
            card.saplings += 1
            is_s2 = "_s2" in cid
            base = 0.08 if is_s2 else 0.05
            per_sap = 0.04 if is_s2 else 0.03
            unit_max = 4 if is_s2 else 3
            shield_pct = base + card.saplings * per_sap
            if card.total_units <= unit_max:
                shield_pct *= 1.5
            # Apply to self + both adjacent (★1/★2 both)
            shield_targets = {i}
            if i > 0:
                shield_targets.add(i - 1)
            if i + 1 < len(board):
                shield_targets.add(i + 1)
            for ti in shield_targets:
                if _is_druid(board[ti]):
                    board[ti].shield_hp_pct += shield_pct

        # spore cloud: enemy AS debuff
        elif cid in ("dr_spore_cloud", "dr_spore_cloud_s2"):
            is_s2 = "_s2" in cid
            base = 0.20 if is_s2 else 0.15
            per_sap = 0.02 if is_s2 else 0.015
            enemy_as_debuff = min(base + card.saplings * per_sap, 0.50)

        # wrath: self ATK buff (temp)
        elif cid in ("dr_wrath", "dr_wrath_s2"):
            is_s2 = "_s2" in cid
            if card.total_units <= 5:
                atk_base = 1.20 if is_s2 else 0.80
                atk_per = 0.08 if is_s2 else 0.05
                atk_bonus = atk_base + card.saplings * atk_per
                card.temp_buff(None, atk_bonus)
                if is_s2:
                    card.shield_hp_pct += 0.60

    # world tree: ATK multiplier (temp) — no cap
    for _i, card in druid_indices:
        cid = _card_id(card)
        if cid in ("dr_world", "dr_world_s2"):
            total_units = _total_druid_units(board)
            is_s2 = "_s2" in cid
            if total_units <= 20:
                depth = _forest_depth(board)
                start = 1.15 if is_s2 else 1.1
                divisor = 20 if is_s2 else 30
                mult = start + (depth // divisor) * 0.1
                for _, dc in druid_indices:
                    dc.temp_mult_buff(mult)

    return enemy_as_debuff


# ── Post-combat ──────────────────────────────────────────────────


def apply_druid_postcombat(board: list[CardInstance],
                           combat_won: bool) -> int:
    """Apply druid post-combat effects. Returns gold earned."""
    gold = 0
    for card in board:
        if not _is_druid(card):
            continue
        cid = _card_id(card)
        if cid in ("dr_grace", "dr_grace_s2"):
            is_s2 = "_s2" in cid
            base = 2 if is_s2 else 1
            sap_gold = card.saplings // 3
            total = base + sap_gold
            terr_thresh = 8 if is_s2 else 10
            if card.saplings >= terr_thresh:
                total += 2
            if not combat_won and not is_s2:
                total = total // 2
            gold += total
    return gold
