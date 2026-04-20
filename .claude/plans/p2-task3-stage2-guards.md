# Task 3 — Stage 2 guards 를 v2 chain_engine에 재적용

**선행**: p2-task1-main-merge.md 완료 (main이 v2 기반)
**상태**: 대기
**난이도**: 하-중 (chain_engine 1곳 + theme_system 기본 클래스 push_error)
**작성일**: 2026-04-20

## 배경

main의 `0c55b9d` Stage 2가 해결한 항목:
- backlog #8: POST_COMBAT phase에 `conditional_effects` 순회 추가 (RS/OE/BS와 대칭)
- backlog #6: `theme_system` 기본 클래스의 hook들에 `push_error` 가드 추가 (steampunk의 BS/PC 오버라이드 부재 감지)

이 Task가 **v2 코드에 재적용**.

## v2 현황 조사 필요

### PC conditional_effects 순회 여부
`godot/core/chain_engine.gd` 의 `process_post_combat` 함수에서 conditional_effects 순회 있는지 확인. v2 rewrite(f9eb4d0) 시점에 RS/OE/BS 에는 넣었지만 PC 놓쳤을 가능성.

```bash
grep -n "process_post_combat\|conditional_effects" godot/core/chain_engine.gd | head
```

- 있다면: 이 항목 skip.
- 없다면: RS phase의 순회 패턴 복사해서 PC에도 적용.

### theme_system base class push_error
`godot/core/theme_system.gd` 의 hook (process_rs_card, process_event_card, apply_battle_start, apply_post_combat)이 현재 조용한 no-op인지, 이미 push_error 로깅 있는지 확인.

```bash
cat godot/core/theme_system.gd
```

- 조용한 no-op: Stage 2 패턴대로 push_error 추가.
- 이미 있음: skip.

## 목표

1. `chain_engine.process_post_combat` — RS/OE/BS 와 동일하게 conditional_effects 순회
2. `theme_system.gd` base class — 4개 hook (process_rs_card / process_event_card / apply_battle_start / apply_post_combat) 에 `push_error`로 missing override 경고. `apply_persistent` 는 quiet 유지 (Stage 2 rationale 참조)

## 작업 세부

### 1) chain_engine.process_post_combat — conditional_effects 순회

**기존 (v2)**:
```gdscript
func process_post_combat(board: Array, won: bool) -> Dictionary:
    ...
    for i in board.size():
        var card: CardInstance = board[i]
        var tmpl := card.template
        var block: Dictionary = {}
        var timing: int = -1
        for t in pc_timings:
            var b := _find_block(tmpl, t)
            if not b.is_empty():
                block = b; timing = t; break
        if block.is_empty():
            continue
        ...
        # 여기에 conditional_effects 순회가 누락됐을 가능성
        ...
```

**추가**:
RS phase (chain_engine.gd:144-150) 와 같은 패턴을 PC 결과 다음에 삽입.

### 2) theme_system base class push_error

**Stage 2 패턴** (0c55b9d 참조):
```gdscript
func process_rs_card(card: CardInstance, _idx: int, _board: Array,
        _rng: RandomNumberGenerator) -> Dictionary:
    _warn_missing_override(card, "process_rs_card")
    return {"events": [], "gold": 0, "terazin": 0}


func process_event_card(card: CardInstance, _idx: int, _board: Array,
        _event: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
    _warn_missing_override(card, "process_event_card")
    return {"events": [], "gold": 0, "terazin": 0}


func apply_persistent(_card: CardInstance) -> void:
    # Quiet no-op: chain_engine.process_persistent iterates ALL board cards
    # and dispatches any PERSISTENT-timed one through its theme_system, even
    # card_db impl cards. See 0c55b9d commit message for rationale.
    pass


func apply_battle_start(card: CardInstance, _idx: int, _board: Array) -> Dictionary:
    _warn_missing_override(card, "apply_battle_start")
    return {"events": [], "gold": 0, "terazin": 0}


func apply_post_combat(card: CardInstance, _idx: int, _board: Array,
        _won: bool) -> Dictionary:
    _warn_missing_override(card, "apply_post_combat")
    return {"events": [], "gold": 0, "terazin": 0}


func _warn_missing_override(card: CardInstance, hook: String) -> void:
    # Fires when a theme_system-dispatched card hits the base no-op, meaning
    # the derived theme class did not override the hook for this card_id.
    # Only card_db-impl cards hit the base class legitimately (via
    # effects.is_empty() card_db fallback), so we filter.
    if card.template.get("impl", "card_db") == "theme_system":
        push_error("%s: theme_system missing override for %s (card_id=%s)" % [
            get_script().get_path().get_file(), hook, card.get_base_id()])
```

**Protocol 주석** 추가 (파일 상단):
```
## Protocol contract:
##   Any ``impl: theme_system`` card with timing T routes through the
##   corresponding derived class's hook. If the derived class does not
##   override the hook, the base-class push_error below flags at runtime.
##   Current gap: steampunk_system overrides process_rs_card(sp_warmachine
##   only) + process_event_card + apply_persistent + on_sell_trigger.
##   Any future sp_* card with BATTLE_START / POST_COMBAT timing and
##   ``impl: theme_system`` must add a matching override in
##   steampunk_system.gd.
```

### 3) 검증 — 현 55장 중 steampunk의 BS/PC theme_system 카드 없는지 확인
Stage 2의 가드가 **false positive를 안 일으키려면** 현 상태에서 push_error 발생 0건이어야.

```bash
grep -n "apply_battle_start\|apply_post_combat" godot/core/steampunk_system.gd
```

Steampunk 현 구현:
- `process_event_card`: sp_charger만
- `apply_persistent`: sp_warmachine만
- `on_sell_trigger`: sp_arsenal만
- `process_rs_card`: sp_warmachine(manufacture, Phase 2 C5에서 추가)
- `apply_battle_start` / `apply_post_combat`: **없음**

steampunk의 BS/PC impl: theme_system 카드가 실제로 없는지 YAML 확인:
```bash
grep -B2 "trigger_timing: BS\|trigger_timing: PC" data/cards/steampunk.yaml | head
```

없다면 push_error false positive 0. 있다면 Stage 2의 문제 식별 대상.

## 검증 기준 (Sprint Contract Done)

- [ ] `chain_engine.gd:process_post_combat` 가 RS/OE/BS 와 동일한 conditional_effects 순회 패턴 보유
- [ ] `theme_system.gd` base class 4개 hook에 `push_error` (apply_persistent 제외)
- [ ] Protocol 주석 파일 상단 추가
- [ ] GUT 907/907 pass, push_error 메시지 0건 발생
- [ ] 현 55장 YAML 에 PC+conditional 조합 없음 확인 (test — `grep -B2 "conditional" data/cards/*.yaml | grep "PC"`)
- [ ] `docs/design/backlog.md` 에서 항목 #6, #8 상태 업데이트 ("해결")

## 참고

- `0c55b9d` 전체 diff: `git show 0c55b9d`
- v2 chain_engine의 RS phase conditional 순회 패턴: `chain_engine.gd` line 143~150 근처
