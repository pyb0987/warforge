# Task 4 — Stage 3 max_activation_override 를 v2에 재적용

**선행**: p2-task1-main-merge.md 완료 (main이 v2 기반)
**상태**: 대기
**난이도**: 중 (CardInstance 필드 추가 + sim 2파일 + can_activate/can_activate_with 일원화)
**작성일**: 2026-04-20

## 배경

main의 `58aaf2a` Stage 3가 backlog #2 "sim 이중 쓰기"를 **깔끔하게 해결**. v2에서는 제가 d18d1ce 단계에서 임시로 "template + block 양쪽 쓰기"로 대충 동기화했는데, 이건 여전히 template mutation이고 부작용 큼:
- genome이 -1 리턴하는 라운드에 stale cap 묻어가는 잠복 버그
- template identity 오염

Stage 3의 해결책: **per-instance override 필드 + override 우선 accessor**.

## 목표

1. `CardInstance` 에 `max_activation_override: int = -1` 필드 추가
2. `get_max_activations()` 메서드 — override 있으면 우선, 없으면 `template["max_activations"]`
3. `can_activate(bonus)` 가 `get_max_activations()` 경유하도록
4. `can_activate_with(max_act, bonus)` — v2가 chain_engine에서 block의 `max_activations` 를 명시 전달하는 경로. Stage 3에서는 이 경로가 없음 (v1 기반). v2 에서 어떻게 통합할지 결정 필요 (아래 "v1↔v2 해석 차이" 참조).
5. `sim/headless_runner.gd` + `sim/diagnostic_game.gd` — genome cap을 `max_activation_override` 에 할당. template mutation 제거.
6. 보스 `activation_bonus` — `chain_engine.activation_bonus` 경로로 일원화 (template mutation 제거).
7. Phase 2의 flat hoist 이중 쓰기 코드 완전 삭제.

## v1↔v2 해석 차이 (주의)

Stage 3는 v1 base에서 작업 → `template["max_activations"]` 가 카드 top-level의 단일 값. v2 에서는:
- top-level `max_activations` = flat hoist (첫 block에서 복사)
- **실제 값**은 각 block의 `max_activations` 에 존재

chain_engine의 v2 phase 루프들은 **block 에서 직접 읽음**:
```gdscript
var max_act: int = block.get("max_activations", -1)
if not card.can_activate_with(max_act, activation_bonus):
    continue
```

이러면 `max_activation_override` 가 block의 값을 **오버라이드 해야 의미**. 두 가지 옵션:

### Option A) `can_activate_with` 가 override를 참조
```gdscript
func can_activate_with(max_act: int, bonus: int = 0) -> bool:
    var effective := max_activation_override if max_activation_override >= 0 else max_act
    if effective == -1:
        return true
    return activations_used < effective + bonus
```

Pros: chain_engine 코드 변경 없음. override 가 block의 값을 가로챔.
Cons: 의미가 복잡 (argument 보다 override 우선).

### Option B) chain_engine이 `get_max_activations()` 호출로 변경
```gdscript
var max_act: int = card.get_max_activations()  # override 우선, 없으면 top-level hoist
if not card.can_activate(activation_bonus):
    continue
```

`get_max_activations` 는 override 우선 → top-level hoist (첫 block만 반영).
Pros: sim 과 runtime 일관.
Cons: multi-block 카드에서 hoist 는 첫 block 만. block.max_activations 읽지 않음 → 이상하게 느껴짐. 하지만 현재 multi-block 카드(sp_warmachine)는 모든 block의 max_activations가 -1이라 실용적 영향 없음.

**권고: Option A** — 코드 변경 최소화 + v2 block 의미 유지 (block이 max_activations를 정의하면 그게 기본, override는 sim 예외 경로).

## 작업 세부

### 1) `godot/core/card_instance.gd`

필드 추가 (line ~24 근처 `threshold_fired` 아래):
```gdscript
## Per-instance max_activations override (sim genome cap).
## -1 = no override; uses template or block value from chain_engine.
var max_activation_override: int = -1
```

`can_activate_with` 수정 (Option A):
```gdscript
func can_activate_with(max_act: int, bonus: int = 0) -> bool:
    # override (sim genome cap) wins over block's own max_activations
    var effective := max_activation_override if max_activation_override >= 0 else max_act
    if effective == -1:
        return true
    return activations_used < effective + bonus
```

`can_activate(bonus)` 도 일관되게 hoist 경유 유지:
```gdscript
func can_activate(bonus: int = 0) -> bool:
    var max_act := get_max_activations()
    if max_act == -1:
        return true
    return activations_used < max_act + bonus


func get_max_activations() -> int:
    if max_activation_override >= 0:
        return max_activation_override
    return template.get("max_activations", -1)
```

### 2) `godot/sim/headless_runner.gd`

현재 v2 버전의 d18d1ce에서 추가한 이중 쓰기 블록 전체 제거:
```gdscript
# BEFORE (내 d18d1ce):
var cap: int = _genome.get_activation_cap(c.get_base_id())
if cap >= 0:
    c.template["max_activations"] = cap
    for block in c.template.get("effects", []):
        block["max_activations"] = cap
```

Stage 3 방식으로 교체 (unconditional 할당이 stale cap 방지):
```gdscript
c.max_activation_override = _genome.get_activation_cap(c.get_base_id())
# -1 = clear (genome이 override 해제 시 자동 fallback)
```

보스 activation_bonus (chain_engine.activation_bonus 경로):
```gdscript
# BEFORE:
var act_bonus: int = BossReward.get_activation_bonus(state)
if act_bonus > 0:
    for card in state.get_active_board():
        var c: CardInstance = card as CardInstance
        var base_max: int = c.template.get("max_activations", -1)
        if base_max > 0:
            c.template["max_activations"] = base_max + act_bonus
            for block in c.template.get("effects", []):
                if block.get("max_activations", -1) == base_max:
                    block["max_activations"] = base_max + act_bonus

# AFTER (Stage 3 방식):
chain_engine.activation_bonus = BossReward.get_activation_bonus(state)
```

game_manager.gd:632 가 동일 패턴 — 일관성 확보.

### 3) `godot/sim/diagnostic_game.gd`

headless_runner 와 동일 패턴 교체. 두 곳 동일 로직이므로 한 번에.

### 4) 검증

```bash
python3 scripts/codegen_card_db.py --check
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=0 -gexit
# Expected: 907/907 pass
```

sim 로직 테스트 (선택):
```bash
# headless_runner 가 실제로 max_activation_override 사용하는지 sim 실행
godot --headless --path godot/ --script sim/headless_runner.gd ... 
# (정확한 명령은 기존 sim 실행 스크립트 참조)
```

## 검증 기준 (Sprint Contract Done)

- [ ] `card_instance.gd` 에 `max_activation_override` 필드 + `get_max_activations()` 메서드
- [ ] `can_activate` / `can_activate_with` 모두 override 우선
- [ ] `headless_runner.gd` 에 `template["max_activations"] = cap` 쓰기 0건
- [ ] `diagnostic_game.gd` 에 동일
- [ ] 보스 activation_bonus 경로 = `chain_engine.activation_bonus` (game_manager.gd:632와 동일)
- [ ] `grep -rn 'template\\["max_activations"\\]\\s*=' godot/` 결과 0건
- [ ] GUT 907/907 pass
- [ ] `docs/design/backlog.md` 항목 #2 상태 "해결" 로 업데이트

## 참고

- `58aaf2a` 전체 diff
- game_manager.gd:632 (보스 activation_bonus 참조 경로)
- d18d1ce 이 Phase 2에서 임시로 넣은 이중 쓰기 — 삭제 대상
