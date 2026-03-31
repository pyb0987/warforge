"""Growth chain engine: BFS event queue with left-to-right scanning."""

from __future__ import annotations

from collections import deque
import random

from .types import (
    ChainEvent, TriggerTiming, Layer1, Layer2, EffectSpec,
)
from .cards import CardInstance


MAX_EVENTS = 100  # safety cap
MAX_RETRIGGER_DEPTH = 3  # retrigger 재귀 깊이 상한


def run_growth_chain(board: list[CardInstance], rng: random.Random,
                     verbose: bool = False) -> tuple[int, int]:
    """Execute one round's growth chain.

    Returns (chain_count, gold_earned).
    """
    # Reset activations, increment tenure
    for card in board:
        card.reset_round()

    queue: deque[ChainEvent] = deque()
    chain_count = 0
    gold_earned = 0

    # Phase 1: ROUND_START cards fire (left → right)
    for i, card in enumerate(board):
        t = card.template.trigger
        if t.timing != TriggerTiming.ROUND_START:
            continue
        if card.template.theme == "druid":
            continue
        if t.require_tenure > 0 and card.tenure < t.require_tenure:
            continue
        if t.is_threshold and card.threshold_fired:
            continue
        if t.is_threshold:
            card.threshold_fired = True

        events, gold = _execute_effects(card, i, board, rng, None, _depth=0)
        queue.extend(events)
        gold_earned += gold
        chain_count += 1

        if verbose:
            _log(f"R.START {card.template.name}[{i}] → {len(events)}evt")

    # Phase 2: BFS event cascade
    safety = MAX_EVENTS
    while queue and safety > 0:
        event = queue.popleft()
        safety -= 1

        for i, card in enumerate(board):
            t = card.template.trigger
            if t.timing != TriggerTiming.ON_EVENT:
                continue
            if not _trigger_matches(t, event, i):
                continue
            if card.template.max_activations is not None:
                if card.activations_used >= card.template.max_activations:
                    continue
                card.activations_used += 1

            events, gold = _execute_effects(card, i, board, rng,
                                            event.target_card_idx,
                                            _depth=0)
            queue.extend(events)
            gold_earned += gold
            chain_count += 1

            if verbose:
                l2 = event.layer2.name if event.layer2 else "L1"
                _log(f"CHAIN {card.template.name}[{i}] ← {l2} → {len(events)}evt")

    return chain_count, gold_earned


# ── Internal helpers ─────────────────────────────────────────────


def _trigger_matches(trigger, event: ChainEvent, card_idx: int) -> bool:
    if trigger.listen_layer1 is not None:
        if event.layer1 != trigger.listen_layer1:
            return False
    if trigger.listen_layer2 is not None:
        if event.layer2 != trigger.listen_layer2:
            return False
    if trigger.require_other_card:
        if event.source_card_idx == card_idx:
            return False
    return True


def _resolve_targets(target: str, card_idx: int,
                     event_target_idx: int | None,
                     board_len: int) -> list[int]:
    if target == "self":
        return [card_idx]
    if target == "right_adj":
        r = card_idx + 1
        return [r] if r < board_len else []
    if target == "both_adj":
        out = []
        if card_idx > 0:
            out.append(card_idx - 1)
        if card_idx + 1 < board_len:
            out.append(card_idx + 1)
        return out
    if target == "all_allies":
        return list(range(board_len))
    if target == "event_target":
        return [event_target_idx] if event_target_idx is not None else []
    return []


def _execute_effects(card: CardInstance, card_idx: int,
                     board: list[CardInstance], rng: random.Random,
                     event_target_idx: int | None,
                     _depth: int = 0,
                     ) -> tuple[list[ChainEvent], int]:
    """Run card's effects. Returns (new_events, gold_earned)."""
    events: list[ChainEvent] = []
    gold = 0

    for eff in card.template.effects:
        targets = _resolve_targets(
            eff.target, card_idx, event_target_idx, len(board))

        for ti in targets:
            if eff.action == "spawn":
                for _ in range(eff.spawn_count):
                    board[ti].spawn_random(rng)
                if eff.output_layer1:
                    events.append(ChainEvent(
                        eff.output_layer1, eff.output_layer2,
                        card_idx, ti))

            elif eff.action == "enhance_pct":
                n = board[ti].enhance(
                    eff.unit_tag_filter,
                    eff.enhance_atk_pct, eff.enhance_hp_pct)
                if n > 0 and eff.output_layer1:
                    events.append(ChainEvent(
                        eff.output_layer1, eff.output_layer2,
                        card_idx, ti))

            elif eff.action == "retrigger":
                if _depth < MAX_RETRIGGER_DEPTH:
                    sub_events, sub_gold = _execute_effects(
                        board[ti], ti, board, rng,
                        event_target_idx=None, _depth=_depth + 1)
                    events.extend(sub_events)
                    gold += sub_gold

            elif eff.action == "grant_gold":
                gold += eff.gold_amount

            elif eff.action == "shield_pct":
                _apply_shield(board[ti], eff.shield_hp_pct)

    return events, gold


def _apply_shield(card: CardInstance, hp_pct: float) -> None:
    """Add shield as bonus HP (% of base HP). Card-level accumulation."""
    card.shield_hp_pct += hp_pct


def _log(msg: str) -> None:
    print(f"    {msg}")
