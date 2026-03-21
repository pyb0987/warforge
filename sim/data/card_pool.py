"""Card pool: steampunk 9 + neutral 6 (증기 이자기 excluded)."""

from __future__ import annotations

from engine.types import (
    CardTemplate, TriggerSpec, EffectSpec,
    TriggerTiming, Layer1, Layer2,
)

CARD_TEMPLATES: dict[str, CardTemplate] = {}


def _ct(id_: str, name: str, tier: int, theme: str,
        comp: tuple[tuple[str, int], ...],
        trigger: TriggerSpec,
        effects: tuple[EffectSpec, ...],
        max_act: int | None = None,
        tags: frozenset[str] = frozenset()) -> CardTemplate:
    return CardTemplate(id_, name, tier, theme, comp, trigger, effects, max_act, tags)


# ── Helpers ──────────────────────────────────────────────────────

_SPAWN = lambda target, count=1, l2=Layer2.MANUFACTURE: EffectSpec(
    action="spawn", target=target, spawn_count=count,
    output_layer1=Layer1.UNIT_ADDED, output_layer2=l2,
)
_SPAWN_NEUTRAL = lambda target, count=1: EffectSpec(
    action="spawn", target=target, spawn_count=count,
    output_layer1=Layer1.UNIT_ADDED, output_layer2=None,
)
_ENHANCE = lambda target, tag, atk_pct, hp_pct=0.0: EffectSpec(
    action="enhance_pct", target=target,
    enhance_atk_pct=atk_pct, enhance_hp_pct=hp_pct,
    unit_tag_filter=tag,
    output_layer1=Layer1.ENHANCED, output_layer2=Layer2.UPGRADE,
)
_ON_EVENT = lambda l1=None, l2=None, other=False: TriggerSpec(
    timing=TriggerTiming.ON_EVENT,
    listen_layer1=l1, listen_layer2=l2,
    require_other_card=other,
)


_CARDS = [
    # ── Steampunk (8 active, 증기 이자기 제외) ───────────────────

    # 1. 증기 조립소 — chain starter (제조)
    _ct("sp_assembly", "증기 조립소", 1, "steampunk",
        comp=(("sp_spider", 2), ("sp_rat", 1)),
        trigger=TriggerSpec(timing=TriggerTiming.ROUND_START),
        effects=(_SPAWN("right_adj"),),
        tags=frozenset({"스팀펑크", "생산"})),

    # 2. 태엽 공방 — 제조→개량 bridge
    _ct("sp_workshop", "태엽 공방", 1, "steampunk",
        comp=(("sp_spider", 2), ("sp_sawblade", 1)),
        trigger=_ON_EVENT(l2=Layer2.MANUFACTURE),
        effects=(_ENHANCE("event_target", "태엽", 0.05),),
        max_act=2,
        tags=frozenset({"스팀펑크", "강화"})),

    # 3. 증기 대장간 — 개량 증폭
    _ct("sp_forge", "증기 대장간", 2, "steampunk",
        comp=(("sp_crab", 1), ("sp_sawblade", 1)),
        trigger=_ON_EVENT(l2=Layer2.UPGRADE),
        effects=(_ENHANCE("event_target", "기갑", 0.05),),
        max_act=2,
        tags=frozenset({"스팀펑크", "강화"})),

    # 4. 조립 라인 — 제조 증폭 (다른 카드 제조 시)
    _ct("sp_line", "조립 라인", 3, "steampunk",
        comp=(("sp_sawblade", 2), ("sp_spider", 1)),
        trigger=_ON_EVENT(l2=Layer2.MANUFACTURE, other=True),
        effects=(_SPAWN("self"), _SPAWN("right_adj")),
        max_act=3,
        tags=frozenset({"스팀펑크", "생산"})),

    # 5. 시한 보일러 — 3R 체류 인내 보상 (개량)
    _ct("sp_boiler", "시한 보일러", 3, "steampunk",
        comp=(("sp_scorpion", 1), ("sp_rat", 2)),
        trigger=TriggerSpec(timing=TriggerTiming.ROUND_START, require_tenure=3),
        effects=(_ENHANCE("self", "증기", 0.08, 0.08),),
        tags=frozenset({"스팀펑크", "시간"})),

    # 6. 전쟁 기계 — 전투 중 버프 (pre-combat in sim)
    _ct("sp_warmachine", "전쟁 기계", 4, "steampunk",
        comp=(("sp_turret", 1), ("sp_cannon", 1), ("sp_drone", 1)),
        trigger=TriggerSpec(timing=TriggerTiming.ON_COMBAT_ATTACK),
        effects=(EffectSpec(
            action="buff_pct", target="self",
            buff_atk_pct=0.15, unit_tag_filter="화기"),),
        tags=frozenset({"스팀펑크", "전투"})),

    # 7. 과부하 코일 — 비전투원, 인접 추가 발동
    _ct("sp_overload", "과부하 코일", 4, "steampunk",
        comp=(("sp_drone", 2),),
        trigger=TriggerSpec(
            timing=TriggerTiming.ROUND_START, is_non_combatant=True),
        effects=(EffectSpec(action="retrigger", target="right_adj"),),
        tags=frozenset({"스팀펑크", "과부하"})),

    # 8. 제국 공장 — capstone, 전체 제조
    _ct("sp_factory", "제국 공장", 5, "steampunk",
        comp=(("sp_titan", 1), ("sp_scorpion", 1), ("sp_crab", 1)),
        trigger=TriggerSpec(timing=TriggerTiming.ROUND_START),
        effects=(_SPAWN("all_allies"),),
        tags=frozenset({"스팀펑크", "생산"})),

    # ── Neutral (6) ──────────────────────────────────────────────

    # 9. 떠돌이 무리 — Layer1 유닛추가 반응
    _ct("ne_wanderers", "떠돌이 무리", 1, "neutral",
        comp=(("ne_merc", 1), ("ne_scrap", 2)),
        trigger=_ON_EVENT(l1=Layer1.UNIT_ADDED, other=True),
        effects=(_SPAWN_NEUTRAL("self"),),
        max_act=2,
        tags=frozenset({"중립", "범용"})),

    # 10. 방랑 상인 — 패배 시 골드
    _ct("ne_merchant", "방랑 상인", 1, "neutral",
        comp=(("ne_archer", 1), ("ne_scrap", 1)),
        trigger=TriggerSpec(timing=TriggerTiming.POST_COMBAT_DEFEAT),
        effects=(EffectSpec(action="grant_gold", target="self", gold_amount=2),),
        max_act=1,
        tags=frozenset({"중립", "경제"})),

    # 11. 야생의 힘 — 전투 시작 버프
    _ct("ne_wildforce", "야생의 힘", 2, "neutral",
        comp=(("ne_beast", 1), ("ne_chimera", 1)),
        trigger=TriggerSpec(timing=TriggerTiming.BATTLE_START),
        effects=(EffectSpec(
            action="buff_pct", target="self", buff_atk_pct=0.10),),
        tags=frozenset({"중립", "전투"})),

    # 12. 고대의 잔해 — 2R 체류 보상 (골드 + 유닛)
    _ct("ne_ruins", "고대의 잔해", 2, "neutral",
        comp=(("ne_golem", 1), ("ne_spirit", 1)),
        trigger=TriggerSpec(timing=TriggerTiming.ROUND_START, require_tenure=2),
        effects=(
            EffectSpec(action="grant_gold", target="self", gold_amount=2),
            _SPAWN_NEUTRAL("right_adj"),
        ),
        tags=frozenset({"중립", "시간"})),

    # 13. 키메라의 울부짖음 — 패배 시 유닛 추가
    _ct("ne_chimera_cry", "키메라의 울부짖음", 3, "neutral",
        comp=(("ne_chimera", 1), ("ne_mutant", 1)),
        trigger=TriggerSpec(timing=TriggerTiming.POST_COMBAT_DEFEAT),
        effects=(_SPAWN_NEUTRAL("self", 2),),
        max_act=1,
        tags=frozenset({"중립", "역전"})),

    # 14. 고대의 각성 — 5R 체류 임계점 대보상
    _ct("ne_awakening", "고대의 각성", 4, "neutral",
        comp=(("ne_sentinel", 1), ("ne_golem", 1)),
        trigger=TriggerSpec(
            timing=TriggerTiming.ROUND_START,
            require_tenure=5, is_threshold=True),
        effects=(
            _SPAWN_NEUTRAL("all_allies"),
            EffectSpec(action="shield_pct", target="all_allies",
                       shield_hp_pct=0.20),
        ),
        tags=frozenset({"중립", "고대"})),
]


def register_all() -> None:
    for c in _CARDS:
        CARD_TEMPLATES[c.id] = c


def get_template(card_id: str) -> CardTemplate:
    return CARD_TEMPLATES[card_id]
