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
# Keyword glossary — Single Source of Truth (data/keywords.yaml)
# ═══════════════════════════════════════════════════════════════════
# desc 핸들러는 키워드 한글 표기를 하드코딩하지 않고 _kw / _kw_reaction
# 으로 lookup. P5 사다리 3단계 — 사전 우회 시 codegen guard 가 차단.

_KEYWORDS_CACHE: dict | None = None

def _load_keywords() -> dict:
    global _KEYWORDS_CACHE
    if _KEYWORDS_CACHE is None:
        path = Path(__file__).resolve().parent.parent / "data/keywords.yaml"
        try:
            import yaml
            with open(path, encoding="utf-8") as f:
                _KEYWORDS_CACHE = yaml.safe_load(f)
        except Exception as e:
            raise RuntimeError(f"data/keywords.yaml 로드 실패: {e}")
    return _KEYWORDS_CACHE

def _kw(layer: str, code: str) -> str:
    """이벤트 키워드 표기 (예: _kw('layer2', 'CO') → '징집').

    layer: 'layer1' | 'layer2'
    drift 방지: desc 핸들러는 'CO', '징집' 같은 한글 키워드 문자열을 직접 쓰지 말 것.
    """
    g = _load_keywords()
    entry = g.get(layer, {}).get(code)
    if not entry:
        raise KeyError(f"keywords.yaml: {layer}.{code} 미정의")
    return entry["name"]

def _kw_reaction(l1: str | None, l2: str | None, *, other_only: bool) -> str:
    """[반응] prefix 생성.

    l1/l2 중 더 구체적인 prefix 선택 (l2 우선). other_only=True 면 '다른 카드의'
    한정자, False 면 '어디서든' 한정자. 기존 OE_PREFIX 의 ambiguity 해소.
    """
    g = _load_keywords()
    src_label = g["reaction_origin"]["other_only"] if other_only \
        else g["reaction_origin"]["any"]
    if l2 and l2 in g.get("layer2", {}):
        body = g["layer2"][l2]["reaction_prefix"]
    elif l1 and l1 in g.get("layer1", {}):
        body = g["layer1"][l1]["reaction_prefix"]
    else:
        body = "이벤트 시"
    return f"[반응] {src_label} {body}:"

def _kw_filter(filter_id: str) -> str:
    """target_filters lookup (예: 'cross_theme' → '이 카드와 다른 테마의 대상이면').
    """
    g = _load_keywords()
    entry = g.get("target_filters", {}).get(filter_id)
    if not entry:
        raise KeyError(f"keywords.yaml: target_filters.{filter_id} 미정의")
    return entry["text"]

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

# OE_PREFIX 는 keywords.yaml + _kw_reaction 으로 동적 생성한다 (lookup 타임).
# 비-glossary 키 (MERGE, REROLL, SELL, ANY) 는 별도 핸들링.
# 사용처: build_oe_prefix(card) — require_other 플래그까지 함께 평가.
NON_GLOSSARY_OE_PREFIX = {
    ("UA", "MERGE"):  "★합성 시:",
    ("UA", "REROLL"): "리롤 시:",
    ("UA", "SELL"):   "[반응] 판매 시:",
}

# Action types whose intrinsic timing differs from the card's base timing
ACTION_TIMING_OVERRIDE = {
    "economy":          "PC",
    "battle_buff":      "BS",
    "tree_combat_bonus": "BS",
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
    "event_source":      "해당 카드",
    "self_and_both_adj": "이 카드 + 양쪽 인접 카드",
    "adj_druids":        "인접 드루이드 카드",
    "adj_or_self":       "인접 카드",
    "both_adj_or_self":  "양쪽 인접 카드",
    "all_other_druid":   "필드 위 모든 드루이드 카드",
    "enhanced_units":    "(강화) 유닛",
    # Military R4/R10 재설계 target (trace 012)
    "far_military":      "인접하지 않은 다른 군대 카드",
    "event_target_adj":  "해당 카드 양쪽 인접 카드",
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
    # Layer 2 (theme keyword) 가 있으면 그것이 verb. 없으면 Layer 1 'UA' = '유닛 추가'.
    # Drift 방지: 키워드 한글 표기는 _kw 로만 lookup (data/keywords.yaml 단일 진실 소스).
    if ol2 == "MF":
        verb = _kw("layer2", "MF")
    else:
        verb = _kw("layer1", "UA")
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
        # ATK/HP 분리 표기 (값이 같아도 '+' 으로 합치지 않음 — 사용자 요청).
        atk_pct = fmt_pct(atk_val)
        hp_pct = fmt_pct(hp_val)
        return f"{t}{tag_text} ATK +{atk_pct}% / HP +{hp_pct}% {verb}"
    return f"{t}{tag_text} ATK +{fmt_pct(atk_val)}% {verb}"

def desc_buff(p: dict) -> str:
    ## 버프 효과: tag 가 있으면 '{대상} #{tag} 유닛' (tag 필터 의미 보존),
    ## 없으면 '{대상}' 만 사용해 '유닛' 군더더기 제거.
    t = resolve_target(p["target"])
    has_tag = bool(p.get("tag"))
    scope = f"{t} #{tag_kr(p['tag'])} 유닛" if has_tag else t
    if p.get("atk_mult"):
        text = f"{scope} ATK ×{p['atk_mult']}(이번 전투)"
    elif p.get("as_bonus"):
        # military ml_tactical R10: 모든 군대 카드 AS +15%
        text = f"{scope} AS +{fmt_pct(p['as_bonus'])}%(이번 전투)"
    else:
        atk = fmt_pct(p["atk_pct"])
        text = f"{scope} ATK +{atk}%(이번 전투)"
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
    return f"{t}에 방어막(HP {pct}%)"

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
    text = f"판매된 스팀펑크 카드의 모든 유닛 흡수 + 누적 개량 {ratio}% 이식"
    if p.get("transfer_upgrades"):
        text += " + 업그레이드 이전"
    return text


def desc_growth_multiply(p: dict) -> str:
    pct = fmt_pct(p.get("pct", 0.2))
    return f"이 카드의 누적 개량 효과 +{pct}% 증폭(복리)"

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

def desc_tree_combat_bonus(p: dict) -> str:
    t = resolve_target(p.get("target", "self"))
    per_tree = fmt_pct(p.get("per_tree_pct", 0.02))
    cap = fmt_pct(p.get("cap_pct", 0.2))
    return f"{t} ATK/HP +(자기 🌳×{per_tree}%) (상한 +{cap}%, 이번 전투)"

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
    ## 자기 자신의 🌳 카운트가 임계 이상이면 다른 모든 드루이드 카드 각각에 🌳을 분배.
    ## (이전 표기 "전체 드루이드 +1" 은 합산/개별/단위가 모호 → 명시적 표현으로 교체.)
    tiers = p["tiers"]
    parts = []
    for tier in tiers:
        parts.append(
            f"이 카드 🌳{tier['tree_gte']}+ → 다른 드루이드 카드 각각 🌳+{tier['amount']}")
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
    ## 2026-04-28 재설계: dr_world 누적 가산형.
    ##   per_step 만큼 ATK/HP/AS 가 함께 (additive cumulative) 매 라운드 증가.
    ##   tree_step 마다 1 step. 누적은 라운드 간 보존.
    tgt_str = resolve_target(p.get("target", "all_allies"))
    per_step = p.get("per_step", 0.05)
    tree_step = p.get("tree_step", 30)
    pct_str = fmt_pct(per_step)
    return (f"[지속] 매 라운드 {tgt_str} ATK/HP/AS 동시 +{pct_str}% 누적 "
            f"(전체 나무 수 {tree_step}개당 1 step)")

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

def desc_free_reroll(p) -> str:
    if isinstance(p, dict):
        amount = p.get("value", 0)
    else:
        amount = p
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
    # 대상 명시 (target 미지정 시 implicit self → '이 카드' prefix).
    # count > 1 이면 'N회' suffix (× 기호 없이) — 사용자 선호 (2026-04-27).
    target = p.get("target", "self")
    t = resolve_target(target) if target else "이 카드"
    base = f"{t}에 변태({p['consume']}기 소모)"
    count = p.get("count", 1)
    if count > 1:
        return f"{base} {count}회"
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
    ## compress_repeated_target이 '그 카드'로 축약하는 상황을 방지 —
    ## 플레이어가 '그 카드'의 지시 대상을 혼동하지 않도록.
    t = resolve_target(p["target"])
    atk = fmt_pct(p["atk_per_unit"])
    per_n = p.get("per_n", 1)
    ec = int(p.get("enhanced_count", 1))
    enh_note = (f"(강화) 유닛은 {ec}기로 집계. " if ec > 1 else "")
    text = enh_note + (
        f"{t} 유닛 1기당 ATK +{atk}%"
        if per_n == 1 else
        f"{t} 유닛 {per_n}기당 ATK +{atk}%"
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
    return text + " (이번 전투)"

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
    ## 2026-04-21 해석 B (+ 계급 변환 glossary 이관):
    ##   count = "뽑기 횟수" (이전엔 "유닛 수"). 각 뽑기 = base pool uniform
    ##   1 선택 → 유닛별 count (3/2/2/1/1/1) 만큼 추가. 평균 1.67 기/뽑기.
    ##   rank_upgrade: YAML 선언 플래그 (runtime 이 source_card rank 로 R4/R10
    ##                 변환·엘리트 보너스 자동 적용). desc 에는 표시 안 함 —
    ##                 "징집" 키워드 glossary 에 R4/R10 효과가 통합 기술돼 있음.
    ##   forced_unit: pool 랜덤 대신 고정 유닛 징집 (ml_assault 용).
    ##                "무조건 바이커 2기" 같은 desc 로 표시.
    ##   enhanced_count: 앞 N 회 뽑기는 강화 변환 강제 (ml_outpost 용).
    ##   biker_rebirth: 바이커 뽑히면 즉시 추가 뽑기 연쇄 (구 ml_assault 용, 현재 미사용).
    t = resolve_target(p["target"])
    n = p["count"]
    forced: str = p.get("forced_unit", "")
    if forced:
        # 고정 유닛 경로: "N회 × M기" 대신 총 수량 직접 표기.
        unit_name = _unit_name(forced)
        return f"{t}에 {unit_name} {n}회 징집 (회당 2기)" if forced == "ml_biker" \
            else f"{t}에 {unit_name} 고정 징집 {n}회"
    text = f"{t}에 징집 {n}회"
    modifiers: list = []
    if p.get("biker_rebirth"):
        modifiers.append("바이커 뽑으면 재징집")
    eh = int(p.get("enhanced_count", 0))
    if "enhanced" in p and not eh:
        eh = 1 if p["enhanced"] == "partial" else (n if p["enhanced"] == "all" else 0)
    if eh > 0:
        if eh >= n:
            modifiers.append("전원 강화 변환" if n > 1 else "강화 변환")
        else:
            modifiers.append(f"앞 {eh}회 강화 변환")
    if modifiers:
        text += " (" + ", ".join(modifiers) + ")"
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

# desc_enhance_convert_card 제거 (2026-04-21):
# enhance_convert_card action 이 모든 r_conditional 에서 제거됨 (사용자 결정).
# "카드 내 기존 비(강화) 유닛 소급 변환" 효과는 폐기.
# 신규 유닛의 강화는 conscript rank_upgrade 플래그로 일원화.

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
    return f"이 카드 치명타 {chance}% (×{mult} 피해)"

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
    return f"{t} 라이프스틸 {pct}%"

def desc_high_rank_mult(p: dict) -> str:
    rank = p["rank"]
    mult = p["atk_mult"]
    return f"계급 {rank}+ 시 ATK ×{mult}"

def desc_grant_gold(p: dict) -> str:
    amount = p["amount"]
    if amount < 0:
        return f"골드 {amount}"  # 음수는 부호 그대로 (예: '골드 -1')
    return f"골드 +{amount}"

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

def desc_revive_scope_override(p: dict) -> str:
    t = resolve_target(p["target"])
    return f"부활 대상 확장 → {t}"


# ═══════════════════════════════════════════════════════════════════
# Phase 6a: 4 테마 카드 (Phase 1-3 신규 13장 중 테마부)
# ═══════════════════════════════════════════════════════════════════


def desc_mirror_l2(p: dict) -> str:
    """pr_parasitic_swarm — OE_PREFIX (None, ANY) prefix 가 키워드 나열 prefix
    (data/keywords.yaml 기반) 를 붙이므로 본문만 작성.
    ATK/HP 분리 표기 (' / ') — 사용자 요청 일관성 (failures/011 multi-review C2 fix)."""
    atk = p.get("atk_pct", 0.0)
    hp = p.get("hp_pct", 0.0)
    spawn = p.get("spawn_unit", 0)
    div = p.get("l2_diversity_bonus", 0.0)
    parts = []
    if atk:
        parts.append(f"ATK +{fmt_pct(atk)}%")
    if hp:
        parts.append(f"HP +{fmt_pct(hp)}%")
    base = f"이 카드 {' / '.join(parts)} 영구 강화"
    if spawn:
        base += f" + 유닛 {spawn}기 추가"
    if div:
        base += f" (새 l2 종류 첫 발견마다 추가 ATK +{fmt_pct(div)}%)"
    return base


def desc_gear_diversity_enhance(p: dict) -> str:
    """sp_global_workshop — 필드에 비-스팀펑크 카드 1장+ 시 #기어 강화.
    'non_steampunk_card' 필터 표기는 keywords.yaml glossary lookup."""
    min_n = p.get("min_non_steampunk", 1)
    atk = p.get("atk_pct", 0.0)
    hp = p.get("hp_pct", 0.0)
    spawn_n = p.get("spawn_unit", 0)
    spawn_thresh = p.get("spawn_threshold", 0)
    parts = []
    if atk:
        parts.append(f"ATK +{fmt_pct(atk)}%")
    if hp:
        parts.append(f"HP +{fmt_pct(hp)}%")
    flt_text = _kw_filter("non_steampunk_card")
    base = f"필드에 {flt_text} {min_n}장+ 시 #기어 유닛 {' / '.join(parts)} 영구 강화"
    if spawn_n and spawn_thresh:
        base += f" ({flt_text} {spawn_thresh}장+ 시 #기어 유닛 {spawn_n}기 추가)"
    return base


def desc_theme_count_conscript(p: dict) -> str:
    """ml_alliance RS — 필드 테마 수 × mult 만큼 이 카드에 징집 (glossary CO)."""
    mult = p.get("mult", 1)
    co = _kw("layer2", "CO")
    if mult == 1:
        return f"필드 테마 수만큼 이 카드에 {co}"
    return f"필드 테마 수 × {mult}만큼 이 카드에 {co}"


def desc_theme_count_spawn(p: dict) -> str:
    """ml_alliance BS — 필드 테마 수 × mult 만큼 랜덤 아군에 spawn,
    instant_conscript_threshold 시 즉시 징집.
    block timing prefix ('전투 시작:')는 상위 desc_gen에서 추가 — 여기선 본문만."""
    mult = p.get("mult", 1)
    thresh = p.get("instant_conscript_threshold", 0)
    if mult == 1:
        base = "필드 테마 수만큼 랜덤 아군 유닛 추가"
    else:
        base = f"필드 테마 수 × {mult}만큼 랜덤 아군 유닛 추가"
    if thresh:
        co = _kw("layer2", "CO")
        base += f" (테마 {thresh}+ 시 이 카드에 즉시 {co})"
    return base


def desc_mirror_spawn_to_tree(p: dict) -> str:
    """dr_resonance — OE_PREFIX (UA) prefix 가 '[반응] 유닛 추가 시:'를
    이미 붙이므로 필터(non_druid_target glossary lookup)와 본문만 작성."""
    tree = p.get("tree_add", 1)
    atk = p.get("self_atk_pct", 0.0)
    hp = p.get("self_hp_pct", 0.0)
    parts = []
    if atk:
        parts.append(f"ATK +{fmt_pct(atk)}%")
    if hp:
        parts.append(f"HP +{fmt_pct(hp)}%")
    self_part = f", 이 카드 {' / '.join(parts)} 영구 강화" if parts else ""
    return f"{_kw_filter('non_druid_target')} 🌳 +{tree}{self_part}"


# ═══════════════════════════════════════════════════════════════════
# Phase 6b: 9 중립 카드 (Phase 1-3 신규)
# ═══════════════════════════════════════════════════════════════════


def desc_mirror_l1(p: dict) -> str:
    """ne_nexus — listen l1: EN/UA, filter (target_filters glossary).
    기본 filter = cross_theme: 발동 카드 테마 ≠ 대상 카드 테마.
    OE_PREFIX (UA, None) / (EN, None) 가 '[반응] 유닛 추가 시:' / '강화 발동 시:' 붙임."""
    atk = p.get("atk_pct", 0.0)
    hp = p.get("hp_pct", 0.0)
    spawn = p.get("spawn_unit", 0)
    flt = p.get("filter", "cross_theme")
    parts = []
    if atk:
        parts.append(f"ATK +{fmt_pct(atk)}%")
    if hp:
        parts.append(f"HP +{fmt_pct(hp)}%")
    base = f"{_kw_filter(flt)} 이 카드 {' / '.join(parts)} 영구 강화"
    if spawn:
        base += f" + 유닛 {spawn}기 추가"
    return base


def desc_levelup_discount(p: dict) -> str:
    """ne_pawnbroker REROLL — 리롤 시 chance 확률로 상점 업그레이드 가격 -amount."""
    chance = p.get("chance", 1.0)
    amount = p.get("amount", 1)
    if chance >= 1.0:
        return f"상점 업그레이드 가격 -{amount}"
    return f"{fmt_pct(chance)}% 확률로 상점 업그레이드 가격 -{amount}"


def desc_tenure_gold(p: dict) -> str:
    """ne_hoarder 구버전(2026-04-29 폐기) — 체류 라운드 × per_tenure 골드."""
    per = p.get("gold_per_tenure", 0)
    chance = p.get("upgrade_chance", 0.0)
    base = f"체류 라운드 × {per}골드 획득"
    if chance:
        base += f" + {fmt_pct(chance)}% 확률 업그레이드 1장"
    return base


def desc_hoarder_transfer(p: dict) -> str:
    """ne_hoarder SELL — 카드 1장 선택 → 자기 stack 전부 이전 +
    체류 R 비례 영구 강화 (★3 unit_cap +1 추가)."""
    atk_per = p.get("atk_per_tenure", 0.0)
    hp_per = p.get("hp_per_tenure", 0.0)
    cap_bonus = p.get("bonus_unit_cap", 0)
    parts = ["카드 1장 선택 → 이 카드의 모든 유닛 stack 이전"]
    enhance_terms = []
    if atk_per:
        enhance_terms.append(f"ATK +{fmt_pct(atk_per)}%")
    if hp_per:
        enhance_terms.append(f"HP +{fmt_pct(hp_per)}%")
    if enhance_terms:
        parts.append(f"체류 R마다 {' / '.join(enhance_terms)} 영구 강화")
    if cap_bonus:
        parts.append(f"유닛 상한 +{cap_bonus}")
    return ". ".join(parts)


def desc_duplicate_buff_aura(p: dict) -> str:
    """ne_legion PERSISTENT — 필드 중복 카드(같은 template_id 2장+)들에
    ATK/HP buff. N_excl=중복 카드 수-1."""
    atk = p.get("atk_pct_per_n", 0.0)
    hp = p.get("hp_pct_per_n", 0.0)
    spawn = p.get("spawn_per_card", 0)
    parts = []
    if atk:
        parts.append(f"ATK +{fmt_pct(atk)}%")
    if hp:
        parts.append(f"HP +{fmt_pct(hp)}%")
    base = f"필드 중복 카드들 각각 다른 사본 1장당 {' / '.join(parts)}"
    if spawn:
        base += f" + 유닛 {spawn}기 추가"
    return base


def desc_transform_theme(p: dict) -> str:
    """ne_masquerade SELL — 필드 카드 1장 theme 변경. ★3: omni-theme."""
    omni = p.get("omni", False)
    if omni:
        return "필드 카드 1장을 모든 5테마 동시 매치 (omni) 상태로 영구 변환"
    offer = p.get("offer_count", 3)
    return f"필드 카드 1장 선택 → {offer}개 theme 중 1개로 영구 변환"


def desc_empty_slot_scaling(p: dict) -> str:
    """ne_void_force BS — 필드 빈칸 E 만큼 self ATK/HP/AS scaling."""
    atk = p.get("atk_pct_per_e", 0.0)
    hp = p.get("hp_pct_per_e", 0.0)
    as_div = p.get("as_div_per_e", 0.0)
    parts = []
    if atk:
        parts.append(f"ATK +{fmt_pct(atk)}%")
    if hp:
        parts.append(f"HP +{fmt_pct(hp)}%")
    base = f"필드 빈칸 1개당 이 카드 {' / '.join(parts)}"
    if as_div:
        base += f" + AS 가속 (빈칸 1개당 ÷(1+{fmt_pct(as_div)}%))"
    return base + " (이번 전투)"


def desc_star_aura(p: dict) -> str:
    """ne_fusion_end PERSISTENT — 필드의 각 ★≥min_star 아군에게 ATK/HP buff.
    PERSISTENT timing prefix ('[지속]')는 상위 desc_gen 에서 추가."""
    min_star = p.get("min_star", 2)
    atk = p.get("atk_pct", 0.0)
    hp = p.get("hp_pct", 0.0)
    include_self = p.get("include_self", True)
    parts = []
    if atk:
        parts.append(f"ATK +{fmt_pct(atk)}%")
    if hp:
        parts.append(f"HP +{fmt_pct(hp)}%")
    star_label = "★" * min_star + "+ " if min_star > 1 else ""
    self_label = "" if include_self else " (이 카드 제외)"
    return (f"필드의 각 {star_label}아군 카드{self_label} "
            f"{' / '.join(parts)} (이번 전투)")


def desc_transfer_upgrade(p: dict) -> str:
    """ne_clone_seed ★3 SELL — 이 카드의 업그레이드 1개를 필드 카드로 이전."""
    count = p.get("count", 1)
    return f"이 카드의 업그레이드 {count}개를 필드 카드 1장에 이전"


def desc_all_themes_field_bonus(p: dict) -> str:
    """ne_council PERSISTENT — 5테마 모두 존재 시 field_slots+1 + 아군 buff."""
    slot = p.get("slot_bonus", 0)
    a_atk = p.get("allies_atk_pct", 0.0)
    a_hp = p.get("allies_hp_pct", 0.0)
    parts = []
    if slot:
        parts.append(f"필드 슬롯 +{slot}")
    if a_atk:
        parts.append(f"모든 아군 ATK +{fmt_pct(a_atk)}%")
    if a_hp:
        parts.append(f"모든 아군 HP +{fmt_pct(a_hp)}%")
    return "필드에 5테마 모두 존재 시 " + " + ".join(parts)

def desc_awakening_sell(p: dict) -> str:
    """ne_awakening SELL: 카드 1장 선택 → (★별) 유닛 + 무작위 N등급 업글 1개 이전."""
    rarity_kr = {"common": "커먼", "rare": "레어", "epic": "에픽"}
    rarity = rarity_kr.get(p.get("rarity", "common"), "커먼")
    transfer_units = p.get("transfer_units", False)
    if transfer_units:
        return (f"보드 카드 1장 선택 → 이 카드의 유닛 + 부착된 "
                f"무작위 {rarity} 업그레이드 1개 이전")
    return (f"보드 카드 1장 선택 → 부착된 "
            f"무작위 {rarity} 업그레이드 1개 이전")


def desc_council_epic_grant(p: dict) -> str:
    """ne_council ★2/★3: 5테마 활성 라운드마다 +1, 임계 도달 시 차감 + 에픽 부여 (반복)."""
    return (f"5테마 활성 라운드마다 카운터 +1. "
            f"카운터 {p['threshold']}+ 도달 시 카운터 -{p['threshold']}, "
            f"카드 1장에 에픽 업그레이드 3택1 (반복 가능)")



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

def _normalize_per_unit_ratio(per: float, counter: str) -> str:
    """`gold/unit` 분수 비율을 정수 비율 한글 표기로 변환.

    counter: '기' (유닛 단위) | '장' (카드 단위).
    예: 0.2,'기' → '5기당 1골드', 0.5,'장' → '2장당 1골드',
        1.0,'기' → '1기당 1골드', 2.0,'장' → '1장당 2골드'.
    정수 비율이 아니면 fallback "× per골드".
    """
    if per > 0 and per <= 1:
        inv = 1.0 / per
        if abs(inv - round(inv)) < 1e-6:
            n = int(round(inv))
            return f"{n}{counter}당 1골드"
    if per >= 1 and abs(per - round(per)) < 1e-6:
        return f"1{counter}당 {int(round(per))}골드"
    return f"× {per}골드"


def desc_economy(p: dict) -> str:
    base = p.get("gold_base", 0)
    per = p.get("gold_per", 0)
    unit = p.get("gold_per_unit", "units")
    if unit == "units":
        prefix, counter = "유닛", "기"
    else:
        prefix, counter = "군대 카드", "장"
    halve = p.get("halve_on_loss", False)
    max_g = p.get("max_gold")
    ratio = _normalize_per_unit_ratio(per, counter)
    if ratio.startswith("×"):
        body = f"{prefix} 수 {ratio}"
    else:
        body = f"{prefix} {ratio}"
    if base:
        text = f"{base}골드 + {body}"
    else:
        text = body
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
    "tree_combat_bonus": desc_tree_combat_bonus,
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
    "total_counter":    desc_total_counter,
    "upgrade_discount": desc_upgrade_discount,
    "manufacture":      desc_manufacture,
    "range_bonus":      desc_range_bonus,
    "economy":          desc_economy,
    "battle_buff":      desc_battle_buff,
    # Military R4/R10 재설계 (trace 012)
    "spawn_unit":              desc_spawn_unit,
    "spawn_enhanced_random":   desc_spawn_enhanced_random,
    "enhance_convert_target":  desc_enhance_convert_target,
    "crit_buff":               desc_crit_buff,
    "crit_splash":             desc_crit_splash,
    "rank_buff_hp":            desc_rank_buff_hp,
    "lifesteal":               desc_lifesteal,
    "high_rank_mult":          desc_high_rank_mult,
    "grant_gold":              desc_grant_gold,
    "grant_terazin":           desc_grant_terazin,
    "upgrade_shop_bonus":      desc_upgrade_shop_bonus,
    "revive_scope_override":   desc_revive_scope_override,
    # ml_factory PC 재설계 (2026-04-21)
    "rank_scaled_enhance":     desc_rank_scaled_enhance,
    # Steampunk-specific: hatch_enhance, battle_buff already covered
    # Phase 6a: 4 테마 카드 (Phase 1-3 신규)
    "mirror_l2":                desc_mirror_l2,
    "gear_diversity_enhance":   desc_gear_diversity_enhance,
    "theme_count_conscript":    desc_theme_count_conscript,
    "theme_count_spawn":        desc_theme_count_spawn,
    "mirror_spawn_to_tree":     desc_mirror_spawn_to_tree,
    # Phase 6b: 9 중립 카드 (Phase 1-3 신규)
    "mirror_l1":                desc_mirror_l1,
    "levelup_discount":         desc_levelup_discount,
    "tenure_gold":              desc_tenure_gold,
    "hoarder_transfer":         desc_hoarder_transfer,
    "duplicate_buff_aura":      desc_duplicate_buff_aura,
    "transform_theme":          desc_transform_theme,
    "empty_slot_scaling":       desc_empty_slot_scaling,
    "star_aura":                desc_star_aura,
    "all_themes_field_bonus":   desc_all_themes_field_bonus,
    "council_epic_grant":       desc_council_epic_grant,
    "awakening_sell":           desc_awakening_sell,
    "transfer_upgrade":         desc_transfer_upgrade,
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

def get_oe_prefix(card: dict, listen_override: dict | None = None) -> str:
    """OE 섹션의 prefix 생성. listen_override 가 있으면 우선 사용
    (Phase 6 fix: same-timing multi-block per-section prefix).

    [반응] 출처 한정자 (어디서든 / 다른 카드의):
      require_other: true  → '다른 카드의'
      require_other: false → '어디서든'   (이 카드 자신 이벤트 포함)

    키워드 글로서리(keywords.yaml) 기반 — desc_gen 내부 하드코딩 금지.
    """
    listen = listen_override if listen_override else card.get("listen", {})
    l1, l2 = listen.get("l1"), listen.get("l2")
    key = (l1, l2)
    other_only = bool(card.get("require_other"))

    # ANY wildcard (pr_parasitic_swarm intertheme listener):
    # 모든 layer2 키워드를 명시적으로 나열.
    if l2 == "ANY":
        g = _load_keywords()
        kws = " / ".join(v["name"] for v in g["layer2"].values())
        src = g["reaction_origin"]["other_only" if other_only else "any"]
        return f"[반응] {src} 키워드({kws}) 발동 시:"

    # 비-glossary 트리거 (MERGE/REROLL/SELL): 자기 자신 이벤트 개념 없음.
    if key in NON_GLOSSARY_OE_PREFIX:
        base = NON_GLOSSARY_OE_PREFIX[key]
        if other_only:
            base = base.replace("[반응] ", "[반응] 다른 카드의 ", 1)
        return base

    # Glossary 기반 동적 prefix.
    return _kw_reaction(l1, l2, other_only=other_only)

def get_prefix(card: dict, timing: str, listen_override: dict | None = None) -> str:
    if timing == "OE":
        return get_oe_prefix(card, listen_override)
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
    "counter_produce", "total_counter",
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
    g = _load_keywords()
    layer2 = g.get("layer2", {})
    event_name = layer2[l2]["name"] if l2 in layer2 else "발동"
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
    →  '필드 위 모든 카드에 2기 유닛, 그 카드 ATK +10% 영구 강화, 그 카드
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
            # Replace the repeated prefix with "그 카드" and use comma join.
            # suffix preserves leading space (or particle attached directly,
            # e.g. '에 방어막') so '그 카드' bonds correctly without extra gap.
            suffix = seg[len(matched):]
            out[-1] = out[-1] + ", 그 카드" + suffix
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
        eff_listen_override = None
        if isinstance(params, dict):
            eff_timing = params.get("timing_override")
            eff_listen_override = params.get("listen_override")
        # ACTION_TIMING_OVERRIDE (economy, battle_buff etc.)
        if not eff_timing:
            eff_timing = ACTION_TIMING_OVERRIDE.get(action)
        # Default: card timing
        if not eff_timing:
            eff_timing = base_timing
        # Section key: (timing, listen_override) — 같은 timing 이지만 다른 listen
        # 의 multi-block (예: ne_nexus EN+UA) 분리. listen_override 없으면 None
        # 으로 fallback (단일 그룹).
        listen_key = None
        if eff_listen_override:
            listen_key = (eff_listen_override.get("l1"),
                          eff_listen_override.get("l2"))
        section_key = (eff_timing, listen_key)
        timing_groups.setdefault(section_key, []).append(desc_effect(eff))

    # 3. Conditionals → base timing group (listen=None → primary section)
    for cond in star_data.get("conditional", []):
        timing_groups.setdefault((base_timing, None), []).append(
            desc_conditional(cond))

    # 4. post_threshold → base timing group
    if star_data.get("post_threshold"):
        timing_groups.setdefault((base_timing, None), []).append(
            desc_post_threshold(star_data["post_threshold"]))

    # 4.5. r_conditional → base timing group (P2-1 newline 보존)
    for rcond in star_data.get("r_conditional") or []:
        timing_groups.setdefault((base_timing, None), []).append(
            "\n" + desc_r_conditional(rcond))

    # 5. Tenure prefix
    tenure_pfx = prefix_tenure(card, star_data)

    # 5.5. Counter auto-prefix (P1-2): counter 계열 action이 있으면
    # 'X 1회당 카운터 +1'을 base 본문 앞에 삽입해 축적 전제 노출.
    counter_pfx = counter_prefix_for(card, star_data)

    # 6. Assemble per-section texts — section_key = (timing, listen_override).
    # 각 (timing, listen) 조합마다 자신의 prefix + max_act suffix.
    # Phase 6 fix: same-timing multi-block (예: ne_nexus EN+UA) 별도 섹션 분리.
    max_act_map: dict = star_data.get("max_act_by_timing", {})
    max_act_by_section: dict = star_data.get("max_act_by_section", {})
    parts = []
    base_section = (base_timing, None)
    # Primary 섹션 먼저, 그 외 순서대로
    ordered_keys = ([base_section]
            + [k for k in timing_groups if k != base_section])
    card_listen = card.get("listen", {}) or {}
    for section_key in ordered_keys:
        if section_key not in timing_groups:
            continue
        timing, listen_key = section_key
        listen_override = None
        if listen_key is not None:
            listen_override = {"l1": listen_key[0], "l2": listen_key[1]}
        # Prefix
        if timing == base_timing and listen_override is None:
            pfx = get_prefix(card, base_timing)
            if tenure_pfx:
                pfx = f"{tenure_pfx} {pfx}"
        else:
            pfx = get_prefix(card, timing, listen_override)
        body = ". ".join(timing_groups[section_key])
        body = body.replace(". \n", "\n")
        body = compress_repeated_target(body)
        if section_key == base_section and counter_pfx:
            body = f"{counter_pfx} {body}"
        # max_act 우선순위:
        #   1) max_act_by_section[(timing, l1, l2)] — 정확한 섹션
        #   2) max_act_by_timing[timing] — same-timing 단일 listen
        #   3) star_data.max_act — legacy fallback
        section_full = (timing,
                listen_key[0] if listen_key else card_listen.get("l1"),
                listen_key[1] if listen_key else card_listen.get("l2"))
        if section_full in max_act_by_section:
            block_suffix = desc_max_act_suffix(
                    max_act_by_section[section_full], timing)
        elif timing in max_act_map:
            block_suffix = desc_max_act_suffix(max_act_map[timing], timing)
        elif section_key == base_section:
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
