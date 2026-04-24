# 고유효과 (Unique Effect) 시스템 구현 계획

> 작성: 2026-04-23. 다른 세션이 이 문서를 읽고 단독 실행 가능한 플랜.
> 선행 맥락 없음 가정.

## 1. 배경 / 문제

현재 벤치 카드는 효과가 발동하지 않지만 **보드에 같은 카드가 여러 장 있을 경우 전부 발동**한다.
일부 카드(ml_factory 등)는 여러 장 스택하면 효과가 n배로 곱해져 밸런스가 무너진다.
플레이테스트에서 ml_factory ×3 보드가 재현됨 (2026-04-23 세션 분석).

**해결 방향**: 같은 base_id의 카드가 보드에 여러 장이면, **최좌측 1장만 효과 발동**.
나머지는 보드 슬롯을 차지하되 dormant (유닛은 소환되지만 효과는 skip).

이 메커니즘은 카드 단위 opt-in (`unique_effect: true` YAML 플래그). 보편 적용 아님.

## 2. 범위 / Non-goals

**포함**:
- YAML 스키마에 `unique_effect` 필드 추가
- codegen이 `card_db.gd`에 해당 필드 반영
- chain_engine 및 각 theme_system의 trigger dispatch 지점에서 suppression 체크
- GUT 테스트 추가
- keyword_glossary.gd에 "고유효과" 정의 등록

**제외** (별도 작업):
- 어떤 카드에 `unique_effect: true`를 붙일지 (설계 판단 별도 세션)
- UI 시각 표시 (dormant 상태 표시 — 별도 세션)
- 유닛 소환 자체를 suppress (이건 정체성 달라짐. 현재 안은 유닛 soulcon 유지, effects만 skip)

## 3. 코드베이스 현황 파악 (이 세션 시작 시 먼저 읽어볼 것)

### 3.1 Trigger 발화 지점

**`godot/core/chain_engine.gd`** — 중앙 dispatch.
보드 각 카드를 순회하며 theme_system에 위임하는 for-loop 다수 존재.
`grep -n "for.*board" godot/core/chain_engine.gd` 로 확인 (~10-15개).

주요 trigger 종류와 루프 위치 (2026-04-23 기준 근사값):
- `TriggerTiming.RS` (round start)
- `TriggerTiming.BS` (battle start)
- `TriggerTiming.OE` (on event — listen block 포함)
- `TriggerTiming.PC` (post combat)
- `TriggerTiming.PERSISTENT`
- `TriggerTiming.ON_SELL`
- `TriggerTiming.ON_REROLL`

각 trigger마다 보드 순회 함수 별도 존재 (예: `process_reroll_triggers`, `process_on_sell` 등).

### 3.2 Theme systems

**`godot/core/military_system.gd`**, `steampunk_system.gd`, `druid_system.gd`, `predator_system.gd`.
`apply_battle_start`, `apply_post_combat`, `apply_rs` 등 외부에서 호출되는 hook 존재.
이들은 chain_engine의 루프 내부에서 호출됨.

### 3.3 CardInstance 관련

**`godot/core/card_instance.gd`**: `get_base_id()`가 카드 종류 식별자 반환.

### 3.4 YAML → card_db 변환

**`scripts/codegen_card_db.py`**: YAML을 읽어 `godot/core/data/card_db.gd` 생성.
card 레벨 필드 (name, tier, theme, tags 등)를 dict로 출력. 새 필드 추가 시 이 파이프라인에 통과시킴.

`card_db.gd`는 codegen protect 대상 (직접 편집 금지, CLAUDE.md 참조).

## 4. 구현 단계

### Step 1: YAML 스키마 + codegen 지원

**파일 수정**:
- `data/cards/<theme>.yaml`: 카드 top-level에 `unique_effect: true` 플래그 추가 가능 (default false)
- `scripts/codegen_card_db.py`: `unique_effect` 필드를 card template dict에 포함해 `card_db.gd` 생성

**검증**:
- codegen 실행 후 `godot/core/data/card_db.gd` grep으로 `unique_effect` 필드 확인
- 아직 어떤 카드에도 `true`로 설정하지 않음 (이 단계는 스키마만)

### Step 2: Suppression 헬퍼 구현

**새 파일 또는 chain_engine.gd 내 static 함수**:

```gdscript
## 고유효과 규칙: 같은 base_id의 카드가 보드에 여러 장이면
## 최좌측 1장만 효과 발동. 나머지는 suppression 대상.
##
## card.template["unique_effect"] == true 인 카드만 체크.
## board 배열은 null 슬롯이 있을 수 있음 (slot-based).
static func is_unique_suppressed(card: CardInstance, board: Array, current_idx: int) -> bool:
    if card == null or card.template == null:
        return false
    if not card.template.get("unique_effect", false):
        return false
    var base_id: String = card.get_base_id()
    for j in range(current_idx):
        var other: CardInstance = board[j] as CardInstance
        if other == null:
            continue
        if other.get_base_id() == base_id:
            return true  # 좌측에 이미 같은 카드가 있음 → suppress
    return false
```

**위치 제안**: `godot/core/chain_engine.gd` 상단 static 함수로 추가.
이유: 다른 theme_system에서도 `ChainEngine.is_unique_suppressed(...)` 호출 가능.

**단위 테스트** (신규):
- `godot/tests/test_unique_effect.gd`
  - 플래그 false 카드는 suppress 안 됨
  - 플래그 true 카드 1장 → suppress 안 됨
  - 같은 id 2장 → 좌측 skip-false, 우측 suppress
  - 같은 id 3장 → 좌측 1장만 활성
  - null 슬롯 사이에 있어도 정상 동작
  - 다른 base_id는 서로 영향 없음

### Step 3: Dispatch 지점에 필터 삽입

**chain_engine.gd 내 모든 trigger dispatch 루프**에 다음 패턴 삽입:

```gdscript
for i in board.size():
    var card: CardInstance = board[i]
    if card == null:
        continue
    # 고유효과 suppression
    if is_unique_suppressed(card, board, i):
        continue
    # ... 기존 로직
```

**확인 대상 루프 목록** (2026-04-23 기준):
- `process_round_start` (RS)
- `process_on_event` (OE, 여러 listen 타입)
- `process_battle_start` (BS)
- `process_post_combat` (PC)
- `process_persistent` (PERSISTENT)
- `process_sell_triggers` (ON_SELL)
- `process_reroll_triggers` (ON_REROLL)

각 함수에 grep으로 찾아 동일 필터 삽입. 주의: listen-기반 OE는 `_find_block` 호출 전/후 어디에 넣을지 판단 필요 (권장: template 체크 전에 early return).

**theme_system 쪽 훅**이 chain_engine 밖에서 불리는 경우 (예: combat_engine에서 `apply_battle_start` 직접 호출)는 해당 호출부에도 필터 추가 필요. 검색으로 확인:
```
grep -rn "apply_battle_start\|apply_post_combat\|apply_rs\|on_sell_trigger" godot/
```

**주의**: suppression은 **카드 자체 효과만** 차단. 다른 카드가 이 카드를 target으로 하는 event (예: ml_factory가 다른 카드의 trained_this_round를 수집)는 target이 dormant이어도 정상 처리됨. 즉 "자신의 trigger"만 skip.

### Step 4: 회귀 테스트

- `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit`
- 기존 906/906 통과 유지 확인 (어떤 카드에도 unique_effect: true가 아직 없으므로 행동 불변)
- Step 2의 `test_unique_effect.gd` 신규 테스트 통과

### Step 5: keyword_glossary 등록

`godot/core/data/keyword_glossary.gd`에 "고유효과" 엔트리 추가:
```gdscript
"고유효과": {
    "definition": "같은 카드가 보드에 여러 장이면 가장 왼쪽 1장만 효과 발동. 나머지는 유닛은 소환되나 효과 차단.",
    "theme": "범용",
},
```

### Step 6: 단일 카드에 적용 검증 (smoke test)

**임시로** `ml_factory`에 `unique_effect: true` 설정 → codegen → GUT 전체 → 효과 확인.
(이 단계의 적용 여부는 별도 설계 세션에서 결정. 본 플랜은 인프라만 구축.)

## 5. 리스크 / 주의사항

### 5.1 Dormant 카드의 rank 축적

Factory처럼 self-train이 있는 카드의 경우, dormant 상태에서 rank가 쌓이지 말아야 함.
현재 설계: "자신의 trigger skip" = self-train도 자동 skip → 문제 없음.

### 5.2 Merge 와 상호작용

Merge는 별도 시스템 (game_state.try_merge). 3장 중 1장만 활성이라도 merge는 trigger 가능해야 함 — merge는 trigger path 밖에서 동작하므로 영향 없음. **테스트로 확인**.

### 5.3 AI 시뮬 영향

`godot/sim/ai_agent.gd`가 unique_effect 고려하지 않으면 같은 카드를 반복 구매할 수 있음.
구현 시점에는 AI 수정 불필요 (AI가 학습적으로 비효율 선택을 하는 건 허용). 다만 평가 점수에 영향 가능 — **autoresearch 실행 전 baseline 재계산 권장**.

### 5.4 "고유효과 대상 카드 선정"은 본 플랜 밖

본 플랜은 **인프라 구축**만 담당. 어떤 카드에 플래그를 붙일지는 별도 설계 결정.
후보 카드(관찰 기반):
- ml_factory (확인됨 — 3 스택 OP)
- ml_assault (라이프스틸 스택 가능성)
- ml_command (전 군대 훈련 스택 가능성)
- sp_charger (counter_produce 스택)
- pr_queen (swarm 생성 스택)
- 기타 "같은 종류 여러 장이 비정상적으로 강해지는" 카드 전반

## 6. 완료 기준 (Sprint Contract)

```
Done when:
- YAML 스키마 `unique_effect: bool` 지원
- codegen이 해당 필드를 card_db.gd에 반영
- chain_engine.is_unique_suppressed() 헬퍼 구현 + 단위 테스트 통과
- 모든 trigger dispatch 지점에 필터 삽입 (RS/BS/OE/PC/PERSISTENT/ON_SELL/ON_REROLL)
- theme_system 직접 호출 지점도 필터 적용
- keyword_glossary에 "고유효과" 등록
- GUT 전체 906+ 테스트 통과
- 신규 test_unique_effect.gd 통과 (최소 6 케이스)

Evaluator: Tier 2 (haiku) + 체크리스트:
- 각 trigger timing별 suppression 체크 삽입됨
- unique_effect: false 기본값에서 기존 카드 행동 불변
- null 슬롯에서 crash 없음
```

## 7. 예상 작업 시간

- Step 1 (schema + codegen): 30분
- Step 2 (헬퍼 + 단위 테스트): 45분
- Step 3 (dispatch 삽입): 1-1.5시간 (루프 ~10-15곳 + theme hook 호출부)
- Step 4 (회귀 테스트): 30분
- Step 5 (keyword_glossary): 5분
- Step 6 (smoke test): 20분

**총 3-4시간**. 중간 복잡도. 한 세션에 완료 가능.

## 8. Context rot 방지 / Handoff 노트

이 작업은 grep + 여러 파일 수정이 많다. 컨텍스트 효율을 위해:
- **Explore sub-agent로 trigger dispatch 루프 전수 조사 먼저** (chain_engine + theme systems)
- 결과를 받아 메인에서 순차 수정
- 각 Step 끝에 GUT 회귀 실행 (교란 변수 격리)

작업 완료 시 evolution trace 기록: `.claude/traces/evolution/NNN-unique-effect-system.md`
