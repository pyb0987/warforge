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
    # Military factory PC target (2026-04-21): "이번 라운드 TR 이벤트가 있던 군대 카드들"
    "trained_this_round": "이번 라운드 훈련된 각 군대 카드",
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


def desc_absorb_steampunk(p: dict) -> str:
    ratio = fmt_pct(p.get("growth_ratio", 0.5))
    text = f"판매된 스팀펑크 카드의 모든 유닛 흡수 + 성장률 {ratio}% 이식"
    if p.get("transfer_upgrades"):
        text += " + 업그레이드 이전"
    return text


def desc_growth_multiply(p: dict) -> str:
    pct = fmt_pct(p.get("pct", 0.2))
    return f"이 카드의 성장률 +{pct}% 개량(복리)"

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
    ## iter3 N3: '≤3기 ×1.5' 수식 대상 모호. 런타임(_lifebeat_battle):
    ## 'shield *= low_mult' — 방어막 수치 전체에 곱. 기준은 이 카드 유닛 수.
    t = resolve_target(p["target"])
    base = fmt_pct(p["base_pct"])
    scale = fmt_pct(p["tree_scale_pct"])
    text = f"{t}에 방어막(HP {base}%+🌳×{scale}%)"
    low = p.get("low_unit")
    if low:
        text += (f". 이 카드 ≤{low['thresh']}기이면 "
                 f"방어막 수치 ×{low['mult']}")
    return text

def desc_tree_enhance(p: dict) -> str:
    ## 런타임 의미 (druid_system._tree_enhance):
    ##   - low_unit: 이 카드 유닛 수 ≤ thresh 시 base_pct 대체 (더 큰 계수로)
    ##   - tree_bonus: 🌳 ≥ thresh 시 최종 growth에 mult 곱 (누적)
    ## P2 (review R4, 2026-04-17): 대체/곱셈 관계를 desc에 명시.
    base = fmt_pct(p["base_pct"])
    target = p.get("target", "self")
    target_text = "전체 드루이드" if target == "all_druid" else "이 카드"
    text = f"{target_text} ATK+HP +(🌳×{base}%) 성장"
    low = p.get("low_unit")
    if low:
        low_pct = fmt_pct(low["pct"])
        text += f". 이 카드 ≤{low['thresh']}기이면 계수 🌳×{low_pct}% 대체 적용"
    bonus = p.get("tree_bonus")
    if bonus:
        mult = bonus.get("mult", 1.3)
        text += f". 🌳 {bonus['thresh']}+ 시 최종 성장 ×{mult}"
    return text

def desc_tree_gold(p: dict) -> str:
    base = p["base_gold"]
    div = p["tree_divisor"]
    text = f"{base}골드 + 🌳÷{div} 골드"
    if p.get("win_half"):
        text += ". 패배 시 절반"
    else:
        text += ". 승패 무관 전액"
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

def desc_prune(p: dict) -> str:
    count = p.get("count", 2)
    min_u = p.get("min_units", 3)
    text = f"유닛 최다 카드의 최약 {count}기→🌳 변환 (≤{min_u - 1}기 스킵)"
    ep = p.get("enhance_pct")
    if ep:
        text += f". 남은 유닛 ATK+HP +{fmt_pct(ep)}%"
    return text


def desc_druid_unit_enhance(p: dict) -> str:
    ## iter3 N4: '8기+/12기+' 집계 기준이 불명. 런타임(_earth)은 필드
    ## 전체 드루이드 유닛 합계를 사용하므로 이를 명시.
    div = p["divisor"]
    text = (f"모든 드루이드 ATK+HP +(필드 전체 드루이드 유닛 수÷{div})% "
            f"성장")
    if p.get("bonus_tiers"):
        for bt in p["bonus_tiers"]:
            pct = fmt_pct(bt["bonus_pct"])
            text += (f". 필드 전체 드루이드 유닛 {bt['unit_gte']}기 이상이면 "
                     f"추가 +{pct}% 성장")
    return text

def desc_multiply_stats(p: dict) -> str:
    ## 2026-04-21 재설계: dr_world 의 multiply_stats 가
    ## target: all_allies (필드 전체), unit_cap 제거, tree_source:forest_depth.
    ## P2 (review R1, 2026-04-17): 3축 각 독립 줄로 배치, '전체 나무 수' 용어 통일.
    atk_base = p["atk_base"]
    atk_step = p["atk_tree_step"]
    atk_per = p["atk_per_tree"]
    tgt_str = resolve_target(p.get("target", "all_allies"))

    lines = [f"[지속] {tgt_str} 유닛 스탯 배수 적용:"]
    lines.append(f"  ATK ×{atk_base} (전체 나무 수 {atk_step}당 +{atk_per}×)")
    if p.get("hp_base"):
        hp_step = p.get("hp_tree_step", atk_step)
        hp_per = p.get("hp_per_tree", 0)
        hp_tail = (f" (전체 나무 수 {hp_step}당 +{hp_per}×)"
                   if hp_per else "")
        lines.append(f"  HP ×{p['hp_base']}{hp_tail}")
    if p.get("as_base") and p["as_base"] != 1.0:
        as_step = p.get("as_tree_step", atk_step)
        as_per = p.get("as_per_tree", 0)
        as_tail = (f" (전체 나무 수 {as_step}당 +{as_per}×)"
                   if as_per else "")
        lines.append(f"  AS ×{p['as_base']}{as_tail}")
    return "\n".join(lines)

def desc_tree_temp_buff(p: dict) -> str:
    cap = p["unit_cap"]
    # '이 카드' prefix를 CONDITION_TEXT["unit_count_lte"]와 일치시켜 다른 lte
    # 조건문(ne_wildforce, pr_apex_hunt 등)과 표기 통일 (review 2026-04-17 L2).
    cond_pfx = f"이 카드 ≤{cap}기이면"
    if p.get("atk_mult"):
        text = f"{cond_pfx} ATK ×{p['atk_mult']}"
        if p.get("hp_mult"):
            text += f", HP ×{p['hp_mult']}(곱연산, 이번 전투)"
    else:
        atk_base = fmt_pct(p["atk_base_pct"])
        atk_tree = fmt_pct(p["atk_tree_pct"])
        text = f"{cond_pfx} ATK +({atk_base}%+🌳×{atk_tree}%)(이번 전투)"
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
    base = f"변태({p['consume']}기 소모)"
    count = p.get("count", 1)
    if count > 1:
        return f"{base} × {count}회"
    return base

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
    ## P2-3 + iter3 N1 + iter4 L1:
    ## 집계 prefix가 atk_per_unit + ms_thresh 양쪽에 공통 적용됨을 명시.
    ## ms/as 조건 문장은 '+' 연결자로 단일 segment 내부에 머물게 해서
    ## compress_repeated_target이 '동 대상'으로 축약하는 상황을 방지 —
    ## 플레이어가 '동 대상'의 지시 대상을 혼동하지 않도록.
    t = resolve_target(p["target"])
    atk = fmt_pct(p["atk_per_unit"])
    per_n = p.get("per_n", 1)
    ec = int(p.get("enhanced_count", 1))
    enh_note = (f"(강화) 유닛은 {ec}기로 집계. " if ec > 1 else "")
    text = enh_note + (
        f"{t} 유닛 1기당 ATK +{atk}% 전투 버프"
        if per_n == 1 else
        f"{t} 유닛 {per_n}기당 ATK +{atk}% 전투 버프"
    )
    if p.get("ms_bonus"):
        ms = p["ms_bonus"]
        text += (f" + {t} 유닛 합계 {ms['unit_thresh']}기 이상이면 "
                 f"MS +{ms['bonus']}")
    if p.get("high_rank"):
        hr = p["high_rank"]
        if hr.get("as_bonus"):
            text += (f" + {t} 유닛 합계 {hr['unit_thresh']}기 이상이면 "
                     f"AS +{fmt_pct(hr['as_bonus'])}%")
    return text

def desc_persistent(p: dict) -> str:
    parts = []
    if p.get("death_atk_bonus"):
        pct = fmt_pct(p["death_atk_bonus"])
        parts.append(f"아군 사망 시 생존 ATK +{pct}%(이번 전투)")
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
    text = f"{t}에 징집 {n}기"
    # enhanced_count: 강화 버전 유닛 수 (0 ≤ enhanced_count ≤ count).
    # P1-1 migration (2026-04-17): 기존 'enhanced: partial/all' 문자열 필드를
    # 이 수량 필드로 교체. 0이면 표기 생략, count와 같으면 '(전원 (강화))',
    # 그 외엔 '(그중 N기는 (강화))'로 관계 명시.
    # 호환: 기존 'enhanced: partial/all' entry가 남아있으면 관습대로 해석.
    eh = int(p.get("enhanced_count", 0))
    if "enhanced" in p and not eh:
        eh = 1 if p["enhanced"] == "partial" else (n if p["enhanced"] == "all" else 0)
    if eh <= 0:
        return text
    if eh >= n:
        text += " (전원 (강화))" if n > 1 else " (강화)"
    else:
        text += f" (그중 {eh}기는 (강화))"
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
    ## iter3 N2 + iter4 L3: shield/ATK 축 명시 + 단위 명시.
    ## 런타임(_tactical_battle)은 shield_hp_pct에 %p 가산하므로 '+Np' 표기.
    shield = fmt_pct(p["shield_per_rank"])
    atk_unit = fmt_pct(p["atk_per_unit"])
    enhanced = fmt_pct(p["enhanced_shield_bonus"])
    text = (f"모든 군대 카드에 방어막(HP 계급×{shield}%) + "
            f"ATK +유닛수×{atk_unit}%. "
            f"(강화) 유닛 보유 카드는 방어막 HP +{enhanced}%p 추가")
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
        text += f" + ATK +{fmt_pct(buff['atk_pct'])}%(이번 전투)"
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


def desc_rank_scaled_enhance(p: dict) -> str:
    ## ml_factory (2026-04-21 재설계). PC 타이밍에 "이번 라운드 훈련된"
    ## (= 이번 라운드에 TR 이벤트가 1회+ 발생한) 군대 카드들 각각에
    ## (그 카드의 계급) × atk_pct_per_rank 만큼 ATK 영구 강화.
    ## ml_factory 자신 rank 4+ 일 때 동일 비율 HP 강화, rank 10+ 일 때
    ## 동일 비율 AS 강화(공격 속도 향상) 가 붙는다.
    ## 추가로 자신의 계급 +1 (self-train, 이벤트 방출 없음).
    target = resolve_target(p.get("target", ""))
    atk_pct = p.get("atk_pct_per_rank", 0.0)
    r4_hp_pct = p.get("r4_hp_pct_per_rank", 0.0)
    r10_as_pct = p.get("r10_as_pct_per_rank", 0.0)
    s = f"{target}에 (그 카드의 계급) × {fmt_pct(atk_pct)}% ATK 영구 강화"
    gates = []
    if r4_hp_pct > 0.0:
        gates.append(f"이 카드 계급 4+: HP 도 동일 비율")
    if r10_as_pct > 0.0:
        gates.append(f"계급 10+: AS 도 동일 비율")
    if gates:
        s += f" ({', '.join(gates)})"
    s += ". 이 카드 계급 +1"
    return s


# ─── Military R4/R10 milestone effects (trace 012) ───

def desc_spawn_unit(p: dict) -> str:
    t = resolve_target(p["target"])
    unit = _unit_name(p.get("unit", "유닛"))
    n = p.get("count", 1)
    return f"{t}에 {unit} {n}기 추가"

def desc_spawn_enhanced_random(p: dict) -> str:
    ## ml_academy R10 전용. R4의 enhance_convert_target과 slot 공유
    ## (military_system._dispatch_r_effect: academy_convert_tenure).
    ## R10 도달 시 R4 효과를 대체하므로 '랭크 4 슬롯과 공유' 명시.
    t = resolve_target(p["target"])
    n = p.get("count", 1)
    cap = p.get("max_per_round")
    text = f"{t}에 랜덤 (강화) {n}기"
    if cap:
        text += f" (라운드당 {cap}회, 랭크 4 효과 대체)"
    return text

def desc_enhance_convert_card(p: dict) -> str:
    ## 군대 10장 × 3★ = 30 entries에 반복되는 R4/R10 공통 전환 효과.
    ## 2026-04-19: '부대' 키워드 제거 — '유닛'과 중복되어 혼란 유발. 전원 '유닛'으로 통일.
    frac = p.get("fraction", 0.5)
    if frac >= 1.0:
        return "비(강화) 유닛 전원 → (강화)"
    if frac == 0.5:
        return "비(강화) 유닛 절반 → (강화)"
    return f"비(강화) 유닛 {fmt_pct(frac)}% → (강화)"

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

def desc_manufacture(p: dict) -> str:
    count = p.get("count", 1)
    return f"이 카드에 유닛 {count}기 제조 (#화기 랜덤)"


def desc_range_bonus(p: dict) -> str:
    raw_tag = p.get("tag", "firearm")
    tag = tag_kr(raw_tag)
    thresh = p["unit_thresh"]
    text = f"#{tag} 유닛 {thresh}기당 사거리 +1"
    if p.get("atk_buff_pct"):
        text += f". #{tag} ATK +{fmt_pct(p['atk_buff_pct'])}%"
    if p.get("attack_stack_pct"):
        text += (f". 공격 시마다 "
                 f"ATK +{fmt_pct(p['attack_stack_pct'])}%(이번 전투)")
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
        text += ". 승패 무관 전액"
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
    "absorb_steampunk": desc_absorb_steampunk,
    "growth_multiply":  desc_growth_multiply,
    # Druid
    "tree_add":         desc_tree_add,
    "tree_absorb":      desc_tree_absorb,
    "tree_breed":       desc_tree_breed,
    "tree_shield":      desc_tree_shield,
    "tree_enhance":     desc_tree_enhance,
    "tree_gold":        desc_tree_gold,
    "tree_distribute":  desc_tree_distribute,
    "druid_unit_enhance": desc_druid_unit_enhance,
    "prune":             desc_prune,
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
    "manufacture":      desc_manufacture,
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
    # ml_factory PC 재설계 (2026-04-21)
    "rank_scaled_enhance":     desc_rank_scaled_enhance,
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
    ## iter3 N5: '1회' trigger 끝나고 '이후 매 라운드' 경계를 명확히 하기 위해
    ## 줄바꿈 prefix로 물리 분리. ne_awakening ★3 등에서 '1회성 대각성'과
    ## '영구 영향'을 시각적으로 구분.
    parts = [desc_effect(e) for e in effects]
    return f"\n이후 매 라운드: {', '.join(parts)}"


R_CONDITIONAL_PREFIX = {
    # P1-3 (2026-04-17): 과거 '[R4]' 축약 표기는 "조건/추가 효과"의 의미를
    # 플레이어에게 자명하게 전달하지 못했다. '[랭크 N 이상]'은 한국어로
    # 조건절임을 명시하고, 상위 milestone 도달 시 하위 milestone이 그대로
    # 유효함을 '이상'이라는 표현으로 자연스럽게 시사한다.
    "rank_gte": lambda v: f"[랭크 {v} 이상]",
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

COUNTER_ACTIONS = frozenset([
    "counter_produce", "rare_counter", "epic_counter", "total_counter",
])


def counter_prefix_for(card: dict, star_data: dict) -> str:
    """카드의 base effects에 counter 계열 action이 있으면 '이벤트 1회당 카운터 +1'
    을 명시하는 짧은 prefix를 반환. 없으면 빈 문자열.

    P1-2 (2026-04-17): 기존에는 카운터 축적 규칙(이벤트당 +1)이 런타임에만
    존재하고 description에는 없어, 플레이어가 '카운터 N+'의 전제를 몰랐다.
    OE 카드의 listen.l2가 이벤트 타입을 결정하므로 여기서 자동 유추.
    """
    has_counter = any(
        isinstance(e, dict) and next(iter(e)) in COUNTER_ACTIONS
        for e in star_data.get("effects", []) or []
    )
    if not has_counter:
        return ""
    l2 = (card.get("listen") or {}).get("l2")
    event_name = {
        "MF": "제조",
        "CO": "징집",
        "TR": "훈련",
        "HA": "부화",
        "MT": "변태",
        "UP": "개량",
        "BR": "번식",
        "TG": "나무 성장",
    }.get(l2, "발동")
    # self_target_multiplier — counter_produce 의 self-target bonus 표시.
    self_mult = None
    for e in star_data.get("effects", []) or []:
        if isinstance(e, dict) and next(iter(e)) == "counter_produce":
            params = e["counter_produce"]
            if isinstance(params, dict) and params.get("self_target_multiplier"):
                self_mult = params["self_target_multiplier"]
            break
    if self_mult and self_mult > 1:
        return f"{event_name} 1회당 카운터 +1 (이 카드 대상이면 +{self_mult})."
    return f"{event_name} 1회당 카운터 +1."


def compress_repeated_target(body: str) -> str:
    """같은 target prefix가 연속된 여러 segment에서 중복을 접는다.

    예 (ne_awakening ★1):
      '필드 위 모든 카드에 2기 유닛. 필드 위 모든 카드 ATK +10% 영구 강화.
       필드 위 모든 카드 유닛에 방어막(HP 20%)'
    →  '필드 위 모든 카드에 2기 유닛, 동 대상 ATK +10% 영구 강화, 동 대상
        유닛에 방어막(HP 20%)'

    대상 prefix 후보는 TARGET dict에 정의된 한국어 라벨 중 **4자 이상** 만
    대상으로 한다 ('self'='이 카드'처럼 짧은 건 접기 효과 없음).

    P2 (review R5, 2026-04-17): 'ne_awakening'처럼 동일 대상에 여러 효과가
    같은 timing으로 걸리는 카드의 가독성 개선.
    """
    segments = body.split(". ")
    if len(segments) < 2:
        return body
    # '이 카드'(4자) / '적 전체'(4자) / '해당 카드'(5자) 같은 짧고 흔한
    # prefix는 서로 다른 의미의 effect 사이에도 우연히 매칭되어 의미를
    # 흐릴 수 있으므로 제외. 테마별 집합형 target('필드 위 모든 카드',
    # '모든 군대 카드' 등)만 안전하게 접는다.
    target_labels = [t for t in TARGET.values() if len(t) >= 7]
    out: list[str] = [segments[0]]
    current_prefix: str = ""
    for tlabel in target_labels:
        if segments[0].startswith(tlabel):
            current_prefix = tlabel
            break
    for seg in segments[1:]:
        matched = None
        for tlabel in target_labels:
            if seg.startswith(tlabel) and tlabel == current_prefix:
                matched = tlabel
                break
        if matched:
            # Replace the repeated prefix with "동 대상" and use comma join.
            suffix = seg[len(matched):].lstrip()
            out[-1] = out[-1] + ", 동 대상 " + suffix
        else:
            out.append(seg)
            current_prefix = ""
            for tlabel in target_labels:
                if seg.startswith(tlabel):
                    current_prefix = tlabel
                    break
    return ". ".join(out)


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
    # Each milestone rendered with "[랭크 N 이상] ..." prefix on its own line.
    # P2-1 (2026-04-17): base+R4+R10을 한 줄 prose로 합치면 플레이어가 경계를
    # 찾지 못해 스캔 불가 (review H3 HIGH). r_conditional entry 앞에 '\n'을
    # 끼워 tooltip 렌더러가 물리적 줄바꿈으로 분리하게 한다.
    # 구분자는 '. ' 기준 join 후에도 살아남아 최종 출력에 반영됨.
    for rcond in star_data.get("r_conditional") or []:
        timing_groups.setdefault(base_timing, []).append(
            "\n" + desc_r_conditional(rcond))

    # 5. Tenure prefix
    tenure_pfx = prefix_tenure(card, star_data)

    # 5.5. Counter auto-prefix (P1-2): counter 계열 action이 있으면
    # 'X 1회당 카운터 +1'을 base 본문 앞에 삽입해 축적 전제 노출.
    counter_pfx = counter_prefix_for(card, star_data)

    # 6. Assemble per-timing texts — each timing section carries its OWN
    # max_act suffix when available (multi-block aware). Falls back to the
    # star-level max_act for the base timing in legacy single-block cases.
    max_act_map: dict = star_data.get("max_act_by_timing", {})
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
        # r_conditional 엔트리 앞에 삽입된 '\n'의 앞쪽 '. ' 소거 (P2-1).
        body = body.replace(". \n", "\n")
        # 같은 target prefix 연속 반복 압축 (R5).
        body = compress_repeated_target(body)
        if timing == base_timing and counter_pfx:
            body = f"{counter_pfx} {body}"
        # Per-block max_act suffix: attach to this timing's section, not the
        # whole sentence. timing_override / ACTION_TIMING_OVERRIDE 로 만들어진
        # 가짜 timing group 은 블록이 아니므로 map 에 없어 suffix 없음 (정상).
        if timing in max_act_map:
            block_suffix = desc_max_act_suffix(max_act_map[timing], timing)
        elif timing == base_timing:
            # Fallback for projections lacking max_act_by_timing (legacy).
            block_suffix = desc_max_act_suffix(star_data["max_act"], base_timing)
        else:
            block_suffix = ""
        parts.append(f"{pfx} {body}{block_suffix}")

    return ". ".join(parts)

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

