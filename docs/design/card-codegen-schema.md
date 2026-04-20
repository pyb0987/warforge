# 카드 YAML 코드젠 설계 — 단일 소스 아키텍처

## 목적

카드의 기계적 데이터를 YAML로 정의하고, **card_db.gd를 자동 생성**한다.
YAML이 유일한 진실 소스(Single Source of Truth)가 되어 설계↔코드 이중 소스 문제를 구조적으로 제거한다.

### 배경
- 전수조사(2026-04-12) 결과 55장 중 20장(36%)에서 설계↔코드 불일치 발견
- 근본 원인: 마크다운 자유 형식 + GDScript Dict의 이중 소스 수동 동기화 실패
- traces/failures/006-card-design-code-audit.md 참조

### 이전 설계와의 차이
- **이전**: YAML 검증 블록 + 수동 card_db.gd → 검증 스크립트가 diff 출력 (삼중 소스 위험)
- **현재**: YAML → 코드젠 → card_db.gd 자동 생성 (단일 소스)

## 아키텍처

```
docs/design/cards-*.md     ← 설계 산문 (인간용 설명, 의도)
         ↕ 참조              ↑ 설계자가 양쪽 편집
data/cards/{theme}.yaml    ← 기계적 진실 소스 (코드젠 입력)
         ↓ 코드젠
godot/core/data/card_db.gd ← 자동 생성 (수동 편집 금지)
```

### 파일 구조

```
data/cards/
├── neutral.yaml        # 중립 15장
├── steampunk.yaml      # 스팀펑크 10장
├── druid.yaml          # 드루이드 10장
├── predator.yaml       # 포식종 10장
└── military.yaml       # 군대 10장

scripts/
└── codegen_card_db.py  # YAML → card_db.gd 생성기
```

### 워크플로우

1. 설계자가 `data/cards/{theme}.yaml` 편집 (기계적 데이터)
2. 필요시 `docs/design/cards-{theme}.md` 산문도 갱신 (의도 설명)
3. `python3 scripts/codegen_card_db.py` 실행
4. `godot/core/data/card_db.gd` 자동 생성
5. GUT 테스트 실행으로 검증

### 규칙
- `card_db.gd`는 **수동 편집 금지** — 코드젠 출력물
- 기계적 변경(수치, 효과, 타이밍)은 반드시 YAML에서
- `card_db.gd`에 `# AUTO-GENERATED — DO NOT EDIT` 헤더 삽입
- theme_system.gd는 **행동 로직만** 유지 — per-card 파라미터(수치, 임계값, 수량)는 YAML에서 card template으로 전달
- theme_system.gd의 `match card_id:` 분기는 **effects 배열 순회**로 리팩터링

### 설계 원칙
- **DSL 순응 원칙**: DSL로 표현하기 어려운 복잡 효과는 효과 설계를 변경하여 DSL에 맞춘다. DSL 복잡도를 높이는 것보다 게임 설계를 조정하는 비용이 낮다.

---

## YAML 스키마

### 카드 엔트리 (v2 block 구조)

2026-04-20 Phase 2: **timing이 effect 블록 안으로 이관**. 카드 상단에서 `timing` 필드 제거, 각 효과 블록이 자신의 `trigger_timing`을 가진다. 한 카드가 여러 timing(RS+PERSISTENT 등)을 동시에 가질 수 있는 multi-block 지원 (예: sp_warmachine).

```yaml
cards:
  {card_id}:
    name: string                   # 카드 이름 (한글)
    tier: int                      # 1-5
    theme: string                  # neutral | steampunk | druid | predator | military
    comp:                          # 구성 유닛 배열
      - unit: string               # unit_id
        n: int                     # 유닛 수
    tags: [string]                 # 카드 태그 배열

    # 구현 위치 (기본 card_db)
    impl: string                   # card_db | theme_system
    # star_scalable_actions: r_conditional 내부에서 ★별 수치 차이를 허용할 action 이름 (선택)
    star_scalable_actions: [string]

    # ★ 레벨별 데이터
    stars:
      1:
        effects:                   # ← 이제 timing 블록의 리스트
          - trigger_timing: string # RS | OE | BS | CA | PC | PCD | PCV | REROLL | MERGE | SELL | DEATH | PERSISTENT
            max_act: int           # -1 = 무제한, 양수 = 라운드당 상한
            # OE timing일 때만
            listen:
              l1: string|null      # UA | EN | null
              l2: string|null      # MF | UP | TG | BR | HA | MT | TR | CO | null
            # 선택 (카드 전역 상태 — 블록별 설정 가능)
            require_other: bool    # 기본 false — 인접 다른 카드 필요
            require_tenure: int    # 기본 0 — 최소 보유 라운드
            is_threshold: bool     # 기본 false — 임계점 카드
            conditional: [...]     # 이 block의 timing에 종속된 조건부 effect (선택)
            r_conditional: [...]   # rank milestone 조건부 (선택, 주로 military)
            post_threshold: [...]  # is_threshold 돌파 후 effect (선택)
            # actions — 블록 안의 나머지 key 전부가 action. 이름별 dict 또는 list-of-dict
            {action_name}: {params}           # 단일 호출
            {action_name}: [{params}, {...}]  # 동일 action 여러 번 (중복 허용, dict 아닌 list)
      2:
        effects: [...]             # ★2 효과 (완전 명시, ★1과 독립)
      3:
        effects: [...]             # ★3 효과
```

### Multi-block 카드 예시 (sp_warmachine)

```yaml
sp_warmachine:
  tier: 4
  theme: steampunk
  impl: theme_system
  comp: [...]
  stars:
    1:
      effects:
        - trigger_timing: PERSISTENT       # ★ 대표 timing = 첫 block (flat hoist)
          max_act: -1
          range_bonus: {tag: firearm, unit_thresh: 8}
        - trigger_timing: RS               # 같은 카드의 두 번째 block
          max_act: -1
          manufacture: {target: self, count: 1}
```

### ★ 레벨 데이터 규칙

- 모든 ★ 레벨은 **완전 명시** (상속/병합 없음). ★2가 ★1과 동일해도 전부 적는다.
- 코드젠은 ★1을 base로, ★2/★3에서 차이가 있는 필드만 `star_overrides`로 생성한다.
- Multi-block 카드: YAML 첫 block의 `trigger_timing`이 카드의 "대표 timing"으로 flat hoist 됨 (backward-compat). `template["trigger_timing"]` top-level 접근자는 이 값을 가리킨다.
- `impl: theme_system` 카드는 YAML에 full effects 배열을 작성. 코드젠은 `_templates[id]["effects"]`에 block 리스트 그대로 저장. theme_system에서 `_find_eff(CardDB.get_theme_effects(id, star), action_name)`으로 action 탐색.
- `impl: theme_system` 누락 시 codegen에서 hard-fail (theme 카드가 `CARD_DB_ACTIONS` 외 action을 쓰는 경우).

---

## Effect DSL

효과는 `{action}: {params}` 형식의 단일 키 dict.

### spawn — 유닛 소환

```yaml
- spawn:
    target: string     # self | right_adj | left_adj | both_adj | all_allies | event_target
    count: int         # 기본 1
    strongest: bool    # 기본 false — 가장 강한 유닛 복제 (breed_strongest)
    ol1: string|null   # 기본 UA — output_layer1 (null = 이벤트 미방출)
    ol2: string|null   # 기본 null — output_layer2
```

**기본값**: `count: 1`, `strongest: false`, `ol1: UA`, `ol2: null`

축약 예시:
```yaml
- spawn: {target: right_adj}                              # 인접 1기 소환, UA 방출
- spawn: {target: both_adj, count: 2, ol2: MF}            # 양쪽 2기, UA+MF 방출
- spawn: {target: self, count: 1, ol1: null}               # 자체 1기, 이벤트 미방출
- spawn: {target: both_adj, count: 2, ol1: UA, ol2: MF, strongest: true}  # 최강 유닛 복제
```

### enhance — 스탯 영구 강화 (%)

```yaml
- enhance:
    target: string     # self | right_adj | left_adj | both_adj | all_allies | event_target
    atk_pct: float     # ATK 강화 비율 (0.05 = 5%)
    hp_pct: float      # 기본 0.0 — HP 강화 비율
    tag: string        # 기본 "" — unit_tag_filter
    ol1: string|null   # 기본 EN
    ol2: string|null   # 기본 null
```

축약 예시:
```yaml
- enhance: {target: self, atk_pct: 0.03}                  # 자체 ATK 3%, EN 방출
- enhance: {target: event_target, atk_pct: 0.05, tag: gear, ol2: UP}  # 기어 유닛 ATK 5%
- enhance: {target: self, atk_pct: 0.03, ol1: null}       # 이벤트 미방출 강화
```

### buff — 전투 중 임시 버프 (이벤트 미방출)

```yaml
- buff:
    target: string
    atk_pct: float
    tag: string        # 기본 ""
```

### gold — 골드 획득

```yaml
- gold: int            # 축약 형식 (금액만)
```

### terazin — 테라진 획득

```yaml
- terazin: int         # 축약 형식
```

### shield — 방어막 부여

```yaml
- shield:
    target: string
    hp_pct: float      # HP 비례 방어막
```

### scrap — 인접 유닛 분해

```yaml
- scrap:
    target: string
    count: int         # 분해 유닛 수
    reroll_gain: int   # 무료 리롤 획득
    gold_per_unit: int # 유닛당 추가 골드
```

### diversity_gold — 테마 다양성 보상

```yaml
- diversity_gold:
    gold_per_theme: int       # 기본 1 — 테마당 골드
    terazin_threshold: int    # null = 없음 — N테마 이상 시 테라진
    terazin_per_theme: int    # 테마당 테라진
    mercenary_spawn: int      # null = 없음 — 용병 소환 수
```

### absorb — 유닛 흡수

```yaml
- absorb:
    target: string
    count: int                # 흡수 유닛 수
    transfer_upgrades: bool   # 기본 false
    majority_atk_bonus: float # 기본 null — 다수 종족 ATK 보너스
```

---

## Conditional (조건부 효과)

```yaml
conditional:
  - when: {condition_type: threshold_value}
    effects: [Effect]
```

### 조건 타입

| 타입 | 의미 | 예시 |
|------|------|------|
| `unit_count_gte` | 유닛 N기 이상 | `{unit_count_gte: 8}` |
| `unit_count_lte` | 유닛 N기 이하 | `{unit_count_lte: 3}` |
| `tenure_gte` | N라운드 이상 보유 | `{tenure_gte: 4}` |

### Post-Threshold (임계점 초과 효과)

`is_threshold: true`인 카드에서, 임계점(tenure 등) 충족 후 추가 적용되는 효과:

```yaml
post_threshold:
  - spawn: {target: all_allies, count: 1}
  - shield: {target: all_allies, hp_pct: 0.10}
```

---

## 테마별 Effect DSL 확장

theme_system 카드도 YAML로 완전 선언한다. 테마 메카닉의 **행동 로직**은 theme_system.gd에,
**파라미터**는 YAML에 분리한다. theme_system.gd는 match card_id 분기 대신 effects 배열을 순회.

> **설계 원칙**: DSL로 표현하기 어려운 복잡 케이스는 효과 설계를 변경하여 DSL에 맞춘다.
> DSL 복잡도를 높이는 것보다 게임 설계를 조정하는 것이 유지 비용이 낮다.

### 드루이드 — 나무(tree) 시스템

```yaml
# 나무 추가
- tree_add:
    target: string       # self | right_adj | left_adj | both_adj | all_other_druid
    count: int

# 인접 드루이드에서 나무 흡수
- tree_absorb:
    target: string       # adj_druids
    count: int           # 카드당 흡수량

# 나무 기반 번식 (나무 임계값 도달 시 유닛 소환)
- tree_breed:
    target: string       # right_adj | both_adj
    count: int           # 번식 유닛 수
    tree_thresh: int     # 필요 나무 수
    penalty_pct: float   # 기본 0.0 — 성장 페널티 (%)

# 나무 기반 강화 (trees × pct 공식)
- tree_enhance:
    target: string       # self | all_druid
    base_pct: float      # trees × base_pct
    low_unit:            # 선택 — 소수 유닛 보너스
      thresh: int
      pct: float         # trees × pct (base_pct 대체)
    tree_bonus:          # 선택 — 나무 임계점 보너스
      thresh: int
      mult: float        # 최종 결과 × mult

# 나무 기반 방어막
- tree_shield:
    target: string
    base_pct: float      # 기본 방어막 %
    tree_scale_pct: float  # 나무당 추가 %
    low_unit:            # 선택
      thresh: int
      mult: float

# 나무 분배 (다른 드루이드에게)
- tree_distribute:
    target: string       # all_other_druid
    tiers:               # 나무 임계점별 분배량
      - {tree_gte: int, amount: int}

# 곱연산 스케일링 (dr_world)
- multiply_stats:
    target: string
    atk_base: float      # 기본 ATK 배율
    atk_per_tree: float  # 나무 N개당 추가 배율
    atk_tree_step: int   # N (나무 몇 개마다)
    hp_base: float
    hp_per_tree: float
    hp_tree_step: int
    as_base: float       # AS 배율
    as_per_tree: float
    as_tree_step: int
    unit_cap: int        # 유닛 상한 (초과 시 미적용)

# 적 디버프 저장 (dr_spore_cloud)
- debuff_store:
    stat: string         # as | atk
    base_pct: float
    tree_scale_pct: float
    cap_pct: float

# 나무 기반 골드 (dr_grace)
- tree_gold:
    base_gold: int         # 기본 골드
    tree_divisor: int      # 나무 N개당 +1 골드
    win_half: bool         # 기본 true — 패배 시 절반
    terazin_thresh: int    # N골드 이상 시 테라진 추가 (null = 없음)

# 드루이드 유닛 개수 기반 강화 (dr_earth)
- druid_unit_enhance:
    target: string         # self | all_druid
    divisor: int           # 유닛 N기당 1단계
    bonus_tiers:           # 단계별 강화량
      - {stage: int, atk_pct: float, hp_pct: float}
```

### 포식종 — 부화/변태 시스템

```yaml
# 유충 부화
- hatch:
    target: string       # self | right_adj | left_adj | both_adj | all_predator
    count: int

# 유충 소비 → 변태 (이벤트 방출)
- meta_consume:
    consume: int         # 소비 유충 수
    emit: bool           # 기본 true — METAMORPHOSIS 이벤트 방출

# 전투 후 유닛 수 비례 부화 (pr_parasite)
- hatch_scaled:
    target: string
    per_units: int       # N유닛당 1기
    cap: int             # 최대 부화 수

# 전투 조건부 효과 (승리/패배 시)
- on_combat_result:
    condition: string    # victory | defeat | always
    effects: [Effect]    # 중첩 효과 배열
```

### 군대 — 계급/징집 시스템

```yaml
# 계급 훈련
- train:
    target: string       # self | adj_military | all_military | event_target
    amount: int          # 계급 +N

# 계급 임계점 보상 (일회성 소환)
- rank_threshold:
    tiers:
      - {rank: int, unit: string, count: int}

# 병력 충원
- conscript:
    target: string       # self | right_adj | both_adj
    count: int

# 계급 기반 전투 버프 (ml_tactical)
- rank_buff:
    target: string       # all_military
    shield_per_rank: float
    atk_per_unit: float  # 전체 군대 유닛 수 기준

# 유닛 수 기반 전투 버프 (ml_assault)
- swarm_buff:
    target: string       # all_military
    atk_per_unit: float
    ms_bonus:            # 선택
      unit_thresh: int
      bonus: int

# 카운터 기반 보상 (ml_factory, sp_charger 공용)
- counter_produce:
    event: string        # CONSCRIPT | MF 등 — 어떤 이벤트를 카운트
    threshold: int       # N회마다 발동
    rewards:
      terazin: int       # 기본 0
      enhance_atk_pct: float  # 기본 0.0
```

### 스팀펑크 (theme_system 전용)

```yaml
# 화기 유닛 기반 사거리 보너스 (sp_warmachine)
- range_bonus:
    tag: string          # firearm — 대상 유닛 태그
    unit_thresh: int     # N기당 사거리 +1
    atk_buff_pct: float  # 기본 0.0 — 태그 유닛 ATK 버프
    attack_stack_pct: float  # 기본 0.0 — 공격당 ATK 스택 (★3)

# 희귀 업그레이드 카운터 (sp_charger ★2)
# 누적 MF 횟수가 threshold에 도달하면 pending_rare_upgrade 보상
- rare_counter:
    threshold: int       # 누적 이벤트 수 (회차 누적, 리셋 없음)
    reward: string       # pending_rare_upgrade

# 에픽 업그레이드 카운터 (sp_charger ★3)
# 누적 MF 횟수가 threshold에 도달하면 pending_epic_upgrade 보상 (레어→에픽 승격)
- epic_counter:
    threshold: int       # 누적 이벤트 수 (회차 누적, 리셋 없음)
    reward: string       # pending_epic_upgrade

# 총 누적 카운터 기반 보상 (sp_charger ★3)
# 라운드 리셋 없이 누적 — threshold마다 테라진 지급
- total_counter:
    per_manufacture: int # MF N회마다 발동
    reward_terazin: int  # 지급 테라진

# 합성 시 1회 발동 효과 (sp_charger ★3, on_merge 타이밍 카드와 별도)
# 주석 처리 보류 중 — theme_system 내부 on_merge 훅으로 구현 예정
- on_merge:
    epic_upgrade: int    # 무료 에픽 업그레이드 수
    terazin: int         # 지급 테라진

# 경제 카드 (dr_grace, ml_supply 등 공용)
- economy:
    gold_base: int
    gold_per: float      # N카드/유닛당 추가 골드
    gold_per_unit: string  # cards | units — 기준
    halve_on_loss: bool  # 기본 true
    terazin:             # 선택
      condition: string  # tree_gte | rank_gte 등
      thresh: int
      amount: int
```

### 공용 확장

```yaml
# 기존 target 어휘 확장
# 기본: self | right_adj | left_adj | both_adj | all_allies | event_target
# 추가:
#   all_druid       — 모든 드루이드 카드
#   all_predator    — 모든 포식종 카드
#   all_military    — 모든 군대 카드
#   all_other_druid — 자신 제외 드루이드
#   adj_druids      — 인접 드루이드만
#   event_source    — 이벤트를 발생시킨 카드
#   tag:{name}      — 특정 태그 유닛 보유 카드 (pr_carapace)
```

---

## Enum 매핑

### timing

| YAML | Enums.TriggerTiming | 설계 문서 키워드 |
|------|---------------------|----------------|
| `RS` | ROUND_START | `라운드 시작:` |
| `OE` | ON_EVENT | `[반응]` |
| `BS` | BATTLE_START | `전투 시작:` |
| `CA` | ON_COMBAT_ATTACK | `공격 시:` |
| `PC` | POST_COMBAT | `전투 종료:` |
| `PCD` | POST_COMBAT_DEFEAT | `패배 시:` |
| `PCV` | POST_COMBAT_VICTORY | `승리 시:` |
| `REROLL` | ON_REROLL | `리롤 시:` |
| `MERGE` | ON_MERGE | `합성 시:` |
| `SELL` | ON_SELL | `판매 시:` |
| `DEATH` | ON_COMBAT_DEATH | `사망 시:` |
| `PERSISTENT` | PERSISTENT | `[지속]` |

### layer1 / layer2

| YAML | Enum | 의미 |
|------|------|------|
| `UA` | Layer1.UNIT_ADDED | 유닛 추가됨 |
| `EN` | Layer1.ENHANCED | 강화됨 |
| `MF` | Layer2.MANUFACTURE | 제조 |
| `UP` | Layer2.UPGRADE | 개량 |
| `TG` | Layer2.TREE_GROW | 나무 성장 |
| `BR` | Layer2.BREED | 번식 |
| `HA` | Layer2.HATCH | 부화 |
| `MT` | Layer2.METAMORPHOSIS | 변태 |
| `TR` | Layer2.TRAIN | 훈련 |
| `CO` | Layer2.CONSCRIPT | 징집 |

### theme

| YAML | Enums.CardTheme |
|------|-----------------|
| `neutral` | NEUTRAL |
| `steampunk` | STEAMPUNK |
| `druid` | DRUID |
| `predator` | PREDATOR |
| `military` | MILITARY |

---

## 예시: 스팀펑크 카드 (card_db 구현)

```yaml
cards:
  sp_assembly:
    name: 증기 조립소
    tier: 1
    theme: steampunk
    timing: RS
    comp:
      - {unit: sp_spider, n: 2}
      - {unit: sp_rat, n: 1}
    tags: [steampunk, production]
    stars:
      1:
        max_act: -1
        effects:
          - spawn: {target: right_adj, count: 1, ol2: MF}
      2:
        max_act: -1
        effects:
          - spawn: {target: both_adj, count: 1, ol2: MF}
      3:
        max_act: -1
        effects:
          - spawn: {target: both_adj, count: 2, ol2: MF}
          - enhance: {target: both_adj, atk_pct: 0.05, ol2: UP}

  sp_circulator:
    name: 증기 순환기
    tier: 2
    theme: steampunk
    timing: OE
    listen: {l2: UP}
    comp:
      - {unit: sp_sawblade, n: 1}
      - {unit: sp_scout, n: 1}
    tags: [steampunk, cycle]
    stars:
      1:
        max_act: 1
        effects:
          - spawn: {target: event_target, count: 1, ol2: MF}
      2:
        max_act: 2
        effects:
          - spawn: {target: event_target, count: 1, ol2: MF}
      3:
        max_act: 3
        effects:
          - spawn: {target: event_target, count: 1, ol2: MF, strongest: true}

  sp_line:
    name: 조립 라인
    tier: 3
    theme: steampunk
    timing: OE
    listen: {l1: UA, l2: MF}
    require_other: true
    comp:
      - {unit: sp_sawblade, n: 2}
      - {unit: sp_spider, n: 1}
    tags: [steampunk, production]
    stars:
      1:
        max_act: 3
        effects:
          - spawn: {target: both_adj, count: 1, ol2: MF}
      2:
        max_act: 4
        effects:
          - spawn: {target: both_adj, count: 2, ol2: MF}
      3:
        max_act: 4
        effects:
          - spawn: {target: both_adj, count: 2, ol2: MF, strongest: true}
```

## 예시: 조건부 효과

```yaml
  sp_furnace:
    name: 증기 용광로
    tier: 1
    theme: steampunk
    timing: RS
    comp:
      - {unit: sp_crab, n: 1}
      - {unit: sp_sawblade, n: 1}
    tags: [steampunk, focus]
    stars:
      1:
        max_act: -1
        effects:
          - spawn: {target: self, count: 1, ol2: MF}
          - enhance: {target: self, atk_pct: 0.03}
      2:
        max_act: -1
        effects:
          - spawn: {target: self, count: 2, ol2: MF}
          - enhance: {target: self, atk_pct: 0.05}
      3:
        max_act: -1
        effects:
          - spawn: {target: self, count: 2, ol2: MF}
          - enhance: {target: self, atk_pct: 0.05}
        conditional:
          - when: {unit_count_gte: 8}
            effects:
              - enhance: {target: self, atk_pct: 0.03}

  ne_awakening:
    name: 고대의 각성
    tier: 4
    theme: neutral
    timing: RS
    require_tenure: 4
    is_threshold: true
    comp:
      - {unit: ne_guardian, n: 1}
      - {unit: ne_golem, n: 1}
    tags: [neutral, ancient]
    stars:
      1:
        max_act: -1
        effects:
          - spawn: {target: all_allies, count: 2}
          - enhance: {target: all_allies, atk_pct: 0.10}
          - shield: {target: all_allies, hp_pct: 0.20}
      2:
        max_act: -1
        effects:
          - spawn: {target: all_allies, count: 3}
          - enhance: {target: all_allies, atk_pct: 0.15}
          - shield: {target: all_allies, hp_pct: 0.30}
      3:
        max_act: -1
        effects:
          - spawn: {target: all_allies, count: 3}
          - enhance: {target: all_allies, atk_pct: 0.15}
          - shield: {target: all_allies, hp_pct: 0.30}
        post_threshold:
          - spawn: {target: all_allies, count: 1}
          - shield: {target: all_allies, hp_pct: 0.10}
```

## 예시: 이벤트 미방출 카드

```yaml
  sp_interest:
    name: 증기 이자기
    tier: 2
    theme: steampunk
    timing: REROLL
    comp:
      - {unit: sp_scout, n: 2}
      - {unit: sp_rat, n: 1}
    tags: [steampunk, economy]
    stars:
      1:
        max_act: 3
        effects:
          - spawn: {target: self, count: 1, ol1: null}
          - enhance: {target: self, atk_pct: 0.03, ol1: null}
      2:
        max_act: 3
        effects:
          - spawn: {target: self, count: 2, ol1: null}
          - enhance: {target: self, atk_pct: 0.05, ol1: null}
      3:
        max_act: 3
        effects:
          - spawn: {target: self, count: 2, ol1: null}
          - spawn: {target: both_adj, count: 1, ol1: null}
          - enhance: {target: self, atk_pct: 0.05, ol1: null}
```

## 예시: theme_system 카드 — 드루이드

```yaml
  dr_cradle:
    name: 숲의 요람
    tier: 1
    theme: druid
    timing: RS
    impl: theme_system
    comp: [{unit: dr_treant_y, n: 1}, {unit: dr_wolf, n: 1}]
    tags: [druid, creation]
    stars:
      1:
        max_act: -1
        effects:
          - tree_add: {target: self, count: 1}
          - tree_add: {target: right_adj, count: 1}
      2:
        max_act: -1
        effects:
          - tree_add: {target: self, count: 2}
          - tree_add: {target: both_adj, count: 1}
      3:
        max_act: -1
        effects:
          - tree_add: {target: self, count: 3}
          - tree_add: {target: both_adj, count: 2}

  dr_deep:
    name: 뿌리깊은 자
    tier: 3
    theme: druid
    timing: RS
    impl: theme_system
    comp: [{unit: dr_treant_a, n: 1}, {unit: dr_rootguard, n: 1}]
    tags: [druid, time]
    stars:
      1:
        max_act: -1
        effects:
          - tree_add: {target: self, count: 1}
          - tree_enhance: {target: self, base_pct: 0.008, low_unit: {thresh: 3, pct: 0.012}, tree_bonus: {thresh: 10, mult: 1.3}}
      2:
        max_act: -1
        effects:
          - tree_add: {target: self, count: 1}
          - tree_enhance: {target: self, base_pct: 0.012, low_unit: {thresh: 3, pct: 0.018}, tree_bonus: {thresh: 8, mult: 1.3}}
      3:
        max_act: -1
        effects:
          - tree_add: {target: self, count: 2}
          - tree_enhance: {target: self, base_pct: 0.012, low_unit: {thresh: 3, pct: 0.018}, tree_bonus: {thresh: 8, mult: 1.5}}
```

## 예시: theme_system 카드 — 포식종

```yaml
  pr_nest:
    name: 유충 둥지
    tier: 1
    theme: predator
    timing: RS
    impl: theme_system
    comp: [{unit: pr_larva, n: 3}, {unit: pr_worker, n: 1}]
    tags: [predator, hatch]
    stars:
      1:
        max_act: -1
        effects:
          - hatch: {target: self, count: 2}
          - hatch: {target: right_adj, count: 1}
      2:
        max_act: -1
        effects:
          - hatch: {target: self, count: 4}
          - hatch: {target: right_adj, count: 2}
      3:
        max_act: -1
        effects:
          - hatch: {target: self, count: 4}
          - hatch: {target: left_adj, count: 2}
          - hatch: {target: right_adj, count: 2}

  pr_molt:
    name: 탈피의 방
    tier: 2
    theme: predator
    timing: OE
    listen: {l2: HA}
    impl: theme_system
    comp: [{unit: pr_larva, n: 2}, {unit: pr_guardian, n: 1}]
    tags: [predator, metamorphosis]
    stars:
      1:
        max_act: 2
        effects:
          - meta_consume: {consume: 3}
      2:
        max_act: 3
        effects:
          - meta_consume: {consume: 2}
      3:
        max_act: 3
        effects:
          - meta_consume: {consume: 2}
          - enhance: {target: self, atk_pct: 0.05}
```

## 예시: theme_system 카드 — 군대

```yaml
  ml_barracks:
    name: 신병 훈련소
    tier: 1
    theme: military
    timing: RS
    impl: theme_system
    comp: [{unit: ml_recruit, n: 2}, {unit: ml_infantry, n: 1}]
    tags: [military, training]
    stars:
      1:
        max_act: -1
        effects:
          - train: {target: self, amount: 1}
          - train: {target: adj_military, amount: 1}
          - rank_threshold:
              tiers:
                - {rank: 3, unit: ml_infantry, count: 1}
                - {rank: 5, unit: ml_plasma, count: 1}
                - {rank: 8, unit: ml_walker, count: 1}
      2:
        max_act: -1
        effects:
          - train: {target: self, amount: 2}
          - train: {target: adj_military, amount: 1}
          - rank_threshold:
              tiers:
                - {rank: 3, unit: ml_infantry, count: 1}
                - {rank: 5, unit: ml_plasma, count: 1}
                - {rank: 8, unit: ml_walker, count: 1}
      3:
        max_act: -1
        effects:
          - train: {target: self, amount: 2}
          - train: {target: adj_military, amount: 1}
          - rank_threshold:
              tiers:
                - {rank: 3, unit: ml_infantry, count: 1}
                - {rank: 5, unit: ml_plasma, count: 1}
                - {rank: 8, unit: ml_walker, count: 1}

  sp_charger:
    name: 태엽 과급기
    tier: 4
    theme: steampunk
    timing: OE
    listen: {l1: UA, l2: MF}
    impl: theme_system
    comp: [{unit: sp_titan, n: 1}, {unit: sp_turret, n: 1}]
    tags: [steampunk, power]
    stars:
      1:
        max_act: -1
        effects:
          - counter_produce: {event: MF, threshold: 10, rewards: {terazin: 1, enhance_atk_pct: 0.05}}
      2:
        max_act: -1
        effects:
          - counter_produce: {event: MF, threshold: 10, rewards: {terazin: 1, enhance_atk_pct: 0.05}}
          - rare_counter: {threshold: 20, reward: pending_rare_upgrade}
      3:
        max_act: -1
        effects:
          - counter_produce: {event: MF, threshold: 10, rewards: {terazin: 1, enhance_atk_pct: 0.05}}
          - epic_counter: {threshold: 15, reward: pending_epic_upgrade}
          - total_counter: {per_manufacture: 10, reward_terazin: 1}
          # ★3 합성 시 1회: 무료 에픽 업그레이드 + 3 테라진 (on_merge 훅, theme_system 내부)
          # - on_merge: {epic_upgrade: 1, terazin: 3}
```

---

## 코드젠 설계

### 입력 → 출력

```
data/cards/*.yaml  →  codegen_card_db.py  →  godot/core/data/card_db.gd
```

### `_theme_effects` API

`impl: theme_system` 카드는 card_db.gd에서 `effects=[]`로 저장되고, 파라미터는 별도 dict에 보존된다:

- `CardDB._theme_effects`: `card_id → {star_level → Array of effect dicts}`
  - 코드젠이 자동 생성. 구조: `{1: [...], 2: [...], 3: [...]}`
- `CardDB.get_theme_effects(card_id: String, star_level: int) -> Array`
  - theme_system.gd가 이 API로 per-star 효과 파라미터를 읽음
  - `match star_level:` 분기 대신 데이터 드리븐 처리 가능

```gdscript
# theme_system.gd 사용 예시
var effects = CardDB.get_theme_effects("sp_charger", card.star_level)
for effect in effects:
    if effect.has("counter_produce"):
        _handle_counter_produce(card, effect["counter_produce"])
```

### 생성 전략

1. **헤더**: `# AUTO-GENERATED from data/cards/*.yaml — DO NOT EDIT` + 기존 유틸 함수
2. **헬퍼 함수**: `_c()`, `_star()`, `_spawn()`, `_enhance()` 등은 그대로 유지 (GDScript 런타임 인터페이스)
3. **등록 함수**: YAML 파일별로 `_register_{theme}()` 생성
4. **star_overrides 최적화**: 코드젠이 ★1 대비 차이점만 `star_overrides`에 넣음

### 코드젠 의사 코드

```python
for theme_file in glob("data/cards/*.yaml"):
    cards = yaml.safe_load(theme_file)["cards"]
    
    for card_id, spec in cards.items():
        # 1. composition 배열 생성
        comp = [{"unit_id": c["unit"], "count": c["n"]} for c in spec["comp"]]
        
        # 2. ★1 effects → GDScript 헬퍼 호출 코드 생성
        star1 = spec["stars"][1]
        effects_code = generate_effects(star1["effects"])
        
        # 3. timing/layer 매핑
        timing = TIMING_MAP[spec["timing"]]
        l1 = LAYER1_MAP.get(spec.get("listen", {}).get("l1"), -1)
        l2 = LAYER2_MAP.get(spec.get("listen", {}).get("l2"), -1)
        
        # 4. star_overrides: ★2/★3 중 ★1과 차이 있는 필드만
        overrides = {}
        for star in [2, 3]:
            diff = compute_star_diff(star1, spec["stars"][star])
            if diff:
                overrides[star] = generate_star_override(spec, star, diff)
        
        # 5. _c() 호출 코드 출력
        emit_c_call(card_id, spec, comp, timing, star1, effects_code, l1, l2, overrides)
```

### Effect → GDScript 매핑

| YAML | 생성 코드 |
|------|----------|
| `spawn: {target: X, count: N, ol2: MF}` | `_spawn("X", N, Enums.Layer1.UNIT_ADDED, Enums.Layer2.MANUFACTURE)` |
| `spawn: {target: X, strongest: true, ...}` | `{"action": "spawn", "target": "X", ..., "breed_strongest": true}` |
| `spawn: {target: X, ol1: null}` | `_spawn("X", N, -1, -1)` |
| `enhance: {target: X, atk_pct: P}` | `_enhance("X", P)` |
| `enhance: {target: X, atk_pct: P, tag: T, ol2: UP}` | `_enhance("X", P, 0.0, "T", Enums.Layer1.ENHANCED, Enums.Layer2.UPGRADE)` |
| `buff: {target: X, atk_pct: P}` | `_buff("X", P)` |
| `gold: N` | `_gold(N)` |
| `terazin: N` | `{"action": "grant_terazin", "target": "self", "terazin_amount": N}` |
| `shield: {target: X, hp_pct: P}` | `_shield("X", P)` |
| `scrap: {...}` | `{"action": "scrap_adjacent", ...}` |
| `diversity_gold: {...}` | `{"action": "diversity_gold", ...}` |
| `absorb: {...}` | `{"action": "absorb_units", ...}` |

**헬퍼 우선**: `_spawn()`, `_enhance()` 등으로 표현 가능하면 헬퍼 사용, 특수 파라미터 필요 시 직접 dict.

### conditional → GDScript 매핑

```yaml
conditional:
  - when: {unit_count_gte: 8}
    effects:
      - enhance: {target: self, atk_pct: 0.03}
```
→
```gdscript
"conditional_effects": [
    {"condition": "unit_count_gte", "threshold": 8,
     "effects": [_enhance("self", 0.03)]},
],
```

---

## 마이그레이션 계획

### Phase 1: 중립 + 스팀펑크 (25장) — 코드젠 구축

1. `data/cards/neutral.yaml`, `data/cards/steampunk.yaml` 작성
2. `scripts/codegen_card_db.py` 구현
3. 코드젠 출력과 기존 card_db.gd 비교 → 100% 일치 확인
4. 기존 card_db.gd를 코드젠 출력으로 교체
5. GUT 테스트 전체 통과 확인

### Phase 2: 드루이드 + 포식종 + 군대 (30장) — theme_system 리팩터링

1. 나머지 3테마 YAML 작성 (테마별 DSL effect 타입 사용)
2. 코드젠이 theme_system 카드에도 effects 배열 포함시킴
3. theme_system.gd 리팩터링: `match card_id:` → effects 배열 순회 dispatcher
4. 코드젠으로 card_db.gd 전체 생성
5. GUT 테스트 전체 통과 확인

### Phase 3: Hook 통합

1. `data/cards/*.yaml` 또는 `card_db.gd` 수동 편집 시 경고 hook
2. 커밋 시 `codegen_card_db.py --check` 자동 실행 (생성물과 현재 파일 일치 여부)
3. 기존 `.gd edit warning` hook을 코드젠 파이프라인으로 대체

---

## DESIGN.md 등록

변경 영향 맵에 추가:
```
card-codegen-schema.md
  ← data/cards/*.yaml (진실 소스)
  ← cards-*.md (산문)
  → codegen_card_db.py → card_db.gd (생성물)
  → theme_system.gd 리팩터링 (effects dispatcher)
```

## 결정 사항 이력

| 항목 | 결정 | 일자 |
|------|------|------|
| 파일명 리네임 | `card-codegen-schema.md` ✅ | 2026-04-12 |
| 코드젠 스크립트 언어 | Python 3 (PyYAML) ✅ | 2026-04-12 |
| theme_system DSL 흡수 | 전체 흡수 ✅ — 테마별 effect 타입으로 파라미터 선언 | 2026-04-12 |
| DSL 순응 원칙 | DSL에 안 맞으면 효과 설계를 변경 ✅ | 2026-04-12 |
