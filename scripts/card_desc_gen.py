#!/usr/bin/env python3
"""
card_desc_gen.py — Generate card effect description texts from YAML DSL.

Separate module (800-line limit). Called by codegen_card_db.py.
API: generate_all_descs(all_cards) → dict[card_id → {1: str, 2: str, 3: str}]
"""

from __future__ import annotations
from typing import Any
import re
import sys
from pathlib import Path

# ═══════════════════════════════════════════════════════════════════
# Unit id → Korean name (parsed lazily from godot/core/data/unit_db.gd)
# ═══════════════════════════════════════════════════════════════════

_UNIT_NAME_CACHE: dict[str, str] | None = None

def _unit_name(unit_id: str) -> str:
    """Resolve unit id (e.g. 'ml_biker') to Korean name ('강습 바이커').

    Parses ``_reg("id", "name", ...)`` lines in unit_db.gd on first call.
    Falls back to the raw id if not found.
    """
    global _UNIT_NAME_CACHE
    if _UNIT_NAME_CACHE is None:
        _UNIT_NAME_CACHE = {}
        db_path = Path(__file__).resolve().parent.parent / "godot/core/data/unit_db.gd"
        try:
            content = db_path.read_text()
            for match in re.finditer(r'_reg\(\s*"([^"]+)"\s*,\s*"([^"]+)"', content):
                _UNIT_NAME_CACHE[match.group(1)] = match.group(2)
        except OSError:
            pass
    return _UNIT_NAME_CACHE.get(unit_id, unit_id)

# ═══════════════════════════════════════════════════════════════════
# Timing → prefix mappings
# ═══════════════════════════════════════════════════════════════════

TIMING_PREFIX = {
    "RS":         "라운드 시작:",
    "BS":         "전투 시작:",
    "PC":         "전투 종료:",
    "PCD":        "전투 패배 시:",
    "PCV":        "전투 승리 시:",
    "REROLL":     "리롤 시:",
    "MERGE":      "★합성 시:",
    "SELL":       "[반응] 판매 시:",
    "PERSISTENT": "[지속]",
    "DEATH":      "[지속] 사망 시:",
}

OE_PREFIX = {
    # (l1, l2) → prefix
    ("UA", None):  "[반응] 유닛 추가 시:",
    ("EN", None):  "[반응] 강화 발동 시:",
    ("UA", "MF"):  "[반응] 제조 발동 시:",
    ("EN", "UP"):  "[반응] 개량 발동 시:",
    ("UA", "HA"):  "[반응] 부화 시:",
    ("EN", "MT"):  "[반응] 변태 시:",
    (None, "TR"):  "[반응] 훈련 시:",
    (None, "CO"):  "[반응] 징집 시:",
    (None, "HA"):  "[반응] 부화 시:",
    (None, "MT"):  "[반응] 변태 시:",
    (None, "UP"):  "[반응] 개량 발동 시:",
    ("UA", "MERGE"): "★합성 시:",
    ("UA", "REROLL"): "리롤 시:",
    ("UA", "SELL"):   "[반응] 판매 시:",
}

# Action types whose intrinsic timing differs from the card's base timing
ACTION_TIMING_OVERRIDE = {
    "economy":          "PC",
    "battle_buff":      "BS",
    "tree_temp_buff":   "BS",
    "on_combat_result": "PC",
}

# ═══════════════════════════════════════════════════════════════════
# Target resolution
# ═══════════════════════════════════════════════════════════════════

TARGET = {
    "self":              "이 카드",
    "right_adj":         "오른쪽 인접 카드",
    "left_adj":          "왼쪽 인접 카드",
    "both_adj":          "양쪽 인접 카드",
    "all_allies":        "필드 위 모든 카드",
    "all_druid":         "모든 드루이드 카드",
    "all_predator":      "모든 포식종 카드",
    "all_military":      "모든 군대 카드",
    "all_steampunk":     "모든 스팀펑크 카드",
    "all_enemy":         "적 전체",
    "event_target":      "해당 카드",
    "event_source":      "발동 카드",
    "self_and_both_adj": "이 카드 + 양쪽 인접",
    "adj_druids":        "인접 드루이드 카드",
    "adj_or_self":       "인접 카드",
    "both_adj_or_self":  "양쪽 인접 카드",
    "all_other_druid":   "필드 위 모든 드루이드 카드",
    "enhanced_units":    "(강화) 유닛",
    # Military R4/R10 재설계 target (trace 012)
    "far_military":      "인접하지 않은 다른 군대 카드",
    "event_target_adj":  "해당 카드 양쪽 인접",
    "far_event_military": "해당 카드·인접 제외 다른 군대 카드",
    # Military command revive scope (trace 014)
    "self_enhanced":     "이 카드 (강화) 유닛",
    "self_all":          "이 카드 모든 유닛",
    "self_and_adj_all":  "이 카드 + 양쪽 인접 카드 모든 유닛",
}

TAG_KR = {
    "gear": "기어",
    "electric": "전기",
    "firearm": "화기",
    "queen": "여왕",
    "carapace": "갑각",
}

RARITY_KR = {
    "rare": "레어",
    "epic": "에픽",
    "legendary": "전설",
}

def tag_kr(tag_str: str) -> str:
    """Tag name(s) → Korean. 'gear,electric' → '기어·전기'."""
    parts = [TAG_KR.get(t.strip(), t.strip()) for t in tag_str.split(",")]
    return "·".join(parts)

def resolve_target(target_str: str) -> str:
    """target string → Korean. Supports tag:* dynamic patterns."""
    if target_str in TARGET:
        return TARGET[target_str]
    if target_str.startswith("tag:"):
        tag = target_str[4:]
        return f"#{tag_kr(tag)} 유닛"
    return target_str  # fallback

# ═══════════════════════════════════════════════════════════════════
# Utility
# ═══════════════════════════════════════════════════════════════════

def fmt_pct(f: float) -> str:
    """0.05 → '5', 0.075 → '7.5'"""
    val = f * 100
    if val == int(val):
        return str(int(val))
    return f"{val:.1f}".rstrip("0").rstrip(".")

# ═══════════════════════════════════════════════════════════════════
# Common effect descriptors
# ═══════════════════════════════════════════════════════════════════

def desc_spawn(p: dict) -> str:
    t = resolve_target(p["target"])
    n = p.get("count", 1)
    ol2 = p.get("ol2")
    verb = {None: "유닛", "MF": "제조"}.get(ol2, "유닛")
    strongest = " 가장 강한 유닛(CP)" if p.get("strongest") else ""
    return f"{t}에{strongest} {n}기 {verb}"

def desc_enhance(p: dict) -> str:
    t = resolve_target(p["target"])
    atk_val = p.get("atk_pct", 0)
    hp_val = p.get("hp_pct", 0)
    tag = p.get("tag", "")
    # ol1=null → event suppressed → "성장"
    ol1_null = p.get("ol1") is None and "ol1" in p
    ol2 = p.get("ol2")
    if ol1_null:
        verb = "성장"
    else:
        verb = {None: "영구 강화", "UP": "개량"}.get(ol2, "영구 강화")
    tag_text = f" #{tag_kr(tag)} 유닛" if tag else ""
    if hp_val and not atk_val:
        return f"{t}{tag_text} HP +{fmt_pct(hp_val)}% {verb}"
    if hp_val:
        return f"{t}{tag_text} ATK+HP +{fmt_pct(atk_val)}% {verb}"
    return f"{t}{tag_text} ATK +{fmt_pct(atk_val)}% {verb}"

def desc_buff(p: dict) -> str:
    t = resolve_target(p["target"])
    tag = f" #{tag_kr(p['tag'])}" if p.get("tag") else ""
    if p.get("atk_mult"):
        text = f"{t}{tag} 유닛 ATK ×{p['atk_mult']}(이번 전투)"
    elif p.get("as_bonus"):
        # military ml_tactical R10: 모든 군대 카드 AS +15%
        text = f"{t}{tag} 유닛 AS +{fmt_pct(p['as_bonus'])}%(이번 전투)"
    else:
        atk = fmt_pct(p["atk_pct"])
        text = f"{t}{tag} 유닛 ATK +{atk}%(이번 전투)"
    if p.get("kill_hp_recover"):
        text += ". 적 처치 HP 회복"
    return text

def desc_gold(amount) -> str:
    return f"{amount}골드 획득"

def desc_terazin(amount) -> str:
    return f"{amount} 테라진 획득"

def desc_shield(p: dict) -> str:
    t = resolve_target(p["target"])
    pct = fmt_pct(p["hp_pct"])
    return f"{t} 유닛에 방어막(HP {pct}%)"

def desc_scrap(p: dict) -> str:
    n = p["count"]
    reroll = p["reroll_gain"]
    gold = p.get("gold_per_unit", 0)
    text = f"양쪽 인접 카드에서 최약 유닛 {n}기씩 제거. 무료 리롤 +{reroll}"
    if gold:
        text += f" + 제거 유닛당 {gold}골드"
    return text

def desc_diversity_gold(p: dict) -> str:
    gpt = p.get("gold_per_theme", 1)
    text = f"필드 위 테마 수 × {gpt}골드 획득"
    if p.get("terazin_threshold"):
        text += (f". {p['terazin_threshold']}종 이상이면 "
                 f"테마당 {p.get('terazin_per_theme', 1)} 테라진")
    if p.get("mercenary_spawn"):
        text += ". 용병 카드마다 유닛 +1"
    return text

def desc_absorb(p: dict) -> str:
    n = p["count"]
    text = f"판매된 카드의 가장 강한 유닛 {n}기 흡수"
    if p.get("transfer_upgrades"):
        text += " + 업그레이드 이전"
    if p.get("majority_atk_bonus"):
        pct = fmt_pct(p["majority_atk_bonus"])
        text += f" + 최다 유닛 ATK +{pct}%"
    return text

# ═══════════════════════════════════════════════════════════════════
# Druid effect descriptors
# ═══════════════════════════════════════════════════════════════════

def desc_tree_add(p: dict) -> str:
    t = resolve_target(p["target"])
    return f"{t}에 🌳+{p['count']}"

def desc_tree_absorb(p: dict) -> str:
    return f"인접에서 🌳{p['count']} 흡수"

def desc_tree_breed(p: dict) -> str:
    t = resolve_target(p["target"])
    n = p["count"]
    thresh = p["tree_thresh"]
    penalty = p.get("penalty_pct", 0)
    text = f"🌳{thresh} 이상 → {t}에 번식 {n}기"
    if penalty:
        text += f"(-{fmt_pct(penalty)}%p 성장)"
    else:
        text += "(페널티 없음)"
    return text

def desc_tree_shield(p: dict) -> str:
    t = resolve_target(p["target"])
    base = fmt_pct(p["base_pct"])
    scale = fmt_pct(p["tree_scale_pct"])
    # timing_override is handled by generate_star_desc timing groups
    text = f"{t}에 방어막(HP {base}%+🌳×{scale}%)"
    low = p.get("low_unit")
    if low:
        text += f". ≤{low['thresh']}기 ×{low['mult']}"
    return text

def desc_tree_enhance(p: dict) -> str:
    base = fmt_pct(p["base_pct"])
    text = f"이 카드 ATK+HP +(🌳×{base}%) 성장"
    low = p.get("low_unit")
    if low:
        low_pct = fmt_pct(low["pct"])
        text += f". ≤{low['thresh']}기 → 🌳×{low_pct}%"
    bonus = p.get("tree_bonus")
    if bonus:
        pct = fmt_pct(bonus["bonus_growth_pct"])
        text += f". 🌳{bonus['thresh']}+ → 성장 +{pct}%"
    return text

def desc_tree_gold(p: dict) -> str:
    base = p["base_gold"]
    div = p["tree_divisor"]
    text = f"{base}골드 + 🌳÷{div} 골드"
    if p.get("win_half"):
        text += ". 패배 시 절반"
    else:
        text += ". 패배 전액"
    if p.get("terazin_thresh"):
        text += f". 🌳{p['terazin_thresh']}+ → +{p.get('terazin', 1)} 테라진"
    return text

def desc_tree_distribute(p: dict) -> str:
    tiers = p["tiers"]
    parts = []
    for tier in tiers:
        parts.append(
            f"🌳{tier['tree_gte']}+ → 전체 드루이드 +{tier['amount']}")
    return ". ".join(parts)

def desc_druid_unit_enhance(p: dict) -> str:
    div = p["divisor"]
    text = f"모든 드루이드 ATK+HP +(전체 유닛÷{div})% 성장"
    if p.get("bonus_tiers"):
        for bt in p["bonus_tiers"]:
            pct = fmt_pct(bt["bonus_pct"])
            text += f". {bt['unit_gte']}기+ → 추가 +{pct}%"
    return text

def desc_multiply_stats(p: dict) -> str:
    cap = p["unit_cap"]
    atk_base = p["atk_base"]
    atk_step = p["atk_tree_step"]
    atk_per = p["atk_per_tree"]
    text = (f"[지속] ≤{cap}기 → 전체 드루이드 ATK×{atk_base}. "
            f"숲의 깊이 {atk_step}당 +{atk_per}×")
    if p.get("hp_base"):
        hp_step = p.get("hp_tree_step", atk_step)
        hp_per = p.get("hp_per_tree", 0)
        text += f", HP×{p['hp_base']}"
        if hp_per:
            text += f"(깊이 {hp_step}당 +{hp_per}×)"
    if p.get("as_base") and p["as_base"] != 1.0:
        as_step = p.get("as_tree_step", atk_step)
        as_per = p.get("as_per_tree", 0)
        text += f", AS×{p['as_base']}"
        if as_per:
            text += f"(깊이 {as_step}당 +{as_per}×)"
    return text

def desc_tree_temp_buff(p: dict) -> str:
    cap = p["unit_cap"]
    if p.get("atk_mult"):
        text = f"≤{cap}기 ATK ×{p['atk_mult']}"
        if p.get("hp_mult"):
            text += f", HP ×{p['hp_mult']}(곱연산, 전투)"
    else:
        atk_base = fmt_pct(p["atk_base_pct"])
        atk_tree = fmt_pct(p["atk_tree_pct"])
        text = f"≤{cap}기 ATK +({atk_base}%+🌳×{atk_tree}%)(전투)"
        if p.get("hp_pct"):
            text += f", HP +{fmt_pct(p['hp_pct'])}%"
    if p.get("kill_hp_recover"):
        if isinstance(p["kill_hp_recover"], (int, float)) and p["kill_hp_recover"] != 1:
            text += f". 적 처치 HP {fmt_pct(p['kill_hp_recover'])}% 회복"
        else:
            text += ". 적 처치 HP 회복"
    return text

def desc_debuff_store(p: dict) -> str:
    t = resolve_target(p.get("target", "all_enemy"))
    stat = p["stat"].upper()
    base = fmt_pct(p["base_pct"])
    cap = fmt_pct(p["cap"])
    if p.get("tree_scale_pct"):
        scale = fmt_pct(p["tree_scale_pct"])
        return f"{t} {stat} -({base}%+🌳×{scale}%) (상한 -{cap}%)"
    return f"{t} {stat} -{base}% (상한 -{cap}%)"

def desc_epic_shop_unlock(p: dict) -> str:
    return f"🌳{p['tree_thresh']}+ → 매 라운드 에픽 업그레이드 후보 1장 상점 추가"

def desc_free_reroll(amount) -> str:
    return f"무료 리롤 +{amount}"

# ═══════════════════════════════════════════════════════════════════
# Predator effect descriptors
# ═══════════════════════════════════════════════════════════════════

def desc_hatch(p: dict) -> str:
    t = resolve_target(p["target"])
    return f"{t}에 부화 {p['count']}기"

def desc_hatch_enhance(p: dict) -> str:
    pct = fmt_pct(p["atk_pct"])
    return f"부화 유닛 ATK +{pct}% 성장"

def desc_meta_consume(p: dict) -> str:
    return f"변태({p['consume']}기 소모)"

def desc_hatch_scaled(p: dict) -> str:
    per = p["per_units"]
    cap = p["cap"]
    return f"생존 유닛당 부화 {per}기(최대 {cap})"

def desc_on_combat_result(p: dict) -> str:
    cond = p["condition"]
    cond_text = {"victory": "승리 시", "defeat": "패배 시",
                 "always": "승패 무관"}.get(cond, "")
    effects_text = ". ".join(desc_effect(e) for e in p["effects"])
    return f"{cond_text} {effects_text}"

def desc_swarm_buff(p: dict) -> str:
    t = resolve_target(p["target"])
    atk = fmt_pct(p["atk_per_unit"])
    per_n = p.get("per_n", 1)
    text = f"{t} 유닛 {per_n}기당 ATK +{atk}% 전투 버프"
    if p.get("ms_bonus"):
        ms = p["ms_bonus"]
        text += f". {ms['unit_thresh']}기+ → MS +{ms['bonus']}"
    if p.get("enhanced_count"):
        text += f". (강화) {p['enhanced_count']}기 카운트"
    if p.get("high_rank"):
        hr = p["high_rank"]
        if hr.get("as_bonus"):
            text += f". {hr['unit_thresh']}기+ → AS +{fmt_pct(hr['as_bonus'])}%"
    return text

def desc_persistent(p: dict) -> str:
    parts = []
    if p.get("death_atk_bonus"):
        pct = fmt_pct(p["death_atk_bonus"])
        parts.append(f"아군 사망 시 생존 ATK +{pct}%(전투)")
    if p.get("kill_hp_recover"):
        pct = fmt_pct(p["kill_hp_recover"])
        parts.append(f"적 처치 HP {pct}% 회복")
    if p.get("all_spawn_strongest"):
        parts.append("모든 스팀펑크 제조가 가장 강한 유닛(CP) 생성")
    return "[지속] " + ". ".join(parts)

# ═══════════════════════════════════════════════════════════════════
# Military effect descriptors
# ═══════════════════════════════════════════════════════════════════

def desc_train(p: dict) -> str:
    t = resolve_target(p["target"])
    n = p["amount"]
    return f"{t} 훈련(계급+{n})"

def desc_conscript(p: dict) -> str:
    t = resolve_target(p["target"])
    n = p["count"]
    enhanced = p.get("enhanced")
    text = f"{t}에 징집 {n}기"
    if enhanced == "partial":
        text += "(1기 강화 버전)"
    elif enhanced == "all":
        text += "(전원 강화 버전)"
    return text

def desc_rank_threshold(p: dict) -> str:
    tiers = p["tiers"]
    parts = []
    for tier in tiers:
        unit = tier.get("unit", "정예 유닛")
        n = tier.get("count", 1)
        bonus = ""
        if tier.get("atk_bonus"):
            bonus = f" ATK +{fmt_pct(tier['atk_bonus'])}%"
        parts.append(f"계급 {tier['rank']} → {unit} {n}기{bonus}")
    text = ". ".join(parts)
    if p.get("high_rank"):
        hr = p["high_rank"]
        if hr.get("atk_mult"):
            text += f". 계급 {hr['rank']} → 전체 ATK ×{hr['atk_mult']}"
        if hr.get("leader_spread"):
            spread = resolve_target(hr["leader_spread"])
            text += f". 계급 {hr['rank']} → 리더 버프 {spread} 확산"
    return text

def desc_rank_buff(p: dict) -> str:
    shield = fmt_pct(p["shield_per_rank"])
    atk_unit = fmt_pct(p["atk_per_unit"])
    enhanced = fmt_pct(p["enhanced_shield_bonus"])
    text = (f"모든 군대 카드에 방어막(HP 계급×{shield}%) + "
            f"ATK +유닛수×{atk_unit}%. (강화) 추가 +{enhanced}%")
    if p.get("high_rank"):
        hr = p["high_rank"]
        text += (f". 계급 {hr['rank_gte']}+ → "
                 f"AS +{fmt_pct(hr['as_bonus'])}%")
    return text

def desc_revive(p: dict) -> str:
    hp = fmt_pct(p["hp_pct"])
    limit = p["limit_per_combat"]
    text = f"(강화) 유닛 사망 시 HP {hp}% 부활({limit}/전투)"
    if p.get("shield_pct"):
        text += f" + 방어막(HP {fmt_pct(p['shield_pct'])}%)"
    if p.get("on_revive_buff"):
        buff = p["on_revive_buff"]
        text += f" + ATK +{fmt_pct(buff['atk_pct'])}%(전투)"
    return text

def desc_revive_override(p: dict) -> str:
    return "부활 대상 → 전체 군대(리더 포함)"

def desc_counter_produce(p: dict) -> str:
    thresh = p["threshold"]
    rewards = p["rewards"]
    parts = []
    if rewards.get("terazin"):
        parts.append(f"{rewards['terazin']} 테라진")
    if rewards.get("enhance_atk_pct"):
        parts.append(f"개량 ATK +{fmt_pct(rewards['enhance_atk_pct'])}%")
    # Military factory (trace 012 재설계)
    if rewards.get("global_military_atk_pct"):
        parts.append(f"모든 군대 카드 ATK +{fmt_pct(rewards['global_military_atk_pct'])}%(영구)")
    if rewards.get("global_military_range_bonus"):
        parts.append(f"모든 군대 카드 Range +{rewards['global_military_range_bonus']}(영구)")
    reward_text = " + ".join(parts) if parts else "(보상 없음)"
    return f"카운터 {thresh}+ → {thresh} 소비, {reward_text}"


# ─── Military R4/R10 milestone effects (trace 012) ───

def desc_spawn_unit(p: dict) -> str:
    t = resolve_target(p["target"])
    unit = _unit_name(p.get("unit", "유닛"))
    n = p.get("count", 1)
    return f"{t}에 {unit} {n}기 추가"

def desc_spawn_enhanced_random(p: dict) -> str:
    t = resolve_target(p["target"])
    n = p.get("count", 1)
    cap = p.get("max_per_round")
    text = f"{t}에 랜덤 (강화) {n}기"
    if cap:
        text += f" (라운드당 {cap}회)"
    return text

def desc_enhance_convert_card(p: dict) -> str:
    frac = p.get("fraction", 0.5)
    if frac >= 1.0:
        return "이 카드의 비(강화) 유닛 전원 → (강화)"
    return f"이 카드의 비(강화) 유닛 {fmt_pct(frac)}% → (강화)"

def desc_enhance_convert_target(p: dict) -> str:
    n = p.get("count", 1)
    cap = p.get("max_per_round")
    text = f"대상 카드의 비(강화) {n}기 → (강화)"
    if cap:
        text += f" (라운드당 {cap}회)"
    return text

def desc_crit_buff(p: dict) -> str:
    chance = fmt_pct(p["chance"])
    mult = p["mult"]
    return f"이 카드 유닛 치명타 {chance}% (×{mult} 피해)"

def desc_crit_splash(p: dict) -> str:
    pct = fmt_pct(p["splash_pct"])
    return f"치명타 시 인접 적에 {pct}% 스플래시"

def desc_rank_buff_hp(p: dict) -> str:
    t = resolve_target(p["target"])
    hp = fmt_pct(p["hp_per_rank"])
    return f"{t} HP +계급×{hp}%"

def desc_lifesteal(p: dict) -> str:
    t = resolve_target(p["target"])
    pct = fmt_pct(p["pct"])
    return f"{t} 유닛 라이프스틸 {pct}%"

def desc_high_rank_mult(p: dict) -> str:
    rank = p["rank"]
    mult = p["atk_mult"]
    return f"계급 {rank}+ 시 ATK ×{mult}"

def desc_grant_gold(p: dict) -> str:
    return f"골드 +{p['amount']}"

def desc_grant_terazin(p: dict) -> str:
    return f"테라진 +{p['amount']}"

def desc_upgrade_shop_bonus(p: dict) -> str:
    slot = p.get("slot_delta", 0)
    disc = p.get("terazin_discount", 0)
    parts = []
    if slot:
        parts.append(f"업그레이드 슬롯 +{slot}")
    if disc:
        parts.append(f"업그레이드 비용 -{disc} 테라진")
    return ", ".join(parts) if parts else "(효과 없음)"

def desc_conscript_pool_tier(p: dict) -> str:
    tier = p.get("tier", "enhanced")
    tier_kr = {"enhanced": "(강화)", "elite": "정예"}.get(tier, tier)
    return f"징집 풀에 {tier_kr} 유닛 추가"

def desc_revive_scope_override(p: dict) -> str:
    t = resolve_target(p["target"])
    return f"부활 대상 확장 → {t}"

def desc_rare_counter(p: dict) -> str:
    return (f"카운터 {p['threshold']}+ → "
            f"{p['threshold']} 소비, 레어 업그레이드 3택1")

def desc_epic_counter(p: dict) -> str:
    return (f"카운터 {p['threshold']}+ → "
            f"{p['threshold']} 소비, 에픽 업그레이드")

def desc_total_counter(p: dict) -> str:
    per = p["per_manufacture"]
    tz = p["reward_terazin"]
    return f"영구: 제조 {per}회마다 +{tz} 테라진"

def desc_upgrade_discount(p: dict) -> str:
    tier = RARITY_KR.get(p["tier"], p["tier"])
    pct = int(p["pct"] * 100)
    return f"[지속] {tier} 업그레이드 {pct}% 할인"

def desc_range_bonus(p: dict) -> str:
    raw_tag = p.get("tag", "firearm")
    tag = tag_kr(raw_tag)
    thresh = p["unit_thresh"]
    text = f"#{tag} 유닛 {thresh}기당 사거리 +1"
    if p.get("atk_buff_pct"):
        text += f". #{tag} ATK +{fmt_pct(p['atk_buff_pct'])}%"
    if p.get("attack_stack_pct"):
        text += (f". 공격 시마다 "
                 f"ATK +{fmt_pct(p['attack_stack_pct'])}%(전투)")
    return text

def desc_economy(p: dict) -> str:
    base = p.get("gold_base", 0)
    per = p.get("gold_per", 0)
    unit = p.get("gold_per_unit", "units")
    unit_text = "유닛 수" if unit == "units" else "군대 카드 수"
    halve = p.get("halve_on_loss", False)
    max_g = p.get("max_gold")
    if base:
        text = f"{base}골드 + {unit_text} × {per}골드"
    else:
        text = f"{unit_text} × {per}골드"
    if max_g:
        text += f"(최대 {max_g})"
    if halve:
        text += ". 패배 시 절반"
    else:
        text += ". 패배 전액"
    tz = p.get("terazin")
    if tz:
        cond = tz.get("condition", "always")
        if cond == "always":
            text += f" + {tz['amount']} 테라진"
        elif cond == "rank_gte":
            text += f". 계급 {tz['thresh']}+ → +{tz['amount']} 테라진"
    return text

def desc_battle_buff(p: dict) -> str:
    atk = fmt_pct(p["atk_per_reroll"])
    cap = p["cap"]
    return f"리롤 횟수 × ATK +{atk}%(최대 {cap}회)"

# ═══════════════════════════════════════════════════════════════════
# Effect dispatcher
# ═══════════════════════════════════════════════════════════════════

EFFECT_HANDLERS: dict[str, Any] = {
    # Common
    "spawn":            desc_spawn,
    "enhance":          desc_enhance,
    "buff":             desc_buff,
    "gold":             desc_gold,
    "terazin":          desc_terazin,
    "shield":           desc_shield,
    "scrap":            desc_scrap,
    "diversity_gold":   desc_diversity_gold,
    "absorb":           desc_absorb,
    # Druid
    "tree_add":         desc_tree_add,
    "tree_absorb":      desc_tree_absorb,
    "tree_breed":       desc_tree_breed,
    "tree_shield":      desc_tree_shield,
    "tree_enhance":     desc_tree_enhance,
    "tree_gold":        desc_tree_gold,
    "tree_distribute":  desc_tree_distribute,
    "druid_unit_enhance": desc_druid_unit_enhance,
    "multiply_stats":   desc_multiply_stats,
    "tree_temp_buff":   desc_tree_temp_buff,
    "debuff_store":     desc_debuff_store,
    "epic_shop_unlock": desc_epic_shop_unlock,
    "free_reroll":      desc_free_reroll,
    # Predator
    "hatch":            desc_hatch,
    "hatch_enhance":    desc_hatch_enhance,
    "meta_consume":     desc_meta_consume,
    "hatch_scaled":     desc_hatch_scaled,
    "on_combat_result": desc_on_combat_result,
    "swarm_buff":       desc_swarm_buff,
    "persistent":       desc_persistent,
    # Military
    "train":            desc_train,
    "conscript":        desc_conscript,
    "rank_threshold":   desc_rank_threshold,
    "rank_buff":        desc_rank_buff,
    "revive":           desc_revive,
    "revive_override":  desc_revive_override,
    "counter_produce":  desc_counter_produce,
    "rare_counter":     desc_rare_counter,
    "epic_counter":     desc_epic_counter,
    "total_counter":    desc_total_counter,
    "upgrade_discount": desc_upgrade_discount,
    "range_bonus":      desc_range_bonus,
    "economy":          desc_economy,
    "battle_buff":      desc_battle_buff,
    # Military R4/R10 재설계 (trace 012)
    "spawn_unit":              desc_spawn_unit,
    "spawn_enhanced_random":   desc_spawn_enhanced_random,
    "enhance_convert_card":    desc_enhance_convert_card,
    "enhance_convert_target":  desc_enhance_convert_target,
    "crit_buff":               desc_crit_buff,
    "crit_splash":             desc_crit_splash,
    "rank_buff_hp":            desc_rank_buff_hp,
    "lifesteal":               desc_lifesteal,
    "high_rank_mult":          desc_high_rank_mult,
    "grant_gold":              desc_grant_gold,
    "grant_terazin":           desc_grant_terazin,
    "upgrade_shop_bonus":      desc_upgrade_shop_bonus,
    "conscript_pool_tier":     desc_conscript_pool_tier,
    "revive_scope_override":   desc_revive_scope_override,
    # Steampunk-specific: hatch_enhance, battle_buff already covered
}

def desc_effect(eff: dict | int | float) -> str:
    """Single effect dict → text. Unknown actions get a placeholder."""
    if not isinstance(eff, dict):
        return str(eff)
    action = next(iter(eff))
    params = eff[action]
    handler = EFFECT_HANDLERS.get(action)
    if handler is None:
        print(f"WARNING: unknown action '{action}' — add handler",
              file=sys.stderr)
        return f"[TODO: {action}]"
    try:
        return handler(params)
    except (KeyError, TypeError) as e:
        print(f"ERROR: action '{action}' handler failed: {e}",
              file=sys.stderr)
        return f"[ERROR: {action} — {e}]"

# ═══════════════════════════════════════════════════════════════════
# Conditional / post_threshold
# ═══════════════════════════════════════════════════════════════════

CONDITION_TEXT = {
    "unit_count_gte": lambda v: f"이 카드 {v}기 이상이면",
    "unit_count_lte": lambda v: f"이 카드 ≤{v}기이면",
    "tenure_gte":     lambda v: f"{v}R+ 체류 시",
    "rank_gte":       lambda v: f"계급 {v}+ 이면",
}

def desc_conditional(cond: dict) -> str:
    when = cond["when"]
    cond_type = next(iter(when))
    threshold = when[cond_type]
    cond_text = CONDITION_TEXT.get(cond_type, lambda v: f"{cond_type}={v}")(
        threshold)
    effects = [desc_effect(e) for e in cond["effects"]]
    return f"{cond_text} {' + '.join(effects)}"

def desc_post_threshold(effects: list) -> str:
    parts = [desc_effect(e) for e in effects]
    return f"이후 매 라운드 {'. '.join(parts)}"


R_CONDITIONAL_PREFIX = {
    "rank_gte": lambda v: f"[R{v}]",
}


def desc_r_conditional(r_cond: dict) -> str:
    """Render one r_conditional milestone entry (military R4/R10).

    YAML shape:
      - when: {rank_gte: 4}
        effects: [{enhance_convert_card: {fraction: 0.5}}, {train: {...}}]
    Output: "[R4] 이 카드의 비(강화) 유닛 50% → (강화) + 오른쪽 인접 카드 훈련(계급+1)"
    """
    when = r_cond.get("when", {})
    cond_type = next(iter(when)) if when else "rank_gte"
    threshold = when.get(cond_type, 0)
    prefix_fn = R_CONDITIONAL_PREFIX.get(cond_type,
                                         lambda v: f"[{cond_type}={v}]")
    prefix = prefix_fn(threshold)
    effects = [desc_effect(e) for e in r_cond.get("effects", [])]
    return f"{prefix} {' + '.join(effects)}"

# ═══════════════════════════════════════════════════════════════════
# Prefix helpers
# ═══════════════════════════════════════════════════════════════════

def get_oe_prefix(card: dict) -> str:
    listen = card.get("listen", {})
    key = (listen.get("l1"), listen.get("l2"))
    base = OE_PREFIX.get(key, f"[반응] {key}:")
    # require_other: true 인 카드는 자기 자신이 방출한 이벤트에는 반응하지 않는다
    # (chain_engine.gd: require_other_card 체크). 이 의미를 툴팁에 반영.
    if card.get("require_other"):
        base = base.replace("[반응] ", "[반응] 다른 카드의 ", 1)
    return base

def get_prefix(card: dict, timing: str) -> str:
    if timing == "OE":
        return get_oe_prefix(card)
    return TIMING_PREFIX.get(timing, timing + ":")

def prefix_tenure(card: dict, star_data: dict) -> str:
    tenure = star_data.get("require_tenure",
                           card.get("require_tenure", 0))
    threshold = star_data.get("is_threshold",
                              card.get("is_threshold", False))
    if tenure > 0:
        if threshold:
            return f"필드 {tenure}R+ 체류 시 1회:"
        return f"필드 {tenure}R+ 체류 시"
    return ""

def desc_max_act_suffix(max_act: int, timing: str) -> str:
    if max_act == -1:
        return ""  # RS/BS cards — 1x per round is obvious
    if max_act == 0:
        return " (발동 무제한)"
    return f" (최대 {max_act}/R)"

# ═══════════════════════════════════════════════════════════════════
# Main generator
# ═══════════════════════════════════════════════════════════════════

def generate_star_desc(card: dict, star_data: dict) -> str:
    """Generate complete description for one ★ level."""
    # 1. Base timing (★-level override possible)
    base_timing = star_data.get("timing", card["timing"])

    # 2. Group effects by timing
    timing_groups: dict[str, list[str]] = {}
    for eff in star_data.get("effects", []):
        if not isinstance(eff, dict):
            timing_groups.setdefault(base_timing, []).append(str(eff))
            continue
        action = next(iter(eff))
        params = eff[action]
        # Per-effect timing_override field (tree_shield etc.)
        eff_timing = None
        if isinstance(params, dict):
            eff_timing = params.get("timing_override")
        # ACTION_TIMING_OVERRIDE (economy, battle_buff etc.)
        if not eff_timing:
            eff_timing = ACTION_TIMING_OVERRIDE.get(action)
        # Default: card timing
        if not eff_timing:
            eff_timing = base_timing
        timing_groups.setdefault(eff_timing, []).append(desc_effect(eff))

    # 3. Conditionals → base timing group
    for cond in star_data.get("conditional", []):
        timing_groups.setdefault(base_timing, []).append(
            desc_conditional(cond))

    # 4. post_threshold → base timing group
    if star_data.get("post_threshold"):
        timing_groups.setdefault(base_timing, []).append(
            desc_post_threshold(star_data["post_threshold"]))

    # 4.5. r_conditional (rank milestones, e.g. military R4/R10) → base timing
    # Each milestone rendered with "[R4] ..." / "[R10] ..." prefix.
    for rcond in star_data.get("r_conditional") or []:
        timing_groups.setdefault(base_timing, []).append(
            desc_r_conditional(rcond))

    # 5. Tenure prefix
    tenure_pfx = prefix_tenure(card, star_data)

    # 6. Assemble per-timing texts
    parts = []
    # Base timing first, then others
    ordered = [base_timing] + [t for t in timing_groups if t != base_timing]
    for timing in ordered:
        if timing not in timing_groups:
            continue
        if timing == base_timing:
            pfx = get_prefix(card, base_timing)
            if tenure_pfx:
                pfx = f"{tenure_pfx} {pfx}"
        else:
            pfx = TIMING_PREFIX.get(timing, timing + ":")
        body = ". ".join(timing_groups[timing])
        parts.append(f"{pfx} {body}")

    # 7. max_act suffix
    suffix = desc_max_act_suffix(star_data["max_act"], base_timing)

    return ". ".join(parts) + suffix

def generate_all_descs(
    all_cards: dict[str, dict[str, dict]]
) -> dict[str, dict[int, str]]:
    """
    Generate descriptions for all cards.

    Args:
        all_cards: {theme_name: {card_id: card_data}}

    Returns:
        {card_id: {1: "★1 desc", 2: "★2 desc", 3: "★3 desc"}}
    """
    result: dict[str, dict[int, str]] = {}
    for _theme, cards in all_cards.items():
        for card_id, card in cards.items():
            stars = card.get("stars", {})
            descs: dict[int, str] = {}
            for star_n in (1, 2, 3):
                star_data = stars.get(star_n)
                if star_data is None:
                    continue
                descs[star_n] = generate_star_desc(card, star_data)
            result[card_id] = descs
    return result

