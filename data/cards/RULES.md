# YAML 생성 규칙서

서브에이전트가 card_db.gd + theme_system.gd + 설계 문서에서 YAML을 생성할 때 따르는 명세.
**모호함 없이 기계적으로 변환 가능해야 한다.**

스키마 전체 정의: `docs/design/card-codegen-schema.md` 참조.

---

## 🔄 v2 스키마 변경 (2026-04-20)

**중요**: Phase 2에서 YAML 스키마가 block 구조로 이관됨. 이 문서의 §5 이전 섹션(§1–§4)은 v1 기반이므로 **카드 스키마 예시는 아래 v2 규칙을 우선 참조**.

### 핵심 변경
- `timing`이 카드 상단 → **각 effect block 안**으로 이관 (`trigger_timing` 필드)
- `listen`, `require_other`, `require_tenure`, `is_threshold`, `max_act`, `conditional`, `r_conditional`, `post_threshold`도 block 안으로
- 한 카드가 여러 block 보유 가능 (multi-block — 예: sp_warmachine의 PERSISTENT + RS)
- 동일 action을 한 block에서 여러 번 쓸 때 params를 **리스트**로 (`spawn: [{...}, {...}]`)

### v2 YAML 형태 (최소 예시)

```yaml
sp_furnace:
  name: 증기 용광로
  tier: 1
  theme: steampunk
  comp: [{unit: sp_crab, n: 1}, {unit: sp_sawblade, n: 1}]
  tags: [steampunk, focus]
  stars:
    1:
      effects:
        - trigger_timing: RS          # ← block 단위
          max_act: -1                  # ← block 단위
          spawn: {target: self, ol2: MF}
          enhance: {target: self, atk_pct: 0.03}
```

### Multi-block 예시 (sp_warmachine)

```yaml
sp_warmachine:
  impl: theme_system
  stars:
    1:
      effects:
        - trigger_timing: PERSISTENT   # ← 첫 block = 대표 timing (flat hoist)
          max_act: -1
          range_bonus: {tag: firearm, unit_thresh: 8}
        - trigger_timing: RS           # ← 두 번째 block, 같은 ★에서 공존
          max_act: -1
          manufacture: {target: self, count: 1}
```

### v2 핵심 규칙
1. **카드 상단에 `timing` 금지** — 반드시 block의 `trigger_timing`으로
2. **`impl: theme_system` 누락 주의** — theme action(hatch, train, range_bonus 등) 쓰면서 `impl: theme_system` 없으면 codegen hard-fail
3. **Multi-block 카드 제약 (codegen hard-fail로 강제, 2026-04-21)**:
   - (a) 첫 block의 `trigger_timing` = 카드 "대표 timing" (flat hoist → UI/sim AI evaluator 참조). 모든 ★에서 **첫 block 순서 일관** — ★별 뒤바뀌면 codegen 차단 (`validate_multiblock_primary_timing_consistency`)
   - (b) `conditional` / `r_conditional` / `post_threshold` 는 **primary(첫) block에만** — non-primary block의 이들은 desc_gen이 말없이 드롭 (`validate_multiblock_nonprimary_conditional`)
   - (c) Scalar action (`gold: 5` 같이 dict 아닌 값)은 primary block 에만 — non-primary에 두면 설명 오배치 (`validate_multiblock_scalar_actions`)
4. **codegen 실행 후 카드 설명 확인** — multi-block은 `[지속] ... 라운드 시작: ...` 식으로 섹션 분리됨

### 기존 §2–§4는 Enum 매핑/필드 규칙 참고용
아래 섹션들의 "카드 상단 timing" 예시는 v1 잔재. 실제 카드 작성 시 무시하고 위 v2 형태를 따를 것.

---

## 1. 데이터 소스 우선순위

| 우선순위 | 소스 | 용도 |
|---------|------|------|
| 1 | `card_db.gd` _c() 호출 | tier, timing, comp, tags, max_act, effects, listen layers, flags |
| 2 | `card_db.gd` _star() / inline dict | ★2/★3 데이터 |
| 3 | `{theme}_system.gd` match 분기 | theme_system 카드의 per-star 파라미터 |
| 4 | `docs/design/cards-{theme}.md` | name (한글), 의도 확인용 (수치는 코드 우선) |

**원칙**: 코드와 설계 문서가 불일치하면 **코드를 따른다**. YAML은 현재 코드의 정확한 선언적 표현이다.

---

## 2. Enum → YAML 문자열 매핑

### TriggerTiming
```
ROUND_START       → RS
ON_EVENT          → OE
BATTLE_START      → BS
ON_COMBAT_ATTACK  → CA
POST_COMBAT       → PC
POST_COMBAT_DEFEAT  → PCD
POST_COMBAT_VICTORY → PCV
ON_REROLL         → REROLL
ON_MERGE          → MERGE
ON_SELL           → SELL
ON_COMBAT_DEATH   → DEATH
PERSISTENT        → PERSISTENT
```

### Layer1
```
UNIT_ADDED → UA
ENHANCED   → EN
-1         → (생략 또는 null)
```

### Layer2
```
MANUFACTURE    → MF
UPGRADE        → UP
TREE_GROW      → TG
BREED          → BR
HATCH          → HA
METAMORPHOSIS  → MT
TRAIN          → TR
CONSCRIPT      → CO
-1             → (생략 또는 null)
```

### CardTheme
```
NEUTRAL   → neutral
STEAMPUNK → steampunk
DRUID     → druid
PREDATOR  → predator
MILITARY  → military
```

### 코드 내 변수 매핑
_register 함수 상단의 로컬 변수를 enum으로 역매핑:
```gdscript
var RS := Enums.TriggerTiming.ROUND_START   # → RS
var OE := Enums.TriggerTiming.ON_EVENT      # → OE
var BS := Enums.TriggerTiming.BATTLE_START  # → BS
var UA := Enums.Layer1.UNIT_ADDED           # → UA
var EN := Enums.Layer1.ENHANCED             # → EN
var MF := Enums.Layer2.MANUFACTURE          # → MF
var UP := Enums.Layer2.UPGRADE              # → UP
var HT := Enums.Layer2.HATCH               # → HA  (주의: 변수명 HT ≠ YAML HA)
var MT := Enums.Layer2.METAMORPHOSIS        # → MT
var TR := Enums.Layer2.TRAIN               # → TR
var CO := Enums.Layer2.CONSCRIPT            # → CO
```

---

## 3. 카드 필드 변환 규칙

### name
- 설계 문서(cards-{theme}.md)에서 한글 이름을 가져온다.
- _c()의 두 번째 인자와 일치해야 하지만, 설계 문서가 정본.

### comp (composition)
```gdscript
# 코드
[{"unit_id":"sp_spider","count":2},{"unit_id":"sp_rat","count":1}]

# YAML
comp:
  - {unit: sp_spider, n: 2}
  - {unit: sp_rat, n: 1}
```
- flow style `{unit: X, n: N}` 사용 (한 줄로 간결하게).

### tags
```gdscript
PackedStringArray(["steampunk","production"])

# YAML
tags: [steampunk, production]
```

### listen
- timing이 OE가 아니면 listen 필드 **생략**.
- _c()의 `l1`, `l2` 파라미터에서 추출.
- -1인 필드는 생략.

```gdscript
_c(..., Enums.Layer1.UNIT_ADDED, MF)  → listen: {l1: UA, l2: MF}
_c(..., UA, -1)                        → listen: {l1: UA}
_c(..., -1, UP)                        → listen: {l2: UP}
_c(..., -1, -1)                        → (listen 필드 생략)
```

### 선택 필드 (기본값이면 생략)
```
require_other: false  → 생략
require_other: true   → require_other: true

require_tenure: 0     → 생략
require_tenure: 2     → require_tenure: 2

is_threshold: false   → 생략
is_threshold: true    → is_threshold: true
```

### impl
- theme_system에서 처리 (effects=[] 또는 DSL effects 포함 모두) → `impl: theme_system`
  - DSL effects가 있어도 `{theme}_system.gd`가 `get_theme_effects()`로 소비하면 `impl: theme_system`
  - 예: sp_arsenal — absorb effects가 YAML에 있지만 steampunk_system.gd가 소비 → `impl: theme_system`
- card_db가 직접 처리 (effects 배열 있음, theme_system 불관여) → 생략 (기본 card_db)
- 양쪽 모두 → `impl: hybrid`

---

## 4. Effect 변환 규칙

### 기본값 규칙 (생략 = 기본값 사용)

| Effect | 필드 | 기본값 | 기본값이면 |
|--------|------|--------|-----------|
| spawn | count | 1 | 생략 |
| spawn | strongest | false | 생략 |
| spawn | ol1 | UA | 생략 |
| spawn | ol2 | null | 생략 |
| enhance | hp_pct | 0.0 | 생략 |
| enhance | tag | "" | 생략 |
| enhance | ol1 | EN | 생략 |
| enhance | ol2 | null | 생략 |
| buff | tag | "" | 생략 |

### spawn 변환

```gdscript
# 헬퍼: _spawn(target, count=1, ol1=UA, ol2=-1)

_spawn("right_adj")
→ spawn: {target: right_adj}
# count=1 기본, ol1=UA 기본, ol2=-1 기본 → 전부 생략

_spawn("right_adj", 2)
→ spawn: {target: right_adj, count: 2}

_spawn("both_adj", 1, Enums.Layer1.UNIT_ADDED, MF)
→ spawn: {target: both_adj, ol2: MF}
# ol1=UA는 기본값이므로 생략, ol2만 명시

_spawn("self", 1, -1, -1)
→ spawn: {target: self, ol1: null}
# ol1이 기본값(UA)과 다름 → 명시. ol2=-1은 기본값이므로 생략

_spawn("both_adj", 2, Enums.Layer1.UNIT_ADDED, MF)  + breed_strongest: true
→ spawn: {target: both_adj, count: 2, ol2: MF, strongest: true}
# 직접 dict에서 breed_strongest가 있으면 strongest: true
```

**판정 기준**: `ol1`이 -1이면 `ol1: null` 명시. `ol1`이 UA(spawn 기본)이면 생략. `ol2`가 -1이면 생략. `ol2`가 값 있으면 명시.

### enhance 변환

```gdscript
_enhance("self", 0.03)
→ enhance: {target: self, atk_pct: 0.03}

_enhance("self", 0.08, 0.08)
→ enhance: {target: self, atk_pct: 0.08, hp_pct: 0.08}

_enhance("event_target", 0.05, 0.0, "gear", Enums.Layer1.ENHANCED, UP)
→ enhance: {target: event_target, atk_pct: 0.05, tag: gear, ol2: UP}
# hp_pct=0 기본 → 생략, ol1=EN 기본 → 생략

_enhance("self", 0.03, 0.0, "", -1, -1)
→ enhance: {target: self, atk_pct: 0.03, ol1: null}
```

### buff 변환

```gdscript
_buff("self", 0.10)
→ buff: {target: self, atk_pct: 0.10}
```

### gold / terazin 변환

```gdscript
_gold(3)
→ gold: 3

{"action": "grant_terazin", "target": "self", "terazin_amount": 1}
→ terazin: 1
```

### shield 변환

```gdscript
_shield("self", 0.20)
→ shield: {target: self, hp_pct: 0.20}
```

### 직접 dict 변환 (특수 effect)

```gdscript
{"action": "scrap_adjacent", "target": "self", "scrap_count": 1, "reroll_gain": 1, "gold_per_unit": 0}
→ scrap: {target: self, count: 1, reroll_gain: 1, gold_per_unit: 0}

{"action": "diversity_gold", "target": "self"}
→ diversity_gold: {}
# 기본값만 사용 시 빈 dict

{"action": "diversity_gold", "target": "self", "gold_per_theme": 2}
→ diversity_gold: {gold_per_theme: 2}

{"action": "absorb_units", "target": "self", "absorb_count": 3}
→ absorb: {target: self, count: 3}

{"action": "absorb_units", "target": "self", "absorb_count": 5, "transfer_upgrades": true}
→ absorb: {target: self, count: 5, transfer_upgrades: true}
```

---

## 5. ★ 레벨 변환 규칙

### ★1 → stars.1
- _c()의 직접 인자에서 추출.
- max_act, effects 필수.

### ★2/★3 → stars.2, stars.3
- star_overrides dict에서 추출.
- _star() 호출이면: 인자 순서로 매핑.
- inline dict이면: 키 이름으로 매핑.
- **완전 명시**: ★1과 동일한 필드도 전부 적는다 (상속 없음).

### _star() 인자 순서

```gdscript
func _star(nm, comp, timing, max_act, effects, tags, l1=-1, l2=-1, require_other=false, require_tenure=0, is_threshold=false)
```

→ YAML에서는 name/comp/timing/tags/listen/flags는 카드 레벨에서 이미 정의.
→ stars.N에는 `max_act`과 `effects`만 기록 (+ conditional/post_threshold가 있으면 포함).

### star_overrides가 없는 카드
- ★2/★3가 ★1과 동일 → 그래도 전부 적는다.

```yaml
# star_overrides 없는 druid 카드 (theme_system)
stars:
  1:
    max_act: -1
    effects: [...]
  2:
    max_act: -1
    effects: [...]    # ★1과 동일해도 복사
  3:
    max_act: -1
    effects: [...]
```

### ★2/★3에서 timing이 변경되는 경우
- ne_merchant ★3: POST_COMBAT_DEFEAT → POST_COMBAT
- ne_chimera_cry ★3: POST_COMBAT_DEFEAT → POST_COMBAT
- 이 경우 해당 star에 `timing: PC` 추가.

```yaml
stars:
  3:
    timing: PC         # ★1의 PCD에서 변경
    max_act: 1
    effects: [...]
```

### conditional_effects / post_threshold_effects

```gdscript
"conditional_effects": [
    {"condition": "unit_count_gte", "threshold": 8,
     "effects": [_enhance("self", 0.03)]},
]
```
→
```yaml
conditional:
  - when: {unit_count_gte: 8}
    effects:
      - enhance: {target: self, atk_pct: 0.03}
```

```gdscript
"post_threshold_effects": [_spawn("all_allies", 1), _shield("all_allies", 0.10)]
```
→
```yaml
post_threshold:
  - spawn: {target: all_allies}
  - shield: {target: all_allies, hp_pct: 0.10}
```

---

## 6. theme_system 카드 변환 규칙

### 소스
- card_db.gd에서 메타데이터(tier, timing, comp, tags, listen, max_act) 추출
- {theme}_system.gd의 match 분기에서 per-star 파라미터 추출

### impl 필드
- theme_system이 소비하는 카드 (effects=[] 또는 DSL effects 포함) → `impl: theme_system`

### effects 추출 방법
1. theme_system.gd에서 해당 card_id의 match 분기를 찾는다
2. star_level별 분기 (if/match)에서 수치를 추출한다
3. 해당 수치를 테마 DSL effect 타입으로 매핑한다

### 예시: druid_system.gd → YAML

```gdscript
# druid_system.gd
"dr_cradle":
    match star_level:
        1: _add_trees(card, 1); _add_trees_to_adjacent(card, "right", 1)
        2: _add_trees(card, 2); _add_trees_to_adjacent(card, "both", 1)
        3: _add_trees(card, 3); _add_trees_to_adjacent(card, "both", 2)
```
→
```yaml
stars:
  1:
    max_act: -1    # card_db.gd에서
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
```

### theme_system ★2/★3 수치가 ★1과 동일한 경우
- star_overrides가 있어도 effects가 동일 → 그래도 완전 명시.
- star_overrides가 없고 theme_system에서도 star 분기 없음 → ★1과 동일한 effects를 복사.

---

## 7. YAML 포맷 규칙

### 들여쓰기
- 2 spaces (YAML 표준).

### Flow vs Block style
- **comp**: flow style `{unit: X, n: N}` (한 줄)
- **tags**: flow style `[tag1, tag2]`
- **listen**: flow style `{l1: UA, l2: MF}`
- **단순 effects**: flow style `spawn: {target: self, count: 2, ol2: MF}`
- **복잡 effects** (파라미터 4개+): block style
- **conditional**: block style (중첩 있으므로)
- **stars.N이 max_act과 effects:[] 뿐일 때**: flow style `1: {max_act: -1, effects: []}`

### 카드 순서
- card_db.gd의 _register_{theme}() 내 등록 순서를 따른다.

### 파일 구조
```yaml
# data/cards/{theme}.yaml
# Source of truth for {Theme} cards.
# Generated YAML — edit here, run codegen to update card_db.gd.

cards:
  {first_card_id}:
    ...
  {second_card_id}:
    ...
```

---

## 8. 검증 체크리스트

YAML 생성 후 서브에이전트가 자가 검증:

- [ ] 카드 수가 card_db.gd의 해당 테마 카드 수와 일치
- [ ] 모든 card_id가 card_db.gd와 정확히 일치 (오타 없음)
- [ ] ★1/★2/★3 모두 존재 (생략 없음)
- [ ] OE 카드에 listen 필드가 있고, 비-OE 카드에는 없음
- [ ] effects 개수가 코드의 effects 배열 길이와 일치 (card_db 카드)
- [ ] ol1/ol2 기본값 규칙 준수 (불필요한 명시 없음, 필요한 명시 누락 없음)
- [ ] theme_system 카드의 effects가 theme_system.gd match 분기와 일치
- [ ] timing이 ★별로 변경되는 카드에 star-level timing 명시
