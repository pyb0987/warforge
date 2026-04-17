# 카드 효과 텍스트 코드젠 설계

## 목적

`data/cards/*.yaml`의 Effect DSL에서 한국어 효과 설명 텍스트를 자동 생성하여,
`card_descs.gd`를 코드젠 출력물로 만든다.

### 배경
- 현재 `card_descs.gd`는 55장 × 3★ = 165개 텍스트를 수동 관리
- YAML에서 수치를 바꿔도 `card_descs.gd`는 갱신되지 않음 → 이중 소스 재발
- 해결: YAML이 유일한 진실 소스 → 텍스트도 YAML에서 생성

### 구조

```
data/cards/*.yaml          ← 단일 소스
         ↓ codegen_card_db.py
godot/core/data/card_db.gd       ← 기계적 데이터 (기존)
godot/core/data/card_descs.gd    ← 효과 텍스트 (신규 생성 대상)
```

`scripts/card_desc_gen.py`에 텍스트 생성 로직을 분리하고,
`codegen_card_db.py`에서 import하여 한 번의 실행으로 두 파일 모두 생성.

> **파일 분리 (800줄 제한)**: codegen_card_db.py(955줄) + desc(~400줄) = 1350줄 초과.
> `card_desc_gen.py`를 별도 모듈로 분리한다.

---

## 텍스트 생성 규칙

### 전체 구조

각 ★ 레벨의 텍스트는 독립적으로 생성한다 (상속 없음).

```
[접두사] [효과1]. [효과2]. ... [조건부] [접미사]
```

| 구성요소 | 소스 | 예시 |
|---------|------|------|
| 접두사 | timing + require_tenure + is_threshold | `"라운드 시작:"`, `"필드 2R+ 체류 시 라운드 시작:"` |
| 효과 | effects 배열 각 항목 | `"이 카드에 유닛 2기 제조"` |
| 조건부 | conditional 배열 | `"이 카드 8기 이상이면 추가 개량 +3%"` |
| 접미사 | max_act | `"(최대 3/R)"`, `"(발동 무제한)"` |

### 구분자

- 같은 타이밍의 효과: `. ` (마침표+공백) 또는 ` + ` — 짧으면 ` + `, 길면 `. `
- 다른 타이밍의 효과 (예: RS 효과 + BS battle_buff): 별도 문장으로 분리
- 조건부: `. ` 후 조건 텍스트

---

## 접두사 생성

### timing → 접두사

```python
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
```

### OE 카드: listen → 접두사

```python
OE_PREFIX = {
    # (l1, l2) → 접두사
    # l1만 있는 경우
    ("UA", None):  "[반응] 유닛 추가 시:",
    ("EN", None):  "[반응] 강화 발동 시:",
    # l1 + l2
    ("UA", "MF"):  "[반응] 제조 발동 시:",
    ("EN", "UP"):  "[반응] 개량 발동 시:",
    ("UA", "HA"):  "[반응] 부화 시:",
    ("EN", "MT"):  "[반응] 변태 시:",
    # l2만 있는 경우 (l1=None)
    (None, "TR"):  "[반응] 훈련 시:",
    (None, "CO"):  "[반응] 징집 시:",
    (None, "HA"):  "[반응] 부화 시:",     # pr_molt: l2만 HA
    (None, "MT"):  "[반응] 변태 시:",     # pr_harvest, pr_carapace, pr_apex_hunt: l2만 MT
    # 특수
    ("UA", "MERGE"): "★합성 시:",
    ("UA", "REROLL"): "리롤 시:",
    ("UA", "SELL"):   "[반응] 판매 시:",
}
```

**listen 키 해석**: `listen` dict에서 `l1`, `l2`를 각각 읽되, 없는 키는 `None`으로 처리.
```python
def get_oe_prefix(card):
    listen = card.get("listen", {})
    key = (listen.get("l1"), listen.get("l2"))
    return OE_PREFIX.get(key, f"[반응] {key}:")  # fallback: 키 표시
```

### require_tenure / is_threshold

```python
def prefix_tenure(card, star_data):
    tenure = star_data.get("require_tenure", card.get("require_tenure", 0))
    threshold = star_data.get("is_threshold", card.get("is_threshold", False))
    if tenure > 0:
        if threshold:
            return f"필드 {tenure}R+ 체류 시 1회:"
        return f"필드 {tenure}R+ 체류 시"
    return ""
```

### ★별 timing override

★3에서 timing이 변경되는 경우(예: ne_merchant ★3 PCD→PC):
- `star_data.get("timing")` 이 있으면 해당 접두사 사용

---

## 효과 텍스트 템플릿

### target → 한국어

```python
TARGET = {
    "self":           "이 카드",
    "right_adj":      "오른쪽 인접 카드",
    "left_adj":       "왼쪽 인접 카드",
    "both_adj":       "양쪽 인접 카드",
    "all_allies":     "필드 위 모든 카드",
    "all_druid":      "모든 드루이드 카드",
    "all_predator":   "모든 포식종 카드",
    "all_military":   "모든 군대 카드",
    "all_enemy":      "적 전체",
    "event_target":   "해당 카드",
    "event_source":   "발동 카드",
    "self_and_both_adj": "이 카드 + 양쪽 인접",
    "adj_druids":     "인접 드루이드 카드",
    "adj_or_self":    "인접 카드",
    "both_adj_or_self": "양쪽 인접 카드",
    "all_other_druid": "필드 위 모든 드루이드 카드",
    "enhanced_units":  "(강화) 유닛",          # ml_command revive 대상
    "all_steampunk":   "모든 스팀펑크 카드",
}

def resolve_target(target_str):
    """target 문자열 → 한국어. tag:* 패턴 지원."""
    if target_str in TARGET:
        return TARGET[target_str]
    # tag:queen, tag:carapace 등 동적 태그 참조
    if target_str.startswith("tag:"):
        tag = target_str[4:]
        return f"#{tag} 유닛"
    return target_str  # fallback: 원본 표시
```

### 공통 효과 (card_db 직접 구현)

#### spawn

```python
def desc_spawn(p):
    t = resolve_target(p["target"])
    n = p.get("count", 1)
    # ol2 테마 키워드
    ol2 = p.get("ol2")
    verb = {None: "유닛", "MF": "제조"}.get(ol2, "유닛")
    strongest = " 가장 강한 유닛(CP)" if p.get("strongest") else ""
    # ol1=null → 이벤트 미방출 (텍스트에 표기하지 않음 — 내부 동작)
    return f"{t}에{strongest} {n}기 {verb}"
```

예시:
- `spawn: {target: right_adj}` → `"오른쪽 인접 카드에 1기 유닛"`
- `spawn: {target: both_adj, count: 2, ol2: MF}` → `"양쪽 인접 카드에 2기씩 제조"`
- `spawn: {target: event_target, ol2: MF, strongest: true}` → `"해당 카드에 가장 강한 유닛(CP) 1기 제조"`

#### enhance

```python
def desc_enhance(p):
    t = resolve_target(p["target"])  # tag:queen 등 동적 태그 지원
    atk = fmt_pct(p.get("atk_pct", 0))
    hp = fmt_pct(p.get("hp_pct", 0))
    tag = p.get("tag", "")
    # ol1=null → 이벤트 미방출 (체인 비참여) → "성장" 표기
    # ol2 테마 키워드 → "개량" 표기
    ol1_null = p.get("ol1") is None and "ol1" in p
    ol2 = p.get("ol2")
    if ol1_null:
        verb = "성장"
    else:
        verb = {None: "영구 강화", "UP": "개량"}.get(ol2, "영구 강화")
    
    tag_text = f" #{tag} 유닛" if tag else ""
    
    # hp_pct만 있는 경우 (pr_queen ★3: hp_pct만, atk_pct 없음)
    if hp and not atk:
        return f"{t}{tag_text} HP +{hp}% {verb}"
    if hp:
        return f"{t}{tag_text} ATK+HP +{atk}% {verb}"
    return f"{t}{tag_text} ATK +{atk}% {verb}"
```

예시:
- `enhance: {target: self, atk_pct: 0.03}` → `"이 카드 ATK +3% 영구 강화"`
- `enhance: {target: event_target, atk_pct: 0.05, ol2: UP}` → `"해당 카드 ATK +5% 개량"`
- `enhance: {target: self, atk_pct: 0.05, ol1: null}` → `"이 카드 ATK +5% 성장"` (ol1=null → 이벤트 미방출 → "성장" 표기)

**ol1=null 특수 처리**: 이벤트를 방출하지 않는 강화는 "성장"으로 표기 (체인에 참여하지 않음을 암시).

#### buff

```python
def desc_buff(p):
    t = resolve_target(p["target"])
    tag = f" #{p['tag']}" if p.get("tag") else ""
    # atk_mult vs atk_pct 분기 (pr_apex_hunt ★3: atk_mult: 2.0)
    if p.get("atk_mult"):
        text = f"{t}{tag} 유닛 ATK ×{p['atk_mult']}(이번 전투)"
    else:
        atk = fmt_pct(p["atk_pct"])
        text = f"{t}{tag} 유닛 ATK +{atk}%(이번 전투)"
    if p.get("kill_hp_recover"):
        text += ". 적 처치 HP 회복"
    return text
```

#### gold / terazin

```python
def desc_gold(amount):
    return f"{amount}골드 획득"

def desc_terazin(amount):
    return f"{amount} 테라진 획득"
```

#### shield

```python
def desc_shield(p):
    t = resolve_target(p["target"])
    pct = fmt_pct(p["hp_pct"])
    return f"{t} 유닛에 방어막(기본HP {pct}%)"
```

#### scrap

```python
def desc_scrap(p):
    t = resolve_target(p["target"])
    n = p["count"]
    reroll = p["reroll_gain"]
    gold = p.get("gold_per_unit", 0)
    text = f"양쪽 인접 카드에서 최약 유닛 {n}기씩 제거. 무료 리롤 +{reroll}"
    if gold:
        text += f" + 제거 유닛당 {gold}골드"
    return text
```

#### diversity_gold

```python
def desc_diversity_gold(p):
    gpt = p.get("gold_per_theme", 1)
    text = f"필드 위 테마 수 × {gpt}골드 획득"
    if p.get("terazin_threshold"):
        text += f". {p['terazin_threshold']}종 이상이면 테마당 {p.get('terazin_per_theme', 1)} 테라진"
    if p.get("mercenary_spawn"):
        text += ". 용병 카드마다 유닛 +1"
    return text
```

#### absorb

```python
def desc_absorb(p):
    n = p["count"]
    text = f"판매된 카드의 가장 강한 유닛 {n}기 흡수"
    if p.get("transfer_upgrades"):
        text += " + 업그레이드 이전"
    if p.get("majority_atk_bonus"):
        pct = fmt_pct(p["majority_atk_bonus"])
        text += f" + 최다 유닛 ATK +{pct}%"
    return text
```

### 테마 DSL 효과

#### 드루이드

```python
def desc_tree_add(p):
    t = resolve_target(p["target"])
    return f"{t}에 🌳+{p['count']}"

def desc_tree_absorb(p):
    return f"인접에서 🌳{p['count']} 흡수"

def desc_tree_breed(p):
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

def desc_tree_shield(p):
    t = resolve_target(p["target"])
    base = fmt_pct(p["base_pct"])
    scale = fmt_pct(p["tree_scale_pct"])
    # timing_override: dr_earth ★3 — RS 카드지만 이 효과는 BS에 발동
    prefix = ""
    if p.get("timing_override"):
        override_text = TIMING_PREFIX.get(p["timing_override"], p["timing_override"])
        prefix = f"{override_text} "
    text = f"{prefix}{t}에 방어막({base}%+🌳×{scale}%)"
    low = p.get("low_unit")
    if low:
        text += f". ≤{low['thresh']}기 ×{low['mult']}"
    return text

def desc_tree_enhance(p):
    base = fmt_pct(p["base_pct"])
    text = f"이 카드 ATK+HP +(🌳×{base}%) 성장"
    low = p.get("low_unit")
    if low:
        low_pct = fmt_pct(low["pct"])
        text += f". ≤{low['thresh']}기 → 🌳×{low_pct}%"
    bonus = p.get("tree_bonus")
    if bonus:
        text += f". 🌳{bonus['thresh']} → ATK ×{1 + bonus['bonus_growth_pct']:.1f}"
    return text

def desc_tree_gold(p):
    base = p["base_gold"]
    div = p["tree_divisor"]
    text = f"{base}골드 + floor(🌳÷{div}) 골드"
    if p.get("win_half"):
        text += ". 패배 시 절반"
    else:
        text += ". 패배 전액"
    if p.get("terazin_thresh"):
        text += f". 🌳{p['terazin_thresh']}+ → +{p.get('terazin', 1)} 테라진"
    return text

def desc_tree_distribute(p):
    tiers = p["tiers"]
    parts = []
    for tier in tiers:
        parts.append(f"🌳{tier['tree_gte']}+ → 전체 드루이드 +{tier['amount']}")
    return ". ".join(parts)

def desc_druid_unit_enhance(p):
    div = p["divisor"]
    text = f"모든 드루이드 ATK+HP +(전체 유닛÷{div})% 성장"
    # bonus_tiers: dr_earth ★2/★3 — 유닛 수 임계점별 추가 보너스
    if p.get("bonus_tiers"):
        for bt in p["bonus_tiers"]:
            pct = fmt_pct(bt["bonus_pct"])
            text += f". {bt['unit_gte']}기+ → 추가 +{pct}%"
    return text

def desc_multiply_stats(p):
    cap = p["unit_cap"]
    atk_base = p["atk_base"]
    step = p["atk_tree_step"]
    per = p["atk_per_tree"]
    text = f"[지속] ≤{cap}기 → 이 카드 유닛 ATK×{atk_base}. 전체 나무 수 {step}당 +{per}×"
    # HP/AS 축약 (있으면 추가)
    if p.get("hp_base"):
        text += f", HP×{p['hp_base']}"
    if p.get("as_base") and p["as_base"] != 1.0:
        text += f", AS×{p['as_base']}"
    return text

def desc_tree_temp_buff(p):
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
        text += ". 적 처치 HP 15% 회복"
    return text

def desc_debuff_store(p):
    t = resolve_target(p.get("target", "all_enemy"))
    stat = p["stat"].upper()
    base = fmt_pct(p["base_pct"])
    cap = fmt_pct(p["cap"])
    # 드루이드: tree_scale_pct 있음 → 🌳 비례 스케일링
    # 포식종: tree_scale_pct 없음 → 고정 디버프
    if p.get("tree_scale_pct"):
        scale = fmt_pct(p["tree_scale_pct"])
        return f"{t} {stat} -({base}%+🌳×{scale}%) (상한 -{cap}%)"
    return f"{t} {stat} -{base}% (상한 -{cap}%)"

def desc_epic_shop_unlock(p):
    return f"🌳{p['tree_thresh']}+ → 매 라운드 에픽 업글 후보 1장 상점 추가"

def desc_free_reroll(amount):
    return f"무료 리롤 +{amount}"
```

#### 포식종

```python
def desc_hatch(p):
    t = resolve_target(p["target"])
    return f"{t}에 부화 {p['count']}기"

def desc_hatch_enhance(p):
    pct = fmt_pct(p["atk_pct"])
    return f"부화 유닛 ATK +{pct}% 성장"

def desc_meta_consume(p):
    n = p["consume"]
    return f"변태({n}기 소모)"

def desc_hatch_scaled(p):
    t = resolve_target(p["target"])
    per = p["per_units"]
    cap = p["cap"]
    return f"생존 유닛당 부화 {per}기(최대 {cap})"

def desc_on_combat_result(p):
    cond = p["condition"]
    cond_text = {"victory": "승리 시", "defeat": "패배 시", "always": "승패 무관"}.get(cond, "")
    effects_text = ". ".join(desc_effect(e) for e in p["effects"])
    return f"{cond_text} {effects_text}"

def desc_swarm_buff(p):  # 포식종 + 군대 공유
    t = resolve_target(p["target"])
    atk = fmt_pct(p["atk_per_unit"])
    per_n = p.get("per_n", 1)
    text = f"{t} 유닛 {per_n}기당 ATK +{atk}% 전투 버프"
    # 군대 확장 필드
    if p.get("ms_bonus"):
        ms = p["ms_bonus"]
        text += f". {ms['unit_thresh']}기+ → MS +{ms['bonus']}"
    if p.get("enhanced_count"):
        text += f". (강화) {p['enhanced_count']}기 카운트"
    if p.get("high_rank"):
        hr = p["high_rank"]
        if hr.get("as_bonus"):
            text += f". {hr['unit_thresh']}기+ → AS ×{1 - hr['as_bonus']:.2f}"
    return text

def desc_persistent(p):
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
```

#### 군대

```python
def desc_train(p):
    t = resolve_target(p["target"])
    n = p["amount"]
    return f"{t} 훈련(계급+{n})"

def desc_conscript(p):
    t = resolve_target(p["target"])
    n = p["count"]
    enhanced = p.get("enhanced")
    text = f"{t}에 징집 {n}기"
    if enhanced == "partial":
        text += "(1기 강화 버전)"
    elif enhanced == "all":
        text += "(전원 강화 버전)"
    return text

def desc_rank_threshold(p):
    tiers = p["tiers"]
    parts = []
    for tier in tiers:
        unit = tier.get("unit", "정예 유닛")
        n = tier.get("count", 1)
        bonus = f" ATK +{fmt_pct(tier['atk_bonus'])}%" if tier.get("atk_bonus") else ""
        parts.append(f"계급 {tier['rank']} → {unit} {n}기{bonus}")
    text = ". ".join(parts)
    if p.get("high_rank"):
        hr = p["high_rank"]
        # high_rank 구조는 카드마다 다름:
        #   ml_barracks ★3: {rank: 15, atk_mult: 1.3}  → 전체 ATK 곱연산
        #   ml_special_ops ★3: {rank: 10, leader_spread: both_adj} → 리더 버프 인접 확산
        if hr.get("atk_mult"):
            text += f". 계급 {hr['rank']} → 전체 ATK ×{hr['atk_mult']}"
        if hr.get("leader_spread"):
            spread = resolve_target(hr["leader_spread"])
            text += f". 계급 {hr['rank']} → 리더 버프 {spread} 확산"
    return text

def desc_rank_buff(p):
    shield = fmt_pct(p["shield_per_rank"])
    atk_unit = fmt_pct(p["atk_per_unit"])
    enhanced = fmt_pct(p["enhanced_shield_bonus"])
    text = f"모든 군대에 방어막(계급×{shield}%) + ATK +유닛수×{atk_unit}%. (강화) 추가 +{enhanced}%"
    if p.get("high_rank"):
        hr = p["high_rank"]
        text += f". 계급 {hr['rank_gte']}+ → AS ×{1 - hr['as_bonus']:.2f}"
    return text

def desc_revive(p):
    hp = fmt_pct(p["hp_pct"])
    limit = p["limit_per_combat"]
    text = f"(강화) 유닛 사망 시 HP {hp}% 부활({limit}/전투)"
    if p.get("shield_pct"):
        text += f" + 방어막 {fmt_pct(p['shield_pct'])}%"
    if p.get("on_revive_buff"):
        buff = p["on_revive_buff"]
        text += f" + ATK +{fmt_pct(buff['atk_pct'])}%(전투)"
    return text

def desc_revive_override(p):
    return "부활 대상 → 전체 군대(리더 포함)"

def desc_counter_produce(p):
    thresh = p["threshold"]
    rewards = p["rewards"]
    parts = []
    if rewards.get("terazin"):
        parts.append(f"{rewards['terazin']} 테라진")
    if rewards.get("enhance_atk_pct"):
        parts.append(f"개량 ATK +{fmt_pct(rewards['enhance_atk_pct'])}%")
    reward_text = " + ".join(parts)
    return f"카운터 {thresh}+ → {thresh} 소비, {reward_text}"

def desc_rare_counter(p):
    return f"카운터 {p['threshold']}+ → {p['threshold']} 소비, 레어 업그레이드 3택1"

def desc_epic_counter(p):
    return f"카운터 {p['threshold']}+ → {p['threshold']} 소비, 에픽 업그레이드"

def desc_total_counter(p):
    per = p["per_manufacture"]
    tz = p["reward_terazin"]
    return f"영구: 제조 {per}회마다 +{tz} 테라진"

def desc_upgrade_discount(p):
    tier = p["tier"]
    pct = int(p["pct"] * 100)
    return f"[지속] {tier} 업글 {pct}% 할인"

def desc_range_bonus(p):
    tag = p.get("tag", "firearm")
    thresh = p["unit_thresh"]
    text = f"#{tag} 유닛 {thresh}기당 사거리 +1"
    if p.get("atk_buff_pct"):
        text += f". #{tag} ATK +{fmt_pct(p['atk_buff_pct'])}%"
    if p.get("attack_stack_pct"):
        text += f". 공격 시마다 ATK +{fmt_pct(p['attack_stack_pct'])}%(전투)"
    return text

def desc_economy(p):
    base = p.get("gold_base", 0)
    per = p.get("gold_per", 0)
    unit = p.get("gold_per_unit", "units")  # "units" or "cards"
    unit_text = "유닛 수" if unit == "units" else "군대 카드 수"
    halve = p.get("halve_on_loss", False)
    max_g = p.get("max_gold")

    text = f"{base}골드 + {unit_text} × {per}골드"
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

def desc_battle_buff(p):
    atk = fmt_pct(p["atk_per_reroll"])
    cap = p["cap"]
    return f"전투: 리롤 횟수 × ATK +{atk}%(최대 {cap}회)"
```

---

## 조건부 효과 (conditional)

```python
CONDITION_TEXT = {
    "unit_count_gte": lambda v: f"이 카드 {v}기 이상이면",
    "unit_count_lte": lambda v: f"이 카드 ≤{v}기이면",
    "tenure_gte":     lambda v: f"{v}R+ 체류 시",
    "rank_gte":       lambda v: f"계급 {v}+ 이면",
}

def desc_conditional(cond):
    when = cond["when"]
    cond_type = next(iter(when))
    threshold = when[cond_type]
    cond_text = CONDITION_TEXT[cond_type](threshold)
    effects = [desc_effect(e) for e in cond["effects"]]
    return f"{cond_text} {' + '.join(effects)}"
```

---

## post_threshold 효과

is_threshold=true인 카드에서 임계점 초과 후 매 라운드 적용되는 효과.

```python
def desc_post_threshold(effects):
    parts = [desc_effect(e) for e in effects]
    return f"이후 매 라운드 {'. '.join(parts)}"
```

---

## 접미사: max_activations

```python
def desc_max_act_suffix(max_act):
    if max_act == -1:
        return ""  # 무제한은 접미사 없음 (RS/BS 카드 대부분)
    if max_act == 0:
        return " (발동 무제한)"  # 군수 공장 등 명시적 무제한
    return f" (최대 {max_act}/R)"
```

**OE 카드**: max_act 접미사 항상 표시 (반응형이므로 상한이 의미 있음).
**RS/BS 카드**: max_act == -1이면 접미사 없음 (라운드당 1회가 자명).

---

## 조합 함수

### 다중 타이밍 분리 (B1 해결)

일부 action은 카드 timing과 다른 고유 타이밍을 가진다:

```python
ACTION_TIMING_OVERRIDE = {
    # action_name → 고유 timing (카드 timing과 다르면 분리 출력)
    "economy":          "PC",
    "battle_buff":      "BS",
    "tree_temp_buff":   "BS",
    "on_combat_result": "PC",
    # tree_shield는 timing_override 필드로 개별 지정 (드루이드)
}
```

예시: pr_farm (timing=RS)
- `hatch: {target: self, count: 1}` → RS 그룹
- `economy: {gold_base: 0, ...}` → PC 그룹 (ACTION_TIMING_OVERRIDE)
- 출력: `"라운드 시작: 이 카드에 부화 1기. 전투 종료: 유닛 수 × 0.2골드(최대 3)..."`

### Unknown action fallback (C2 해결)

```python
def desc_effect(eff):
    """단일 효과 dict → 텍스트. 미정의 action은 경고 + 플레이스홀더."""
    action = next(iter(eff))
    params = eff[action]
    handler = EFFECT_HANDLERS.get(action)
    if handler is None:
        import sys
        print(f"WARNING: unknown action '{action}' — add handler", file=sys.stderr)
        return f"[TODO: {action}]"
    return handler(params)
```

### generate_star_desc

```python
def generate_star_desc(card, star_data):
    """하나의 ★ 레벨에 대한 완전한 설명 텍스트 생성."""
    
    # 1. timing (★별 override 가능)
    base_timing = star_data.get("timing", card["timing"])
    
    # 2. 효과를 타이밍별로 그룹핑
    timing_groups = {}  # timing → [effect_text]
    for eff in star_data.get("effects", []):
        action = next(iter(eff))
        params = eff[action]
        # timing_override 필드 (tree_shield 등)
        eff_timing = None
        if isinstance(params, dict):
            eff_timing = params.get("timing_override")
        # ACTION_TIMING_OVERRIDE (economy, battle_buff 등)
        if not eff_timing:
            eff_timing = ACTION_TIMING_OVERRIDE.get(action)
        # 기본: 카드 timing
        if not eff_timing:
            eff_timing = base_timing
        
        timing_groups.setdefault(eff_timing, []).append(desc_effect(eff))
    
    # 3. 조건부 효과 → 기본 타이밍 그룹에 추가
    for cond in star_data.get("conditional", []):
        timing_groups.setdefault(base_timing, []).append(desc_conditional(cond))
    
    # 4. post_threshold → 기본 타이밍 그룹에 추가
    if star_data.get("post_threshold"):
        timing_groups.setdefault(base_timing, []).append(
            desc_post_threshold(star_data["post_threshold"]))
    
    # 5. tenure 접두사
    tenure_prefix = prefix_tenure(card, star_data)
    
    # 6. 타이밍별 텍스트 조합
    parts = []
    # 기본 타이밍 먼저, 나머지 순서대로
    ordered = [base_timing] + [t for t in timing_groups if t != base_timing]
    for timing in ordered:
        if timing not in timing_groups:
            continue
        prefix = get_prefix(card, timing) if timing == base_timing else TIMING_PREFIX.get(timing, timing)
        if tenure_prefix and timing == base_timing:
            prefix = f"{tenure_prefix} {prefix}"
        body = ". ".join(timing_groups[timing])
        parts.append(f"{prefix} {body}")
    
    # 7. max_act 접미사 (전체 텍스트 끝에)
    suffix = desc_max_act_suffix(star_data["max_act"])
    
    return ". ".join(parts) + suffix
```

---

## 출력 포맷

생성되는 `card_descs.gd`:

```gdscript
# AUTO-GENERATED from data/cards/*.yaml — DO NOT EDIT
# Run: python3 scripts/codegen_card_db.py
extends Node
## 카드 효과 한 줄 설명. 툴팁에서 ★별 독립적 설명 제공.

var _descs := {
    "ne_earth_echo": {
        1: "라운드 시작: 오른쪽 인접 카드에 1기 유닛",
        2: "라운드 시작: 오른쪽 인접 카드에 2기 유닛",
        3: "라운드 시작: 양쪽 인접 카드에 2기씩 유닛",
    },
    # ... 55장 × 3★ = 165 엔트리
}


func get_desc(card_id: String, star: int = 1) -> String:
    if not _descs.has(card_id):
        return ""
    var per_star: Dictionary = _descs[card_id]
    if per_star.has(star):
        return per_star[star]
    return per_star.get(1, "")
```

---

## 유틸리티

```python
def fmt_pct(f):
    """0.05 → 5, 0.075 → 7.5"""
    val = f * 100
    if val == int(val):
        return str(int(val))
    return f"{val:.1f}".rstrip("0").rstrip(".")
```

---

## 구현 계획

### Phase 1: 공통 효과 + 중립/스팀펑크 card_db 카드
- spawn, enhance, buff, gold, terazin, shield, scrap, diversity_gold, absorb
- 대상: ~25장 (effects가 card_db에 직접 구현된 카드)
- 검증: 생성 텍스트 vs 기존 card_descs.gd diff → 불일치 리스트

### Phase 2: 조건부 + 특수 메커니즘
- conditional, post_threshold, battle_buff, timing override
- 대상: 조건부 있는 ~10장

### Phase 3: 드루이드 테마 DSL
- tree_add, tree_absorb, tree_breed, tree_shield, tree_enhance, tree_gold,
  tree_distribute, multiply_stats, debuff_store, tree_temp_buff, druid_unit_enhance,
  epic_shop_unlock, free_reroll
- 대상: 10장

### Phase 4: 포식종 테마 DSL
- hatch, meta_consume, hatch_scaled, hatch_enhance, on_combat_result,
  swarm_buff, persistent
- 대상: 10장

### Phase 5: 군대 테마 DSL
- train, conscript, rank_threshold, rank_buff, revive, revive_override,
  counter_produce, economy, upgrade_discount, rare_counter, epic_counter, total_counter
- 대상: 10장

### Phase 6: 통합 + card_descs.gd 교체
- `scripts/card_desc_gen.py` 별도 모듈로 분리 (C1: 800줄 제한)
  - 모든 `desc_*` 함수, `resolve_target`, `ACTION_TIMING_OVERRIDE`, `OE_PREFIX` 등
  - `generate_all_descs(cards_data) → dict[card_id → {1: str, 2: str, 3: str}]` API
- `codegen_card_db.py`에서 `from card_desc_gen import generate_all_descs`
- `card_descs.gd`에 `# AUTO-GENERATED` 헤더 + chmod 444
- `--check` 모드에 card_descs.gd 검증 추가
- 기존 수동 card_descs.gd 삭제

### 검증 방법
각 Phase에서 생성 텍스트와 기존 card_descs.gd를 diff:
```bash
python3 scripts/codegen_card_db.py --diff-descs
```
- **정확 일치**: 불필요 (문체 차이는 허용)
- **수치 일치**: 필수 (ATK +3%가 +5%로 바뀌면 버그)
- **효과 누락**: 필수 (★3에 spawn이 있는데 텍스트에 없으면 버그)

---

## 엣지 케이스

### 1. 다중 타이밍 카드 (B1)
독 양식장(pr_farm): RS(부화) + PC(경제). YAML에서 effects가 둘 다 포함.
→ **해결**: `ACTION_TIMING_OVERRIDE` 맵으로 action별 고유 타이밍 자동 감지.
→ `generate_star_desc`에서 타이밍별 그룹핑 → 별도 문장 출력.
→ YAML 변경 불필요.

### 2. ★3에서 timing 변경
ne_merchant ★3: PCD → PC, ne_chimera_cry ★3: PCD → PC.
→ `star_data.get("timing")` 으로 처리 (이미 YAML에 기술됨).

### 3. persistent 효과가 주 효과와 혼재
sp_line ★3: `effects: [spawn, persistent]`. 
→ persistent action을 만나면 `[지속]` 접두사로 분리 출력.

### 4. OE 카드의 require_other
sp_line: `require_other: true` → "(이 카드 제외)" 텍스트 추가.

### 5. 군대 rank_threshold의 unit 이름
YAML에 `unit: ml_infantry` 형태 → UnitDB에서 한국어 이름 조회 필요.
→ 코드젠 시점에 units-*.yaml (또는 unit_db.gd)에서 매핑 필요. 또는 YAML에 display_name 추가.
→ **간단 해법**: codegen 스크립트에 unit_id → 한국어 매핑 테이블 하드코딩 (유닛 수 ~40종으로 관리 가능).

### 6. tag:* 동적 타겟 (B2)
pr_queen ★3: `enhance: {target: tag:queen, hp_pct: 0.05}` 
→ **해결**: `resolve_target()`에서 `tag:` 접두사 파싱 → `"#queen 유닛"` 출력.

### 7. effect별 timing_override 필드 (B3)
dr_earth ★3: `tree_shield: {timing_override: BS, ...}`
→ **해결**: `desc_tree_shield`에서 `timing_override` 필드 감지 → `"전투 시작: ..."` 접두사 추가.
→ `generate_star_desc`에서도 `params.get("timing_override")` 확인하여 그룹핑.

### 8. OE listen l1 없는 경우 (C5)
pr_molt: `listen: {l2: HA}`, pr_harvest: `listen: {l2: MT}`
→ **해결**: OE_PREFIX에 `(None, "HA")`, `(None, "MT")` 엔트리 추가.
